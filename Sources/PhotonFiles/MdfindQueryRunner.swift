import Foundation

/// Runs one `/usr/bin/mdfind` snapshot and returns the paths it printed.
/// Start and cancel from the file-search engine; the process is stopped as
/// soon as a newer query lands.
final class MdfindQueryRunner: @unchecked Sendable {
  struct Request: Sendable {
    let queryString: String?
    let fileName: String?
    let onlyIn: [String]
    let scanLimit: Int

    init(queryString: String, onlyIn: [String], scanLimit: Int) {
      self.queryString = queryString
      fileName = nil
      self.onlyIn = onlyIn
      self.scanLimit = scanLimit
    }

    init(fileName: String, onlyIn: [String], scanLimit: Int) {
      queryString = nil
      self.fileName = fileName
      self.onlyIn = onlyIn
      self.scanLimit = scanLimit
    }
  }

  struct Outcome: Sendable {
    var paths: [String] = []
    var spotlightAvailable = true
    var cancelled = false
  }

  private let lock = NSLock()
  private var process: Process?
  private var completion: (@Sendable (Outcome) -> Void)?
  private var timedOut = false

  func start(_ request: Request, completion: @escaping @Sendable (Outcome) -> Void) {
    lock.lock()
    self.completion = completion
    timedOut = false
    lock.unlock()

    let process = Process()
    process.executableURL = URL(fileURLWithPath: MdfindInvocation.executable)
    process.arguments = MdfindInvocation.arguments(
      queryString: request.queryString,
      fileName: request.fileName,
      onlyIn: request.onlyIn
    )
    process.standardOutput = Pipe()
    process.standardError = Pipe()
    process.qualityOfService = .userInitiated

    lock.lock()
    self.process = process
    lock.unlock()

    process.terminationHandler = { [weak self] finished in
      let data: Data = if let pipe = finished.standardOutput as? Pipe {
        (try? pipe.fileHandleForReading.readToEnd()) ?? Data()
      } else {
        Data()
      }
      self?.processFinished(finished, data: data, scanLimit: request.scanLimit)
    }

    do {
      try process.run()
    } catch {
      finish(Outcome(spotlightAvailable: false))
    }
  }

  func cancel() {
    lock.lock()
    let process = process
    lock.unlock()
    process?.terminate()
    finish(Outcome(cancelled: true))
  }

  /// Stops a hung `mdfind` and keeps whatever paths it already printed.
  func expire() {
    lock.lock()
    timedOut = true
    let process = process
    lock.unlock()
    process?.terminate()
  }

  private func processFinished(_ process: Process, data: Data, scanLimit: Int) {
    lock.lock()
    let stillCurrent = self.process === process
    let didTimeOut = timedOut
    lock.unlock()
    guard stillCurrent else {
      return
    }

    if process.terminationReason == .uncaughtSignal, !didTimeOut {
      finish(Outcome(cancelled: true))
      return
    }
    let available = didTimeOut || process.terminationStatus == 0
    let paths = MdfindInvocation.paths(fromNullTerminated: data, limit: scanLimit)
    finish(Outcome(paths: paths, spotlightAvailable: available))
  }

  private func finish(_ outcome: Outcome) {
    lock.lock()
    let completion = completion
    let process = process
    self.completion = nil
    self.process = nil
    lock.unlock()

    guard let completion else {
      return
    }
    if let process, process.isRunning {
      process.terminate()
    }
    completion(outcome)
  }
}

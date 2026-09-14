import Foundation

/// Coalesces rapid calls into one delayed action on the main actor.
///
/// The scheduler is injectable so the delay logic can be unit tested without a run loop.
@MainActor
public final class Debouncer {
  public typealias Action = @MainActor @Sendable () -> Void
  /// Runs `fire` after `delay` seconds and returns a handle that cancels the run.
  public typealias Scheduler = @MainActor (_ delay: TimeInterval, _ fire: @escaping Action) -> () -> Void

  public let delay: TimeInterval
  private let scheduler: Scheduler
  private var pending: Action?
  private var cancelScheduled: (() -> Void)?

  public init(delay: TimeInterval, scheduler: Scheduler? = nil) {
    self.delay = delay
    self.scheduler = scheduler ?? Debouncer.dispatchScheduler
  }

  public var isPending: Bool {
    pending != nil
  }

  /// Replaces any pending action and restarts the delay.
  public func schedule(_ action: @escaping Action) {
    cancelScheduled?()
    pending = action
    cancelScheduled = scheduler(delay) { [weak self] in
      self?.flush()
    }
  }

  /// Runs the pending action immediately, if there is one.
  public func flush() {
    cancelScheduled?()
    cancelScheduled = nil
    guard let action = pending else {
      return
    }
    pending = nil
    action()
  }

  /// Drops the pending action without running it.
  public func cancel() {
    cancelScheduled?()
    cancelScheduled = nil
    pending = nil
  }

  static let dispatchScheduler: Scheduler = { delay, fire in
    let item = DispatchWorkItem {
      MainActor.assumeIsolated {
        fire()
      }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    return {
      item.cancel()
    }
  }
}

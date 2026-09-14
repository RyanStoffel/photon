import Foundation
import PhotonNotes
import XCTest

@MainActor
final class DebouncerTests: XCTestCase {
  /// Captures scheduled work so tests control when the delay elapses.
  @MainActor
  private final class ManualScheduler {
    var scheduled: [(delay: TimeInterval, fire: Debouncer.Action)] = []
    var cancelled = 0

    func schedule(_ delay: TimeInterval, _ fire: @escaping Debouncer.Action) -> () -> Void {
      scheduled.append((delay, fire))
      return { [weak self] in
        self?.cancelled += 1
      }
    }

    func elapse() {
      let pending = scheduled
      scheduled.removeAll()
      for item in pending {
        item.fire()
      }
    }
  }

  private func makeDebouncer(delay: TimeInterval = 0.5) -> (Debouncer, ManualScheduler) {
    let scheduler = ManualScheduler()
    let debouncer = Debouncer(delay: delay) { delay, fire in
      scheduler.schedule(delay, fire)
    }
    return (debouncer, scheduler)
  }

  func testRapidCallsRunOnceAfterDelay() {
    let (debouncer, scheduler) = makeDebouncer()
    var runs = 0
    for _ in 0 ..< 5 {
      debouncer.schedule { runs += 1 }
    }
    XCTAssertEqual(runs, 0)
    XCTAssertTrue(debouncer.isPending)
    XCTAssertEqual(scheduler.cancelled, 4)
    XCTAssertEqual(scheduler.scheduled.last?.delay, 0.5)
    scheduler.elapse()
    XCTAssertEqual(runs, 1)
    XCTAssertFalse(debouncer.isPending)
  }

  func testLatestActionWins() {
    let (debouncer, scheduler) = makeDebouncer()
    var saved = ""
    debouncer.schedule { saved = "first" }
    debouncer.schedule { saved = "second" }
    scheduler.elapse()
    XCTAssertEqual(saved, "second")
  }

  func testFlushRunsImmediatelyAndCancelsTimer() {
    let (debouncer, scheduler) = makeDebouncer()
    var runs = 0
    debouncer.schedule { runs += 1 }
    debouncer.flush()
    XCTAssertEqual(runs, 1)
    XCTAssertEqual(scheduler.cancelled, 1)
    scheduler.elapse()
    XCTAssertEqual(runs, 1, "a flushed action must not run again when the timer fires")
    debouncer.flush()
    XCTAssertEqual(runs, 1, "flush with nothing pending is a no-op")
  }

  func testCancelDropsPendingAction() {
    let (debouncer, scheduler) = makeDebouncer()
    var runs = 0
    debouncer.schedule { runs += 1 }
    debouncer.cancel()
    XCTAssertFalse(debouncer.isPending)
    scheduler.elapse()
    XCTAssertEqual(runs, 0)
  }

  func testDefaultSchedulerFiresOnMainQueue() async throws {
    let debouncer = Debouncer(delay: 0.01)
    var fired = false
    debouncer.schedule {
      fired = true
    }
    for _ in 0 ..< 100 where !fired {
      try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTAssertTrue(fired)
    XCTAssertFalse(debouncer.isPending)
  }
}

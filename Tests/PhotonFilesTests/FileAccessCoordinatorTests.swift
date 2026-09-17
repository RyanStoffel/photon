import AppKit
import Foundation
import PhotonFiles
import XCTest

@MainActor
final class FileAccessCoordinatorTests: XCTestCase {
  func testSelectedFolderPersistsAndRestoresAcrossCoordinatorRelaunch() throws {
    let suite = "photon-file-access-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }

    let coordinator = FileAccessCoordinator(defaults: defaults)
    coordinator.requestAccess(using: StubFileAccessPanel(selection: .selected([folder])))

    XCTAssertEqual(coordinator.status, .granted)
    XCTAssertEqual(coordinator.folders.map { URL(fileURLWithPath: $0).lastPathComponent }, [folder.lastPathComponent])

    let relaunched = FileAccessCoordinator(defaults: defaults)
    XCTAssertEqual(relaunched.status, .granted)
    XCTAssertEqual(relaunched.folders, coordinator.folders)
  }

  func testCancelAndErrorStatesDoNotDiscardExistingGrant() throws {
    let suite = "photon-file-access-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let folder = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: folder) }
    let coordinator = FileAccessCoordinator(defaults: defaults)
    coordinator.requestAccess(using: StubFileAccessPanel(selection: .selected([folder])))

    coordinator.requestAccess(using: StubFileAccessPanel(selection: .cancelled))
    XCTAssertEqual(coordinator.status, .cancelled)
    XCTAssertEqual(coordinator.folders.count, 1)

    coordinator.requestAccess(using: StubFileAccessPanel(selection: .failed("Open panel failed")))
    XCTAssertEqual(coordinator.status, .failed("Open panel failed"))
    XCTAssertEqual(coordinator.folders.count, 1)
  }

  func testSequentialGrantsPersistEachFolderAndStopOnCancel() throws {
    let suite = "photon-file-access-\(UUID().uuidString)"
    let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let second = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let third = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: third, withIntermediateDirectories: true)
    defer {
      try? FileManager.default.removeItem(at: first)
      try? FileManager.default.removeItem(at: second)
      try? FileManager.default.removeItem(at: third)
    }

    let presenter = SequentialStubFileAccessPanel(selections: [
      .selected([first]),
      .selected([second]),
      .cancelled,
    ])
    let coordinator = FileAccessCoordinator(defaults: defaults)
    let added = coordinator.requestAccessSequentially(
      suggestedFolders: [first, second, third],
      using: presenter
    )

    XCTAssertEqual(added, 2)
    XCTAssertEqual(presenter.callCount, 3)
    XCTAssertEqual(Set(coordinator.folders.map { URL(fileURLWithPath: $0).lastPathComponent }), [
      first.lastPathComponent,
      second.lastPathComponent,
    ])
    XCTAssertEqual(coordinator.status, .cancelled)
  }
}

@MainActor
private struct StubFileAccessPanel: FileAccessPanelPresenting {
  let selection: FileAccessSelection

  func chooseFolders(parent _: NSWindow?, directory _: URL?) -> FileAccessSelection {
    selection
  }
}

@MainActor
private final class SequentialStubFileAccessPanel: FileAccessPanelPresenting {
  private let selections: [FileAccessSelection]
  private(set) var callCount = 0

  init(selections: [FileAccessSelection]) {
    self.selections = selections
  }

  func chooseFolders(parent _: NSWindow?, directory _: URL?) -> FileAccessSelection {
    let index = min(callCount, selections.count - 1)
    callCount += 1
    return selections[index]
  }
}

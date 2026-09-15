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
}

@MainActor
private struct StubFileAccessPanel: FileAccessPanelPresenting {
  let selection: FileAccessSelection

  func chooseFolders() -> FileAccessSelection {
    selection
  }
}

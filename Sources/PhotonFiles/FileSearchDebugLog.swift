import Foundation

enum FileSearchDebugLog: Sendable {
  static func log(_ message: String) {
    guard ProcessInfo.processInfo.environment["PHOTON_DEBUG_FILE_SEARCH"] == "1" else {
      return
    }
    NSLog("PhotonFiles: %@", message)
  }
}

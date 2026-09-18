import Foundation

/// `photon://note/<id>` links that open a specific note.
public enum NoteDeepLink: Sendable {
  public static let scheme = "photon"
  public static let host = "note"

  public static func url(for id: String) -> URL? {
    var components = URLComponents()
    components.scheme = scheme
    components.host = host
    components.path = "/" + id
    return components.url
  }

  public static func noteID(from url: URL) -> String? {
    guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == host else {
      return nil
    }
    let id = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    return id.isEmpty ? nil : id
  }
}

import AppKit

@main
enum PhotonStub {
  static func main() {
    let app = NSApplication.shared
    app.setActivationPolicy(.accessory)
    app.run()
  }
}

import Cocoa
import FlutterMacOS

@main
class AppDelegate: NSObject, NSApplicationDelegate {
  var window: NSWindow!
  func applicationDidFinishLaunching(_ notification: Notification) {
    let flutterViewController = FlutterViewController()
    RegisterGeneratedPlugins(registry: flutterViewController)
    window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 800), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
    window.center()
    window.title = "THAMAN POS"
    window.contentViewController = flutterViewController
    window.makeKeyAndOrderFront(nil)
  }
  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

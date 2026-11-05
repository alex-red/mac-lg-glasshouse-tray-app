import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = NSImage(systemSymbolName: "tv", accessibilityDescription: "Glasshouse Tray")
        statusItem.button?.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Quit Glasshouse Tray", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        statusItem.menu = menu
    }
}

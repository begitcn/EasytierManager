import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var navigationVM: NavigationVM!
    var mainWindowController: MainWindowController!

    @MainActor
    func applicationDidFinishLaunching(_: Notification) {
        navigationVM = NavigationVM()

        mainWindowController = MainWindowController(
            navigationVM: navigationVM
        )

        openMainWindow()
    }

    @MainActor
    func applicationDidBecomeActive(_: Notification) {
        mainWindowController.showWindow(nil)
    }

    @MainActor
    func openMainWindow() {
        NSApp.setActivationPolicy(.regular)
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

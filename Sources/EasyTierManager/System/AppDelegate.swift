import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationSupportsSecureRestorableState(_: NSApplication) -> Bool {
        true
    }
    var navigationVM: NavigationVM!
    var networkStore: NetworkStore!
    var easyTierService: EasyTierService!
    var mainWindowController: MainWindowController!
    var statusBarController: StatusBarController?

    @MainActor
    func applicationDidFinishLaunching(_: Notification) {
        navigationVM = NavigationVM()
        networkStore = NetworkStore.shared
        easyTierService = EasyTierService.shared

        mainWindowController = MainWindowController(
            navigationVM: navigationVM,
            networkStore: networkStore,
            easyTierService: easyTierService
        )

        _ = AppSettings.shared
        statusBarController = StatusBarController(mainWindowController: mainWindowController)

        openMainWindow()

        AppSettings.shared.applyActivationPolicy()

        Task {
            await EasyTierHelperManager.shared.installAndConnect()
        }
    }

    @MainActor
    func applicationDidBecomeActive(_: Notification) {
        mainWindowController.showWindow(nil)
    }

    @MainActor
    func openMainWindow() {
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
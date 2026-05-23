import Cocoa

class AppDelegate: NSObject, NSApplicationDelegate {
    var navigationVM: NavigationVM!
    var networkStore: NetworkStore!
    var easyTierService: EasyTierService!
    var mainWindowController: MainWindowController!

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

        openMainWindow()

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
        NSApp.setActivationPolicy(.regular)
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
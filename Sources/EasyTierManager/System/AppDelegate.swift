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

        setupTerminationHandlers()
        setupWakeObserver()

        Task {
            await EasyTierHelperManager.shared.installAndConnect()
            await performAutoConnect()
        }
    }

    private func setupTerminationHandlers() {
        let signalQueue = DispatchQueue.global(qos: .userInitiated)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        termSource.setEventHandler {
            Self.handleTerminationSignal()
        }
        termSource.activate()
        signal(SIGTERM, SIG_IGN)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        intSource.setEventHandler {
            Self.handleTerminationSignal()
        }
        intSource.activate()
        signal(SIGINT, SIG_IGN)
    }

    private func setupWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleSystemWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }

    @objc private func handleSystemWake(_ notification: Notification) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            await EasyTierHelperManager.shared.installAndConnect()
            await easyTierService.restartActiveNetworks()
        }
    }

    private static func handleTerminationSignal() {
        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.main.async {
            EasyTierService.shared.forceStopAll()
            EasyTierHelperManager.shared.disconnect()
            semaphore.signal()
        }
        _ = semaphore.wait(timeout: .now() + 8.0)
        exit(0)
    }

    @MainActor
    private func performAutoConnect() async {
        guard AppSettings.shared.autoConnectOnLaunch else { return }
        for network in networkStore.networks where network.isAutoConnect {
            networkStore.updateStatus(id: network.id, status: .connecting)
            do {
                try await easyTierService.startNetwork(configPath: network.configPath)
                networkStore.updateStatus(id: network.id, status: .connected)
            } catch {
                networkStore.updateStatus(id: network.id, status: .error)
            }
        }
    }

    func applicationWillTerminate(_: Notification) {
        easyTierService.forceStopAll()
        EasyTierHelperManager.shared.disconnect()
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
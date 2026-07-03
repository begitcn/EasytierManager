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
    private var signalSources: [DispatchSourceSignal] = []
    private var wakeObserver: NSObjectProtocol?
    private var sleepObserver: NSObjectProtocol?

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
        setupSleepWakeObservers()

        Task {
            await EasyTierHelperManager.shared.installAndConnect()
            await performAutoConnect()
        }
    }

    private func setupTerminationHandlers() {
        let signalQueue = DispatchQueue.global(qos: .userInitiated)

        let termSource = DispatchSource.makeSignalSource(signal: SIGTERM, queue: signalQueue)
        termSource.setEventHandler {
            Task {
                await Self.handleTerminationSignal()
            }
        }
        termSource.activate()
        signal(SIGTERM, SIG_IGN)
        signalSources.append(termSource)

        let intSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: signalQueue)
        intSource.setEventHandler {
            Task {
                await Self.handleTerminationSignal()
            }
        }
        intSource.activate()
        signal(SIGINT, SIG_IGN)
        signalSources.append(intSource)
    }

    private func setupSleepWakeObservers() {
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }

        sleepObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleSystemSleep()
        }
    }

    private func handleSystemSleep() {
        Task { @MainActor in
            await easyTierService.prepareForSleep()
        }
    }

    private func handleSystemWake() {
        Task { @MainActor in
            await easyTierService.restoreAfterWake()
        }
    }

    private static func handleTerminationSignal() async {
        await EasyTierService.shared.forceStopAllAsync()
        await EasyTierHelperManager.shared.disconnect()
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
        for source in signalSources {
            source.cancel()
        }
        signalSources.removeAll()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if let sleepObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(sleepObserver)
        }
        easyTierService.forceStopAll()
        EasyTierHelperManager.shared.disconnect()
    }

    @MainActor
    func applicationDidBecomeActive(_: Notification) {
        easyTierService.isAppActive = true
        mainWindowController.showWindow(nil)
    }

    @MainActor
    func applicationDidResignActive(_: Notification) {
        easyTierService.isAppActive = false
    }

    @MainActor
    func openMainWindow() {
        mainWindowController.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}

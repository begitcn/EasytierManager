import AppKit
import Combine

@MainActor
class StatusBarController: NSObject {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var cancellables = Set<AnyCancellable>()

    private weak var mainWindowController: MainWindowController?

    init(mainWindowController: MainWindowController) {
        self.mainWindowController = mainWindowController
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "network", accessibilityDescription: "EasyTier")
            button.action = #selector(showMenu)
            button.target = self
        }

        setupMenu()

        AppSettings.shared.$showMenuBarIcon
            .sink { [weak self] show in
                self?.statusItem.button?.isHidden = !show
            }
            .store(in: &cancellables)

        statusItem.button?.isHidden = !AppSettings.shared.showMenuBarIcon
    }

    private func setupMenu() {
        let showItem = NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func showMenu() {
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func showWindow() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

import AppKit
import SwiftUI

@MainActor
class MainWindowController: NSWindowController {
    let navigationVM: NavigationVM
    let networkStore: NetworkStore
    let easyTierService: EasyTierService

    init(
        navigationVM: NavigationVM,
        networkStore: NetworkStore,
        easyTierService: EasyTierService
    ) {
        self.navigationVM = navigationVM
        self.networkStore = networkStore
        self.easyTierService = easyTierService

        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: MainView()
                    .environmentObject(navigationVM)
                    .environmentObject(networkStore)
                    .environmentObject(easyTierService)
            )
        )

        super.init(window: window)

        window.delegate = self

        configureWindow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func configureWindow() {
        window?.standardWindowButton(NSWindow.ButtonType.zoomButton)?.isEnabled = false
        window?.standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isEnabled = false

        window?.title = " "
        window?.titleVisibility = .hidden
        window?.titlebarAppearsTransparent = true
        window?.styleMask.insert(.fullSizeContentView)
        window?.setFrame(NSRect(x: 0, y: 0, width: 860, height: 660), display: false)
        window?.center()
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}
import AppKit
import SwiftUI

/// 主窗口控制器。
/// 本应用为常驻菜单栏工具：窗口关闭时立即销毁整个 SwiftUI 视图树
/// （轮询任务、节点缓存视图随之释放），再次打开时按需重建，
/// 显著降低闲置内存占用。
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

        super.init(window: nil)

        makeWindow()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func showWindow(_ sender: Any?) {
        if window == nil {
            makeWindow()
        }
        super.showWindow(sender)
    }

    private func makeWindow() {
        let window = NSWindow(
            contentViewController: NSHostingController(
                rootView: MainView()
                    .environmentObject(navigationVM)
                    .environmentObject(networkStore)
                    .environmentObject(easyTierService)
                    .environmentObject(AppSettings.shared)
                    .environmentObject(EasyTierHelperManager.shared)
            )
        )
        window.delegate = self
        configureWindow(window)
        easyTierService.isWindowVisible = true
        self.window = window
    }

    private func configureWindow(_ window: NSWindow) {
        window.standardWindowButton(NSWindow.ButtonType.zoomButton)?.isEnabled = false
        window.standardWindowButton(NSWindow.ButtonType.miniaturizeButton)?.isEnabled = false

        window.title = " "
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.setFrame(NSRect(x: 0, y: 0, width: 860, height: 660), display: false)
        window.center()
    }
}

extension MainWindowController: NSWindowDelegate {
    func windowWillClose(_: Notification) {
        easyTierService.isWindowVisible = false
        // 释放窗口与整个 SwiftUI 视图树，重开时由 showWindow 重建
        window?.delegate = nil
        window = nil
    }
}

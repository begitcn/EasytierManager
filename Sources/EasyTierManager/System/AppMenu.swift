import Cocoa

class AppMenu: NSMenu {
    private lazy var applicationName = ProcessInfo.processInfo.processName

    override init(title: String) {
        super.init(title: title)

        let mainMenu = NSMenuItem()
        mainMenu.submenu = NSMenu(title: "MainMenu")
        let aboutItem = NSMenuItem(title: "About \(applicationName)", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        let hideItem = NSMenuItem(title: "Hide \(applicationName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        let hideOthersItem = NSMenuItem(title: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthersItem.keyEquivalentModifierMask = [.command, .option]
        let showAllItem = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        let quitItem = NSMenuItem(title: "Quit \(applicationName)", action: #selector(NSApplication.shared.terminate(_:)), keyEquivalent: "q")
        mainMenu.submenu?.items = [
            aboutItem,
            NSMenuItem.separator(),
            hideItem,
            hideOthersItem,
            showAllItem,
            NSMenuItem.separator(),
            quitItem,
        ]

        let fileMenu = NSMenuItem()
        fileMenu.submenu = NSMenu(title: "File")
        fileMenu.submenu?.items = [
            NSMenuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"),
        ]

        let editMenu = NSMenuItem()
        editMenu.submenu = NSMenu(title: "Edit")
        editMenu.submenu?.items = [
            NSMenuItem(title: "Undo", action: #selector(UndoManager.undo), keyEquivalent: "z"),
            NSMenuItem(title: "Redo", action: #selector(UndoManager.redo), keyEquivalent: "Z"),
            NSMenuItem.separator(),
            NSMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"),
            NSMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"),
            NSMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"),
            NSMenuItem.separator(),
            NSMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"),
        ]

        let windowMenu = NSMenuItem()
        windowMenu.submenu = NSMenu(title: "Window")
        windowMenu.submenu?.items = [
            NSMenuItem(title: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m"),
            NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: ""),
            NSMenuItem.separator(),
            NSMenuItem(title: "Show All", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "m"),
        ]

        let viewMenu = NSMenuItem()
        viewMenu.submenu = NSMenu(title: "View")
        viewMenu.submenu?.items = []

        let helpMenu = NSMenuItem()
        helpMenu.submenu = NSMenu(title: "Help")
        helpMenu.submenu?.items = []

        items = [mainMenu, fileMenu, editMenu, viewMenu, windowMenu, helpMenu]
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}

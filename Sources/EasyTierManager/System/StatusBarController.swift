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

        AppSettings.shared.$showMenuBarIcon
            .sink { [weak self] show in
                self?.statusItem.button?.isHidden = !show
            }
            .store(in: &cancellables)

        statusItem.button?.isHidden = !AppSettings.shared.showMenuBarIcon
    }

    @objc private func showMenu() {
        rebuildMenu()
        guard let button = statusItem.button else { return }
        menu.popUp(positioning: nil, at: CGPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let networks = NetworkStore.shared.networks
        let connectedCount = networks.filter { $0.status == .connected }.count

        // Status summary
        let statusText: String
        if networks.isEmpty {
            statusText = "无网络配置"
        } else if connectedCount == networks.count {
            statusText = "已全部连接 (\(connectedCount))"
        } else if connectedCount > 0 {
            statusText = "已连接 \(connectedCount)/\(networks.count)"
        } else {
            statusText = "未连接"
        }
        let statusItem = NSMenuItem(title: statusText, action: nil, keyEquivalent: "")
        statusItem.isEnabled = false
        menu.addItem(statusItem)
        menu.addItem(NSMenuItem.separator())

        // Per-network items with submenus
        if networks.isEmpty {
            let emptyItem = NSMenuItem(title: "请先添加网络配置", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for network in networks {
                let icon = statusIcon(network.status)
                let title = "\(icon) \(network.name)"
                let item = NSMenuItem(title: title, action: #selector(toggleNetwork(_:)), keyEquivalent: "")
                item.target = self
                item.representedObject = network.id
                item.isEnabled = network.status != .connecting

                // Add submenu with node info if connected and cache exists
                if network.status == .connected,
                   let peers = EasyTierService.shared.peerCache[network.id], !peers.isEmpty {
                    let submenu = NSMenu()
                    let header = NSMenuItem(title: "节点 (\(peers.count))", action: nil, keyEquivalent: "")
                    header.isEnabled = false
                    submenu.addItem(header)
                    submenu.addItem(NSMenuItem.separator())

                    for peer in peers {
                        let latencyText = peer.latency.map { "\($0)ms" } ?? "-"
                        let costLabel: String = {
                            switch peer.cost {
                            case "Local": return "本地"
                            case "p2p": return "P2P"
                            default: return "中继"
                            }
                        }()
                        let peerTitle = "\(peer.name)  \(peer.ipv4)  \(latencyText)  \(costLabel)"
                        let peerItem = NSMenuItem(title: peerTitle, action: #selector(copyPeerIP(_:)), keyEquivalent: "")
                        peerItem.target = self
                        peerItem.representedObject = peer.ipv4
                        submenu.addItem(peerItem)
                    }

                    item.submenu = submenu
                }

                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Quick actions
        if !networks.isEmpty {
            if connectedCount < networks.count {
                let connectAllItem = NSMenuItem(title: "全部连接", action: #selector(connectAllNetworks), keyEquivalent: "")
                connectAllItem.target = self
                menu.addItem(connectAllItem)
            }
            if connectedCount > 0 {
                let disconnectAllItem = NSMenuItem(title: "全部断开", action: #selector(disconnectAllNetworks), keyEquivalent: "")
                disconnectAllItem.target = self
                menu.addItem(disconnectAllItem)
            }
            menu.addItem(NSMenuItem.separator())
        }

        let showItem = NSMenuItem(title: "显示窗口", action: #selector(showWindow), keyEquivalent: "")
        showItem.target = self
        menu.addItem(showItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
    }

    @objc private func toggleNetwork(_ sender: NSMenuItem) {
        guard let networkId = sender.representedObject as? UUID,
              let network = NetworkStore.shared.networks.first(where: { $0.id == networkId })
        else { return }

        if network.status == .connected {
            NetworkStore.shared.updateStatus(id: networkId, status: .connecting)
            Task {
                try? await EasyTierService.shared.stopNetwork(configPath: network.configPath)
                NetworkStore.shared.updateStatus(id: networkId, status: .disconnected)
            }
        } else {
            NetworkStore.shared.updateStatus(id: networkId, status: .connecting)
            Task {
                do {
                    try await EasyTierService.shared.startNetwork(configPath: network.configPath)
                    NetworkStore.shared.updateStatus(id: networkId, status: .connected)
                } catch {
                    NetworkStore.shared.updateStatus(id: networkId, status: .error)
                }
            }
        }
    }

    @objc private func connectAllNetworks() {
        Task {
            for network in NetworkStore.shared.networks where network.status == .disconnected {
                NetworkStore.shared.updateStatus(id: network.id, status: .connecting)
                try? await EasyTierService.shared.startNetwork(configPath: network.configPath)
                NetworkStore.shared.updateStatus(id: network.id, status: .connected)
            }
        }
    }

    @objc private func disconnectAllNetworks() {
        Task {
            for network in NetworkStore.shared.networks where network.status == .connected {
                NetworkStore.shared.updateStatus(id: network.id, status: .connecting)
                try? await EasyTierService.shared.stopNetwork(configPath: network.configPath)
                NetworkStore.shared.updateStatus(id: network.id, status: .disconnected)
            }
        }
    }

    @objc private func copyPeerIP(_ sender: NSMenuItem) {
        guard let ip = sender.representedObject as? String else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(ip, forType: .string)
    }

    @objc private func showWindow() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    private func statusIcon(_ status: VirtualNetwork.ConnectionStatus) -> String {
        switch status {
        case .connected: return "\u{25CF}"      // ●
        case .connecting: return "\u{25D0}"     // ◐
        case .disconnected: return "\u{25CB}"   // ○
        case .error: return "\u{2715}"           // ✕
        }
    }
}

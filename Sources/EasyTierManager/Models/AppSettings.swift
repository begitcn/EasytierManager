import Foundation
import AppKit
import ServiceManagement

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var showMenuBarIcon: Bool
    @Published var showDockIcon: Bool
    @Published var isLaunchAtLogin: Bool
    @Published var autoConnectOnLaunch: Bool
    @Published var toggleWarning: String?

    private let defaults = UserDefaults.standard

    private init() {
        let menuBar = defaults.object(forKey: "showMenuBarIcon") as? Bool ?? true
        let dock = defaults.object(forKey: "showDockIcon") as? Bool ?? true
        if !menuBar && !dock {
            showMenuBarIcon = true
            showDockIcon = true
        } else {
            showMenuBarIcon = menuBar
            showDockIcon = dock
        }
        isLaunchAtLogin = defaults.object(forKey: "isLaunchAtLogin") as? Bool ?? false
        autoConnectOnLaunch = defaults.object(forKey: "autoConnectOnLaunch") as? Bool ?? false
    }

    func setMenuBarIcon(_ value: Bool) {
        if !value && !showDockIcon {
            toggleWarning = "至少需要选中一个"
            return
        }
        showMenuBarIcon = value
        save()
        applyActivationPolicy()
    }

    func setDockIcon(_ value: Bool) {
        if !value && !showMenuBarIcon {
            toggleWarning = "至少需要选中一个"
            return
        }
        showDockIcon = value
        save()
        applyActivationPolicy()
    }

    func setAutoConnectOnLaunch(_ value: Bool) {
        autoConnectOnLaunch = value
        save()
    }

    func setLaunchAtLogin(_ value: Bool) {
        isLaunchAtLogin = value
        save()
        applyLaunchAtLogin()
    }

    private func save() {
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(showDockIcon, forKey: "showDockIcon")
        defaults.set(isLaunchAtLogin, forKey: "isLaunchAtLogin")
        defaults.set(autoConnectOnLaunch, forKey: "autoConnectOnLaunch")
    }

    private func applyLaunchAtLogin() {
        do {
            if isLaunchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update login item: \(error)")
        }
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}

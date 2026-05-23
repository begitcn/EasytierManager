import Foundation
import AppKit

@MainActor
class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var showMenuBarIcon: Bool
    @Published var showDockIcon: Bool
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

    private func save() {
        defaults.set(showMenuBarIcon, forKey: "showMenuBarIcon")
        defaults.set(showDockIcon, forKey: "showDockIcon")
    }

    func applyActivationPolicy() {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }
}

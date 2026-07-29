import SwiftUI

struct MainView: View {
    @EnvironmentObject var navigationVM: NavigationVM

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            navigationVM.selection.getView()
                .frame(minWidth: 560, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 800, minHeight: 600)
    }

    private var sidebar: some View {
        List(selection: $navigationVM.selection) {
            ForEach(NavigationVM.Nav.allCases) { nav in
                Label(nav.displayName, systemImage: nav.icon)
                    .tag(nav)
            }
        }
        .listStyle(.sidebar)
        .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        .safeAreaInset(edge: .bottom) {
            Text(Bundle.main.versionStr)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Spacing.sm)
        }
        .background(KeyboardShortcuts(selection: $navigationVM.selection))
    }
}

/// 保留 ⌘1 / ⌘2 / ⌘3 页面切换快捷键。
/// 快捷键必须挂在参与渲染的 Button 上，这里用零尺寸透明按钮承载。
private struct KeyboardShortcuts: View {
    @Binding var selection: NavigationVM.Nav

    var body: some View {
        ZStack {
            ForEach(NavigationVM.Nav.allCases) { nav in
                Button(action: { selection = nav }) { EmptyView() }
                    .keyboardShortcut(nav.shortcutKey, modifiers: .command)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

extension NavigationVM.Nav {
    var icon: String {
        switch self {
        case .connections:
            return "network"
        case .nodes:
            return "square.3.layers.3d"
        case .settings:
            return "gear"
        }
    }

    var displayName: String {
        switch self {
        case .connections:
            return "连接"
        case .nodes:
            return "节点"
        case .settings:
            return "设置"
        }
    }

    var shortcutKey: KeyEquivalent {
        switch self {
        case .connections:
            return "1"
        case .nodes:
            return "2"
        case .settings:
            return "3"
        }
    }

    @ViewBuilder
    func getView() -> some View {
        switch self {
        case .connections:
            ConnectionsView()
        case .nodes:
            NodesView()
        case .settings:
            SettingsView()
        }
    }
}

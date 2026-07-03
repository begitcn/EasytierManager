import SwiftUI

struct MainView: View {
    @EnvironmentObject var navigationVM: NavigationVM

    @State private var asyncSelection: NavigationVM.Nav = .connections

    var body: some View {
        return HStack(spacing: 0) {
            ZStack {
                Rectangle()
                    .fill(.ultraThickMaterial)

                HStack {
                    VStack {
                        Button(action: {}) {
                            Text(" ")
                        }

                        Spacer()
                    }
                    Spacer()
                }
                .opacity(0)

                VStack(spacing: 12) {
                    ForEach(NavigationVM.Nav.grouped, id: \.id) { group in
                        VStack(spacing: 2) {
                            if !group.title.isEmpty {
                                HStack {
                                    Text(group.title)
                                        .font(.system(size: 10))
                                        .opacity(0.6)
                                    Spacer()
                                }
                                .padding(.leading, 20)
                                .padding(.bottom, 2)
                            }

                            ForEach(group.nav) { nav in
                                let onSelect = { navigationVM.selection = nav }

                                Button(action: onSelect) {
                                    Text(nav.displayName)
                                }
                                .buttonStyle(
                                    NavButtonStyle(
                                        icon: nav.icon,
                                        isActive: navigationVM.selection == nav
                                    )
                                )
                                .keyboardShortcut(nav.shortcutKey, modifiers: .command)
                            }
                        }
                    }

                    Spacer()

                    Text(" \(Bundle.main.versionStr)")
                        .opacity(0.5)
                        .font(.system(size: 12))
                }
                .padding(.top, 40)
                .padding(.vertical)
            }
            .frame(width: 200)

            HStack {
                VStack(spacing: 0) {
                    HStack {
                        Image(systemName: asyncSelection.icon)
                            .font(.system(size: 18, weight: .medium))
                            .opacity(0.8)
                            .frame(width: 20)

                        Text(asyncSelection.displayName)
                            .font(.system(size: 12, weight: .semibold))
                            .opacity(0.8)

                        Spacer()
                    }
                    .frame(height: 52)
                    .padding(.horizontal)
                    .background(NSColor.background.color)
                    .border(width: 1, edges: [.bottom], color: NSColor.border.color)

                    asyncSelection.getView()
                        .frame(minWidth: 0, maxWidth: .infinity, maxHeight: .infinity)
                    Spacer(minLength: 0)
                }
                .frame(minWidth: 580)

                Spacer(minLength: 0)
            }
            .border(width: 1, edges: [.leading], color: NSColor.border.color)
        }
        .frame(minWidth: 820, minHeight: 620)
        .background(NSColor.background.color)
        .onChange(of: navigationVM.selection) { _ in
            asyncSelection = navigationVM.selection
        }
        .onAppear {
            asyncSelection = navigationVM.selection
        }
        .edgesIgnoringSafeArea(.top)
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

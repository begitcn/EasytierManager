import SwiftUI

@MainActor
class NavigationVM: ObservableObject {
    enum Nav: String, CaseIterable, Identifiable {
        var id: String { rawValue }

        case connections = "连接"
        case nodes = "节点"
        case settings = "设置"

        static var grouped: [(id: String, title: String, nav: [Nav])] {
            [
                ("main", "", [.connections, .nodes, .settings]),
            ]
        }
    }

    @Published var selection: Nav = .connections
}

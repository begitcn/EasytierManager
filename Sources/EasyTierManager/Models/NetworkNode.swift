import Foundation

struct NetworkNode: Identifiable {
    var id: UUID
    var name: String
    var ipv4: String
    var ipv6: String?
    var status: NodeStatus
    var latency: Int?
    var networkId: UUID
    var isLocal: Bool
    var cost: String?

    enum NodeStatus: String {
        case online
        case offline
        case unknown
    }

    init(id: UUID = UUID(), name: String, ipv4: String, ipv6: String? = nil, status: NodeStatus = .unknown, latency: Int? = nil, networkId: UUID, isLocal: Bool = false, cost: String? = nil) {
        self.id = id
        self.name = name
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.status = status
        self.latency = latency
        self.networkId = networkId
        self.isLocal = isLocal
        self.cost = cost
    }
}

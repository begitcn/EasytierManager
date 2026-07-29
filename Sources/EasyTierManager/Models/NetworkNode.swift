import Foundation

struct NetworkNode: Identifiable, Equatable {
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

    init(id: UUID? = nil, name: String, ipv4: String, ipv6: String? = nil, status: NodeStatus = .unknown, latency: Int? = nil, networkId: UUID, isLocal: Bool = false, cost: String? = nil) {
        // 默认使用由 networkId + ipv4 派生的稳定 ID：
        // 同一进程内多次解析同一节点得到相同 ID，使列表 diff / Equatable 比较有效，
        // 避免每次刷新都重建整个列表。
        self.id = id ?? Self.makeID(networkId: networkId, ipv4: ipv4)
        self.name = name
        self.ipv4 = ipv4
        self.ipv6 = ipv6
        self.status = status
        self.latency = latency
        self.networkId = networkId
        self.isLocal = isLocal
        self.cost = cost
    }

    private static func makeID(networkId: UUID, ipv4: String) -> UUID {
        func hash(_ salt: Int) -> UInt64 {
            var hasher = Hasher()
            hasher.combine(salt)
            hasher.combine(networkId)
            hasher.combine(ipv4)
            return UInt64(bitPattern: Int64(hasher.finalize()))
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(16)
        withUnsafeBytes(of: hash(0).bigEndian) { bytes.append(contentsOf: $0) }
        withUnsafeBytes(of: hash(1).bigEndian) { bytes.append(contentsOf: $0) }
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }
}

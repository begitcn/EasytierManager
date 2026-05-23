import Foundation

struct VirtualNetwork: Identifiable, Codable {
    var id: UUID
    var name: String
    var configPath: String
    var isAutoConnect: Bool
    var status: ConnectionStatus

    enum ConnectionStatus: String, Codable {
        case disconnected
        case connecting
        case connected
        case error
    }

    init(id: UUID = UUID(), name: String, configPath: String, isAutoConnect: Bool = false, status: ConnectionStatus = .disconnected) {
        self.id = id
        self.name = name
        self.configPath = configPath
        self.isAutoConnect = isAutoConnect
        self.status = status
    }
}

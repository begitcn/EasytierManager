import Foundation

@MainActor
class NetworkStore: ObservableObject {
    static let shared = NetworkStore()

    @Published var networks: [VirtualNetwork] = []

    private let saveURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyTierManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("networks.json")
    }()

    private init() {
        load()
    }

    func addNetwork(_ network: VirtualNetwork) {
        networks.append(network)
        save()
    }

    func updateNetwork(_ network: VirtualNetwork) {
        if let index = networks.firstIndex(where: { $0.id == network.id }) {
            networks[index] = network
            save()
        }
    }

    func removeNetwork(id: UUID) {
        networks.removeAll { $0.id == id }
        save()
    }

    func updateStatus(id: UUID, status: VirtualNetwork.ConnectionStatus) {
        if let index = networks.firstIndex(where: { $0.id == id }) {
            networks[index].status = status
        }
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: saveURL.path),
              let data = try? Data(contentsOf: saveURL),
              let decoded = try? JSONDecoder().decode([VirtualNetwork].self, from: data)
        else {
            networks = []
            return
        }
        networks = decoded
    }
}
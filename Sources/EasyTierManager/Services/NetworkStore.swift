import Foundation

@MainActor
class NetworkStore: ObservableObject {
    static let shared = NetworkStore()

    @Published var networks: [VirtualNetwork] = []
    @Published private(set) var configCache: [UUID: EasyTierConfig] = [:]

    private let saveURL: URL = {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("EasyTierManager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("networks.json")
    }()

    private var saveTask: Task<Void, Never>?

    private init() {
        load()
    }

    func addNetwork(_ network: VirtualNetwork) {
        networks.append(network)
        scheduleSave()
    }

    func updateNetwork(_ network: VirtualNetwork) {
        if let index = networks.firstIndex(where: { $0.id == network.id }) {
            networks[index] = network
            scheduleSave()
        }
    }

    func removeNetwork(id: UUID) {
        networks.removeAll { $0.id == id }
        configCache.removeValue(forKey: id)
        scheduleSave()
    }

    func updateStatus(id: UUID, status: VirtualNetwork.ConnectionStatus) {
        if let index = networks.firstIndex(where: { $0.id == id }) {
            networks[index].status = status
        }
    }

    func cacheConfig(_ config: EasyTierConfig, for id: UUID) {
        configCache[id] = config
    }

    func invalidateConfig(for id: UUID) {
        configCache.removeValue(forKey: id)
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 500_000_000)
            guard let self, !Task.isCancelled else { return }
            performSave()
        }
    }

    private func performSave() {
        guard let data = try? JSONEncoder().encode(networks) else { return }
        try? data.write(to: saveURL, options: .atomic)
    }

    func saveImmediately() {
        saveTask?.cancel()
        performSave()
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
        for i in networks.indices {
            networks[i].status = .disconnected
        }
    }
}

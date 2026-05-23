import Foundation
import EasyTierHelperShared

@MainActor
class EasyTierService: ObservableObject {
    static let shared = EasyTierService()

    @Published private(set) var activeConfigs: [String] = []
    @Published private(set) var isConnecting = false

    private var coreProcessPID: Int?
    private let helperManager = EasyTierHelperManager.shared

    private var helpersPath: String { Bundle.main.bundlePath + "/Contents/Helpers" }
    private var corePath: String { helpersPath + "/easytier-core" }
    private var cliPath: String { helpersPath + "/easytier-cli" }

    private init() {}

    private func getProxy() async throws -> EasyTierHelperProtocol {
        if !helperManager.isHelperConnected {
            await helperManager.installAndConnect()
        }
        guard let anyProxy = helperManager.proxy,
              let proxy = anyProxy as? EasyTierHelperProtocol else {
            throw EasyTierError.helperNotConnected
        }
        return proxy
    }

    func startNetwork(configPath: String) async throws {
        let proxy = try await getProxy()
        isConnecting = true
        defer { isConnecting = false }

        activeConfigs.append(configPath)

        if let pid = coreProcessPID {
            try await stopProcessSafely(pid: pid, proxy: proxy)
        }

        do {
            let newPid = try await launchCore(proxy: proxy)
            coreProcessPID = newPid
        } catch {
            activeConfigs.removeLast()
            throw error
        }
    }

    func stopNetwork(configPath: String) async throws {
        let proxy = try await getProxy()

        guard let index = activeConfigs.firstIndex(of: configPath) else {
            return
        }

        activeConfigs.remove(at: index)

        guard let pid = coreProcessPID else {
            return
        }

        if activeConfigs.isEmpty {
            try await stopProcessSafely(pid: pid, proxy: proxy)
            coreProcessPID = nil
        } else {
            let originalConfigs = activeConfigs
            try await stopProcessSafely(pid: pid, proxy: proxy)
            coreProcessPID = nil

            do {
                let newPid = try await launchCore(proxy: proxy)
                coreProcessPID = newPid
            } catch {
                activeConfigs = originalConfigs
                throw error
            }
        }
    }

    func checkNetworkStatus(configPath: String) async throws -> Bool {
        guard activeConfigs.contains(configPath), let pid = coreProcessPID else {
            return false
        }

        let proxy = try await getProxy()
        return try await withCheckedThrowingContinuation { continuation in
            proxy.isProcessRunning(pid: pid) { isRunning in
                if !isRunning {
                    Task { @MainActor in
                        self.coreProcessPID = nil
                    }
                }
                continuation.resume(returning: isRunning)
            }
        }
    }

    func getPeerList(connectedNetworks: [VirtualNetwork] = []) async throws -> [NetworkNode] {
        let output = try await runCLI([cliPath, "-o", "json", "peer", "list"])
        let networkMap = Dictionary(connectedNetworks.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        return parsePeerJSON(output, networkMap: networkMap)
    }

    func getNodeInfo() async throws -> [String: Any] {
        let output = try await runCLI([cliPath, "-o", "json", "node", "info"])
        return parseNodeJSON(output)
    }

    func getCoreVersion() -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: corePath)
        process.arguments = ["--version"]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
            process.waitUntilExit()
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let outputStr = String(data: data, encoding: .utf8) ?? ""
            let version = outputStr
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .components(separatedBy: .whitespacesAndNewlines)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return version.isEmpty ? "" : version
        } catch {
            return ""
        }
    }

    func forceStopAll() {
        guard let pid = coreProcessPID else { return }
        coreProcessPID = nil
        activeConfigs = []

        let semaphore = DispatchSemaphore(value: 0)
        if let anyProxy = helperManager.proxy,
           let proxy = anyProxy as? EasyTierHelperProtocol {
            proxy.forceStopProcess(pid: pid) { _, _ in
                semaphore.signal()
            }
            _ = semaphore.wait(timeout: .now() + 3.0)
        }
    }

    // MARK: - Private

    private func launchCore(proxy: EasyTierHelperProtocol) async throws -> Int {
        var args = ["--daemon"]
        for config in activeConfigs {
            args += ["-c", config]
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.startProcess(executablePath: corePath, arguments: args) { success, pid, error in
                Task { @MainActor in
                    if success && pid > 0 {
                        continuation.resume(returning: Int(pid))
                    } else {
                        continuation.resume(throwing: EasyTierError.startFailed(error ?? "Unknown error"))
                    }
                }
            }
        }
    }

    private func stopProcessSafely(pid: Int, proxy: EasyTierHelperProtocol) async throws {
        try await withCheckedThrowingContinuation { continuation in
            proxy.stopProcess(pid: pid) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EasyTierError.stopFailed(error ?? "Unknown error"))
                }
            }
        }

        let startTime = Date()
        while Date().timeIntervalSince(startTime) < 5.0 {
            let isRunning = try await withCheckedThrowingContinuation { continuation in
                proxy.isProcessRunning(pid: pid) { running in
                    continuation.resume(returning: running)
                }
            }
            if !isRunning { return }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        try await withCheckedThrowingContinuation { continuation in
            proxy.forceStopProcess(pid: pid) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EasyTierError.stopFailed(error ?? "Force kill failed"))
                }
            }
        }
    }

    private func runCLI(_ args: [String]) async throws -> String {
        guard let firstArg = args.first else { throw EasyTierError.invalidArguments }
        let arguments = Array(args.dropFirst())

        let process = Process()
        process.executableURL = URL(fileURLWithPath: firstArg)
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        return try await withCheckedThrowingContinuation { continuation in
            do {
                try process.run()
                process.waitUntilExit()
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                if process.terminationStatus == 0 {
                    continuation.resume(returning: output)
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(throwing: EasyTierError.cliFailed(errorStr))
                }
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private func parsePeerJSON(_ json: String, networkMap: [String: UUID] = [:]) -> [NetworkNode] {
        guard let data = json.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return parsePeerText(json) }

        let defaultNetworkId = networkMap.values.first ?? UUID()

        return jsonArray.flatMap { element -> [NetworkNode] in
            if let result = element["result"] as? [[String: Any]] {
                let instanceName = element["instance_name"] as? String ?? ""
                let networkId = networkMap[instanceName] ?? defaultNetworkId
                return result.compactMap { parsePeerNode($0, networkId: networkId) }
            }
            if let node = parsePeerNode(element, networkId: defaultNetworkId) {
                return [node]
            }
            return []
        }
    }

    private func parsePeerNode(_ dict: [String: Any], networkId: UUID) -> NetworkNode? {
        guard let name = dict["hostname"] as? String ?? dict["peer_id"] as? String,
              let ipv4 = dict["ipv4"] as? String
        else { return nil }

        let latency: Int? = {
            if let latStr = dict["lat_ms"] as? String ?? dict["latency_ms"] as? String,
               latStr != "-" {
                return Int(Double(latStr) ?? 0)
            }
            return nil
        }()

        let cost = dict["cost"] as? String

        return NetworkNode(
            name: name,
            ipv4: ipv4,
            ipv6: dict["virtual_ipv6"] as? String ?? dict["ipv6"] as? String,
            status: .online,
            latency: latency,
            networkId: networkId,
            isLocal: cost == "Local",
            cost: cost
        )
    }

    private func parsePeerText(_ text: String) -> [NetworkNode] {
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line -> NetworkNode? in
            let columns = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard columns.count >= 2 else { return nil }
            return NetworkNode(name: columns[0], ipv4: columns[1], status: .online, networkId: UUID())
        }
    }

    private func parseNodeJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}

enum EasyTierError: LocalizedError {
    case helperNotConnected
    case startFailed(String)
    case stopFailed(String)
    case cliFailed(String)
    case invalidArguments

    var errorDescription: String? {
        switch self {
        case .helperNotConnected:
            return "特权助手未连接，请在设置中安装助手"
        case .startFailed(let msg):
            return "启动网络失败: \(msg)"
        case .stopFailed(let msg):
            return "停止网络失败: \(msg)"
        case .cliFailed(let msg):
            return "CLI 执行失败: \(msg)"
        case .invalidArguments:
            return "无效参数"
        }
    }
}

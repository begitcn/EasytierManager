import Foundation
import EasyTierHelperShared

@MainActor
class EasyTierService: ObservableObject {
    static let shared = EasyTierService()

    @Published private(set) var runningNetworks: [String: Int] = [:]
    @Published private(set) var isConnecting = false

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

        let args = ["--daemon", "-c", configPath]

        return try await withCheckedThrowingContinuation { continuation in
            proxy.startProcess(executablePath: corePath, arguments: args) { success, pid, error in
                Task { @MainActor in
                    if success && pid > 0 {
                        self.runningNetworks[configPath] = pid
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: EasyTierError.startFailed(error ?? "Unknown error"))
                    }
                }
            }
        }
    }

    func stopNetwork(configPath: String) async throws {
        let proxy = try await getProxy()

        if let pid = runningNetworks[configPath] {
            try await stopProcess(pid: pid, proxy: proxy)
            runningNetworks.removeValue(forKey: configPath)
            return
        }

        let processes = try await findProcess(configPath: configPath, proxy: proxy)
        guard let firstProc = processes.first,
              let pidStr = firstProc.components(separatedBy: .whitespaces).first,
              let pid = Int(pidStr)
        else { return }

        try await stopProcess(pid: pid, proxy: proxy)
        runningNetworks.removeValue(forKey: configPath)
    }

    func checkNetworkStatus(configPath: String) async throws -> Bool {
        let proxy = try await getProxy()

        if let pid = runningNetworks[configPath] {
            return try await withCheckedThrowingContinuation { continuation in
                proxy.isProcessRunning(pid: pid) { isRunning in
                    if !isRunning { self.runningNetworks.removeValue(forKey: configPath) }
                    continuation.resume(returning: isRunning)
                }
            }
        }

        let processes = try await findProcess(configPath: configPath, proxy: proxy)
        return !processes.isEmpty
    }

    func getPeerList() async throws -> [NetworkNode] {
        let output = try await runCLI([cliPath, "-o", "json", "peer", "list"])
        return parsePeerJSON(output)
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

    private func stopProcess(pid: Int, proxy: EasyTierHelperProtocol) async throws {
        try await withCheckedThrowingContinuation { continuation in
            proxy.stopProcess(pid: pid) { success, error in
                if success {
                    continuation.resume()
                } else {
                    continuation.resume(throwing: EasyTierError.stopFailed(error ?? "Unknown error"))
                }
            }
        }
    }

    private func findProcess(configPath: String, proxy: EasyTierHelperProtocol) async throws -> [String] {
        let pattern = "easytier-core.*\(configPath)"
        return try await withCheckedThrowingContinuation { continuation in
            proxy.findProcess(pattern: pattern) { results in
                continuation.resume(returning: results)
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

    private func parsePeerJSON(_ json: String) -> [NetworkNode] {
        guard let data = json.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return parsePeerText(json) }

        return jsonArray.compactMap { dict -> NetworkNode? in
            guard let name = dict["hostname"] as? String ?? dict["peer_id"] as? String,
                  let ipv4 = dict["virtual_ipv4"] as? String ?? dict["ipv4"] as? String
            else { return nil }

            return NetworkNode(
                name: name,
                ipv4: ipv4,
                ipv6: dict["virtual_ipv6"] as? String ?? dict["ipv6"] as? String,
                status: .online,
                latency: dict["latency_us"] as? Int ?? dict["latency_ms"] as? Int,
                networkId: UUID()
            )
        }
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
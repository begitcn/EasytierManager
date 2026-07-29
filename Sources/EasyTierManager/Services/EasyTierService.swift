import Foundation
import os
@preconcurrency import EasyTierHelperShared

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

    private var healthCheckTask: Task<Void, Never>?
    private let healthCheckInterval: TimeInterval = 30
    private var consecutiveFailures = 0
    private let maxConsecutiveFailures = 5
    private var sleepConfigs: [String] = []
    private var isSleeping = false

    @Published private(set) var peerCache: [UUID: [NetworkNode]] = [:]
    private var cachedCoreVersion: String?
    var isAppActive = true
    /// 主窗口是否可见。不可见时停止一切 UI 轮询，仅保留核心健康检查。
    var isWindowVisible = true

    func updatePeerCache(_ nodes: [NetworkNode]) {
        // Group nodes by networkId for the cache
        var cache: [UUID: [NetworkNode]] = [:]
        for node in nodes {
            cache[node.networkId, default: []].append(node)
        }
        // 内容未变化时不触发 @Published 刷新，避免无效视图重建
        guard cache != peerCache else { return }
        peerCache = cache
    }

    private init() {}

    private func getProxy() async throws -> EasyTierHelperProtocol {
        if !helperManager.isHelperConnected {
            await helperManager.installAndConnect()
        }
        guard let proxy = helperManager.proxy else {
            throw EasyTierError.helperNotConnected
        }
        return proxy
    }

    func startNetwork(configPath: String) async throws {
        guard !activeConfigs.contains(configPath) else { return }
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
            consecutiveFailures = 0
            startHealthCheck()
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
            stopHealthCheck()
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
            proxy.isProcessRunning(pid: pid) { [weak self] isRunning in
                if !isRunning {
                    Task { @MainActor in
                        self?.coreProcessPID = nil
                    }
                }
                continuation.resume(returning: isRunning)
            }
        }
    }

    func getPeerList(connectedNetworks: [VirtualNetwork] = []) async throws -> [NetworkNode] {
        guard await isCoreAlive() else {
            throw EasyTierError.coreNotRunning
        }
        let output = try await runCLI([cliPath, "-o", "json", "peer", "list"])
        let networkMap = Dictionary(connectedNetworks.map { ($0.name, $0.id) }, uniquingKeysWith: { first, _ in first })
        return parsePeerJSON(output, networkMap: networkMap)
    }

    func isCoreAlive() async -> Bool {
        guard let pid = coreProcessPID else { return false }
        guard let proxy = helperManager.proxy else { return false }
        return await withCheckedContinuation { continuation in
            proxy.isProcessRunning(pid: pid) { running in
                continuation.resume(returning: running)
            }
        }
    }

    func getNodeInfo() async throws -> [String: Any] {
        let output = try await runCLI([cliPath, "-o", "json", "node", "info"])
        return parseNodeJSON(output)
    }

    func getCoreVersion() async -> String {
        if let cached = cachedCoreVersion { return cached }
        let path = corePath
        let version = await Task.detached(priority: .utility) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = ["--version"]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = output
            do {
                try process.run()
                let data = output.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
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
        }.value
        cachedCoreVersion = version
        return version
    }

    func clearCoreVersionCache() {
        cachedCoreVersion = nil
    }

    func restartActiveNetworks() async {
        guard !activeConfigs.isEmpty else { return }

        for configPath in activeConfigs {
            if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                NetworkStore.shared.updateStatus(id: network.id, status: .connecting)
            }
        }

        do {
            let proxy = try await getProxy()
            if let pid = coreProcessPID {
                try? await stopProcessSafely(pid: pid, proxy: proxy)
                coreProcessPID = nil
            }

            let newPid = try await launchCore(proxy: proxy)
            coreProcessPID = newPid
            consecutiveFailures = 0
            startHealthCheck()

            for configPath in activeConfigs {
                if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                    NetworkStore.shared.updateStatus(id: network.id, status: .connected)
                }
            }
        } catch {
            coreProcessPID = nil
            for configPath in activeConfigs {
                if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                    NetworkStore.shared.updateStatus(id: network.id, status: .error)
                }
            }
        }
    }

    func prepareForSleep() async {
        guard !activeConfigs.isEmpty else { return }
        isSleeping = true
        sleepConfigs = activeConfigs

        stopHealthCheck()

        if let pid = coreProcessPID {
            if let proxy = helperManager.proxy {
                try? await stopProcessSafely(pid: pid, proxy: proxy)
            }
            coreProcessPID = nil
        }

        helperManager.disconnect()
    }

    func restoreAfterWake() async {
        isSleeping = false

        let configsToRestore = !sleepConfigs.isEmpty ? sleepConfigs : activeConfigs
        guard !configsToRestore.isEmpty else { return }

        activeConfigs = configsToRestore
        sleepConfigs = []

        // 唤醒后网络栈需要一点时间就绪；重连助手成功后统一走 restartActiveNetworks
        var success = false
        let maxRetries = 5
        for attempt in 1...maxRetries {
            let delay = attempt == 1 ? 2 : attempt
            try? await Task.sleep(nanoseconds: UInt64(delay) * 1_000_000_000)

            await helperManager.installAndConnect()
            guard helperManager.isHelperConnected else { continue }

            await restartActiveNetworks()
            success = coreProcessPID != nil
            if success { break }
        }

        if !success {
            for configPath in configsToRestore {
                if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                    NetworkStore.shared.updateStatus(id: network.id, status: .error)
                }
            }
        }
    }

    func forceStopAll(completion: (() -> Void)? = nil) {
        stopHealthCheck()
        let pid = coreProcessPID
        coreProcessPID = nil
        activeConfigs = []

        guard let proxy = helperManager.proxy else {
            completion?()
            return
        }

        if let pid {
            proxy.stopProcess(pid: pid) { _, _ in
                DispatchQueue.global().asyncAfter(deadline: .now() + 2.0) {
                    proxy.forceStopProcess(pid: pid) { _, _ in
                        proxy.stopAllProcesses { _, _ in
                            completion?()
                        }
                    }
                }
            }
        } else {
            proxy.stopAllProcesses { _, _ in
                completion?()
            }
        }
    }

    func forceStopAllAsync() async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            forceStopAll {
                continuation.resume()
            }
        }
    }

    private func startHealthCheck() {
        stopHealthCheck()
        let intervalNs = UInt64(healthCheckInterval * 1_000_000_000)
        healthCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: intervalNs)
                guard let self else { break }
                await self.performHealthCheck()
            }
        }
    }

    private func stopHealthCheck() {
        healthCheckTask?.cancel()
        healthCheckTask = nil
    }

    private func performHealthCheck() async {
        // 健康检查不依赖 App 是否在前台：常驻工具必须在后台也维持连接稳定
        guard !activeConfigs.isEmpty, let _ = coreProcessPID, !isSleeping else { return }
        let alive = await isCoreAlive()
        if alive {
            consecutiveFailures = 0
            return
        }

        consecutiveFailures += 1
        if consecutiveFailures > maxConsecutiveFailures {
            stopHealthCheck()
            for configPath in activeConfigs {
                if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                    NetworkStore.shared.updateStatus(id: network.id, status: .error)
                }
            }
            return
        }

        coreProcessPID = nil

        // 指数退避（5s → 10s → 20s → 40s，封顶 60s），避免核心反复崩溃时陷入高频重启循环
        let backoff = min(5.0 * pow(2.0, Double(consecutiveFailures - 1)), 60.0)
        try? await Task.sleep(nanoseconds: UInt64(backoff * 1_000_000_000))
        guard !Task.isCancelled, !activeConfigs.isEmpty, !isSleeping else { return }

        do {
            let proxy = try await getProxy()
            let newPid = try await launchCore(proxy: proxy)
            coreProcessPID = newPid
            consecutiveFailures = 0
        } catch {
            for configPath in activeConfigs {
                if let network = NetworkStore.shared.networks.first(where: { $0.configPath == configPath }) {
                    NetworkStore.shared.updateStatus(id: network.id, status: .error)
                }
            }
        }
    }

    // MARK: - Private

    private func launchCore(proxy: EasyTierHelperProtocol) async throws -> Int {
        var args = [String]()
        for config in activeConfigs {
            args += ["-c", config]
        }

        return try await withCheckedThrowingContinuation { continuation in
            proxy.startProcess(executablePath: corePath, arguments: args) { success, pid, error in
                if success && pid > 0 {
                    continuation.resume(returning: Int(pid))
                } else {
                    continuation.resume(throwing: EasyTierError.startFailed(error ?? "Unknown error"))
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
            let guardFlag = CLIResumeGuard()

            let timeoutTask = DispatchWorkItem {
                if process.isRunning {
                    process.terminate()
                }
                guardFlag.safeResume(continuation) {
                    throw EasyTierError.cliTimeout
                }
            }

            process.terminationHandler = { p in
                timeoutTask.cancel()

                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: outputData, encoding: .utf8) ?? ""

                guardFlag.safeResume(continuation) {
                    if p.terminationStatus == 0 {
                        return output
                    } else {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorStr = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        throw EasyTierError.cliFailed(errorStr)
                    }
                }
            }

            do {
                try process.run()
            } catch {
                timeoutTask.cancel()
                guardFlag.safeResume(continuation) { throw error }
                return
            }

            DispatchQueue.global().asyncAfter(deadline: .now() + 15.0, execute: timeoutTask)
        }
    }

    // MARK: - Peer 解析（Codable，比 JSONSerialization 更快、更省内存、类型安全）

    private struct PeerInstanceDTO: Decodable {
        let instance_name: String?
        let result: [PeerNodeDTO]?

        // 部分版本输出为扁平节点结构
        let hostname: String?
        let peer_id: String?
        let ipv4: String?
        let virtual_ipv6: String?
        let ipv6: String?
        let lat_ms: String?
        let latency_ms: String?
        let cost: String?
    }

    private struct PeerNodeDTO: Decodable {
        let hostname: String?
        let peer_id: String?
        let ipv4: String?
        let virtual_ipv6: String?
        let ipv6: String?
        let lat_ms: String?
        let latency_ms: String?
        let cost: String?
    }

    private func parsePeerJSON(_ json: String, networkMap: [String: UUID] = [:]) -> [NetworkNode] {
        guard let data = json.data(using: .utf8),
              let entries = try? JSONDecoder().decode([PeerInstanceDTO].self, from: data)
        else { return parsePeerText(json) }

        let defaultNetworkId = networkMap.values.first ?? UUID()

        return entries.flatMap { entry -> [NetworkNode] in
            if let result = entry.result {
                let networkId = entry.instance_name.flatMap { networkMap[$0] } ?? defaultNetworkId
                return result.compactMap { dto in
                    makeNode(
                        name: dto.hostname ?? dto.peer_id,
                        ipv4: dto.ipv4,
                        ipv6: dto.virtual_ipv6 ?? dto.ipv6,
                        latStr: dto.lat_ms ?? dto.latency_ms,
                        cost: dto.cost,
                        networkId: networkId
                    )
                }
            }
            if let node = makeNode(
                name: entry.hostname ?? entry.peer_id,
                ipv4: entry.ipv4,
                ipv6: entry.virtual_ipv6 ?? entry.ipv6,
                latStr: entry.lat_ms ?? entry.latency_ms,
                cost: entry.cost,
                networkId: defaultNetworkId
            ) {
                return [node]
            }
            return []
        }
    }

    private func makeNode(name: String?, ipv4: String?, ipv6: String?, latStr: String?, cost: String?, networkId: UUID) -> NetworkNode? {
        guard let name, let ipv4 else { return nil }

        let latency: Int? = {
            guard let latStr, latStr != "-" else { return nil }
            return Int(Double(latStr) ?? 0)
        }()

        return NetworkNode(
            name: name,
            ipv4: ipv4,
            ipv6: ipv6,
            status: .online,
            latency: latency,
            networkId: networkId,
            isLocal: cost == "Local",
            cost: cost
        )
    }

    private func parsePeerText(_ text: String) -> [NetworkNode] {
        // 纯文本兜底解析（旧版 CLI 无 JSON 输出时）
        let fallbackNetworkId = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        let lines = text.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard lines.count > 1 else { return [] }

        return lines.dropFirst().compactMap { line -> NetworkNode? in
            let columns = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
            guard columns.count >= 2 else { return nil }
            return NetworkNode(name: columns[0], ipv4: columns[1], status: .online, networkId: fallbackNetworkId)
        }
    }

    private func parseNodeJSON(_ json: String) -> [String: Any] {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return [:] }
        return dict
    }
}

private final class CLIResumeGuard: @unchecked Sendable {
    private var _lock = os_unfair_lock()
    private var resumed = false

    func safeResume(_ continuation: CheckedContinuation<String, any Error>,
                    block: () throws -> String) {
        os_unfair_lock_lock(&_lock)
        if resumed { os_unfair_lock_unlock(&_lock); return }
        resumed = true
        os_unfair_lock_unlock(&_lock)
        do {
            continuation.resume(returning: try block())
        } catch {
            continuation.resume(throwing: error)
        }
    }
}

enum EasyTierError: LocalizedError {
    case helperNotConnected
    case startFailed(String)
    case stopFailed(String)
    case cliFailed(String)
    case cliTimeout
    case coreNotRunning
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
        case .cliTimeout:
            return "CLI 执行超时，核心进程可能已停止响应"
        case .coreNotRunning:
            return "核心进程已停止运行"
        case .invalidArguments:
            return "无效参数"
        }
    }
}

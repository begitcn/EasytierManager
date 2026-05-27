import Foundation
import EasyTierHelperShared

@MainActor
class EasyTierHelperManager: ObservableObject {
    static let shared = EasyTierHelperManager()

    @Published private(set) var isHelperConnected = false
    @Published private(set) var lastError: String?

    private var connection: NSXPCConnection?
    private var cachedProxy: EasyTierHelperProtocol?
    private var connectionValid = false

    static let helperInstallPath = "/Library/PrivilegedHelperTools/\(EasyTierHelperConstants.machServiceName)"
    static let helperPlistPath = "/Library/LaunchDaemons/\(EasyTierHelperConstants.daemonPlistName)"

    private init() {}

    func installAndConnect() async {
        lastError = nil

        do {
            try await connectToHelper()
            isHelperConnected = true
            return
        } catch {}

        do {
            try await installHelperManually()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func reinstallHelper() async throws {
        lastError = nil
        disconnect()

        let sourceBin = findHelperBinary()
        guard let sourceBin else {
            throw EasyTierError.startFailed("Helper binary not found. Run 'swift build' first, then try again.")
        }

        let shellScript = """
        launchctl unload '\(Self.helperPlistPath)' 2>/dev/null || true
        cp '\(sourceBin)' '\(Self.helperInstallPath)'
        chmod +x '\(Self.helperInstallPath)'
        chown root:wheel '\(Self.helperInstallPath)'
        launchctl load '\(Self.helperPlistPath)'
        """

        let appleScript = """
        do shell script "\(shellScript)" with administrator privileges
        """

        let script = NSAppleScript(source: appleScript)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)

        if let errorDict = errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(domain: "EasyTierHelperManager", code: -5,
                           userInfo: [NSLocalizedDescriptionKey: "安装失败: \(message)"])
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)

        for i in 0..<3 {
            do {
                try await connectToHelper()
                isHelperConnected = true
                return
            } catch {
                if i < 2 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    throw error
                }
            }
        }
    }

    func installHelperManually() async throws {
        if FileManager.default.fileExists(atPath: Self.helperInstallPath) {
            try await connectToHelper()
            isHelperConnected = true
            return
        }

        let sourceBin = findHelperBinary()
        guard let sourceBin else {
            throw EasyTierError.startFailed("Helper binary not found. Run 'swift build' first, then try again.")
        }

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("easytier-helper-install-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let plistPath = tempDir.appendingPathComponent(EasyTierHelperConstants.daemonPlistName)
        let plistXML = Self.createPlistXML()
        try plistXML.write(to: plistPath, atomically: true, encoding: .utf8)

        let shellScript = """
        mkdir -p /Library/PrivilegedHelperTools
        cp '\(sourceBin)' '\(Self.helperInstallPath)'
        chmod +x '\(Self.helperInstallPath)'
        chown root:wheel '\(Self.helperInstallPath)'
        mkdir -p /Library/LaunchDaemons
        cp '\(plistPath.path)' '\(Self.helperPlistPath)'
        chown root:wheel '\(Self.helperPlistPath)'
        chmod 644 '\(Self.helperPlistPath)'
        launchctl load '\(Self.helperPlistPath)'
        """

        let appleScript = """
        do shell script "\(shellScript)" with administrator privileges
        """

        let script = NSAppleScript(source: appleScript)
        var errorDict: NSDictionary?
        script?.executeAndReturnError(&errorDict)

        if let errorDict = errorDict {
            let message = errorDict[NSAppleScript.errorMessage] as? String ?? "Unknown error"
            throw NSError(domain: "EasyTierHelperManager", code: -5,
                           userInfo: [NSLocalizedDescriptionKey: "安装失败: \(message)"])
        }

        try await Task.sleep(nanoseconds: 1_000_000_000)

        for i in 0..<3 {
            do {
                try await connectToHelper()
                isHelperConnected = true
                return
            } catch {
                if i < 2 {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                } else {
                    throw error
                }
            }
        }
    }

    var proxy: EasyTierHelperProtocol? {
        guard let connection, connectionValid else {
            cachedProxy = nil
            return nil
        }
        if let cachedProxy { return cachedProxy }
        let p = connection.remoteObjectProxyWithErrorHandler { [weak self] _ in
            Task { @MainActor in
                self?.cachedProxy = nil
                self?.isHelperConnected = false
            }
        } as? EasyTierHelperProtocol
        cachedProxy = p
        return p
    }

    func disconnect() {
        cachedProxy = nil
        connectionValid = false
        connection?.invalidate()
        connection = nil
        isHelperConnected = false
    }

    private static func createPlistXML() -> String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(EasyTierHelperConstants.machServiceName)</string>
            <key>MachServices</key>
            <dict>
                <key>\(EasyTierHelperConstants.machServiceName)</key>
                <true/>
            </dict>
            <key>Program</key>
            <string>\(Self.helperInstallPath)</string>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <true/>
        </dict>
        </plist>
        """
    }

    private func findHelperBinary() -> String? {
        let bundle = Bundle.main.bundlePath
        let candidates: [String] = [
            bundle + "/Contents/Library/HelperTools/\(EasyTierHelperConstants.machServiceName)",
            bundle + "/Contents/MacOS/EasyTierHelper",
            "/Library/PrivilegedHelperTools/\(EasyTierHelperConstants.machServiceName)",
        ]
        for path in candidates {
            if FileManager.default.isExecutableFile(atPath: path) {
                return path
            }
        }
        return nil
    }

    private func connectToHelper() async throws {
        let newConnection = NSXPCConnection(machServiceName: EasyTierHelperConstants.machServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: EasyTierHelperProtocol.self)
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.cachedProxy = nil
                self?.connectionValid = false
                self?.isHelperConnected = false
            }
        }
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.cachedProxy = nil
                self?.connectionValid = false
                self?.isHelperConnected = false
                self?.connection = nil
            }
        }

        self.connection?.invalidate()
        self.connection = newConnection
        self.cachedProxy = nil
        self.connectionValid = true
        newConnection.resume()

        let pingSuccess: Bool = try await withThrowingTaskGroup(of: Bool.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Bool, Error>) in
                    guard let proxy = newConnection.remoteObjectProxyWithErrorHandler({ error in
                        continuation.resume(throwing: error)
                    }) as? EasyTierHelperProtocol else {
                        continuation.resume(throwing: NSError(domain: "EasyTierHelperManager", code: -4,
                                       userInfo: [NSLocalizedDescriptionKey: "无法创建代理"]))
                        return
                    }

                    proxy.ping { success, _ in
                        continuation.resume(returning: success)
                    }
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 5_000_000_000)
                throw NSError(domain: "EasyTierHelperManager", code: -2,
                               userInfo: [NSLocalizedDescriptionKey: "连接超时"])
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }

        if !pingSuccess {
            connectionValid = false
            connection?.invalidate()
            connection = nil
            throw NSError(domain: "EasyTierHelperManager", code: -3,
                           userInfo: [NSLocalizedDescriptionKey: "Helper 响应异常"])
        }
    }
}
import Foundation
import EasyTierHelperShared

@MainActor
class EasyTierHelperManager: ObservableObject {
    static let shared = EasyTierHelperManager()

    @Published private(set) var isHelperConnected = false
    @Published private(set) var lastError: String?

    private var connection: NSXPCConnection?

    static let helperInstallPath = "/Library/PrivilegedHelperTools/\(EasyTierHelperConstants.machServiceName)"
    static let helperPlistPath = "/Library/LaunchDaemons/\(EasyTierHelperConstants.daemonPlistName)"

    private init() {}

    func installAndConnect() async {
        lastError = nil

        do {
            try connectToHelper()
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
        try await installHelperManually()
    }

    func installHelperManually() async throws {
        if FileManager.default.fileExists(atPath: Self.helperInstallPath) {
            try connectToHelper()
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

        try connectToHelper()
        isHelperConnected = true
    }

    var proxy: AnyObject? {
        guard let connection else { return nil }
        return connection.remoteObjectProxyWithErrorHandler { [weak self] error in
            Task { @MainActor in
                self?.isHelperConnected = false
            }
        } as AnyObject
    }

    func disconnect() {
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

    private func connectToHelper() throws {
        let newConnection = NSXPCConnection(machServiceName: EasyTierHelperConstants.machServiceName)
        newConnection.remoteObjectInterface = NSXPCInterface(with: EasyTierHelperProtocol.self)
        newConnection.interruptionHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperConnected = false
            }
        }
        newConnection.invalidationHandler = { [weak self] in
            Task { @MainActor in
                self?.isHelperConnected = false
                self?.connection = nil
            }
        }

        self.connection = newConnection
        newConnection.resume()

        let semaphore = DispatchSemaphore(value: 0)
        var pingSuccess = false
        var connectionError: Error?

        let proxy = newConnection.remoteObjectProxyWithErrorHandler { error in
            connectionError = error
            semaphore.signal()
        } as AnyObject

        proxy.ping { success, _ in
            pingSuccess = success
            semaphore.signal()
        }

        let timeout = semaphore.wait(timeout: .now() + 5.0)
        if timeout == .timedOut {
            connection?.invalidate()
            connection = nil
            throw NSError(domain: "EasyTierHelperManager", code: -2,
                           userInfo: [NSLocalizedDescriptionKey: "连接超时"])
        }

        if let error = connectionError {
            connection?.invalidate()
            connection = nil
            throw error
        }

        if !pingSuccess {
            connection?.invalidate()
            connection = nil
            throw NSError(domain: "EasyTierHelperManager", code: -3,
                           userInfo: [NSLocalizedDescriptionKey: "Helper 响应异常"])
        }
    }
}
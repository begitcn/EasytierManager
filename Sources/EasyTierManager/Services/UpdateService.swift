import Foundation
import AppKit
import EasyTierHelperShared

@MainActor
class UpdateService: ObservableObject {
    static let shared = UpdateService()
    
    @Published var isChecking = false
    @Published var isDownloading = false
    @Published var downloadProgress: Double = 0.0
    @Published var latestVersion = ""
    @Published var releaseNotes = ""
    @Published var updateAvailable = false
    @Published var error: String? = nil
    @Published var hasChecked = false
    
    private var downloadTask: URLSessionDownloadTask?
    private var currentReleaseResponse: ReleaseResponse?
    
    struct ReleaseAsset: Codable {
        let name: String
        let browser_download_url: URL
    }
    
    struct ReleaseResponse: Codable {
        let tag_name: String
        let body: String?
        let html_url: String?
        let assets: [ReleaseAsset]
    }
    
    private init() {}
    
    func checkForUpdates() async {
        guard !isChecking else { return }
        
        isChecking = true
        error = nil
        
        let urlString = "https://easytier.782389.xyz"
        guard let url = URL(string: urlString) else {
            error = "无效的更新服务器地址"
            isChecking = false
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("EasyTierManager/\(AppVersion.current)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15.0
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                throw NSError(domain: "UpdateService", code: 0, userInfo: [NSLocalizedDescriptionKey: "服务器返回错误状态码"])
            }
            
            let release = try JSONDecoder().decode(ReleaseResponse.self, from: data)
            
            let cleanCurrent = AppVersion.current.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
            let cleanLatest = release.tag_name.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "v", with: "")
            
            self.latestVersion = release.tag_name
            self.releaseNotes = release.body ?? ""
            self.updateAvailable = cleanLatest.compare(cleanCurrent, options: .numeric) == .orderedDescending
            self.hasChecked = true
            self.currentReleaseResponse = release
        } catch {
            self.error = "检查更新失败: \(error.localizedDescription)"
        }
        
        isChecking = false
    }
    
    func downloadAndInstall() async {
        guard let release = currentReleaseResponse, !isDownloading else { return }
        
        isDownloading = true
        downloadProgress = 0.0
        error = nil
        
        guard let dmgAsset = findDmgAsset(from: release.assets) else {
            error = "未找到适用于当前架构的安装包 (.dmg)"
            isDownloading = false
            return
        }
        
        do {
            let tempDir = FileManager.default.temporaryDirectory
            let downloadDestination = tempDir.appendingPathComponent("EasyTierManager-update.dmg")
            
            if FileManager.default.fileExists(atPath: downloadDestination.path) {
                try? FileManager.default.removeItem(at: downloadDestination)
            }
            
            let downloadedURL = try await downloadFile(from: dmgAsset.browser_download_url)
            try FileManager.default.moveItem(at: downloadedURL, to: downloadDestination)
            
            do {
                try await silentInstall(dmgURL: downloadDestination)
            } catch {
                NSWorkspace.shared.open(downloadDestination)
                self.error = "自动安装失败，已打开安装包，请手动拖拽覆盖安装 (\(error.localizedDescription))"
                isDownloading = false
            }
        } catch {
            self.error = "下载更新失败: \(error.localizedDescription)"
            isDownloading = false
        }
    }
    
    private func downloadFile(from url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let config = URLSessionConfiguration.default
            let delegateQueue = OperationQueue()
            delegateQueue.maxConcurrentOperationCount = 1
            
            let session = URLSession(configuration: config, delegate: DownloadProgressDelegate(
                onProgress: { [weak self] progress in
                    Task { @MainActor in
                        self?.downloadProgress = progress
                    }
                },
                onComplete: { fileURL in
                    continuation.resume(returning: fileURL)
                },
                onError: { err in
                    continuation.resume(throwing: err)
                }
            ), delegateQueue: delegateQueue)
            
            let task = session.downloadTask(with: url)
            task.resume()
        }
    }
    
    private func findDmgAsset(from assets: [ReleaseAsset]) -> ReleaseAsset? {
        let matched = assets.first { asset in
            let name = asset.name.lowercased()
            if !name.hasSuffix(".dmg") { return false }
            
            #if arch(arm64)
            return name.contains("arm64") || name.contains("aarch64")
            #else
            return name.contains("x86_64") || name.contains("x64") || (!name.contains("arm64") && !name.contains("aarch64"))
            #endif
        }
        
        return matched ?? assets.first { $0.name.lowercased().hasSuffix(".dmg") }
    }
    
    private func silentInstall(dmgURL: URL) async throws {
        let mountPoint = try mountDMG(at: dmgURL)
        let appInDMG = try findAppBundle(in: mountPoint)
        
        let currentAppURL = Bundle.main.bundleURL
        let parentDirURL = currentAppURL.deletingLastPathComponent()
        let appName = currentAppURL.lastPathComponent
        let newAppURL = parentDirURL.appendingPathComponent("\(appName).new")
        
        if FileManager.default.fileExists(atPath: newAppURL.path) {
            try FileManager.default.removeItem(at: newAppURL)
        }
        
        try FileManager.default.copyItem(at: appInDMG, to: newAppURL)
        
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            EasyTierService.shared.forceStopAll {
                EasyTierHelperManager.shared.disconnect()
                continuation.resume()
            }
        }
        
        let tempDir = FileManager.default.temporaryDirectory
        let scriptURL = tempDir.appendingPathComponent("EasyTierManager-update.sh")
        
        let scriptContent = """
        #!/bin/bash
        sleep 3
        rm -rf "\(currentAppURL.path)"
        mv "\(newAppURL.path)" "\(currentAppURL.path)"
        rm -f "\(dmgURL.path)" 2>/dev/null
        hdiutil detach "\(mountPoint)" -force 2>/dev/null
        open "\(currentAppURL.path)"
        """
        
        try scriptContent.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptURL.path]
        
        try process.run()
        exit(0)
    }
    
    private func mountDMG(at url: URL) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = ["attach", "-nobrowse", "-readonly", "-plist", url.path]
        
        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        
        try process.run()
        let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "UpdateService", code: 1, userInfo: [NSLocalizedDescriptionKey: "hdiutil attach 失败，状态码 \(process.terminationStatus)"])
        }
        
        guard let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
              let systemEntities = plist["system-entities"] as? [[String: Any]] else {
            throw NSError(domain: "UpdateService", code: 2, userInfo: [NSLocalizedDescriptionKey: "解析 hdiutil plist 输出失败"])
        }
        
        for entity in systemEntities {
            if let mountPoint = entity["mount-point"] as? String {
                return mountPoint
            }
        }
        
        throw NSError(domain: "UpdateService", code: 3, userInfo: [NSLocalizedDescriptionKey: "未在 hdiutil plist 中找到挂载点"])
    }
    
    private func findAppBundle(in mountPoint: String) throws -> URL {
        let mountURL = URL(fileURLWithPath: mountPoint)
        let contents = try FileManager.default.contentsOfDirectory(at: mountURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
        if let appURL = contents.first(where: { $0.pathExtension == "app" }) {
            return appURL
        }
        throw NSError(domain: "UpdateService", code: 4, userInfo: [NSLocalizedDescriptionKey: "挂载的 DMG 中未找到 .app"])
    }
}

class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void
    let onComplete: (URL) -> Void
    let onError: (Error) -> Void
    private var hasResumed = false
    private let lock = NSLock()
    
    init(onProgress: @escaping (Double) -> Void, onComplete: @escaping (URL) -> Void, onError: @escaping (Error) -> Void) {
        self.onProgress = onProgress
        self.onComplete = onComplete
        self.onError = onError
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let progress = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        onProgress(progress)
    }
    
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        
        let tempDir = FileManager.default.temporaryDirectory
        let stableURL = tempDir.appendingPathComponent("EasyTierManager-downloaded-\(UUID().uuidString).dmg")
        do {
            if FileManager.default.fileExists(atPath: stableURL.path) {
                try? FileManager.default.removeItem(at: stableURL)
            }
            try FileManager.default.copyItem(at: location, to: stableURL)
            hasResumed = true
            onComplete(stableURL)
        } catch {
            hasResumed = true
            onError(error)
        }
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        defer { lock.unlock() }
        guard !hasResumed else { return }
        
        if let error = error {
            hasResumed = true
            onError(error)
        }
    }
}

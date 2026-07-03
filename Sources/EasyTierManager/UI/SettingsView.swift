import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var easyTierService: EasyTierService
    @EnvironmentObject var appSettings: AppSettings

    @StateObject private var appUpdateService = UpdateService.shared

    private static let updateCheckInterval: TimeInterval = 600

    @State private var isCheckingUpdate = false
    @State private var dismissWarningTask: Task<Void, Never>?
    @State private var checkUpdateTask: URLSessionDataTask?
    @State private var easytierVersion: String = ""
    @State private var appVersion: String = Bundle.main.versionStr
    @State private var appBuild: String = Bundle.main.buildStr

    @State private var updateAvailable = false
    @State private var latestVersion = ""
    @State private var isDownloading = false
    @State private var downloadError: String?
    @State private var lastCoreCheckTime: Date?

    @EnvironmentObject var helperManager: EasyTierHelperManager
    @State private var isInstallingHelper = false
    @State private var helperError: String?
    @State private var showHelperInfo = false

    private var helpersPath: String {
        Bundle.main.bundlePath + "/Contents/Helpers"
    }

    private var arch: String {
        #if arch(arm64)
        return "aarch64"
        #else
        return "x86_64"
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                privilegeHelperSection
                easyTierSection
                systemSection
                aboutSection

                HStack {
                    Spacer()
                    Text("EasyTierManager")
                        .font(.footnote)
                        .opacity(0.5)
                    Spacer()
                }
            }
            .padding()
        }
        .labelsHidden()
        .toggleStyle(.switch)
        .background(NSColor.background1.color)
        .onAppear(perform: detectEasytierVersion)
        .onDisappear {
            checkUpdateTask?.cancel()
            dismissWarningTask?.cancel()
        }
        .onChange(of: appSettings.toggleWarning) { newValue in
            if newValue != nil {
                dismissWarningTask?.cancel()
                dismissWarningTask = Task {
                    try? await Task.sleep(nanoseconds: 2_000_000_000)
                    if !Task.isCancelled {
                        appSettings.toggleWarning = nil
                    }
                }
            }
        }
    }

    private var privilegeHelperSection: some View {
        SettingsSection(title: "特权助手", trailing:
            Button {
                showHelperInfo = true
            } label: {
                Image(systemName: "questionmark.circle.fill")
                    .font(.caption)
                    .opacity(0.5)
            }
            .buttonStyle(.plain)
            .popover(isPresented: $showHelperInfo) {
                Text("特权助手需要 root 权限来运行 easytier-core，点击\"安装助手\"并输入密码")
                    .font(.caption)
                    .padding(12)
                    .frame(width: 260)
                    .fixedSize(horizontal: false, vertical: true)
            }
        ) {
            VStack(spacing: 0) {
                HelperStatusRow(
                    isConnected: helperManager.isHelperConnected,
                    isInstalling: isInstallingHelper,
                    onInstall: installHelper
                )
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                if let error = helperError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.orange)
                        Spacer()
                    }
                    .padding()
                }
            }
        }
    }

    private var easyTierSection: some View {
        SettingsSection(title: "EasyTier") {
            VStack(spacing: 0) {
                EasyTierVersionRow(
                    version: easytierVersion,
                    isChecking: isCheckingUpdate,
                    isDownloading: isDownloading,
                    updateAvailable: updateAvailable,
                    onCheckUpdate: checkForUpdates
                )
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                if isDownloading {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 16, height: 16)
                        Text("正在下载更新...")
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }

                if let error = downloadError {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                        Spacer()
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }

                if updateAvailable && !isDownloading {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                            .foregroundColor(.blue)
                        Text("版本 \(latestVersion) 可用")
                            .foregroundColor(.blue)
                        Spacer()
                        Button("下载并更新") {
                            downloadUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }
            }
        }
    }

    private var systemSection: some View {
        SettingsSection(title: "系统") {
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 0) {
                toggleRow(title: "开机启动", isOn: Binding(
                    get: { appSettings.isLaunchAtLogin },
                    set: { appSettings.setLaunchAtLogin($0) }
                ))
                .border(width: 1, edges: [.bottom, .trailing], color: NSColor.border2.color)

                toggleRow(title: "显示系统托盘", isOn: Binding(
                    get: { appSettings.showMenuBarIcon },
                    set: { appSettings.setMenuBarIcon($0) }
                ))
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                toggleRow(title: "显示程序坞图标", isOn: Binding(
                    get: { appSettings.showDockIcon },
                    set: { appSettings.setDockIcon($0) }
                ))
                .border(width: 1, edges: [.bottom, .trailing], color: NSColor.border2.color)

                toggleRow(title: "启动自动连接", isOn: Binding(
                    get: { appSettings.autoConnectOnLaunch },
                    set: { appSettings.setAutoConnectOnLaunch($0) }
                ))
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
            }

            if let warning = appSettings.toggleWarning {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.caption)
                    Text(warning)
                        .foregroundColor(.red)
                        .font(.caption)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .transition(.opacity)
            }
        }
    }

    private var aboutSection: some View {
        SettingsSection(title: "关于") {
            VStack(spacing: 0) {
                AppUpdateRow(
                    appVersion: appVersion,
                    updateService: appUpdateService,
                    onCheckUpdate: {
                        Task { await appUpdateService.checkForUpdates() }
                    }
                )
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                if appUpdateService.isDownloading {
                    DownloadProgressRow(progress: appUpdateService.downloadProgress)
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }

                if let error = appUpdateService.error {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.red)
                        Text(error)
                            .foregroundColor(.red)
                            .font(.caption)
                        Spacer()
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }

                if appUpdateService.updateAvailable && !appUpdateService.isDownloading {
                    UpdateAvailableRow(
                        latestVersion: appUpdateService.latestVersion,
                        onDownload: { Task { await appUpdateService.downloadAndInstall() } }
                    )
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }

                LinkRow(
                    title: "GitHub",
                    value: "github.com/begitcn/EasytierManager",
                    url: "https://github.com/begitcn/EasytierManager"
                )
                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                LinkRow(
                    title: "报告问题",
                    value: "github.com/begitcn/EasytierManager/issues",
                    url: "https://github.com/begitcn/EasytierManager/issues"
                )
            }
        }
    }

    private func installHelper() {
        isInstallingHelper = true
        helperError = nil

        Task {
            do {
                let savedConfigs = easyTierService.activeConfigs

                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    easyTierService.forceStopAll {
                        continuation.resume()
                    }
                }

                try await EasyTierHelperManager.shared.reinstallHelper()
                try? await Task.sleep(nanoseconds: 2_000_000_000)

                for configPath in savedConfigs {
                    try? await easyTierService.startNetwork(configPath: configPath)
                }
            } catch {
                helperError = error.localizedDescription
            }
            isInstallingHelper = false
        }
    }

    private func detectEasytierVersion() {
        let path = helpersPath + "/easytier-core"
        guard FileManager.default.isExecutableFile(atPath: path) else {
            easytierVersion = "未安装"
            return
        }

        Task {
            let version = await easyTierService.getCoreVersion()
            easytierVersion = version.isEmpty ? "未知" : version
        }
    }

    private func checkForUpdates() {
        if let lastCheck = lastCoreCheckTime, Date().timeIntervalSince(lastCheck) < Self.updateCheckInterval {
            return
        }

        isCheckingUpdate = true
        let urlString = "https://api.github.com/repos/EasyTier/EasyTier/releases/latest"

        guard let url = URL(string: urlString) else {
            isCheckingUpdate = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("EasyTierManager/\(Bundle.main.versionStr)", forHTTPHeaderField: "User-Agent")

        checkUpdateTask?.cancel()
        checkUpdateTask = URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                isCheckingUpdate = false

                if error != nil {
                    return
                }

                guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                    return
                }

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    return
                }

                latestVersion = tagName
                let current = easytierVersion
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                let latest = tagName.replacingOccurrences(of: "v", with: "")

                updateAvailable = current.compare(latest, options: .numeric) == .orderedAscending
                lastCoreCheckTime = Date()
            }
        }
        checkUpdateTask?.resume()
    }

    private func toggleRow(title: String, isOn: Binding<Bool>) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12))
            Spacer()
            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
                .scaleEffect(0.8)
                .fixedSize()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func downloadUpdate() {
        isDownloading = true
        downloadError = nil

        let version = latestVersion.replacingOccurrences(of: "v", with: "")
        let zipName = "easytier-macos-\(arch)-v\(version).zip"
        guard let url = URL(string: "https://github.com/EasyTier/EasyTier/releases/download/\(latestVersion)/\(zipName)") else {
            downloadError = "无效的下载地址"
            isDownloading = false
            return
        }

        Task {
            do {
                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("easytier-update-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let (tempFileURL, _) = try await URLSession.shared.download(from: url)
                let zipPath = tempDir.appendingPathComponent("easytier.zip")
                try FileManager.default.moveItem(at: tempFileURL, to: zipPath)

                try await Task.detached {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                    process.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                    try process.run()
                    process.waitUntilExit()
                }.value

                let extractedDir = tempDir.appendingPathComponent("easytier-macos-\(arch)")
                let helpersURL = URL(fileURLWithPath: helpersPath)

                let coreDst = helpersURL.appendingPathComponent("easytier-core")
                let cliDst = helpersURL.appendingPathComponent("easytier-cli")

                try? FileManager.default.removeItem(at: coreDst)
                try? FileManager.default.removeItem(at: cliDst)

                try FileManager.default.copyItem(
                    at: extractedDir.appendingPathComponent("easytier-core"), to: coreDst)
                try FileManager.default.copyItem(
                    at: extractedDir.appendingPathComponent("easytier-cli"), to: cliDst)

                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: coreDst.path)
                try FileManager.default.setAttributes(
                    [.posixPermissions: 0o755], ofItemAtPath: cliDst.path)

                await MainActor.run {
                    easyTierService.clearCoreVersionCache()
                    easytierVersion = "v\(version)"
                    updateAvailable = false
                    isDownloading = false
                }
            } catch {
                await MainActor.run {
                    downloadError = error.localizedDescription
                    isDownloading = false
                }
            }
        }
    }
}

// MARK: - Extracted Sub-views

private struct HelperStatusRow: View {
    let isConnected: Bool
    let isInstalling: Bool
    let onInstall: () -> Void

    var body: some View {
        HStack {
            Text("助手状态")
                .opacity(0.6)
                .frame(width: 140, alignment: .leading)

            if isConnected {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                Text("已连接")
            } else {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.red)
                Text("未连接")
            }

            Spacer()

            if isInstalling {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
            } else {
                Button("安装助手", action: onInstall)
                    .buttonStyle(.plain)
                    .foregroundColor(.accentColor)
                    .disabled(isInstalling)
            }
        }
        .padding()
    }
}

private struct EasyTierVersionRow: View {
    let version: String
    let isChecking: Bool
    let isDownloading: Bool
    let updateAvailable: Bool
    let onCheckUpdate: () -> Void

    var body: some View {
        HStack {
            Text("EasyTier 版本")
                .opacity(0.6)
                .frame(width: 140, alignment: .leading)

            Text(version.isEmpty ? "检测中..." : version)
                .font(.system(.body, design: .monospaced))

            if !version.isEmpty && !updateAvailable && !isDownloading {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("已是最新版本")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            Spacer()

            Button(action: onCheckUpdate) {
                if isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Text("检查更新")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(isChecking || isDownloading)
        }
        .padding()
    }
}

private struct AppUpdateRow: View {
    let appVersion: String
    let updateService: UpdateService
    let onCheckUpdate: () -> Void

    var body: some View {
        HStack {
            Text("应用版本")
                .opacity(0.6)
                .frame(width: 140, alignment: .leading)
            Text(appVersion)
                .font(.system(.body, design: .monospaced))

            if updateService.hasChecked && !updateService.updateAvailable && !updateService.isDownloading {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
                    .font(.caption)
                Text("已是最新版本")
                    .foregroundColor(.green)
                    .font(.caption)
            }

            Spacer()

            Button(action: onCheckUpdate) {
                if updateService.isChecking {
                    ProgressView()
                        .scaleEffect(0.7)
                        .frame(width: 16, height: 16)
                } else {
                    Text("检查更新")
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .disabled(updateService.isChecking || updateService.isDownloading)
        }
        .padding()
    }
}

private struct DownloadProgressRow: View {
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 16, height: 16)
                Text("正在下载并自动安装应用更新...")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                Spacer()
                Text("\(Int(progress * 100))%")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
        }
        .padding()
    }
}

private struct UpdateAvailableRow: View {
    let latestVersion: String
    let onDownload: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundColor(.blue)
            Text("最新版本 \(latestVersion) 可用")
                .foregroundColor(.blue)
                .font(.system(size: 12, weight: .semibold))
            Spacer()
            Button("下载并更新", action: onDownload)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding()
    }
}

private struct LinkRow: View {
    let title: String
    let value: String
    let url: String

    var body: some View {
        HStack {
            Text(title)
                .opacity(0.6)
                .frame(width: 140, alignment: .leading)
            Text(value)
                .foregroundColor(.accentColor)
            Spacer()
            Button(action: {
                if let url = URL(string: url) {
                    NSWorkspace.shared.open(url)
                }
            }) {
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
            .opacity(0.6)
        }
        .padding()
    }
}

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var easyTierService: EasyTierService
    @ObservedObject private var appSettings = AppSettings.shared
    @State private var isCheckingUpdate = false
    @State private var dismissWarningTask: Task<Void, Never>?
    @State private var checkUpdateTask: URLSessionDataTask?
    @State private var checkAppUpdateTask: URLSessionDataTask?

    @State private var easytierVersion: String = ""
    @State private var appVersion: String = Bundle.main.versionStr
    @State private var appBuild: String = Bundle.main.buildStr

    @State private var updateAvailable = false
    @State private var latestVersion = ""
    @State private var isDownloading = false
    @State private var downloadError: String?

    @State private var isCheckingAppUpdate = false
    @State private var appUpdateAvailable = false
    @State private var appLatestVersion = ""
    @State private var isAppDownloading = false
    @State private var appDownloadError: String?

    @ObservedObject private var helperManager = EasyTierHelperManager.shared
    @State private var isInstallingHelper = false
    @State private var helperError: String?

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
                SettingsSection(title: "特权助手") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("助手状态")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)

                            if helperManager.isHelperConnected {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已连接")
                            } else {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                                Text("未连接")
                            }

                            Spacer()

                            if isInstallingHelper {
                                ProgressView()
                                    .scaleEffect(0.7)
                                    .frame(width: 16, height: 16)
                            } else {
                                Button("安装助手") {
                                    installHelper()
                                }
                                .buttonStyle(.plain)
                                .foregroundColor(.accentColor)
                                .disabled(isInstallingHelper)
                            }
                        }
                        .padding()
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
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }

                        HStack {
                            Text("说明")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)
                            Text("特权助手需要 root 权限来运行 easytier-core，点击\"安装助手\"并输入密码")
                                .font(.caption)
                                .opacity(0.6)
                            Spacer()
                        }
                        .padding()
                    }
                }

                SettingsSection(title: "EasyTier") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("EasyTier 版本")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)

                            Text(easytierVersion.isEmpty ? "检测中..." : easytierVersion)
                                .font(.system(.body, design: .monospaced))

                            Spacer()

                            Button(action: checkForUpdates) {
                                if isCheckingUpdate {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Text("检查更新")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .disabled(isCheckingUpdate || isDownloading)
                        }
                        .padding()
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

                        if !easytierVersion.isEmpty && !updateAvailable && !isDownloading {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已是最新版本")
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            .padding()
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                    }
                }

                SettingsSection(title: "系统") {
                    VStack(spacing: 0) {
                        HStack {
                            Toggle("", isOn: Binding(
                                get: { appSettings.isLaunchAtLogin },
                                set: { appSettings.setLaunchAtLogin($0) }
                            ))
                            Text("开机启动")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Toggle("", isOn: Binding(
                                get: { appSettings.showMenuBarIcon },
                                set: { appSettings.setMenuBarIcon($0) }
                            ))
                            Text("显示系统托盘")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Toggle("", isOn: Binding(
                                get: { appSettings.showDockIcon },
                                set: { appSettings.setDockIcon($0) }
                            ))
                            Text("显示程序坞图标")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

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
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            .transition(.opacity)
                        }

                        HStack {
                            Toggle("", isOn: Binding(
                                get: { appSettings.autoConnectOnLaunch },
                                set: { appSettings.setAutoConnectOnLaunch($0) }
                            ))
                            Text("启动自动连接")
                            Spacer()
                        }
                        .padding()
                    }
                }

                SettingsSection(title: "关于") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("应用版本")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)
                            Text(appVersion)
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                            Button(action: checkAppUpdates) {
                                if isCheckingAppUpdate {
                                    ProgressView()
                                        .scaleEffect(0.7)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Text("检查更新")
                                }
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                            .disabled(isCheckingAppUpdate || isAppDownloading)
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        if isAppDownloading {
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

                        if let error = appDownloadError {
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

                        if appUpdateAvailable && !isAppDownloading {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.blue)
                                Text("版本 \(appLatestVersion) 可用")
                                    .foregroundColor(.blue)
                                Spacer()
                                Button("下载并更新") {
                                    downloadAppUpdate()
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding()
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }

                        if !isCheckingAppUpdate && !appUpdateAvailable && !isAppDownloading && appDownloadError == nil {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("已是最新版本")
                                    .foregroundColor(.green)
                                Spacer()
                            }
                            .padding()
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }

                        HStack {
                            Text("GitHub")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)
                            Text("github.com/begitcn/EasytierManager")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button(action: {
                                if let url = URL(string: "https://github.com/begitcn/EasytierManager") {
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
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Text("报告问题")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)
                            Text("github.com/begitcn/EasytierManager/issues")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button(action: {
                                if let url = URL(string: "https://github.com/begitcn/EasytierManager/issues") {
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

                HStack {
                    Spacer()
                    Text("EasyTier")
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
            checkAppUpdateTask?.cancel()
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

    private func installHelper() {
        isInstallingHelper = true
        helperError = nil

        Task {
            do {
                try await EasyTierHelperManager.shared.reinstallHelper()
            } catch {
                helperError = error.localizedDescription
            }
            isInstallingHelper = false
        }
    }

    private func detectEasytierVersion() {
        let corePath = helpersPath + "/easytier-core"
        guard FileManager.default.isExecutableFile(atPath: corePath) else {
            easytierVersion = "未安装"
            return
        }

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
                .dropFirst()
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            easytierVersion = version.isEmpty ? "未知" : version
        } catch {
            easytierVersion = "未知"
        }
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        let urlString = "https://api.github.com/repos/EasyTier/EasyTier/releases/latest"

        guard let url = URL(string: urlString) else {
            isCheckingUpdate = false
            return
        }

        checkUpdateTask?.cancel()
        checkUpdateTask = URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isCheckingUpdate = false

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
            }
        }
        checkUpdateTask?.resume()
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
                let (data, _) = try await URLSession.shared.data(from: url)

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("easytier-update-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let zipPath = tempDir.appendingPathComponent("easytier.zip")
                try data.write(to: zipPath)

                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                process.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                try process.run()
                process.waitUntilExit()

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

    private func checkAppUpdates() {
        isCheckingAppUpdate = true
        appUpdateAvailable = false
        appDownloadError = nil
        let urlString = "https://api.github.com/repos/begitcn/EasyTierManager/releases/latest"

        guard let url = URL(string: urlString) else {
            isCheckingAppUpdate = false
            return
        }

        checkAppUpdateTask?.cancel()
        checkAppUpdateTask = URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isCheckingAppUpdate = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    return
                }

                appLatestVersion = tagName
                let current = appVersion.replacingOccurrences(of: "v", with: "")
                let latest = tagName.replacingOccurrences(of: "v", with: "")

                appUpdateAvailable = current.compare(latest, options: .numeric) == .orderedAscending
            }
        }
        checkAppUpdateTask?.resume()
    }

    private func downloadAppUpdate() {
        isAppDownloading = true
        appDownloadError = nil

        let version = appLatestVersion.replacingOccurrences(of: "v", with: "")
        let zipName = "EasyTierManager_v\(version).zip"
        guard let url = URL(string: "https://github.com/begitcn/EasyTierManager/releases/download/\(appLatestVersion)/\(zipName)") else {
            appDownloadError = "无效的下载地址"
            isAppDownloading = false
            return
        }

        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: url)

                let tempDir = FileManager.default.temporaryDirectory
                    .appendingPathComponent("easytiermanager-update-\(UUID().uuidString)")
                defer { try? FileManager.default.removeItem(at: tempDir) }

                try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

                let zipPath = tempDir.appendingPathComponent(zipName)
                try data.write(to: zipPath)

                let unzip = Process()
                unzip.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
                unzip.arguments = ["-o", zipPath.path, "-d", tempDir.path]
                try unzip.run()
                unzip.waitUntilExit()

                guard unzip.terminationStatus == 0 else {
                    throw NSError(domain: "update", code: -1, userInfo: [NSLocalizedDescriptionKey: "解压失败"])
                }

                let appBundleName = "EasyTierManager.app"
                let newAppPath = tempDir.appendingPathComponent(appBundleName).path
                guard FileManager.default.fileExists(atPath: newAppPath) else {
                    throw NSError(domain: "update", code: -2, userInfo: [NSLocalizedDescriptionKey: "未找到应用包"])
                }

                let currentAppPath = Bundle.main.bundlePath

                let script = """
                #!/bin/bash
                sleep 1
                rm -rf "\(currentAppPath)"
                cp -R "\(newAppPath)" "\(currentAppPath)"
                chmod +x "\(currentAppPath)/Contents/MacOS/EasyTierManager"
                open "\(currentAppPath)"
                """

                let scriptPath = tempDir.appendingPathComponent("updater.sh")
                try script.write(to: scriptPath, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptPath.path)

                let updater = Process()
                updater.executableURL = URL(fileURLWithPath: "/bin/bash")
                updater.arguments = [scriptPath.path]
                try updater.run()

                await MainActor.run {
                    isAppDownloading = false
                }

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
            } catch {
                await MainActor.run {
                    appDownloadError = error.localizedDescription
                    isAppDownloading = false
                }
            }
        }
    }
}
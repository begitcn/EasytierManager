import SwiftUI

struct SettingsView: View {
    @State private var isLaunchAtLogin = false
    @State private var showMenuBarIcon = true
    @State private var showDockIcon = true
    @State private var autoConnectOnLaunch = false
    @State private var isCheckingUpdate = false

    @State private var easytierVersion: String = "1.0.0"
    @State private var appVersion: String = Bundle.main.shortVersion
    @State private var appBuild: String = Bundle.main.buildStr

    @State private var updateAvailable = false
    @State private var latestVersion = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "EasyTier") {
                    VStack(spacing: 0) {
                        HStack {
                            Text("EasyTier 版本")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)

                            Text(easytierVersion)
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
                            .disabled(isCheckingUpdate)
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        if updateAvailable {
                            HStack {
                                Image(systemName: "arrow.down.circle.fill")
                                    .foregroundColor(.blue)
                                Text("版本 \(latestVersion) 可用")
                                    .foregroundColor(.blue)
                                Spacer()
                                Button("下载") {
                                    if let url = URL(string: "https://github.com/EasyTier/EasyTier/releases") {
                                        NSWorkspace.shared.open(url)
                                    }
                                }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.small)
                            }
                            .padding()
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                    }
                }

                SettingsSection(title: "系统") {
                    VStack(spacing: 0) {
                        HStack {
                            Toggle("", isOn: $isLaunchAtLogin)
                            Text("开机启动")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Toggle("", isOn: $showMenuBarIcon)
                            Text("显示系统托盘")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Toggle("", isOn: $showDockIcon)
                            Text("显示程序坞图标")
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Toggle("", isOn: $autoConnectOnLaunch)
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
                            Text("\(appVersion) (\(appBuild))")
                                .font(.system(.body, design: .monospaced))
                            Spacer()
                        }
                        .padding()
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        HStack {
                            Text("GitHub")
                                .opacity(0.6)
                                .frame(width: 140, alignment: .leading)
                            Text("github.com/EasyTier/EasyTier")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button(action: {
                                if let url = URL(string: "https://github.com/EasyTier/EasyTier") {
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
                            Text("github.com/EasyTier/EasyTier/issues")
                                .foregroundColor(.accentColor)
                            Spacer()
                            Button(action: {
                                if let url = URL(string: "https://github.com/EasyTier/EasyTier/issues") {
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
    }

    private func checkForUpdates() {
        isCheckingUpdate = true
        let urlString = "https://api.github.com/repos/EasyTier/EasyTier/releases/latest"

        guard let url = URL(string: urlString) else {
            isCheckingUpdate = false
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                isCheckingUpdate = false

                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let tagName = json["tag_name"] as? String else {
                    return
                }

                latestVersion = tagName
                let current = easytierVersion
                let latest = tagName.replacingOccurrences(of: "v", with: "")

                updateAvailable = current.compare(latest, options: .numeric) == .orderedAscending
            }
        }.resume()
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @State private var networks: [VirtualNetwork] = []
    @State private var selectedNetwork: VirtualNetwork.ID?
    @State private var showAddSheet = false
    @State private var editingNetwork: VirtualNetwork?

    var body: some View {
        HSplitView {
            VStack(spacing: 0) {
                List(selection: $selectedNetwork) {
                    ForEach(networks) { network in
                        HStack {
                            Image(systemName: network.status == .connected ? "circle.fill" : "circle")
                                .foregroundColor(network.status == .connected ? .green : network.status == .connecting ? .orange : .secondary)
                                .font(.system(size: 10))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(network.name)
                                    .fontWeight(.medium)
                                Text(network.configPath)
                                    .font(.caption)
                                    .opacity(0.6)
                                    .lineLimit(1)
                            }

                            Spacer()

                            Text(networkStatusText(network.status))
                                .font(.caption)
                                .opacity(0.5)
                        }
                        .padding(.vertical, 4)
                        .tag(network.id)
                    }
                    .onDelete(perform: deleteNetworks)
                }
                .listStyle(.plain)

                Divider()

                HStack {
                    Button(action: { showAddSheet = true }) {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .padding(6)

                    Button(action: {
                        guard let id = selectedNetwork,
                              let index = networks.firstIndex(where: { $0.id == id }) else { return }
                        editingNetwork = networks[index]
                    }) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .disabled(selectedNetwork == nil)

                    Spacer()

                    Button(action: toggleConnection) {
                        Image(systemName: isSelectedConnected ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.plain)
                    .padding(6)
                    .disabled(selectedNetwork == nil)
                }
                .padding(.horizontal, 8)
                .frame(height: 36)
            }
            .frame(minWidth: 250, maxWidth: 350)

            if let id = selectedNetwork, let network = networks.first(where: { $0.id == id }) {
                networkDetailView(network)
            } else {
                emptySelectionView
            }
        }
        .background(NSColor.background1.color)
        .sheet(isPresented: $showAddSheet) {
            NetworkEditView { newNetwork in
                networks.append(newNetwork)
            }
        }
        .sheet(item: $editingNetwork) { network in
            NetworkEditView(network: network) { updated in
                if let index = networks.firstIndex(where: { $0.id == updated.id }) {
                    networks[index] = updated
                }
            }
        }
    }

    private func networkStatusText(_ status: VirtualNetwork.ConnectionStatus) -> String {
        switch status {
        case .connected: return "已连接"
        case .connecting: return "连接中"
        case .disconnected: return "未连接"
        case .error: return "错误"
        }
    }

    private var isSelectedConnected: Bool {
        guard let id = selectedNetwork,
              let network = networks.first(where: { $0.id == id }) else { return false }
        return network.status == .connected
    }

    private var emptySelectionView: some View {
        VStack(spacing: 12) {
            Image(systemName: "network")
                .font(.system(size: 48))
                .opacity(0.3)
            Text("选择一个网络")
                .font(.headline)
                .opacity(0.5)
            Text("从列表中选择一个虚拟网络查看详情")
                .font(.caption)
                .opacity(0.3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func networkDetailView(_ network: VirtualNetwork) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "网络信息") {
                    VStack(spacing: 0) {
                        detailRow(label: "名称", value: network.name)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        detailRow(label: "配置路径", value: network.configPath)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        detailRow(label: "状态", value: networkStatusText(network.status))
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        detailRow(label: "自动连接", value: network.isAutoConnect ? "是" : "否")
                    }
                }

                SettingsSection(title: "操作") {
                    VStack(spacing: 0) {
                        Button(action: toggleConnection) {
                            HStack {
                                Image(systemName: isSelectedConnected ? "stop.fill" : "play.fill")
                                Text(isSelectedConnected ? "断开" : "连接")
                                Spacer()
                            }
                        }
                        .buttonStyle(SectionButtonStyle())
                    }
                }
            }
            .padding()
        }
    }

    @ViewBuilder
    private func detailRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 100, alignment: .leading)
            Text(value)
            Spacer()
        }
        .padding()
    }

    private func toggleConnection() {
        guard let id = selectedNetwork,
              let index = networks.firstIndex(where: { $0.id == id }) else { return }
        networks[index].status = networks[index].status == .connected ? .disconnected : .connected
    }

    private func deleteNetworks(at offsets: IndexSet) {
        networks.remove(atOffsets: offsets)
    }
}

struct NetworkEditView: View {
    @Environment(\.dismiss) var dismiss

    var network: VirtualNetwork?
    let onSave: (VirtualNetwork) -> Void

    @State private var name: String = ""
    @State private var configPath: String = ""
    @State private var isAutoConnect: Bool = false

    init(network: VirtualNetwork? = nil, onSave: @escaping (VirtualNetwork) -> Void) {
        self.network = network
        self.onSave = onSave
        _name = State(initialValue: network?.name ?? "")
        _configPath = State(initialValue: network?.configPath ?? "")
        _isAutoConnect = State(initialValue: network?.isAutoConnect ?? false)
    }

    var body: some View {
        VStack(spacing: 16) {
            Text(network == nil ? "添加网络" : "编辑网络")
                .font(.headline)

            VStack(alignment: .leading, spacing: 8) {
                Text("名称:")
                    .opacity(0.6)
                TextField("网络名称", text: $name)
                    .textFieldStyle(.roundedBorder)

                Text("配置路径:")
                    .opacity(0.6)
                HStack {
                    TextField("/path/to/config.toml", text: $configPath)
                        .textFieldStyle(.roundedBorder)
                    Button("浏览...") {
                        let panel = NSOpenPanel()
                        panel.canChooseFiles = true
                        panel.canChooseDirectories = false
                        panel.allowedContentTypes = [.plainText, .yaml, .init(filenameExtension: "toml") ?? .plainText]
                        if panel.runModal() == .OK, let url = panel.url {
                            configPath = url.path
                        }
                    }
                }

                Toggle("启动时自动连接", isOn: $isAutoConnect)
            }

            HStack {
                Button("取消") {
                    dismiss()
                }
                Button("保存") {
                    let newNetwork = VirtualNetwork(
                        id: network?.id ?? UUID(),
                        name: name,
                        configPath: configPath,
                        isAutoConnect: isAutoConnect,
                        status: network?.status ?? .disconnected
                    )
                    onSave(newNetwork)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || configPath.isEmpty)
            }
        }
        .padding()
        .frame(width: 400)
    }
}

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? .plainText
    }
}

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionsView: View {
    @EnvironmentObject var networkStore: NetworkStore
    @EnvironmentObject var easyTierService: EasyTierService
    @State private var selectedNetwork: VirtualNetwork.ID?
    @State private var connectingNetworkId: UUID?
    @State private var errorMessage: String?
    @State private var showError = false

    @State private var isCreating = false
    @State private var editingNetwork: VirtualNetwork?
    @State private var editConfig = EasyTierConfig()
    @State private var editAutoConnect = false
    @State private var peerUri = ""
    @State private var detailConfig: EasyTierConfig?

    private var isEditing: Bool { isCreating || editingNetwork != nil }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button(action: connectAll) {
                    Label(allConnected ? "全部断开" : "全部连接", systemImage: allConnected ? "stop.fill" : "play.fill")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(networkStore.networks.isEmpty || connectingNetworkId != nil)

                Button(action: exportAll) {
                    Label("全部导出", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(networkStore.networks.isEmpty)
            }
            .padding(.horizontal, 12)
            .frame(height: 32)
            .border(width: 1, edges: [.bottom], color: NSColor.border.color)

            HStack(spacing: 0) {
                listSection
                    .frame(width: 250)

                rightPanel
                    .frame(maxWidth: .infinity)
            }
        }
        .background(NSColor.background1.color)
        .onAppear {
            if selectedNetwork == nil, let first = networkStore.networks.first {
                selectedNetwork = first.id
            }
        }
        .onChange(of: networkStore.networks.count) { _ in
            if selectedNetwork == nil, let first = networkStore.networks.first {
                selectedNetwork = first.id
            }
        }
        .onChange(of: selectedNetwork) { _ in reloadDetailConfig() }
        .confirmationDialog("确认删除", isPresented: .init(
            get: { deleteConfirmationTarget != nil },
            set: { if !$0 { deleteConfirmationTarget = nil } }
        )) {
            if let network = deleteConfirmationTarget {
                Button("删除", role: .destructive) {
                    deleteNetwork(network)
                }
                Button("取消", role: .cancel) {
                    deleteConfirmationTarget = nil
                }
            }
        } message: {
            if let network = deleteConfirmationTarget {
                Text("确定要删除「\(network.name)」吗？此操作不可恢复。")
            }
        }
        .alert("错误", isPresented: $showError) {
            Button("确定", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "未知错误")
        }
    }

    private var listSection: some View {
        VStack(spacing: 0) {
            List(selection: $selectedNetwork) {
                ForEach(networkStore.networks) { network in
                    HStack {
                        Image(systemName: statusIcon(network.status))
                            .foregroundColor(statusColor(network.status))
                            .font(.system(size: 10))

                        Text(network.name)
                            .fontWeight(.medium)

                        Spacer()

                        if connectingNetworkId == network.id {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            Text(networkStatusText(network.status))
                                .font(.caption)
                                .foregroundColor(statusColor(network.status))
                        }
                    }
                    .padding(.vertical, 4)
                    .tag(network.id)
                }
                .onDelete(perform: deleteNetworks)
            }
            .listStyle(.plain)

            Divider()

            HStack(spacing: 0) {
                Button(action: startCreating) {
                    Image(systemName: "plus")
                        .font(.system(size: 16))
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .frame(maxWidth: .infinity)

                Button(action: startEditing) {
                    Image(systemName: "pencil")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedNetwork == nil || isEditing)

                Button(action: confirmDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedNetwork == nil || isEditing)

                Button(action: toggleConnection) {
                    Image(systemName: isSelectedConnected ? "stop.fill" : "play.fill")
                        .font(.system(size: 16))
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .frame(maxWidth: .infinity)
                .disabled(selectedNetwork == nil || connectingNetworkId != nil || isEditing)
            }
            .padding(.horizontal, 12)
            .frame(height: 48)
        }
    }

    @ViewBuilder
    private var rightPanel: some View {
        if isEditing {
            configEditorView
        } else if let id = selectedNetwork, let network = networkStore.networks.first(where: { $0.id == id }) {
            networkDetailView(network)
        } else {
            emptySelectionView
        }
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
                        coloredStatusRow(label: "状态", network: network)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        detailRow(label: "自动连接", value: network.isAutoConnect ? "是" : "否")
                    }
                }

                if let config = detailConfig {
                    SettingsSection(title: "配置") {
                        VStack(spacing: 0) {
                            detailRow(label: "主机名", value: config.hostname)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            detailRow(label: "实例名称", value: config.instanceName)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            if config.dhcp {
                                detailRow(label: "IPv4", value: "自动获取 (DHCP)")
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            } else {
                                detailRowWithCopy(label: "IPv4", value: config.ipv4, copyValue: config.ipv4)
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            }
                            detailRow(label: "网络标识", value: config.networkName)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            if let peer = config.peers.first {
                                detailRow(label: "对等节点", value: peer)
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            }
                            if !config.listeners.isEmpty {
                                HStack(alignment: .top) {
                                    Text("监听地址")
                                        .opacity(0.6)
                                        .frame(width: 100, alignment: .leading)
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(config.listeners, id: \.self) { addr in
                                            Text(addr)
                                        }
                                    }
                                    Spacer()
                                }
                                .padding()
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            }
                        }
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
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        Button(action: { exportConfig(network) }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("导出配置")
                                Spacer()
                            }
                        }
                        .buttonStyle(SectionButtonStyle())
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        Button(action: { confirmDeleteNetwork(network) }) {
                            HStack {
                                Image(systemName: "trash")
                                    .foregroundColor(.red)
                                Text("删除")
                                    .foregroundColor(.red)
                                Spacer()
                            }
                        }
                        .buttonStyle(SectionButtonStyle())
                    }
                }
            }
            .padding()
        }
        .id(network.id)
    }

    private func reloadDetailConfig() {
        guard let id = selectedNetwork,
              let network = networkStore.networks.first(where: { $0.id == id }) else {
            detailConfig = nil
            return
        }
        let url = URL(fileURLWithPath: network.configPath)
        if FileManager.default.fileExists(atPath: url.path) {
            detailConfig = try? EasyTierConfig.parse(from: url)
        } else {
            detailConfig = nil
        }
    }

    @ViewBuilder
    private func coloredStatusRow(label: String, network: VirtualNetwork) -> some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 100, alignment: .leading)
            Text(networkStatusText(network.status))
                .foregroundColor(statusColor(network.status))
            Spacer()
        }
        .padding()
    }

    private var configEditorView: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text(editingNetwork != nil ? "编辑网络" : "新建网络")
                        .font(.headline)
                    Spacer()
                    Button(action: importConfig) {
                        Label("导入配置", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsSection(title: "基础设置") {
                    VStack(spacing: 0) {
                        formField(label: "主机名", value: $editConfig.hostname)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        formField(label: "实例名称", value: $editConfig.instanceName)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        dhcpPicker
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        if !editConfig.dhcp {
                            formField(label: "IPv4", value: $editConfig.ipv4)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                    }
                }

                SettingsSection(title: "网络标识") {
                    VStack(spacing: 0) {
                        formField(label: "网络名称", value: $editConfig.networkName)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        formField(label: "网络密钥", value: $editConfig.networkSecret)
                    }
                }

                SettingsSection(title: "对等节点") {
                    VStack(spacing: 0) {
                        formField(label: "地址", value: $peerUri)
                    }
                }

                SettingsSection(title: "高级设置") {
                    VStack(spacing: 0) {
                        formToggle(label: "接受 DNS", value: $editConfig.acceptDns)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        formToggle(label: "延迟优先", value: $editConfig.latencyFirst)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        formToggle(label: "私有模式", value: $editConfig.privateMode)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        formToggle(label: "启动自动连接", value: $editAutoConnect)
                    }
                }

                SettingsSection(title: "监听地址") {
                    VStack(spacing: 0) {
                        if editConfig.listeners.isEmpty {
                            emptyHint("添加监听地址以接受连接")
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                        ForEach(editConfig.listeners.indices, id: \.self) { index in
                            HStack {
                                TextField("tcp://0.0.0.0:11010", text: $editConfig.listeners[index])
                                    .textFieldStyle(.plain)
                                Button(action: { editConfig.listeners.remove(at: index) }) {
                                    Image(systemName: "xmark")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .buttonStyle(.plain)
                                .opacity(0.4)
                            }
                            .padding()
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                        Button(action: { editConfig.listeners.append("") }) {
                            HStack {
                                Image(systemName: "plus")
                                Text("添加监听地址")
                                Spacer()
                            }
                            .padding()
                        }
                        .buttonStyle(.plain)
                    }
                }

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Button(action: saveEditor) {
                            Label("保存", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(editConfig.instanceName.isEmpty || (!editConfig.dhcp && editConfig.ipv4.isEmpty))
                    }

                    Button(action: cancelEditor) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
            .padding()
        }
    }

    private var dhcpPicker: some View {
        HStack {
            Text("DHCP")
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Picker("", selection: $editConfig.dhcp) {
                Text("自动获取").tag(true)
                Text("手动设置").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)

        }
        .padding()
    }

    private func importConfig() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.plainText, .yaml, .init(filenameExtension: "toml") ?? .plainText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard var config = try? EasyTierConfig.parse(from: url) else {
            errorMessage = "无法解析配置文件"
            showError = true
            return
        }
        if config.listeners.isEmpty {
            config.listeners = defaultListeners()
        }
        editConfig = config
        editAutoConnect = true
        peerUri = config.peers.first ?? ""
    }

    private func saveEditor() {
        let networkId = editingNetwork?.id ?? UUID()
        let configURL = EasyTierConfig.url(for: networkId)
        editConfig.peers = peerUri.isEmpty ? [] : [peerUri]
        if let conflict = checkPortConflict(excluding: editingNetwork?.id) {
            errorMessage = "端口 \(conflict) 已被其他网络占用"
            showError = true
            return
        }
        do {
            try editConfig.save(to: configURL)
            let network = VirtualNetwork(
                id: networkId,
                name: editConfig.instanceName,
                configPath: configURL.path,
                isAutoConnect: editAutoConnect,
                status: editingNetwork?.status ?? .disconnected
            )
            if editingNetwork != nil {
                networkStore.updateNetwork(network)
            } else {
                networkStore.addNetwork(network)
            }
            selectedNetwork = network.id
            cancelEditor()
        } catch {
            errorMessage = error.localizedDescription
            showError = true
        }
    }

    private func startCreating() {
        isCreating = true
        editingNetwork = nil
        selectedNetwork = nil
        editConfig = EasyTierConfig()
        editConfig.listeners = defaultListeners()
        editAutoConnect = true
        peerUri = "tcp://225284.xyz:11010"
    }

    private func startEditing() {
        guard let id = selectedNetwork, let network = networkStore.networks.first(where: { $0.id == id }) else { return }
        isCreating = false
        editingNetwork = network
        editAutoConnect = network.isAutoConnect
        if let config = try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath)) {
            editConfig = config
        } else {
            editConfig = EasyTierConfig()
        }
        peerUri = editConfig.peers.first ?? ""
    }

    private func cancelEditor() {
        isCreating = false
        editingNetwork = nil
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

    @State private var copiedIPv4 = false

    @ViewBuilder
    private func detailRowWithCopy(label: String, value: String, copyValue: String) -> some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button(action: {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(copyValue, forType: .string)
                copiedIPv4 = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                    copiedIPv4 = false
                }
            }) {
                Image(systemName: copiedIPv4 ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(copiedIPv4 ? .green : .primary)
                    .opacity(0.4)
            }
            .buttonStyle(.plain)
            .help("复制")
        }
        .padding()
    }

    @ViewBuilder
    private func formField(label: String, value: Binding<String>) -> some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            TextField("", text: value)
                .textFieldStyle(.plain)
            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private func formToggle(label: String, value: Binding<Bool>) -> some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Toggle("", isOn: value)
        }
        .padding()
    }

    @ViewBuilder
    private func emptyHint(_ text: String) -> some View {
        HStack {
            Text(text)
                .font(.caption)
                .opacity(0.4)
            Spacer()
        }
        .padding()
    }

    private func statusIcon(_ status: VirtualNetwork.ConnectionStatus) -> String {
        switch status {
        case .connected: return "circle.fill"
        case .connecting: return "circle.lefthalf.filled"
        case .disconnected: return "circle"
        case .error: return "xmark.circle"
        }
    }

    private func statusColor(_ status: VirtualNetwork.ConnectionStatus) -> Color {
        switch status {
        case .connected: return .green
        case .connecting: return .orange
        case .disconnected: return .secondary
        case .error: return .red
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
              let network = networkStore.networks.first(where: { $0.id == id }) else { return false }
        return network.status == .connected
    }

    private func toggleConnection() {
        guard let id = selectedNetwork,
              let network = networkStore.networks.first(where: { $0.id == id }) else { return }

        connectingNetworkId = id

        if network.status == .connected {
            Task {
                networkStore.updateStatus(id: id, status: .connecting)
                do {
                    try await easyTierService.stopNetwork(configPath: network.configPath)
                    networkStore.updateStatus(id: id, status: .disconnected)
                } catch {
                    networkStore.updateStatus(id: id, status: .error)
                    errorMessage = error.localizedDescription
                    showError = true
                }
                connectingNetworkId = nil
            }
        } else {
            Task {
                networkStore.updateStatus(id: id, status: .connecting)
                do {
                    try await easyTierService.startNetwork(configPath: network.configPath)
                    networkStore.updateStatus(id: id, status: .connected)
                } catch {
                    networkStore.updateStatus(id: id, status: .error)
                    errorMessage = error.localizedDescription
                    showError = true
                }
                connectingNetworkId = nil
            }
        }
    }

    @State private var deleteConfirmationTarget: VirtualNetwork?

    private func confirmDelete() {
        guard let id = selectedNetwork,
              let network = networkStore.networks.first(where: { $0.id == id }) else { return }
        confirmDeleteNetwork(network)
    }

    private func confirmDeleteNetwork(_ network: VirtualNetwork) {
        deleteConfirmationTarget = network
    }

    private func deleteNetwork(_ network: VirtualNetwork) {
        if network.status == .connected {
            Task {
                try? await easyTierService.stopNetwork(configPath: network.configPath)
            }
        }
        let configURL = URL(fileURLWithPath: network.configPath)
        try? FileManager.default.removeItem(at: configURL)
        networkStore.removeNetwork(id: network.id)
        if selectedNetwork == network.id {
            selectedNetwork = nil
        }
        if isEditing {
            cancelEditor()
        }
    }

    private func deleteNetworks(at offsets: IndexSet) {
        for index in offsets {
            let network = networkStore.networks[index]
            if network.status == .connected {
                Task {
                    try? await easyTierService.stopNetwork(configPath: network.configPath)
                }
            }
            let configURL = URL(fileURLWithPath: network.configPath)
            try? FileManager.default.removeItem(at: configURL)
        }
        networkStore.networks.remove(atOffsets: offsets)
        networkStore.save()
        if selectedNetwork != nil, !networkStore.networks.contains(where: { $0.id == selectedNetwork }) {
            selectedNetwork = nil
        }
        if isEditing {
            cancelEditor()
        }
    }

    private var allConnected: Bool {
        !networkStore.networks.isEmpty && networkStore.networks.allSatisfy { $0.status == .connected }
    }

    private func connectAll() {
        guard !networkStore.networks.isEmpty else { return }
        Task {
            if allConnected {
                for network in networkStore.networks where network.status == .connected {
                    networkStore.updateStatus(id: network.id, status: .connecting)
                    try? await easyTierService.stopNetwork(configPath: network.configPath)
                    networkStore.updateStatus(id: network.id, status: .disconnected)
                }
            } else {
                for network in networkStore.networks where network.status == .disconnected {
                    networkStore.updateStatus(id: network.id, status: .connecting)
                    do {
                        try await easyTierService.startNetwork(configPath: network.configPath)
                        networkStore.updateStatus(id: network.id, status: .connected)
                    } catch {
                        networkStore.updateStatus(id: network.id, status: .error)
                    }
                }
            }
        }
    }

    private func exportAll() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "选择导出目录"
        guard panel.runModal() == .OK, let dir = panel.url else { return }
        for network in networkStore.networks {
            let src = URL(fileURLWithPath: network.configPath)
            let dst = dir.appendingPathComponent(src.lastPathComponent)
            try? FileManager.default.copyItem(at: src, to: dst)
        }
    }

    private func defaultListeners() -> [String] {
        let usedPorts = allUsedPorts()
        var port = 11010
        while usedPorts.contains(port) {
            port += 1
        }
        return ["tcp://0.0.0.0:\(port)", "udp://0.0.0.0:\(port)"]
    }

    private func allUsedPorts() -> Set<Int> {
        var ports = Set<Int>()
        for network in networkStore.networks {
            guard let config = try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath)) else {
                continue
            }
            for listener in config.listeners {
                if let port = parsePort(from: listener) {
                    ports.insert(port)
                }
            }
        }
        return ports
    }

    private func parsePort(from listener: String) -> Int? {
        guard let colon = listener.lastIndex(of: ":"),
              let port = Int(listener[listener.index(after: colon)...]) else {
            return nil
        }
        return port
    }

    private func checkPortConflict(excluding networkId: UUID?) -> Int? {
        var myPorts = Set<Int>()
        for listener in editConfig.listeners {
            if let port = parsePort(from: listener) {
                myPorts.insert(port)
            }
        }
        for network in networkStore.networks {
            if network.id == networkId { continue }
            guard let config = try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath)) else {
                continue
            }
            for listener in config.listeners {
                if let port = parsePort(from: listener), myPorts.contains(port) {
                    return port
                }
            }
        }
        return nil
    }

    private func exportConfig(_ network: VirtualNetwork) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: network.configPath).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: network.configPath), to: url)
    }
}

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? .plainText
    }
}

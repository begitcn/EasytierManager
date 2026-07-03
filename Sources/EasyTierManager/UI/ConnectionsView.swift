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

    @State private var currentTask: Task<Void, Never>?
    @State private var searchText = ""

    private var isEditing: Bool { isCreating || editingNetwork != nil }

    private var filteredNetworks: [VirtualNetwork] {
        if searchText.isEmpty { return networkStore.networks }
        return networkStore.networks.filter { $0.name.localizedCaseInsensitiveContains(searchText) }
    }

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
                .keyboardShortcut("k", modifiers: [.command, .shift])

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
        .onDisappear {
            currentTask?.cancel()
            currentTask = nil
        }
        .confirmationDialog("确认删除", isPresented: .init(
            get: { deleteConfirmationTarget != nil },
            set: { if !$0 { deleteConfirmationTarget = nil } }
        )) {
            if let network = deleteConfirmationTarget {
                Button("删除", role: .destructive) { deleteNetwork(network) }
                Button("取消", role: .cancel) { deleteConfirmationTarget = nil }
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
            searchBar

            List(selection: $selectedNetwork) {
                ForEach(filteredNetworks) { network in
                    NetworkRowView(
                        network: network,
                        connectingNetworkId: connectingNetworkId
                    )
                    .tag(network.id)
                }
                .onDelete(perform: deleteNetworks)
            }
            .listStyle(.plain)

            Divider()

            bottomToolbar
        }
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .opacity(0.4)
                .font(.system(size: 11))
            TextField("搜索网络...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .opacity(0.4)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .padding(.horizontal, 4)
        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
    }

    private var bottomToolbar: some View {
        HStack(spacing: 0) {
            Button(action: startCreating) {
                Image(systemName: "plus")
                    .font(.system(size: 16))
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .keyboardShortcut("n", modifiers: .command)

            Button(action: startEditing) {
                Image(systemName: "pencil")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(selectedNetwork == nil || isEditing)
            .keyboardShortcut("e", modifiers: .command)

            Button(action: confirmDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(selectedNetwork == nil || isEditing)
            .keyboardShortcut(.delete, modifiers: .command)

            Button(action: toggleConnection) {
                Image(systemName: isSelectedConnected ? "stop.fill" : "play.fill")
                    .font(.system(size: 16))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .frame(maxWidth: .infinity)
            .disabled(selectedNetwork == nil || connectingNetworkId != nil || isEditing)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(.horizontal, 12)
        .frame(height: 48)
    }

    @ViewBuilder
    private var rightPanel: some View {
        if isEditing {
            ConfigEditorView(
                editConfig: $editConfig,
                peerUri: $peerUri,
                editAutoConnect: $editAutoConnect,
                isCreating: isCreating,
                onSave: saveEditor,
                onCancel: cancelEditor,
                onImport: importConfig
            )
        } else if let id = selectedNetwork, let network = networkStore.networks.first(where: { $0.id == id }) {
            NetworkDetailView(
                network: network,
                detailConfig: detailConfig,
                onToggle: toggleConnection,
                onExport: { exportConfig(network) },
                onDelete: { confirmDeleteNetwork(network) }
            )
        } else {
            EmptySelectionView()
        }
    }

    private func reloadDetailConfig() {
        guard let id = selectedNetwork,
              let network = networkStore.networks.first(where: { $0.id == id }) else {
            detailConfig = nil
            return
        }
        // Check cache first
        if let cached = networkStore.configCache[id] {
            detailConfig = cached
            return
        }
        // Fall back to file read and cache
        let url = URL(fileURLWithPath: network.configPath)
        if FileManager.default.fileExists(atPath: url.path),
           let config = try? EasyTierConfig.parse(from: url) {
            networkStore.cacheConfig(config, for: id)
            detailConfig = config
        } else {
            detailConfig = nil
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

        currentTask?.cancel()
        currentTask = Task {
            defer { currentTask = nil }
            connectingNetworkId = id

            if network.status == .connected {
                networkStore.updateStatus(id: id, status: .connecting)
                do {
                    try await easyTierService.stopNetwork(configPath: network.configPath)
                    networkStore.updateStatus(id: id, status: .disconnected)
                } catch {
                    networkStore.updateStatus(id: id, status: .error)
                    errorMessage = error.localizedDescription
                    showError = true
                }
            } else {
                networkStore.updateStatus(id: id, status: .connecting)
                do {
                    try await easyTierService.startNetwork(configPath: network.configPath)
                    networkStore.updateStatus(id: id, status: .connected)
                } catch {
                    networkStore.updateStatus(id: id, status: .error)
                    errorMessage = error.localizedDescription
                    showError = true
                }
            }
            connectingNetworkId = nil
        }
    }

    private var allConnected: Bool {
        !networkStore.networks.isEmpty && networkStore.networks.allSatisfy { $0.status == .connected }
    }

    private func connectAll() {
        guard !networkStore.networks.isEmpty else { return }
        currentTask?.cancel()
        currentTask = Task {
            defer { currentTask = nil }
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
        let config = networkStore.configCache[id] ?? (try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath)))
        if let config = config {
            editConfig = config
        } else {
            editConfig = EasyTierConfig()
        }
        peerUri = editConfig.peers.first ?? ""
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
            networkStore.cacheConfig(editConfig, for: networkId)
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

    private func cancelEditor() {
        isCreating = false
        editingNetwork = nil
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
            currentTask?.cancel()
            currentTask = Task {
                try? await easyTierService.stopNetwork(configPath: network.configPath)
                currentTask = nil
            }
        }
        let configURL = URL(fileURLWithPath: network.configPath)
        try? FileManager.default.removeItem(at: configURL)
        networkStore.removeNetwork(id: network.id)
        networkStore.invalidateConfig(for: network.id)
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
                currentTask?.cancel()
                currentTask = Task {
                    try? await easyTierService.stopNetwork(configPath: network.configPath)
                    currentTask = nil
                }
            }
            let configURL = URL(fileURLWithPath: network.configPath)
            try? FileManager.default.removeItem(at: configURL)
            networkStore.invalidateConfig(for: network.id)
        }
        networkStore.networks.remove(atOffsets: offsets)
        networkStore.saveImmediately()
        if selectedNetwork != nil, !networkStore.networks.contains(where: { $0.id == selectedNetwork }) {
            selectedNetwork = nil
        }
        if isEditing {
            cancelEditor()
        }
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

    private func exportConfig(_ network: VirtualNetwork) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: network.configPath).lastPathComponent
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? FileManager.default.copyItem(at: URL(fileURLWithPath: network.configPath), to: url)
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
            let config: EasyTierConfig?
            if let cached = networkStore.configCache[network.id] {
                config = cached
            } else {
                config = try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath))
                if let config = config {
                    networkStore.cacheConfig(config, for: network.id)
                }
            }
            guard let config = config else { continue }
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
            let config: EasyTierConfig?
            if let cached = networkStore.configCache[network.id] {
                config = cached
            } else {
                config = try? EasyTierConfig.parse(from: URL(fileURLWithPath: network.configPath))
                if let config = config {
                    networkStore.cacheConfig(config, for: network.id)
                }
            }
            guard let config = config else { continue }
            for listener in config.listeners {
                if let port = parsePort(from: listener), myPorts.contains(port) {
                    return port
                }
            }
        }
        return nil
    }
}

// MARK: - Extracted Sub-views

private struct NetworkRowView: View {
    let network: VirtualNetwork
    let connectingNetworkId: UUID?

    var body: some View {
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
}

private struct EmptySelectionView: View {
    var body: some View {
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
}

private struct NetworkDetailView: View {
    let network: VirtualNetwork
    let detailConfig: EasyTierConfig?
    let onToggle: () -> Void
    let onExport: () -> Void
    let onDelete: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SettingsSection(title: "网络信息") {
                    VStack(spacing: 0) {
                        DetailRow(label: "名称", value: network.name)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        ColoredStatusRow(label: "状态", network: network)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        DetailRow(label: "自动连接", value: network.isAutoConnect ? "是" : "否")
                    }
                }

                if let config = detailConfig {
                    SettingsSection(title: "配置") {
                        VStack(spacing: 0) {
                            DetailRow(label: "主机名", value: config.hostname)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            DetailRow(label: "实例名称", value: config.instanceName)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            if config.dhcp {
                                DetailRow(label: "IPv4", value: "自动获取 (DHCP)")
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            } else {
                                DetailRowWithCopy(label: "IPv4", value: config.ipv4, copyValue: config.ipv4)
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            }
                            DetailRow(label: "网络标识", value: config.networkName)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            if let peer = config.peers.first {
                                DetailRow(label: "对等节点", value: peer)
                                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                            }
                            if !config.listeners.isEmpty {
                                ListenersView(listeners: config.listeners)
                            }
                        }
                    }
                }

                SettingsSection(title: "操作") {
                    VStack(spacing: 0) {
                        Button(action: onToggle) {
                            HStack {
                                Image(systemName: network.status == .connected ? "stop.fill" : "play.fill")
                                Text(network.status == .connected ? "断开" : "连接")
                                Spacer()
                            }
                        }
                        .buttonStyle(SectionButtonStyle())
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        Button(action: onExport) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("导出配置")
                                Spacer()
                            }
                        }
                        .buttonStyle(SectionButtonStyle())
                        .border(width: 1, edges: [.bottom], color: NSColor.border2.color)

                        Button(action: onDelete) {
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
}

private struct ConfigEditorView: View {
    @Binding var editConfig: EasyTierConfig
    @Binding var peerUri: String
    @Binding var editAutoConnect: Bool
    let isCreating: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    let onImport: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                HStack {
                    Text(isCreating ? "新建网络" : "编辑网络")
                        .font(.headline)
                    Spacer()
                    Button(action: onImport) {
                        Label("导入配置", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                SettingsSection(title: "基础设置") {
                    VStack(spacing: 0) {
                        FormField(label: "主机名", value: $editConfig.hostname)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        FormField(label: "实例名称", value: $editConfig.instanceName)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        DhcpPicker(dhcp: $editConfig.dhcp)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        if !editConfig.dhcp {
                            FormField(label: "IPv4", value: $editConfig.ipv4)
                                .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                    }
                }

                SettingsSection(title: "网络标识") {
                    VStack(spacing: 0) {
                        FormField(label: "网络名称", value: $editConfig.networkName)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        FormField(label: "网络密钥", value: $editConfig.networkSecret)
                    }
                }

                SettingsSection(title: "对等节点") {
                    VStack(spacing: 0) {
                        FormField(label: "地址", value: $peerUri)
                    }
                }

                SettingsSection(title: "高级设置") {
                    VStack(spacing: 0) {
                        FormToggle(label: "接受 DNS", value: $editConfig.acceptDns)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        FormToggle(label: "延迟优先", value: $editConfig.latencyFirst)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        FormToggle(label: "私有模式", value: $editConfig.privateMode)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        FormToggle(label: "启动自动连接", value: $editAutoConnect)
                    }
                }

                ListenerEditor(listeners: $editConfig.listeners)

                VStack(spacing: 12) {
                    HStack(spacing: 8) {
                        Button(action: onSave) {
                            Label("保存", systemImage: "checkmark")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                        .disabled(editConfig.instanceName.isEmpty || (!editConfig.dhcp && editConfig.ipv4.isEmpty))
                        .keyboardShortcut(.return, modifiers: .command)
                    }

                    Button(action: onCancel) {
                        Text("取消")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .keyboardShortcut(.escape, modifiers: [])
                }
            }
            .padding()
        }
    }
}

// MARK: - Tiny Sub-views

private struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 100, alignment: .leading)
            Text(value)
            Spacer()
        }
        .padding()
    }
}

private struct ColoredStatusRow: View {
    let label: String
    let network: VirtualNetwork

    var body: some View {
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
}

private struct DetailRowWithCopy: View {
    let label: String
    let value: String
    let copyValue: String
    @State private var copied = false

    var body: some View {
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
                copied = true
                Task {
                    try? await Task.sleep(nanoseconds: 1_500_000_000)
                    copied = false
                }
            }) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.system(size: 11))
                    .foregroundColor(copied ? .green : .primary)
                    .opacity(0.4)
            }
            .buttonStyle(.plain)
            .help("复制")
        }
        .padding()
    }
}

private struct FormField: View {
    let label: String
    @Binding var value: String

    var body: some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            TextField("", text: $value)
                .textFieldStyle(.plain)
            Spacer()
        }
        .padding()
    }
}

private struct FormToggle: View {
    let label: String
    @Binding var value: Bool

    var body: some View {
        HStack {
            Text(label)
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Toggle("", isOn: $value)
        }
        .padding()
    }
}

private struct DhcpPicker: View {
    @Binding var dhcp: Bool

    var body: some View {
        HStack {
            Text("DHCP")
                .opacity(0.6)
                .frame(width: 90, alignment: .leading)
            Spacer()
            Picker("", selection: $dhcp) {
                Text("自动获取").tag(true)
                Text("手动设置").tag(false)
            }
            .pickerStyle(.segmented)
            .frame(width: 200)
        }
        .padding()
    }
}

private struct ListenersView: View {
    let listeners: [String]

    var body: some View {
        HStack(alignment: .top) {
            Text("监听地址")
                .opacity(0.6)
                .frame(width: 100, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(listeners, id: \.self) { addr in
                    Text(addr)
                }
            }
            Spacer()
        }
        .padding()
    }
}

private struct ListenerEditor: View {
    @Binding var listeners: [String]

    var body: some View {
        SettingsSection(title: "监听地址") {
            VStack(spacing: 0) {
                if listeners.isEmpty {
                    HStack {
                        Text("添加监听地址以接受连接")
                            .font(.caption)
                            .opacity(0.4)
                        Spacer()
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }
                ForEach(listeners.indices, id: \.self) { index in
                    HStack {
                        TextField("tcp://0.0.0.0:11010", text: $listeners[index])
                            .textFieldStyle(.plain)
                        Button(action: { listeners.remove(at: index) }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .buttonStyle(.plain)
                        .opacity(0.4)
                    }
                    .padding()
                    .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                }
                Button(action: { listeners.append("") }) {
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
    }
}

extension UTType {
    static var yaml: UTType {
        UTType(filenameExtension: "yaml") ?? .plainText
    }
}

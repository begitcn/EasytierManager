import SwiftUI

struct NodesView: View {
    @State private var selectedNetworkId: UUID?
    @State private var networks: [VirtualNetwork] = [
        VirtualNetwork(name: "Home Network", configPath: "~/.easytier/home.toml", status: .connected),
        VirtualNetwork(name: "Office Network", configPath: "~/.easytier/office.toml"),
    ]

    @State private var nodes: [NetworkNode] = [
        NetworkNode(name: "MacBook-Pro", ipv4: "10.144.0.1", ipv6: "fd00::1", status: .online, latency: 5, networkId: UUID()),
        NetworkNode(name: "Raspberry-Pi", ipv4: "10.144.0.2", status: .online, latency: 12, networkId: UUID()),
        NetworkNode(name: "NAS-Server", ipv4: "10.144.0.3", ipv6: "fd00::3", status: .online, latency: 3, networkId: UUID()),
        NetworkNode(name: "VPS-Tokyo", ipv4: "10.144.0.4", status: .online, latency: 45, networkId: UUID()),
        NetworkNode(name: "Remote-Desktop", ipv4: "10.144.0.5", status: .offline, networkId: UUID()),
    ]

    @State private var searchText = ""
    @State private var sortOrder: SortOrder = .name
    @State private var copiedAlert = false
    @State private var copiedValue = ""

    enum SortOrder: String, CaseIterable {
        case name = "名称"
        case ipv4 = "IPv4"
        case latency = "延迟"
    }

    var filteredNodes: [NetworkNode] {
        var result = nodes
        if !searchText.isEmpty {
            result = result.filter { node in
                node.name.localizedCaseInsensitiveContains(searchText) ||
                node.ipv4.localizedCaseInsensitiveContains(searchText)
            }
        }
        switch sortOrder {
        case .name:
            result.sort { $0.name < $1.name }
        case .ipv4:
            result.sort { $0.ipv4 < $1.ipv4 }
        case .latency:
            result.sort { ($0.latency ?? 999) < ($1.latency ?? 999) }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Picker("网络", selection: $selectedNetworkId) {
                    Text("所有网络").tag(nil as UUID?)
                    ForEach(networks) { network in
                        Text(network.name).tag(network.id as UUID?)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 150)

                Divider()
                    .frame(height: 20)

                Picker("排序", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { order in
                        Text(order.rawValue).tag(order)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                HStack {
                    Image(systemName: "magnifyingglass")
                        .opacity(0.4)
                    TextField("搜索节点...", text: $searchText)
                        .textFieldStyle(.plain)
                }
                .padding(6)
                .background(NSColor.background.color)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(NSColor.border2.color, lineWidth: 1)
                )
                .frame(maxWidth: 200)
            }
            .padding(8)
            .border(width: 1, edges: [.bottom], color: NSColor.border.color)

            if filteredNodes.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 48))
                        .opacity(0.3)
                    Text("未找到节点")
                        .font(.headline)
                        .opacity(0.5)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        HStack {
                            Text("名称")
                                .frame(width: 200, alignment: .leading)
                            Text("IPv4")
                                .frame(width: 200, alignment: .leading)
                            Text("延迟")
                                .frame(width: 100, alignment: .trailing)
                            Spacer()
                            Text("操作")
                                .frame(width: 80, alignment: .center)
                        }
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(0.5)
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .background(NSColor.background2.color)

                        ForEach(filteredNodes) { node in
                            HStack {
                                Text(node.name)
                                    .frame(width: 200, alignment: .leading)
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    Text(node.ipv4)
                                        .font(.system(.body, design: .monospaced))
                                        .lineLimit(1)

                                    Button(action: {
                                        copyToClipboard(node.ipv4)
                                    }) {
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 10))
                                    }
                                    .buttonStyle(.plain)
                                    .opacity(0.4)
                                    .help("复制 IPv4")
                                }
                                .frame(width: 200, alignment: .leading)

                                Text(node.latency.map { "\($0)ms" } ?? "-")
                                    .frame(width: 100, alignment: .trailing)
                                    .opacity(node.latency != nil ? 1 : 0.3)

                                Spacer()

                                Menu {
                                    Button(action: { copyToClipboard(node.ipv4) }) {
                                        Label("复制 IPv4", systemImage: "doc.on.doc")
                                    }
                                    Divider()
                                    Button(action: {}) {
                                        Label("Ping", systemImage: "antenna.radiowaves.left.and.right")
                                    }
                                    Button(action: {}) {
                                        Label("路由追踪", systemImage: "point.topleft.down.curvedto.point.bottomright.up")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                        .font(.system(size: 14))
                                }
                                .buttonStyle(.plain)
                                .frame(width: 80, alignment: .center)
                            }
                            .font(.system(size: 12))
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                            .background(NSColor.background1.color)
                            .border(width: 1, edges: [.bottom], color: NSColor.border2.color)
                        }
                    }
                }
            }
        }
        .background(NSColor.background1.color)
        .overlay(
            Group {
                if copiedAlert {
                    VStack {
                        Spacer()
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("已复制: \(copiedValue)")
                        }
                        .padding()
                        .background(NSColor.background2.color)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(NSColor.border2.color, lineWidth: 1)
                        )
                        .padding(.bottom, 20)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copiedAlert)
        )
    }

    private func copyToClipboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
        copiedValue = value
        withAnimation {
            copiedAlert = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                copiedAlert = false
            }
        }
    }
}

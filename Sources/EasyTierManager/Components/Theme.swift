import SwiftUI

/// 全局设计系统：颜色 / 圆角 / 间距 / 状态组件
/// 所有页面统一从这里取令牌，保证视觉一致性，深色/浅色模式自动适配。
enum Theme {
    enum Colors {
        /// 已连接
        static let connected = Color(red: 0.24, green: 0.76, blue: 0.42)
        /// 连接中
        static let connecting = Color.orange
        /// 未连接
        static let disconnected = Color.secondary
        /// 错误
        static let error = Color.red

        /// P2P 直连
        static let p2p = Color(red: 0.24, green: 0.76, blue: 0.42)
        /// 中继
        static let relay = Color.orange
        /// 本机
        static let local = Color.secondary
    }

    enum Radius {
        static let small: CGFloat = 6
        static let medium: CGFloat = 10
        static let large: CGFloat = 14
    }

    enum Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    /// 延迟梯度着色：<50ms 优，<150ms 良，其余差
    static func latencyColor(_ ms: Int?) -> Color {
        guard let ms else { return .secondary }
        switch ms {
        case ..<50: return Colors.connected
        case ..<150: return .orange
        default: return .red
        }
    }
}

// MARK: - 连接状态语义化

extension VirtualNetwork.ConnectionStatus {
    var color: Color {
        switch self {
        case .connected: return Theme.Colors.connected
        case .connecting: return Theme.Colors.connecting
        case .disconnected: return Theme.Colors.disconnected
        case .error: return Theme.Colors.error
        }
    }

    var text: String {
        switch self {
        case .connected: return "已连接"
        case .connecting: return "连接中"
        case .disconnected: return "未连接"
        case .error: return "错误"
        }
    }
}

// MARK: - 节点组网方式语义化

extension NetworkNode {
    var costLabel: String {
        switch cost {
        case "Local": return "本地"
        case "p2p": return "P2P"
        default: return "中继"
        }
    }

    var costColor: Color {
        switch cost {
        case "Local": return Theme.Colors.local
        case "p2p": return Theme.Colors.p2p
        default: return Theme.Colors.relay
        }
    }
}

// MARK: - 状态圆点（连接中带呼吸动画）

struct StatusDot: View {
    let status: VirtualNetwork.ConnectionStatus
    var size: CGFloat = 8

    @State private var pulsating = false

    var body: some View {
        Circle()
            .fill(status.color)
            .frame(width: size, height: size)
            .opacity(status == .connecting ? (pulsating ? 0.35 : 1.0) : 1.0)
            .scaleEffect(status == .connecting ? (pulsating ? 0.8 : 1.0) : 1.0)
            .animation(
                status == .connecting
                    ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                    : .default,
                value: pulsating
            )
            .onAppear { pulsating = status == .connecting }
            .onChange(of: status) { newValue in
                pulsating = newValue == .connecting
            }
            .accessibilityLabel(Text(status.text))
    }
}

// MARK: - 状态徽章（圆点 + 文字胶囊）

struct StatusBadge: View {
    let status: VirtualNetwork.ConnectionStatus

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            StatusDot(status: status, size: 6)
            Text(status.text)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(status.color.opacity(0.12), in: Capsule())
    }
}

// MARK: - 组网方式徽章

struct CostBadge: View {
    let cost: String?

    private var label: String {
        switch cost {
        case "Local": return "本地"
        case "p2p": return "P2P"
        default: return "中继"
        }
    }

    private var color: Color {
        switch cost {
        case "Local": return Theme.Colors.local
        case "p2p": return Theme.Colors.p2p
        default: return Theme.Colors.relay
        }
    }

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.small))
    }
}

import SwiftUI

/// 分组卡片内的行按钮样式（导出 / 删除等操作行）
struct SectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.gray.opacity(0.05) : Color.clear)
            .foregroundColor(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small))
            .contentShape(Rectangle())
    }
}

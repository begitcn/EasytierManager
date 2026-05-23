import SwiftUI

struct NavButtonStyle: ButtonStyle {
    let icon: String
    let isActive: Bool

    func makeBody(configuration: Self.Configuration) -> some View {
        HStack {
            VStack {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .frame(width: 15, height: 15)
                    .opacity(0.9)
            }

            configuration.label
                .lineLimit(1)

            Spacer()
        }
        .padding(.leading, 10)
        .padding(.trailing, 5)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(isActive ? Color.gray.opacity(0.2) : Color.clear)
        .background(configuration.isPressed ? Color.gray.opacity(0.1) : Color.clear)
        .foregroundColor(Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .padding(.horizontal, 10)
    }
}

struct SectionButtonStyle: ButtonStyle {
    func makeBody(configuration: Self.Configuration) -> some View {
        configuration.label
            .padding()
            .frame(maxWidth: .infinity)
            .background(configuration.isPressed ? Color.gray.opacity(0.05) : Color.clear)
            .foregroundColor(Color.accentColor)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
    }
}

import SwiftUI

struct SettingsSection<Content: View>: View {
    let title: String
    let trailing: AnyView?
    let content: Content

    init(title: String, @ViewBuilder _ content: () -> Content) {
        self.title = title
        self.trailing = nil
        self.content = content()
    }

    init(title: String, trailing: some View, @ViewBuilder _ content: () -> Content) {
        self.title = title
        self.trailing = AnyView(trailing)
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.secondary)
                    if let trailing {
                        Spacer()
                        trailing
                    }
                }
                .padding(.horizontal, Theme.Spacing.xs)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(.background, in: RoundedRectangle(cornerRadius: Theme.Radius.medium))
            .shadow(color: .black.opacity(0.06), radius: 2, y: 1)
        }
    }
}

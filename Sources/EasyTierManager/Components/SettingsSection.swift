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
        VStack(alignment: .leading) {
            if !title.isEmpty {
                HStack {
                    Text(title)
                        .opacity(0.8)
                    if let trailing {
                        Spacer()
                        trailing
                    }
                }
                .padding(.horizontal)
            }

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .frame(maxWidth: .infinity)
            .background(NSColor.background.color)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(NSColor.border2.color, lineWidth: 1)
            )
        }
    }
}

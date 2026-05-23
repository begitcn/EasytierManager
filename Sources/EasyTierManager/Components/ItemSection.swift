import SwiftUI

struct ItemSection<Content: View>: View {
    let content: Content

    init(@ViewBuilder _ content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                content
                Spacer()
            }
            Spacer()
        }
        .itemSectionStyle()
    }
}

struct ItemSectionStyle: ViewModifier {
    func body(content: Content) -> some View {
        let border = RoundedRectangle(cornerRadius: 6)
            .stroke(NSColor.border2.color, lineWidth: 1)
        return content
            .background(NSColor.background1.color)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(border)
    }
}

extension View {
    func itemSectionStyle() -> some View {
        modifier(ItemSectionStyle())
    }
}

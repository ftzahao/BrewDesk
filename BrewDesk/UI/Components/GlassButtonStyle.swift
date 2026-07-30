import SwiftUI

/// 胶囊 + 玻璃效果按钮样式
struct GlassCapsuleButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .contentShape(Capsule())
            .clipShape(Capsule())
            .glassEffect()
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
    static func glassCapsule(tint: Color) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(tint: tint)
    }
}

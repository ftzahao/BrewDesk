import SwiftUI

/// 胶囊按钮样式：材质背板 + 色调文字/描边（滚动安全），保留玻璃设计语言的质感。
/// 说明：Liquid Glass 的玻璃层是窗口级背板，放在 ScrollView 里滚动时会浮在内容最上层
/// （“按钮层级最高”的残影现象），因此按钮改用 .regularMaterial 背板，滚动时层级正常。
struct GlassCapsuleButtonStyle: ButtonStyle {
    var tint: Color = .accentColor

    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.medium))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(tint)
            .background {
                Capsule()
                    .fill(.regularMaterial)
                    .overlay(Capsule().fill(tint.opacity(0.10)))
            }
            .overlay(
                Capsule()
                    .strokeBorder(tint.opacity(isHovered ? 0.35 : 0.18), lineWidth: 0.5)
            )
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? Design.pressScale : isHovered ? 1.03 : 1)
            .opacity(configuration.isPressed ? 0.75 : 1)
            .animation(.easeInOut(duration: 0.14), value: configuration.isPressed)
            .animation(Design.standardAnimation, value: isHovered)
            .onHover { isHovered = $0 }
    }
}

extension ButtonStyle where Self == GlassCapsuleButtonStyle {
    static var glassCapsule: GlassCapsuleButtonStyle { GlassCapsuleButtonStyle() }
    static func glassCapsule(tint: Color) -> GlassCapsuleButtonStyle {
        GlassCapsuleButtonStyle(tint: tint)
    }
}

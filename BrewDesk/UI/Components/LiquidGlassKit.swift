//
//  LiquidGlassKit.swift
//  BrewDesk
//
//  统一 Liquid Glass 视觉组件：
//  - 玻璃命名空间（跨页面 morph）
//  - 玻璃页头（主页统计/快捷入口与子页面之间的流畅过渡）
//  - 玻璃页脚栏（列表底部状态条）
//  - 浮动任务状态栏（任务运行时的玻璃进度胶囊）
//  - 玻璃卡片容器与统一设计常量
//

import SwiftUI

// MARK: - 设计常量

enum Design {
    static let pagePadding: CGFloat = 20
    /// 两列布局中详情内容的统一内边距
    static let contentPadding: CGFloat = 24
    static let cardRadius: CGFloat = 14
    static let smallRadius: CGFloat = 10
    static let pressScale: CGFloat = 0.96
    static let standardAnimation = Animation.easeOut(duration: 0.18)
}

// MARK: - 玻璃命名空间（让主页卡片与目标页面共享 morph 身份）

private struct GlassNamespaceKey: EnvironmentKey {
    static let defaultValue: Namespace.ID? = nil
}

extension EnvironmentValues {
    /// 由根视图注入，供所有玻璃元素共享，实现跨页面 glassEffectID morph。
    var glassNamespace: Namespace.ID? {
        get { self[GlassNamespaceKey.self] }
        set { self[GlassNamespaceKey.self] = newValue }
    }
}

extension View {
    /// 带可选命名空间的 glassEffectID，避免每个视图重复取环境值。
    func glassID(_ id: some Hashable & Sendable) -> some View {
        modifier(GlassIDModifier(id: id))
    }
}

// MARK: - 玻璃页脚栏

/// 列表底部半透明玻璃状态条：浮动在内容之上，替代原来的 .bar 背景。
struct GlassFooterBar<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .font(.caption)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 11, style: .continuous))
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
    }
}

// MARK: - 浮动任务状态栏

/// 任务运行时的底部浮动玻璃进度胶囊：进度指示 + 任务名 + 取消。
struct TaskStatusBar: View {
    let title: String
    var onCancel: () -> Void

    @State private var visible = false

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(.accentColor)
            Text(title)
                .font(.callout.weight(.medium))
                .lineLimit(1)
                .monospacedDigit()
            Button("取消", action: onCancel)
                .buttonStyle(.glassCapsule)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .glassEffect(.regular.interactive(), in: Capsule())
        .shadow(color: .black.opacity(0.14), radius: 14, y: 6)
        .scaleEffect(visible ? 1 : 0.96)
        .opacity(visible ? 1 : 0)
        .onAppear {
            withAnimation(Design.standardAnimation) { visible = true }
        }
    }
}

// MARK: - 玻璃卡片容器

/// 玻璃卡片按钮的点击反馈（按压回弹 + 透明度）。
struct GlassCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? Design.pressScale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(.easeInOut(duration: 0.12), value: configuration.isPressed)
    }
}

// MARK: - 玻璃空状态

/// 详情栏统一的空状态：玻璃圆图标 + 标题 + 副标题 + 可选操作区。
/// 用于两列布局的 detail 列（背景由 TwoColumnPage 的材质提供，玻璃圆安全）。
struct GlassEmptyState<Actions: View>: View {
    let icon: String
    let title: String
    var subtitle: String?
    var tint: Color
    @ViewBuilder var actions: () -> Actions

    /// 无操作区
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        tint: Color = .accentColor
    ) where Actions == EmptyView {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.actions = { EmptyView() }
    }

    /// 带操作区（trailing closure 形式）
    init(
        icon: String,
        title: String,
        subtitle: String? = nil,
        tint: Color = .accentColor,
        @ViewBuilder actions: @escaping () -> Actions
    ) {
        self.icon = icon
        self.title = title
        self.subtitle = subtitle
        self.tint = tint
        self.actions = actions
    }

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .frame(width: 76, height: 76)
                    .glassEffect(.regular, in: Circle())
                Image(systemName: icon)
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(tint)
            }

            VStack(spacing: 4) {
                Text(title)
                    .font(.title3.weight(.semibold))
                if let subtitle {
                    Text(subtitle)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            actions()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct GlassIDModifier<ID: Hashable & Sendable>: ViewModifier {
    let id: ID?
    @Environment(\.glassNamespace) private var namespace

    func body(content: Content) -> some View {
        if let namespace, let id {
            content.glassEffectID(id, in: namespace)
        } else {
            content
        }
    }
}

// MARK: - 玻璃搜索框

/// 内容区内的玻璃搜索输入框（配合 glassEffect 使用）。
struct GlassSearchField: View {
    let prompt: String
    @Binding var text: String
    var onSubmit: (() -> Void)? = nil
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(focused ? Color.accentColor : .secondary)
                .font(.system(size: 12, weight: .medium))
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
                .onSubmit {
                    onSubmit?()
                }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("清空")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

// MARK: - 玻璃分段控件

/// Liquid Glass 分段选择器：选中段为玻璃胶囊，切换时胶囊在段之间 morph。
/// 使用同一 glassEffectID + GlassEffectContainer，与原生 macOS 26 分段控件观感一致。
struct GlassSegmentedControl<Value: Hashable & Sendable>: View {
    let options: [(title: String, value: Value)]
    @Binding var selection: Value
    /// glassEffectID 前缀，避免同屏多个控件相互 morph
    var idPrefix: String = "segment"

    @Namespace private var namespace
    @State private var hovered: Value?

    var body: some View {
        GlassEffectContainer(spacing: 4) {
            HStack(spacing: 3) {
                ForEach(options, id: \.title) { option in
                    segmentButton(option)
                }
            }
            .padding(3)
            .glassEffect(.clear, in: Capsule())
        }
        .animation(.easeInOut(duration: 0.22), value: selection)
    }

    private func segmentButton(_ option: (title: String, value: Value)) -> some View {
        let isSelected = selection == option.value

        return Button {
            selection = option.value
        } label: {
            Text(option.title)
                .font(.callout.weight(.medium))
                .foregroundStyle(isSelected ? .primary : .secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .contentShape(Capsule())
                .background {
                    if isSelected {
                        Capsule()
                            .fill(.regularMaterial)
                            .overlay {
                                Capsule().fill(Color.accentColor.opacity(0.10))
                            }
                            .glassEffect(.regular.interactive(), in: Capsule())
                            .glassEffectID("\(idPrefix).selected", in: namespace)
                    }
                }
                .scaleEffect(hovered == option.value && !isSelected ? 1.03 : 1)
                .opacity(isSelected ? 1 : 0.9)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(Design.standardAnimation) {
                hovered = hovering ? option.value : nil
            }
        }
        .accessibilityLabel(option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

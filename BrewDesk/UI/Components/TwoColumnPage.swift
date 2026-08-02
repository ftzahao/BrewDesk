//
//  TwoColumnPage.swift
//  BrewDesk
//

import SwiftUI

/// List + detail layout for use inside the root `NavigationSplitView` detail column.
/// Avoid nesting another `NavigationSplitView` (breaks sidebar selection on macOS).
/// 使用 HStack 而非 HSplitView 防止嵌套 NSSplitView 导致的布局递归警告。
struct TwoColumnPage<ListContent: View, DetailContent: View>: View {
    var listMinWidth: CGFloat = 260
    var listIdealWidth: CGFloat = 320
    var listMaxWidth: CGFloat = 420
    @ViewBuilder var list: () -> ListContent
    @ViewBuilder var detail: () -> DetailContent

    var body: some View {
        HStack(spacing: 0) {
            list()
                .frame(minWidth: listMinWidth, idealWidth: listIdealWidth, maxWidth: listMaxWidth)
                .frame(maxHeight: .infinity)
                .layoutPriority(0)

            Rectangle()
                .fill(Color.primary.opacity(0.06))
                .frame(width: 1)

            detail()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .ignoresSafeArea()
                }
                .layoutPriority(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

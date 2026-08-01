//
//  HomeStatsRow.swift
//  BrewDesk
//
//  主页概览统计卡片：已安装 / 可更新 / Formula / Cask / 服务运行中。
//

import SwiftUI

struct HomeStatsRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 10) {
            StatCard(
                icon: "shippingbox.fill",
                tint: .blue,
                title: "已安装",
                value: state.catalogInstalledCount,
                action: { state.selectedSidebar = .installed }
            )
            StatCard(
                icon: "arrow.triangle.2.circlepath",
                tint: .orange,
                title: "可更新",
                value: state.outdated.count,
                highlighted: state.outdated.count > 0,
                action: { state.selectedSidebar = .outdated }
            )
            StatCard(
                icon: "terminal.fill",
                tint: .green,
                title: "Formula",
                value: state.catalogFormulaCount,
                active: state.homeKindFilter == .formula,
                action: toggleFilter(.formula)
            )
            StatCard(
                icon: "app.badge.fill",
                tint: .purple,
                title: "Cask",
                value: state.catalogCaskCount,
                active: state.homeKindFilter == .cask,
                action: toggleFilter(.cask)
            )
            StatCard(
                icon: "bolt.horizontal.circle.fill",
                tint: .red,
                title: "服务运行中",
                value: state.runningServiceCount,
                total: state.services.count,
                action: { state.selectedSidebar = .services }
            )
        }
    }

    private func toggleFilter(_ kind: PackageKind) -> () -> Void {
        {
            state.homeKindFilter = (state.homeKindFilter == kind) ? nil : kind
        }
    }
}

/// 单个统计卡片：图标 + 数值 + 标题，支持高亮与筛选态标记。
private struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: Int
    var total: Int? = nil
    var highlighted: Bool = false
    var active: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var valueText: String {
        if let total {
            return "\(value)/\(total)"
        }
        return "\(value)"
    }

    var body: some View {
        let effectiveTint = active ? Color.accentColor : tint
        return Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(effectiveTint.opacity(active ? 0.18 : 0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(effectiveTint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text(valueText)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if active {
                    Text("筛选中")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        highlighted
                            ? Color.orange.opacity(0.35)
                            : (active ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06)),
                        lineWidth: highlighted || active ? 1.2 : 1
                    )
            }
            .scaleEffect(isHovered ? 1.018 : 1)
            .shadow(color: .black.opacity(isHovered ? 0.08 : 0), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

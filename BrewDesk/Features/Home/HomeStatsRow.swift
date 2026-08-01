//
//  HomeStatsRow.swift
//  BrewDesk
//
//  主页概览统计卡片：已安装 / 可更新 / 服务运行中（均为跳转入口）。
//

import SwiftUI

struct HomeStatsRow: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
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
                icon: "bolt.horizontal.circle.fill",
                tint: .red,
                title: "服务运行中",
                value: state.runningServiceCount,
                total: state.services.count,
                action: { state.selectedSidebar = .services }
            )
        }
    }
}

/// 单个统计卡片：图标 + 数值 + 标题。
private struct StatCard: View {
    let icon: String
    let tint: Color
    let title: String
    let value: Int
    var total: Int? = nil
    var highlighted: Bool = false
    let action: () -> Void

    @State private var isHovered = false

    private var valueText: String {
        if let total {
            return "\(value)/\(total)"
        }
        return "\(value)"
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(valueText)
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .overlay {
                if highlighted {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.orange.opacity(0.35), lineWidth: 1.2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .scaleEffect(isHovered ? 1.015 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.15), value: isHovered)
    }
}

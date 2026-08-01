//
//  HomeQuickActions.swift
//  BrewDesk
//
//  主页功能快捷入口：Taps / 维护 / 设置。
//

import SwiftUI

struct HomeQuickActions: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 12) {
            quickActionCard(
                .taps,
                tint: .teal,
                description: "软件源仓库",
                badge: state.taps.isEmpty ? nil : "\(state.taps.count)"
            )
            quickActionCard(.maintenance, tint: .purple, description: "清理与体检")
            quickActionCard(.settings, tint: .gray, description: "偏好设置")
        }
    }

    private func quickActionCard(
        _ item: SidebarItem,
        tint: Color,
        description: String,
        badge: String? = nil
    ) -> some View {
        Button {
            state.selectedSidebar = item
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(tint.opacity(0.14))
                        .frame(width: 36, height: 36)
                    Image(systemName: item.filledImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(tint)
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.system(size: 13, weight: .medium))
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if let badge {
                    Text(badge)
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(tint)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(tint.opacity(0.12)))
                }

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .glassEffect(
                .regular.interactive(),
                in: RoundedRectangle(cornerRadius: 14, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

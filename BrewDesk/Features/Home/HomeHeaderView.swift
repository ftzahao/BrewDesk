//
//  HomeHeaderView.swift
//  BrewDesk
//
//  主页头部：标题 + Homebrew 状态 + 统计卡片 + 功能快捷入口（悬浮玻璃卡）。
//

import SwiftUI

struct HomeHeaderView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("软件包目录")
                        .font(.system(size: 20, weight: .bold))
                    Text("浏览全部可安装的 formula 与 cask")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                homebrewStatusText
            }

            GlassEffectContainer(spacing: 12) {
                VStack(spacing: 12) {
                    HomeStatsRow(state: state)
                    HomeQuickActions(state: state)
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 18)
        .padding(.bottom, 14)
    }

    private var homebrewStatusText: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(state.isTaskRunning ? Color.orange : Color.green)
                .frame(width: 8, height: 8)

            if let inst = state.installation {
                Text("Homebrew \(inst.version)")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(inst.prefix)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(inst.executableURL.path)
            } else {
                Text("未检测到 Homebrew")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

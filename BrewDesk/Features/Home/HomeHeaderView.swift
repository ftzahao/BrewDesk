//
//  HomeHeaderView.swift
//  BrewDesk
//
//  主页头部：标题 + 概览统计。搜索与刷新已移至窗口工具栏。
//

import SwiftUI

struct HomeHeaderView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("软件包目录")
                    .font(.system(size: 17, weight: .semibold))
                Text("浏览全部可安装的 formula 与 cask")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HomeStatsRow(state: state)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea()
        }
    }
}

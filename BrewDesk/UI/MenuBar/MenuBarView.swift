//
//  MenuBarView.swift
//  BrewDesk
//

import AppKit
import SwiftUI

struct MenuBarLabelView: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "mug.fill")
            if state.outdated.count > 0 {
                Text("\(state.outdated.count)")
                    .font(.caption2.monospacedDigit().weight(.semibold))
            }
        }
        .help(state.installation == nil ? "BrewDesk — 未检测到 Homebrew"
              : state.outdated.isEmpty ? "BrewDesk — 全部是最新的"
              : "BrewDesk — \(state.outdated.count) 个可更新")
    }
}

struct MenuBarMenuContent: View {
    @ObservedObject var state: AppState

    var body: some View {
        if state.installation == nil {
            Text("未检测到 Homebrew")
            Button("打开 BrewDesk") { state.openMainWindow() }
        } else {
            Text(state.isTaskRunning ? (state.currentTaskTitle ?? "运行中…") :
                 state.outdated.isEmpty ? "全部是最新的" : "\(state.outdated.count) 个可更新"
            ).font(.headline)
            Divider()
            Button("打开 BrewDesk") { state.openMainWindow() }.keyboardShortcut("o")
            Button("查看可更新") { state.openMainWindow(sidebar: .outdated) }
            Divider()
            Button("检查更新（刷新）") { Task { await state.loadOutdated() } }
                .disabled(state.isTaskRunning)
            Button("更新 Homebrew") { Task { await state.brewUpdate() } }
                .disabled(state.isTaskRunning)
            Button("全部升级") {
                state.openMainWindow(sidebar: .outdated)
                Task { await state.upgradeAll() }
            }.disabled(state.outdated.isEmpty || state.isTaskRunning)
            Divider()
            if state.isTaskRunning {
                Divider()
                Text(state.currentTaskTitle ?? "任务运行中…").foregroundStyle(.secondary)
                Button("取消任务", role: .destructive) { state.cancelTask() }
            }
        }
        Divider()
        Button("退出 BrewDesk") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}

//
//  BrewDeskApp.swift
//  BrewDesk
//
//  Created by 师梦豪 on 2026/7/28.
//

import Sparkle
import SwiftUI

@main
struct BrewDeskApp: App {
    @State private var appState = AppState()
    @StateObject private var updaterController = UpdaterController()
    @State private var showAbout = false
    /// 用户偏好：隐藏菜单栏图标（默认隐藏，仅当用户在设置中关闭后显示）。
    /// 用 @AppStorage 而非 AppState：MenuBarExtra 插入状态由 App 场景驱动，
    /// 设置页 toggle 与本处绑定同一 key，任意一端变化都会同步重建 App body。
    @AppStorage("hideMenuBarIcon") private var hideMenuBarIcon = true

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appState)
                .environmentObject(updaterController)
                .task {
                    appState.updater = updaterController
                    updaterController.updater.automaticallyChecksForUpdates = appState.autoCheckForUpdates
                    updaterController.updater.automaticallyDownloadsUpdates = appState.autoDownloadUpdates
                    await appState.bootstrap()
                }
                .sheet(isPresented: $showAbout) { AboutView() }
        }
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .appInfo) {
                Button("关于 BrewDesk") { showAbout = true }
            }
            CommandMenu("Brew") {
                Button("刷新全部") { Task { await appState.refreshAll() } }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
                    .disabled(appState.isTaskRunning || appState.installation == nil)
                Button("更新 Homebrew") { Task { await appState.brewUpdate() } }
                    .disabled(appState.isTaskRunning || appState.installation == nil)
                Button("全部升级") { Task { await appState.upgradeAll() } }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                    .disabled(appState.isTaskRunning || appState.outdated.isEmpty)
                Divider()
                Button("清理预览") {
                    appState.selectedSidebar = .maintenance
                    Task { await appState.loadCleanupPreview() }
                }.disabled(appState.installation == nil)
                Divider()
                Button("导出 Brewfile…") {
                    appState.selectedSidebar = .maintenance
                    BrewfilePanel.presentExport(on: appState)
                }
                    .disabled(appState.isTaskRunning || appState.installation == nil)
            }
            CommandGroup(after: .appInfo) {
                Divider()
                Button("检查更新…") {
                    updaterController.checkForUpdates()
                }
                .disabled(!updaterController.canCheckForUpdates)
                .keyboardShortcut("u", modifiers: [.command, .option])
            }
        }

        // isInserted 语义为「显示图标」，与偏好「隐藏」取反；
        // 隐藏后主窗口（Dock 图标/⌘Tab）仍是完整入口，可从设置恢复。
        MenuBarExtra(isInserted: Binding(
            get: { !hideMenuBarIcon },
            set: { hideMenuBarIcon = !$0 }
        )) {
            MenuBarMenuContent(state: appState)
        } label: {
            MenuBarLabelView(state: appState)
        }
    }
}

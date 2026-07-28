//
//  BrewDeskApp.swift
//  BrewDesk
//
//  Created by 师梦豪 on 2026/7/28.
//

import SwiftUI

@main
struct BrewDeskApp: App {
    @StateObject private var appState = AppState()
    @State private var showAbout = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .task { await appState.bootstrap() }
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
                Button("运行 doctor") {
                    appState.selectedSidebar = .maintenance
                    Task { await appState.runDoctor() }
                }.disabled(appState.installation == nil)
                Button("清理预览") {
                    appState.selectedSidebar = .maintenance
                    Task { await appState.loadCleanupPreview() }
                }.disabled(appState.installation == nil)
                Divider()
                Button("导出 Brewfile…") { appState.exportBrewfileInteractively() }
                    .disabled(appState.isTaskRunning || appState.installation == nil)
            }
        }

        MenuBarExtra {
            MenuBarMenuContent(state: appState)
        } label: {
            MenuBarLabelView(state: appState)
        }
    }
}

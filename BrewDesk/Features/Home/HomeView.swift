//
//  HomeView.swift
//  BrewDesk
//
//  主页：概览统计 + 全部 formula / cask 目录，工具栏搜索框（.searchable）进入搜索结果视图。
//  目录采用窗口化渲染：只实例化当前窗口内的行，A-Z 跳转时把窗口移到目标字母附近。
//  结构：HomeHeaderView（标题/统计）+ TwoColumnPage（目录列表 / 详情栏）+ 工具栏（搜索/刷新）。
//

import SwiftUI

struct HomeView: View {
    @ObservedObject var state: AppState
    @State private var pendingUninstall: Package?
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HomeHeaderView(state: state)

            Divider()

            TwoColumnPage(
                listMinWidth: 270,
                listIdealWidth: 340,
                listMaxWidth: 460
            ) {
                HomeCatalogList(
                    state: state,
                    searchFocused: $searchFocused,
                    onUninstall: { pendingUninstall = $0 }
                )
            } detail: {
                HomeDetailPane(state: state, onUninstall: { pendingUninstall = $0 })
            }
        }
        .navigationTitle("主页")
        .onExitCommand(perform: handleEscape)
        .overlay(alignment: .topLeading) {
            // 全局 ⌘F：聚焦工具栏搜索框
            Button("") { searchFocused = true }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                refreshButton
            }
        }
        .uninstallConfirmation(
            package: $pendingUninstall,
            dependents: { state.dependents(of: $0) },
            onConfirm: { pkg in Task { await state.uninstall(pkg) } }
        )
    }

    private var refreshButton: some View {
        Button {
            Task { await state.loadCatalog() }
        } label: {
            if state.isLoadingCatalog {
                ProgressView()
                    .controlSize(.small)
            } else {
                Label("刷新", systemImage: "arrow.clockwise")
            }
        }
        .disabled(state.isLoadingCatalog || state.isTaskRunning)
        .help("重新加载软件包目录")
    }

    private func handleEscape() {
        if !state.searchQuery.isEmpty {
            state.searchQuery = ""
            searchFocused = true
        } else if searchFocused {
            searchFocused = false
        }
    }
}

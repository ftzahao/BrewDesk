//
//  SearchResultsView.swift
//  BrewDesk
//
//  搜索结果视图：由主页搜索框激活，展示匹配 formula / cask 的完整信息。
//

import SwiftUI

struct SearchResultsView: View {
    @ObservedObject var state: AppState
    @State private var pendingUninstall: Package?
    @FocusState private var searchFocused: Bool
    /// 本地选中 ID：避免直接在视图更新周期内修改 @Published 属性
    @State private var localSelection: Package.ID?

    var body: some View {
        TwoColumnPage {
            listColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("搜索结果")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    state.deactivateSearch()
                } label: {
                    Label("返回主页", systemImage: "chevron.left")
                }
                .help("返回主页")
            }
            ToolbarItem(placement: .primaryAction) {
                if state.isSearching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .uninstallConfirmation(
            package: $pendingUninstall,
            dependents: { state.dependents(of: $0) },
            onConfirm: { pkg in Task { await state.uninstall(pkg) } }
        )
        .onAppear { searchFocused = true }
    }

    private var listColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("搜索 formula / cask", text: $state.searchQuery)
                    .textFieldStyle(.roundedBorder)
                    .focused($searchFocused)
                    .onSubmit { Task { await state.runSearch() } }
                    .onChange(of: state.searchQuery) { _, newValue in
                        let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                        if q.isEmpty {
                            state.deactivateSearch()
                        } else {
                            state.scheduleSearch()
                        }
                    }

                Button("搜索") { Task { await state.runSearch() } }
                    .buttonStyle(.glassCapsule)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(
                        state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || state.isSearching || state.isTaskRunning
                    )
            }
            .padding(10)

            List(selection: Binding(
                get: { localSelection },
                set: { newValue in
                    localSelection = newValue
                    DispatchQueue.main.async {
                        state.selectedPackageID = newValue
                    }
                }
            )) {
                ForEach(state.searchResults) { pkg in
                    PackageRowView(package: pkg)
                        .tag(Optional(pkg.id))
                        .contextMenu {
                            if pkg.isInstalled {
                                if pkg.isOutdated {
                                    Button("升级") { Task { await state.upgrade(packages: [pkg]) } }
                                }
                                Button("卸载…", role: .destructive) { pendingUninstall = pkg }
                            } else {
                                Button("安装") { Task { await state.install(pkg) } }
                            }
                        }
                }
            }
            .onReceive(state.$selectedPackageID) { id in
                if localSelection != id {
                    localSelection = id
                }
            }
            .overlay {
                if state.isSearching && state.searchResults.isEmpty {
                    ProgressView("搜索中…")
                } else if state.searchResults.isEmpty {
                    ContentUnavailableView {
                        Label(
                            state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                ? "搜索 Homebrew" : "无结果",
                            systemImage: "magnifyingglass"
                        )
                    } description: {
                        Text(state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                             ? "输入名称关键词，例如 wget、node、visual-studio-code\n输入 2 个字符后会自动搜索"
                             : "换个关键词试试，或按回车立即搜索"
                        ).multilineTextAlignment(.center)
                    }
                }
            }

            HStack {
                Text(state.isSearching ? "搜索中…" :
                     state.searchResults.isEmpty ? " " :
                     "\(state.searchResults.count) 个结果 · \(state.searchResults.filter(\.isInstalled).count) 已安装"
                ).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        }
    }

    private var detailColumn: some View {
        Group {
            if let package = state.searchResults.first(where: { $0.id == state.selectedPackageID }) {
                PackageDetailView(
                    package: package,
                    dependents: state.dependents(of: package),
                    installedNames: state.installedNameSet,
                    isBusy: state.isTaskRunning,
                    onInstall: package.isInstalled ? nil
                        : { Task { await state.install(package) } },
                    onUninstall: package.isInstalled
                        ? { pendingUninstall = package } : nil,
                    onUpgrade: package.isOutdated
                        ? { Task { await state.upgrade(packages: [package]) } } : nil,
                    onPin: package.isInstalled && !package.isPinned
                        ? { Task { await state.pinPackage(package) } } : nil,
                    onUnpin: package.isInstalled && package.isPinned
                        ? { Task { await state.unpinPackage(package) } } : nil,
                    onSelectRelated: { state.selectInstalledPackage(named: $0) }
                )
            } else {
                ContentUnavailableView {
                    Label("选择搜索结果", systemImage: "magnifyingglass")
                } description: {
                    Text("选择左侧结果后可安装、升级或查看依赖。")
                }
            }
        }
    }
}

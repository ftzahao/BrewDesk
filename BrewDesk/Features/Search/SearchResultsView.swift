//
//  SearchResultsView.swift
//  BrewDesk
//
//  搜索结果视图：由主页搜索框激活，展示匹配 formula / cask 的完整信息。
//

import SwiftUI

struct SearchResultsView: View {
    @Bindable var state: AppState
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
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 12, weight: .medium))
                TextField("搜索 formula / cask", text: $state.searchQuery)
                    .textFieldStyle(.plain)
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
                if !state.searchQuery.isEmpty {
                    Button {
                        state.searchQuery = ""
                        searchFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("清空")
                }

                Button("搜索") { Task { await state.runSearch() } }
                    .buttonStyle(.glassCapsule)
                    .keyboardShortcut(.return, modifiers: [])
                    .disabled(
                        state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || state.isSearching || state.isTaskRunning
                    )
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .glassID("home.searchbar")

            List(selection: Binding<Package.ID?>(
                get: {
                    // macOS 26 的 SwiftUI List(selection:) 若持有列表外的 ID，
                    // 滚动目标回映会触发 NSOutlineView 行数不一致断言而闪退；
                    // getter 兜底：只把当前列表内存在的选中项交给 List。
                    guard let id = localSelection,
                          state.searchResults.contains(where: { $0.id == id }) else { return nil }
                    return id
                },
                set: { newValue in
                    // localSelection 同步提交，让选中变更留在点击事务内，
                    // 避免延迟事务与行数据刷新竞态触发 List 崩溃。
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
            .scrollContentBackground(.hidden)
            // 行数据变化时整体重建列表，销毁缓存的滚动目标（见 InstalledView 注释）。
            // id 用轻量内容版本号替代整个行数组：行内容未变化时跳过重建与 O(n) 哈希。
            .id(state.searchStamp)
            // @Observable 下替代 state.$selectedPackageID 的 onReceive：
            // task(id:) 在出现时以当前值启动一次、之后每次变化重启一次，语义等价。
            .task(id: state.selectedPackageID) {
                let id = state.selectedPackageID
                DispatchQueue.main.async {
                    guard localSelection != id else { return }
                    if let id, state.searchResults.contains(where: { $0.id == id }) {
                        localSelection = id
                    } else {
                        // 共享选中 ID 不属于当前列表（被过滤/来自其他页面）时不采纳，
                        // 避免 List 持有无效选中项导致滚动回映崩溃。
                        localSelection = nil
                    }
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

            GlassFooterBar {
                HStack {
                    Text(state.isSearching ? "搜索中…" :
                         state.searchResults.isEmpty ? " " :
                         "\(state.searchResults.count) 个结果 · \(state.searchResults.filter(\.isInstalled).count) 已安装"
                    ).foregroundStyle(.secondary)
                    Spacer()
                }
            }
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
                GlassEmptyState(
                    icon: "magnifyingglass",
                    title: "选择搜索结果",
                    subtitle: "选择左侧结果后可安装、升级或查看依赖。"
                )
            }
        }
    }
}

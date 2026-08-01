//
//  HomeCatalogList.swift
//  BrewDesk
//
//  主页目录列表：分类筛选 + 窗口化渲染 + A-Z 索引 + 空状态。
//

import SwiftUI

struct HomeCatalogList: View {
    @ObservedObject var state: AppState
    @FocusState.Binding var searchFocused: Bool
    let onUninstall: (Package) -> Void

    private static let pageSize = 500

    @State private var localSelection: Package.ID?
    @State private var listStart = 0
    @State private var visibleCount = 500

    // MARK: - 派生数据

    /// 窗口化渲染：始终只展示目录中的一段，保证 List 与无障碍树保持轻量。
    private var displayedPackages: [Package] {
        let filtered = state.homeFilteredCatalog
        guard !filtered.isEmpty else { return [] }
        let start = min(max(listStart, 0), filtered.count - 1)
        let end = min(start + visibleCount, filtered.count)
        return Array(filtered[start..<end])
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                filterBar

                List(selection: Binding(
                    get: { localSelection },
                    set: { newValue in
                        localSelection = newValue
                        DispatchQueue.main.async {
                            state.selectedPackageID = newValue
                        }
                    }
                )) {
                    ForEach(displayedPackages) { pkg in
                        PackageRowView(
                            package: pkg,
                            showKindBadge: false,
                            showIcon: pkg.isInstalled,
                            showInstalledIndicator: true
                        )
                            .tag(Optional(pkg.id))
                            .id(pkg.id)
                            .onAppear {
                                // 滚动接近窗口底部时向下追加一批
                                if pkg.id == displayedPackages.last?.id {
                                    visibleCount = min(
                                        visibleCount + Self.pageSize,
                                        state.homeFilteredCatalog.count - listStart
                                    )
                                }
                            }
                            .contextMenu {
                                if pkg.isInstalled {
                                    if pkg.isOutdated {
                                        Button("升级") {
                                            Task { await state.upgrade(packages: [pkg]) }
                                        }
                                    }
                                    Button("卸载…", role: .destructive) { onUninstall(pkg) }
                                } else {
                                    Button("安装") { Task { await state.install(pkg) } }
                                }
                            }
                    }
                }
                .onChange(of: state.homeKindFilter) { _, _ in
                    resetList(proxy: proxy)
                }
                .onChange(of: state.homeInstalledOnly) { _, _ in
                    resetList(proxy: proxy)
                }
                .onChange(of: state.homeFilteredCatalog.count) { _, _ in
                    let count = state.homeFilteredCatalog.count
                    if count == 0 {
                        listStart = 0
                    } else if listStart >= count {
                        // 目录刷新后窗口起点越界时复位到尾部，避免空白
                        listStart = max(0, count - 1)
                    }
                    visibleCount = min(visibleCount, max(count - listStart, 1))
                }
                .onReceive(state.$selectedPackageID) { id in
                    if localSelection != id {
                        localSelection = id
                    }
                }
                .overlay(alignment: .trailing) {
                    if !state.homeIndexLetters.isEmpty && state.homeFilteredCatalog.count > 100 {
                        HomeAlphabetIndex(
                            letters: state.homeIndexLetters,
                            onSelect: { jumpToLetter($0, proxy: proxy) }
                        )
                    }
                }
                .searchable(text: $state.searchQuery, prompt: "搜索全部 formula 与 cask…")
                .searchFocused($searchFocused)
                .onSubmit(of: .search) {
                    let q = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !q.isEmpty else { return }
                    state.openSearch(query: q)
                }
                .onChange(of: state.searchQuery) { _, newValue in
                    let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    state.scheduleSearchAndActivate()
                }
            }
        }
        .overlay { emptyStates }
        .safeAreaInset(edge: .bottom) { footer }
    }

    // MARK: - 筛选与跳转

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $state.homeKindFilter) {
                Text("全部").tag(Optional<PackageKind>.none)
                Text("Formula").tag(Optional.some(PackageKind.formula))
                Text("Cask").tag(Optional.some(PackageKind.cask))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Toggle("已安装", isOn: $state.homeInstalledOnly)
                .toggleStyle(.checkbox)
                .help("仅显示已安装的软件包")
        }
        .padding(8)
    }

    private func resetList(proxy: ScrollViewProxy) {
        listStart = 0
        visibleCount = Self.pageSize
        DispatchQueue.main.async {
            if let first = state.homeFilteredCatalog.first {
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    private func jumpToLetter(_ letter: String, proxy: ScrollViewProxy) {
        guard let idx = state.homeFilteredCatalog.firstIndex(where: {
            $0.name.lowercased().hasPrefix(letter)
        }) else { return }
        let targetID = state.homeFilteredCatalog[idx].id

        // 把窗口直接移到目标字母附近（目标行必在渲染范围内），再滚动定位
        listStart = max(0, idx - Self.pageSize / 5)
        visibleCount = Self.pageSize
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

    // MARK: - 空状态与页脚

    @ViewBuilder
    private var emptyStates: some View {
        if state.isLoadingCatalog && state.catalog.isEmpty {
            ProgressView("加载全部软件包…")
        } else if state.catalog.isEmpty {
            ContentUnavailableView {
                Label("暂无软件包", systemImage: "square.grid.2x2")
            } description: {
                Text("点击下方按钮重新加载 Homebrew 目录")
            } actions: {
                Button("刷新") { Task { await state.loadCatalog() } }
            }
        } else if state.homeFilteredCatalog.isEmpty {
            ContentUnavailableView {
                Label("没有匹配的软件包", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("试试切换分类，或关闭「仅看已安装」")
            } actions: {
                Button("清除筛选") {
                    state.homeKindFilter = nil
                    state.homeInstalledOnly = false
                    listStart = 0
                    visibleCount = Self.pageSize
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("已显示 \(displayedPackages.count) / 共 \(state.homeFilteredCatalog.count) 项")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            Spacer()
            if state.isLoadingCatalog {
                Text("加载中…")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.bar)
    }
}

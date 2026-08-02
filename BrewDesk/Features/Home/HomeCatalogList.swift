//
//  HomeCatalogList.swift
//  BrewDesk
//
//  主页目录列表：分类筛选 + List 懒加载（按需实例化可见行）+ A-Z 索引 + 空状态。
//

import SwiftUI

struct HomeCatalogList: View {
    @ObservedObject var state: AppState
    @FocusState.Binding var searchFocused: Bool
    let onUninstall: (Package) -> Void

    @State private var localSelection: Package.ID?

    /// 异步绑定工具：避免在视图更新周期内直接修改 @Published 属性（didSet 会同步重建派生数据）
    private func asyncBinding<T>(_ keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(
            get: { state[keyPath: keyPath] },
            set: { newValue in
                DispatchQueue.main.async {
                    state[keyPath: keyPath] = newValue
                }
            }
        )
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                filterBar

                List(selection: Binding<Package.ID?>(
                    get: {
                        // macOS 26 的 SwiftUI List(selection:) 若持有列表外的 ID，
                        // 滚动目标回映会触发 NSOutlineView 行数不一致断言而闪退；
                        // getter 兜底：只把当前列表内存在的选中项交给 List。
                        guard let id = localSelection,
                              state.homeFilteredCatalog.contains(where: { $0.id == id }) else { return nil }
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
                    ForEach(state.homeFilteredCatalog) { pkg in
                        PackageRowView(
                            package: pkg,
                            showKindBadge: false,
                            showIcon: pkg.isInstalled,
                            showInstalledIndicator: true
                        )
                            .tag(Optional(pkg.id))
                            .id(pkg.id)
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
                .scrollContentBackground(.hidden)
                // 行数据变化时整体重建列表，销毁缓存的滚动目标（见 InstalledView 注释）。
                .id(state.homeFilteredCatalog)
                .onChange(of: state.homeKindFilter) { _, _ in
                    scrollToFirst(proxy: proxy)
                }
                .onChange(of: state.homeInstalledOnly) { _, _ in
                    scrollToFirst(proxy: proxy)
                }
                .onReceive(state.$selectedPackageID) { id in
                    DispatchQueue.main.async {
                        guard localSelection != id else { return }
                        if let id,
                           state.homeFilteredCatalog.contains(where: { $0.id == id }) {
                            localSelection = id
                        } else {
                            // 共享选中 ID 不属于当前列表（被过滤/来自其他页面）时不采纳，
                            // 避免 List 持有无效选中项导致滚动回映崩溃。
                            localSelection = nil
                        }
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
            GlassSegmentedControl(
                options: [
                    ("全部", Optional<PackageKind>.none),
                    ("Formula", Optional.some(.formula)),
                    ("Cask", Optional.some(.cask)),
                ],
                selection: asyncBinding(\.homeKindFilter),
                idPrefix: "filter.kind"
            )
            .frame(maxWidth: .infinity)

            Toggle("已安装", isOn: asyncBinding(\.homeInstalledOnly))
                .toggleStyle(.checkbox)
                .help("仅显示已安装的软件包")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .glassID("home.searchbar")
    }

    private func scrollToFirst(proxy: ScrollViewProxy) {
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
                }
            }
        }
    }

    private var footer: some View {
        GlassFooterBar {
            HStack(spacing: 8) {
                Text("共 \(state.homeFilteredCatalog.count) 项")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Spacer()
                if state.isLoadingCatalog {
                    Text("加载中…")
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

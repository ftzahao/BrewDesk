//
//  HomeCatalogList.swift
//  BrewDesk
//
//  主页目录列表：分类筛选 + List 懒加载（按需实例化可见行）+ A-Z 索引 + 空状态。
//

import SwiftUI

struct HomeCatalogList: View {
    @Bindable var state: AppState
    @FocusState.Binding var searchFocused: Bool
    let onUninstall: (Package) -> Void

    @State private var localSelection: Package.ID?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                filterBar

                // 不用 List(selection:)：macOS 的 List 选中引擎会给每行保留 tag/选中结构，
                // 1.6 万行目录实测额外占用约 100MB（约 7KB/行，裸 List 只有其零头），
                // 还带 macOS 26 滚动目标回映的行数断言崩溃风险。
                // 改为行内点击 + 手动高亮，选中交互等价（详情联动、右键菜单、索引跳转不变）。
                List {
                    ForEach(state.homeFilteredCatalog) { pkg in
                        PackageRowView(
                            package: pkg,
                            showKindBadge: false,
                            showIcon: pkg.isInstalled,
                            showInstalledIndicator: true
                        )
                            .contentShape(Rectangle())
                            .background {
                                if localSelection == pkg.id {
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.accentColor.opacity(0.14))
                                }
                            }
                            .onTapGesture {
                                localSelection = pkg.id
                                state.selectedPackageID = pkg.id
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
                .scrollContentBackground(.hidden)
                // 行数据变化时整体重建列表，销毁缓存的滚动目标（见 InstalledView 注释）。
                // id 用轻量内容版本号而非整个数组：避免每次 body 求值对 1.4 万项哈希，
                // 也避免无内容变化的发布（如详情加载同步条目）误触发全表重建。
                .id(state.homeCatalogListStamp)
                .onChange(of: state.homeKindFilter) { _, _ in
                    scrollToFirst(proxy: proxy)
                }
                .onChange(of: state.homeInstalledOnly) { _, _ in
                    scrollToFirst(proxy: proxy)
                }
                // @Observable 下替代 state.$selectedPackageID 的 onReceive：
                // task(id:) 在出现时以当前值启动一次、之后每次变化重启一次，语义等价，
                // 且不再需要 Combine 投影发布器。
                .task(id: state.selectedPackageID) {
                    let id = state.selectedPackageID
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
                    state.scheduleSearch(activateSearchView: true)
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
                selection: state.asyncBinding(\.homeKindFilter),
                idPrefix: "filter.kind"
            )
            .frame(maxWidth: .infinity)

            Toggle("已安装", isOn: state.asyncBinding(\.homeInstalledOnly))
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

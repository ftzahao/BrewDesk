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
    /// 当前悬停行（仅记录最后悬停项，行重建时自动归零）
    @State private var hoveredID: Package.ID?

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                filterBar

                // 不用 List(selection:)：macOS 的 List 选中引擎会给每行保留 tag/选中结构，
                // 1.6 万行目录实测额外占用约 100MB（约 7KB/行，裸 List 只有其零头），
                // 还带 macOS 26 滚动目标回映的行数断言崩溃风险。
                // 改为行内点击 + 手动高亮，选中交互等价（详情联动、右键菜单、索引跳转不变）。
                // 分组渲染：按首字母 A-Z 分段（非字母归 "#"），Section header 随 List 浮动，
                // 行与 header 均为懒实例化，窗口化渲染与大目录性能不冲突。
                List {
                    ForEach(state.homeCatalogSections) { section in
                        Section {
                            ForEach(section.packages) { pkg in
                                row(pkg)
                            }
                        } header: {
                            sectionHeader(section)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                // 去掉行分隔线：分组章节头 + hover/选中高亮已提供视觉层次，
                // 密集目录下无分隔线更干净，也减少每行绘制开销。
                .listRowSeparator(.hidden)
                // 行数据变化时整体重建列表，销毁缓存的滚动目标（见 InstalledView 注释）。
                // id 用轻量内容版本号而非整个数组：避免每次 body 求值对 1.4 万项哈希，
                // 也避免无内容变化的发布（如详情加载同步条目）误触发全表重建。
                .id(state.homeCatalogListStamp)
                .onChange(of: state.homeKindFilter) { _, _ in
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

    // MARK: - 行与章节头

    private func row(_ pkg: Package) -> some View {
        PackageRowView(
            package: pkg,
            showKindBadge: false,
            showIcon: pkg.isInstalled,
            showInstalledIndicator: true
        )
        .contentShape(Rectangle())
        .background {
            RoundedRectangle(cornerRadius: 6)
                .fill(rowBackground(pkg))
        }
        .onHover { hovering in
            // hover 即时切换不带动画：密集目录下鼠标扫过时避免每帧开动画
            hoveredID = hovering ? pkg.id : nil
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

    /// 选中高亮优先于 hover，无悬停/选中时为透明（不加行底色）。
    private func rowBackground(_ pkg: Package) -> Color {
        if localSelection == pkg.id {
            return Color.accentColor.opacity(0.14)
        }
        if hoveredID == pkg.id {
            return Color.primary.opacity(0.06)
        }
        return Color.clear
    }

    /// A-Z 章节头：字母 + 组内数量，List 原生浮动（sticky），
    /// 材质背景保证行内容滚过时可读。
    private func sectionHeader(_ section: AppState.CatalogSection) -> some View {
        HStack(spacing: 6) {
            Text(section.letter.uppercased())
                .font(.system(size: 12, weight: .bold, design: .rounded))
            Text("\(section.packages.count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.tertiary)
            Spacer(minLength: 0)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial)
    }

    // MARK: - 筛选与跳转

    private var filterBar: some View {
        // 分段控件用增强版 Liquid Glass（选中胶囊 spring 滑动 + 水滴质感），
        // 原生 Picker 无法注入切换动画，故由自定义控件实现。
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
        // 定位到该分组第一个包，让 sticky 章节头正好浮在列表顶部
        guard let section = state.homeCatalogSections.first(where: { $0.letter == letter }),
              let targetID = section.packages.first?.id else { return }
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
                Text("试试切换分类")
            } actions: {
                Button("清除筛选") {
                    state.homeKindFilter = nil
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

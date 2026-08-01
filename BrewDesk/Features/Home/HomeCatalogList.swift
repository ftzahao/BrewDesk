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
                .onChange(of: state.homeKindFilter) { _, _ in
                    scrollToFirst(proxy: proxy)
                }
                .onChange(of: state.homeInstalledOnly) { _, _ in
                    scrollToFirst(proxy: proxy)
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
        HStack(spacing: 8) {
            Text("共 \(state.homeFilteredCatalog.count) 项")
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

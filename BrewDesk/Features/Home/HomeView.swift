//
//  HomeView.swift
//  BrewDesk
//
//  主页：概览统计 + 全部 formula / cask 目录，顶部搜索框进入搜索结果视图。
//  目录采用窗口化渲染：只实例化当前窗口内的行，A-Z 跳转时把窗口移到目标字母附近。
//

import AppKit
import SwiftUI

struct HomeView: View {
    @ObservedObject var state: AppState
    @State private var kindFilter: PackageKind?
    @State private var installedOnly = false
    @State private var pendingUninstall: Package?
    @State private var localSelection: Package.ID?
    @State private var isLoadingDetail = false
    @State private var listStart = 0
    @State private var visibleCount = 500
    @State private var hoveredStatID: String?
    @State private var hoveredLetter: String?
    @FocusState private var searchFocused: Bool

    private static let pageSize = 500

    // MARK: - 派生数据

    private var filteredCatalog: [Package] {
        let base = kindFilter.map { kind in
            state.catalog.filter { $0.kind == kind }
        } ?? state.catalog
        guard installedOnly else { return base }
        return base.filter(\.isInstalled)
    }

    /// 窗口化渲染：始终只展示目录中的一段，保证 List 与无障碍树保持轻量。
    private var displayedPackages: [Package] {
        guard !filteredCatalog.isEmpty else { return [] }
        let start = min(max(listStart, 0), filteredCatalog.count - 1)
        let end = min(start + visibleCount, filteredCatalog.count)
        return Array(filteredCatalog[start..<end])
    }

    private var selectedCatalogPackage: Package? {
        guard let selectedPackageID = state.selectedPackageID else { return nil }
        return filteredCatalog.first { $0.id == selectedPackageID }
    }

    private var installedCount: Int {
        state.catalog.lazy.filter(\.isInstalled).count
    }

    private var formulaCount: Int {
        state.catalog.lazy.filter { $0.kind == .formula }.count
    }

    private var caskCount: Int {
        state.catalog.count - formulaCount
    }

    private var indexLetters: [String] {
        var set = Set<String>()
        for pkg in filteredCatalog {
            guard let first = pkg.name.first, first.isLetter else { continue }
            set.insert(String(first).lowercased())
        }
        return set.sorted()
    }

    // MARK: - 主视图

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            HStack(spacing: 0) {
                listColumn
                    .frame(minWidth: 270, idealWidth: 340, maxWidth: 460)
                    .frame(maxHeight: .infinity)
                    .layoutPriority(0)

                detailColumn
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background {
                        Rectangle()
                            .fill(.regularMaterial)
                            .ignoresSafeArea()
                    }
                    .layoutPriority(1)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("主页")
        .onExitCommand(perform: handleEscape)
        .overlay(alignment: .topLeading) {
            // 全局 ⌘F：聚焦主页搜索框
            Button("") { searchFocused = true }
                .buttonStyle(.plain)
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0)
                .opacity(0)
                .accessibilityHidden(true)
        }
        .uninstallConfirmation(
            package: $pendingUninstall,
            dependents: { state.dependents(of: $0) },
            onConfirm: { pkg in Task { await state.uninstall(pkg) } }
        )
    }

    private func handleEscape() {
        if !state.searchQuery.isEmpty {
            state.searchQuery = ""
            searchFocused = true
        } else if searchFocused {
            searchFocused = false
        }
    }

    // MARK: - 头部（标题 + 搜索 + 概览卡片）

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("软件包目录")
                        .font(.system(size: 17, weight: .semibold))
                    Text("浏览全部可安装的 formula 与 cask")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                searchField

                refreshButton
            }

            statsRow
        }
        .padding(EdgeInsets(top: 14, leading: 16, bottom: 12, trailing: 16))
        .background {
            Rectangle()
                .fill(.bar)
                .ignoresSafeArea()
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

            TextField("搜索全部 formula 与 cask…", text: $state.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .font(.system(size: 14))
                .onSubmit {
                    let q = state.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !q.isEmpty else { return }
                    state.openSearch(query: q)
                }
                .onChange(of: state.searchQuery) { _, newValue in
                    let q = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard q.count >= 2 else { return }
                    state.scheduleSearchAndActivate()
                }

            if !state.searchQuery.isEmpty {
                Button {
                    state.searchQuery = ""
                    searchFocused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("清空 (Esc)")
            }

            Text("⌘F")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.tertiary)
                .help("⌘F 聚焦搜索")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(minWidth: 260, idealWidth: 400, maxWidth: 480)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(
                    searchFocused ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08),
                    lineWidth: searchFocused ? 1.5 : 1
                )
        }
        .shadow(color: .black.opacity(searchFocused ? 0.07 : 0), radius: 6, y: 2)
        .animation(.easeInOut(duration: 0.15), value: searchFocused)
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
        .buttonStyle(.glassCapsule)
        .disabled(state.isLoadingCatalog || state.isTaskRunning)
        .help("重新加载软件包目录")
    }

    private var statsRow: some View {
        HStack(spacing: 10) {
            statCard(
                id: "installed",
                icon: "shippingbox.fill",
                tint: .blue,
                title: "已安装",
                value: installedCount,
                action: { state.selectedSidebar = .installed }
            )
            statCard(
                id: "outdated",
                icon: "arrow.triangle.2.circlepath",
                tint: .orange,
                title: "可更新",
                value: state.outdated.count,
                highlighted: state.outdated.count > 0,
                action: { state.selectedSidebar = .outdated }
            )
            statCard(
                id: "formula",
                icon: "terminal.fill",
                tint: .green,
                title: "Formula",
                value: formulaCount,
                active: kindFilter == .formula,
                action: toggleFilter(.formula)
            )
            statCard(
                id: "cask",
                icon: "app.badge.fill",
                tint: .purple,
                title: "Cask",
                value: caskCount,
                active: kindFilter == .cask,
                action: toggleFilter(.cask)
            )
            statCard(
                id: "services",
                icon: "bolt.horizontal.circle.fill",
                tint: .red,
                title: "服务运行中",
                value: state.runningServiceCount,
                action: { state.selectedSidebar = .services }
            )
        }
    }

    private func toggleFilter(_ kind: PackageKind) -> () -> Void {
        {
            kindFilter = (kindFilter == kind) ? nil : kind
        }
    }

    private func statCard(
        id: String,
        icon: String,
        tint: Color,
        title: String,
        value: Int,
        highlighted: Bool = false,
        active: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        let effectiveTint = active ? Color.accentColor : tint
        return Button(action: action) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(effectiveTint.opacity(active ? 0.18 : 0.13))
                        .frame(width: 34, height: 34)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(effectiveTint)
                }

                VStack(alignment: .leading, spacing: 1) {
                    Text("\(value)")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if active {
                    Text("筛选中")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor.opacity(0.12)))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.thinMaterial)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(
                        highlighted
                            ? Color.orange.opacity(0.35)
                            : (active ? Color.accentColor.opacity(0.45) : Color.primary.opacity(0.06)),
                        lineWidth: highlighted || active ? 1.2 : 1
                    )
            }
            .scaleEffect(hoveredStatID == id ? 1.018 : 1)
            .shadow(color: .black.opacity(hoveredStatID == id ? 0.08 : 0), radius: 5, y: 2)
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onHover { hovering in
            hoveredStatID = hovering ? id : nil
        }
        .animation(.easeOut(duration: 0.15), value: hoveredStatID)
    }

    // MARK: - 目录列表

    private var listColumn: some View {
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
                                        filteredCatalog.count - listStart
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
                                    Button("卸载…", role: .destructive) { pendingUninstall = pkg }
                                } else {
                                    Button("安装") { Task { await state.install(pkg) } }
                                }
                            }
                    }
                }
                .onChange(of: kindFilter) { _, _ in
                    resetList(proxy: proxy)
                }
                .onChange(of: installedOnly) { _, _ in
                    resetList(proxy: proxy)
                }
                .onChange(of: filteredCatalog.count) { _, _ in
                    if filteredCatalog.count == 0 {
                        listStart = 0
                    } else if listStart >= filteredCatalog.count {
                        // 目录刷新后窗口起点越界时复位到尾部，避免空白
                        listStart = max(0, filteredCatalog.count - 1)
                    }
                    visibleCount = min(visibleCount, max(filteredCatalog.count - listStart, 1))
                }
                .onReceive(state.$selectedPackageID) { id in
                    if localSelection != id {
                        localSelection = id
                    }
                }
                .overlay(alignment: .trailing) {
                    if !indexLetters.isEmpty && filteredCatalog.count > 100 {
                        alphabetIndex(proxy: proxy)
                    }
                }
            }
        }
        .overlay { emptyStates }
        .safeAreaInset(edge: .bottom) { footer }
    }

    private func resetList(proxy: ScrollViewProxy) {
        listStart = 0
        visibleCount = Self.pageSize
        DispatchQueue.main.async {
            if let first = filteredCatalog.first {
                proxy.scrollTo(first.id, anchor: .top)
            }
        }
    }

    private var filterBar: some View {
        HStack(spacing: 10) {
            Picker("类型", selection: $kindFilter) {
                Text("全部").tag(Optional<PackageKind>.none)
                Text("Formula").tag(Optional.some(PackageKind.formula))
                Text("Cask").tag(Optional.some(PackageKind.cask))
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: .infinity)

            Toggle("已安装", isOn: $installedOnly)
                .toggleStyle(.checkbox)
                .help("仅显示已安装的软件包")
        }
        .padding(8)
    }

    private func alphabetIndex(proxy: ScrollViewProxy) -> some View {
        VStack(spacing: 1) {
            ForEach(indexLetters, id: \.self) { letter in
                Text(letter.uppercased())
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(hoveredLetter == letter ? .primary : .secondary)
                    .frame(width: 18, height: 13)
                    .background {
                        if hoveredLetter == letter {
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.accentColor.opacity(0.16))
                        }
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        hoveredLetter = hovering ? letter : nil
                    }
                    .onTapGesture {
                        jumpToLetter(letter, proxy: proxy)
                    }
                    .accessibilityLabel("跳到以 \(letter.uppercased()) 开头的软件包")
                    .accessibilityAddTraits(.isButton)
                    .accessibilityIdentifier("index-\(letter)")
            }
        }
        .accessibilityElement(children: .contain)
        .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onTapGesture { /* 吞掉空白区域的点击，避免穿透到列表行 */ }
        .padding(.vertical, 4)
        .padding(.horizontal, 2)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.thinMaterial)
                .shadow(color: .black.opacity(0.08), radius: 3, y: 1)
        }
        .padding(.trailing, 4)
        .help("点击跳转到以该字母开头的软件包")
    }

    private func jumpToLetter(_ letter: String, proxy: ScrollViewProxy) {
        guard let idx = filteredCatalog.firstIndex(where: {
            $0.name.lowercased().hasPrefix(letter)
        }) else { return }
        let targetID = filteredCatalog[idx].id

        // 把窗口直接移到目标字母附近（目标行必在渲染范围内），再滚动定位
        listStart = max(0, idx - Self.pageSize / 5)
        visibleCount = Self.pageSize
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(targetID, anchor: .top)
            }
        }
    }

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
        } else if filteredCatalog.isEmpty {
            ContentUnavailableView {
                Label("没有匹配的软件包", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("试试切换分类，或关闭「仅看已安装」")
            } actions: {
                Button("清除筛选") {
                    kindFilter = nil
                    installedOnly = false
                    listStart = 0
                    visibleCount = Self.pageSize
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text("已显示 \(displayedPackages.count) / 共 \(filteredCatalog.count) 项")
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

    // MARK: - 详情

    private var detailColumn: some View {
        Group {
            if let package = selectedCatalogPackage {
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
                .id(package.id)
                .overlay {
                    if isLoadingDetail {
                        ProgressView("加载详情…")
                            .padding(12)
                            .background(
                                .regularMaterial,
                                in: RoundedRectangle(cornerRadius: 10)
                            )
                            .allowsHitTesting(false)
                    }
                }
                .task(id: package.id) {
                    if state.catalogDetailCache[package.id] == nil {
                        isLoadingDetail = true
                    }
                    _ = await state.catalogDetail(for: package)
                    isLoadingDetail = false
                }
            } else {
                emptyDetail
            }
        }
    }

    private var emptyDetail: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 76, height: 76)
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(Color.accentColor)
            }

            VStack(spacing: 4) {
                Text("选择一个软件包")
                    .font(.title3.weight(.semibold))
                Text("查看完整信息、依赖关系，并安装或升级")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                shortcutHint("⌘F", "聚焦搜索")
                shortcutHint("↵", "打开搜索结果")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Capsule().fill(.thinMaterial))
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

//
//  InstalledView.swift
//  BrewDesk
//

import AppKit
import SwiftUI

struct InstalledView: View {
    var state: AppState
    @State private var listFilter = ""
    @State private var pendingUninstall: Package?
    /// 本地选中 ID：避免直接在视图更新周期内修改 @Published 属性
    @State private var localSelection: Package.ID?

    private var packages: [Package] {
        let base = state.filteredInstalled
        let q = listFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.desc?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    /// 轻量列表 stamp：仅当行数据来源（过滤结果缓存 / 过滤词）变化时变化，
    /// 触发 List 重建以销毁缓存的滚动目标（macOS 26 崩溃规避），
    /// 替代对整行数组做 O(n) 哈希的 `.id(packages)`。
    /// 类型/仅手动筛选已折叠进 installedFilterStamp（AppState 内过滤缓存重建时递增）。
    private var listStamp: ListStamp {
        ListStamp(
            dataVersion: state.installedFilterStamp,
            filterText: listFilter
        )
    }

    private struct ListStamp: Hashable {
        let dataVersion: Int
        let filterText: String
    }

    var body: some View {
        VStack(spacing: 0) {
            TwoColumnPage {
                listColumn
            } detail: {
                detailColumn
            }
        }
        .navigationTitle("已安装")
        .navigationSubtitle("管理本机已安装的 formula 与 cask")
        .uninstallConfirmation(
            package: $pendingUninstall,
            dependents: { state.dependents(of: $0) },
            onConfirm: { pkg in Task { await state.uninstall(pkg) } }
        )
        .task {
            await state.loadInstalledIfNeeded()
        }
    }

    private var listColumn: some View {
        List(selection: Binding<Package.ID?>(
            get: {
                // macOS 26 的 SwiftUI List(selection:) 若持有列表外的 ID，
                // 滚动目标回映（reflectScrollTarget）会触发 NSOutlineView
                // 行数不一致断言（ViewListTree.visitItem）而闪退。
                // getter 兜底：只把当前列表内存在的选中项交给 List。
                guard let id = localSelection,
                      packages.contains(where: { $0.id == id }) else { return nil }
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
            ForEach(packages) { pkg in
                PackageRowView(package: pkg)
                    .tag(Optional(pkg.id))
                    .id(pkg.id)
                    .contextMenu {
                        if pkg.isOutdated {
                            Button("升级") { Task { await state.upgrade(packages: [pkg]) } }
                                .disabled(pkg.isPinned || state.isTaskRunning)
                        }
                        if pkg.isPinned {
                            Button("取消固定") { Task { await state.unpinPackage(pkg) } }
                                .disabled(state.isTaskRunning)
                        } else {
                            Button("固定版本") { Task { await state.pinPackage(pkg) } }
                                .disabled(state.isTaskRunning)
                        }
                        Button("复制名称") { copy(pkg.name) }
                        Divider()
                        Button("卸载…", role: .destructive) { pendingUninstall = pkg }
                    }
            }
        }
        .scrollContentBackground(.hidden)
        // macOS 26 的 List(selection:) 在选中时会缓存滚动目标，数据刷新/过滤使行集合
        // 变化后，reflectScrollTarget 用缓存目标算行号会越过 NSOutlineView 行数，
        // 触发 ViewListTree.visitItem 断言闪退。用 .id(行数据) 让行变化时整体重建列表，
        // 旧列表（含缓存目标）随重建销毁，新列表从修剪过的 binding 初始化，杜绝该窗口。
        // id 用轻量 stamp（数据版本 + 筛选条件 + 过滤词）而非整个行数组：
        // 语义与 .id(packages) 一致（行变化才重建），但每次 body 求值只需哈希 4 个小值。
        .id(listStamp)
        // @Observable 下替代 state.$selectedPackageID 的 onReceive：
        // task(id:) 在出现时以当前值启动一次、之后每次变化重启一次，语义等价。
        .task(id: state.selectedPackageID) {
            let id = state.selectedPackageID
            DispatchQueue.main.async {
                guard localSelection != id else { return }
                if let id, packages.contains(where: { $0.id == id }) {
                    localSelection = id
                } else {
                    // 共享选中 ID 不属于当前列表（被过滤/来自其他页面）时不采纳，
                    // 避免 List 持有无效选中项导致滚动回映崩溃。
                    localSelection = nil
                }
            }
        }
        .overlay {
            if state.isLoadingInstalled && state.installed.isEmpty {
                ProgressView("加载已安装软件…")
            } else if packages.isEmpty { emptyList }
        }
        .searchable(text: $listFilter, prompt: "过滤已安装")
        .toolbar {
            ToolbarItemGroup {
                Picker("类型", selection: state.asyncBinding(\.kindFilter)) {
                    Text("全部").tag(Optional<PackageKind>.none)
                    Text("Formula").tag(Optional.some(PackageKind.formula))
                    Text("Cask").tag(Optional.some(PackageKind.cask))
                }.pickerStyle(.segmented).frame(width: 200)
                Toggle("仅手动安装", isOn: state.asyncBinding(\.showOnlyRequested))
                    .toggleStyle(.checkbox)
                    .help("隐藏作为依赖被拉起的 formula")
                    .padding(.horizontal, 12)
            }
            ToolbarItem {
                Button { Task { await state.loadInstalled() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(state.isLoadingInstalled || state.isTaskRunning)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GlassFooterBar {
                HStack {
                    Text(state.showOnlyRequested
                         ? "\(packages.count) 项（仅手动）· 共 \(state.installed.count) 已安装"
                         : "\(packages.count) 项")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var emptyList: some View {
        if !listFilter.isEmpty || state.kindFilter != nil || state.showOnlyRequested {
            ContentUnavailableView {
                Label("没有匹配的软件包", systemImage: "line.3.horizontal.decrease.circle")
            } description: {
                Text("试试清空过滤条件，或关闭「仅手动安装」。")
            } actions: {
                Button("重置过滤") {
                    listFilter = ""
                    DispatchQueue.main.async {
                        state.kindFilter = nil
                        state.showOnlyRequested = false
                    }
                }
            }
        } else {
            ContentUnavailableView("尚未安装软件包", systemImage: "shippingbox")
        }
    }

    private var detailColumn: some View {
        Group {
            // 只在「当前显示列表」和「已安装全量」中查找：与旧逻辑
            // （selectedPackage 三数组回退 + 两次 contains）语义等价，
            // 但把最多 5 次线性扫描降到 2 次，且不再在已安装页误读搜索结果。
            if let id = state.selectedPackageID,
               let package = packages.first(where: { $0.id == id })
                    ?? state.installed.first(where: { $0.id == id }) {
                PackageDetailView(
                    package: package,
                    dependents: state.dependents(of: package),
                    installedNames: state.installedNameSet,
                    isBusy: state.isTaskRunning,
                    onUninstall: { pendingUninstall = package },
                    onUpgrade: package.isOutdated
                        ? { Task { await state.upgrade(packages: [package]) } } : nil,
                    onPin: package.isPinned ? nil
                        : { Task { await state.pinPackage(package) } },
                    onUnpin: package.isPinned
                        ? { Task { await state.unpinPackage(package) } } : nil,
                    onSelectRelated: { state.selectInstalledPackage(named: $0) }
                )
            } else {
                GlassEmptyState(
                    icon: "shippingbox",
                    title: "选择一个软件包",
                    subtitle: "在左侧列表中选择，可查看详情、升级或卸载。"
                )
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

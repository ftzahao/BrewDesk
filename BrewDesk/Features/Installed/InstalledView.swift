//
//  InstalledView.swift
//  BrewDesk
//

import AppKit
import SwiftUI

struct InstalledView: View {
    @ObservedObject var state: AppState
    @State private var listFilter = ""
    @State private var pendingUninstall: Package?
    /// 本地选中 ID：避免直接在视图更新周期内修改 @Published 属性
    @State private var localSelection: Package.ID?

    /// 异步绑定工具：避免在视图更新周期内直接修改 @Published 属性
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

    private var packages: [Package] {
        let base = state.filteredInstalled
        let q = listFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return base }
        return base.filter {
            $0.name.localizedCaseInsensitiveContains(q)
                || ($0.desc?.localizedCaseInsensitiveContains(q) ?? false)
        }
    }

    var body: some View {
        TwoColumnPage {
            listColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("已安装")
        .uninstallConfirmation(
            package: $pendingUninstall,
            dependents: { state.dependents(of: $0) },
            onConfirm: { pkg in Task { await state.uninstall(pkg) } }
        )
    }

    private var listColumn: some View {
        List(selection: Binding(
            get: { localSelection },
            set: { newValue in
                localSelection = newValue
                DispatchQueue.main.async {
                    state.selectedPackageID = newValue
                }
            }
        )) {
            ForEach(packages) { pkg in
                PackageRowView(package: pkg)
                    .tag(Optional(pkg.id))
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
        .onReceive(state.$selectedPackageID) { id in
            if localSelection != id {
                localSelection = id
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
                Picker("类型", selection: asyncBinding(\.kindFilter)) {
                    Text("全部").tag(Optional<PackageKind>.none)
                    Text("Formula").tag(Optional.some(PackageKind.formula))
                    Text("Cask").tag(Optional.some(PackageKind.cask))
                }.pickerStyle(.segmented).frame(width: 200)
                Toggle("仅手动安装", isOn: asyncBinding(\.showOnlyRequested))
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
            HStack {
                Text(state.showOnlyRequested
                     ? "\(packages.count) 项（仅手动）· 共 \(state.installed.count) 已安装"
                     : "\(packages.count) 项")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
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
            if let package = state.selectedPackage,
               packages.contains(where: { $0.id == package.id })
                    || state.installed.contains(where: { $0.id == package.id }) {
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
                ContentUnavailableView {
                    Label("选择一个软件包", systemImage: "shippingbox")
                } description: {
                    Text("在左侧列表中选择，可查看详情、升级或卸载。")
                }
            }
        }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

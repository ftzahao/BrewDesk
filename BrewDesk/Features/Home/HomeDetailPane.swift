//
//  HomeDetailPane.swift
//  BrewDesk
//
//  主页详情栏：选中软件包的详情 / 加载状态 / 未选择时的空状态。
//

import SwiftUI

struct HomeDetailPane: View {
    @ObservedObject var state: AppState
    let onUninstall: (Package) -> Void

    @State private var isLoadingDetail = false

    private var selectedCatalogPackage: Package? {
        guard let id = state.selectedPackageID,
              let idx = state.homeCatalogIndex[id] else { return nil }
        return state.homeFilteredCatalog[idx]
    }

    var body: some View {
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
                        ? { onUninstall(package) } : nil,
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
        GlassEmptyState(
            icon: "square.grid.2x2",
            title: "选择一个软件包",
            subtitle: "查看完整信息、依赖关系，并安装或升级"
        ) {
            HStack(spacing: 8) {
                shortcutHint("⌘F", "聚焦搜索")
                shortcutHint("↵", "打开搜索结果")
            }
        }
    }

    private func shortcutHint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 6) {
            Text(key)
                .font(.caption.monospaced().weight(.semibold))
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .glassEffect(.regular, in: Capsule())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

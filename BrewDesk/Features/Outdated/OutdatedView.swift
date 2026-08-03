//
//  OutdatedView.swift
//  BrewDesk
//

import SwiftUI

struct OutdatedView: View {
    @ObservedObject var state: AppState
    @State private var selection = Set<Package.ID>()

    private var packages: [Package] { state.outdated }
    private var selectedPackages: [Package] { packages.filter { selection.contains($0.id) } }

    var body: some View {
        VStack(spacing: 0) {
            TwoColumnPage {
                listColumn
            } detail: {
                detailColumn
            }
        }
        .navigationTitle("可更新")
        .navigationSubtitle("升级已安装的 formula 与 cask 到最新版本")
        .onChange(of: selection) { _, newValue in
            DispatchQueue.main.async {
                state.setSelectedPackageID(newValue.first)
            }
        }
        .task {
            await state.loadOutdatedIfNeeded()
        }
    }

    private var listColumn: some View {
        List(selection: Binding<Set<Package.ID>>(
            get: {
                // getter 先剔除已不在列表中的 ID（如升级完成的包），
                // 避免 List 持有无效选中项在滚动目标回映时触发断言崩溃。
                let valid = Set(packages.map(\.id))
                return selection.intersection(valid)
            },
            set: { selection = $0 }
        )) {
            ForEach(packages) { pkg in
                PackageRowView(package: pkg)
                    .tag(pkg.id)
                    .contextMenu {
                        Button("升级") { Task { await state.upgrade(packages: [pkg]) } }
                            .disabled(state.isTaskRunning || pkg.isPinned)
                    }
            }
        }
        .scrollContentBackground(.hidden)
        // 行数据变化时整体重建列表，销毁缓存的滚动目标（见 InstalledView 注释）。
        .id(packages)
        .overlay {
            if state.isLoadingOutdated && packages.isEmpty {
                VStack(spacing: 12) {
                    ProgressView("检查更新…")
                    Button("取消") { state.cancelOutdatedLoading() }
                        .buttonStyle(.glassCapsule)
                        .controlSize(.small)
                }
            } else if packages.isEmpty {
                ContentUnavailableView {
                    Label("全部是最新的", systemImage: "checkmark.seal.fill")
                } description: {
                    Text("没有可升级的 formula 或 cask。可以先点击 \"更新 Homebrew\" 刷新索引。")
                }
            }
        }
        .toolbar {
            ToolbarItemGroup {
                Button { Task { await state.brewUpdate() } } label: {
                    Label(
                        "更新 Homebrew",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                    .help("更新 Homebrew")
                }
                .disabled(state.isTaskRunning)
                Button { Task { await state.upgrade(packages: selectedPackages) } } label: {
                    Label("升级所选", systemImage: "arrow.up.circle")
                        .help("升级所选")
                }
                .disabled(selectedPackages.isEmpty || state.isTaskRunning)
                Button { Task { await state.upgradeAll() } } label: {
                    Label("全部升级", systemImage: "arrow.up.circle.fill")
                        .help("全部升级")
                }
                .disabled(packages.isEmpty || state.isTaskRunning)
                .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            ToolbarItem {
                Button { Task { await state.loadOutdated() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise").help("刷新")
                }.disabled(state.isLoadingOutdated || state.isTaskRunning)
            }
        }
        .safeAreaInset(edge: .bottom) {
            GlassFooterBar {
                HStack {
                    Text(packages.isEmpty ? "0 项可更新" : "\(packages.count) 项可更新")
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !selection.isEmpty {
                        Text("已选 \(selection.count)")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let id = state.selectedPackageID,
               let package = packages.first(where: { $0.id == id }) {
                PackageDetailView(
                    package: package,
                    dependents: state.dependents(of: package),
                    installedNames: state.installedNameSet,
                    isBusy: state.isTaskRunning,
                    onUpgrade: { Task { await state.upgrade(packages: [package]) } },
                    onPin: package.isPinned ? nil
                        : { Task { await state.pinPackage(package) } },
                    onUnpin: package.isPinned
                        ? { Task { await state.unpinPackage(package) } } : nil,
                    onSelectRelated: { state.selectInstalledPackage(named: $0) }
                )
            } else if packages.isEmpty {
                GlassEmptyState(
                    icon: "checkmark.seal.fill",
                    title: "无需更新",
                    subtitle: "所有已安装软件都已是最新版本。",
                    tint: .green
                )
            } else {
                GlassEmptyState(
                    icon: "arrow.triangle.2.circlepath",
                    title: "选择要查看的软件包",
                    subtitle: "可多选后点击「升级所选」，或直接全部升级。"
                )
            }
        }
    }
}

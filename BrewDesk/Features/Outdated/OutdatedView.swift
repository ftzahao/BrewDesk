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
        TwoColumnPage {
            listColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("可更新")
        .onChange(of: selection) { _, newValue in
            state.setSelectedPackageID(newValue.first)
        }
    }

    private var listColumn: some View {
        List(selection: $selection) {
            ForEach(packages) { pkg in
                PackageRowView(package: pkg)
                    .tag(pkg.id)
                    .contextMenu {
                        Button("升级") { Task { await state.upgrade(packages: [pkg]) } }
                            .disabled(state.isTaskRunning || pkg.isPinned)
                    }
            }
        }
        .overlay {
            if state.isLoadingOutdated && packages.isEmpty {
                ProgressView("检查更新…")
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
                Button("更新 Homebrew") { Task { await state.brewUpdate() } }
                    .disabled(state.isTaskRunning)
                Button("升级所选") { Task { await state.upgrade(packages: selectedPackages) } }
                    .disabled(selectedPackages.isEmpty || state.isTaskRunning)
                Button("全部升级") { Task { await state.upgradeAll() } }
                    .disabled(packages.isEmpty || state.isTaskRunning)
                    .keyboardShortcut("u", modifiers: [.command, .shift])
            }
            ToolbarItem {
                Button { Task { await state.loadOutdated() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(state.isLoadingOutdated || state.isTaskRunning)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(packages.isEmpty ? "0 项可更新" : "\(packages.count) 项可更新")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                if !selection.isEmpty {
                    Text("已选 \(selection.count)").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
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
                ContentUnavailableView {
                    Label("无需更新", systemImage: "arrow.triangle.2.circlepath")
                } description: { Text("所有已安装软件都已是最新版本。") }
            } else {
                ContentUnavailableView {
                    Label("选择要查看的软件包", systemImage: "arrow.triangle.2.circlepath")
                } description: { Text("可多选后点击「升级所选」，或直接全部升级。") }
            }
        }
    }
}

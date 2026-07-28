//
//  TapsView.swift
//  BrewDesk
//

import SwiftUI

struct TapsView: View {
    @ObservedObject var state: AppState
    @State private var showAddTap = false
    @State private var newTapName = ""
    @State private var pendingRemove: BrewTap?
    @State private var confirmRemove = false
    @State private var pendingInstall: Package?
    @State private var confirmInstall = false
    @State private var viewingPackage: Package?
    @State private var pendingTrust: BrewTap?
    @State private var confirmTrust = false
    @State private var pendingUntrust: BrewTap?
    @State private var confirmUntrust = false

    var body: some View {
        TwoColumnPage {
            listColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("Taps")
        .alert("添加 Tap", isPresented: $showAddTap) {
            TextField("user/repo", text: $newTapName)
            Button("添加") {
                let name = newTapName.trimmingCharacters(in: .whitespacesAndNewlines)
                newTapName = ""
                Task { await state.addTap(name) }
            }
            Button("取消", role: .cancel) { newTapName = "" }
        } message: {
            Text("输入 GitHub tap 名称，例如 user/repo")
        }
        .alert("确认删除？", isPresented: $confirmRemove, presenting: pendingRemove) { tap in
            Button("删除", role: .destructive) {
                Task { await state.removeTap(tap.name) }
            }
            Button("取消", role: .cancel) {}
        } message: { tap in
            Text("将移除 Tap「\(tap.name)」及其所有 formula。")
        }
        .sheet(item: $viewingPackage) { pkg in
            PackageSheet(package: pkg, state: state)
        }
        .alert("信任此 Tap？", isPresented: $confirmTrust, presenting: pendingTrust) { tap in
            Button("信任") {
                Task { await state.trustTap(tap.name) }
            }
            Button("取消", role: .cancel) {}
        } message: { tap in
            Text("信任「\(tap.name)」后，将可安装该 Tap 内的所有软件包。")
        }
        .alert("取消信任？", isPresented: $confirmUntrust, presenting: pendingUntrust) { tap in
            Button("取消信任", role: .destructive) {
                Task { await state.untrustTap(tap.name) }
            }
            Button("取消", role: .cancel) {}
        } message: { tap in
            Text("取消信任后，将无法继续安装「\(tap.name)」内的任意包。已安装的包不受影响，可正常使用。")
        }
    }

    private var listColumn: some View {
        List {
            Section {
                ForEach(state.taps) { tap in
                    TapRow(tap: tap, isSelected: state.selectedTapID == tap.id)
                        .onTapGesture { selectTap(tap) }
                        .contextMenu {
                            Button("浏览包") { selectTap(tap) }
                            Divider()
                            if tap.isOfficial {
                                Label("官方源，不可删除", systemImage: "checkmark.circle")
                                    .disabled(true)
                            } else {
                                Button("删除…", role: .destructive) {
                                    pendingRemove = tap
                                    confirmRemove = true
                                }
                            }
                            if !tap.isOfficial {
                                if tap.isTrusted {
                                    Button("取消信任") {
                                        pendingUntrust = tap
                                        confirmUntrust = true
                                    }
                                    .disabled(state.isTaskRunning)
                                } else {
                                    Button("信任此 Tap") {
                                        pendingTrust = tap
                                        confirmTrust = true
                                    }
                                    .disabled(state.isTaskRunning)
                                }
                            }
                            Button("复制名称") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(tap.name, forType: .string)
                            }
                        }
                }
            } header: {
                HStack {
                    Text("\(state.taps.count) 个 Tap")
                    Spacer()
                    Button { showAddTap = true } label: {
                        Label("添加", systemImage: "plus")
                    }
                    .buttonStyle(.glassCapsule)
                    .controlSize(.small)
                    .disabled(state.isTaskRunning)
                }
            }
        }
        .overlay {
            if state.isLoadingTaps && state.taps.isEmpty {
                ProgressView("加载 Taps…")
            } else if state.taps.isEmpty {
                ContentUnavailableView {
                    Label("没有安装 Tap", systemImage: "square.grid.2x2")
                } description: {
                    Text("点击上方添加按钮添加第三方 Tap。")
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await state.loadTaps() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(state.isLoadingTaps || state.isTaskRunning)
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let tapID = state.selectedTapID,
               let tap = state.taps.first(where: { $0.id == tapID }) {
                TapDetailView(
                    tap: tap,
                    state: state,
                    isLoading: state.isLoadingTapPackages,
                    onTapPackage: { name in
                        Task {
                            if let pkg = await state.lookupTapPackage(named: name) {
                                viewingPackage = pkg
                            } else {
                                // Fallback: go to search
                                state.selectedSidebar = .search
                                state.searchQuery = name
                                await state.runSearch()
                            }
                        }
                    },
                    onInstall: { pkg in
                        pendingInstall = pkg
                        confirmInstall = true
                    },
                    onUninstall: { pkg in
                        let p = pkg
                        pendingInstall = nil
                        confirmInstall = false
                        Task { await state.uninstall(p) }
                    }
                )
            } else {
                ContentUnavailableView {
                    Label("选择一个 Tap", systemImage: "square.grid.2x2")
                } description: {
                    Text("选择左侧 Tap 查看其包含的软件包。")
                }
            }
        }
        .alert("确认安装？", isPresented: $confirmInstall, presenting: pendingInstall) { pkg in
            Button("安装") {
                Task { await state.install(pkg) }
            }
            Button("取消", role: .cancel) {}
        } message: { pkg in
            Text("将安装 \(pkg.name)（\(pkg.kind.title)）。")
        }
    }

    private func selectTap(_ tap: BrewTap) {
        state.selectedTapID = tap.id
        if tap.formulaNames.isEmpty && tap.caskNames.isEmpty {
            Task { await state.loadTapPackages(tapName: tap.name) }
        }
    }
}

// MARK: - Tap Row

private struct TapRow: View {
    let tap: BrewTap
    var isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: tap.isOfficial ? "checkmark.circle.fill" : "externaldrive.badge.plus")
                .foregroundStyle(tap.isOfficial ? .green : .secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tap.name).font(.body.weight(.medium))
                    if !tap.formulaNames.isEmpty {
                        Text("\(tap.formulaNames.count) f")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(Capsule().fill(Color.blue.opacity(0.12)))
                            }
                            .foregroundStyle(.blue)
                    }
                    if !tap.caskNames.isEmpty {
                        Text("\(tap.caskNames.count) c")
                            .font(.caption2.monospacedDigit())
                            .padding(.horizontal, 5).padding(.vertical, 1)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(Capsule().fill(Color.green.opacity(0.12)))
                            }
                            .foregroundStyle(.green)
                    }
                }
                HStack(spacing: 8) {
                    Text(tap.isOfficial ? "官方源" : "第三方源")
                        .font(.caption).foregroundStyle(.secondary)
                    if !tap.isOfficial {
                        if tap.isTrusted {
                            Label("已信任", systemImage: "lock.open.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                        } else {
                            Label("未信任", systemImage: "lock.fill")
                                .font(.caption2)
                                .foregroundStyle(.orange)
                        }
                    }
                }
            }
            Spacer()
            if isSelected {
                Image(systemName: "chevron.right")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Tap Detail View

private struct TapDetailView: View {
    let tap: BrewTap
    @ObservedObject var state: AppState
    var isLoading: Bool
    var onTapPackage: (String) -> Void
    var onInstall: (Package) -> Void
    var onUninstall: (Package) -> Void

    @State private var filterText = ""
    @FocusState private var filterFocused: Bool
    @State private var pendingTrust: BrewTap?
    @State private var confirmTrust = false
    @State private var pendingUntrust: BrewTap?
    @State private var confirmUntrust = false

    private var allNames: [String] { tap.formulaNames + tap.caskNames }
    private var filteredFormulaNames: [String] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return tap.formulaNames }
        return tap.formulaNames.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    private var filteredCaskNames: [String] {
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        if q.isEmpty { return tap.caskNames }
        return tap.caskNames.filter { $0.localizedCaseInsensitiveContains(q) }
    }
    private var installedNames: Set<String> { state.installedNameSet }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView("正在加载 Tap 包列表…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if allNames.isEmpty {
                ContentUnavailableView {
                    Label("Tap 为空", systemImage: "tray")
                } description: {
                    Text("该 Tap 暂无公式或 Cask。")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                packageList
            }
        }
        .navigationTitle(tap.name)
        .alert("信任此 Tap？", isPresented: $confirmTrust, presenting: pendingTrust) { t in
            Button("信任") {
                Task { await state.trustTap(t.name) }
            }
            Button("取消", role: .cancel) {}
        } message: { t in
            Text("信任「\(t.name)」后，将可任意安装该 Tap 内的所有软件包。")
        }
        .alert("取消信任？", isPresented: $confirmUntrust, presenting: pendingUntrust) { t in
            Button("取消信任", role: .destructive) {
                Task { await state.untrustTap(t.name) }
            }
            Button("取消", role: .cancel) {}
        } message: { t in
            Text("取消信任后，将无法继续安装「\(t.name)」内的任意包。已安装的包不受影响，可正常使用。")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: tap.isOfficial ? "checkmark.circle.fill" : "externaldrive.badge.plus")
                    .font(.title2)
                    .foregroundStyle(tap.isOfficial ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(tap.name).font(.title2.weight(.semibold))
                    HStack(spacing: 8) {
                        Text(tap.isOfficial ? "Homebrew 官方源" : "第三方源")
                            .font(.caption).foregroundStyle(.secondary)
                        if !tap.isOfficial {
                            if tap.isTrusted {
                                Label("已信任", systemImage: "lock.open.fill")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background {
                                        Capsule()
                                            .fill(.regularMaterial)
                                            .overlay(Capsule().fill(Color.green.opacity(0.12)))
                                    }
                                    .foregroundStyle(.green)
                            } else {
                                Label("未信任", systemImage: "lock.fill")
                                    .font(.caption2.weight(.medium))
                                    .padding(.horizontal, 6).padding(.vertical, 2)
                                    .background {
                                        Capsule()
                                            .fill(.regularMaterial)
                                            .overlay(Capsule().fill(Color.orange.opacity(0.12)))
                                    }
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }

                Spacer()

                HStack(spacing: 8) {
                    if !tap.isOfficial {
                        if tap.isTrusted {
                            Button("取消信任", systemImage: "lock.slash") {
                                pendingUntrust = tap
                                confirmUntrust = true
                            }
                            .buttonStyle(.glassCapsule)
                            .controlSize(.small)
                            .disabled(state.isTaskRunning)
                        } else {
                            Button("信任此 Tap", systemImage: "lock.open") {
                                pendingTrust = tap
                                confirmTrust = true
                            }
                            .buttonStyle(.glassCapsule)
                            .controlSize(.small)
                            .disabled(state.isTaskRunning)
                        }
                    }

                    if !tap.formulaNames.isEmpty {
                        Text("\(tap.formulaNames.count) f")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    if !tap.caskNames.isEmpty {
                        Text("\(tap.caskNames.count) c")
                            .font(.caption.monospacedDigit())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.green.opacity(0.12), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索 tap 内的包…", text: $filterText)
                    .textFieldStyle(.plain)
                    .focused($filterFocused)
                if !filterText.isEmpty {
                    Button {
                        filterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(8)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(.regularMaterial)
            }

            if !tap.isOfficial && !tap.isTrusted {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text("此 Tap 尚未信任，安装其中的包前需先信任。")
                        .font(.callout).foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(16)
    }

    private var packageList: some View {
        List {
            if !filteredFormulaNames.isEmpty {
                Section("Formula（\(filteredFormulaNames.count)）") {
                    ForEach(filteredFormulaNames, id: \.self) { name in
                        packageRow(name: name, kind: .formula)
                    }
                }
            }
            if !filteredCaskNames.isEmpty {
                Section("Cask（\(filteredCaskNames.count)）") {
                    ForEach(filteredCaskNames, id: \.self) { name in
                        packageRow(name: name, kind: .cask)
                    }
                }
            }
        }
        .overlay {
            if !filterText.isEmpty && filteredFormulaNames.isEmpty && filteredCaskNames.isEmpty {
                ContentUnavailableView {
                    Label("无匹配结果", systemImage: "magnifyingglass")
                } description: {
                    Text("没有包名包含「\(filterText)」")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                let total = filteredFormulaNames.count + filteredCaskNames.count
                Text("显示 \(total) / \(allNames.count) 项")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                let installedCount = (filteredFormulaNames + filteredCaskNames)
                    .filter { installedNames.contains($0) }.count
                if installedCount > 0 {
                    Text("\(installedCount) 已安装")
                        .font(.caption).foregroundStyle(.green)
                }
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        }
    }

    private func packageRow(name: String, kind: PackageKind) -> some View {
        let isInstalled = installedNames.contains(name)
        let iconPackage = Package(
            name: name, kind: kind, isInstalled: isInstalled, isOutdated: false,
            isPinned: false, dependencies: [], installedOnRequest: true
        )
        return HStack(spacing: 10) {
            CaskIconView(package: iconPackage, iconSize: 12, containerSize: 20, rounded: false)

            Button {
                onTapPackage(name)
            } label: {
                Text(name)
                    .font(.body.weight(.medium))
                    .lineLimit(1)
            }
            .buttonStyle(.plain)

            Spacer()

            if isInstalled {
                Text("已安装")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 5).padding(.vertical, 1)
                    .background(Color.green.opacity(0.15), in: Capsule())
                    .foregroundStyle(.green)
            }

            if isInstalled {
                Button("卸载") {
                    let pkg = makePackage(name: name, kind: kind, installed: true)
                    onUninstall(pkg)
                }
                .buttonStyle(.glassCapsule(tint: .red))
                .controlSize(.small)
                .disabled(state.isTaskRunning)
            } else {
                Button("安装") {
                    let pkg = makePackage(name: name, kind: kind, installed: false)
                    onInstall(pkg)
                }
                .buttonStyle(.glassCapsule)
                .controlSize(.small)
                .disabled(state.isTaskRunning)
            }
        }
        .padding(.vertical, 2)
    }

    private func makePackage(name: String, kind: PackageKind, installed: Bool) -> Package {
        // Check if it's already in installed list (has version info)
        if let existing = installedNames.first(where: { $0 == name }) {
            if let pkg = state.installed.first(where: { $0.name == existing }) {
                return pkg
            }
        }
        return Package(
            name: name, kind: kind, version: nil, latestVersion: nil,
            desc: nil, homepage: nil, isInstalled: installed, isOutdated: false,
            isPinned: false, dependencies: [], installedOnRequest: true
        )
    }
}

// MARK: - Package Sheet (detail popup)

private struct PackageSheet: View {
    let package: Package
    @ObservedObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var loaded: Package?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(pkg.name)
                    .font(.title2.weight(.semibold))
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(20)

            Divider()

            if let pkg = loaded {
                PackageDetailView(
                    package: pkg,
                    dependents: state.dependents(of: pkg),
                    installedNames: state.installedNameSet,
                    isBusy: state.isTaskRunning,
                    onInstall: pkg.isInstalled ? nil : {
                        Task { await state.install(pkg); dismiss() }
                    },
                    onUninstall: pkg.isInstalled ? {
                        Task { await state.uninstall(pkg); dismiss() }
                    } : nil,
                    onUpgrade: pkg.isOutdated ? {
                        Task { await state.upgrade(packages: [pkg]); dismiss() }
                    } : nil,
                    onSelectRelated: { name in
                        dismiss()
                        state.selectInstalledPackage(named: name)
                    }
                )
            } else {
                ProgressView("加载详情…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 520, idealWidth: 680, minHeight: 380, idealHeight: 480)
        .task {
            if let fetched = await state.lookupTapPackage(named: package.name) {
                loaded = fetched
            } else {
                loaded = package
            }
        }
    }

    private var pkg: Package { loaded ?? package }
}

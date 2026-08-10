//
//  PackageDetailView.swift
//  BrewDesk
//

import AppKit
import SwiftUI

struct PackageDetailView: View {
    let package: Package
    var dependents: [String] = []
    var installedNames: Set<String> = []
    var isBusy: Bool = false
    var onInstall: (() -> Void)?
    var onUninstall: (() -> Void)?
    var onUpgrade: (() -> Void)?
    var onPin: (() -> Void)?
    var onUnpin: (() -> Void)?
    var onSelectRelated: ((String) -> Void)?

    @State private var copied = false
    @State private var showGraph = false

    private var hasRelations: Bool {
        !package.dependencies.isEmpty || !dependents.isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                actions
                if package.isDisabled {
                    warningBanner(
                        title: "已禁用",
                        reason: package.disableReason,
                        date: package.disableDate,
                        color: .red
                    )
                }
                if package.isDeprecated {
                    warningBanner(
                        title: "已废弃",
                        reason: package.deprecationReason,
                        date: package.deprecationDate,
                        color: .orange
                    )
                }
                infoSection
                if let caveats = package.caveats, !caveats.isEmpty {
                    GroupBox("注意事项 (Caveats)") {
                        Text(caveats)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(4)
                    }
                }
                if hasRelations {
                    DependencyGraphView(
                        package: package,
                        dependents: dependents,
                        installedNames: installedNames,
                        onSelect: { name in
                            Task { @MainActor in
                                onSelectRelated?(name)
                            }
                        }
                    )

                    HStack {
                        Spacer()
                        Button("放大查看") {
                            showGraph = true
                        }
                        .buttonStyle(.glassCapsule)
                    }
                }
                if !package.dependencies.isEmpty {
                    chipSection(
                        title: "依赖列表（\(package.dependencies.count)）",
                        items: package.dependencies,
                        tint: .secondary
                    )
                }
                if !dependents.isEmpty {
                    chipSection(
                        title: "被依赖列表（\(dependents.count)）",
                        items: dependents,
                        tint: .orange
                    )
                }
                if !package.buildDependencies.isEmpty {
                    chipSection(
                        title: "构建依赖（\(package.buildDependencies.count)）",
                        items: package.buildDependencies,
                        tint: .indigo
                    )
                }
                if !package.usesFromMacOS.isEmpty {
                    chipSection(
                        title: "使用 macOS 自带（\(package.usesFromMacOS.count)）",
                        items: package.usesFromMacOS,
                        tint: .teal
                    )
                }
                if !package.caskDependsOn.isEmpty {
                    chipSection(
                        title: "依赖条件（\(package.caskDependsOn.count)）",
                        items: package.caskDependsOn,
                        tint: .blue
                    )
                }
                if !package.conflictsWith.isEmpty {
                    chipSection(
                        title: "冲突软件包（\(package.conflictsWith.count)）",
                        items: package.conflictsWith,
                        tint: .red
                    )
                }
            }
            .padding(Design.contentPadding)
            .frame(alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .sheet(isPresented: $showGraph) {
            DependencyGraphSheet(
                package: package,
                dependents: dependents,
                installedNames: installedNames,
                onSelect: { name in
                    Task { @MainActor in
                        onSelectRelated?(name)
                    }
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                CaskIconView(package: package, iconSize: 30, containerSize: 44)

                VStack(alignment: .leading, spacing: 6) {
                    Text(package.name)
                        .font(.title2.weight(.semibold))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)

                    // 徽章独立一行，长包名 + 多徽章时靠换行兜底，避免与图标/按钮竞争宽度
                    HStack(spacing: 8) {
                        Text(package.kind.title)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background {
                                Capsule().fill(.thinMaterial)
                            }

                        statusBadge

                        if package.isPinned {
                            badge("已固定", color: .purple)
                        }
                    }
                }

                Spacer(minLength: 0)

                Button {
                    copyName()
                } label: {
                    Label(copied ? "已复制" : "复制名称", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.glassCapsule)
                .help("复制软件包名称")
            }
            .animation(Design.standardAnimation, value: statusText)

            if let desc = package.desc, !desc.isEmpty {
                Text(desc)
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }

    private func warningBanner(title: String, reason: String?, date: String?, color: Color) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(color)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                if let reason, !reason.isEmpty {
                    Text(reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
                if let date, !date.isEmpty {
                    Text(date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(color.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(color.opacity(0.25), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        if package.isOutdated {
            badge("可更新", color: .orange)
        } else if package.isInstalled {
            badge("已安装", color: .green)
        } else {
            badge("未安装", color: .secondary)
        }
    }

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background {
                Capsule().fill(color.opacity(0.12))
            }
            .foregroundStyle(color)
    }

    private var actions: some View {
        HStack(spacing: 10) {
            if package.isInstalled {
                if package.isOutdated, let onUpgrade {
                    Button("升级", systemImage: "arrow.up.circle") {
                        onUpgrade()
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(isBusy || package.isPinned)
                    .help(package.isPinned ? "已固定，请先取消固定再升级" : "升级到最新版本")
                }

                if package.isPinned, let onUnpin {
                    Button("取消固定", systemImage: "pin.slash") {
                        onUnpin()
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(isBusy)
                    .help("允许 brew upgrade 更新此软件包")
                } else if let onPin {
                    Button("固定版本", systemImage: "pin") {
                        onPin()
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(isBusy)
                    .help("防止 brew upgrade 更新此软件包")
                }

                if let onUninstall {
                    Button("卸载", systemImage: "trash", role: .destructive) {
                        onUninstall()
                    }
                    .buttonStyle(.glassCapsule(tint: .red))
                    .disabled(isBusy)
                }
            } else if let onInstall {
                Button("安装", systemImage: "plus.circle") {
                    onInstall()
                }
                .buttonStyle(.glassCapsule)
                .disabled(isBusy)
                .keyboardShortcut(.defaultAction)
            }

            if let homepage = package.homepage {
                Link(destination: homepage) {
                    Label("主页", systemImage: "safari")
                }
                .buttonStyle(.glassCapsule)
                .help(homepage.absoluteString)
            }

            Button("复制 brew 命令") {
                copyBrewCommand()
            }
            .buttonStyle(.glassCapsule)
            .help("复制对应的 brew 安装/卸载命令")

            Spacer()
        }
    }

    private var infoSection: some View {
        GroupBox("信息") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                if let version = package.version, !version.isEmpty {
                    gridRow("版本", version)
                } else if let latest = package.latestVersion, !latest.isEmpty {
                    // 未安装时展示最新稳定版本（brew info 惯例）；
                    // 此前这里会额外输出一行「版本 —」+「版本 1.2.3」的重复行。
                    gridRow("版本", latest)
                }
                if package.isOutdated {
                    gridRow("最新", package.latestVersion ?? "—")
                }
                if package.installedVersions.count > 1 {
                    gridRow("已装版本", package.installedVersions.joined(separator: ", "))
                }
                gridRow("状态", statusText)
                if package.kind == .formula {
                    gridRow("安装方式", package.installedOnRequest ? "手动安装" : "作为依赖")
                }
                if package.installedTime != nil {
                    gridRow("安装时间", package.installedTimeLabel)
                }
                if package.isPinned {
                    gridRow("固定", "已 pin，不会被 upgrade")
                }
                if !dependents.isEmpty {
                    gridRow("被依赖", "\(dependents.count) 个已安装软件")
                }
                if let license = package.license, !license.isEmpty {
                    gridRow("许可证", license)
                }
                if let tap = package.tap, !tap.isEmpty {
                    gridRow("来源 Tap", tap)
                }
                if package.kegOnly {
                    if let reason = package.kegOnlyReason, !reason.isEmpty {
                        gridRow("Keg-only", reason)
                    } else {
                        gridRow("Keg-only", "是（不链接到 PATH）")
                    }
                }
                if package.autoUpdates {
                    gridRow("自动更新", "是")
                }
                if let sha = package.sha256, !sha.isEmpty {
                    gridRow("SHA256", "\(sha.prefix(16))…")
                }
                if let url = package.sourceURL {
                    gridRowLong("下载地址", url.absoluteString)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)

            if hasAnalytics {
                Divider().padding(.vertical, 4)
                analyticsSection
            }
        }
    }

    private func chipSection(title: String, items: [String], tint: Color) -> some View {
        GroupBox(title) {
            FlowWrap(items: items) { name in
                Button {
                    Task { @MainActor in
                        onSelectRelated?(name)
                    }
                } label: {
                    Text(name)
                        .font(.caption.monospaced())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(onSelectRelated == nil)
                .help(onSelectRelated == nil ? name : "查看 \(name)")
            }
            .padding(4)
        }
    }

    private var statusText: String {
        if !package.isInstalled { return "未安装" }
        if package.isOutdated { return "可更新" }
        if package.isPinned { return "已固定" }
        return "已安装"
    }

    private var hasAnalytics: Bool {
        package.analyticsInstall30d != nil || package.analyticsInstall365d != nil
    }

    private var analyticsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Analytics")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 20) {
                analyticsCell(title: "安装 (30d)", value: package.analyticsInstall30d)
                analyticsCell(title: "安装 (90d)", value: package.analyticsInstall90d)
                analyticsCell(title: "安装 (365d)", value: package.analyticsInstall365d)
            }
            HStack(spacing: 20) {
                analyticsCell(title: "主动安装 (30d)", value: package.analyticsInstallOnRequest30d)
                analyticsCell(title: "主动安装 (90d)", value: package.analyticsInstallOnRequest90d)
                analyticsCell(title: "主动安装 (365d)", value: package.analyticsInstallOnRequest365d)
            }
        }
        .padding(4)
    }

    private func analyticsCell(title: String, value: Int?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Text(value.map { formatAnalytics($0) } ?? "—")
                .font(.caption.monospacedDigit().weight(.medium))
                .foregroundStyle(.secondary)
        }
        .frame(minWidth: 80, alignment: .leading)
    }

    private func formatAnalytics(_ n: Int) -> String {
        n.formatted(.number)
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func gridRowLong(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .gridColumnAlignment(.trailing)
            Text(value)
                .textSelection(.enabled)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(value)
        }
    }

    private func copyName() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(package.name, forType: .string)
        copied = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copied = false
        }
    }

    private func copyBrewCommand() {
        let command: String
        if package.isInstalled {
            if package.kind == .cask {
                command = "brew uninstall --cask \(package.name)"
            } else {
                command = "brew uninstall \(package.name)"
            }
        } else if package.kind == .cask {
            command = "brew install --cask \(package.name)"
        } else {
            command = "brew install \(package.name)"
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
    }
}

private struct FlowWrap<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 80), spacing: 6)],
            alignment: .leading,
            spacing: 6
        ) {
            ForEach(items, id: \.self) { item in
                content(item)
            }
        }
    }
}

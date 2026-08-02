//
//  UninstallConfirmation.swift
//  BrewDesk
//

import SwiftUI

struct UninstallConfirmationModifier: ViewModifier {
    @Binding var package: Package?
    var dependents: (Package) -> [String]
    var onConfirm: (Package) -> Void

    func body(content: Content) -> some View {
        content
            .sheet(item: $package) { pkg in
                UninstallConfirmationSheet(
                    package: pkg,
                    dependents: dependents(pkg),
                    onConfirm: {
                        let p = pkg
                        package = nil
                        onConfirm(p)
                    },
                    onCancel: {
                        package = nil
                    }
                )
            }
    }
}

extension View {
    func uninstallConfirmation(
        package: Binding<Package?>,
        dependents: @escaping (Package) -> [String] = { _ in [] },
        onConfirm: @escaping (Package) -> Void
    ) -> some View {
        modifier(
            UninstallConfirmationModifier(
                package: package,
                dependents: dependents,
                onConfirm: onConfirm
            )
        )
    }
}

private struct UninstallConfirmationSheet: View {
    let package: Package
    let dependents: [String]
    var onConfirm: () -> Void
    var onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "trash.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 4) {
                    Text("卸载 \(package.name)？")
                        .font(.title2.weight(.semibold))
                    Text(package.kind.title)
                        .foregroundStyle(.secondary)
                }
            }

            Text(mainMessage)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Force + Zap warning — always shown
            callout(
                icon: "flame.fill",
                tint: .red,
                title: "将使用 --force --zap 强制卸载",
                detail: "--force：即使被其它软件依赖也会强制删除。\n--zap：同时清理配置、缓存和残留文件，卸载更彻底，且不可撤销。"
            )

            if !package.installedOnRequest, package.kind == .formula {
                callout(
                    icon: "link",
                    tint: .orange,
                    title: "它可能是其它软件的依赖",
                    detail: "该 formula 标记为“作为依赖安装”。使用 --force 卸载后，依赖它的软件可能无法正常工作。"
                )
            }

            if !dependents.isEmpty {
                callout(
                    icon: "exclamationmark.triangle.fill",
                    tint: .orange,
                    title: "仍有 \(dependents.count) 个已安装软件依赖它",
                    detail: dependents.prefix(12).joined(separator: ", ")
                        + (dependents.count > 12 ? "…" : "")
                )
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                    .buttonStyle(.glassCapsule)
                    .keyboardShortcut(.cancelAction)
                Button("强制卸载", role: .destructive, action: onConfirm)
                    .buttonStyle(.glassCapsule(tint: .red))
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private var mainMessage: String {
        "将使用 brew uninstall --force --zap 从本机彻底移除 \(package.name)。卸载后不可恢复。"
    }

    private func callout(icon: String, tint: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.callout.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(tint.opacity(0.08))
        }
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 10))
    }
}

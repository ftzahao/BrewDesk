//
//  PackageRowView.swift
//  BrewDesk
//

import SwiftUI

struct PackageRowView: View {
    let package: Package
    var showKindBadge: Bool = false
    /// 为 false 时使用静态符号，不启动图标查找任务（适合超大规模目录列表）
    var showIcon: Bool = true
    /// 在版本号前显示已安装的绿色对勾
    var showInstalledIndicator: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            if showIcon {
                CaskIconView(package: package, iconSize: 20, containerSize: 28)
            } else {
                staticGlyph
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

                    if showKindBadge {
                        Text(package.kind == .formula ? "Formula" : "Cask")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                            }
                            .foregroundStyle(.secondary)
                    }

                    if package.isOutdated {
                        Text("更新")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(Capsule().fill(Color.orange.opacity(0.12)))
                            }
                            .foregroundStyle(.orange)
                    }

                    if package.isPinned {
                        Text("固定")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background {
                                Capsule()
                                    .fill(.regularMaterial)
                                    .overlay(Capsule().fill(Color.purple.opacity(0.12)))
                            }
                            .foregroundStyle(.purple)
                    }
                }

                if let desc = package.desc, !desc.isEmpty {
                    Text(desc)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 8)

            if showInstalledIndicator && package.isInstalled {
                Image(systemName: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
                    .help("已安装")
            }

            // 未安装且无版本信息时不显示占位符，降低目录列表的视觉噪音
            if package.isInstalled || package.version != nil || package.latestVersion != nil {
                Text(package.versionLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var staticGlyph: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.06))
                .frame(width: 28, height: 28)
            Image(systemName: package.kind == .formula ? "terminal" : "app.badge")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
    }
}

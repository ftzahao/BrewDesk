//
//  PackageRowView.swift
//  BrewDesk
//

import SwiftUI

struct PackageRowView: View {
    let package: Package

    var body: some View {
        HStack(spacing: 10) {
            CaskIconView(package: package, iconSize: 16, containerSize: 26)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(package.name)
                        .font(.body.weight(.medium))
                        .lineLimit(1)

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

            Text(package.versionLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 3)
    }
}

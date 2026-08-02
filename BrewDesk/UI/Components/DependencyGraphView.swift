//
//  DependencyGraphView.swift
//  BrewDesk
//

import SwiftUI

/// Simple star-layout graph: dependents ← center → dependencies.
struct DependencyGraphView: View {
    let package: Package
    let dependents: [String]
    let installedNames: Set<String>
    var onSelect: (String) -> Void
    /// When true, hides the header/legend and lets the graph fill available space (for sheet use).
    var isExpanded: Bool = false

    private let nodeWidth: CGFloat = 108
    private let nodeHeight: CGFloat = 36
    private let columnGap: CGFloat = 56
    private let rowGap: CGFloat = 10

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !isExpanded {
                HStack {
                    Label("依赖关系", systemImage: "point.3.connected.trianglepath.dotted")
                        .font(.headline)
                    Spacer()
                    legend
                }
            }

            if package.dependencies.isEmpty && dependents.isEmpty {
                ContentUnavailableView {
                    Label("没有直接依赖关系", systemImage: "circle.dashed")
                } description: {
                    Text(package.kind == .cask
                         ? "Cask 通常不展示 formula 依赖图。"
                         : "此软件包没有记录直接依赖，也没有其它已安装包依赖它。")
                }
                .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                ScrollView([.horizontal, .vertical]) {
                    graphCanvas
                        .padding(20)
                }
                .frame(
                    minWidth: isExpanded ? 480 : nil,
                    minHeight: isExpanded ? 320 : min(graphHeight + 40, 360),
                    maxHeight: isExpanded ? .infinity : 360
                )
                .background {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(.regularMaterial)
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(Color.primary.opacity(0.08))
                )
            }

            if !isExpanded {
                Text("点击节点可跳转查看。箭头：被依赖 ← 当前包 → 依赖。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .accentColor, title: "当前")
            legendItem(color: .orange.opacity(0.85), title: "被依赖")
            legendItem(color: .secondary.opacity(0.55), title: "依赖")
            legendItem(color: .green.opacity(0.75), title: "已安装")
        }
        .font(.caption2)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }

    private var maxSideCount: Int {
        max(dependents.count, package.dependencies.count, 1)
    }

    private var graphHeight: CGFloat {
        CGFloat(maxSideCount) * (nodeHeight + rowGap) + 24
    }

    private var graphWidth: CGFloat {
        nodeWidth * 3 + columnGap * 2 + 40
    }

    private var graphCanvas: some View {
        let deps = package.dependencies
        let dens = dependents
        let height = graphHeight
        let width = graphWidth
        let center = CGPoint(x: width / 2, y: height / 2)

        return ZStack {
            // Edges
            Canvas { context, size in
                let depPoints = columnPoints(count: dens.count, x: nodeWidth / 2 + 8, canvasHeight: height)
                let depencyPoints = columnPoints(count: deps.count, x: width - nodeWidth / 2 - 8, canvasHeight: height)

                for point in depPoints {
                    drawEdge(context: context, from: point, to: center, color: .orange.opacity(0.55))
                }
                for point in depencyPoints {
                    drawEdge(context: context, from: center, to: point, color: Color.secondary.opacity(0.45))
                }
            }

            // Dependent nodes (left)
            ForEach(Array(dens.enumerated()), id: \.offset) { index, name in
                nodeButton(name: name, role: .dependent)
                    .position(columnPoints(count: dens.count, x: nodeWidth / 2 + 8, canvasHeight: height)[index])
            }

            // Center
            centerNode
                .position(center)

            // Dependency nodes (right)
            ForEach(Array(deps.enumerated()), id: \.offset) { index, name in
                nodeButton(name: name, role: .dependency)
                    .position(columnPoints(count: deps.count, x: width - nodeWidth / 2 - 8, canvasHeight: height)[index])
            }
        }
        .frame(width: width, height: height)
    }

    private var centerNode: some View {
        VStack(spacing: 2) {
            Text(package.name)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text("当前")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.85))
        }
        .foregroundStyle(.white)
        .frame(width: nodeWidth, height: nodeHeight + 4)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.regularMaterial)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.accentColor.opacity(0.85)))
        }
        .shadow(color: Color.accentColor.opacity(0.25), radius: 6, y: 2)
        .help(package.name)
    }

    private enum NodeRole {
        case dependent
        case dependency
    }

    private func nodeButton(name: String, role: NodeRole) -> some View {
        let installed = installedNames.contains(name)
        return Button {
            onSelect(name)
        } label: {
            HStack(spacing: 4) {
                if installed {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                }
                Text(name)
                    .font(.caption.monospaced())
                    .lineLimit(1)
            }
            .padding(.horizontal, 8)
            .frame(width: nodeWidth, height: nodeHeight)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(nodeBackground(role: role, installed: installed).opacity(0.6)))
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(nodeBorder(role: role, installed: installed), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(installed ? "\(name)（已安装）· 点击查看" : "\(name) · 点击搜索/查看")
    }

    private func nodeBackground(role: NodeRole, installed: Bool) -> Color {
        if installed {
            return Color.green.opacity(0.12)
        }
        switch role {
        case .dependent: return Color.orange.opacity(0.12)
        case .dependency: return Color.primary.opacity(0.05)
        }
    }

    private func nodeBorder(role: NodeRole, installed: Bool) -> Color {
        if installed { return Color.green.opacity(0.35) }
        switch role {
        case .dependent: return Color.orange.opacity(0.35)
        case .dependency: return Color.primary.opacity(0.12)
        }
    }

    private func columnPoints(count: Int, x: CGFloat, canvasHeight: CGFloat) -> [CGPoint] {
        guard count > 0 else { return [] }
        if count == 1 {
            return [CGPoint(x: x, y: canvasHeight / 2)]
        }
        let total = CGFloat(count - 1) * (nodeHeight + rowGap)
        let startY = (canvasHeight - total) / 2
        return (0..<count).map { index in
            CGPoint(x: x, y: startY + CGFloat(index) * (nodeHeight + rowGap))
        }
    }

    private func drawEdge(context: GraphicsContext, from: CGPoint, to: CGPoint, color: Color) {
        var path = Path()
        let dx = to.x - from.x
        let control1 = CGPoint(x: from.x + dx * 0.45, y: from.y)
        let control2 = CGPoint(x: to.x - dx * 0.45, y: to.y)
        path.move(to: from)
        path.addCurve(to: to, control1: control1, control2: control2)
        context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))

        // Arrow head near `to`
        let angle = atan2(to.y - control2.y, to.x - control2.x)
        let arrowLen: CGFloat = 7
        var arrow = Path()
        arrow.move(to: to)
        arrow.addLine(to: CGPoint(
            x: to.x - arrowLen * cos(angle - .pi / 7),
            y: to.y - arrowLen * sin(angle - .pi / 7)
        ))
        arrow.move(to: to)
        arrow.addLine(to: CGPoint(
            x: to.x - arrowLen * cos(angle + .pi / 7),
            y: to.y - arrowLen * sin(angle + .pi / 7)
        ))
        context.stroke(arrow, with: .color(color), style: StrokeStyle(lineWidth: 1.5, lineCap: .round))
    }
}

struct DependencyGraphSheet: View {
    let package: Package
    let dependents: [String]
    let installedNames: Set<String>
    var onSelect: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.title2.weight(.semibold))
                    Text("依赖关系图")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                legend
                Button("完成") { dismiss() }
                    .buttonStyle(.glassCapsule)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(20)

            Divider()

            DependencyGraphView(
                package: package,
                dependents: dependents,
                installedNames: installedNames,
                onSelect: { name in
                    dismiss()
                    Task { @MainActor in
                        onSelect(name)
                    }
                },
                isExpanded: true
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 640, minHeight: 420, idealHeight: 480)
    }

    private var legend: some View {
        HStack(spacing: 12) {
            legendItem(color: .accentColor, title: "当前")
            legendItem(color: .orange.opacity(0.85), title: "被依赖")
            legendItem(color: .secondary.opacity(0.55), title: "依赖")
            legendItem(color: .green.opacity(0.75), title: "已安装")
        }
        .font(.caption2)
    }

    private func legendItem(color: Color, title: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
            Text(title)
                .foregroundStyle(.secondary)
        }
    }
}

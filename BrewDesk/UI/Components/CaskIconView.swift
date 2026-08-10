//
//  CaskIconView.swift
//  BrewDesk
//
//  显示已安装 cask 的真实应用图标，找不到时回退到 SF Symbol
//

import AppKit
import SwiftUI

// MARK: - Cask 图标视图

struct CaskIconView: View {
    let package: Package
    var iconSize: CGFloat = 26
    var containerSize: CGFloat? = nil
    var rounded: Bool = true

    @State private var appIcon: NSImage? = nil

    private var effectiveContainerSize: CGFloat { containerSize ?? iconSize }

    var body: some View {
        Group {
            if let nsImage = appIcon {
                iconContent(nsImage: nsImage)
            } else {
                fallbackContent
            }
        }
        .frame(width: effectiveContainerSize, height: effectiveContainerSize)
        .task(id: "\(package.id)|\(package.isInstalled)") {
            await loadIcon()
        }
    }

    @ViewBuilder
    private func iconContent(nsImage: NSImage) -> some View {
        if rounded {
            RoundedRectangle(cornerRadius: effectiveContainerSize * 0.22)
                .fill(Color.primary.opacity(0.06))
                .frame(width: effectiveContainerSize, height: effectiveContainerSize)
                .overlay(
                    Image(nsImage: nsImage)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: iconSize, height: iconSize)
                )
                .clipShape(RoundedRectangle(cornerRadius: effectiveContainerSize * 0.2))
        } else {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .frame(width: iconSize, height: iconSize)
        }
    }

    @ViewBuilder
    private var fallbackContent: some View {
        if rounded {
            ZStack {
                RoundedRectangle(cornerRadius: effectiveContainerSize * 0.22)
                    .fill(Color.primary.opacity(0.06))
                    .frame(width: effectiveContainerSize, height: effectiveContainerSize)
                Image(systemName: package.kind == .formula ? "terminal" : "app.badge")
                    .foregroundStyle(.secondary)
                    .font(.system(size: iconSize * 0.46, weight: .medium))
            }
        } else {
            Image(systemName: package.kind == .formula ? "terminal" : "app.badge")
                .foregroundStyle(.secondary)
                .font(.system(size: iconSize * 0.46, weight: .medium))
        }
    }

    private func loadIcon() async {
        guard package.kind == .cask, package.isInstalled else {
            // 非 cask 或未安装时清掉可能残留的旧图标
            appIcon = nil
            return
        }

        // 1) 内存缓存命中时直接显示，避免重复磁盘扫描
        if let cached = CaskIconCache.shared.icon(for: package.name) {
            appIcon = cached
            return
        }

        // 2) 在途去重：同一 cask 已有扫描在跑时不重复启动（并发扫描可能已写入缓存）
        guard CaskIconCache.shared.beginScan(for: package.name) else {
            appIcon = CaskIconCache.shared.icon(for: package.name)
            return
        }

        // 3) 文件系统扫描在后台线程执行；Task.detached 不继承外层取消，
        //    用 withTaskCancellationHandler 显式传播：行滚出屏幕即终止扫描，
        //    配合扫描循环内的取消检查点提前退出，避免孤儿扫描占满后台线程。
        let packageForScan = package
        let scanTask = Task.detached(priority: .utility) {
            defer { CaskIconCache.shared.endScan(for: packageForScan.name) }
            return CaskIconProvider.findAppPath(for: packageForScan)
        }
        let path = await withTaskCancellationHandler {
            await scanTask.value
        } onCancel: {
            scanTask.cancel()
        }

        guard !Task.isCancelled else { return }
        guard let path else { return }

        // NSWorkspace.icon(forFile:) 必须在 MainActor 上调用
        let nsImage = NSWorkspace.shared.icon(forFile: path)

        guard !Task.isCancelled else { return }
        // 缩样后再缓存：NSWorkspace 图标底层是 512-1024pt 全尺寸位图，
        // 直接缓存会在浏览大量 cask 时占用数百 MB 内存。
        // 64pt（Retina 2x 下 128px）足够界面最大显示尺寸（详情页 44pt），
        // 512 个图标的内存占用从约 134MB 降到约 33MB。
        let thumbnail = Self.downscaled(nsImage, points: 64)
        CaskIconCache.shared.store(icon: thumbnail, for: package.name)
        appIcon = thumbnail
    }

    /// 把全尺寸 NSImage 画成 points 尺寸的真缩略图（Retina 下 2x 像素），丢弃底层大位图。
    private static func downscaled(_ image: NSImage, points: CGFloat) -> NSImage {
        let px = Int(points * 2)
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return image }
        rep.size = NSSize(width: points, height: points)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(
            in: NSRect(x: 0, y: 0, width: points, height: points),
            from: .zero, operation: .copy, fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        let result = NSImage(size: NSSize(width: points, height: points))
        result.addRepresentation(rep)
        return result
    }
}

// MARK: - 图标与路径缓存

/// 跨行复用的 cask 图标缓存，避免每次滚动/刷新都重新扫描磁盘。
/// AppState 在已安装 cask 集合变化后调用 invalidate(keeping:)，仅清除已卸载 cask 的条目。
nonisolated final class CaskIconCache: @unchecked Sendable {
    static let shared = CaskIconCache()

    /// 最多缓存的图标数量（FIFO 淘汰），防止浏览大量 cask 时内存无界增长
    private static let maxIconCount = 512

    private let lock = NSLock()
    private var icons: [String: NSImage] = [:]
    private var iconOrder: [String] = []
    private var paths: [String: String] = [:]
    private var misses: Set<String> = []
    /// 正在扫描磁盘的 cask token，避免同一 token 并发启动多个扫描任务
    private var inFlight: Set<String> = []

    /// 尝试登记一次磁盘扫描。返回 false 表示该 token 已在扫描/已缓存/已知 miss，无需再扫。
    func beginScan(for token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !inFlight.contains(token), icons[token] == nil, !misses.contains(token) else {
            return false
        }
        inFlight.insert(token)
        return true
    }

    func endScan(for token: String) {
        lock.lock()
        defer { lock.unlock() }
        inFlight.remove(token)
    }

    func icon(for token: String) -> NSImage? {
        lock.lock()
        defer { lock.unlock() }
        return icons[token]
    }

    func store(icon: NSImage, for token: String) {
        lock.lock()
        defer { lock.unlock() }
        if icons[token] == nil {
            iconOrder.append(token)
        }
        icons[token] = icon
        while iconOrder.count > Self.maxIconCount {
            let evicted = iconOrder.removeFirst()
            icons[evicted] = nil
        }
    }

    /// 已解析且仍然存在的 .app 路径
    func cachedPath(for token: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard let path = paths[token], FileManager.default.fileExists(atPath: path) else {
            return nil
        }
        return path
    }

    func store(path: String, for token: String) {
        lock.lock()
        defer { lock.unlock() }
        paths[token] = path
        misses.remove(token)
    }

    func wasMiss(for token: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return misses.contains(token)
    }

    func markMiss(for token: String) {
        lock.lock()
        defer { lock.unlock() }
        misses.insert(token)
    }

    /// 仅保留指定 token（当前仍安装的 cask）的缓存，其余清除。
    /// 调用时机：已安装 cask 集合变化时。未变化的 cask 图标/路径/miss 记录
    /// 全部保留，避免装一个 cask 后刷新就重扫磁盘并重绘全部图标。
    func invalidate(keeping tokens: Set<String>) {
        lock.lock()
        defer { lock.unlock() }
        icons = icons.filter { tokens.contains($0.key) }
        iconOrder = iconOrder.filter { tokens.contains($0) }
        paths = paths.filter { tokens.contains($0.key) }
        misses = misses.filter { tokens.contains($0) }
        inFlight = inFlight.filter { tokens.contains($0) }
    }
}

// MARK: - Cask 图标查找器

nonisolated private enum CaskIconProvider {
    /// 查找 .app 路径（非 MainActor，可在后台调用）
    static func findAppPath(for package: Package) -> String? {
        guard package.kind == .cask else { return nil }
        let token = package.name

        if CaskIconCache.shared.wasMiss(for: token) { return nil }
        if let cached = CaskIconCache.shared.cachedPath(for: token) { return cached }

        // 1) 优先使用 brew 提供的权威安装路径（如 "/Applications/CleanShot X.app"）
        for artifact in package.caskArtifacts {
            guard !Task.isCancelled else { return nil }
            guard let target = artifact.target else { continue }
            let expanded = (target as NSString).expandingTildeInPath
            if isAppBundle(at: expanded) {
                CaskIconCache.shared.store(path: expanded, for: token)
                return expanded
            }
        }

        // 2) 按权威 app 名在 Caskroom 版本目录 / 应用目录中精确查找
        let appNames = package.caskArtifacts.flatMap(\.appNames)
        if !appNames.isEmpty {
            if let path = findExactApp(appNames: appNames, token: token, version: package.version) {
                CaskIconCache.shared.store(path: path, for: token)
                return path
            }
        }

        // 3) 无权威信息（如 outdated 列表）时使用启发式匹配
        if let path = findAppByHeuristics(token: token, displayNames: package.caskDisplayNames) {
            CaskIconCache.shared.store(path: path, for: token)
            return path
        }

        CaskIconCache.shared.markMiss(for: token)
        return nil
    }

    /// 按权威 app 名精确查找（不做猜测）
    private static func findExactApp(appNames: [String], token: String, version: String?) -> String? {
        for caskroom in caskroomRoots {
            guard !Task.isCancelled else { return nil }
            let root = (caskroom as NSString).appendingPathComponent(token)
            guard FileManager.default.fileExists(atPath: root) else { continue }

            // 已知版本时先直接查 Caskroom/<token>/<version>/ 目录
            if let version {
                let versionPath = (root as NSString).appendingPathComponent(version)
                if FileManager.default.fileExists(atPath: versionPath),
                   let path = findAppByNames(in: versionPath, appNames: appNames, depth: 3) {
                    return path
                }
            }

            // 兜底：扫描全部版本子目录
            if let path = findAppByNames(in: root, appNames: appNames, depth: 3) {
                return path
            }
        }

        // 应用目录（/Applications、~/Applications）精确查找
        for appName in appNames {
            guard !Task.isCancelled else { return nil }
            if let path = findAppNamed(appName, in: applicationRoots()) {
                return path
            }
        }
        return nil
    }

    /// 无权威信息时，通过候选名匹配（精确 → 归一化 → 前缀）
    private static func findAppByHeuristics(token: String, displayNames: [String]) -> String? {
        let matcher = AppNameMatcher(candidates: namingCandidates(token: token, displayNames: displayNames))

        for caskroom in caskroomRoots {
            guard !Task.isCancelled else { return nil }
            let root = (caskroom as NSString).appendingPathComponent(token)
            guard FileManager.default.fileExists(atPath: root) else { continue }
            if let found = findMatchingApp(in: root, matcher: matcher, depth: 4) {
                return found
            }
        }

        for basePath in applicationRoots() {
            guard !Task.isCancelled else { return nil }
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents where item.hasSuffix(".app") {
                if matcher.matches(item: item) {
                    return (basePath as NSString).appendingPathComponent(item)
                }
            }
        }
        return nil
    }

    // MARK: - 目录扫描

    /// 递归按精确 app 名查找，不进入 .app 内部，限制深度
    private static func findAppByNames(in directory: String, appNames: [String], depth: Int) -> String? {
        guard depth > 0 else { return nil }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }

        for item in contents where !item.hasPrefix(".") {
            guard !Task.isCancelled else { return nil }
            let fullPath = (directory as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue && item.hasSuffix(".app") {
                let base = String(item.dropLast(4))
                if appNames.contains(where: {
                    $0.localizedCaseInsensitiveCompare(item) == .orderedSame
                        || $0.localizedCaseInsensitiveCompare(base) == .orderedSame
                }) {
                    return fullPath
                }
                continue
            }

            if isDir.boolValue,
               let found = findAppByNames(in: fullPath, appNames: appNames, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    /// 在应用目录中按精确 app 名查找
    private static func findAppNamed(_ appName: String, in roots: [String]) -> String? {
        let targets: [String]
        if appName.hasSuffix(".app") {
            targets = [appName, String(appName.dropLast(4))]
        } else {
            targets = [appName, appName + ".app"]
        }

        for basePath in roots {
            guard !Task.isCancelled else { return nil }
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath) else { continue }
            for item in contents {
                if targets.contains(where: { $0.localizedCaseInsensitiveCompare(item) == .orderedSame }) {
                    return (basePath as NSString).appendingPathComponent(item)
                }
            }
        }
        return nil
    }

    /// 递归扫描目录树找匹配的 .app（启发式，限制深度）
    private static func findMatchingApp(in directory: String, matcher: AppNameMatcher, depth: Int) -> String? {
        guard depth > 0 else { return nil }
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return nil }

        for item in contents where !item.hasPrefix(".") {
            guard !Task.isCancelled else { return nil }
            let fullPath = (directory as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if isDir.boolValue && item.hasSuffix(".app") {
                if matcher.matches(item: item) { return fullPath }
                continue
            }

            if isDir.boolValue,
               let found = findMatchingApp(in: fullPath, matcher: matcher, depth: depth - 1) {
                return found
            }
        }
        return nil
    }

    private static func isAppBundle(at path: String) -> Bool {
        guard path.hasSuffix(".app") else { return false }
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    // MARK: - 候选名与路径

    private static func namingCandidates(token: String, displayNames: [String]) -> [String] {
        var names: [String] = [token]
        names.append(contentsOf: displayNames)

        var candidates: [String] = []
        for name in names {
            candidates.append(name)
            candidates.append(name.prefix(1).uppercased() + name.dropFirst())

            let words = name.components(separatedBy: "-")
            if words.count > 1 {
                candidates.append(words.joined(separator: " "))
                candidates.append(
                    words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
                )
            }
        }
        return Array(Set(candidates))
    }

    private static func applicationRoots() -> [String] {
        [
            "/Applications",
            NSHomeDirectory() + "/Applications",
        ]
    }

    /// Homebrew 的 Caskroom 根目录（支持 Apple Silicon / Intel / 自定义前缀）。
    /// 标准路径存在时直接使用，跳过 BrewLocator.locate()（会同步拉起 2 个 brew 子进程）；
    /// 仅当标准路径都不存在（自定义前缀安装）时才定位。
    /// 已知边界：同时装有标准 + 自定义前缀两套 brew 时只覆盖标准路径，图标回退 SF Symbol。
    private static let caskroomRoots: [String] = {
        var roots = [
            "/opt/homebrew/Caskroom",
            "/usr/local/Caskroom",
        ].filter { FileManager.default.fileExists(atPath: $0) }
        if roots.isEmpty, let install = BrewLocator.locate() {
            roots.append((install.prefix as NSString).appendingPathComponent("Caskroom"))
        }
        return Array(Set(roots))
    }()

    /// 应用名匹配器：先精确/归一化，再前缀兜底（如 "SF Symbols" → "SF Symbols Beta"）
    nonisolated private struct AppNameMatcher {
        let candidates: [String]
        private let normalizedCandidates: [String]

        init(candidates: [String]) {
            self.candidates = candidates
            self.normalizedCandidates = candidates.map(Self.normalize)
        }

        func matches(item: String) -> Bool {
            let appName = item.hasSuffix(".app") ? String(item.dropLast(4)) : item
            let normalizedApp = Self.normalize(appName)

            // 第一轮：精确 / 归一化相等
            for (i, candidate) in candidates.enumerated() {
                if appName.localizedCaseInsensitiveCompare(candidate) == .orderedSame { return true }
                if normalizedApp == normalizedCandidates[i] { return true }
            }
            // 第二轮：前缀兜底，避免精确名被跳过
            for (i, candidate) in candidates.enumerated() where candidate.count >= 3 {
                if normalizedApp.hasPrefix(normalizedCandidates[i]) { return true }
            }
            return false
        }

        private static func normalize(_ s: String) -> String {
            s.lowercased().filter { $0.isLetter || $0.isNumber }
        }
    }
}

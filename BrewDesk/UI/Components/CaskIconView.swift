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
    @State private var isLoading = true

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
        .task {
            await loadIcon()
        }
        .onChange(of: package) { _, _ in
            appIcon = nil
            isLoading = true
            Task { await loadIcon() }
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
            isLoading = false
            return
        }

        // 文件系统扫描在后台线程执行
        let path = await Task.detached(priority: .low) {
            CaskIconProvider.findAppPath(for: package.name)
        }.value

        guard let path else {
            isLoading = false
            return
        }

        // NSWorkspace.icon(forFile:) 必须在 MainActor 上调用
        let nsImage = NSWorkspace.shared.icon(forFile: path)
        nsImage.size = NSSize(width: 64, height: 64)

        appIcon = nsImage
        isLoading = false
    }
}

// MARK: - Cask 图标查找器

private enum CaskIconProvider {
    /// 查找 .app 路径（非 MainActor，可在后台调用）
    nonisolated static func findAppPath(for caskName: String) -> String? {
        let searchPaths = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
        ]

        let caskroomPath = "/opt/homebrew/Caskroom/\(caskName)"
        if FileManager.default.fileExists(atPath: caskroomPath) {
            if let appInCaskroom = findAppInDirectory(caskroomPath, caskName: caskName) {
                return appInCaskroom
            }
        }

        let intelCaskroomPath = "/usr/local/Caskroom/\(caskName)"
        if FileManager.default.fileExists(atPath: intelCaskroomPath) {
            if let appInCaskroom = findAppInDirectory(intelCaskroomPath, caskName: caskName) {
                return appInCaskroom
            }
        }

        let variations = namingVariations(for: caskName)

        for basePath in searchPaths {
            guard let contents = try? FileManager.default.contentsOfDirectory(atPath: basePath)
            else { continue }

            for item in contents {
                guard item.hasSuffix(".app") else { continue }
                let appName = String(item.dropLast(4))
                for variation in variations {
                    if appName.localizedCaseInsensitiveCompare(variation) == .orderedSame {
                        return (basePath as NSString).appendingPathComponent(item)
                    }
                }
            }
        }

        return nil
    }

    /// 在目录（如 Caskroom 版本子目录）中递归查找 .app
    nonisolated private static func findAppInDirectory(_ dirPath: String, caskName: String) -> String? {
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: dirPath)
        else { return nil }

        let variations = namingVariations(for: caskName)

        for item in contents {
            let fullPath = (dirPath as NSString).appendingPathComponent(item)
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDir) else { continue }

            if item.hasSuffix(".app") {
                let appName = String(item.dropLast(4))
                for variation in variations {
                    if appName.localizedCaseInsensitiveCompare(variation) == .orderedSame {
                        return fullPath
                    }
                }
            }

            // 递归查找子目录（Caskroom 内有版本号子目录）
            if isDir.boolValue {
                if let found = findAppInDirectory(fullPath, caskName: caskName) {
                    return found
                }
            }
        }
        return nil
    }

    nonisolated private static func namingVariations(for caskName: String) -> [String] {
        var variations: [String] = [caskName]

        // "visual-studio-code" → "Visual Studio Code"
        let words = caskName.components(separatedBy: "-")
        if words.count > 1 {
            let withSpaces = words.joined(separator: " ")
            variations.append(withSpaces)

            let titleCased = words
                .map { $0.prefix(1).uppercased() + $0.dropFirst() }
                .joined(separator: " ")
            variations.append(titleCased)
        }

        // "visual-studio-code" → "Visual-studio-code"
        let capitalized = caskName.prefix(1).uppercased() + caskName.dropFirst()
        variations.append(capitalized)

        return variations
    }
}

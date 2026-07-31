//
//  Package.swift
//  BrewDesk
//

import Foundation

nonisolated enum PackageKind: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case formula
    case cask

    var id: String { rawValue }

    var title: String {
        switch self {
        case .formula: "Formula"
        case .cask: "Cask"
        }
    }
}

nonisolated struct Package: Identifiable, Hashable, Sendable {
    var id: String { "\(kind.rawValue):\(name)" }

    let name: String
    let kind: PackageKind
    var version: String?
    var latestVersion: String?
    var desc: String?
    var homepage: URL?
    var isInstalled: Bool
    var isOutdated: Bool
    var isPinned: Bool
    var dependencies: [String]
    var installedOnRequest: Bool
    var installedTime: Date?
    var analyticsInstall30d: Int?
    var analyticsInstall90d: Int?
    var analyticsInstall365d: Int?
    var analyticsInstallOnRequest30d: Int?
    var analyticsInstallOnRequest90d: Int?
    var analyticsInstallOnRequest365d: Int?

    /// cask 的权威应用信息（来自 `brew info --json` 的 artifacts 字段），
    /// 用于精确查找已安装应用的图标，避免靠猜名字。
    var caskArtifacts: [CaskArtifact] = []
    /// cask 的展示名数组（来自 JSON 的 name 字段），用于匹配兜底。
    var caskDisplayNames: [String] = []

    // MARK: - 完整信息（来自 brew info --json=v2）

    /// 许可证，如 "GPL-3.0-or-later"
    var license: String?
    /// 来源 tap，如 "homebrew/core"
    var tap: String?
    /// 下载地址（formula 的 stable 源 / cask 的 url）
    var sourceURL: URL?
    /// 安装后的注意事项
    var caveats: String?
    /// 冲突的软件包
    var conflictsWith: [String] = []
    /// 是否已废弃
    var isDeprecated: Bool = false
    var deprecationReason: String?
    var deprecationDate: String?
    /// 是否已禁用
    var isDisabled: Bool = false
    var disableReason: String?
    var disableDate: String?
    /// keg-only（仅装入 Cellar，不链接到 PATH）
    var kegOnly: Bool = false
    var kegOnlyReason: String?
    /// 构建期依赖（formula）
    var buildDependencies: [String] = []
    /// 使用 macOS 自带组件（formula）
    var usesFromMacOS: [String] = []
    /// 全部已安装版本
    var installedVersions: [String] = []
    /// cask 是否自动更新
    var autoUpdates: Bool = false
    /// cask 安装包 sha256
    var sha256: String?
    /// cask 的 depends_on 摘要，如 ["macOS >= 11", "formula: x, y"]
    var caskDependsOn: [String] = []

    var versionLabel: String {
        if let version, let latestVersion, isOutdated {
            return "\(version) → \(latestVersion)"
        }
        return version ?? latestVersion ?? "—"
    }

    var installedTimeLabel: String {
        guard let t = installedTime else { return "—" }
        let fmt = DateFormatter()
        fmt.dateStyle = .medium
        fmt.timeStyle = .short
        return fmt.string(from: t)
    }
}

/// `brew info --json` 中某个 cask artifact 的应用信息。
nonisolated struct CaskArtifact: Hashable, Sendable {
    /// 应用包名，如 `["Downie 4.app"]`
    let appNames: [String]
    /// 安装目标路径，如 `/Applications/Downie 4.app`
    let target: String?
}

//
//  UpdaterController.swift
//  BrewDesk
//
//  Sparkle 更新管理器
//

import Combine
import Foundation
import Sparkle

/// 管理 Sparkle 自动更新流程，作为 SwiftUI 的 ObservableObject 使用。
final class UpdaterController: NSObject, ObservableObject {
    private(set) lazy var updaterController: SPUStandardUpdaterController = {
        // 启用 Sparkle 调试日志
        UserDefaults.standard.set(true, forKey: "SUEnableVerboseLogging")
        return SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: self,
            userDriverDelegate: nil
        )
    }()

    @Published var canCheckForUpdates = false

    override init() {
        super.init()
        // 触发懒加载创建 updaterController
        _ = updaterController
        updaterController.updater.publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)

        // 打印当前版本信息
        let bundle = Bundle.main
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        print("[Updater] App 版本: \(shortVersion) (\(buildVersion))")
        print("[Updater] Feed URL: \(feedURLString(for: updaterController.updater) ?? "nil")")
    }

    /// 手动检查更新
    func checkForUpdates() {
        let bundle = Bundle.main
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let buildVersion = bundle.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        print("[Updater] 手动检查更新 — 本地版本: \(shortVersion) (\(buildVersion))")
        updaterController.checkForUpdates(nil)
    }

    /// 获取更新设置（自动检查、自动下载等）
    var updater: SPUUpdater { updaterController.updater }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterController: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String? {
        "https://raw.githubusercontent.com/ftzahao/BrewDesk/main/appcast.xml"
    }

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        // appcast.xml 中使用了 <sparkle:channel>release</sparkle:channel>
        // 必须显式声明允许的频道，否则该条目会被过滤掉
        ["release"]
    }

    func updater(_ updater: SPUUpdater, didFinishLoading appcast: SUAppcast) {
        print("[Updater] Appcast 加载成功，共 \(appcast.items.count) 个条目")
        for item in appcast.items {
            print(
                "  - 版本: \(item.versionString) (\(item.displayVersionString))"
            )
        }
    }

    func updaterDidNotFindUpdate(_ updater: SPUUpdater) {
        print("[Updater] 未找到更新 ❌")
    }

    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        print(
            "[Updater] 找到更新 ✅ — \(item.displayVersionString) (\(item.versionString))"
        )
    }
}

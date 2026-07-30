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
        SPUStandardUpdaterController(
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
    }

    /// 手动检查更新
    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }

    /// 获取更新设置（自动检查、自动下载等）
    var updater: SPUUpdater { updaterController.updater }
}

// MARK: - SPUUpdaterDelegate

extension UpdaterController: SPUUpdaterDelegate {
    func feedURLString(for updater: SPUUpdater) -> String {
        "https://raw.githubusercontent.com/ftzahao/BrewDesk/main/appcast.xml"
    }
}

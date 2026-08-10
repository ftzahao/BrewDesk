//
//  BrewfilePanel.swift
//  BrewDesk
//
//  导出 Brewfile 的保存面板：纯视图层工具，AppState 只负责执行导出。
//  （原实现内嵌在 AppState.exportBrewfileInteractively 中，两处调用方各写一份。）
//

import AppKit
import UniformTypeIdentifiers

enum BrewfilePanel {
    static func presentExport(on state: AppState) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "导出 Brewfile"
        panel.nameFieldStringValue = "Brewfile"
        panel.allowedContentTypes = [UTType.plainText, UTType.data]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await state.exportBrewfile(to: url) }
        }
    }
}

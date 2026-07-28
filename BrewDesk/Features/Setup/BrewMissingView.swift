//
//  BrewMissingView.swift
//  BrewDesk
//

import SwiftUI

struct BrewMissingView: View {
    var onRetry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("未找到 Homebrew", systemImage: "mug.fill")
        } description: {
            Text("BrewDesk 需要本机已安装 Homebrew。安装完成后点击重新检测。")
        } actions: {
            Link("打开安装说明", destination: URL(string: "https://brew.sh")!)
                .buttonStyle(.glassCapsule)

            Button("重新检测", systemImage: "arrow.clockwise") {
                onRetry()
            }
            .buttonStyle(.glassCapsule)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

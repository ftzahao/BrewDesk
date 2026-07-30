//
//  AboutView.swift
//  BrewDesk
//

import AppKit
import Sparkle
import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var updater: UpdaterController

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 420, height: 460)
    }

    private var header: some View {
        VStack(spacing: 12) {
            appIcon
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: .black.opacity(0.12), radius: 10, y: 4)

            Text("BrewDesk")
                .font(.title.weight(.semibold))

            Text("Homebrew 的原生 macOS 图形界面")
                .foregroundStyle(.secondary)

            Text("版本 \(appVersion)")
                .font(.callout.monospacedDigit())
                .foregroundStyle(.secondary)

            Button {
                updater.checkForUpdates()
            } label: {
                Label("检查更新…", systemImage: "arrow.down.circle")
            }
            .buttonStyle(.glassCapsule)
            .disabled(!updater.canCheckForUpdates)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 28)
        .padding(.horizontal, 24)
        .background {
            Rectangle()
                .fill(.regularMaterial)
        }
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = NSApp.applicationIconImage {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [Color.accentColor.opacity(0.85), Color.accentColor.opacity(0.45)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                Image(systemName: "mug.fill")
                    .font(.system(size: 40, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private var content: some View {
        Form {
            Section("功能") {
                Label("浏览、搜索、安装与卸载 formula / cask", systemImage: "shippingbox")
                Label("检查更新、固定版本、服务管理", systemImage: "arrow.triangle.2.circlepath")
                Label("Cleanup、Brewfile 迁移", systemImage: "stethoscope")
                Label("菜单栏状态与任务通知", systemImage: "bell")
            }

            Section("技术") {
                LabeledContent("界面", value: "SwiftUI")
                LabeledContent("后端", value: "Homebrew CLI")
                LabeledContent("更新框架", value: "Sparkle")
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
            }

            Section("致谢") {
                Text("Homebrew 由 Homebrew 社区维护。BrewDesk 只是它的图形前端，所有包装操作最终由 brew 命令完成。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Link(destination: URL(string: "https://brew.sh")!) {
                    Label("Homebrew 官网", systemImage: "safari")
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var footer: some View {
        HStack {
            Text("本地工具 · 不上传你的软件包列表")
                .font(.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button("好") {
                dismiss()
            }
            .buttonStyle(.glassCapsule)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.bar)
    }
}

struct AboutView_Previews: PreviewProvider {
    static var previews: some View {
        AboutView()
    }
}

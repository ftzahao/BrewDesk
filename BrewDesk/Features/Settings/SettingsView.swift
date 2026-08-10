//
//  SettingsView.swift
//  BrewDesk
//

import AppKit
import Sparkle
import SwiftUI

struct SettingsView: View {
    @Bindable var state: AppState
    @State private var showAbout = false

    private var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"]  as? String ?? "?"
        return "\(short)"
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section {
                    if let installation = state.installation {
                        LabeledContent("版本", value: installation.version)
                        LabeledContent("路径") {
                            Text(installation.executableURL.path)
                                .textSelection(.enabled)
                                .foregroundStyle(.secondary)
                        }
                        LabeledContent("前缀", value: installation.prefix)
                    } else {
                        Label("未检测到 Homebrew", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Label("Homebrew", systemImage: "mug")
                } footer: {
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("自定义 brew 路径（可选）", text: $state.customBrewPath)
                            .textFieldStyle(.roundedBorder)
                            .help("例如 /opt/homebrew/bin/brew")
                        HStack {
                            Button("重新检测") { Task { await state.redetectBrew() } }
                                .buttonStyle(.glassCapsule)
                            Button("打开 Homebrew 网站") {
                                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
                            }
                            .buttonStyle(.glassCapsule)
                            Spacer()
                        }
                    }
                }

                Section {
                    Toggle("默认仅显示手动安装的 formula", isOn: state.asyncBinding(\.showOnlyRequested))
                        .help("作为依赖安装的 formula 默认隐藏，可在已安装页随时切换")
                } header: {
                    Label("列表", systemImage: "list.bullet")
                } footer: {
                    Text("作为依赖安装的 formula 默认隐藏，可在已安装页随时切换。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("任务完成时发送系统通知", isOn: state.asyncBinding(\.notificationsEnabled))
                        .onChange(of: state.notificationsEnabled) { _, enabled in
                            guard enabled else { return }
                            NotificationService.requestAuthorizationIfNeeded()
                        }
                } header: {
                    Label("通知", systemImage: "bell")
                } footer: {
                    Text("安装、升级、卸载、清理、Brewfile 等任务结束时通知。首次开启会请求系统权限。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Toggle("自动检查更新", isOn: state.asyncBinding(\.autoCheckForUpdates))
                        .onChange(of: state.autoCheckForUpdates) { _, enabled in
                            state.updater?.updater.automaticallyChecksForUpdates = enabled
                        }
                    Toggle("自动下载更新", isOn: state.asyncBinding(\.autoDownloadUpdates))
                        .onChange(of: state.autoDownloadUpdates) { _, enabled in
                            state.updater?.updater.automaticallyDownloadsUpdates = enabled
                        }
                    Button {
                        state.updater?.checkForUpdates()
                    } label: {
                        Label("立即检查更新…", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.updater?.canCheckForUpdates != true)
                } header: {
                    Label("更新", systemImage: "arrow.down.circle")
                } footer: {
                    Text("BrewDesk 使用 Sparkle 框架自动更新应用本身。设置应用更新前会通知你。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    Picker("主题", selection: state.asyncBinding(\.appearanceMode)) {
                        ForEach(AppState.AppearanceMode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } header: {
                    Label("外观", systemImage: "paintbrush")
                } footer: {
                    Text("更改后立即生效，无需重启应用。")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section {
                    LabeledContent("刷新全部", value: "⇧⌘R")
                    LabeledContent("全部升级", value: "⇧⌘U")
                } header: {
                    Label("快捷键", systemImage: "command")
                }

                Section {
                    LabeledContent("应用", value: "BrewDesk")
                    LabeledContent("版本", value: appVersion)
                    LabeledContent("用途", value: "Homebrew 图形界面")
                    Button { showAbout = true } label: {
                        Label("打开关于页…", systemImage: "info.circle")
                    }
                    .buttonStyle(.glassCapsule)
                } header: {
                    Label("关于", systemImage: "info.circle")
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .padding(.horizontal, Design.pagePadding)
            .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .navigationTitle("设置")
        .navigationSubtitle("偏好、外观、更新与关于")
        .sheet(isPresented: $showAbout) { AboutView() }
    }

}

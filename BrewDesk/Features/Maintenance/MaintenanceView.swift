//
//  MaintenanceView.swift
//  BrewDesk
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct MaintenanceView: View {
    @ObservedObject var state: AppState
    @State private var confirmCleanup = false
    @State private var brewfileImporterMode: BrewfileImporterMode?

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    cleanupSection
                    brewfileSection
                }
                .padding(Design.pagePadding)
            }
            .scrollContentBackground(.hidden)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
        }
        .navigationTitle("维护")
        .navigationSubtitle("清理缓存与 Brewfile 迁移工具")
        .task {
            await state.loadCleanupPreviewIfNeeded()
        }
        .alert("确认清理？", isPresented: $confirmCleanup) {
            Button("清理", role: .destructive) { Task { await state.runCleanup() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将执行 \"brew cleanup --prune=all\"，删除所有缓存。此操作不可撤销。")
        }
        .fileImporter(
            isPresented: Binding(
                get: { brewfileImporterMode != nil },
                set: { if !$0 { brewfileImporterMode = nil } }
            ),
            allowedContentTypes: [.plainText, .data],
            allowsMultipleSelection: false
        ) { handleBrewfileImport($0) }
    }

    private var cleanupSection: some View {
        glassSection(title: "清理", systemImage: "trash") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("清除缓存")
                        .font(.headline)
                        .help("brew cleanup --prune=all")
                    Spacer()
                    Button { Task { await state.loadCleanupPreview() } } label: {
                        if state.isLoadingCleanupPreview {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("刷新预览", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.isLoadingCleanupPreview || state.isTaskRunning)
                    Button("执行清理", role: .destructive) { confirmCleanup = true }
                        .buttonStyle(.glassCapsule(tint: .red))
                        .disabled(state.isTaskRunning)
                }
                if let preview = state.cleanupPreview {
                    Text(preview.summary).foregroundStyle(.secondary)
                    if preview.isEmpty {
                        Label("没有可清理的缓存或旧版本。", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    } else {
                        ScrollView {
                            Text(preview.lines.joined(separator: "\n"))
                                .font(.system(.caption, design: .monospaced))
                                .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        }
                        .frame(maxHeight: 220).padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.regularMaterial)
                        }
                    }
                } else if state.isLoadingCleanupPreview {
                    ProgressView("生成清理预览…")
                } else {
                    Text("点击刷新预览查看将删除的内容。").foregroundStyle(.secondary)
                }
            }.padding(4)
        }
    }

    private var brewfileSection: some View {
        glassSection(title: "Brewfile", systemImage: "doc.on.doc") {
            VStack(alignment: .leading, spacing: 12) {
                Text("导出当前已安装列表，或从 Brewfile 安装 / 检查依赖。适合换机迁移。")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button { exportBrewfileViaPanel() } label: {
                        Label("导出 Brewfile…", systemImage: "square.and.arrow.up")
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.isTaskRunning)
                    Button { brewfileImporterMode = .install } label: {
                        Label("从 Brewfile 安装…", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.isTaskRunning)
                    Button { brewfileImporterMode = .check } label: {
                        Label("检查 Brewfile…", systemImage: "checklist")
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.isTaskRunning)
                }
                if let result = state.brewfileCheckResult {
                    let ok = state.brewfileCheckOK ?? false
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(ok ? Color.green : Color.orange)
                        Text(result.isEmpty ? (ok ? "全部依赖已安装。" : "存在未满足的依赖。") : result)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(10)
                    .background {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(.regularMaterial)
                    }
                }
            }.padding(4)
        }
    }

    private func glassSection<Content: View>(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .fill(.regularMaterial)
        }
        .overlay(
            RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 1)
        )
    }

    private func exportBrewfileViaPanel() { state.exportBrewfileInteractively() }

    private func handleBrewfileImport(_ result: Result<[URL], Error>) {
        let mode = brewfileImporterMode
        brewfileImporterMode = nil
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            let access = url.startAccessingSecurityScopedResource()
            Task { @MainActor in
                defer { if access { url.stopAccessingSecurityScopedResource() } }
                switch mode {
                case .install: await state.importBrewfile(from: url)
                case .check: await state.checkBrewfile(from: url)
                case .none: break
                }
            }
        case .failure(let error):
            state.lastError = error.localizedDescription
        }
    }
}

private enum BrewfileImporterMode { case install, check }

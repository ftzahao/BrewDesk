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
    @State private var selectedIssueID: DoctorIssue.ID?
    @State private var brewfileImporterMode: BrewfileImporterMode?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                doctorSection
                cleanupSection
                brewfileSection
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        }
        .navigationTitle("维护")
        .task {
            if !state.doctorRan { await state.runDoctor() }
            if state.cleanupPreview == nil { await state.loadCleanupPreview() }
        }
        .alert("确认清理？", isPresented: $confirmCleanup) {
            Button("清理", role: .destructive) { Task { await state.runCleanup() } }
            Button("取消", role: .cancel) {}
        } message: {
            Text("将执行 brew cleanup -s，删除旧版本下载与过期缓存。此操作不可撤销。")
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

    private var doctorSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("brew doctor", systemImage: "stethoscope").font(.headline)
                    Spacer()
                    Button { Task { await state.runDoctor() } } label: {
                        if state.isLoadingDoctor {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("重新检查", systemImage: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.glassCapsule)
                    .disabled(state.isLoadingDoctor || state.isTaskRunning)
                }
                if state.isLoadingDoctor && !state.doctorRan {
                    ProgressView("正在检查…")
                        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 12)
                } else if state.doctorRan && state.doctorHealthy {
                    Label("系统看起来正常，可以安心使用 Homebrew。", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(.green).padding(.vertical, 4)
                } else if state.doctorIssues.isEmpty && state.doctorRan {
                    Text("未解析到具体警告，原始输出如下：").foregroundStyle(.secondary)
                    Text(state.doctorRaw.isEmpty ? "（无输出）" : state.doctorRaw)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                        .background {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                        }
                } else {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(state.doctorIssues) { issue in
                            DoctorIssueCard(issue: issue, isExpanded: selectedIssueID == issue.id) {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedIssueID = selectedIssueID == issue.id ? nil : issue.id
                                }
                            }
                        }
                    }
                }
            }.padding(4)
        } label: { Text("健康检查") }
    }

    private var cleanupSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("brew cleanup", systemImage: "trash").font(.headline)
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
                        .disabled(state.isTaskRunning || (state.cleanupPreview?.isEmpty ?? true))
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
                            RoundedRectangle(cornerRadius: 8)
                                .fill(.regularMaterial)
                        }
                    }
                } else if state.isLoadingCleanupPreview {
                    ProgressView("生成清理预览…")
                } else {
                    Text("点击刷新预览查看将删除的内容。").foregroundStyle(.secondary)
                }
            }.padding(4)
        } label: { Text("清理") }
    }

    private var brewfileSection: some View {
        GroupBox {
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
                        RoundedRectangle(cornerRadius: 8)
                            .fill(.regularMaterial)
                    }
                }
            }.padding(4)
        } label: { Text("Brewfile") }
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

private struct DoctorIssueCard: View {
    let issue: DoctorIssue
    var isExpanded: Bool
    var onToggle: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: issue.severity.systemImage)
                        .foregroundStyle(issue.severity == .error ? Color.red : Color.orange)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title).font(.body.weight(.medium))
                            .foregroundStyle(.primary).multilineTextAlignment(.leading)
                        if !isExpanded, !issue.detail.isEmpty {
                            Text(issue.detail).font(.caption).foregroundStyle(.secondary)
                                .lineLimit(2).multilineTextAlignment(.leading)
                        }
                    }
                    Spacer()
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            if isExpanded, !issue.detail.isEmpty {
                Text(issue.detail)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    .background {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.regularMaterial)
                    }
            }
        }
        .padding(10)
        .background {
            RoundedRectangle(cornerRadius: 10)
                .fill(.regularMaterial)
        }
    }
}

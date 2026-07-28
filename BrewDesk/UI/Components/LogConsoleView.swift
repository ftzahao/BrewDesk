//
//  LogConsoleView.swift
//  BrewDesk
//

import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct LogConsoleView: View {
    @ObservedObject var state: AppState
    @State private var autoScroll = true
    @State private var filterText = ""
    @FocusState private var filterFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if state.isLogExpanded {
                logContent
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .overlay(alignment: .top) { Divider() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.secondary)
                .font(.system(size: 12))
            if state.isTaskRunning {
                ProgressView().controlSize(.small)
                Text(state.currentTaskTitle ?? "运行中…")
                    .font(.callout.weight(.medium)).lineLimit(1)
            } else {
                Text("日志").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            }
            Spacer()

            if !state.logText.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.tertiary)
                        .font(.caption2)
                    TextField("过滤", text: $filterText)
                        .textFieldStyle(.plain)
                        .focused($filterFocused)
                        .frame(width: 100)
                    if !filterText.isEmpty {
                        Button { filterText = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
            }

            if !state.logText.isEmpty {
                Toggle(isOn: $autoScroll) {
                    Text("自动滚动").font(.caption)
                }
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("当日志更新时自动滚动到底部")
            }

            if state.isTaskRunning {
                Button(role: .destructive) { state.cancelTask() } label: {
                    Label("取消", systemImage: "xmark.circle")
                }
                .buttonStyle(.glassCapsule(tint: .red))
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }
            Button { copyLog() } label: {
                Label("复制", systemImage: "doc.on.doc")
            }
            .buttonStyle(.glassCapsule)
            .controlSize(.small)
            .disabled(state.logText.isEmpty)
            .help("复制全部日志")
            Button { exportLog() } label: {
                Label("导出", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.glassCapsule)
            .controlSize(.small)
            .disabled(state.logText.isEmpty)
            .help("导出日志到文件")
            Button { state.clearLog() } label: {
                Label("清空", systemImage: "trash")
            }
            .buttonStyle(.glassCapsule(tint: .red))
            .controlSize(.small)
            .disabled(state.logText.isEmpty)
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { state.isLogExpanded.toggle() }
            } label: {
                Label(state.isLogExpanded ? "收起" : "展开",
                      systemImage: state.isLogExpanded ? "chevron.down" : "chevron.up")
            }
            .buttonStyle(.glassCapsule)
            .controlSize(.small)
            .keyboardShortcut("l", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .onTapGesture(count: 2) {
            withAnimation(.easeInOut(duration: 0.15)) { state.isLogExpanded.toggle() }
        }
    }

    // MARK: - Log Content

    private var logContent: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical]) {
                if state.logText.isEmpty {
                    emptyView
                } else if formattedText.isEmpty {
                    noMatchView
                } else {
                    Text(formattedText)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .id("log-end")
                }
            }
            .frame(minHeight: 120, idealHeight: 180, maxHeight: 320)
            .background {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.06)))
            }
            .onChange(of: state.logText) { _, _ in
                guard autoScroll else { return }
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("log-end", anchor: .bottom)
                }
            }
        }
    }

    // MARK: - Empty States

    private var emptyView: some View {
        Text(placeholderText)
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .id("log-end")
    }

    private var noMatchView: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.tertiary)
            Text("无匹配「\(filterText)」")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .top)
        .padding(20)
        .id("log-end")
    }

    // MARK: - Formatting

    /// 带行号的格式化日志文本
    private var formattedText: String {
        let lines = state.logText.components(separatedBy: "\n")
        let q = filterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = q.isEmpty ? lines : lines.filter { $0.localizedCaseInsensitiveContains(q) }
        let width = max("\(target.count)".count, 2)
        return target.enumerated().map { i, line in
            let num = String(format: "%\(width)d", i + 1)
            return "\(num) │ \(line)"
        }.joined(separator: "\n")
    }

    private var placeholderText: String {
        "等待任务执行…\n安装、升级、卸载时会显示 brew 输出。"
    }

    // MARK: - Actions

    private func copyLog() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(state.logText, forType: .string)
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "brewdesk-log-\(Self.logDateFormatter.string(from: Date())).txt"
        panel.begin { result in
            guard result == .OK, let url = panel.url else { return }
            try? state.logText.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static let logDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()
}

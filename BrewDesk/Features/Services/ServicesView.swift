//
//  ServicesView.swift
//  BrewDesk
//

import SwiftUI

struct ServicesView: View {
    @ObservedObject var state: AppState
    /// 本地选中 ID：避免直接在视图更新周期内修改 @Published 属性
    @State private var localSelection: BrewService.ID?

    var body: some View {
        TwoColumnPage {
            listColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("服务")
        .task { await state.loadServices() }
    }

    private var listColumn: some View {
        List(selection: Binding(
            get: { localSelection },
            set: { newValue in
                localSelection = newValue
                DispatchQueue.main.async {
                    state.selectedServiceID = newValue
                }
            }
        )) {
            ForEach(state.services) { service in
                ServiceRowView(service: service)
                    .tag(Optional(service.id))
                    .contextMenu { serviceMenu(service) }
            }
        }
        .onReceive(state.$selectedServiceID) { id in
            if localSelection != id {
                localSelection = id
            }
        }
        .overlay {
            if state.isLoadingServices && state.services.isEmpty {
                ProgressView("加载服务…")
            } else if state.services.isEmpty {
                ContentUnavailableView {
                    Label("没有 brew 服务", systemImage: "bolt.horizontal.circle")
                } description: {
                    Text("已安装且支持 services 的 formula 会显示在这里。")
                }
            }
        }
        .toolbar {
            ToolbarItem {
                Button { Task { await state.loadServices() } } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }.disabled(state.isLoadingServices || state.isTaskRunning)
            }
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text("\(state.services.count) 个服务 · \(state.runningServiceCount) 运行中")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12).padding(.vertical, 6).background(.bar)
        }
    }

    @ViewBuilder
    private var detailColumn: some View {
        if let service = state.selectedService {
            ServiceDetailView(
                service: service, isBusy: state.isTaskRunning,
                onStart: { Task { await state.startService(service) } },
                onStop: { Task { await state.stopService(service) } },
                onRestart: { Task { await state.restartService(service) } }
            )
        } else {
            ContentUnavailableView {
                Label("选择一个服务", systemImage: "bolt.horizontal.circle")
            } description: {
                Text("在左侧列表中选择，可查看状态、启动或停止服务。")
            }
        }
    }

    @ViewBuilder
    private func serviceMenu(_ service: BrewService) -> some View {
        Button("启动") { Task { await state.startService(service) } }
            .disabled(service.status == .started || state.isTaskRunning)
        Button("停止") { Task { await state.stopService(service) } }
            .disabled(service.status == .stopped || service.status == .none || state.isTaskRunning)
        Button("重启") { Task { await state.restartService(service) } }
            .disabled(state.isTaskRunning)
    }
}

private struct ServiceRowView: View {
    let service: BrewService
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: service.status.systemImage)
                .foregroundStyle(statusColor).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(service.name).font(.body.weight(.medium))
                Text(service.status.title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            if let user = service.user, !user.isEmpty {
                Text(user).font(.caption).foregroundStyle(.tertiary)
            }
        }.padding(.vertical, 2)
    }
    private var statusColor: Color {
        switch service.status {
        case .started: .green
        case .error: .orange
        case .stopped, .none, .unknown: .secondary
        }
    }
}

private struct ServiceDetailView: View {
    let service: BrewService
    var isBusy: Bool
    var onStart: () -> Void
    var onStop: () -> Void
    var onRestart: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.name).font(.largeTitle.weight(.semibold))
                    Label(service.status.title, systemImage: service.status.systemImage)
                        .foregroundStyle(.secondary)
                }
                HStack(spacing: 10) {
                    Button("启动", systemImage: "play.fill", action: onStart)
                        .buttonStyle(.borderedProminent)
                        .disabled(isBusy || service.status == .started)
                    Button("停止", systemImage: "stop.fill", action: onStop)
                        .disabled(isBusy || service.status == .stopped || service.status == .none)
                    Button("重启", systemImage: "arrow.clockwise", action: onRestart)
                        .disabled(isBusy)
                }
                GroupBox("信息") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                        gridRow("状态", "\(service.status.title) (\(service.statusRaw))")
                        gridRow("用户", service.user?.isEmpty == false ? service.user! : "—")
                        gridRow("Plist", service.file ?? "—")
                        if let code = service.exitCode { gridRow("退出码", "\(code)") }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(4)
                }
            }.padding(24).frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func gridRow(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).textSelection(.enabled)
        }
    }
}

//
//  ContentView.swift
//  BrewDesk
//
//  Created by 师梦豪 on 2026/7/28.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState
    @State private var sidebarSelection: SidebarItem? = .home

    var body: some View {
        Group {
            if state.installation == nil {
                BrewMissingView {
                    Task { await state.redetectBrew() }
                }
            } else {
                mainInterface
            }
        }
        .frame(minWidth: 900, minHeight: 560)
        .overlay(alignment: .top) {
            if let error = state.lastError {
                StatusToast(message: error, isError: true) {
                    state.lastError = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding()
            } else if let status = state.lastStatus {
                StatusToast(message: status) {
                    state.lastStatus = nil
                }
                .transition(.move(edge: .top).combined(with: .opacity))
                .padding()
            }
        }
        .animation(.easeOut(duration: 0.12), value: state.lastError)
        .animation(.easeOut(duration: 0.12), value: state.lastStatus)
    }

    private var mainInterface: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 200, ideal: 220, max: 360)
        } detail: {
            detail(for: state.selectedSidebar)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .id(state.selectedSidebar)
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if state.isTaskRunning {
                    ProgressView().controlSize(.small)
                    Text(state.currentTaskTitle ?? "")
                        .foregroundStyle(.secondary).font(.callout)
                }
            }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            // App branding header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.accentColor.opacity(0.12))
                        .frame(width: 26, height: 26)
                    Image(systemName: "mug.fill")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                Text("BrewDesk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)

            Divider()

            List(selection: $sidebarSelection) {
                Section {
                    NavigationLink(destination: HomeView(state: state)) {
                        sidebarLabel(.home)
                    }
                    .tag(SidebarItem.home as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                    NavigationLink(destination: InstalledView(state: state)) {
                        sidebarLabel(.installed)
                    }
                    .tag(SidebarItem.installed as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                    NavigationLink(destination: OutdatedView(state: state)) {
                        sidebarLabel(.outdated)
                    }
                    .tag(SidebarItem.outdated as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                } header: {
                    sectionHeader("软件包")
                }

                Section {
                    NavigationLink(destination: TapsView(state: state)) {
                        sidebarLabel(.taps)
                    }
                    .tag(SidebarItem.taps as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                    NavigationLink(destination: ServicesView(state: state)) {
                        sidebarLabel(.services)
                    }
                    .tag(SidebarItem.services as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                    NavigationLink(destination: MaintenanceView(state: state)) {
                        sidebarLabel(.maintenance)
                    }
                    .tag(SidebarItem.maintenance as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                } header: {
                    sectionHeader("系统")
                }

                Section {
                    NavigationLink(destination: SettingsView(state: state)) {
                        sidebarLabel(.settings)
                    }
                    .tag(SidebarItem.settings as SidebarItem?)
                    .listRowInsets(EdgeInsets(top: 1.5, leading: 10, bottom: 1.5, trailing: 10))
                    .listRowSeparator(.hidden)
                } header: {
                    sectionHeader("其他")
                }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .onChange(of: sidebarSelection) { _, newValue in
                if let value = newValue {
                    state.selectedSidebar = value
                    if value != .home {
                        state.deactivateSearch()
                    }
                }
            }
            .onChange(of: state.selectedSidebar) { _, newValue in
                sidebarSelection = newValue
            }

            Divider()
            sidebarFooter
        }
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .ignoresSafeArea()
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.8)
    }

    private func sidebarLabel(_ item: SidebarItem) -> some View {
        HStack(spacing: 10) {
            // Icon with rounded container
            ZStack {
                RoundedRectangle(cornerRadius: 7)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 22, height: 22)
                Image(systemName: item.filledImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(item.title)
                .font(.system(size: 13))

            Spacer(minLength: 0)
            let count = badge(for: item)
            if count > 0 {
                Text("\(count)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Color.accentColor)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor.opacity(0.12)))
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func detail(for item: SidebarItem) -> some View {
        switch item {
        case .home:
            if state.isSearchActive {
                SearchResultsView(state: state)
            } else {
                HomeView(state: state)
            }
        case .installed: InstalledView(state: state)
        case .outdated: OutdatedView(state: state)
        case .taps: TapsView(state: state)
        case .services: ServicesView(state: state)
        case .maintenance: MaintenanceView(state: state)
        case .settings: SettingsView(state: state)
        }
    }

    private func badge(for item: SidebarItem) -> Int {
        switch item {
        case .outdated: state.outdated.count
        case .services: state.runningServiceCount
        case .maintenance: 0
        default: 0
        }
    }

    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let inst = state.installation {
                HStack(spacing: 5) {
                    Circle()
                        .fill(state.isTaskRunning ? Color.orange : Color.green)
                        .frame(width: 6, height: 6)
                    Text(inst.version)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Text(inst.prefix)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .help(inst.executableURL.path)
            } else {
                Text("未检测到 Homebrew")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(EdgeInsets(top: 8, leading: 14, bottom: 10, trailing: 14))
        .background {
            Rectangle().fill(.ultraThinMaterial)
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

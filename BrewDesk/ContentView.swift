//
//  ContentView.swift
//  BrewDesk
//
//  根视图：以主页为入口 Hub，不再使用侧边栏；各功能页通过工具栏返回按钮回到主页。
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

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
        .onChange(of: state.selectedSidebar) { _, newValue in
            if newValue != .home {
                state.deactivateSearch()
            }
        }
    }

    private var mainInterface: some View {
        detail(for: state.selectedSidebar)
            .id(state.selectedSidebar)
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    if state.isTaskRunning {
                        ProgressView().controlSize(.small)
                        Text(state.currentTaskTitle ?? "")
                            .foregroundStyle(.secondary).font(.callout)
                    }
                }

                if state.selectedSidebar != .home {
                    ToolbarItem(placement: .navigation) {
                        Button {
                            state.selectedSidebar = .home
                        } label: {
                            Label("返回主页", systemImage: "chevron.left")
                        }
                        .help("返回主页")
                    }
                }
            }
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
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View { ContentView() }
}

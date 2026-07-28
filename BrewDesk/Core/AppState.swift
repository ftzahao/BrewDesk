//
//  AppState.swift
//  BrewDesk
//

import AppKit
import Combine
import Foundation
import SwiftUI
import UniformTypeIdentifiers

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case installed
    case outdated
    case search
    case taps
    case services
    case maintenance
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .installed: "已安装"
        case .outdated: "可更新"
        case .search: "搜索"
        case .taps: "Taps"
        case .services: "服务"
        case .maintenance: "维护"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .installed: "shippingbox"
        case .outdated: "arrow.triangle.2.circlepath"
        case .search: "magnifyingglass"
        case .taps: "square.grid.2x2"
        case .services: "bolt.horizontal.circle"
        case .maintenance: "stethoscope"
        case .settings: "gearshape"
        }
    }

    /// Filled variant for sidebar icon display.
    var filledImage: String {
        switch self {
        case .installed: "shippingbox.fill"
        case .outdated: "arrow.triangle.2.circlepath"
        case .search: "magnifyingglass"
        case .taps: "square.grid.2x2"
        case .services: "bolt.horizontal.circle.fill"
        case .maintenance: "stethoscope"
        case .settings: "gearshape.fill"
        }
    }
}

enum TaskKind: String, Sendable {
    case refresh, update, upgrade, install, uninstall, search
    case doctor, cleanup, service, tap, bundle, pin

    var title: String {
        switch self {
        case .refresh: "刷新"
        case .update: "更新 Homebrew"
        case .upgrade: "升级"
        case .install: "安装"
        case .uninstall: "卸载"
        case .search: "搜索"
        case .doctor: "brew doctor"
        case .cleanup: "清理"
        case .service: "服务"
        case .tap: "Tap"
        case .bundle: "Brewfile"
        case .pin: "固定版本"
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    let client = BrewClient()

    @Published var installation: BrewInstallation?
    @Published var selectedSidebar: SidebarItem = .installed
    @Published var selectedPackageID: Package.ID?
    @Published var selectedServiceID: BrewService.ID?

    @Published var installed: [Package] = []
    @Published var outdated: [Package] = []
    @Published var searchResults: [Package] = []
    @Published var searchQuery: String = ""
    @Published var services: [BrewService] = []
    @Published var taps: [BrewTap] = []
    @Published var selectedTapID: String?

    @Published var doctorIssues: [DoctorIssue] = []
    @Published var doctorRaw: String = ""
    @Published var doctorHealthy = false
    @Published var doctorRan = false
    @Published var cleanupPreview: CleanupPreview?

    @Published var isLoadingInstalled = false
    @Published var isLoadingOutdated = false
    @Published var isSearching = false
    @Published var isLoadingServices = false
    @Published var isLoadingTaps = false
    @Published var isLoadingTapPackages = false
    @Published var isLoadingDoctor = false
    @Published var isLoadingCleanupPreview = false

    @Published var isTaskRunning = false
    @Published var currentTaskTitle: String?
    @Published var logText: String = ""
    @Published var isLogExpanded = false

    @Published var lastError: String?
    @Published var lastStatus: String?

    @Published var customBrewPath: String = UserDefaults.standard.string(forKey: "customBrewPath") ?? "" {
        didSet { UserDefaults.standard.set(customBrewPath, forKey: "customBrewPath") }
    }

    @Published var showOnlyRequested: Bool = UserDefaults.standard.object(forKey: "showOnlyRequested") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showOnlyRequested, forKey: "showOnlyRequested") }
    }

    @Published var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    enum AppearanceMode: String, CaseIterable, Sendable {
        case system
        case light
        case dark

        var title: String {
            switch self {
            case .system: "跟随系统"
            case .light: "浅色"
            case .dark: "深色"
            }
        }

        var nsAppearanceName: NSAppearance.Name? {
            switch self {
            case .system: nil
            case .light: .aqua
            case .dark: .darkAqua
            }
        }
    }

    @Published var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system {
        didSet {
            UserDefaults.standard.set(appearanceMode.rawValue, forKey: "appearanceMode")
            applyAppearance()
        }
    }

    private func applyAppearance() {
        if let name = appearanceMode.nsAppearanceName {
            NSApp.appearance = NSAppearance(named: name)
        } else {
            NSApp.appearance = nil
        }
    }

    @Published var kindFilter: PackageKind? = nil
    @Published var showPinnedOnly: Bool = false

    @Published var brewfileCheckResult: String?
    @Published var brewfileCheckOK: Bool?

    private var statusClearTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var didBootstrap = false

    var filteredInstalled: [Package] {
        installed.filter { pkg in
            if showOnlyRequested && pkg.kind == .formula && !pkg.installedOnRequest {
                return false
            }
            if let kindFilter, pkg.kind != kindFilter {
                return false
            }
            return true
        }
    }

    var selectedPackage: Package? {
        guard let selectedPackageID else { return nil }
        return installed.first { $0.id == selectedPackageID }
            ?? outdated.first { $0.id == selectedPackageID }
            ?? searchResults.first { $0.id == selectedPackageID }
    }

    var selectedService: BrewService? {
        guard let selectedServiceID else { return nil }
        return services.first { $0.id == selectedServiceID }
    }

    var runningServiceCount: Int {
        services.filter { $0.status == .started }.count
    }

    func dependents(of package: Package) -> [String] {
        guard package.kind == .formula else { return [] }
        return installed
            .filter { $0.kind == .formula && $0.dependencies.contains(package.name) }
            .map(\.name)
            .sorted()
    }

    var installedNameSet: Set<String> {
        Set(installed.map(\.name))
    }

    // MARK: - Lifecycle

    func bootstrap() async {
        guard !didBootstrap else { return }
        didBootstrap = true
        // 应用保存的外观设置
        applyAppearance()
        if notificationsEnabled {
            NotificationService.requestAuthorizationIfNeeded()
        }
        let path = customBrewPath.isEmpty ? nil : customBrewPath
        installation = await client.resolve(customPath: path)
        guard installation != nil else {
            didBootstrap = false
            return
        }
        await refreshAll()
    }

    func redetectBrew() async {
        let path = customBrewPath.isEmpty ? nil : customBrewPath
        installation = await client.refreshInstallation(customPath: path)
        if installation != nil {
            await refreshAll()
        }
    }

    // MARK: - Load

    func refreshAll() async {
        async let a: Void = loadInstalled()
        async let b: Void = loadOutdated()
        async let c: Void = loadServices()
        async let d: Void = loadTaps()
        _ = await (a, b, c, d)
    }

    func loadInstalled() async {
        guard installation != nil else { return }
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        do {
            installed = try await client.installedPackages()
            lastError = nil
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func loadOutdated() async {
        guard installation != nil else { return }
        isLoadingOutdated = true
        defer { isLoadingOutdated = false }
        do {
            outdated = try await client.outdatedPackages()
            lastError = nil
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func loadServices() async {
        guard installation != nil else { return }
        isLoadingServices = true
        defer { isLoadingServices = false }
        do {
            services = try await client.listServices()
            lastError = nil
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func loadTaps() async {
        guard installation != nil else { return }
        isLoadingTaps = true
        defer { isLoadingTaps = false }
        do {
            // Use nonisolated task to avoid actor deadlock
            let result = try await Task.detached { @Sendable in
                try await self.client.listTaps()
            }.value
            taps = result
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addTap(_ name: String) async {
        await runTask(kind: .tap, title: "添加 Tap \(name)") {
            try await self.client.addTap(name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadTaps()
        }
    }

    func removeTap(_ name: String) async {
        await runTask(kind: .tap, title: "删除 Tap \(name)") {
            try await self.client.removeTap(name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadTaps()
        }
    }

    func trustTap(_ name: String) async {
        await runTask(kind: .tap, title: "信任 Tap \(name)") {
            try await self.client.trustTap(name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadTaps()
        }
    }

    func untrustTap(_ name: String) async {
        await runTask(kind: .tap, title: "取消信任 Tap \(name)") {
            try await self.client.untrustTap(name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadTaps()
        }
    }

    func loadTapPackages(tapName: String) async {
        guard installation != nil else { return }
        isLoadingTapPackages = true
        defer { isLoadingTapPackages = false }
        do {
            let info = try await client.tapInfo(name: tapName)
            if let idx = taps.firstIndex(where: { $0.name == tapName }) {
                taps[idx].formulaNames = info.formulaNames
                taps[idx].caskNames = info.caskNames
                taps[idx].formulaCount = info.formulaCount
                taps[idx].caskCount = info.caskCount
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Lookup a single package by name for tap detail view.
    func lookupTapPackage(named name: String) async -> Package? {
        // Try installed first
        if let pkg = installed.first(where: { $0.name == name }) {
            return pkg
        }
        // Otherwise query brew info
        // Try formula first, then cask
        if let pkg = try? await client.info(name: name, kind: .formula) {
            return pkg
        }
        if let pkg = try? await client.info(name: name, kind: .cask) {
            return pkg
        }
        return nil
    }

    func runSearch() async {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { searchResults = []; return }
        isSearching = true
        defer { isSearching = false }
        do {
            searchResults = try await client.search(query: q)
            lastError = nil
            if searchResults.isEmpty {
                showStatus("未找到与「\(q)」匹配的软件包")
            }
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func scheduleSearch(delayNanoseconds: UInt64 = 450_000_000) {
        searchTask?.cancel()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { searchResults = []; return }
        guard q.count >= 2 else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            await runSearch()
        }
    }

    func runDoctor() async {
        guard installation != nil else { return }
        isLoadingDoctor = true
        defer { isLoadingDoctor = false }
        do {
            let result = try await client.doctor()
            doctorIssues = result.issues
            doctorRaw = result.raw
            doctorHealthy = result.isHealthy
            doctorRan = true
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    func loadCleanupPreview() async {
        guard installation != nil else { return }
        isLoadingCleanupPreview = true
        defer { isLoadingCleanupPreview = false }
        do {
            cleanupPreview = try await client.cleanupPreview()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func brewUpdate() async {
        await runTask(kind: .update, title: "更新 Homebrew") {
            try await self.client.update { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
        }
    }

    func upgrade(packages: [Package]) async {
        guard !packages.isEmpty else { return }
        let names = packages.map(\.name)
        let title = packages.count == 1 ? "升级 \(names[0])" : "升级 \(packages.count) 个软件包"
        await runTask(kind: .upgrade, title: title) {
            try await self.client.upgrade(names: names) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
        }
    }

    func upgradeAll() async { await upgrade(packages: outdated) }

    func install(_ package: Package) async {
        await runTask(kind: .install, title: "安装 \(package.name)") {
            try await self.client.install(name: package.name, kind: package.kind) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
            if let updated = try? await self.client.info(name: package.name, kind: package.kind) {
                self.patchSearchResult(updated)
            }
        }
    }

    func uninstall(_ package: Package) async {
        let title = "卸载 \(package.name)"
        await runTask(kind: .uninstall, title: title) {
            try await self.client.uninstall(name: package.name, kind: package.kind) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            if self.selectedPackageID == package.id { self.selectedPackageID = nil }
            await self.refreshAll()
        }
    }

    func pinPackage(_ package: Package) async {
        await runTask(kind: .pin, title: "固定 \(package.name)") {
            try await self.client.pin(name: package.name, kind: package.kind) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
            await self.refreshSelectedPackage(package)
        }
    }

    func unpinPackage(_ package: Package) async {
        await runTask(kind: .pin, title: "取消固定 \(package.name)") {
            try await self.client.unpin(name: package.name, kind: package.kind) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
            await self.refreshSelectedPackage(package)
        }
    }

    func selectInstalledPackage(named name: String) {
        if let pkg = installed.first(where: { $0.name == name }) {
            selectedSidebar = .installed
            selectedPackageID = pkg.id
            return
        }
        selectedSidebar = .search
        searchQuery = name
        Task { await runSearch() }
    }

    func setSelectedPackageID(_ id: Package.ID?) {
        selectedPackageID = id
    }

    func runCleanup() async {
        await runTask(kind: .cleanup, title: "brew cleanup") {
            try await self.client.cleanup(scrub: true) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadCleanupPreview()
        }
    }

    func startService(_ service: BrewService) async {
        await runTask(kind: .service, title: "启动 \(service.name)") {
            try await self.client.startService(service.name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadServices()
        }
    }

    func stopService(_ service: BrewService) async {
        await runTask(kind: .service, title: "停止 \(service.name)") {
            try await self.client.stopService(service.name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadServices()
        }
    }

    func restartService(_ service: BrewService) async {
        await runTask(kind: .service, title: "重启 \(service.name)") {
            try await self.client.restartService(service.name) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.loadServices()
        }
    }

    // MARK: - Brewfile

    func exportBrewfile(to fileURL: URL) async {
        await runTask(kind: .bundle, title: "导出 Brewfile") {
            try await self.client.dumpBrewfile(to: fileURL) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
        }
    }

    func exportBrewfileInteractively() {
        selectedSidebar = .maintenance
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.title = "导出 Brewfile"
        panel.nameFieldStringValue = "Brewfile"
        panel.allowedContentTypes = [UTType.plainText, UTType.data]
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self.exportBrewfile(to: url) }
        }
    }

    func importBrewfile(from fileURL: URL) async {
        await runTask(kind: .bundle, title: "安装 Brewfile") {
            try await self.client.installBrewfile(from: fileURL) { chunk in
                Task { @MainActor in self.appendLog(chunk) }
            }
            await self.refreshAll()
        }
    }

    func checkBrewfile(from fileURL: URL) async {
        guard installation != nil else { return }
        do {
            let result = try await client.checkBrewfile(from: fileURL)
            brewfileCheckOK = result.ok
            brewfileCheckResult = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            showStatus(result.ok ? "Brewfile 检查通过" : "Brewfile 存在未安装依赖")
            lastError = nil
        } catch {
            brewfileCheckOK = false
            brewfileCheckResult = error.localizedDescription
            lastError = error.localizedDescription
        }
    }

    func openMainWindow(sidebar: SidebarItem? = nil) {
        if let sidebar { selectedSidebar = sidebar }
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func cancelTask() {
        Task { await client.cancel() }
    }

    func clearLog() {
        logText = ""
    }

    // MARK: - Private

    private func runTask(kind: TaskKind, title: String, work: @escaping () async throws -> Void) async {
        guard !isTaskRunning else {
            lastError = BrewError.busy.localizedDescription
            return
        }
        isTaskRunning = true
        currentTaskTitle = title
        isLogExpanded = true
        appendLog("\n—— \(title) ——\n")
        lastError = nil
        lastStatus = nil
        defer {
            isTaskRunning = false
            currentTaskTitle = nil
        }
        do {
            try await work()
            appendLog("\n✓ 完成：\(title)\n")
            showStatus("完成：\(title)")
            notifyIfNeeded(title: "BrewDesk", body: "完成：\(title)", success: true)
        } catch is CancellationError {
            appendLog("\n✗ 已取消\n")
        } catch let error as BrewError {
            if case .cancelled = error {
                appendLog("\n✗ 已取消\n")
            } else {
                lastError = error.localizedDescription
                appendLog("\n✗ 失败：\(error.localizedDescription)\n")
                notifyIfNeeded(title: "BrewDesk 失败", body: title, success: false)
            }
        } catch {
            lastError = error.localizedDescription
            appendLog("\n✗ 失败：\(error.localizedDescription)\n")
            notifyIfNeeded(title: "BrewDesk 失败", body: title, success: false)
        }
        _ = kind
    }

    private func showStatus(_ message: String) {
        lastStatus = message
        statusClearTask?.cancel()
        statusClearTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            if lastStatus == message { lastStatus = nil }
        }
    }

    private func notifyIfNeeded(title: String, body: String, success: Bool) {
        guard notificationsEnabled else { return }
        NotificationService.post(title: title, body: body, success: success)
    }

    private func appendLog(_ chunk: String) {
        logText.append(chunk)
        if logText.count > 200_000 { logText = String(logText.suffix(150_000)) }
    }

    private func patchSearchResult(_ package: Package) {
        if let idx = searchResults.firstIndex(where: { $0.id == package.id }) {
            searchResults[idx] = package
        }
    }

    private func refreshSelectedPackage(_ package: Package) async {
        if let updated = try? await client.info(name: package.name, kind: package.kind) {
            patchSearchResult(updated)
            if selectedPackageID == package.id { selectedPackageID = updated.id }
        }
    }
}

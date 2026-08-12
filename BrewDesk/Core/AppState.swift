//
//  AppState.swift
//  BrewDesk
//

import AppKit
import Foundation
import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable, Hashable {
    case home
    case installed
    case outdated
    case taps
    case services
    case maintenance
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "主页"
        case .installed: "已安装"
        case .outdated: "可更新"
        case .taps: "Taps"
        case .services: "服务"
        case .maintenance: "维护"
        case .settings: "设置"
        }
    }

    var systemImage: String {
        switch self {
        case .home: "house"
        case .installed: "shippingbox"
        case .outdated: "arrow.triangle.2.circlepath"
        case .taps: "square.grid.2x2"
        case .services: "bolt.horizontal.circle"
        case .maintenance: "stethoscope"
        case .settings: "gearshape"
        }
    }

    /// Filled variant for sidebar icon display.
    var filledImage: String {
        switch self {
        case .home: "house.fill"
        case .installed: "shippingbox.fill"
        case .outdated: "arrow.triangle.2.circlepath"
        case .taps: "square.grid.2x2"
        case .services: "bolt.horizontal.circle.fill"
        case .maintenance: "stethoscope"
        case .settings: "gearshape.fill"
        }
    }
}

enum TaskKind: String, Sendable {
    case refresh, update, upgrade, install, uninstall, search
    case cleanup, service, tap, bundle, pin

    var title: String {
        switch self {
        case .refresh: "刷新"
        case .update: "更新 Homebrew"
        case .upgrade: "升级"
        case .install: "安装"
        case .uninstall: "卸载"
        case .search: "搜索"
        case .cleanup: "清理"
        case .service: "服务"
        case .tap: "Tap"
        case .bundle: "Brewfile"
        case .pin: "固定版本"
        }
    }
}

@MainActor
@Observable
final class AppState {
    let client = BrewClient()

    var installation: BrewInstallation?
    var selectedSidebar: SidebarItem = .home
    var selectedPackageID: Package.ID?
    var selectedServiceID: BrewService.ID?

    var installed: [Package] = []
    var outdated: [Package] = []
    /// 全部可安装包目录（轻量：名称 + 类型 + 已安装状态合并），详情按需加载
    var catalog: [Package] = []
    /// 主页详情缓存：按包 id 缓存拉取到的完整信息
    var catalogDetailCache: [Package.ID: Package] = [:]
    var searchResults: [Package] = []
    var searchQuery: String = ""
    /// 是否处于搜索结果视图（由主页搜索框激活）
    var isSearchActive = false
    var services: [BrewService] = []
    var taps: [BrewTap] = []
    var selectedTapID: String?

    var cleanupPreview: CleanupPreview?

    var isLoadingInstalled = false
    var isLoadingOutdated = false
    var isLoadingCatalog = false
    var isSearching = false
    var isLoadingServices = false
    var isLoadingTaps = false
    var isLoadingTapPackages = false
    var isLoadingCleanupPreview = false

    var isTaskRunning = false
    var currentTaskTitle: String?

    var lastError: String?
    var lastStatus: String?

    var customBrewPath: String = UserDefaults.standard.string(forKey: "customBrewPath") ?? "" {
        didSet { UserDefaults.standard.set(customBrewPath, forKey: "customBrewPath") }
    }

    var showOnlyRequested: Bool = UserDefaults.standard.object(forKey: "showOnlyRequested") as? Bool ?? true {
        didSet {
            UserDefaults.standard.set(showOnlyRequested, forKey: "showOnlyRequested")
            rebuildFilteredInstalled()
        }
    }

    var notificationsEnabled: Bool = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    var autoCheckForUpdates: Bool = UserDefaults.standard.object(forKey: "autoCheckForUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoCheckForUpdates, forKey: "autoCheckForUpdates") }
    }

    var autoDownloadUpdates: Bool = UserDefaults.standard.object(forKey: "autoDownloadUpdates") as? Bool ?? true {
        didSet { UserDefaults.standard.set(autoDownloadUpdates, forKey: "autoDownloadUpdates") }
    }

    /// Sparkle 更新控制器（懒加载，由 BrewDeskApp 在启动后设置）
    var updater: UpdaterController?

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

    var appearanceMode: AppearanceMode = AppearanceMode(rawValue: UserDefaults.standard.string(forKey: "appearanceMode") ?? "") ?? .system {
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

    var kindFilter: PackageKind? = nil {
        didSet { rebuildFilteredInstalled() }
    }

    /// 主页目录过滤状态（提升到 AppState，便于集中做派生数据缓存）
    var homeKindFilter: PackageKind? = nil {
        didSet { scheduleCatalogDerivedRebuild() }
    }

    /// 主页目录派生数据缓存：避免视图每帧对整个目录做全量过滤/统计
    private(set) var homeFilteredCatalog: [Package] = []
    /// 目录 A-Z 分组缓存（非字母开头归 "#"），与 homeFilteredCatalog 同源同步更新
    private(set) var homeCatalogSections: [CatalogSection] = []
    private(set) var homeCatalogIndex: [Package.ID: Int] = [:]
    private(set) var homeIndexLetters: [String] = []
    private(set) var catalogInstalledCount = 0
    private(set) var catalogFormulaCount = 0
    private(set) var catalogCaskCount = 0

    var brewfileCheckResult: String?
    var brewfileCheckOK: Bool?

    private var statusClearTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?
    private var didBootstrap = false
    private var lastInstalledCaskTokens: Set<String>?
    /// 各数据集在途加载任务：合并并发请求，避免重复拉起 brew 子进程。
    private var installedLoadTask: Task<Void, Never>?
    private var installedLoadToken: UUID?
    private var outdatedLoadTask: Task<Void, Never>?
    private var outdatedLoadToken: UUID?
    private var catalogLoadTask: Task<Void, Never>?
    private var catalogLoadToken: UUID?
    private var servicesLoadTask: Task<Void, Never>?
    private var servicesLoadToken: UUID?
    private var tapsLoadTask: Task<Void, Never>?
    private var tapsLoadToken: UUID?
    private var cleanupPreviewLoadTask: Task<Void, Never>?
    private var cleanupPreviewLoadToken: UUID?

    /// 主页详情缓存上限：防止浏览目录时无界累积完整信息（LRU 淘汰）
    private static let maxCatalogDetailCacheSize = 200
    private var catalogDetailOrder: [Package.ID] = []

    /// 已安装列表过滤结果缓存：installed / showOnlyRequested / kindFilter 变化时重建，
    /// 避免视图每次 body 求值对已安装列表做全量过滤（仿 homeFilteredCatalog 模式）。
    private(set) var filteredInstalled: [Package] = []
    /// 过滤结果版本号：仅过滤结果内容实际变化时 +1（列表 .id 用，
    /// 已安装数据变化与筛选条件变化都折叠进来）。
    private(set) var installedFilterStamp = 0

    private func rebuildFilteredInstalled() {
        let base = installed.filter { pkg in
            if showOnlyRequested && pkg.kind == .formula && !pkg.installedOnRequest {
                return false
            }
            if let kindFilter, pkg.kind != kindFilter {
                return false
            }
            return true
        }
        if base != filteredInstalled {
            filteredInstalled = base
            installedFilterStamp += 1
        }
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
        return (dependentsIndex[package.name] ?? []).sorted()
    }

    /// 已安装包名集合（在 loadInstalled 时一次性构建，避免视图反复创建）
    private(set) var installedNameSet: Set<String> = []

    /// 依赖反转索引：依赖名 → 依赖它的已安装 formula 名（loadInstalled 时重建，
    /// 避免 dependents(of:) 在 5 个视图 body 里反复做 O(已装数 × 依赖数) 扫描）
    private var dependentsIndex: [String: [String]] = [:]

    private func rebuildDependentsIndex() {
        var index: [String: [String]] = [:]
        for pkg in installed where pkg.kind == .formula {
            for dep in pkg.dependencies {
                index[dep, default: []].append(pkg.name)
            }
        }
        dependentsIndex = index
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
        // 启动只加载核心数据；Taps 等到首次进入页面时再懒加载
        await refreshCore()
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
        cancelPendingLoads()
        async let a: Void = loadInstalled()
        async let b: Void = loadOutdated()
        async let c: Void = loadServices()
        async let d: Void = loadTaps()
        async let e: Void = loadCatalog()
        _ = await (a, b, c, d, e)
    }

    /// 启动 / 首次进入所需的核心数据（不含 Taps，Taps 按需懒加载）
    func refreshCore() async {
        async let a: Void = loadInstalled()
        async let b: Void = loadOutdated()
        async let c: Void = loadServices()
        async let d: Void = loadCatalog()
        _ = await (a, b, c, d)
    }

    /// 安装/卸载/升级等变更后只需刷新受影响的数据，避免重载整个目录
    func refreshLists() async {
        cancelPendingLoads()
        async let a: Void = loadInstalled()
        async let b: Void = loadOutdated()
        async let c: Void = loadServices()
        _ = await (a, b, c)
    }

    // MARK: - 数据免重载（页面切换流畅度）

    /// 数据新鲜度阈值：超过该时长后，下次进入页面才重新拉取（秒）。
    static let dataStalenessInterval: TimeInterval = 300

    /// 各数据集最后成功加载时间；.distantPast 表示本会话尚未加载。
    private(set) var installedLoadedAt = Date.distantPast
    private(set) var outdatedLoadedAt = Date.distantPast
    private(set) var servicesLoadedAt = Date.distantPast
    private(set) var tapsLoadedAt = Date.distantPast
    private(set) var catalogLoadedAt = Date.distantPast
    private(set) var cleanupPreviewLoadedAt = Date.distantPast

    private func isStale(_ loadedAt: Date) -> Bool {
        Date().timeIntervalSince(loadedAt) > Self.dataStalenessInterval
    }

    func loadInstalledIfNeeded() async {
        guard isStale(installedLoadedAt) else { return }
        await loadInstalled()
    }

    func loadOutdatedIfNeeded() async {
        guard isStale(outdatedLoadedAt) else { return }
        await loadOutdated()
    }

    func loadServicesIfNeeded() async {
        guard isStale(servicesLoadedAt) else { return }
        await loadServices()
    }

    func loadTapsIfNeeded() async {
        guard isStale(tapsLoadedAt) else { return }
        await loadTaps()
    }

    func loadCatalogIfNeeded() async {
        guard isStale(catalogLoadedAt) else { return }
        await loadCatalog()
    }

    func loadCleanupPreviewIfNeeded() async {
        guard isStale(cleanupPreviewLoadedAt) else { return }
        await loadCleanupPreview()
    }

    func loadInstalled() async {
        guard installation != nil else { return }
        if let running = installedLoadTask {
            await running.value
            return
        }
        let token = UUID()
        installedLoadToken = token
        let task = Task { await self.performLoadInstalled() }
        installedLoadTask = task
        await task.value
        if installedLoadToken == token { installedLoadTask = nil }
    }

    private func performLoadInstalled() async {
        isLoadingInstalled = true
        defer { isLoadingInstalled = false }
        do {
            let newInstalled = try await client.installedPackages()
            installedGen += 1
            // 仅内容实际变化时发布：无变化刷新不重建列表、不刷新依赖视图。
            if newInstalled != installed {
                installed = newInstalled
                installedNameSet = Set(installed.map(\.name))
                rebuildDependentsIndex()
                // 安装状态可能已变化：仅当已安装 cask 集合真的变化时才清理图标缓存，
                // 且只清除已卸载的 token——仍安装的 cask 图标/路径/miss 全部保留，
                // 避免装一个 cask 后刷新就重扫磁盘并重绘全部图标。
                let caskTokens = Set(installed.filter { $0.kind == .cask }.map(\.name))
                if caskTokens != lastInstalledCaskTokens {
                    CaskIconCache.shared.invalidate(keeping: caskTokens)
                    lastInstalledCaskTokens = caskTokens
                }
            }
            setOutdated(Self.enrichOutdated(outdated, with: installed))
            rebuildFilteredInstalled()
            enrichCatalogWithInstalledInfo()
            lastError = nil
            installedLoadedAt = Date()
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func loadOutdated() async {
        guard installation != nil else { return }
        if let running = outdatedLoadTask {
            await running.value
            return
        }
        let token = UUID()
        outdatedLoadToken = token
        let task = Task { await self.performLoadOutdated() }
        outdatedLoadTask = task
        await task.value
        if outdatedLoadToken == token { outdatedLoadTask = nil }
    }

    private func performLoadOutdated() async {
        isLoadingOutdated = true
        defer { isLoadingOutdated = false }
        do {
            let result = try await client.outdatedPackages()
            outdatedGen += 1
            setOutdated(Self.enrichOutdated(result, with: installed))
            enrichCatalogWithInstalledInfo()
            lastError = nil
            outdatedLoadedAt = Date()
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    /// 加载全部可安装包目录（名称 + 类型），毫秒级完成。
    func loadCatalog() async {
        guard installation != nil else { return }
        if let running = catalogLoadTask {
            await running.value
            return
        }
        let token = UUID()
        catalogLoadToken = token
        let task = Task { await self.performLoadCatalog() }
        catalogLoadTask = task
        await task.value
        if catalogLoadToken == token { catalogLoadTask = nil }
    }

    private func performLoadCatalog() async {
        isLoadingCatalog = true
        defer { isLoadingCatalog = false }
        do {
            let names = try await client.allPackageNames()
            var result: [Package] = []
            result.reserveCapacity(names.formulae.count + names.casks.count)
            for name in names.formulae {
                result.append(
                    Package(
                        name: name,
                        kind: .formula,
                        isInstalled: false,
                        isOutdated: false,
                        isPinned: false,
                        dependencies: [],
                        installedOnRequest: false
                    )
                )
            }
            for name in names.casks {
                result.append(
                    Package(
                        name: name,
                        kind: .cask,
                        isInstalled: false,
                        isOutdated: false,
                        isPinned: false,
                        dependencies: [],
                        installedOnRequest: false
                    )
                )
            }
            catalog = result.sorted {
                $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            catalogGen += 1
            enrichCatalogWithInstalledInfo()
            lastError = nil
            catalogLoadedAt = Date()
            // 名称目录先渲染；随后后台拉取全量 info 补齐版本/描述等字段，
            // 让目录行默认完整展示（无需点击详情后才回填）。
            enrichCatalogFullInfoInBackground()
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    /// 后台富化目录行字段：一次 `brew info --json=v2`（无参数即全量）取回全部包的
    /// 极简信息，按 id（kind:name）只合并 desc/最新版本两个字段，保持排序与结构。
    /// 详情（依赖/caveats/analytics 等）由 catalogDetail(for:) 按需拉取并 LRU 缓存，
    /// 目录本身不持有——1.6 万行若存完整 Package 会吃掉数百 MB 内存。
    /// brew 调用在 BrewClient actor 上执行（含 JSON 解码），主线程只做轻量合并。
    private func enrichCatalogFullInfoInBackground() {
        Task { [weak self] in
            guard let self else { return }
            guard let rows = try? await self.client.catalogRows() else { return }
            let byId = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            var newCatalog = self.catalog
            var changed = false
            for idx in newCatalog.indices {
                guard let row = byId[newCatalog[idx].id] else { continue }
                var pkg = newCatalog[idx]
                var dirty = false
                if row.desc != pkg.desc {
                    pkg.desc = row.desc
                    dirty = true
                }
                if row.latestVersion != pkg.latestVersion {
                    pkg.latestVersion = row.latestVersion
                    dirty = true
                }
                if dirty {
                    newCatalog[idx] = pkg
                    changed = true
                }
            }
            if changed {
                self.catalog = newCatalog
                self.catalogGen += 1
                // 用已安装数据重新叠加安装状态（快照中的安装字段以本机当前数据为准）
                self.enrichCatalogWithInstalledInfo()
            }
            // 全量 dump 的 JSON 缓冲区（约 50MB）与解码临时对象已释放，但 malloc 默认
            // 不把空闲页归还 OS，显式让出，避免 RSS 长期停留在解码峰值。
            malloc_zone_pressure_relief(malloc_default_zone(), 0)
        }
    }

    /// 目录/已安装/可更新三份数据的版本号：enrich 按元组去重，
    /// 避免 loadInstalled 与 loadOutdated 各触发一次全目录遍历。
    private var installedGen = 0
    private var outdatedGen = 0
    private var catalogGen = 0
    private var lastEnrichGens: (Int, Int, Int)?

    // MARK: - 列表内容版本号（用作列表 .id 的轻量 stamp）

    /// 列表内容版本号：仅在对应数据内容实际变化时 +1。
    /// 用作各列表 `.id(stamp)` 的轻量标识，替代 `.id(整个数组)`
    /// （每次 body 求值 O(n) 哈希 + 无内容变化的发布也触发全表重建）。
    private(set) var outdatedStamp = 0
    private(set) var searchStamp = 0
    private(set) var servicesStamp = 0
    /// 主页目录过滤结果版本号：仅在实际内容变化时 +1（重建写回与详情同步时）。
    private(set) var homeCatalogListStamp = 0

    /// 用已安装/可更新列表补全目录的安装状态与版本信息。
    private func enrichCatalogWithInstalledInfo() {
        // 版本元组必须在最顶部记录（含下方 installed 为空的早退分支），
        // 否则同一版本内的后续调用会误跳过「清空安装标记」的路径。
        let gens = (installedGen, outdatedGen, catalogGen)
        if let last = lastEnrichGens, last == gens { return }
        lastEnrichGens = gens

        guard !installed.isEmpty else {
            // 没有任何已安装包时，清掉目录中的安装/更新标记
            if catalog.contains(where: \.isInstalled) {
                catalog = catalog.map { pkg in
                    var copy = pkg
                    copy.isInstalled = false
                    copy.isOutdated = false
                    copy.isPinned = false
                    return copy
                }
            }
            scheduleCatalogDerivedRebuild()
            return
        }
        let installedByToken = Dictionary(
            installed.map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let outdatedTokens = Set(outdated.map(\.name))
        var newCatalog = catalog
        var changed = false
        for idx in newCatalog.indices {
            let pkg = newCatalog[idx]
            guard let inst = installedByToken[pkg.name], inst.kind == pkg.kind else { continue }
            var copy = pkg
            copy.isInstalled = true
            copy.isOutdated = outdatedTokens.contains(pkg.name)
            copy.isPinned = inst.isPinned
            copy.version = inst.version
            copy.latestVersion = inst.latestVersion
            copy.desc = inst.desc
            copy.homepage = inst.homepage
            copy.dependencies = inst.dependencies
            copy.installedTime = inst.installedTime
            copy.installedOnRequest = inst.installedOnRequest
            copy.caskArtifacts = inst.caskArtifacts
            copy.caskDisplayNames = inst.caskDisplayNames
            if copy != pkg {
                newCatalog[idx] = copy
                changed = true
            }
        }
        if changed {
            catalog = newCatalog
        }
        scheduleCatalogDerivedRebuild()
    }

    /// 主页详情：优先缓存，未命中时拉取完整信息并缓存。
    func catalogDetail(for package: Package) async -> Package {
        if let cached = catalogDetailCache[package.id] {
            return cached
        }
        do {
            if let full = try await client.info(name: package.name, kind: package.kind) {
                storeCatalogDetail(full)
                syncCatalogEntry(full)
                return full
            }
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
        return package
    }

    /// outdated 列表来自 `brew outdated --json`，不含 cask 的 artifacts 信息；
    /// 用已安装列表中的权威 app 信息补全，保证“可更新”页也能显示真实图标。
    /// 纯函数形式：先计算完整结果，再按内容差异写回（无变化不发布、不重建列表）。
    nonisolated static func enrichOutdated(
        _ outdated: [Package], with installed: [Package]
    ) -> [Package] {
        guard !installed.isEmpty, !outdated.isEmpty else { return outdated }

        let installedByToken = Dictionary(
            installed
                .filter { $0.kind == .cask && (!$0.caskArtifacts.isEmpty || !$0.caskDisplayNames.isEmpty) }
                .map { ($0.name, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        guard !installedByToken.isEmpty else { return outdated }

        return outdated.map { pkg in
            guard let installedPkg = installedByToken[pkg.name] else { return pkg }
            var copy = pkg
            copy.caskArtifacts = installedPkg.caskArtifacts
            copy.caskDisplayNames = installedPkg.caskDisplayNames
            return copy
        }
    }

    /// 写回 outdated，仅内容实际变化时发布并递增列表 stamp。
    private func setOutdated(_ newValue: [Package]) {
        if newValue != outdated {
            outdated = newValue
            outdatedStamp += 1
        }
    }

    func loadServices() async {
        guard installation != nil else { return }
        if let running = servicesLoadTask {
            await running.value
            return
        }
        let token = UUID()
        servicesLoadToken = token
        let task = Task { await self.performLoadServices() }
        servicesLoadTask = task
        await task.value
        if servicesLoadToken == token { servicesLoadTask = nil }
    }

    private func performLoadServices() async {
        isLoadingServices = true
        defer { isLoadingServices = false }
        do {
            let result = try await client.listServices()
            if result != services {
                services = result
                servicesStamp += 1
            }
            lastError = nil
            servicesLoadedAt = Date()
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    func loadTaps() async {
        guard installation != nil else { return }
        if let running = tapsLoadTask {
            await running.value
            return
        }
        let token = UUID()
        tapsLoadToken = token
        let task = Task { await self.performLoadTaps() }
        tapsLoadTask = task
        await task.value
        if tapsLoadToken == token { tapsLoadTask = nil }
    }

    private func performLoadTaps() async {
        isLoadingTaps = true
        defer { isLoadingTaps = false }
        do {
            // Use nonisolated task to avoid actor deadlock
            let result = try await Task.detached { @Sendable in
                try await self.client.listTaps()
            }.value
            taps = result
            lastError = nil
            tapsLoadedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func addTap(_ name: String) async {
        await runTask(kind: .tap, title: "添加 Tap \(name)") {
            try await self.client.addTap(name) { _ in }
            await self.loadTaps()
        }
    }

    func removeTap(_ name: String) async {
        await runTask(kind: .tap, title: "删除 Tap \(name)") {
            try await self.client.removeTap(name) { _ in }
            await self.loadTaps()
        }
    }

    func trustTap(_ name: String) async {
        await runTask(kind: .tap, title: "信任 Tap \(name)") {
            try await self.client.trustTap(name) { _ in }
            await self.loadTaps()
        }
    }

    func untrustTap(_ name: String) async {
        await runTask(kind: .tap, title: "取消信任 Tap \(name)") {
            try await self.client.untrustTap(name) { _ in }
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
            let result = try await client.search(query: q)
            if result != searchResults {
                searchResults = result
                searchStamp += 1
            }
            lastError = nil
            if searchResults.isEmpty {
                showStatus("未找到与「\(q)」匹配的软件包")
            }
        } catch is CancellationError {} catch {
            lastError = error.localizedDescription
        }
    }

    /// 从主页搜索框进入搜索结果视图。
    func openSearch(query: String) {
        searchTask?.cancel()
        searchQuery = query
        isSearchActive = true
        selectedSidebar = .home
        searchTask = Task { await runSearch() }
    }

    /// 退出搜索结果视图，返回主页。
    func deactivateSearch() {
        searchTask?.cancel()
        isSearchActive = false
        searchQuery = ""
        if !searchResults.isEmpty {
            searchResults = []
            searchStamp += 1
        }
    }

    /// 搜索防抖：输入停止 450ms 后执行搜索。
    /// - Parameter activateSearchView: 主页搜索框传 true——防抖结束后激活搜索结果视图再搜索；
    ///   搜索结果页自身的输入框传 false（视图已激活，只执行搜索）。
    func scheduleSearch(delayNanoseconds: UInt64 = 450_000_000, activateSearchView: Bool = false) {
        searchTask?.cancel()
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else {
            // 清空输入：清空结果并递增 stamp 触发列表重建——若行数变化而不重建，
            // List 会持有失效的滚动目标（macOS 26 回映断言崩溃，见 InstalledView 注释）。
            if !activateSearchView && !searchResults.isEmpty {
                searchResults = []
                searchStamp += 1
            }
            return
        }
        guard q.count >= 2 else { return }
        searchTask = Task {
            try? await Task.sleep(nanoseconds: delayNanoseconds)
            guard !Task.isCancelled else { return }
            if activateSearchView { isSearchActive = true }
            await runSearch()
        }
    }

    func loadCleanupPreview() async {
        guard installation != nil else { return }
        if let running = cleanupPreviewLoadTask {
            await running.value
            return
        }
        let token = UUID()
        cleanupPreviewLoadToken = token
        let task = Task { await self.performLoadCleanupPreview() }
        cleanupPreviewLoadTask = task
        await task.value
        if cleanupPreviewLoadToken == token { cleanupPreviewLoadTask = nil }
    }

    private func performLoadCleanupPreview() async {
        isLoadingCleanupPreview = true
        defer { isLoadingCleanupPreview = false }
        do {
            cleanupPreview = try await client.cleanupPreview()
            lastError = nil
            cleanupPreviewLoadedAt = Date()
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Actions

    func brewUpdate() async {
        await runTask(kind: .update, title: "更新 Homebrew") {
            try await self.client.update { _ in }
            await self.refreshAll()
        }
    }

    func upgrade(packages: [Package]) async {
        guard !packages.isEmpty else { return }
        let names = packages.map(\.name)
        let title = packages.count == 1 ? "升级 \(names[0])" : "升级 \(packages.count) 个软件包"
        await runTask(kind: .upgrade, title: title) {
            try await self.client.upgrade(names: names) { _ in }
            await self.refreshLists()
        }
    }

    func upgradeAll() async { await upgrade(packages: outdated) }

    func install(_ package: Package) async {
        await runTask(kind: .install, title: "安装 \(package.name)") {
            try await self.client.install(name: package.name, kind: package.kind) { _ in }
            await self.refreshLists()
            if let updated = try? await self.client.info(name: package.name, kind: package.kind) {
                self.patchSearchResult(updated)
            }
        }
    }

    func uninstall(_ package: Package) async {
        let title = "卸载 \(package.name)"
        await runTask(kind: .uninstall, title: title) {
            try await self.client.uninstall(name: package.name, kind: package.kind) { _ in }
            if self.selectedPackageID == package.id { self.selectedPackageID = nil }
            await self.refreshLists()
        }
    }

    func pinPackage(_ package: Package) async {
        await runTask(kind: .pin, title: "固定 \(package.name)") {
            try await self.client.pin(name: package.name, kind: package.kind) { _ in }
            await self.refreshLists()
            await self.refreshSelectedPackage(package)
        }
    }

    func unpinPackage(_ package: Package) async {
        await runTask(kind: .pin, title: "取消固定 \(package.name)") {
            try await self.client.unpin(name: package.name, kind: package.kind) { _ in }
            await self.refreshLists()
            await self.refreshSelectedPackage(package)
        }
    }

    func selectInstalledPackage(named name: String) {
        if let pkg = installed.first(where: { $0.name == name }) {
            selectedSidebar = .installed
            selectedPackageID = pkg.id
            return
        }
        openSearch(query: name)
    }

    func setSelectedPackageID(_ id: Package.ID?) {
        selectedPackageID = id
    }

    func runCleanup() async {
        await runTask(kind: .cleanup, title: "清理缓存") {
            try await self.client.cleanup(scrub: true) { _ in }
            await self.loadCleanupPreview()
        }
    }

    func startService(_ service: BrewService) async {
        await runTask(kind: .service, title: "启动 \(service.name)") {
            try await self.client.startService(service.name) { _ in }
            await self.loadServices()
        }
    }

    func stopService(_ service: BrewService) async {
        await runTask(kind: .service, title: "停止 \(service.name)") {
            try await self.client.stopService(service.name) { _ in }
            await self.loadServices()
        }
    }

    func restartService(_ service: BrewService) async {
        await runTask(kind: .service, title: "重启 \(service.name)") {
            try await self.client.restartService(service.name) { _ in }
            await self.loadServices()
        }
    }

    // MARK: - Brewfile

    func exportBrewfile(to fileURL: URL) async {
        await runTask(kind: .bundle, title: "导出 Brewfile") {
            try await self.client.dumpBrewfile(to: fileURL) { _ in }
        }
    }

    func importBrewfile(from fileURL: URL) async {
        await runTask(kind: .bundle, title: "安装 Brewfile") {
            try await self.client.installBrewfile(from: fileURL) { _ in }
            await self.refreshLists()
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

    /// 取消在途的「可更新」加载任务（列表为空且加载中时允许手动取消）。
    func cancelOutdatedLoading() {
        outdatedLoadTask?.cancel()
        outdatedLoadTask = nil
        outdatedLoadToken = nil
    }

    // MARK: - Private

    private func runTask(kind: TaskKind, title: String, work: @escaping () async throws -> Void) async {
        guard !isTaskRunning else {
            lastError = BrewError.busy.localizedDescription
            return
        }
        isTaskRunning = true
        currentTaskTitle = title
        lastError = nil
        lastStatus = nil
        defer {
            isTaskRunning = false
            currentTaskTitle = nil
        }
        do {
            try await work()
            showStatus("完成：\(title)")
            notifyIfNeeded(title: "BrewDesk", body: "完成：\(title)", success: true)
        } catch is CancellationError {
        } catch let error as BrewError {
            if case .cancelled = error {
            } else {
                lastError = error.localizedDescription
                notifyIfNeeded(title: "BrewDesk 失败", body: title, success: false)
            }
        } catch {
            lastError = error.localizedDescription
            notifyIfNeeded(title: "BrewDesk 失败", body: title, success: false)
        }
        _ = kind
    }

    /// 取消并清空所有在途加载任务（刷新前调用，避免旧任务把过期数据写回）。
    private func cancelPendingLoads() {
        installedLoadTask?.cancel()
        installedLoadTask = nil
        installedLoadToken = nil
        outdatedLoadTask?.cancel()
        outdatedLoadTask = nil
        outdatedLoadToken = nil
        catalogLoadTask?.cancel()
        catalogLoadTask = nil
        catalogLoadToken = nil
        servicesLoadTask?.cancel()
        servicesLoadTask = nil
        servicesLoadToken = nil
        tapsLoadTask?.cancel()
        tapsLoadTask = nil
        tapsLoadToken = nil
        cleanupPreviewLoadTask?.cancel()
        cleanupPreviewLoadTask = nil
        cleanupPreviewLoadToken = nil
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

    private func patchSearchResult(_ package: Package) {
        if let idx = searchResults.firstIndex(where: { $0.id == package.id }) {
            searchResults[idx] = package
        }
        storeCatalogDetail(package)
        syncCatalogEntry(package)
    }

    private func refreshSelectedPackage(_ package: Package) async {
        if let updated = try? await client.info(name: package.name, kind: package.kind) {
            patchSearchResult(updated)
            if selectedPackageID == package.id { selectedPackageID = updated.id }
        }
    }

    // MARK: - 派生数据缓存

    /// 目录级派生数据：统计 + 过滤结果 + 字母索引 + 选中索引。
    /// 计算移出主线程（目录 ~14000 项，全量遍历 + 14k 键字典构建），
    /// 用 generation 计数丢弃过期结果，主线程只做一次性写回。
    private var derivedGeneration = 0

    private func scheduleCatalogDerivedRebuild() {
        derivedGeneration += 1
        let generation = derivedGeneration
        let snapshot = catalog // COW：仅 retain，零拷贝
        let kindFilter = homeKindFilter

        Task.detached {
            let result = AppState.computeCatalogDerivedData(
                catalog: snapshot, kindFilter: kindFilter
            )
            await MainActor.run {
                guard self.derivedGeneration == generation else { return }
                // 过滤结果无变化时跳过写回：不发布、不重建列表。
                // 统计基于完整目录（可能与过滤结果不同步变化），独立按值写回。
                if result.filtered != self.homeFilteredCatalog {
                    self.homeFilteredCatalog = result.filtered
                    self.homeCatalogSections = result.sections
                    self.homeCatalogIndex = result.index
                    self.homeIndexLetters = result.letters
                    self.homeCatalogListStamp += 1
                }
                if result.installedCount != self.catalogInstalledCount {
                    self.catalogInstalledCount = result.installedCount
                }
                if result.formulaCount != self.catalogFormulaCount {
                    self.catalogFormulaCount = result.formulaCount
                }
                if result.caskCount != self.catalogCaskCount {
                    self.catalogCaskCount = result.caskCount
                }
            }
        }
    }

    /// 纯函数：目录派生数据计算（nonisolated，可在任意执行器运行）。
    nonisolated static func computeCatalogDerivedData(
        catalog: [Package], kindFilter: PackageKind?
    ) -> CatalogDerivedData {
        // 统计（基于完整目录，与历史语义一致）
        var installedCount = 0
        var formulaCount = 0
        for pkg in catalog {
            if pkg.kind == .formula { formulaCount += 1 }
            if pkg.isInstalled { installedCount += 1 }
        }

        // 过滤 + 字母索引 + O(1) 选中查找
        let filtered = kindFilter.map { kind in
            catalog.filter { $0.kind == kind }
        } ?? catalog

        var index: [Package.ID: Int] = [:]
        index.reserveCapacity(filtered.count)
        for (i, pkg) in filtered.enumerated() {
            index[pkg.id] = i
        }

        var letters = Set<String>()
        for pkg in filtered {
            guard let first = pkg.name.first, first.isLetter else { continue }
            letters.insert(String(first).lowercased())
        }

        // A-Z 分组：与字母索引共用同一分组规则（非字母开头归 "#" 放最后）。
        // 单趟遍历完成分桶，避免为每个字母重复扫描数组。
        var buckets: [String: [Package]] = [:]
        for pkg in filtered {
            let key = CatalogSection.letter(for: pkg.name)
            buckets[key, default: []].append(pkg)
        }
        let sections = buckets.keys.sorted { a, b in
            if a == CatalogSection.nonLetterKey { return false }
            if b == CatalogSection.nonLetterKey { return true }
            return a < b
        }.map { CatalogSection(letter: $0, packages: buckets[$0] ?? []) }

        return CatalogDerivedData(
            filtered: filtered,
            sections: sections,
            index: index,
            letters: letters.sorted(),
            installedCount: installedCount,
            formulaCount: formulaCount,
            caskCount: catalog.count - formulaCount
        )
    }

    /// 目录派生数据的计算结果，跨线程传递。
    nonisolated struct CatalogDerivedData: Sendable {
        let filtered: [Package]
        let sections: [CatalogSection]
        let index: [String: Int]
        let letters: [String]
        let installedCount: Int
        let formulaCount: Int
        let caskCount: Int
    }

    /// 目录 A-Z 分组：letter 存小写字母（或 "#"），视图展示时转大写。
    /// 与 homeIndexLetters 使用同一首字母规则，保证索引跳转与分组完全一致。
    nonisolated struct CatalogSection: Identifiable, Sendable, Equatable {
        static let nonLetterKey = "#"
        let letter: String
        var packages: [Package]
        var id: String { letter }

        /// 与 computeCatalogDerivedData 中 letters 收集逻辑同源的分组键。
        static func letter(for name: String) -> String {
            guard let first = name.first, first.isLetter else { return nonLetterKey }
            return String(first).lowercased()
        }
    }

    /// 写入完整详情缓存并做 LRU 淘汰，防止内存无界增长。
    private func storeCatalogDetail(_ package: Package) {
        if catalogDetailCache[package.id] != nil {
            catalogDetailOrder.removeAll { $0 == package.id }
        }
        catalogDetailCache[package.id] = package
        catalogDetailOrder.append(package.id)
        while catalogDetailOrder.count > Self.maxCatalogDetailCacheSize {
            let evicted = catalogDetailOrder.removeFirst()
            catalogDetailCache[evicted] = nil
        }
    }

    /// 同步更新完整目录与主页过滤缓存中的同一条目，
    /// 保证详情视图拿到完整信息，且无需重建整个派生数据。
    private func syncCatalogEntry(_ package: Package) {
        // 使在途的派生重建结果作废，避免其写回回滚刚同步的条目
        derivedGeneration += 1
        // 逐处按内容差异写回：无变化不发布、不递增列表 stamp。
        // 之前每次详情加载（catalogDetail）都会无条件更新目录条目，
        // 触发整个 1.4 万行列表的重建——浏览目录时点一个包就闪一次。
        if let idx = catalog.firstIndex(where: { $0.id == package.id }),
           catalog[idx] != package {
            catalog[idx] = package
        }
        if let homeIdx = homeCatalogIndex[package.id],
           homeIdx < homeFilteredCatalog.count,
           homeFilteredCatalog[homeIdx] != package {
            homeFilteredCatalog[homeIdx] = package
            // 同步分组缓存中的同一条目（分组内查找，组平均 ~500 项，仅详情同步时触发）
            for si in homeCatalogSections.indices {
                guard let pi = homeCatalogSections[si].packages.firstIndex(where: { $0.id == package.id }) else { continue }
                homeCatalogSections[si].packages[pi] = package
                break
            }
            homeCatalogListStamp += 1
        }
    }
}

// MARK: - 视图绑定工具

extension AppState {
    /// 异步绑定工具：避免在视图更新周期内直接修改 属性
    /// （didSet 会同步重建派生数据的属性尤其需要）。跨视图共用一份实现。
    func asyncBinding<T>(_ keyPath: ReferenceWritableKeyPath<AppState, T>) -> Binding<T> {
        Binding(
            get: { self[keyPath: keyPath] },
            set: { newValue in
                DispatchQueue.main.async {
                    self[keyPath: keyPath] = newValue
                }
            }
        )
    }
}

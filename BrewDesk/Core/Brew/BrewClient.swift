//
//  BrewClient.swift
//  BrewDesk
//

import Foundation

nonisolated struct BrewCommandResult: Sendable {
    let exitCode: Int32
    let stdout: String
    let stderr: String

    var succeeded: Bool { exitCode == 0 }
}

actor BrewClient {
    private var installation: BrewInstallation?
    private var writeProcess: Process?
    private var readProcesses: [UUID: Process] = [:]

    var currentInstallation: BrewInstallation? { installation }

    var isWriteRunning: Bool { writeProcess != nil }

    func resolve(customPath: String? = nil) -> BrewInstallation? {
        if let installation {
            return installation
        }
        let found = BrewLocator.locate(customPath: customPath)
        installation = found
        return found
    }

    func setCustomPath(_ path: String?) {
        installation = BrewLocator.locate(customPath: path)
    }

    func refreshInstallation(customPath: String? = nil) -> BrewInstallation? {
        installation = BrewLocator.locate(customPath: customPath)
        return installation
    }

    // MARK: - Queries

    func installedPackages() async throws -> [Package] {
        let data = try await runData(["info", "--json=v2", "--installed"])
        return try BrewJSON.decodeInfo(data)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func outdatedPackages() async throws -> [Package] {
        let data = try await runData(["outdated", "--json=v2"])
        let outdated = try BrewJSON.decodeOutdated(data)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

        // `brew outdated --json=v2` 只含名称与版本号；用 `brew info --json=v2`
        // 批量拉取完整信息（描述、主页、许可证、Tap、依赖、caveats、cask 图标等）补全，
        // 让“可更新”页与详情面板显示包的全部信息。失败时降级返回精简列表。
        guard !outdated.isEmpty else { return [] }

        let formulaNames = outdated.filter { $0.kind == .formula }.map(\.name)
        let caskNames = outdated.filter { $0.kind == .cask }.map(\.name)

        var fullByID: [String: Package] = [:]
        if !formulaNames.isEmpty,
           let full = try? await infoPackages(names: formulaNames, kind: .formula) {
            for pkg in full { fullByID[pkg.id] = pkg }
        }
        if !caskNames.isEmpty,
           let full = try? await infoPackages(names: caskNames, kind: .cask) {
            for pkg in full { fullByID[pkg.id] = pkg }
        }

        guard !fullByID.isEmpty else { return outdated }

        return outdated.map { entry in
            guard var full = fullByID[entry.id] else { return entry }
            // 版本与固定状态以 `brew outdated` 为准，其余字段取完整信息
            full.version = entry.version ?? full.version
            full.latestVersion = entry.latestVersion ?? full.latestVersion
            full.isInstalled = true
            full.isOutdated = true
            full.isPinned = entry.isPinned || full.isPinned
            return full
        }
    }

    /// 全部可安装包名（本地 tap 目录即时读取，毫秒级）。
    /// formula 与 cask 分开返回，避免同名 token 混淆。
    func allPackageNames() async throws -> (formulae: [String], casks: [String]) {
        async let formulae = runNameList(["formulae"])
        async let casks = runNameList(["casks"])
        return (try await formulae, try await casks)
    }

    /// 目录行的极简信息（`brew info --json=v2` 无参数即输出全量目录）。
    /// 全量 JSON 约 50MB / 1.6 万条，若在本进程内解码，启动峰值会吃掉数百 MB
    /// 内存。这里用管道把输出交给系统自带 ruby（macOS 必带）瘦身成
    /// name/desc/版本 三个字段，应用内只收到约 1–2MB JSON。
    /// 若 ruby 管道失败（异常环境），调用方 try? 静默跳过，目录行回退为仅名称。
    func catalogRows() async throws -> [BrewJSON.CatalogRow] {
        let install = try requireInstallation()
        // 脚本只用双引号，保证能被 sh 单引号安全包裹
        let script = #"require "json";s=STDIN.read;d=JSON.parse(s);f=d["formulae"].map{|x|{"name"=>x["name"],"desc"=>x["desc"],"versions"=>{"stable"=>x.dig("versions","stable")}}};c=d["casks"].map{|x|{"token"=>x["token"],"desc"=>x["desc"],"version"=>x["version"]}};print JSON.generate({"formulae"=>f,"casks"=>c})"#
        let pipeline = #""$BREW" info --json=v2 | /usr/bin/ruby -e '"# + script + "'"
        let result = try await runRead(
            install: install,
            arguments: ["-c", pipeline],
            environment: ["BREW": install.executableURL.path]
        )
        guard result.exitCode == 0, let data = result.stdout.data(using: .utf8) else {
            throw BrewError.nonZeroExit(
                command: "brew info --json=v2 (ruby 瘦身)",
                code: result.exitCode,
                stderr: result.stderr
            )
        }
        return try BrewJSON.decodeCatalogRows(data)
    }

    func search(query: String) async throws -> [Package] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        async let formulaNames = runSearchLines(["search", "--formula", trimmed])
        async let caskNames = runSearchLines(["search", "--cask", trimmed])

        let formulae = try await formulaNames
        let casks = try await caskNames

        let formulaDetails = try await infoPackages(names: Array(formulae.prefix(40)), kind: .formula)
        let caskDetails = try await infoPackages(names: Array(casks.prefix(40)), kind: .cask)

        var packages: [Package] = []
        packages.append(contentsOf: formulaDetails)
        packages.append(contentsOf: caskDetails)

        let order = Dictionary(
            uniqueKeysWithValues: (formulae.map { "formula:\($0)" } + casks.map { "cask:\($0)" })
                .enumerated()
                .map { ($0.element, $0.offset) }
        )
        return packages.sorted {
            (order[$0.id] ?? Int.max) < (order[$1.id] ?? Int.max)
        }
    }

    func info(name: String, kind: PackageKind) async throws -> Package? {
        let flag = kind == .formula ? "--formula" : "--cask"
        let data = try await runData(["info", "--json=v2", flag, name])
        guard var pkg = try BrewJSON.decodeInfo(data).first else { return nil }
        // Fetch analytics from brew info text output
        if let analytics = try? await fetchAnalytics(name: name) {
            pkg.analyticsInstall30d = analytics.install30d
            pkg.analyticsInstall90d = analytics.install90d
            pkg.analyticsInstall365d = analytics.install365d
            pkg.analyticsInstallOnRequest30d = analytics.installOnRequest30d
            pkg.analyticsInstallOnRequest90d = analytics.installOnRequest90d
            pkg.analyticsInstallOnRequest365d = analytics.installOnRequest365d
        }
        return pkg
    }

    /// Fetches analytics data from `brew info` text output.
    private func fetchAnalytics(name: String) async throws -> (install30d: Int?, install90d: Int?, install365d: Int?, installOnRequest30d: Int?, installOnRequest90d: Int?, installOnRequest365d: Int?) {
        let install = try requireInstallation()
        let result = try await runRead(install: install, arguments: ["info", name])
        return AnalyticsParser.parse(result.stdout)
    }

    // MARK: - Mutations (streaming)

    func update(onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["update"], onOutput: onOutput)
    }

    func upgrade(names: [String], onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["upgrade"]
        args.append(contentsOf: names)
        try await runStreaming(args, onOutput: onOutput)
    }

    func install(name: String, kind: PackageKind, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["install"]
        if kind == .cask { args.append("--cask") }
        args.append(name)
        try await runStreaming(args, onOutput: onOutput)
    }

    func uninstall(name: String, kind: PackageKind, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["uninstall", "--force", "--zap"]
        if kind == .cask { args.append("--cask") }
        args.append(name)
        try await runStreaming(args, onOutput: onOutput)
    }

    func pin(name: String, kind: PackageKind, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["pin"]
        args.append(kind == .cask ? "--cask" : "--formula")
        args.append(name)
        try await runStreaming(args, onOutput: onOutput)
    }

    func unpin(name: String, kind: PackageKind, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["unpin"]
        args.append(kind == .cask ? "--cask" : "--formula")
        args.append(name)
        try await runStreaming(args, onOutput: onOutput)
    }

    // MARK: - Cleanup
    func cleanupPreview() async throws -> CleanupPreview {
        let result = try await run(["cleanup", "-n", "--prune=all"])
        return CleanupParser.parse(result.stdout + result.stderr)
    }

    func cleanup(scrub: Bool = true, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["cleanup"]
        if scrub { args.append("--prune=all") }
        try await runStreaming(args, onOutput: onOutput)
    }

    // MARK: - Services

    func listServices() async throws -> [BrewService] {
        let data = try await runData(["services", "list", "--json"])
        var services = try ServicesJSON.decode(data)
        // `brew services list --json` 可能把在跑服务误报为 stopped，
        // 用 `brew services info --json --all` 一次取回全部服务的权威 running/loaded 状态
        // （单进程替代原来的每服务一个子进程，启动阶段从 1+N 降到 2 个进程）。
        if let allData = try? await runData(["services", "info", "--json", "--all"]),
           let rows = try? JSONDecoder().decode([ServiceInfoRow].self, from: allData) {
            let byName = Dictionary(
                rows.map { ($0.name, $0.asService()) },
                uniquingKeysWith: { first, _ in first }
            )
            for i in services.indices {
                if let info = byName[services[i].name] {
                    services[i] = info
                }
            }
        }
        return services
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func startService(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["services", "start", name], onOutput: onOutput)
    }

    func stopService(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["services", "stop", name], onOutput: onOutput)
    }

    func restartService(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["services", "restart", name], onOutput: onOutput)
    }

    // MARK: - Taps

    func listTaps() async throws -> [BrewTap] {
        let install = try requireInstallation()

        // Parse installed taps from `brew tap`
        let result = try await runRead(install: install, arguments: ["tap"])
        let lines = result.stdout.split(separator: "\n").map(String.init)
        var tapMap: [String: (name: String, installed: Bool)] = [:]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.lowercased().hasPrefix("==>") else { continue }
            tapMap[trimmed] = (name: trimmed, installed: true)
        }

        // Built-in taps are always present
        let builtins = ["homebrew/core", "homebrew/cask"]
        for name in builtins {
            if tapMap[name] == nil {
                tapMap[name] = (name: name, installed: false)
            }
        }

        // 获取每个 tap 的包列表与信任状态；并行执行并限制并发进程数。
        let entries = tapMap.values.sorted(by: { $0.name < $1.name })
        var tapResults: [BrewTap?] = Array(repeating: nil, count: entries.count)
        var batchStart = 0
        while batchStart < entries.count {
            let batchEnd = min(batchStart + Self.maxConcurrentBrewProcesses, entries.count)
            await withTaskGroup(of: (Int, BrewTap).self) { group in
                for i in batchStart..<batchEnd {
                    let entry = entries[i]
                    group.addTask { [self] in
                        let isOfficial = entry.name.hasPrefix("homebrew/")
                        // official taps are always trusted
                        var tap = BrewTap(
                            name: entry.name,
                            isOfficial: isOfficial,
                            isTrusted: isOfficial,
                            formulaCount: nil,
                            caskCount: nil,
                            isInstalled: entry.installed
                        )
                        // Try to get trust status from tap-info (may fail for sandbox reasons)
                        if let info = try? await self.tapInfo(name: entry.name) {
                            tap.formulaNames = info.formulaNames
                            tap.caskNames = info.caskNames
                            tap.formulaCount = info.formulaCount
                            tap.caskCount = info.caskCount
                            tap.isTrusted = info.isTrusted
                        }
                        return (i, tap)
                    }
                }
                for await (index, tap) in group {
                    tapResults[index] = tap
                }
            }
            batchStart = batchEnd
        }

        return tapResults.compactMap { $0 }
    }

    func addTap(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["tap", name], onOutput: onOutput)
    }

    func removeTap(_ name: String, force: Bool = false, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["untap"]
        if force { args.append("--force") }
        args.append(name)
        try await runStreaming(args, onOutput: onOutput)
    }

    func trustTap(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["trust", "--tap", name], onOutput: onOutput)
    }

    func untrustTap(_ name: String, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(["untrust", "--tap", name], onOutput: onOutput)
    }

    /// Get formula/cask names and trust status for a tap.
    func tapInfo(name: String) async throws -> (formulaNames: [String], caskNames: [String], formulaCount: Int?, caskCount: Int?, isTrusted: Bool) {
        let install = try requireInstallation()

        // Convert tap name to directory path
        // e.g. "ftzahao/tap" -> "/opt/homebrew/Library/Taps/ftzahao/homebrew-tap"
        let parts = name.split(separator: "/")
        guard parts.count == 2 else {
            // Fallback to tap-info for unusual names
            return try await tapInfoFromBrew(name: name)
        }
        let user = String(parts[0])
        let repo = String(parts[1])
        let tapDir = URL(fileURLWithPath: install.prefix)
            .appendingPathComponent("Library/Taps/\(user)/homebrew-\(repo)")
            .path

        let fm = FileManager.default
        guard fm.fileExists(atPath: tapDir) else {
            return try await tapInfoFromBrew(name: name)
        }

        // List Formula/*.rb
        let formulaDir = (tapDir as NSString).appendingPathComponent("Formula")
        let formulaNames = (try? fm.contentsOfDirectory(atPath: formulaDir))?
            .filter { $0.hasSuffix(".rb") }
            .map { String($0.dropLast(3)) } ?? []

        // Also check root-level .rb files (some taps put formulas at root)
        let rootFiles = (try? fm.contentsOfDirectory(atPath: tapDir))?
            .filter { $0.hasSuffix(".rb") }
            .map { String($0.dropLast(3)) } ?? []

        let allFormulas = Set(formulaNames + rootFiles).sorted()

        // List Casks/*.rb
        let caskDir = (tapDir as NSString).appendingPathComponent("Casks")
        let caskNames = (try? fm.contentsOfDirectory(atPath: caskDir))?
            .filter { $0.hasSuffix(".rb") }
            .map { String($0.dropLast(3)) } ?? []

        // Check trust status via brew tap-info --json (authoritative source)
        let isOfficial = name.hasPrefix("homebrew/")
        let isTrusted: Bool
        if isOfficial {
            isTrusted = true
        } else if let brewInfo = try? await tapInfoFromBrew(name: name) {
            isTrusted = brewInfo.isTrusted
        } else {
            isTrusted = false
        }

        return (allFormulas, caskNames, allFormulas.count, caskNames.count, isTrusted)
    }

    /// Fallback: use brew tap-info --json for taps not on local disk.
    private func tapInfoFromBrew(name: String) async throws -> (formulaNames: [String], caskNames: [String], formulaCount: Int?, caskCount: Int?, isTrusted: Bool) {
        let data = try await runData(["tap-info", "--json", name])
        guard let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let first = jsonArray.first else {
            return ([], [], nil, nil, false)
        }
        let fn = (first["formula_names"] as? [String]) ?? []
        let cn = (first["cask_names"] as? [String]) ?? []
        let trusted = (first["trusted"] as? Bool) ?? false
        return (fn, cn, first["formula_count"] as? Int, first["cask_count"] as? Int, trusted)
    }

    // MARK: - Brewfile (bundle)

    /// Dump current installs to a Brewfile path (`brew bundle dump --force --file …`).
    func dumpBrewfile(to fileURL: URL, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(
            ["bundle", "dump", "--force", "--file", fileURL.path],
            onOutput: onOutput
        )
    }

    func installBrewfile(from fileURL: URL, onOutput: @escaping @Sendable (String) -> Void) async throws {
        try await runStreaming(
            ["bundle", "install", "--file", fileURL.path],
            onOutput: onOutput
        )
    }

    func checkBrewfile(from fileURL: URL) async throws -> (ok: Bool, output: String) {
        let install = try requireInstallation()
        let result = try await runRead(
            install: install,
            arguments: ["bundle", "check", "--file", fileURL.path]
        )
        let output = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        if result.exitCode != 0 && result.exitCode != 1 {
            throw BrewError.nonZeroExit(
                command: "brew bundle check",
                code: result.exitCode,
                stderr: output
            )
        }
        return (result.exitCode == 0, output)
    }

    func cancel() {
        writeProcess?.terminate()
        writeProcess = nil
        for (_, process) in readProcesses {
            process.terminate()
        }
        readProcesses.removeAll()
    }

    // MARK: - Internals

    /// 并行查询时最多同时运行的 brew 子进程数（防止瞬间拉起大量进程）
    private static let maxConcurrentBrewProcesses = 6

    private func requireInstallation() throws -> BrewInstallation {
        if let installation {
            return installation
        }
        guard let found = BrewLocator.locate() else {
            throw BrewError.notInstalled
        }
        installation = found
        return found
    }

    /// 批量拉取指定包的完整 info（search / outdated 补全共用），失败时逐个降级重试。
    func infoPackages(names: [String], kind: PackageKind) async throws -> [Package] {
        guard !names.isEmpty else { return [] }
        let flag = kind == .formula ? "--formula" : "--cask"
        do {
            let data = try await runData(["info", "--json=v2", flag] + names)
            return try BrewJSON.decodeInfo(data)
        } catch {
            var result: [Package] = []
            for name in names {
                if let pkg = try? await info(name: name, kind: kind) {
                    result.append(pkg)
                }
            }
            return result
        }
    }

    /// `brew search` exits 1 when there are no matches — treat that as empty.
    private func runSearchLines(_ arguments: [String]) async throws -> [String] {
        let install = try requireInstallation()
        let result = try await runRead(install: install, arguments: arguments)
        if result.exitCode != 0 && result.exitCode != 1 {
            let command = (["brew"] + arguments).joined(separator: " ")
            throw BrewError.nonZeroExit(command: command, code: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
    }

    /// 解析 `brew formulae` / `brew casks` 这类纯名称列表输出。
    private func runNameList(_ arguments: [String]) async throws -> [String] {
        let install = try requireInstallation()
        let result = try await runRead(install: install, arguments: arguments)
        if result.exitCode != 0 {
            let command = (["brew"] + arguments).joined(separator: " ")
            throw BrewError.nonZeroExit(
                command: command,
                code: result.exitCode,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==") }
    }

    private func runData(_ arguments: [String]) async throws -> Data {
        let result = try await run(arguments)
        guard let data = result.stdout.data(using: .utf8) else {
            throw BrewError.invalidJSON("stdout 不是合法 UTF-8")
        }
        return data
    }

    private func run(_ arguments: [String]) async throws -> BrewCommandResult {
        let install = try requireInstallation()
        let result = try await runRead(install: install, arguments: arguments)
        if result.exitCode != 0 {
            let command = (["brew"] + arguments).joined(separator: " ")
            throw BrewError.nonZeroExit(
                command: command,
                code: result.exitCode,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        return result
    }

    // Wrapper to safely pass mutable Data across @Sendable closures.
    private final class PipeBuffer: @unchecked Sendable {
        var data = Data()
    }

    /// 任务取消时用于终止子进程的线程安全容器。
    private final class ProcessHolder: @unchecked Sendable {
        private let lock = NSLock()
        private var process: Process?

        func set(_ process: Process) {
            lock.lock()
            defer { lock.unlock() }
            self.process = process
        }

        func terminate() {
            lock.lock()
            defer { lock.unlock() }
            process?.terminate()
            process = nil
        }
    }

    private func runRead(
        install: BrewInstallation,
        arguments: [String],
        environment: [String: String] = [:]
    ) async throws -> BrewCommandResult {
        let id = UUID()
        let holder = ProcessHolder()

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let process = Process()
                holder.set(process)
                process.executableURL = install.executableURL
                process.arguments = arguments
                var env = BrewLocator.brewEnvironment(executable: install.executableURL)
                env.merge(environment) { _, new in new }
                process.environment = env

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                readProcesses[id] = process

                // Read pipe data in background threads to prevent the child process
                // from blocking when output exceeds the pipe buffer size (64KB on macOS).
                let outHandle = out.fileHandleForReading
                let errHandle = err.fileHandleForReading
                let readGroup = DispatchGroup()
                let stdoutBuf = PipeBuffer()
                let stderrBuf = PipeBuffer()

                readGroup.enter()
                DispatchQueue.global().async {
                    stdoutBuf.data = outHandle.readDataToEndOfFile()
                    readGroup.leave()
                }

                readGroup.enter()
                DispatchQueue.global().async {
                    stderrBuf.data = errHandle.readDataToEndOfFile()
                    readGroup.leave()
                }

                process.terminationHandler = { [weak self] proc in
                    readGroup.wait()

                    let stdout = String(data: stdoutBuf.data, encoding: .utf8) ?? ""
                    let stderr = String(data: stderrBuf.data, encoding: .utf8) ?? ""

                    Task {
                        await self?.clearReadProcess(id)
                    }

                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: BrewError.cancelled)
                        return
                    }

                    // 退出码原样返回，由各调用方自行判断（如 `brew search` 无结果时退出码为 1）
                    continuation.resume(returning: BrewCommandResult(
                        exitCode: proc.terminationStatus,
                        stdout: stdout,
                        stderr: stderr
                    ))
                }

                do {
                    try process.run()
                } catch {
                    readProcesses[id] = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            holder.terminate()
        }
    }

    private func runStreaming(_ arguments: [String], onOutput: @escaping @Sendable (String) -> Void) async throws {
        let install = try requireInstallation()
        if writeProcess != nil {
            throw BrewError.busy
        }

        let holder = ProcessHolder()

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let process = Process()
                holder.set(process)
                process.executableURL = install.executableURL
                process.arguments = arguments
                process.environment = BrewLocator.brewEnvironment(executable: install.executableURL)

                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                writeProcess = process

                let handleOutput: @Sendable (FileHandle) -> Void = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                    onOutput(text)
                }

                out.fileHandleForReading.readabilityHandler = handleOutput
                err.fileHandleForReading.readabilityHandler = handleOutput

                process.terminationHandler = { [weak self] proc in
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil

                    let restOut = out.fileHandleForReading.readDataToEndOfFile()
                    if !restOut.isEmpty, let text = String(data: restOut, encoding: .utf8) {
                        onOutput(text)
                    }
                    let restErr = err.fileHandleForReading.readDataToEndOfFile()
                    if !restErr.isEmpty, let text = String(data: restErr, encoding: .utf8) {
                        onOutput(text)
                    }

                    Task {
                        await self?.clearWriteProcess()
                    }

                    if proc.terminationReason == .uncaughtSignal {
                        continuation.resume(throwing: BrewError.cancelled)
                        return
                    }

                    if proc.terminationStatus != 0 {
                        let command = (["brew"] + arguments).joined(separator: " ")
                        continuation.resume(
                            throwing: BrewError.nonZeroExit(
                                command: command,
                                code: proc.terminationStatus,
                                stderr: "见上方日志"
                            )
                        )
                        return
                    }

                    continuation.resume()
                }

                do {
                    onOutput("$ brew \(arguments.joined(separator: " "))\n")
                    try process.run()
                } catch {
                    writeProcess = nil
                    out.fileHandleForReading.readabilityHandler = nil
                    err.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        } onCancel: {
            holder.terminate()
        }
    }

    private func clearWriteProcess() {
        writeProcess = nil
    }

    private func clearReadProcess(_ id: UUID) {
        readProcesses[id] = nil
    }
}

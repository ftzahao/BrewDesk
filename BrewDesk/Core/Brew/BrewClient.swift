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
        return try BrewJSON.decodeOutdated(data)
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
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
        let result = try await runRead(install: install, arguments: ["info", name], allowNonZero: false)
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

    // MARK: - Doctor / Cleanup

    /// `brew doctor` exits non-zero when warnings exist; that is not a hard failure.
    func doctor() async throws -> (issues: [DoctorIssue], raw: String, isHealthy: Bool) {
        let install = try requireInstallation()
        let result = try await runRead(install: install, arguments: ["doctor"], allowNonZero: true)
        if result.exitCode != 0 && result.exitCode != 1 {
            let command = "brew doctor"
            throw BrewError.nonZeroExit(
                command: command,
                code: result.exitCode,
                stderr: result.stderr.isEmpty ? result.stdout : result.stderr
            )
        }
        let combined = [result.stdout, result.stderr]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        let issues = DoctorParser.parse(combined)
        let healthy = result.exitCode == 0 && issues.isEmpty
        return (issues, combined, healthy)
    }

    func cleanupPreview() async throws -> CleanupPreview {
        let result = try await run(["cleanup", "-n", "-s"])
        return CleanupParser.parse(result.stdout + result.stderr)
    }

    func cleanup(scrub: Bool = true, onOutput: @escaping @Sendable (String) -> Void) async throws {
        var args = ["cleanup"]
        if scrub { args.append("-s") }
        try await runStreaming(args, onOutput: onOutput)
    }

    // MARK: - Services

    func listServices() async throws -> [BrewService] {
        let data = try await runData(["services", "list", "--json"])
        var services = try ServicesJSON.decode(data)
        // Use `brew services info --json` for each service to get accurate `running` status,
        // since `brew services list --json` may report "stopped" for actually running services.
        for i in services.indices {
            if let info = try? await serviceInfo(name: services[i].name) {
                services[i] = info
            }
        }
        return services
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func serviceInfo(name: String) async throws -> BrewService? {
        let data = try? await runData(["services", "info", "--json", name])
        guard let data, let rows = try? JSONDecoder().decode([ServiceInfoRow].self, from: data),
              let row = rows.first else { return nil }
        return row.asService()
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
        let result = try await runRead(install: install, arguments: ["tap"], allowNonZero: true)
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

        // Get trust status via tap-info for each tap
        var taps: [BrewTap] = []
        for entry in tapMap.values.sorted(by: { $0.name < $1.name }) {
            let isOfficial = entry.name.hasPrefix("homebrew/")
            let isTrusted = isOfficial // official taps are always trusted
            var tap = BrewTap(
                name: entry.name,
                isOfficial: isOfficial,
                isTrusted: isTrusted,
                formulaCount: nil,
                caskCount: nil,
                isInstalled: entry.installed
            )
            // Try to get trust status from tap-info (may fail for sandbox reasons)
            if let info = try? await tapInfo(name: entry.name) {
                tap.formulaNames = info.formulaNames
                tap.caskNames = info.caskNames
                tap.formulaCount = info.formulaCount
                tap.caskCount = info.caskCount
                tap.isTrusted = info.isTrusted
            }
            taps.append(tap)
        }

        return taps
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

    /// Dump Brewfile contents to stdout (no file write).
    func dumpBrewfileText() async throws -> String {
        let result = try await run(["bundle", "dump", "--file", "-"])
        let text = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty {
            throw BrewError.invalidJSON("Brewfile 导出结果为空")
        }
        return result.stdout
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
            arguments: ["bundle", "check", "--file", fileURL.path],
            allowNonZero: true
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

    private func infoPackages(names: [String], kind: PackageKind) async throws -> [Package] {
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
        let result = try await runRead(install: install, arguments: arguments, allowNonZero: true)
        if result.exitCode != 0 && result.exitCode != 1 {
            let command = (["brew"] + arguments).joined(separator: " ")
            throw BrewError.nonZeroExit(command: command, code: result.exitCode, stderr: result.stderr)
        }
        return result.stdout
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("==>") }
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
        let result = try await runRead(install: install, arguments: arguments, allowNonZero: false)
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

    private func runRead(
        install: BrewInstallation,
        arguments: [String],
        allowNonZero: Bool
    ) async throws -> BrewCommandResult {
        let id = UUID()

        return try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = install.executableURL
            process.arguments = arguments
            process.environment = BrewLocator.brewEnvironment(executable: install.executableURL)

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

                _ = allowNonZero
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
    }

    private func runStreaming(_ arguments: [String], onOutput: @escaping @Sendable (String) -> Void) async throws {
        let install = try requireInstallation()
        if writeProcess != nil {
            throw BrewError.busy
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
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
    }

    private func clearWriteProcess() {
        writeProcess = nil
    }

    private func clearReadProcess(_ id: UUID) {
        readProcesses[id] = nil
    }
}

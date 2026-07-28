//
//  BrewLocator.swift
//  BrewDesk
//

import Foundation

nonisolated struct BrewInstallation: Sendable, Equatable {
    let executableURL: URL
    let prefix: String
    let version: String
}

nonisolated enum BrewLocator {
    private static let candidatePaths = [
        "/opt/homebrew/bin/brew",
        "/usr/local/bin/brew",
        "\(NSHomeDirectory())/homebrew/bin/brew",
        "\(NSHomeDirectory())/.linuxbrew/bin/brew",
    ]

    static func locate(customPath: String? = nil) -> BrewInstallation? {
        var paths: [String] = []
        if let customPath, !customPath.isEmpty {
            paths.append(customPath)
        }
        paths.append(contentsOf: candidatePaths)

        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                paths.append("\(dir)/brew")
            }
        }

        var seen = Set<String>()
        for path in paths {
            let normalized = (path as NSString).standardizingPath
            guard seen.insert(normalized).inserted else { continue }
            let url = URL(fileURLWithPath: normalized)
            guard FileManager.default.isExecutableFile(atPath: url.path) else { continue }
            if let installation = probe(executableURL: url) {
                return installation
            }
        }
        return nil
    }

    private static func probe(executableURL: URL) -> BrewInstallation? {
        guard let version = runSimple(executableURL, arguments: ["--version"])?
            .split(separator: "\n").first
            .map(String.init),
            !version.isEmpty
        else {
            return nil
        }

        let prefix = runSimple(executableURL, arguments: ["--prefix"])?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? executableURL.deletingLastPathComponent().deletingLastPathComponent().path

        return BrewInstallation(
            executableURL: executableURL,
            prefix: prefix,
            version: version
        )
    }

    private static func runSimple(_ executable: URL, arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = brewEnvironment(executable: executable)

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)
    }

    static func brewEnvironment(executable: URL) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let binDir = executable.deletingLastPathComponent().path
        let existing = env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"
        if !existing.split(separator: ":").contains(where: { String($0) == binDir }) {
            env["PATH"] = "\(binDir):\(existing)"
        }
        env["HOMEBREW_NO_AUTO_UPDATE"] = "1"
        env["HOMEBREW_NO_ENV_HINTS"] = "1"
        env["HOMEBREW_COLOR"] = "0"
        env["HOMEBREW_NO_ANALYTICS"] = "1"
        env["HOMEBREW_NO_EMOJI"] = "1"
        return env
    }
}

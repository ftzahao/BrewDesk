//
//  DoctorParser.swift
//  BrewDesk
//

import Foundation

nonisolated enum CleanupParser {
    static func parse(_ text: String) -> CleanupPreview {
        let lines = text
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { line in
                guard !line.isEmpty else { return false }
                let lower = line.lowercased()
                return lower.hasPrefix("would remove")
                    || lower.hasPrefix("would uninstall")
                    || lower.contains("would remove")
            }
        return CleanupPreview(lines: lines, rawText: text)
    }
}

nonisolated enum ServicesJSON {
    private struct Row: Decodable {
        let name: String
        let status: String?
        let user: String?
        let file: String?
        let exitCode: Int?

        enum CodingKeys: String, CodingKey {
            case name, status, user, file
            case exitCode = "exit_code"
        }

        func asService() -> BrewService {
            let raw = status ?? "unknown"
            return BrewService(
                name: name,
                status: BrewServiceStatus(raw: raw),
                statusRaw: raw,
                user: user,
                file: file,
                exitCode: exitCode
            )
        }
    }

    static func decode(_ data: Data) throws -> [BrewService] {
        do {
            let rows = try JSONDecoder().decode([Row].self, from: data)
            return rows.map { $0.asService() }
        } catch {
            throw BrewError.invalidJSON(error.localizedDescription)
        }
    }
}

/// Decodes `brew services info --json <name>` which includes `running` and `loaded` fields.
nonisolated struct ServiceInfoRow: Decodable {
    let name: String
    let running: Bool?
    let loaded: Bool?
    let status: String?
    let user: String?
    let file: String?
    let exitCode: Int?
    let pid: Int?

    enum CodingKeys: String, CodingKey {
        case name, running, loaded, status, user, file, pid
        case exitCode = "exit_code"
    }

    func asService() -> BrewService {
        let raw = status ?? "unknown"
        let parsed = BrewServiceStatus(raw: raw)
        // Override status using the `running` boolean when available
        let finalStatus: BrewServiceStatus
        if let running {
            finalStatus = running ? .started : (parsed == .error ? .error : .stopped)
        } else {
            finalStatus = parsed
        }
        return BrewService(
            name: name,
            status: finalStatus,
            statusRaw: raw,
            user: user,
            file: file,
            exitCode: exitCode
        )
    }
}

/// Parses analytics section from `brew info <name>` text output.
nonisolated enum AnalyticsParser {
    static func parse(_ text: String) -> (install30d: Int?, install90d: Int?, install365d: Int?,
                                          installOnRequest30d: Int?, installOnRequest90d: Int?, installOnRequest365d: Int?) {
        var install30d: Int?, install90d: Int?, install365d: Int?
        var ior30d: Int?, ior90d: Int?, ior365d: Int?

        let lines = text.split(separator: "\n").map(String.init)
        var inAnalytics = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "==> Analytics" {
                inAnalytics = true
                continue
            }
            if inAnalytics {
                if trimmed.hasPrefix("==>") { break }
                if trimmed.hasPrefix("install:") {
                    let values = parseAnalyticsValues(trimmed)
                    install30d = values.0; install90d = values.1; install365d = values.2
                } else if trimmed.hasPrefix("install-on-request:") {
                    let values = parseAnalyticsValues(trimmed)
                    ior30d = values.0; ior90d = values.1; ior365d = values.2
                } else if trimmed.hasPrefix("build-error:") {
                    break
                }
            }
        }
        return (install30d, install90d, install365d, ior30d, ior90d, ior365d)
    }

    /// Parses "install: 3,658 (30 days), 9,291 (90 days), 21,971 (365 days)"
    private static func parseAnalyticsValues(_ line: String) -> (Int?, Int?, Int?) {
        guard let colonIdx = line.firstIndex(of: ":") else { return (nil, nil, nil) }
        let afterColon = line[line.index(after: colonIdx)...]
            .trimmingCharacters(in: .whitespaces)
        let parts = afterColon.components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        let cleaned = parts.compactMap { part -> Int? in
            let digits = part.filter { $0.isNumber || $0 == "," }
                .replacingOccurrences(of: ",", with: "")
            return Int(digits)
        }
        guard cleaned.count >= 3 else { return (nil, nil, nil) }
        return (cleaned[0], cleaned[1], cleaned[2])
    }
}

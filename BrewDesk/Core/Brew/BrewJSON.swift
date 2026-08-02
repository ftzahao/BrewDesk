//
//  BrewJSON.swift
//  BrewDesk
//

import Foundation

nonisolated enum BrewJSON {
    struct InfoRoot: Decodable {
        let formulae: [Formula]
        let casks: [Cask]
    }

    struct Formula: Decodable {
        let name: String
        let fullName: String?
        let desc: String?
        let homepage: String?
        let versions: Versions?
        let outdated: Bool?
        let pinned: Bool?
        let dependencies: [String]?
        let installed: [InstalledFormula]?
        let license: String?
        let tap: String?
        let urls: Urls?
        let caveats: String?
        let conflictsWith: [String]?
        let deprecated: Bool?
        let deprecationReason: String?
        let deprecationDate: String?
        let disabled: Bool?
        let disableReason: String?
        let disableDate: String?
        let kegOnly: Bool?
        let kegOnlyReason: KegOnlyReason?
        let buildDependencies: [String]?
        let usesFromMacOS: [UsesFromMacOSEntry]?

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case desc, homepage, versions, outdated, pinned, dependencies, installed
            case license, tap, urls, caveats
            case conflictsWith = "conflicts_with"
            case deprecated
            case deprecationReason = "deprecation_reason"
            case deprecationDate = "deprecation_date"
            case disabled
            case disableReason = "disable_reason"
            case disableDate = "disable_date"
            case kegOnly = "keg_only"
            case kegOnlyReason = "keg_only_reason"
            case buildDependencies = "build_dependencies"
            case usesFromMacOS = "uses_from_macos"
        }

        struct Versions: Decodable {
            let stable: String?
        }

        /// `urls` 字段：{"stable": {"url": "…"}}，stable 偶尔可能是字符串。
        struct Urls: Decodable {
            let stable: Stable?

            struct Stable: Decodable {
                let url: String?

                init(from decoder: Decoder) throws {
                    if let single = try? decoder.singleValueContainer(),
                       let s = try? single.decode(String.self) {
                        url = s
                        return
                    }
                    let container = try decoder.container(keyedBy: CodingKeys.self)
                    url = try? container.decodeIfPresent(String.self, forKey: .url)
                }

                private enum CodingKeys: String, CodingKey { case url }
            }
        }

        /// `keg_only_reason`：{"reason": ":shadowed_by_macos", "explanation": "…"}，也可能是字符串。
        struct KegOnlyReason: Decodable {
            let reason: String?
            let explanation: String?

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let s = try? single.decode(String.self) {
                    reason = s
                    explanation = nil
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                reason = try? container.decodeIfPresent(String.self, forKey: .reason)
                explanation = try? container.decodeIfPresent(String.self, forKey: .explanation)
            }

            private enum CodingKeys: String, CodingKey { case reason, explanation }
        }

        /// uses_from_macos 的元素：可能是 "ncurses" 字符串，也可能是 {"m4": "build"} 字典。
        struct UsesFromMacOSEntry: Decodable {
            let summary: String

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let s = try? single.decode(String.self) {
                    summary = s
                    return
                }
                if let container = try? decoder.container(keyedBy: DynamicKey.self) {
                    var parts: [String] = []
                    for key in container.allKeys {
                        if let value = try? container.decode(String.self, forKey: key) {
                            parts.append("\(key.stringValue) (\(value))")
                        } else if let value = try? container.decode(Bool.self, forKey: key),
                                  value {
                            parts.append(key.stringValue)
                        } else {
                            parts.append(key.stringValue)
                        }
                    }
                    summary = parts.joined(separator: ", ")
                    return
                }
                summary = "?"
            }

            private struct DynamicKey: CodingKey {
                var stringValue: String
                var intValue: Int? { nil }
                init?(stringValue: String) { self.stringValue = stringValue }
                init?(intValue: Int) { nil }
            }
        }

        struct InstalledFormula: Decodable {
            let version: String?
            let installedOnRequest: Bool?
            let time: Int?

            enum CodingKeys: String, CodingKey {
                case version
                case installedOnRequest = "installed_on_request"
                case time
            }
        }

        func asPackage() -> Package {
            let installedVersion = installed?.last?.version
            let onRequest = installed?.contains(where: { $0.installedOnRequest == true }) ?? false
            let installTime = installed?.last?.time.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
            let kegReason = kegOnlyReason?.explanation?.isEmpty == false
                ? kegOnlyReason?.explanation
                : kegOnlyReason?.reason
            return Package(
                name: name,
                kind: .formula,
                version: installedVersion,
                latestVersion: versions?.stable,
                desc: desc,
                homepage: homepage.flatMap(URL.init(string:)),
                isInstalled: installed?.isEmpty == false,
                isOutdated: outdated ?? false,
                isPinned: pinned ?? false,
                dependencies: dependencies ?? [],
                installedOnRequest: onRequest,
                installedTime: installTime,
                license: license,
                tap: tap,
                sourceURL: urls?.stable?.url.flatMap(URL.init(string:)),
                caveats: caveats,
                conflictsWith: conflictsWith ?? [],
                isDeprecated: deprecated ?? false,
                deprecationReason: deprecationReason,
                deprecationDate: deprecationDate,
                isDisabled: disabled ?? false,
                disableReason: disableReason,
                disableDate: disableDate,
                kegOnly: kegOnly ?? false,
                kegOnlyReason: kegReason,
                buildDependencies: buildDependencies ?? [],
                usesFromMacOS: usesFromMacOS?.compactMap(\.summary) ?? [],
                installedVersions: installed?.compactMap(\.version) ?? []
            )
        }
    }

    struct Cask: Decodable {
        let token: String
        let name: [String]?
        let desc: String?
        let homepage: String?
        let version: String?
        let outdated: Bool?
        let pinned: Bool?
        let installed: String?
        let installedTime: Int?
        let artifacts: [Artifact]?
        let license: String?
        let tap: String?
        let url: String?
        let caveats: String?
        let conflictsWith: ConflictsWith?
        let deprecated: Bool?
        let deprecationReason: String?
        let deprecationDate: String?
        let disabled: Bool?
        let disableReason: String?
        let disableDate: String?
        let autoUpdates: Bool?
        let sha256: String?
        let dependsOn: DependsOn?

        enum CodingKeys: String, CodingKey {
            case token, name, desc, homepage, version, outdated, pinned, installed, artifacts
            case installedTime = "installed_time"
            case license, tap, url, caveats
            case conflictsWith = "conflicts_with"
            case deprecated
            case deprecationReason = "deprecation_reason"
            case deprecationDate = "deprecation_date"
            case disabled
            case disableReason = "disable_reason"
            case disableDate = "disable_date"
            case autoUpdates = "auto_updates"
            case sha256
            case dependsOn = "depends_on"
        }

        /// cask 的 conflicts_with：{"cask": […], "formula": […]}
        struct ConflictsWith: Decodable {
            let cask: [String]?
            let formula: [String]?

            init(from decoder: Decoder) throws {
                if let single = try? decoder.singleValueContainer(),
                   let arr = try? single.decode([String].self) {
                    cask = arr
                    formula = nil
                    return
                }
                let container = try decoder.container(keyedBy: CodingKeys.self)
                cask = Self.flexibleStrings(
                    try? container.decodeIfPresent(StringList.self, forKey: .cask)
                )
                formula = Self.flexibleStrings(
                    try? container.decodeIfPresent(StringList.self, forKey: .formula)
                )
            }

            private enum CodingKeys: String, CodingKey { case cask, formula }

            /// 兼容值为字符串或字符串数组两种形态。
            private enum StringList: Decodable {
                case one(String)
                case many([String])

                init(from decoder: Decoder) throws {
                    let single = try decoder.singleValueContainer()
                    if let s = try? single.decode(String.self) {
                        self = .one(s)
                    } else {
                        self = .many(try single.decode([String].self))
                    }
                }
            }

            private static func flexibleStrings(_ list: StringList?) -> [String]? {
                switch list {
                case .one(let s): [s]
                case .many(let arr): arr
                case nil: nil
                }
            }

            var all: [String] { (cask ?? []) + (formula ?? []) }
        }

        /// cask 的 depends_on：{"macos": {">=": ["11"]}, "formula": […], "cask": […], "arch": […], "java": "…"}
        struct DependsOn: Decodable {
            let formula: [String]?
            let cask: [String]?
            let arch: [ArchEntry]?
            let java: JavaConstraint?
            let macos: MacOSConstraint?

            /// depends_on.java：可能是 "17" 字符串，也可能是数组。
            struct JavaConstraint: Decodable {
                let summary: String?

                init(from decoder: Decoder) throws {
                    let single = try decoder.singleValueContainer()
                    if let s = try? single.decode(String.self) {
                        summary = s
                    } else if let arr = try? single.decode([String].self) {
                        summary = arr.joined(separator: ", ")
                    } else {
                        summary = nil
                    }
                }
            }

            /// depends_on.arch 的元素：可能是 "arm64" 字符串，也可能是 {"type": "arm", "bits": 64} 字典。
            struct ArchEntry: Decodable {
                let summary: String

                init(from decoder: Decoder) throws {
                    if let single = try? decoder.singleValueContainer(),
                       let s = try? single.decode(String.self) {
                        summary = s
                        return
                    }
                    if let container = try? decoder.container(keyedBy: CodingKeys.self) {
                        let type = (try? container.decodeIfPresent(String.self, forKey: .type)) ?? ""
                        let bits = (try? container.decodeIfPresent(Int.self, forKey: .bits)) ?? 0
                        var parts: [String] = []
                        if !type.isEmpty { parts.append(type) }
                        if bits > 0 { parts.append("\(bits)") }
                        summary = parts.joined(separator: " ")
                        return
                    }
                    summary = "?"
                }

                private enum CodingKeys: String, CodingKey { case type, bits }
            }

            struct MacOSConstraint: Decodable {
                let summary: String?

                init(from decoder: Decoder) throws {
                    if let single = try? decoder.singleValueContainer() {
                        if let s = try? single.decode(String.self) {
                            summary = s
                            return
                        }
                        if let arr = try? single.decode([String].self) {
                            summary = arr.joined(separator: ", ")
                            return
                        }
                    }
                    if let container = try? decoder.container(keyedBy: DynamicKey.self) {
                        var parts: [String] = []
                        for key in container.allKeys {
                            if let op = try? container.decode([String].self, forKey: key) {
                                parts.append("\(key.stringValue) \(op.joined(separator: ", "))")
                            } else if let op = try? container.decode(String.self, forKey: key) {
                                parts.append("\(key.stringValue) \(op)")
                            }
                        }
                        summary = parts.isEmpty ? nil : parts.joined(separator: ", ")
                        return
                    }
                    summary = nil
                }

                private struct DynamicKey: CodingKey {
                    var stringValue: String
                    var intValue: Int? { nil }
                    init?(stringValue: String) { self.stringValue = stringValue }
                    init?(intValue: Int) { nil }
                }
            }
        }

        /// artifacts 中任意一项（app/pkg/zap 等），只关心其中的 app 信息。
        /// 注意：`app` 数组可能是混合类型，例如
        /// `["CleanMyMac_5.app", {"target": "CleanMyMac.app"}]`，
        /// 直接按 [String] 解码会导致整个列表解析失败，这里做宽容解码。
        struct Artifact: Decodable {
            let app: [String]?
            let target: String?

            private enum CodingKeys: String, CodingKey {
                case app, target
            }

            init(from decoder: Decoder) throws {
                // 兼容非字典条目（老格式如 ["X.app", ["app"]]），直接忽略
                guard let container = try? decoder.container(keyedBy: CodingKeys.self) else {
                    app = nil
                    target = nil
                    return
                }

                target = (try? container.decodeIfPresent(String.self, forKey: .target)) ?? nil

                if let raw = try? container.decode([AppValue].self, forKey: .app) {
                    app = raw.compactMap(\.name)
                } else if let single = try? container.decode(String.self, forKey: .app) {
                    app = [single]
                } else {
                    app = nil
                }
            }

            /// app 数组中的单个元素：可能是字符串，也可能是带 target 的字典
            private enum AppValue: Decodable {
                case string(String)
                case target(String)
                case other

                init(from decoder: Decoder) throws {
                    if let s = try? decoder.singleValueContainer().decode(String.self) {
                        self = .string(s)
                    } else if let nested = try? decoder.container(keyedBy: CodingKeys.self),
                              let target = try? nested.decode(String.self, forKey: .target) {
                        self = .target(target)
                    } else {
                        self = .other
                    }
                }

                var name: String? {
                    switch self {
                    case .string(let s): s
                    case .target(let t): t
                    case .other: nil
                    }
                }

                private enum CodingKeys: String, CodingKey {
                    case target
                }
            }
        }

        func asPackage() -> Package {
            let installTime = installedTime.flatMap { Date(timeIntervalSince1970: TimeInterval($0)) }
            var depends: [String] = []
            if let macos = dependsOn?.macos?.summary, !macos.isEmpty {
                depends.append("macOS \(macos)")
            }
            if let formula = dependsOn?.formula, !formula.isEmpty {
                depends.append("formula: \(formula.joined(separator: ", "))")
            }
            if let cask = dependsOn?.cask, !cask.isEmpty {
                depends.append("cask: \(cask.joined(separator: ", "))")
            }
            if let arch = dependsOn?.arch, !arch.isEmpty {
                depends.append("arch: \(arch.compactMap(\.summary).joined(separator: ", "))")
            }
            if let java = dependsOn?.java?.summary, !java.isEmpty {
                depends.append("java: \(java)")
            }
            return Package(
                name: token,
                kind: .cask,
                version: installed,
                latestVersion: version,
                desc: desc ?? name?.first,
                homepage: homepage.flatMap(URL.init(string:)),
                isInstalled: installed != nil,
                isOutdated: outdated ?? false,
                isPinned: pinned ?? false,
                dependencies: [],
                installedOnRequest: true,
                installedTime: installTime,
                caskArtifacts: (artifacts ?? []).compactMap { artifact in
                    guard let apps = artifact.app, !apps.isEmpty else { return nil }
                    return CaskArtifact(appNames: apps, target: artifact.target)
                },
                caskDisplayNames: name ?? [],
                license: license,
                tap: tap,
                sourceURL: url.flatMap(URL.init(string:)),
                caveats: caveats,
                conflictsWith: conflictsWith?.all ?? [],
                isDeprecated: deprecated ?? false,
                deprecationReason: deprecationReason,
                deprecationDate: deprecationDate,
                isDisabled: disabled ?? false,
                disableReason: disableReason,
                disableDate: disableDate,
                autoUpdates: autoUpdates ?? false,
                sha256: sha256,
                caskDependsOn: depends
            )
        }
    }

    struct OutdatedRoot: Decodable {
        let formulae: [OutdatedFormula]
        let casks: [OutdatedCask]
    }

    struct OutdatedFormula: Decodable {
        let name: String
        let installedVersions: [String]?
        let currentVersion: String?
        let pinned: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
            case pinned
        }

        func asPackage() -> Package {
            Package(
                name: name,
                kind: .formula,
                version: installedVersions?.last,
                latestVersion: currentVersion,
                desc: nil,
                homepage: nil,
                isInstalled: true,
                isOutdated: true,
                isPinned: pinned ?? false,
                dependencies: [],
                installedOnRequest: true
            )
        }
    }

    struct OutdatedCask: Decodable {
        let name: String
        let installedVersions: [String]?
        let currentVersion: String?
        let pinned: Bool?

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
            case pinned
        }

        func asPackage() -> Package {
            Package(
                name: name,
                kind: .cask,
                version: installedVersions?.last,
                latestVersion: currentVersion,
                desc: nil,
                homepage: nil,
                isInstalled: true,
                isOutdated: true,
                isPinned: pinned ?? false,
                dependencies: [],
                installedOnRequest: true
            )
        }
    }

    static func decodeInfo(_ data: Data) throws -> [Package] {
        do {
            let root = try JSONDecoder().decode(InfoRoot.self, from: data)
            return root.formulae.map { $0.asPackage() } + root.casks.map { $0.asPackage() }
        } catch {
            throw BrewError.invalidJSON(error.localizedDescription)
        }
    }

    static func decodeOutdated(_ data: Data) throws -> [Package] {
        do {
            let root = try JSONDecoder().decode(OutdatedRoot.self, from: data)
            return root.formulae.map { $0.asPackage() } + root.casks.map { $0.asPackage() }
        } catch {
            throw BrewError.invalidJSON(error.localizedDescription)
        }
    }
}

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

        enum CodingKeys: String, CodingKey {
            case name
            case fullName = "full_name"
            case desc, homepage, versions, outdated, pinned, dependencies, installed
        }

        struct Versions: Decodable {
            let stable: String?
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
                installedTime: installTime
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

        enum CodingKeys: String, CodingKey {
            case token, name, desc, homepage, version, outdated, pinned, installed, artifacts
            case installedTime = "installed_time"
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
                caskDisplayNames: name ?? []
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

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
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
                isPinned: false,
                dependencies: [],
                installedOnRequest: true
            )
        }
    }

    struct OutdatedCask: Decodable {
        let name: String
        let installedVersions: [String]?
        let currentVersion: String?

        enum CodingKeys: String, CodingKey {
            case name
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
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
                isPinned: false,
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

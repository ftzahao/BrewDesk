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

        enum CodingKeys: String, CodingKey {
            case token, name, desc, homepage, version, outdated, pinned, installed
            case installedTime = "installed_time"
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
                installedTime: installTime
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

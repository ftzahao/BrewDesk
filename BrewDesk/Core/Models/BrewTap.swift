//
//  BrewTap.swift
//  BrewDesk
//

import Foundation

nonisolated struct BrewTap: Identifiable, Hashable, Sendable {
    var id: String { name }
    let name: String
    var isOfficial: Bool
    var isTrusted: Bool
    var formulaCount: Int?
    var caskCount: Int?
    var isInstalled: Bool
    var formulaNames: [String] = []
    var caskNames: [String] = []

    var canDelete: Bool { !isOfficial }
    var canInstall: Bool { isTrusted }
}

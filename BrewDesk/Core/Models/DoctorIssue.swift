//
//  DoctorIssue.swift
//  BrewDesk
//

import Foundation

nonisolated struct CleanupPreview: Sendable, Equatable {
    let lines: [String]
    let rawText: String

    var isEmpty: Bool { lines.isEmpty }

    var summary: String {
        if lines.isEmpty { return "没有可清理的内容" }
        return "预览将移除 \(lines.count) 项"
    }
}

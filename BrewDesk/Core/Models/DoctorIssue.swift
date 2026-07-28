//
//  DoctorIssue.swift
//  BrewDesk
//

import Foundation

nonisolated enum DoctorSeverity: String, Sendable, Hashable {
    case warning
    case error
    case info

    var title: String {
        switch self {
        case .warning: "警告"
        case .error: "错误"
        case .info: "信息"
        }
    }

    var systemImage: String {
        switch self {
        case .warning: "exclamationmark.triangle.fill"
        case .error: "xmark.octagon.fill"
        case .info: "info.circle.fill"
        }
    }
}

nonisolated struct DoctorIssue: Identifiable, Hashable, Sendable {
    let id: UUID
    let severity: DoctorSeverity
    let title: String
    let detail: String

    init(id: UUID = UUID(), severity: DoctorSeverity, title: String, detail: String) {
        self.id = id
        self.severity = severity
        self.title = title
        self.detail = detail
    }
}

nonisolated struct CleanupPreview: Sendable, Equatable {
    let lines: [String]
    let rawText: String

    var isEmpty: Bool { lines.isEmpty }

    var summary: String {
        if lines.isEmpty { return "没有可清理的内容" }
        return "预览将移除 \(lines.count) 项"
    }
}

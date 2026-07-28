//
//  BrewService.swift
//  BrewDesk
//

import Foundation

nonisolated enum BrewServiceStatus: String, Sendable, Hashable {
    case started
    case stopped
    case error
    case none
    case unknown

    init(raw: String) {
        switch raw.lowercased() {
        case "started", "running":
            self = .started
        case "stopped":
            self = .stopped
        case "error":
            self = .error
        case "none", "":
            self = .none
        default:
            // e.g. "started 123" or "error 1"
            let token = raw.split(separator: " ").first.map(String.init)?.lowercased() ?? raw.lowercased()
            switch token {
            case "started", "running": self = .started
            case "stopped": self = .stopped
            case "error": self = .error
            case "none": self = .none
            default: self = .unknown
            }
        }
    }

    var title: String {
        switch self {
        case .started: "运行中"
        case .stopped: "已停止"
        case .error: "错误"
        case .none: "未加载"
        case .unknown: "未知"
        }
    }

    var systemImage: String {
        switch self {
        case .started: "play.circle.fill"
        case .stopped: "stop.circle"
        case .error: "exclamationmark.triangle.fill"
        case .none: "circle"
        case .unknown: "questionmark.circle"
        }
    }
}

nonisolated struct BrewService: Identifiable, Hashable, Sendable {
    var id: String { name }

    let name: String
    var status: BrewServiceStatus
    var statusRaw: String
    var user: String?
    var file: String?
    var exitCode: Int?
}

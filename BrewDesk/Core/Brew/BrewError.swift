//
//  BrewError.swift
//  BrewDesk
//

import Foundation

enum BrewError: LocalizedError, Sendable {
    case notInstalled
    case executableMissing(URL)
    case nonZeroExit(command: String, code: Int32, stderr: String)
    case cancelled
    case invalidJSON(String)
    case busy

    var errorDescription: String? {
        switch self {
        case .notInstalled:
            return "未检测到 Homebrew。请先安装后再使用 BrewDesk。"
        case .executableMissing(let url):
            return "找不到 brew 可执行文件：\(url.path)"
        case .nonZeroExit(let command, let code, let stderr):
            let detail = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "命令失败（退出码 \(code)）：\(command)"
            }
            return "命令失败（退出码 \(code)）：\(command)\n\(detail)"
        case .cancelled:
            return "操作已取消"
        case .invalidJSON(let message):
            return "解析 brew 输出失败：\(message)"
        case .busy:
            return "已有 brew 任务在运行，请等待完成或取消后再试。"
        }
    }
}

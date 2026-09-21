//
//  TodoTask.swift
//  LifeTodoList
//

import Foundation
import SwiftData

enum TaskStatus: String, Codable {
    case pending    // 进行中
    case completed  // 已完成
    case archived   // 已归档（清除后）
}

@Model
final class TodoTask {
    var id: UUID
    var content: String
    var status: TaskStatus
    var order: Int
    var createdAt: Date
    var completedAt: Date?
    var archivedAt: Date?
    var claimedBy: String?
    var claimedAt: Date?
    var progressReport: String?
    var progressReportedAt: Date?
    var boardColumn: BoardColumn?

    var project: Project?

    init(
        id: UUID = UUID(),
        content: String,
        status: TaskStatus = .pending,
        order: Int = 0,
        createdAt: Date = Date(),
        completedAt: Date? = nil,
        archivedAt: Date? = nil,
        claimedBy: String? = nil,
        claimedAt: Date? = nil,
        progressReport: String? = nil,
        progressReportedAt: Date? = nil
    ) {
        self.id = id
        self.content = content
        self.status = status
        self.order = order
        self.createdAt = createdAt
        self.completedAt = completedAt
        self.archivedAt = archivedAt
        self.claimedBy = claimedBy
        self.claimedAt = claimedAt
        self.progressReport = progressReport
        self.progressReportedAt = progressReportedAt
    }

    /// 切换完成状态
    func toggleComplete() {
        if status == .pending {
            status = .completed
            completedAt = Date()
        } else if status == .completed {
            status = .pending
            completedAt = nil
        }
    }

    /// 归档任务（清除）
    func archive() {
        status = .archived
        archivedAt = Date()
    }

    /// 恢复任务
    func restore() {
        status = .pending
        archivedAt = nil
        completedAt = nil
    }
}

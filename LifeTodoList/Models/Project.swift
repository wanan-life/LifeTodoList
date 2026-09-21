//
//  Project.swift
//  LifeTodoList
//

import Foundation
import SwiftData

@Model
final class Project {
    var id: UUID
    var name: String
    var colorHex: String?
    var order: Int
    var isDefault: Bool
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \TodoTask.project)
    var tasks: [TodoTask] = []

    init(
        id: UUID = UUID(),
        name: String,
        colorHex: String? = nil,
        order: Int = 0,
        isDefault: Bool = false,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.colorHex = colorHex
        self.order = order
        self.isDefault = isDefault
        self.createdAt = createdAt
    }

    /// 获取活跃任务（未归档）
    var activeTasks: [TodoTask] {
        tasks.filter { $0.status != .archived }
            .sorted { $0.order < $1.order }
    }

    /// 获取未完成任务数量
    var pendingTasksCount: Int {
        tasks.filter { $0.status == .pending }.count
    }
}

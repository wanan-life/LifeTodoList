//
//  MCPServer.swift
//  LifeTodoList
//

import Foundation
import Network
import SwiftData
import Combine

@MainActor
final class MCPTaskStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func listProjects() throws -> [[String: Any]] {
        let projects = try fetchProjects()
        return projects.map(projectPayload)
    }

    func listTasks(status: String?, projectName: String?, includeArchived: Bool) throws -> [[String: Any]] {
        let statusFilter = try parseOptionalStatus(status)
        var tasks = try fetchTasks()

        if !includeArchived {
            tasks = tasks.filter { $0.status != .archived }
        }

        if let statusFilter {
            tasks = tasks.filter { $0.status == statusFilter }
        }

        if let projectName = projectName?.trimmingCharacters(in: .whitespacesAndNewlines), !projectName.isEmpty {
            tasks = tasks.filter { $0.project?.name == projectName }
        }

        return tasks.map(taskPayload)
    }

    func getTask(taskId: String) throws -> [String: Any] {
        return taskPayload(try findTask(taskId: taskId))
    }

    func createProject(name: String) throws -> [String: Any] {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            throw MCPServerError.invalidArguments("项目名称不能为空")
        }

        let context = modelContainer.mainContext
        let projects = try fetchProjects()
        let maxOrder = projects.map(\.order).max() ?? 0
        let project = Project(name: trimmedName, order: maxOrder + 1)
        context.insert(project)
        try context.save()
        return projectPayload(project)
    }

    func createTask(content: String, projectName: String?) throws -> [String: Any] {
        let trimmedContent = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedContent.isEmpty else {
            throw MCPServerError.invalidArguments("任务内容不能为空")
        }

        let context = modelContainer.mainContext
        let project = try findOrCreateProject(named: projectName)
        let maxOrder = project.tasks.map(\.order).max() ?? 0
        let task = TodoTask(content: trimmedContent, order: maxOrder + 1)
        task.project = project
        context.insert(task)
        try context.save()
        return taskPayload(task)
    }

    func claimTask(taskId: String, claimer: String?) throws -> [String: Any] {
        let task = try findTask(taskId: taskId)
        let trimmedClaimer = claimer?.trimmingCharacters(in: .whitespacesAndNewlines)
        task.claimedBy = trimmedClaimer?.isEmpty == false ? trimmedClaimer : "AI"
        task.claimedAt = Date()

        if task.status == .archived {
            task.status = .pending
            task.archivedAt = nil
        }

        try modelContainer.mainContext.save()
        return taskPayload(task)
    }

    func reportTask(taskId: String, report: String, status: String?) throws -> [String: Any] {
        let trimmedReport = report.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedReport.isEmpty else {
            throw MCPServerError.invalidArguments("report 不能为空")
        }

        let task = try findTask(taskId: taskId)
        task.progressReport = trimmedReport
        task.progressReportedAt = Date()

        if let status {
            task.status = try parseStatus(status)
            applyDates(for: task)
        }

        try modelContainer.mainContext.save()
        return taskPayload(task)
    }

    func completeTask(taskId: String, report: String?) throws -> [String: Any] {
        let task = try findTask(taskId: taskId)
        task.status = .completed
        task.completedAt = Date()
        task.archivedAt = nil

        if let report = report?.trimmingCharacters(in: .whitespacesAndNewlines), !report.isEmpty {
            task.progressReport = report
            task.progressReportedAt = Date()
        }

        try modelContainer.mainContext.save()
        return taskPayload(task)
    }

    func updateTaskStatus(taskId: String, status: String) throws -> [String: Any] {
        let context = modelContainer.mainContext
        let task = try findTask(taskId: taskId)
        task.status = try parseStatus(status)
        applyDates(for: task)

        try context.save()
        return taskPayload(task)
    }

    func progressSummary() throws -> [String: Any] {
        let projects = try fetchProjects()
        let tasks = try fetchTasks()

        let pendingCount = tasks.filter { $0.status == .pending }.count
        let completedCount = tasks.filter { $0.status == .completed }.count
        let archivedCount = tasks.filter { $0.status == .archived }.count
        let totalActive = pendingCount + completedCount
        let completionRate = totalActive == 0 ? 0 : Double(completedCount) / Double(totalActive)

        return [
            "totalTasks": tasks.count,
            "pendingTasks": pendingCount,
            "completedTasks": completedCount,
            "archivedTasks": archivedCount,
            "completionRate": completionRate,
            "projects": projects.map { project in
                [
                    "id": project.id.uuidString,
                    "name": project.name,
                    "pendingTasks": project.tasks.filter { $0.status == .pending }.count,
                    "completedTasks": project.tasks.filter { $0.status == .completed }.count,
                    "archivedTasks": project.tasks.filter { $0.status == .archived }.count
                ]
            }
        ]
    }

    private func fetchProjects() throws -> [Project] {
        let descriptor = FetchDescriptor<Project>(sortBy: [SortDescriptor(\Project.order)])
        return try modelContainer.mainContext.fetch(descriptor)
    }

    private func fetchTasks() throws -> [TodoTask] {
        let descriptor = FetchDescriptor<TodoTask>(sortBy: [SortDescriptor(\TodoTask.createdAt, order: .reverse)])
        return try modelContainer.mainContext.fetch(descriptor)
    }

    private func findTask(taskId: String) throws -> TodoTask {
        guard let uuid = UUID(uuidString: taskId) else {
            throw MCPServerError.invalidArguments("taskId 不是有效 UUID")
        }

        let tasks = try fetchTasks()
        guard let task = tasks.first(where: { $0.id == uuid }) else {
            throw MCPServerError.invalidArguments("未找到指定任务")
        }

        return task
    }

    private func parseOptionalStatus(_ status: String?) throws -> TaskStatus? {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines), !status.isEmpty else {
            return nil
        }
        return try parseStatus(status)
    }

    private func parseStatus(_ status: String) throws -> TaskStatus {
        guard let taskStatus = TaskStatus(rawValue: status) else {
            throw MCPServerError.invalidArguments("status 只能是 pending、completed 或 archived")
        }
        return taskStatus
    }

    private func applyDates(for task: TodoTask) {
        switch task.status {
        case .pending:
            task.completedAt = nil
            task.archivedAt = nil
        case .completed:
            task.completedAt = task.completedAt ?? Date()
            task.archivedAt = nil
        case .archived:
            task.archivedAt = task.archivedAt ?? Date()
        }
    }

    private func findOrCreateProject(named name: String?) throws -> Project {
        let trimmedName = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let projects = try fetchProjects()

        if let trimmedName, !trimmedName.isEmpty {
            if let existingProject = projects.first(where: { $0.name == trimmedName }) {
                return existingProject
            }

            let context = modelContainer.mainContext
            let maxOrder = projects.map(\.order).max() ?? 0
            let project = Project(name: trimmedName, order: maxOrder + 1)
            context.insert(project)
            return project
        }

        if let defaultProject = projects.first(where: { $0.isDefault }) {
            return defaultProject
        }

        let context = modelContainer.mainContext
        let inbox = Project(name: "收件箱", order: 0, isDefault: true)
        context.insert(inbox)
        return inbox
    }

    private func projectPayload(_ project: Project) -> [String: Any] {
        [
            "id": project.id.uuidString,
            "name": project.name,
            "order": project.order,
            "isDefault": project.isDefault,
            "pendingTasks": project.tasks.filter { $0.status == .pending }.count,
            "completedTasks": project.tasks.filter { $0.status == .completed }.count,
            "archivedTasks": project.tasks.filter { $0.status == .archived }.count
        ]
    }

    private func taskPayload(_ task: TodoTask) -> [String: Any] {
        [
            "id": task.id.uuidString,
            "content": task.content,
            "status": task.status.rawValue,
            "projectId": task.project?.id.uuidString ?? NSNull(),
            "projectName": task.project?.name ?? NSNull(),
            "createdAt": ISO8601DateFormatter().string(from: task.createdAt),
            "completedAt": task.completedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "archivedAt": task.archivedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "claimedBy": task.claimedBy ?? NSNull(),
            "claimedAt": task.claimedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull(),
            "progressReport": task.progressReport ?? NSNull(),
            "progressReportedAt": task.progressReportedAt.map { ISO8601DateFormatter().string(from: $0) } ?? NSNull()
        ]
    }
}

enum MCPServiceState: String {
    case stopped = "已关闭"
    case starting = "正在启动"
    case running = "运行中"
    case failed = "启动失败"
}

final class MCPServer: ObservableObject {
    @Published private(set) var state: MCPServiceState = .stopped
    @Published private(set) var errorMessage: String?

    var endpoint: String { "http://127.0.0.1:\(port)/mcp" }
    var toolCount: Int { toolDefinitions.count }

    private let port: UInt16
    private let taskStore: MCPTaskStore
    private let queue = DispatchQueue(label: "LifeTodoList.MCPServer")
    private var listener: NWListener?

    init(modelContainer: ModelContainer, port: UInt16 = 8765) {
        self.port = port
        self.taskStore = MCPTaskStore(modelContainer: modelContainer)
    }

    func start() {
        guard listener == nil else { return }
        state = .starting
        errorMessage = nil

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.acceptLocalOnly = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: .ipv4(.loopback),
                port: NWEndpoint.Port(rawValue: port)!
            )

            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] newState in
                DispatchQueue.main.async {
                    guard let self, let listener, self.listener === listener else { return }
                    switch newState {
                    case .ready:
                        self.state = .running
                    case .failed(let error):
                        self.state = .failed
                        self.errorMessage = error.localizedDescription
                        self.listener?.cancel()
                        self.listener = nil
                    default:
                        break
                    }
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            state = .failed
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        state = .stopped
        errorMessage = nil
    }

    private func handleConnection(_ connection: NWConnection) {
        var buffer = Data()
        connection.start(queue: queue)

        func receiveMore() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
                guard let self else { return }

                if let data {
                    buffer.append(data)
                }

                if let request = self.parseHTTPRequest(buffer) {
                    Task {
                        let rpcResponse = await self.handleRPCRequest(request.body)
                        await self.sendHTTPResponse(rpcResponse, on: connection)
                    }
                    return
                }

                if isComplete || error != nil {
                    self.sendHTTPResponse(.error(statusCode: 400, message: "Bad Request"), on: connection)
                    return
                }

                receiveMore()
            }
        }

        receiveMore()
    }

    private func parseHTTPRequest(_ data: Data) -> HTTPRequest? {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        let headerData = data[..<headerEnd.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else { return nil }

        let contentLength = headerText
            .components(separatedBy: "\r\n")
            .first(where: { $0.lowercased().hasPrefix("content-length:") })?
            .split(separator: ":", maxSplits: 1)
            .last
            .flatMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? 0

        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else { return nil }
        let body = data[bodyStart..<(bodyStart + contentLength)]
        return HTTPRequest(body: Data(body))
    }

    private func handleRPCRequest(_ body: Data) async -> MCPHTTPResponse {
        do {
            let json = try JSONSerialization.jsonObject(with: body)
            guard let request = json as? [String: Any] else {
                throw MCPServerError.invalidRequest("请求体必须是 JSON object")
            }

            guard let method = request["method"] as? String else {
                throw MCPServerError.invalidRequest("缺少 method")
            }

            if method == "notifications/initialized" {
                return .empty
            }

            let id = request["id"] ?? NSNull()
            let result = try await handleMethod(method, params: request["params"])
            return .json([
                "jsonrpc": "2.0",
                "id": id,
                "result": result
            ])
        } catch let error as MCPServerError {
            return .json(error.jsonRPCResponse)
        } catch {
            return .json(MCPServerError.internalError(error.localizedDescription).jsonRPCResponse)
        }
    }

    private func handleMethod(_ method: String, params: Any?) async throws -> [String: Any] {
        switch method {
        case "initialize":
            return [
                "protocolVersion": "2025-06-18",
                "capabilities": [
                    "tools": [
                        "listChanged": false
                    ]
                ],
                "serverInfo": [
                    "name": "LifeTodoList",
                    "version": "1.0.0"
                ]
            ]
        case "tools/list":
            return ["tools": toolDefinitions]
        case "tools/call":
            return try callTool(params: params)
        default:
            throw MCPServerError.methodNotFound(method)
        }
    }

    @MainActor
    private func callTool(params: Any?) throws -> [String: Any] {
        guard
            let params = params as? [String: Any],
            let name = params["name"] as? String
        else {
            throw MCPServerError.invalidArguments("tools/call 需要 name")
        }

        let arguments = params["arguments"] as? [String: Any] ?? [:]
        let structuredContent: [String: Any]

        switch name {
        case "list_projects":
            structuredContent = ["projects": try taskStore.listProjects()]
        case "list_tasks":
            structuredContent = [
                "tasks": try taskStore.listTasks(
                    status: arguments["status"] as? String,
                    projectName: arguments["projectName"] as? String,
                    includeArchived: arguments["includeArchived"] as? Bool ?? false
                )
            ]
        case "get_task":
            guard let taskId = arguments["taskId"] as? String else {
                throw MCPServerError.invalidArguments("get_task 需要 taskId")
            }
            structuredContent = ["task": try taskStore.getTask(taskId: taskId)]
        case "create_project":
            guard let projectName = arguments["name"] as? String else {
                throw MCPServerError.invalidArguments("create_project 需要 name")
            }
            structuredContent = ["project": try taskStore.createProject(name: projectName)]
        case "create_task":
            guard let content = arguments["content"] as? String else {
                throw MCPServerError.invalidArguments("create_task 需要 content")
            }
            structuredContent = [
                "task": try taskStore.createTask(
                    content: content,
                    projectName: arguments["projectName"] as? String
                )
            ]
        case "update_task_status":
            guard
                let taskId = arguments["taskId"] as? String,
                let status = arguments["status"] as? String
            else {
                throw MCPServerError.invalidArguments("update_task_status 需要 taskId 和 status")
            }
            structuredContent = ["task": try taskStore.updateTaskStatus(taskId: taskId, status: status)]
        case "claim_task":
            guard let taskId = arguments["taskId"] as? String else {
                throw MCPServerError.invalidArguments("claim_task 需要 taskId")
            }
            structuredContent = [
                "task": try taskStore.claimTask(
                    taskId: taskId,
                    claimer: arguments["claimer"] as? String
                )
            ]
        case "report_task":
            guard
                let taskId = arguments["taskId"] as? String,
                let report = arguments["report"] as? String
            else {
                throw MCPServerError.invalidArguments("report_task 需要 taskId 和 report")
            }
            structuredContent = [
                "task": try taskStore.reportTask(
                    taskId: taskId,
                    report: report,
                    status: arguments["status"] as? String
                )
            ]
        case "complete_task":
            guard let taskId = arguments["taskId"] as? String else {
                throw MCPServerError.invalidArguments("complete_task 需要 taskId")
            }
            structuredContent = [
                "task": try taskStore.completeTask(
                    taskId: taskId,
                    report: arguments["report"] as? String
                )
            ]
        case "progress_summary":
            structuredContent = try taskStore.progressSummary()
        default:
            throw MCPServerError.invalidArguments("未知工具: \(name)")
        }

        return [
            "content": [
                [
                    "type": "text",
                    "text": mcpResultText(for: name, structuredContent: structuredContent)
                ]
            ],
            "structuredContent": structuredContent,
            "isError": false
        ]
    }

    private var toolDefinitions: [[String: Any]] {
        [
            [
                "name": "list_projects",
                "description": "列出 LifeTodoList 中的所有项目和每个项目的任务数量。",
                "inputSchema": objectSchema(properties: [:], required: [])
            ],
            [
                "name": "list_tasks",
                "description": "列出任务。默认不包含已归档任务，可按状态和项目名称筛选。",
                "inputSchema": objectSchema(
                    properties: [
                        "status": [
                            "type": "string",
                            "enum": ["pending", "completed", "archived"],
                            "description": "按任务状态筛选，可选"
                        ],
                        "projectName": [
                            "type": "string",
                            "description": "按项目名称筛选，可选"
                        ],
                        "includeArchived": [
                            "type": "boolean",
                            "description": "是否包含已归档任务，默认 false"
                        ]
                    ],
                    required: []
                )
            ],
            [
                "name": "get_task",
                "description": "按任务 UUID 获取单个任务详情。",
                "inputSchema": objectSchema(
                    properties: [
                        "taskId": [
                            "type": "string",
                            "description": "任务 UUID"
                        ]
                    ],
                    required: ["taskId"]
                )
            ],
            [
                "name": "create_project",
                "description": "创建一个新的任务项目。",
                "inputSchema": objectSchema(
                    properties: [
                        "name": [
                            "type": "string",
                            "description": "项目名称"
                        ]
                    ],
                    required: ["name"]
                )
            ],
            [
                "name": "create_task",
                "description": "在指定项目中创建任务；如果项目不存在会自动创建。不传项目时使用默认收件箱。",
                "inputSchema": objectSchema(
                    properties: [
                        "content": [
                            "type": "string",
                            "description": "任务内容"
                        ],
                        "projectName": [
                            "type": "string",
                            "description": "目标项目名称，可选"
                        ]
                    ],
                    required: ["content"]
                )
            ],
            [
                "name": "update_task_status",
                "description": "更新任务状态，用于 AI 管理任务进度。",
                "inputSchema": objectSchema(
                    properties: [
                        "taskId": [
                            "type": "string",
                            "description": "任务 UUID"
                        ],
                        "status": [
                            "type": "string",
                            "enum": ["pending", "completed", "archived"],
                            "description": "目标状态"
                        ]
                    ],
                    required: ["taskId", "status"]
                )
            ],
            [
                "name": "claim_task",
                "description": "领取一个任务，记录领取人和领取时间。如果任务已归档，会恢复为进行中。",
                "inputSchema": objectSchema(
                    properties: [
                        "taskId": [
                            "type": "string",
                            "description": "任务 UUID"
                        ],
                        "claimer": [
                            "type": "string",
                            "description": "领取人名称，可选；默认 AI"
                        ]
                    ],
                    required: ["taskId"]
                )
            ],
            [
                "name": "report_task",
                "description": "报告任务进度，记录最近一次进度说明，并可同时更新任务状态。",
                "inputSchema": objectSchema(
                    properties: [
                        "taskId": [
                            "type": "string",
                            "description": "任务 UUID"
                        ],
                        "report": [
                            "type": "string",
                            "description": "进度报告内容"
                        ],
                        "status": [
                            "type": "string",
                            "enum": ["pending", "completed", "archived"],
                            "description": "可选，同时更新任务状态"
                        ]
                    ],
                    required: ["taskId", "report"]
                )
            ],
            [
                "name": "complete_task",
                "description": "完成任务，并可附带最终进度报告。",
                "inputSchema": objectSchema(
                    properties: [
                        "taskId": [
                            "type": "string",
                            "description": "任务 UUID"
                        ],
                        "report": [
                            "type": "string",
                            "description": "最终报告，可选"
                        ]
                    ],
                    required: ["taskId"]
                )
            ],
            [
                "name": "progress_summary",
                "description": "获取任务管理进度汇总，包括总数、进行中、已完成、已归档和完成率。",
                "inputSchema": objectSchema(properties: [:], required: [])
            ]
        ]
    }

    private func objectSchema(properties: [String: Any], required: [String]) -> [String: Any] {
        [
            "type": "object",
            "properties": properties,
            "required": required,
            "additionalProperties": false
        ]
    }

    private func mcpResultText(for toolName: String, structuredContent: [String: Any]) -> String {
        switch toolName {
        case "list_tasks":
            return "任务列表已生成"
        case "get_task":
            return "任务详情已获取"
        case "create_task":
            return "任务已创建"
        case "create_project":
            return "项目已创建"
        case "update_task_status":
            return "任务状态已更新"
        case "claim_task":
            return "任务已领取"
        case "report_task":
            return "任务进度已报告"
        case "complete_task":
            return "任务已完成"
        case "progress_summary":
            return "任务进度汇总已生成"
        default:
            return "操作完成"
        }
    }

    private func sendHTTPResponse(_ response: MCPHTTPResponse, on connection: NWConnection) {
        let data = response.data
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}

private struct HTTPRequest {
    let body: Data
}

private enum MCPHTTPResponse {
    case empty
    case json([String: Any])
    case error(statusCode: Int, message: String)

    var data: Data {
        switch self {
        case .empty:
            return Data("HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n".utf8)
        case .json(let payload):
            let body = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data()
            return http(status: "200 OK", contentType: "application/json", body: body)
        case .error(let statusCode, let message):
            let body = Data(message.utf8)
            return http(status: "\(statusCode) Error", contentType: "text/plain; charset=utf-8", body: body)
        }
    }

    private func http(status: String, contentType: String, body: Data) -> Data {
        var response = Data()
        response.append(Data("HTTP/1.1 \(status)\r\n".utf8))
        response.append(Data("Content-Type: \(contentType)\r\n".utf8))
        response.append(Data("Content-Length: \(body.count)\r\n".utf8))
        response.append(Data("Connection: close\r\n\r\n".utf8))
        response.append(body)
        return response
    }
}

private enum MCPServerError: Error {
    case invalidRequest(String)
    case invalidArguments(String)
    case methodNotFound(String)
    case internalError(String)

    var jsonRPCResponse: [String: Any] {
        [
            "jsonrpc": "2.0",
            "id": NSNull(),
            "error": [
                "code": code,
                "message": message
            ]
        ]
    }

    private var code: Int {
        switch self {
        case .invalidRequest:
            return -32600
        case .methodNotFound:
            return -32601
        case .invalidArguments:
            return -32602
        case .internalError:
            return -32603
        }
    }

    private var message: String {
        switch self {
        case .invalidRequest(let message),
             .invalidArguments(let message),
             .methodNotFound(let message),
             .internalError(let message):
            return message
        }
    }
}

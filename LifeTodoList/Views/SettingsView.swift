import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var coordinator: AppCoordinator
    @AppStorage("statusBarMode") private var statusBarMode = "menuBar"
    @AppStorage("quitOnWindowClose") private var quitOnWindowClose = false
    @AppStorage("mcpEnabled") private var mcpEnabled = true
    @State private var selectedTab = SettingsTab.general

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("设置")
                    .font(.title2.weight(.semibold))
                Spacer()
                Picker("设置页面", selection: $selectedTab) {
                    ForEach(SettingsTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 210)
            }
            .padding(.horizontal, 28)
            .padding(.top, 24)
            .padding(.bottom, 18)

            Divider()

            Form {
                switch selectedTab {
                case .general:
                    Section("状态栏") {
                        Picker("点击图标时", selection: $statusBarMode) {
                            Label("下拉待办", systemImage: "list.bullet.indent").tag("menuBar")
                            Label("打开窗口", systemImage: "macwindow").tag("window")
                        }
                        .pickerStyle(.radioGroup)
                    }
                    Section {
                        Toggle("点击关闭按钮时退出应用", isOn: $quitOnWindowClose)
                    } header: {
                        Text("窗口")
                    } footer: {
                        Text(quitOnWindowClose ? "关闭窗口会退出 LifeTodo。" : "关闭时收起窗口，应用仍在状态栏运行。")
                    }
                case .mcp:
                    Section("MCP 服务") {
                        Toggle("启用 MCP 服务", isOn: $mcpEnabled)
                            .onChange(of: mcpEnabled) { _, enabled in
                                coordinator.updateMCP(enabled: enabled)
                            }
                        MCPStatusView(server: coordinator.mcpServer)
                    }
                    Section("连接信息") {
                        LabeledContent("传输方式", value: "本机 HTTP")
                        LabeledContent("地址", value: coordinator.mcpServer.endpoint)
                        LabeledContent("工具数量", value: "\(coordinator.mcpServer.toolCount)")
                        Button {
                            let pasteboard = NSPasteboard.general
                            pasteboard.clearContents()
                            pasteboard.setString(connectionConfiguration, forType: .string)
                        } label: {
                            Label("复制 MCP 配置", systemImage: "doc.on.doc")
                        }
                        .disabled(!mcpEnabled)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(.regularMaterial)
    }

    private var connectionConfiguration: String {
        """
        {
          "mcpServers": {
            "LifeTodoList": {
              "type": "http",
              "url": "\(coordinator.mcpServer.endpoint)"
            }
          }
        }
        """
    }
}

private enum SettingsTab: String, CaseIterable, Identifiable {
    case general
    case mcp

    var id: Self { self }
    var title: String {
        switch self {
        case .general: "通用"
        case .mcp: "MCP"
        }
    }
}

private struct MCPStatusView: View {
    @ObservedObject var server: MCPServer

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(server.state.rawValue)
            if let message = server.errorMessage {
                Text(message)
                    .foregroundStyle(.red)
                    .lineLimit(2)
            }
        }
    }

    private var statusColor: Color {
        switch server.state {
        case .running: .green
        case .starting: .orange
        case .stopped: .secondary
        case .failed: .red
        }
    }
}

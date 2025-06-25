//
//  ContentView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

struct ContentView: View {
    @State private var selectedTool: NetworkTool? = nil
    
    var body: some View {
#if os(macOS)
        NavigationSplitView {
            ToolsList(selectedTool: $selectedTool)
        } detail: {
            if let tool = selectedTool {
                switch tool {
                case .ping:
                    PingView()
                case .traceroute:
                    TracerouteView()
                case .about:
                    AboutView()
                }
            } else {
                Text("Select a tool from the sidebar")
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
#else
        NavigationStack {
            ToolsList(selectedTool: $selectedTool)
        }
#endif
    }
}

struct ToolsList: View {
    @Binding var selectedTool: NetworkTool?
    
    var body: some View {
        List(NetworkTool.allCases, selection: $selectedTool) { tool in
#if os(macOS)
            Label(tool.title, systemImage: tool.icon)
                .tag(tool)
#else
            NavigationLink(destination: destinationView(for: tool)) {
                Label(tool.title, systemImage: tool.icon)
            }
#endif
        }
        .navigationTitle("NETo")
#if os(macOS)
        .listStyle(SidebarListStyle())
#endif
    }
    
#if os(iOS)
    @ViewBuilder
    private func destinationView(for tool: NetworkTool) -> some View {
        switch tool {
        case .ping:
            PingView()
        case .traceroute:
            TracerouteView()
        case .about:
            AboutView()
        }
    }
#endif
}

enum NetworkTool: String, CaseIterable, Identifiable {
    case ping = "ping"
    case traceroute = "traceroute"
    case about = "about"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ping:
            return "Ping"
        case .traceroute:
            return "Traceroute"
        case .about:
            return "About"
        }
    }
    
    var icon: String {
        switch self {
        case .ping:
            return "network"
        case .traceroute:
            return "point.topleft.down.curvedto.point.bottomright.up"
        case .about:
            return "info.circle"
        }
    }
}

#Preview {
    ContentView()
}

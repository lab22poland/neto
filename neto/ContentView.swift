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
        NavigationSplitView {
            ToolsList(selectedTool: $selectedTool)
        } detail: {
            if let tool = selectedTool {
                switch tool {
                case .ping:
                    PingView()
                case .traceroute:
                    TracerouteView()
                case .whois:
                    WhoisView()
                case .arp:
                    ArpView()
                case .about:
                    AboutView()
                }
            } else {
                Text("Select a tool from the sidebar")
                    .foregroundColor(.secondary)
            }
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 250)
    }
}

struct ToolsList: View {
    @Binding var selectedTool: NetworkTool?
    
    var body: some View {
        List(NetworkTool.allCases, selection: $selectedTool) { tool in
            Label(tool.title, systemImage: tool.icon)
                .tag(tool)
        }
        .navigationTitle("NETo")
        .listStyle(SidebarListStyle())
    }
}

enum NetworkTool: String, CaseIterable, Identifiable {
    case ping = "ping"
    case traceroute = "traceroute"
    case whois = "whois"
    case arp = "arp"
    case about = "about"
    
    var id: String { rawValue }
    
    var title: String {
        switch self {
        case .ping:
            return "Ping"
        case .traceroute:
            return "Traceroute"
        case .whois:
            return "WHOIS"
        case .arp:
            return "ARP"
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
        case .whois:
            return "doc.text.magnifyingglass"
        case .arp:
            return "table"
        case .about:
            return "info.circle"
        }
    }
}

#Preview {
    ContentView()
}

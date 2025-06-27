//
//  AboutView.swift
//  neto
//
//  Created by Sergii Solianyk on 21/06/2025.
//  © 2025 Lab22 Poland Sp. z o.o.
//

import SwiftUI

struct AboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Image(systemName: "network")
                            .font(.system(size: 48))
                            .foregroundColor(.accentColor)
                        
                        VStack(alignment: .leading) {
                            Text("NETo")
                                .font(.largeTitle)
                                .fontWeight(.bold)
                            
                            Text("Network Engineer Tools")
                                .font(.title2)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Text("Version 1.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("About NETo")
                        .font(.headline)
                    
                    Text("NETo (Network Engineer Tools) is a multiplatform SwiftUI application designed specifically for network engineers and IT professionals. This powerful suite of tools provides essential utilities for network management, troubleshooting, and diagnostics.")
                        .font(.body)
                        .lineSpacing(4)
                    
                    Text("Built with modern Swift and SwiftUI technologies, NETo offers a native experience across iPhone, iPad, and macOS platforms, ensuring you have the tools you need wherever you work.")
                        .font(.body)
                        .lineSpacing(4)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Current Tools")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Image(systemName: "network")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("Ping Tool - Send ICMP echo packets to test network connectivity")
                        }
                        .font(.body)
                        
                        HStack {
                            Image(systemName: "point.topleft.down.curvedto.point.bottomright.up")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("Traceroute Tool - Discover the network path to a destination")
                        }
                        .font(.body)
                        
                        HStack {
                            Image(systemName: "doc.text.magnifyingglass")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("WHOIS Tool - RFC 3912 compliant queries for domains, IP addresses, AS numbers, and person/organization records (FreeBSD compatible)")
                        }
                        .font(.body)
                    }
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Platform Support")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Image(systemName: "iphone")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("iPhone (iOS 17.0+)")
                        }
                        
                        HStack {
                            Image(systemName: "ipad")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("iPad (iPadOS 17.0+)")
                        }
                        
                        HStack {
                            Image(systemName: "macbook")
                                .foregroundColor(.accentColor)
                                .frame(width: 20)
                            Text("macOS (14.0+)")
                        }
                    }
                    .font(.body)
                }
                
                Divider()
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Technologies")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text("• Swift 5.0+")
                        Text("• SwiftUI Framework")
                        Text("• Network Framework")
                        Text("• Multiplatform Architecture")
                    }
                    .font(.body)
                }
                
                Spacer(minLength: 40)
                
                VStack(spacing: 8) {
                    Text("© 2025 Lab22 Poland Sp. z o.o.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Text("sergii.solyanik@lab22.pl")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("Built for Network Engineers")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
            }
            .padding()
        }
        .navigationTitle("About")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
    }
}

#Preview {
    NavigationStack {
        AboutView()
    }
} 
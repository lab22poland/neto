# NETo - Network Engineer Tools

**© 2025, Lab22 Poland Sp. z o.o.** | `info@lab22.pl`

A powerful multiplatform SwiftUI application designed specifically for network engineers, providing essential tools and utilities for network management, troubleshooting, and diagnostics.

## 🌟 Overview

NETo (Network Engineer Tools) brings professional-grade network utilities to your fingertips across iPhone, iPad, and macOS platforms. Built with modern SwiftUI architecture, it offers a native experience on all Apple devices while maintaining feature parity and performance.

## ✨ Features

### 🔍 Network Diagnostics
- **Ping Tool**: Advanced ping functionality with real-time results
- **Traceroute Tool**: Network path discovery and hop-by-hop analysis
- **WHOIS Tool**: RFC 3912 compliant queries (FreeBSD whois.c compatible)
  - Domain registration information (gTLDs, ccTLDs, new gTLDs)
  - IP address allocation details (IPv4/IPv6 with RIR routing)
  - AS number information and network prefixes
  - Person/organization contact records
  - Direct TCP port 43 connections with proper server selection
- **Network Reachability**: Test connectivity to any host or IP address
- **Multi-protocol Support**: UDP and TCP connectivity testing
- **Detailed Results**: Comprehensive statistics and error reporting

### 📱 Multiplatform Support
- **iPhone**: Optimized portrait and landscape interfaces
- **iPad**: Adaptive split-view navigation for enhanced productivity  
- **macOS**: Full desktop experience with native menu integration

### 🛡️ Enterprise-Ready
- **App Sandbox**: Secure execution environment
- **Network Entitlements**: Proper permissions for network operations
- **Code Signing**: Support for both development and distribution

## 🔧 Technical Specifications

### Requirements
- **iOS/iPadOS**: 17.0+ (required for SwiftData)
- **macOS**: 14.0+ (required for SwiftData)
- **Xcode**: 16.4+ for development
- **Swift**: 5.0+

### Architecture
- **Framework**: SwiftUI with MVVM pattern
- **Data Persistence**: SwiftData for cross-platform compatibility
- **Network Stack**: Network.framework for modern networking
- **Async/Await**: Modern Swift concurrency for responsive UI

### WHOIS Implementation Standards
- **RFC 3912 Compliance**: Direct TCP port 43 connections
- **FreeBSD Compatibility**: Exact server selection logic from FreeBSD whois.c
- **Multi-Object Support**: Domains, IP addresses, AS numbers, person/org records
- **Character Encoding**: UTF-8, ASCII, and ISO-Latin-1 fallback support
- **Server-Specific Formatting**: Proper query formatting for different WHOIS servers
- **Referral Following**: Automatic redirect detection and recursion

### Bundle Information
- **Bundle Identifier**: `pl.lab22.neto`
- **Deployment Targets**: iOS 17.0+, macOS 14.0+
- **Code Signing**: Automatic signing for development

## 🚀 Getting Started

### Prerequisites
```bash
# Ensure you have Xcode 16.4+ installed
xcode-select --version

# Clone the repository
git clone [repository-url]
cd neto/neto
```

### Building the Project
```bash
# Build for macOS
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS' build

# Build for iOS Simulator
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Open in Xcode
open neto.xcodeproj
```

### Running the Application
- **macOS**: Run directly from Xcode or build artifacts
- **iOS Simulator**: Use Xcode's built-in simulator
- **Physical Devices**: Requires Apple Developer account for code signing

## 🎯 Usage

### Ping Tool
1. Launch NETo application
2. Navigate to "Ping" from the main menu
3. Enter target hostname or IP address (e.g., `google.com`, `8.8.8.8`)
4. Tap "Start Ping" to begin connectivity testing
5. View real-time results and statistics

### Traceroute Tool
1. Select "Traceroute" from the main menu
2. Enter destination hostname or IP address
3. Tap "Start Traceroute" to trace network path
4. Monitor hop-by-hop progress and latency

### WHOIS Tool
1. Navigate to "WHOIS" from the main menu
2. Enter query target:
   - **Domains**: `google.com`, `example.org`
   - **IP Addresses**: `8.8.8.8`, `2001:4860:4860::8888`
   - **AS Numbers**: `AS15169`, `AS32934`
   - **Contacts**: Person/organization handles
3. Tap "Perform WHOIS Lookup" to query registration information
4. View detailed results including registrar, dates, name servers, and network details

### Network Testing
- Test both IPv4 and IPv6 addresses
- Monitor connection latency and success rates
- Identify network connectivity issues
- Export results for reporting

## 🏗️ Development

### Project Structure
```
neto/                         # Xcode project directory (current location)
├── neto/                     # Application source code
│   ├── netoApp.swift          # App entry point
│   ├── ContentView.swift      # Main navigation
│   ├── PingView.swift         # Ping tool implementation
│   ├── AboutView.swift        # Application information
│   ├── neto.entitlements      # Security permissions
│   └── Assets.xcassets/       # App resources
├── neto.xcodeproj/           # Xcode project
├── netoTests/                # Unit tests
├── netoUITests/              # UI tests
├── LICENSE                   # BSD 3-Clause License (app bundle)
└── README.md                 # This file
```

### Key Components
- **PingView**: Advanced network connectivity testing
- **TracerouteView**: Network path discovery and analysis
- **WhoisView & WhoisManager**: RFC 3912 compliant WHOIS queries
  - FreeBSD whois.c compatible implementation
  - Multi-object support (domains, IPs, AS numbers, contacts)
  - Direct TCP port 43 connections with server-specific formatting
- **Network Framework**: Modern networking with proper error handling
- **SwiftUI Navigation**: Platform-adaptive interface design
- **Entitlements**: Secure network access permissions

## 🤖 AI-Powered Development

This application was created using **AI-assisted development** with:
- **[Cursor](https://cursor.sh/)**: AI-powered code editor
- **[Claude Sonnet 4](https://www.anthropic.com/claude)**: Advanced AI coding assistant

The AI tools helped with:
- 🏗️ **Architecture Design**: SwiftUI MVVM patterns and multiplatform considerations
- 🔧 **Code Generation**: Swift implementation with modern async/await patterns  
- 🐛 **Bug Fixing**: Network permission issues and App Sandbox configuration
- 📚 **Documentation**: Comprehensive code comments and this README
- ✅ **Testing**: Cross-platform build verification and functionality testing

## 📄 License

This project is licensed under the **BSD 3-Clause License**.

```
Copyright (c) 2025, Lab22 Poland Sp. z o.o.
All rights reserved.
```

See [LICENSE](LICENSE) file for complete license terms.

## 👨‍💻 Author

**Sergii Solianyk**  
📧 sergii.solyanik@lab22.pl  
🏢 Lab22 Poland Sp. z o.o.

## 🔮 Roadmap

### ✅ **Implemented Features**
- **Ping Tool**: ICMP connectivity testing
- **Traceroute Tool**: Network path analysis  
- **WHOIS Tool**: RFC 3912 compliant queries (FreeBSD compatible)

### 🚧 **In Development**
- [ ] **DNS Lookup**: Domain name resolution tools
- [ ] **Port Scanner**: TCP/UDP port connectivity testing

### 📋 **Planned Features**
- [ ] **ARP Lookup**: Address Resolution Protocol table inspection
- [ ] **Wake-on-LAN**: Remote device wake-up functionality
- [ ] **Nmap Integration**: Network mapping and security scanning
- [ ] **Network Monitoring**: Continuous connectivity monitoring
- [ ] **Export Features**: CSV/PDF report generation

## 🤝 Contributing

This project follows Lab22 Poland development standards. For contributions:

1. Follow Swift API Design Guidelines
2. Maintain multiplatform compatibility
3. Include comprehensive tests
4. Update documentation
5. Respect BSD 3-Clause License terms

## 🆘 Support

For technical support or questions:
- 📧 Email: sergii.solyanik@lab22.pl
- 🏢 Company: Lab22 Poland Sp. z o.o.

---

**NETo** - Professional Network Tools for the Modern Engineer 
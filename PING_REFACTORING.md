# Ping Functionality Refactoring

## Overview

This document describes the refactoring of the ping functionality in the NETo application, replacing the Network framework-based approach with a proper ICMP implementation based on Apple's SimplePing sample code.

## Background

### Previous Implementation

The original ping functionality used the Network framework with UDP connections to simulate ping behavior. While this approach worked within Apple's sandbox constraints, it had several limitations:

- **Not true ICMP**: Used UDP instead of ICMP echo requests/responses
- **Limited accuracy**: Response times were not as precise as native ping
- **Sandbox restrictions**: Relied on Network framework limitations
- **Inconsistent behavior**: Different from standard ping tools

### New Implementation

The refactored implementation uses a modern Swift version of Apple's SimplePing sample code, providing:

- **True ICMP**: Proper ICMP echo request/response handling
- **Better accuracy**: More precise response time measurements
- **Enhanced features**: Configurable payload size, timeout, and interval
- **Statistics**: Packet loss, min/max/average response times
- **Cross-platform**: Works on iOS, iPadOS, and macOS

## Architecture

### Core Components

#### 1. SimplePing.swift
The core ICMP implementation based on Apple's SimplePing sample code:

```swift
final class SimplePing: NSObject {
    protocol Delegate: AnyObject {
        func simplePing(_ pinger: SimplePing, didStartWithAddress address: Data)
        func simplePing(_ pinger: SimplePing, didFailWithError error: Error)
        func simplePing(_ pinger: SimplePing, didSendPacket packet: Data, sequenceNumber: UInt16)
        func simplePing(_ pinger: SimplePing, didFailToSendPacket packet: Data, sequenceNumber: UInt16, error: Error)
        func simplePing(_ pinger: SimplePing, didReceivePingResponsePacket packet: Data, sequenceNumber: UInt16)
        func simplePing(_ pinger: SimplePing, didReceiveUnexpectedPacket packet: Data)
    }
}
```

**Key Features:**
- ICMP header construction and parsing
- Checksum calculation
- Socket management for ICMP communication
- Asynchronous packet sending and receiving
- Error handling and timeout management

#### 2. PingManagerV2.swift
Enhanced ping manager that uses SimplePing:

```swift
final class PingManagerV2: NSObject {
    struct PingConfig {
        let count: Int
        let interval: TimeInterval
        let timeout: TimeInterval
        let payloadSize: Int
    }
}
```

**Key Features:**
- Configurable ping parameters
- Sequence number management
- Response time calculation
- Timeout handling
- Task cancellation support

#### 3. PingViewModelV2.swift
Enhanced view model with statistics:

```swift
@MainActor
final class PingViewModelV2: ObservableObject {
    var pingStatistics: PingStatistics {
        // Calculates packet loss, min/max/avg response times
    }
}
```

**Key Features:**
- Ping statistics calculation
- Configuration management
- Error handling
- UI state management

#### 4. PingViewV2.swift
Enhanced UI with configuration options and statistics:

```swift
struct PingViewV2: View {
    // Configuration panel
    // Statistics display
    // Enhanced results view
}
```

**Key Features:**
- Configurable ping parameters
- Real-time statistics display
- Enhanced results formatting
- Configuration panel

## Usage

### Basic Usage

```swift
let pingManager = PingManagerV2()

let task = pingManager.performPing(
    to: "8.8.8.8",
    onResult: { result in
        print("Ping result: \(result.message)")
    },
    onComplete: {
        print("Ping completed")
    }
)

// Cancel when needed
task.cancel()
```

### Advanced Usage with Configuration

```swift
let config = PingManagerV2.PingConfig(
    count: 10,
    interval: 0.5,
    timeout: 3.0,
    payloadSize: 128
)

let task = pingManager.performPing(
    to: "google.com",
    config: config,
    onResult: { result in
        // Handle individual ping results
    },
    onComplete: {
        // Handle completion
    }
)
```

### Using the Enhanced View

```swift
struct ContentView: View {
    var body: some View {
        NavigationView {
            PingViewV2()
        }
    }
}
```

## Configuration Options

### PingConfig Parameters

| Parameter | Default | Range | Description |
|-----------|---------|-------|-------------|
| `count` | 5 | 1-20 | Number of ping packets to send |
| `interval` | 1.0s | 0.1-5.0s | Interval between pings |
| `timeout` | 5.0s | 1.0-30.0s | Timeout for each ping |
| `payloadSize` | 56 bytes | 32-1024 bytes | ICMP payload size |

### Statistics

The enhanced implementation provides comprehensive statistics:

- **Total packets**: Number of packets sent
- **Success count**: Number of successful responses
- **Failure count**: Number of failed/timeout responses
- **Packet loss**: Percentage of lost packets
- **Response times**: Minimum, maximum, and average response times

## Testing

### Unit Tests

Comprehensive unit tests are provided:

- `SimplePingTests.swift`: Tests for the core ICMP implementation
- `PingManagerV2Tests.swift`: Tests for the ping manager
- Integration tests for various scenarios
- Performance tests for optimization

### Test Coverage

- Initialization and lifecycle
- Error handling
- Configuration validation
- Network connectivity
- Performance benchmarks
- Edge cases and timeouts

## Migration Guide

### From Old Implementation

1. **Replace PingManager with PingManagerV2**
   ```swift
   // Old
   let manager = PingManager()
   
   // New
   let manager = PingManagerV2()
   ```

2. **Update method calls**
   ```swift
   // Old
   manager.performPing(to: host, onResult: onResult, onComplete: onComplete)
   
   // New
   manager.performPing(to: host, config: config, onResult: onResult, onComplete: onComplete)
   ```

3. **Update ViewModels**
   ```swift
   // Old
   @StateObject private var viewModel = PingViewModel()
   
   // New
   @StateObject private var viewModel = PingViewModelV2()
   ```

4. **Update Views**
   ```swift
   // Old
   PingView()
   
   // New
   PingViewV2()
   ```

## Platform Compatibility

### iOS/iPadOS
- Requires network permissions in Info.plist
- Works within app sandbox constraints
- Supports both IPv4 and IPv6

### macOS
- Requires network permissions in entitlements
- Works with App Sandbox enabled
- Full ICMP functionality available

### Entitlements

Add the following to your entitlements file:

```xml
<key>com.apple.security.network.client</key>
<true/>
```

## Performance Considerations

### Memory Usage
- Efficient packet handling with minimal memory allocation
- Proper cleanup of resources
- No memory leaks in long-running operations

### Battery Usage
- Optimized for mobile devices
- Configurable intervals to balance accuracy vs. battery life
- Efficient socket management

### Network Usage
- Minimal bandwidth usage
- Configurable payload sizes
- Proper timeout handling to avoid hanging connections

## Troubleshooting

### Common Issues

1. **Permission Denied**
   - Ensure network permissions are properly configured
   - Check entitlements for macOS

2. **Timeout Errors**
   - Increase timeout value in configuration
   - Check network connectivity
   - Verify host is reachable

3. **Socket Errors**
   - Ensure proper cleanup of previous connections
   - Check for port conflicts
   - Verify firewall settings

### Debug Information

Enable debug logging by setting environment variables:

```bash
export NETO_DEBUG_PING=1
```

## Future Enhancements

### Planned Features

1. **Traceroute Integration**
   - Use ICMP timeout messages for hop discovery
   - Integrate with existing traceroute functionality

2. **Advanced Statistics**
   - Jitter calculation
   - Round-trip time variance
   - Historical data tracking

3. **Network Diagnostics**
   - Bandwidth testing
   - Connection quality assessment
   - Network path analysis

### API Extensions

1. **Batch Operations**
   - Ping multiple hosts simultaneously
   - Comparative analysis

2. **Custom Protocols**
   - Support for other ICMP message types
   - Custom packet formats

## Contributing

When contributing to the ping functionality:

1. Follow the existing code style and patterns
2. Add comprehensive unit tests
3. Update documentation
4. Test on all supported platforms
5. Consider performance implications

## License

© 2025 Lab22 Poland Sp. z o.o.
Author: Sergii Solianyk
Email: sergii.solyanik@lab22.pl

This implementation is based on Apple's SimplePing sample code, adapted for modern Swift and iOS/macOS platforms. 
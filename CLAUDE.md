# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NETo (Network Engineer Tools) – multiplatform SwiftUI app for iPhone, iPad and macOS. This repo is a git submodule of the neto-suite workspace (see the parent `CLAUDE.md` for the submodule workflow). Sources are in `neto/`, tests in `netoTests/` (XCTest + Swift Testing) and `netoUITests/`.

## Build and test

Run from this directory. Single scheme `neto`; targets `neto`, `netoTests`, `netoUITests`. The `/verify` skill (workspace root) runs the full check.

```bash
# iOS / iPadOS simulators – no overrides; disable parallel testing (see below)
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' -parallel-testing-enabled NO test -only-testing:netoTests

# macOS – needs the signing overrides shown (see "Project quirks")
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' test -only-testing:netoTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' test -only-testing:netoUITests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=   # ~4 min

# Single test: XCTest method vs. Swift Testing function (note the parentheses)
xcodebuild ... test -only-testing:netoTests/SimplePingTests/testSimplePingInitialization
xcodebuild ... test -only-testing:'netoTests/netoTests/networkToolCaseCount()'
```

On simulators always pass `-parallel-testing-enabled NO`: with parallel testing, xcodebuild spawns simulator clones whose app launch fails (`RequestDenied` / `Launch failed`), adding log noise and up to 10 minutes of diagnostics timeout, even though the tests themselves run on one clone. Before a simulator test run, uninstall stale builds (`xcrun simctl uninstall <udid> pl.lab22.neto` and `pl.lab22.netoUITests.xctrunner`); otherwise launches regularly fail with `Busy ("Application failed preflight checks")`.

Simulator names depend on the installed runtime – check `xcrun simctl list devices available`. Per project convention, verify changes on macOS, an iPhone simulator and an iPad Pro 11-inch simulator.

The unit test suite is not green yet (WHOIS and stale assertions fail), and many tests hit the real network (ICMP to 127.0.0.1 / 8.8.8.8, live WHOIS servers). Known failures are listed in `../.claude/test-baseline.md` (workspace root); compare against it instead of assuming that every failure is new.

No linter or formatter is configured. All three targets use Xcode file-system synchronized groups: new files in `neto/`, `netoTests/` or `netoUITests/` are picked up without editing `project.pbxproj`.

## Project quirks

- macOS signing: the app target has `DEVELOPMENT_TEAM = RR748D7U66` with automatic signing. Without a "Mac Development" certificate for that team in the keychain, macOS builds fail (exit 65) unless ad-hoc signing is forced via the overrides above. Simulator builds are unaffected.
- `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 5.0`, device family iPhone + iPad, no visionOS/tvOS/watchOS. Do not lower the deployment targets or add platforms unless asked.
- There is no Info.plist file (`GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_*` build settings), and there are no `NS*UsageDescription` keys yet.
- `neto/neto.entitlements` (App Sandbox, network client + server, user-selected read-only files) is applied to the app target on all platforms. ICMP inside the macOS sandbox needs **both** `network.client` and `network.server` (verified: without `server` the replies are blocked with EPERM), so do not drop either.
- SwiftData is **not** used, despite older docs/README claiming it. There is no persistence.

## Architecture

- `netoApp` → `ContentView`: a `NavigationSplitView` on all platforms (no iPhone-specific `NavigationStack`), driven by the `NetworkTool` enum (sidebar → detail). Adding a tool = new enum case (title + SF Symbol) + a `switch` branch in `ContentView`. `NetworkTool.allCases.count` is asserted in tests.
- Every tool is split into four files: `XxxView` (owns the view model via `@StateObject`) → `XxxViewModel` (`@MainActor final class`, `ObservableObject`, `@Published` state, keeps the running `Task` for cancellation) → `XxxManager` (networking, no UI) → `XxxResult` (value type).
- Managers expose `performXxx(to:..., onResult:, onComplete:) -> Task<Void, Never>`: results stream back through callbacks, and the view model cancels the returned task on stop. ARP is the exception (`async throws -> ArpResult`).
- Per tool:
  - **Ping** – `PingView` → `PingViewModel` → `PingManager` → `SimplePing` (Swift port of Apple's SimplePing): unprivileged `SOCK_DGRAM` ICMP socket (`IPPROTO_ICMP` / `IPPROTO_ICMPV6`), read through a `DispatchSource` on the main queue. On IPv4 the kernel hands back the IP header in front of the ICMP reply, so it has to be skipped. Identifier and sequence number travel in big-endian order. `PingManager` keeps all state on the main actor, calls `onComplete` exactly once (also after cancellation) and serializes runs. Verified on macOS and the iOS Simulator; not yet verified on a physical iOS device.
  - **Traceroute** – TCP `NWConnection` probes with per-hop timeouts, not a TTL-based traceroute.
  - **WHOIS** – raw TCP port 43 via `NWConnection`, intended as a port of FreeBSD `whois.c` (server constants, suffix→server table, referral prefixes and RIR loop detection are marked "exact match" in comments). Keep it consistent with the reference sources in `Temporary Items/` (`whois.c`, `rfc3912.txt`; untracked, local only) rather than inventing new logic.
  - **ARP** – macOS reads the neighbor cache via `sysctl()` on the routing table; iOS/iPadOS can only list basic interface info.
- UI tests match on visible label text (there are no accessibility identifiers), so changing user-facing strings can break `netoUITests`.

## Conventions

- Platform-specific code goes behind `#if os(macOS)` / `#if !os(macOS)` (UIKit imports and the clipboard: `NSPasteboard` vs `UIPasteboard`). Shared views stay free of AppKit/UIKit.
- Use only semantic system colors (`.primary`, `.secondary`, `.quaternary`), no custom colors.
- Document every manager method with `///` comments, as the existing managers do.
- Swift file header:
  ```
  //
  //  FileName.swift
  //  neto
  //
  //  Created by Sergii Solianyk on DD/MM/YYYY.
  //  © 2025 Lab22 Poland Sp. z o.o.
  //
  ```

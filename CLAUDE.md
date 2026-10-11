# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

NETo (Network Engineer Tools) – multiplatform SwiftUI app for iPhone, iPad and macOS. This repo is a git submodule of the neto-suite workspace (see the parent `CLAUDE.md` for the submodule workflow). Sources are in `neto/`, tests in `netoTests/` (XCTest + Swift Testing) and `netoUITests/`.

## Build and test

Run from this directory. Single scheme `neto`; targets `neto`, `netoTests`, `netoUITests`. The `/verify` skill (workspace root) runs the full check.

```bash
# iOS / iPadOS simulators – builds work without overrides
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=iOS Simulator,name=iPhone 17' build
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=iOS Simulator,name=iPad Pro 11-inch (M5)' build

# macOS – needs the build-setting overrides shown (see "Project quirks")
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' build CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= MACOSX_DEPLOYMENT_TARGET=14.0
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' test -only-testing:netoTests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= MACOSX_DEPLOYMENT_TARGET=14.0
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' test -only-testing:netoUITests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER= MACOSX_DEPLOYMENT_TARGET=14.0   # ~4 min

# Single test: XCTest method vs. Swift Testing function (note the parentheses)
xcodebuild ... test -only-testing:netoTests/SimplePingTests/testSimplePingInitialization
xcodebuild ... test -only-testing:'netoTests/netoTests/networkToolCaseCount()'
```

Running tests on iOS simulators currently fails: the test host app `pl.lab22.neto` is refused at launch (`Launch failed`, cause not yet investigated). Until that is fixed, run tests on macOS and only build for the simulators.

Simulator names depend on the installed runtime – check `xcrun simctl list devices available`. Per project convention, verify changes on macOS, an iPhone simulator and an iPad Pro 11-inch simulator.

The unit test suite is not green (several WHOIS, ping and stale assertions fail), and many tests hit the real network (ICMP to 127.0.0.1 / 8.8.8.8, live WHOIS servers). Known failures are listed in `../.claude/test-baseline.md` (workspace root); compare against it instead of assuming that every failure is new.

No linter or formatter is configured. All three targets use Xcode file-system synchronized groups: new files in `neto/`, `netoTests/` or `netoUITests/` are picked up without editing `project.pbxproj`.

## Project quirks

- macOS signing: the app target has `DEVELOPMENT_TEAM = RR748D7U66` with automatic signing. Without a "Mac Development" certificate for that team in the keychain, macOS builds fail (exit 65) unless ad-hoc signing is forced via the overrides above. Simulator builds are unaffected.
- `MACOSX_DEPLOYMENT_TARGET = 14.0` is set only on the app target. The test targets inherit the SDK default, so macOS tests refuse to run on an older host OS without the override.
- `IPHONEOS_DEPLOYMENT_TARGET = 17.0`, `SWIFT_VERSION = 5.0`, device family iPhone + iPad, no visionOS/tvOS/watchOS. Do not lower the deployment targets or add platforms unless asked.
- There is no Info.plist file (`GENERATE_INFOPLIST_FILE = YES`, `INFOPLIST_KEY_*` build settings), and there are no `NS*UsageDescription` keys yet.
- `neto/neto.entitlements` (App Sandbox, network client + server, user-selected read-only files) is applied to the app target on all platforms.
- SwiftData is **not** used, despite older docs/README claiming it. There is no persistence.

## Architecture

- `netoApp` → `ContentView`: a `NavigationSplitView` on all platforms (no iPhone-specific `NavigationStack`), driven by the `NetworkTool` enum (sidebar → detail). Adding a tool = new enum case (title + SF Symbol) + a `switch` branch in `ContentView`. `NetworkTool.allCases.count` is asserted in tests.
- Every tool is split into four files: `XxxView` (owns the view model via `@StateObject`) → `XxxViewModel` (`@MainActor final class`, `ObservableObject`, `@Published` state, keeps the running `Task` for cancellation) → `XxxManager` (networking, no UI) → `XxxResult` (value type).
- Managers expose `performXxx(to:..., onResult:, onComplete:) -> Task<Void, Never>`: results stream back through callbacks, and the view model cancels the returned task on stop. ARP is the exception (`async throws -> ArpResult`).
- Per tool:
  - **Ping (shipped)** – `PingView` → `PingViewModel` → `PingManager`: not ICMP; it opens a UDP `NWConnection` to port 80 as a reachability probe.
  - **Ping V2 (not wired in)** – `SimplePing` (Swift port of Apple's SimplePing: unprivileged `SOCK_DGRAM`/`IPPROTO_ICMP` socket, delegate-based) + `PingManagerV2` (`PingConfig`: count/interval/timeout/payloadSize) + `PingViewModelV2`/`PingViewV2`. Only tests reference it. `PING_REFACTORING.md` describes the intended migration; its `NETO_DEBUG_PING` env var is not implemented. Swapping `PingView` for `PingViewV2` will break UI tests that match the texts "Ping Tool" / "Send 5 Ping Packets".
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

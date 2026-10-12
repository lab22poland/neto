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
xcodebuild -project neto.xcodeproj -scheme neto -destination 'platform=macOS,arch=arm64' test -only-testing:netoUITests CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE_SPECIFIER=   # ~1–1.5 min

# Single test: XCTest method vs. Swift Testing function (note the parentheses)
xcodebuild ... test -only-testing:netoTests/PingManagerTests/testZeroCountCompletesWithoutResults
xcodebuild ... test -only-testing:'netoTests/WhoisManagerLogicTests/emptyQueryHasNoServer()'
```

On simulators always pass `-parallel-testing-enabled NO`: with parallel testing, xcodebuild spawns simulator clones whose app launch fails (`RequestDenied` / `Launch failed`), adding log noise and up to 10 minutes of diagnostics timeout, even though the tests themselves run on one clone. Before a simulator test run, uninstall stale builds (`xcrun simctl uninstall <udid> pl.lab22.neto` and `pl.lab22.netoUITests.xctrunner`); otherwise launches regularly fail with `Busy ("Application failed preflight checks")`.

Simulator names depend on the installed runtime – check `xcrun simctl list devices available`. Per project convention, verify changes on macOS, an iPhone simulator and an iPad Pro 11-inch simulator.

Unit tests (`netoTests/`, one file per area) test app logic, not Swift: pure functions are `internal` (not `private`) so `@testable import` can reach them – e.g. `ICMPPacket` (packet encoding), `WhoisManager.chooseServer/formatQueryForServer/parseWhoisReferral/parseWhoisResponse`, `ICMPPacket.probeReply`, `TracerouteManager.classifyHost/resolveHost/isValidIPv4/formatHopMessage`. Ping tests use real ICMP over loopback (127.0.0.1, ::1), which needs no internet. Do not add tests that only build a struct and read its fields back or copy app code (e.g. a regex) into the test.

- Known app bugs are pinned with `withKnownIssue` (Swift Testing) or `XCTExpectFailure` (XCTest): the test passes while the bug exists and fails once it is fixed – then remove the wrapper.
- Tests that need the internet live in `NetworkDependentTests.swift` (tag `network`) and are skipped by default. Run them with `TEST_RUNNER_NETO_NETWORK_TESTS=1 xcodebuild … test`; they depend on live registry data.
- Known failures and the current pass counts are in `../.claude/test-baseline.md` (workspace root).

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
  - **Traceroute** – real `traceroute -I`: one unprivileged ICMP socket, echo probes (3 per hop, sent one after another like traceroute: each waits for its own reply or the per-probe timeout, so ICMP-rate-limited routers answer as they do to `traceroute`) with increasing `IP_TTL` / `IPV6_UNICAST_HOPS`; routers answer Time Exceeded, the target Echo Reply. When to stop, the `!X` annotations (incl. "!" for an IPv4 reply with TTL <= 1; IPv6 hop limit is not read) and which replies count (only Time Exceeded in transit, ICMPv6 Parameter Problem "next header" as reached) follow `traceroute.c` / `traceroute6.c` (`TracerouteManager.verdict/endsTrace/answer`). A probe that cannot be sent shows its `sendto` error in its column without waiting and the trace goes on, like traceroute; resolution and socket errors end the run through `onComplete(error)` and show as the view model's error, never as a hop row. `ICMPPacket.probeReply` matches replies by the identifier in the quoted datagram (every ICMP socket sees all ICMP traffic of the host; some routers quote only 8 bytes, others append MPLS extensions). Router names come from an async reverse lookup without a time limit that re-delivers the row with the same `id` (also after the run or Stop, never into a newer run). Verified on macOS (sandbox) and the iOS Simulator against `/usr/sbin/traceroute`; the ICMPv6 path is implemented per RFC 4443 but not verified on a live IPv6 network.
  - **WHOIS** – raw TCP port 43 via `NWConnection`, a port of FreeBSD `whois.c` (reference in `Temporary Items/`, untracked, local only): `chooseServer`, `formatQueryForServer` (same rule order, Verisign by canonical name), `processResponse` (Nominet stop, ARIN/RIPE comment handling, referral scan, `actually_arin`, CHOPSPAM cut) and `nextServer` (RIR loop avoidance), with recursion until no referral (capped at `maxReferrals`). Response lines are processed as bytes like whois.c (Swift Characters treat "\r\n" as one grapheme, which broke CRLF answers). Verified against the compiled reference `whois.c` on 16 live queries (google.com, 8.8.8.8, AS15169, example.org, denic.de, bbc.co.uk, 193.0.6.139, nask.pl, example.com, 1.1.1.1, dk-hostmaster.dk, wikipedia.org, nic.io, 41.0.0.1, 200.1.1.1, cloudflare.com): same server chains, same text except server-side timestamps and name-server order. bbc.co.uk ends at IANA in both, because IANA's `whois:` for .uk is empty. A failure after the first server keeps the output so far (like whois.c printing before err()); only a failed connect fails a server – once connected, an error ends the answer like EOF, even with no data (whois.c's fgetln loop never checks ferror(); whois.markmonitor.com resets throttled connections without data). The summary fields (registrar, dates, name servers) come only from the last server's answer (`summarize`/`parseWhoisResponse`), never from IANA's TLD/block record; the result's `outcome` is shown in the UI as not found (registry "no match" lines), no data (empty answer: no record or throttling), incomplete (a referral did not answer, an answer was cut off) or IANA-only (no referral); a found answer without recognized fields says so. Keep it consistent with `whois.c` rather than inventing new logic. To re-check, compile the reference on macOS with a `SOCK_NONBLOCK`/`INFTIM` shim and diff its output against the app's `rawResponse`.
  - **DNS** – own client like `dig @server` (not the system resolver API `dnssd`, which cannot pick a server, distorts TTLs to its cache limits and hides RCODE/flags/sections). `DNSWire` (`DNSMessage.swift`) is the pure RFC 1035 codec: query with RD+AD and EDNS0 (1232), name compression, dig-style presentation for A, AAAA, NS, CNAME, PTR, MX, SOA, TXT, SRV, CAA, DS, DNSKEY and RFC 3597 `\# len HEX` for other types. `DnsManager` sends over UDP (TC=1 → retried over TCP), TCP, DoT (853) or DoH (POST `application/dns-message`, ID 0); presets Cloudflare/Google/Quad9; the system server comes from libresolv `res_9_getservers` (loaded with `dlopen`, `resolv.h` is not a Swift module), falling back to `/etc/resolv.conf`. An IP address in the name field becomes a PTR query (`dig -x`). The result names the server end actually reached (`NWConnection.currentPath.remoteEndpoint`; for DoH `URLSessionTaskMetrics` remote address, port and ALPN), in dig 9.18's `;; SERVER: addr#port(host) (UDP|TCP|TLS|HTTPS)` form (the system dig 9.10.6 has no +tls/+https); the query time starts on a ready connection, for DoH it is request start → response end of the last network transaction. Verified against `dig @1.1.1.1`: 12 types × 4 transports give the same records (A/AAAA by count because CDN answers rotate; DS/DNSKEY digests compared without the spaces dig 9.10 inserts every 56 characters).
  - **ARP** – macOS: `sysctl(NET_RT_FLAGS, RTF_LLINFO)` per address family, parsed like Darwin `arp`/`ndp` (`ArpManager.parseNeighborTable`: interface from the gateway `sockaddr_dl` index, MAC at `LLADDR`, `rmx_expire` in seconds since 1970); IPv6 state/expiry via `ioctl(SIOCGNBRINFO_IN6)` (struct mirrored because `nd6.h` is not imported into Swift). Entries match `arp -an` / `ndp -an` in address, interface, MAC and permanent flag; link type and ifscope are parsed and tested but not shown in the UI (the app zero-pads MACs; IPv6 multicast is skipped like `ndp`; IPv6 state is "unknown" if the ioctl fails). IPv4 expiry is the route's `rmx_expire` (shown as "route expires in"; `arp -an` does not print it and `arp -anl` shows the different link-layer reachability timers). A failed IPv6 dump keeps the IPv4 entries and is shown as a note (`ArpResult.ipv6Error`). On iOS/iPadOS the app cannot read the table and throws `ArpError.platformNotSupported`.
- UI tests (`netoUITests`) are a few end-to-end flows that need no internet (ping and traceroute target 127.0.0.1; WHOIS only checks input validation). They find elements by accessibility identifiers (`sidebar.<tool>`, `<tool>.header`, `ping.host`, `ping.start`, `ping.stats`, …), so keep those when changing views and add one for every element a new test touches. On iPhone the split view collapses into a stack; the `openTool` helper navigates back to the sidebar. Static text is exposed as `label` on iOS but as `value` on macOS, so match both. Prefer statistics or other always-visible elements; when asserting on rows inside a scroll view, make sure the list cannot be squeezed to zero height (Ping and Traceroute scroll as a whole and give their result lists a minimum height for that reason).

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

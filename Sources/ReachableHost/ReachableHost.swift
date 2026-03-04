// The Swift Programming Language
// https://docs.swift.org/swift-book
//
// Swift Argument Parser
// https://swiftpackageindex.com/apple/swift-argument-parser/documentation

import ArgumentParser
import Foundation

@main
struct ReachableHost: AsyncParsableCommand {

    static let configuration = CommandConfiguration(
        commandName: "reachable",
        abstract: "Monitor host reachability in a live TUI. Exits when all hosts are online.",
        version: "1.0.0"
    )

    @Argument(help: "Hostnames or IP addresses to monitor. Append @MAC to enable Wake-on-LAN (e.g. host@aa:bb:cc:dd:ee:ff).")
    var hosts: [String]

    @Option(name: [.customShort("i"), .long], help: "Poll interval in seconds.")
    var interval: Double = 1.0

    mutating func run() async throws {
        guard !hosts.isEmpty else {
            throw ValidationError("Provide at least one hostname or IP address.")
        }

        // Parse host@MAC syntax. The MAC portion is used only for Wake-on-LAN.
        var addresses: [String] = []
        var macMap: [String: String] = [:]
        for arg in self.hosts {
            if let at = arg.firstIndex(of: "@") {
                let address = String(arg[..<at])
                let mac     = String(arg[arg.index(after: at)...])
                addresses.append(address)
                macMap[address] = mac
            } else {
                addresses.append(arg)
            }
        }

        // Capture interval before any await (avoids mutating-self-across-await issues).
        let interval = self.interval

        let terminal = Terminal()
        let tui      = TUI(hosts: addresses)

        terminal.setUp()
        defer { terminal.tearDown() }

        // Clear screen once at startup.
        writeRaw("\u{1B}[2J\u{1B}[H")

        var wolSentHosts: Set<String> = []

        while true {
            let pending = await tui.pendingHosts()

            // Only probe hosts that aren't yet confirmed reachable.
            var results: [(String, CheckResult)] = []
            if !pending.isEmpty {
                await tui.markChecking(pending)
                await tui.draw(phase: .checking(count: pending.count))

                // Check all pending hosts concurrently; redraw as each result arrives.
                await withTaskGroup(of: (String, CheckResult).self) { group in
                    for host in pending {
                        group.addTask {
                            let result = await HostChecker.check(host: host)
                            await tui.update(host: host, result: result)
                            let remaining = await tui.pendingHosts()
                            await tui.draw(phase: .checking(count: remaining.count))
                            return (host, result)
                        }
                    }
                    for await pair in group { results.append(pair) }
                }

                // Send WOL for newly unreachable hosts that have an associated MAC.
                for (host, result) in results {
                    if case .failed = result,
                       let mac = macMap[host],
                       !wolSentHosts.contains(host) {
                        WakeOnLAN.send(mac: mac)
                        await tui.markWolSent(host)
                        wolSentHosts.insert(host)
                    }
                }
            }

            if await tui.allOK {
                await tui.draw(phase: .done)
                return
            }

            await tui.draw(phase: .retrying(interval: interval))
            try? await Task.sleep(for: .seconds(interval))
        }
    }
}

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

    @Argument(help: "Hostnames or IP addresses to monitor.")
    var hosts: [String]

    @Option(name: [.customShort("i"), .long], help: "Poll interval in seconds.")
    var interval: Double = 1.0

    mutating func run() async throws {
        guard !hosts.isEmpty else {
            throw ValidationError("Provide at least one hostname or IP address.")
        }

        // Capture values before any await (avoids mutating-self-across-await issues).
        let hosts    = self.hosts
        let interval = self.interval

        let terminal = Terminal()
        let tui      = TUI(hosts: hosts)

        terminal.setUp()
        defer { terminal.tearDown() }

        // Clear screen once at startup.
        writeRaw("\u{1B}[2J\u{1B}[H")

        while true {
            let pending = await tui.pendingHosts()

            // Only probe hosts that aren't yet confirmed reachable.
            if !pending.isEmpty {
                await tui.markChecking(pending)
                await tui.draw(phase: .checking(count: pending.count))

                // Check all pending hosts concurrently; redraw as each result arrives.
                await withTaskGroup(of: Void.self) { group in
                    for host in pending {
                        group.addTask {
                            let result = await HostChecker.check(host: host)
                            await tui.update(host: host, result: result)
                            let remaining = await tui.pendingHosts()
                            await tui.draw(phase: .checking(count: remaining.count))
                        }
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

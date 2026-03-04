import Foundation

// MARK: - Host status

enum HostStatus: Sendable {
    case pending
    case checking
    case ok(method: String, detail: String)
    case failed
    case wolSent
}

// MARK: - Draw phase (what to show in the status line)

enum DrawPhase: Sendable {
    case checking(count: Int)
    case retrying(interval: Double)
    case done
}

// MARK: - TUI actor

/// Actor-isolated TUI state and renderer.
/// All mutable state lives here; every write to stdout goes through draw().
actor TUI {

    private let hosts:    [String]
    private var statuses: [String: HostStatus]
    private var spinIdx = 0

    private static let spinFrames = ["⠋","⠙","⠹","⠸","⠼","⠴","⠦","⠧","⠇","⠏"]

    init(hosts: [String]) {
        self.hosts    = hosts
        self.statuses = Dictionary(uniqueKeysWithValues: hosts.map { ($0, HostStatus.pending) })
    }

    // MARK: State queries

    var allOK: Bool {
        hosts.allSatisfy { host in
            if case .ok = statuses[host] { return true }
            return false
        }
    }

    /// Returns hosts not yet confirmed reachable.
    func pendingHosts() -> [String] {
        hosts.filter { host in
            if case .ok = statuses[host] { return false }
            return true
        }
    }

    // MARK: State mutations

    func markChecking(_ pending: [String]) {
        for host in pending { statuses[host] = .checking }
    }

    func markWolSent(_ host: String) {
        statuses[host] = .wolSent
    }

    func update(host: String, result: CheckResult) {
        switch result {
        case .ok(let m, let d): statuses[host] = .ok(method: m, detail: d)
        case .failed:           statuses[host] = .failed
        }
    }

    // MARK: Rendering

    func draw(phase: DrawPhase) {
        let spin = TUI.spinFrames[spinIdx % TUI.spinFrames.count]
        spinIdx += 1

        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let now = df.string(from: Date())

        var out = "\u{1B}[H"   // move cursor to top-left (no scrollback clear)

        // Title row
        out += "\u{1B}[1m\u{1B}[36mReachable Check\u{1B}[0m"
        out += "  \u{1B}[2m\(now)\u{1B}[0m\u{1B}[K\n"
        out += "\u{1B}[2m\u{1B}[90mPress ESC or Ctrl-C to quit\u{1B}[0m\u{1B}[K\n"
        out += "\u{1B}[K\n"

        // Status line
        switch phase {
        case .checking(let count):
            out += "\u{1B}[2m\u{1B}[90m\(spin) Checking \(count) host(s)...\u{1B}[0m"
        case .retrying(let iv):
            out += "\u{1B}[1m\u{1B}[33m⚠ Some hosts unreachable. Retrying every \(Int(iv))s...\u{1B}[0m"
        case .done:
            if hosts.count > 1 {
                out += "\u{1B}[1m\u{1B}[32m✔ All hosts reachable. Exiting.\u{1B}[0m"
            } else {
                out += "\u{1B}[1m\u{1B}[32m✔ Host reachable. Exiting.\u{1B}[0m"
            }
        }
        out += "\u{1B}[K\n\u{1B}[K\n"

        // Table header
        out += "\u{1B}[2m\u{1B}[90m   \(col("HOST", 24))  \(col("METHOD", 10))  \(col("DETAIL", 12))\u{1B}[0m\u{1B}[K\n"
        out += "\u{1B}[2m\u{1B}[90m\(String(repeating: "-", count: 62))\u{1B}[0m\u{1B}[K\n"

        // Host rows
        for host in hosts {
            let (dotClr, label, method, detail) = rowInfo(host: host)
            out += "\(dotClr)●\u{1B}[0m  "
            out += "\(col(host, 24))  \(col(method, 10))  \(col(detail, 12))"
            out += "  \u{1B}[2m\(label)\u{1B}[0m\u{1B}[K\n"
        }

        // Erase any stale content below the drawn lines
        out += "\u{1B}[J"

        writeRaw(out)
    }

    private func rowInfo(host: String) -> (dotColor: String, label: String, method: String, detail: String) {
        switch statuses[host] ?? .pending {
        case .ok(let m, let d): return ("\u{1B}[32m", "OK",       m, d)
        case .failed:           return ("\u{1B}[31m", "DOWN",     "–", "–")
        case .wolSent:          return ("\u{1B}[35m", "WOL SENT", "–", "–")
        case .checking:         return ("\u{1B}[33m", "CHECKING", "–", "–")
        case .pending:          return ("\u{1B}[90m", "PENDING",  "–", "–")
        }
    }
}

// MARK: - Column formatter (file-private helper)

private func col(_ s: String, _ width: Int) -> String {
    guard s.count < width else { return String(s.prefix(width)) }
    return s.padding(toLength: width, withPad: " ", startingAt: 0)
}

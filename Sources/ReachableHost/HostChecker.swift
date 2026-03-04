import Foundation

enum CheckResult: Sendable {
    case ok(method: String, detail: String)
    case failed
}

enum HostChecker {

    /// Tries ICMP ping first, then TCP on ports 22/445/5900.
    /// Never throws — encodes failure in the return value.
    static func check(host: String) async -> CheckResult {
        if let r = await ping(host: host) { return r }
        if let r = await tcp(host: host)  { return r }
        return .failed
    }

    // MARK: - ICMP

    private static func ping(host: String) async -> CheckResult? {
        guard let output = await run(
            "/sbin/ping", ["-n", "-c", "1", "-W", "1000", host]
        ) else { return nil }

        // macOS ping prints: "64 bytes from …: icmp_seq=0 ttl=64 time=4.515 ms"
        if let ms = parseLatency(from: output) {
            return .ok(method: "icmp", detail: "\(ms)ms")
        }
        return .ok(method: "icmp", detail: "?")
    }

    // MARK: - TCP fallback

    private static func tcp(host: String) async -> CheckResult? {
        for port in [22, 445, 5900] {
            if await run("/usr/bin/nc", ["-G", "1", "-w", "1", "-z", host, "\(port)"]) != nil {
                return .ok(method: "tcp", detail: ":\(port)")
            }
        }
        return nil
    }

    // MARK: - Ping output parser

    /// Extracts the round-trip time value from ping's stdout.
    /// macOS ping format: "… time=4.515 ms" or "… time= 4.515 ms"
    private static func parseLatency(from output: String) -> String? {
        guard let timeRange = output.range(of: "time=") else { return nil }
        let after = output[timeRange.upperBound...]
            .trimmingCharacters(in: .whitespaces)
        // Take the numeric token before the next whitespace
        let token = after.prefix(while: { $0.isNumber || $0 == "." })
        guard !token.isEmpty else { return nil }
        return String(token)
    }

    // MARK: - Process runner

    /// Runs an executable and returns its stdout string when exit code is 0, nil otherwise.
    /// Uses Process.terminationHandler bridged into async via CheckedContinuation.
    private static func run(_ path: String, _ args: [String]) async -> String? {
        await withCheckedContinuation { (cont: CheckedContinuation<String?, Never>) in
            let proc = Process()
            let pipe = Pipe()
            proc.executableURL  = URL(fileURLWithPath: path)
            proc.arguments      = args
            proc.standardOutput = pipe
            proc.standardError  = FileHandle.nullDevice

            proc.terminationHandler = { p in
                if p.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    cont.resume(returning: String(data: data, encoding: .utf8) ?? "")
                } else {
                    cont.resume(returning: nil)
                }
            }

            do {
                try proc.run()
            } catch {
                // Process failed to launch — resume immediately so the continuation
                // is never left dangling.
                cont.resume(returning: nil)
            }
        }
    }
}

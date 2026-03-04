import Darwin
import Foundation

/// Manages raw terminal state, signal handling, and ESC detection.
/// Marked @unchecked Sendable because mutations happen only in setUp/tearDown,
/// which are called from the single-entry-point run() before concurrency starts.
final class Terminal: @unchecked Sendable {

    private var original   = termios()
    private var torn       = false
    private let lock       = NSLock()
    private var sigSources: [DispatchSourceSignal] = []

    func setUp() {
        // Save original terminal state.
        tcgetattr(STDIN_FILENO, &original)

        // Disable ICANON only — NOT ECHO.
        // Disabling ECHO triggers Ghostty's Secure Input, which blocks keyboard events.
        // Disabling only ICANON switches to character-at-a-time delivery without that side effect.
        var raw = original
        raw.c_lflag &= ~tcflag_t(ICANON)
        withUnsafeMutableBytes(of: &raw.c_cc) { buf in
            buf[Int(VMIN)]  = 1   // deliver after 1 character
            buf[Int(VTIME)] = 0   // no timeout — block until char arrives
        }
        tcsetattr(STDIN_FILENO, TCSANOW, &raw)

        // Hide cursor.
        writeRaw("\u{1B}[?25l")

        // GCD signal sources — must SIG_IGN before makeSignalSource.
        signal(SIGINT,  SIG_IGN)
        signal(SIGTERM, SIG_IGN)
        for sig in [SIGINT, SIGTERM] {
            let src = DispatchSource.makeSignalSource(signal: sig, queue: .global())
            src.setEventHandler { [weak self] in self?.handleExit() }
            src.resume()
            sigSources.append(src)
        }

        // ESC detection on a dedicated OS thread.
        // read() is a blocking syscall — running it on Swift's cooperative thread pool
        // would starve other tasks, so we use a plain OS thread instead.
        Thread.detachNewThread { [weak self] in
            var byte: UInt8 = 0
            while read(STDIN_FILENO, &byte, 1) > 0 {
                if byte == 0x1B { self?.handleExit(); return }
            }
        }
    }

    func tearDown() {
        lock.lock(); defer { lock.unlock() }
        guard !torn else { return }
        torn = true
        sigSources.forEach { $0.cancel() }
        sigSources.removeAll()
        signal(SIGINT,  SIG_DFL)
        signal(SIGTERM, SIG_DFL)
        tcsetattr(STDIN_FILENO, TCSAFLUSH, &original)
        writeRaw("\u{1B}[?25h\u{1B}[0m\n")  // show cursor, reset colours, newline
    }

    private func handleExit() {
        tearDown()
        Darwin.exit(0)
    }
}

// MARK: - Low-level stdout write (no buffering, no newline appended)

func writeRaw(_ s: String) {
    s.withCString { ptr in
        _ = Darwin.write(STDOUT_FILENO, UnsafeRawPointer(ptr), strlen(ptr))
    }
}

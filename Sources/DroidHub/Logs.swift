import SwiftUI

/// Inspector panels, one toolbar toggle each.
enum Panel: String, CaseIterable {
    case settings, logs, crashes

    var title: String { rawValue.capitalized }

    var icon: String {
        switch self {
        case .settings: "slider.horizontal.3"
        case .logs: "doc.text"
        case .crashes: "exclamationmark.triangle"
        }
    }
}

/// One `logcat -v threadtime` line: "09-11 16:45:01.123  1234  5678 I Tag: message".
struct LogLine: Identifiable, Equatable {
    var id = 0
    let time: String
    let pid: String
    let level: Character
    let tag: String
    let message: String

    init?(_ text: some StringProtocol) {
        let f = text.split(separator: " ", maxSplits: 5, omittingEmptySubsequences: true)
        guard f.count == 6, f[4].count == 1, let colon = f[5].range(of: ": ") ?? f[5].range(of: ":") else { return nil }
        time = "\(f[0]) \(f[1])"
        pid = String(f[2])
        level = f[4].first!
        tag = f[5][..<colon.lowerBound].trimmingCharacters(in: .whitespaces)
        message = String(f[5][colon.upperBound...])
    }

    var text: String { "\(time) \(pid) \(level) \(tag): \(message)" }
}

struct Crash: Identifiable, Equatable {
    let id: Int
    let time: String
    let process: String
    let summary: String
    let text: String

    static func load(_ serial: String) async -> [Crash] {
        let out = await adb("-s", serial, "logcat", "-b", "crash", "-d", "-v", "threadtime")
        return parse(out.split(separator: "\n").compactMap { LogLine($0) })
    }

    /// Groups the crash buffer into reports, newest first. A report is a run of lines
    /// with the same pid and tag: AndroidRuntime for Java, DEBUG for native crashes.
    /// A native crash also logs a "Fatal signal" line from libc (another pid) right
    /// before its DEBUG report, so that line joins the report instead of standing alone.
    static func parse(_ lines: [LogLine]) -> [Crash] {
        var groups: [[LogLine]] = []
        for line in lines {
            if let last = groups.last?.last,
               (last.pid == line.pid && last.tag == line.tag) || (last.tag == "libc" && line.tag == "DEBUG") {
                groups[groups.count - 1].append(line)
            } else {
                groups.append([line])
            }
        }
        return groups.enumerated().map { i, group in
            let messages = group.map(\.message)
            // Native reports also mention "Exception" in register dumps, so the abort
            // message and the signal come first.
            let summary = messages.first { $0.hasPrefix("Abort message") }
                ?? messages.first { $0.hasPrefix("signal ") }
                ?? messages.first { $0.contains("Exception") || $0.contains("Error") }
                ?? messages[0]
            return Crash(id: i, time: group[0].time, process: messages.lazy.compactMap(processName).first ?? group[0].tag,
                         summary: summary.trimmingCharacters(in: .whitespaces), text: messages.joined(separator: "\n"))
        }.reversed()
    }

    /// "Process: com.app, PID: 123" (Java) or "pid: 1, tid: 1, name: x  >>> com.app <<<" (native).
    private static func processName(_ message: String) -> String? {
        if message.hasPrefix("Process: ") { return message.dropFirst(9).split(separator: ",").first.map(String.init) }
        if let a = message.range(of: ">>> "), let b = message.range(of: " <<<"), a.upperBound <= b.lowerBound {
            return String(message[a.upperBound..<b.lowerBound])
        }
        return nil
    }
}

@Observable @MainActor
final class Logcat {
    private(set) var lines: [LogLine] = []
    @ObservationIgnored private var pending: [LogLine] = []
    @ObservationIgnored private var flushing = false
    @ObservationIgnored private var nextID = 0
    @ObservationIgnored private var process: Process?
    private static let limit = 5000

    /// Streams the last 1000 lines and everything after them.
    func start(_ serial: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: SDK.adb)
        p.arguments = ["-s", serial, "logcat", "-v", "threadtime", "-T", "1000"]
        let out = Pipe()
        p.standardOutput = out
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return }
        process = p
        Task.detached { [weak self] in
            for try await text in out.fileHandleForReading.bytes.lines {
                if let line = LogLine(text) { await self?.receive(line) }
            }
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    func clear(_ serial: String) {
        lines = []
        pending = []
        Task { await adb("-s", serial, "logcat", "-c") }
    }

    /// Batches lines into one UI update every 100 ms; logcat can spit hundreds per second.
    private func receive(_ line: LogLine) {
        var line = line
        line.id = nextID
        nextID += 1
        pending.append(line)
        guard !flushing else { return }
        flushing = true
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            lines.append(contentsOf: pending)
            pending = []
            flushing = false
            if lines.count > Self.limit { lines.removeFirst(lines.count - Self.limit) }
        }
    }
}

struct LogsView: View {
    let serial: String
    @State private var logcat = Logcat()
    @State private var query = ""
    @State private var level: Character = "V"
    @State private var follow = true
    private static let levels: [(Character, String)] = [("V", "Verbose"), ("D", "Debug"), ("I", "Info"), ("W", "Warning"), ("E", "Error"), ("F", "Fatal")]

    private var shown: [LogLine] {
        let minimum = Self.rank(level)
        return logcat.lines.filter {
            Self.rank($0.level) >= minimum
                && (query.isEmpty || $0.tag.localizedCaseInsensitiveContains(query) || $0.message.localizedCaseInsensitiveContains(query))
        }
    }

    private static func rank(_ level: Character) -> Int { levels.firstIndex { $0.0 == level } ?? levels.count }

    var body: some View {
        let shown = shown
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                TextField("Filter tag or message", text: $query).textFieldStyle(.roundedBorder)
                Picker("Level", selection: $level) {
                    ForEach(Self.levels, id: \.0) { Text($0.1).tag($0.0) }
                }
                .labelsHidden()
                .fixedSize()
                Toggle("Follow", systemImage: "arrow.down.to.line", isOn: $follow)
                    .toggleStyle(.button)
                    .labelStyle(.iconOnly)
                    .help("Keep scrolling to the newest line")
                Menu {
                    Button("Copy Shown Lines") { copy(shown.map(\.text).joined(separator: "\n")) }
                    Button("Clear Device Log") { logcat.clear(serial) }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
            }
            .padding(8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(shown) { LogRow(line: $0) }
                    }
                    .padding(8)
                }
                .onChange(of: shown.last?.id) { _, id in
                    if follow, let id { proxy.scrollTo(id, anchor: .bottom) }
                }
            }
        }
        .inspectorColumnWidth(min: 280, ideal: 440, max: 900)
        .task(id: serial) {
            logcat.start(serial)
            while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
            logcat.stop()
        }
    }
}

struct LogRow: View {
    let line: LogLine

    var body: some View {
        Text("\(Text(line.tag).foregroundStyle(.secondary)) \(Text(verbatim: line.message))")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(color)
            .frame(maxWidth: .infinity, alignment: .leading)
            .help("\(line.time) · pid \(line.pid)")
            .contextMenu { Button("Copy") { copy(line.text) } }
    }

    private var color: Color {
        switch line.level {
        case "W": .orange
        case "E", "F", "A": .red
        case "V", "D": .secondary
        default: .primary
        }
    }
}

struct CrashesView: View {
    let serial: String
    @State private var crashes: [Crash] = []

    var body: some View {
        Group {
            if crashes.isEmpty {
                ContentUnavailableView("No Crashes", systemImage: "checkmark.seal", description: Text("App crashes on this device show up here."))
            } else {
                List(crashes) { crash in
                    DisclosureGroup {
                        Text(verbatim: crash.text)
                            .font(.system(size: 11, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(crash.process).fontWeight(.semibold)
                            Text(crash.summary).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                            Text(crash.time).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .contextMenu { Button("Copy Report") { copy(crash.text) } }
                }
            }
        }
        .safeAreaInset(edge: .top) {
            HStack {
                Text(crashes.count == 1 ? "1 crash" : "\(crashes.count) crashes").foregroundStyle(.secondary)
                Spacer()
                Button("Clear") {
                    crashes = []
                    Task { await adb("-s", serial, "logcat", "-b", "crash", "-c") }
                }
                .disabled(crashes.isEmpty)
            }
            .padding(8)
        }
        .inspectorColumnWidth(min: 280, ideal: 440, max: 900)
        // The crash buffer is tiny, so polling it is cheaper than keeping a second stream.
        .task(id: serial) {
            while !Task.isCancelled {
                let latest = await Crash.load(serial)
                if latest != crashes { crashes = latest }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }
}

private func copy(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

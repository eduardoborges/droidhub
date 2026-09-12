import AppKit
import Observation

struct Device: Identifiable, Hashable {
    let id: String
    var name: String
    var detail: String
    var model = ""
    var release = ""
    var api = ""
    var avd: String?
    /// Set once the device is online and booted.
    var serial: String?
    var isEmulator: Bool { avd != nil }
}

enum SDK {
    static let root: URL = {
        let env = ProcessInfo.processInfo.environment
        if let path = env["ANDROID_HOME"] ?? env["ANDROID_SDK_ROOT"] { return URL(fileURLWithPath: path) }
        return FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Android/sdk")
    }()
    static let adb = root.appending(path: "platform-tools/adb").path
    static let emulator = root.appending(path: "emulator/emulator").path
    // ponytail: ignores ANDROID_AVD_HOME and custom path= entries in the .ini files
    static let avdHome = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".android/avd")
}

/// Runs a tool and returns its stdout.
func exec(_ tool: String, _ args: [String]) async -> Data {
    await withCheckedContinuation { cont in
        DispatchQueue.global().async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            let out = Pipe()
            p.standardOutput = out
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return cont.resume(returning: Data()) }
            let data = out.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            cont.resume(returning: data)
        }
    }
}

@discardableResult
func adb(_ args: String...) async -> String {
    String(decoding: await exec(SDK.adb, args), as: UTF8.self)
}

@Observable @MainActor
final class Hub {
    var devices: [Device] = []
    var selection: Device.ID?
    var booting: Set<Device.ID> = []
    @ObservationIgnored private var props: [String: [String: String]] = [:]

    var selected: Device? { devices.first { $0.id == selection } }

    func poll() async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: .seconds(2))
        }
    }

    func refresh() async {
        let serials = await adb("devices").split(separator: "\n").dropFirst().compactMap { line -> String? in
            let f = line.split(separator: "\t")
            return f.count == 2 && f[1] == "device" ? String(f[0]) : nil
        }
        props = props.filter { serials.contains($0.key) }
        for serial in serials where props[serial] == nil {
            let p = await Self.getprop(serial)
            if p["sys.boot_completed"] == "1" { props[serial] = p }
        }

        var list = Self.avds()
        for (serial, p) in props.sorted(by: { $0.key < $1.key }) {
            let model = p["ro.product.model"] ?? serial
            var d: Device
            // Older images (API 30 and below) publish ro.kernel.qemu.avd_name instead.
            if let avd = p["ro.boot.qemu.avd_name"] ?? p["ro.kernel.qemu.avd_name"], let i = list.firstIndex(where: { $0.avd == avd }) {
                d = list.remove(at: i)
            } else {
                d = Device(id: serial, name: model, detail: p["ro.product.manufacturer"] ?? "Android")
            }
            d.serial = serial
            d.model = model
            d.release = p["ro.build.version.release"] ?? ""
            d.api = p["ro.build.version.sdk"].map { "API \($0)" } ?? d.api
            list.append(d)
        }
        list.sort { ($0.isEmulator ? 1 : 0, $0.name) < ($1.isEmulator ? 1 : 0, $1.name) }

        booting.subtract(list.filter { $0.serial != nil }.map(\.id))
        if devices != list { devices = list }
        if selected == nil { selection = list.first { $0.serial != nil }?.id ?? list.first?.id }
    }

    func boot(_ device: Device) {
        guard let avd = device.avd, !booting.contains(device.id) else { return }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: SDK.emulator)
        p.arguments = ["-avd", avd, "-no-window", "-no-boot-anim"]
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        p.terminationHandler = { _ in Task { @MainActor in self.booting.remove(device.id) } }
        guard (try? p.run()) != nil else { return }
        booting.insert(device.id)
    }

    func shutdown(_ device: Device) {
        guard let serial = device.serial else { return }
        Task { await adb("-s", serial, "emu", "kill") }
    }

    /// scrcpy's own rotate is undone right away when auto-rotate is on, which is the
    /// default. Emulators turn through their console instead, and phones get the
    /// other orientation locked.
    func rotate(_ device: Device) {
        guard let serial = device.serial else { return }
        Task {
            if device.isEmulator {
                await adb("-s", serial, "emu", "rotate")
            } else {
                await adb("-s", serial, "shell", "r=$(dumpsys input | grep -m1 -oE 'orientation=[0-9]' | cut -d= -f2); settings put system accelerometer_rotation 0; settings put system user_rotation $(( (${r:-0} & 1) ^ 1 ))")
            }
        }
    }

    /// Saves to the Desktop and copies to the clipboard, like Simulator.
    func screenshot(_ device: Device) async {
        guard let serial = device.serial else { return }
        let png = await exec(SDK.adb, ["-s", serial, "exec-out", "screencap", "-p"])
        guard !png.isEmpty else { return }
        let date = Date.now.formatted(.verbatim("\(year: .defaultDigits)-\(month: .twoDigits)-\(day: .twoDigits) at \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)", timeZone: .current, calendar: .current))
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]
        try? png.write(to: desktop.appending(path: "\(device.name.replacingOccurrences(of: "/", with: "-")) \(date).png"))
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setData(png, forType: .png)
    }

    private static func getprop(_ serial: String) async -> [String: String] {
        var props: [String: String] = [:]
        for line in await adb("-s", serial, "shell", "getprop").split(separator: "\n") {
            let kv = line.split(separator: "]: [", maxSplits: 1)
            if kv.count == 2 { props[String(kv[0].dropFirst())] = String(kv[1].dropLast()) }
        }
        return props
    }

    private static func avds() -> [Device] {
        let files = (try? FileManager.default.contentsOfDirectory(at: SDK.avdHome, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ini" }.map { url in
            let avd = url.deletingPathExtension().lastPathComponent
            let config = ini(SDK.avdHome.appending(path: "\(avd).avd/config.ini"))
            let sysdir = config["image.sysdir.1"] ?? ""
            let api = sysdir.range(of: #"android-\d+"#, options: .regularExpression).map { "API " + sysdir[$0].dropFirst(8) } ?? ""
            return Device(id: "avd:\(avd)", name: config["avd.ini.displayname"] ?? avd.replacingOccurrences(of: "_", with: " "), detail: "Emulator", api: api, avd: avd)
        }
    }

    nonisolated static func ini(_ url: URL) -> [String: String] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }
        let pairs = text.split(separator: "\n").compactMap { line -> (String, String)? in
            let kv = line.split(separator: "=", maxSplits: 1)
            return kv.count == 2 ? (kv[0].trimmingCharacters(in: .whitespaces), kv[1].trimmingCharacters(in: .whitespaces)) : nil
        }
        return Dictionary(pairs, uniquingKeysWith: { first, _ in first })
    }
}

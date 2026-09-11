import SwiftUI

@main
struct DroidHubApp: App {
    @State private var hub = Hub()

    var body: some Scene {
        Window("DroidHub", id: "main") {
            ContentView().environment(hub)
        }
        .defaultSize(width: 1000, height: 900)
    }
}

struct ContentView: View {
    @Environment(Hub.self) private var hub
    @State private var query = ""
    @State private var inspector = false

    var body: some View {
        @Bindable var hub = hub
        NavigationSplitView {
            List(selection: $hub.selection) {
                section("Devices", hub.devices.filter { !$0.isEmulator })
                section("Emulators", hub.devices.filter(\.isEmulator))
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            if let device = hub.selected {
                DeviceView(device: device, inspector: $inspector).id(device.id)
            } else {
                ContentUnavailableView("No Devices", systemImage: "smartphone", description: Text("Create an emulator in Android Studio or plug in a device."))
            }
        }
        .task { await hub.poll() }
    }

    @ViewBuilder private func section(_ title: String, _ devices: [Device]) -> some View {
        let shown = devices.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        if !shown.isEmpty {
            Section(title) { ForEach(shown) { DeviceRow(device: $0) } }
        }
    }
}

struct DeviceRow: View {
    @Environment(Hub.self) private var hub
    let device: Device

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "smartphone")
                .font(.title2)
                .foregroundStyle(device.serial != nil ? AnyShapeStyle(.tint) : AnyShapeStyle(.tertiary))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(device.name).fontWeight(.medium)
                Text(hub.booting.contains(device.id) ? "Booting…" : device.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(device.api).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .contextMenu {
            if device.isEmulator {
                if device.serial == nil {
                    Button("Boot") { hub.boot(device) }
                } else {
                    Button("Shut Down") { hub.shutdown(device) }
                }
            }
        }
    }
}

struct DeviceView: View {
    @Environment(Hub.self) private var hub
    let device: Device
    @Binding var inspector: Bool
    @State private var mirror: Mirror?
    @State private var size = CGSize(width: 1080, height: 2400)
    @State private var failure: String?
    @State private var attempt = 0

    var body: some View {
        content
            .navigationTitle(device.name)
            .navigationSubtitle(device.release.isEmpty ? device.detail : "Android \(device.release)")
            .toolbar {
                if let mirror {
                    ToolbarItemGroup {
                        Button("Volume Down", systemImage: "speaker.wave.1") { mirror.key(25) }
                        Button("Volume Up", systemImage: "speaker.wave.3") { mirror.key(24) }
                        Button("Power", systemImage: "power") { mirror.key(26) }
                    }
                }
                ToolbarItem {
                    Button("Inspector", systemImage: "sidebar.trailing") { inspector.toggle() }
                }
            }
            .inspector(isPresented: $inspector) {
                if let serial = device.serial {
                    InspectorView(device: device, serial: serial)
                } else {
                    ContentUnavailableView("Offline", systemImage: "powersleep")
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let serial = device.serial {
            Phone(size: size) {
                if let mirror {
                    Screen(mirror: mirror)
                } else {
                    Color.black.overlay {
                        if let failure {
                            VStack(spacing: 12) {
                                Text(failure).foregroundStyle(.white).multilineTextAlignment(.center)
                                Button("Retry") { attempt += 1 }
                            }
                            .padding()
                        } else {
                            ProgressView().controlSize(.large).tint(.white)
                        }
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                if let mirror { controls(mirror) }
            }
            .task(id: "\(serial)#\(attempt)") { await connect(serial) }
        } else if hub.booting.contains(device.id) {
            ProgressView("Booting \(device.name)…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ContentUnavailableView {
                Label(device.name, systemImage: "smartphone")
            } description: {
                Text(device.isEmulator ? "The emulator is off." : "The device is offline.")
            } actions: {
                if device.isEmulator {
                    Button("Boot") { hub.boot(device) }.buttonStyle(.glassProminent)
                }
            }
        }
    }

    private func controls(_ mirror: Mirror) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 2) {
                bar("Back", "arrowtriangle.backward") { mirror.key(4) }
                bar("Home", "circle") { mirror.key(3) }
                    .keyboardShortcut("h", modifiers: [.command, .shift])
                bar("Recents", "square") { mirror.key(187) }
            }
            .padding(4)
            .glassEffect(in: .capsule)
            bar("Screenshot", "camera") { Task { await hub.screenshot(device) } }
                .keyboardShortcut("s")
                .padding(4)
                .glassEffect(in: .circle)
            bar("Rotate", "rotate.right") { mirror.rotate() }
                .keyboardShortcut(.rightArrow)
                .padding(4)
                .glassEffect(in: .circle)
        }
        .padding(.bottom, 16)
    }

    private func bar(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(title)
    }

    private func connect(_ serial: String) async {
        mirror = nil
        failure = nil
        let m = Mirror(serial: serial)
        m.onSize = { size = $0 }
        m.onClose = {
            mirror = nil
            failure = "Disconnected"
        }
        do {
            try await m.start()
        } catch {
            failure = "\(error)"
            return
        }
        mirror = m
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        m.stop()
    }
}

/// Device frame drawn around the screen, sized from the video's pixel dimensions.
struct Phone<Content: View>: View {
    let size: CGSize
    @ViewBuilder let content: Content

    var body: some View {
        let short = min(size.width, size.height)
        let bezel = short * 0.04
        let outer = CGSize(width: size.width + bezel * 2, height: size.height + bezel * 2)
        GeometryReader { geo in
            let k = geo.size.width / outer.width
            let radius = short * 0.1 * k
            let shell = RoundedRectangle(cornerRadius: radius + bezel * k, style: .continuous)
            ZStack {
                shell.fill(.black)
                shell.strokeBorder(
                    LinearGradient(colors: [Color(white: 0.6), Color(white: 0.28), Color(white: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: max(2, bezel * k * 0.3)
                )
                content
                    .frame(width: size.width * k, height: size.height * k)
                    .clipShape(RoundedRectangle(cornerRadius: radius, style: .continuous))
            }
            .overlay(alignment: .topTrailing) {
                if size.height > size.width {  // power and volume keys, right edge, portrait only
                    let h = geo.size.height, w = max(2, bezel * k * 0.3)
                    VStack(spacing: h * 0.04) {
                        Capsule().frame(width: w, height: h * 0.07)
                        Capsule().frame(width: w, height: h * 0.13)
                    }
                    .foregroundStyle(Color(white: 0.4))
                    .offset(x: w * 0.8, y: h * 0.2)
                }
            }
        }
        .aspectRatio(outer, contentMode: .fit)
    }
}

struct Screen: NSViewRepresentable {
    let mirror: Mirror
    func makeNSView(context: Context) -> ScreenView { ScreenView(mirror: mirror) }
    func updateNSView(_ view: ScreenView, context: Context) {}
}

/// Hosts the video layer and turns mouse and keyboard input into Android events.
final class ScreenView: NSView {
    private let mirror: Mirror
    private static let ctrl: UInt32 = 0x3000  // META_CTRL_ON | META_CTRL_LEFT_ON
    private static let commands: [Selector: (UInt32, UInt32)] = [
        #selector(NSResponder.deleteBackward(_:)): (67, 0),
        #selector(NSResponder.deleteWordBackward(_:)): (67, ctrl),
        #selector(NSResponder.deleteForward(_:)): (112, 0),
        #selector(NSResponder.insertNewline(_:)): (66, 0),
        #selector(NSResponder.insertTab(_:)): (61, 0),
        #selector(NSResponder.moveUp(_:)): (19, 0),
        #selector(NSResponder.moveDown(_:)): (20, 0),
        #selector(NSResponder.moveLeft(_:)): (21, 0),
        #selector(NSResponder.moveRight(_:)): (22, 0),
        #selector(NSResponder.moveWordLeft(_:)): (21, ctrl),
        #selector(NSResponder.moveWordRight(_:)): (22, ctrl),
        #selector(NSResponder.scrollPageUp(_:)): (92, 0),
        #selector(NSResponder.scrollPageDown(_:)): (93, 0),
    ]

    init(mirror: Mirror) {
        self.mirror = mirror
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(mirror.layer)
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        mirror.layer.frame = bounds
        CATransaction.commit()
    }

    private func point(_ event: NSEvent) -> CGPoint {
        let p = convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x / bounds.width, y: p.y / bounds.height)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        mirror.touch(0, at: point(event))
    }

    override func mouseDragged(with event: NSEvent) { mirror.touch(2, at: point(event)) }
    override func mouseUp(with event: NSEvent) { mirror.touch(1, at: point(event)) }
    override func rightMouseDown(with event: NSEvent) { mirror.key(4) }

    override func scrollWheel(with event: NSEvent) {
        // ponytail: trackpad points per notch picked by feel
        let k: CGFloat = event.hasPreciseScrollingDeltas ? 1 / 25 : 1
        mirror.scroll(at: point(event), dx: Float(-event.scrollingDeltaX * k), dy: Float(event.scrollingDeltaY * k))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { return mirror.key(4) }  // Esc is Back, like the emulator
        interpretKeyEvents([event])
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // ⌘M opens the React Native dev menu in the emulator, keep that instead of minimizing.
        if window?.firstResponder === self, event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "m" {
            mirror.key(82)
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func insertText(_ string: Any) {
        mirror.type((string as? NSAttributedString)?.string ?? string as? String ?? "")
    }

    override func doCommand(by selector: Selector) {
        if let (code, meta) = Self.commands[selector] { mirror.key(code, meta: meta) }
    }

    @objc func paste(_ sender: Any?) {
        if let text = NSPasteboard.general.string(forType: .string) { mirror.paste(text) }
    }

    @objc func copy(_ sender: Any?) { mirror.key(31, meta: Self.ctrl) }
    @objc func cut(_ sender: Any?) { mirror.key(52, meta: Self.ctrl) }
    override func selectAll(_ sender: Any?) { mirror.key(29, meta: Self.ctrl) }
}

struct InspectorView: View {
    let device: Device
    let serial: String
    @State private var dark = false
    @State private var fontScale = 1.0
    @State private var showTaps = false
    @State private var layoutBounds = false
    @State private var screen = ""

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Appearance", selection: apply($dark) { "cmd uimode night \($0 ? "yes" : "no")" }) {
                    Text("Light").tag(false)
                    Text("Dark").tag(true)
                }
                .pickerStyle(.segmented)
                Picker("Font Size", selection: apply($fontScale) { "settings put system font_scale \($0)" }) {
                    ForEach([0.85, 1, 1.15, 1.3, 1.5, 1.8, 2], id: \.self) { Text("\(Int($0 * 100))%").tag($0) }
                }
            }
            Section("Debug") {
                Toggle("Show Taps", isOn: apply($showTaps) { "settings put system show_touches \($0 ? 1 : 0)" })
                // 1599295570 is SYSPROPS_TRANSACTION: makes running apps pick up the new property.
                Toggle("Layout Bounds", isOn: apply($layoutBounds) { "setprop debug.layout \($0); service call activity 1599295570" })
            }
            Section("Device") {
                LabeledContent("Model", value: device.model)
                LabeledContent("Android", value: device.release)
                LabeledContent("API", value: device.api)
                LabeledContent("Screen", value: screen)
                LabeledContent("Serial", value: serial)
            }
        }
        .formStyle(.grouped)
        .inspectorColumnWidth(min: 240, ideal: 280)
        .task { await load() }
    }

    /// Binding that runs the adb shell command only when the user changes the value.
    private func apply<T>(_ value: Binding<T>, _ command: @escaping (T) -> String) -> Binding<T> {
        Binding(get: { value.wrappedValue }, set: { new in
            value.wrappedValue = new
            Task { await adb("-s", serial, "shell", command(new)) }
        })
    }

    private func load() async {
        func shell(_ cmd: String) async -> String {
            await adb("-s", serial, "shell", cmd).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        async let night = shell("cmd uimode night")
        async let scale = shell("settings get system font_scale")
        async let taps = shell("settings get system show_touches")
        async let bounds = shell("getprop debug.layout")
        async let size = shell("wm size")
        async let density = shell("wm density")
        dark = await night.hasSuffix("yes")
        fontScale = Double(await scale) ?? 1
        showTaps = await taps == "1"
        layoutBounds = await bounds == "true"
        let last = { (s: String) in s.split(separator: "\n").last?.split(separator: ":").last?.trimmingCharacters(in: .whitespaces) ?? "" }
        screen = "\(last(await size).replacingOccurrences(of: "x", with: "×")) · \(last(await density)) dpi"
    }
}

import SwiftUI

@main
struct DroidHubApp: App {
    @State private var hub = Hub()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window("DroidHub", id: "main") {
            ContentView().environment(hub)
        }
        .defaultSize(width: 1000, height: 900)
        .commands {
            CommandGroup(replacing: .appInfo) { Button("About DroidHub") { openWindow(id: "about") } }
            CommandGroup(replacing: .help) { Button("Welcome to DroidHub") { openWindow(id: "welcome") } }
        }
        Window("About DroidHub", id: "about") { AboutView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
        Window("Welcome to DroidHub", id: "welcome") { WelcomeView() }
            .windowStyle(.hiddenTitleBar)
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @Environment(Hub.self) private var hub
    @Environment(\.openWindow) private var openWindow
    @AppStorage("welcomed") private var welcomed = false
    @State private var query = ""
    @State private var panel: Panel?
    @State private var creating = false

    var body: some View {
        @Bindable var hub = hub
        NavigationSplitView {
            List(selection: $hub.selection) {
                section("Devices", hub.devices.filter { !$0.isEmulator })
                section("Emulators", hub.devices.filter(\.isEmulator))
            }
            .searchable(text: $query, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
            .toolbar {
                Button("New Emulator", systemImage: "plus") { creating = true }
            }
            .sheet(isPresented: $creating) { NewEmulatorSheet().environment(hub) }
        } detail: {
            if let device = hub.selected {
                DeviceView(device: device, panel: $panel).id(device.id)
            } else {
                ContentUnavailableView("No Devices", systemImage: "smartphone", description: Text("Create an emulator in Android Studio or plug in a device."))
            }
        }
        .task { await hub.poll() }
        .onAppear { if !welcomed { openWindow(id: "welcome") } }
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
    @State private var confirmingDelete = false
    @State private var deleteRefused = false

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
                    Divider()
                    Button("Delete…", role: .destructive) {
                        // An emulator started outside DroidHub has no serial until it finishes booting.
                        if let avd = device.avd, AVD.isRunning(avd) { deleteRefused = true } else { confirmingDelete = true }
                    }
                    .disabled(hub.booting.contains(device.id))
                } else {
                    Button("Shut Down") { hub.shutdown(device) }
                }
            }
        }
        .confirmationDialog("Delete \(device.name)?", isPresented: $confirmingDelete) {
            Button("Delete", role: .destructive) {
                if let avd = device.avd { try? AVD.delete(avd) }
                Task { await hub.refresh() }
            }
        } message: {
            Text("The emulator and everything installed on it go away. This can't be undone.")
        }
        .alert("\(device.name) is running", isPresented: $deleteRefused) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Shut it down before deleting it.")
        }
    }
}

struct DeviceView: View {
    @Environment(Hub.self) private var hub
    let device: Device
    @Binding var panel: Panel?
    @State private var mirror: Mirror?
    @State private var size = CGSize(width: 1080, height: 2400)
    @State private var failure: String?
    @State private var attempt = 0
    @State private var hingeAngle: Double?
    @State private var corners: [ScreenCorner] = []

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
                ToolbarItemGroup {
                    ForEach(Panel.allCases, id: \.self) { p in
                        Toggle(p.title, systemImage: p.icon, isOn: Binding(get: { panel == p }, set: { panel = $0 ? p : nil }))
                    }
                }
            }
            .inspector(isPresented: Binding(get: { panel != nil }, set: { if !$0 { panel = nil } })) {
                if let serial = device.serial {
                    switch panel {
                    case .logs: LogsView(serial: serial)
                    case .crashes: CrashesView(serial: serial)
                    default: SettingsView(device: device, serial: serial)
                    }
                } else {
                    ContentUnavailableView("Offline", systemImage: "powersleep")
                }
            }
    }

    @ViewBuilder private var content: some View {
        if let serial = device.serial {
            let bend = device.hinge.map { $0.bend(angle: hingeAngle ?? 180, video: size) }
            Phone(size: size, radius: corners.radius(for: size), bend: bend) { half in
                if let mirror {
                    VideoLayer(layer: half == 1 ? mirror.twin ?? mirror.layer : mirror.layer)
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
            .overlay { if let mirror { Screen(mirror: mirror, bend: bend ?? .flat) } }
            .animation(.smooth(duration: 0.25), value: bend)
            .padding(32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .bottom) {
                if let mirror { controls(mirror) }
            }
            .task(id: "\(serial)#\(attempt)") { await connect(serial) }
            .task(id: serial) { corners = ScreenCorner.parse(await adb("-s", serial, "shell", "dumpsys display | grep DisplayDeviceInfo")) }
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
            HStack(spacing: 2) {
                bar("Rotate", "rotate.right") { hub.rotate(device) }
                    .keyboardShortcut(.rightArrow)
                if let hinge = device.hinge { HingeControls(device: device, hinge: hinge, angle: $hingeAngle) }
            }
            .padding(4)
            .glassEffect(in: .capsule)
        }
        .padding(.bottom, 16)
    }

    private func bar(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        BarButton(title: title, icon: icon, action: action)
    }

    private func connect(_ serial: String) async {
        mirror = nil
        failure = nil
        let m = Mirror(serial: serial, twin: device.hinge != nil)
        m.onSize = { size = $0 }
        m.onClose = { [weak m] in
            m?.stop()  // frees the server and the adb forward now, not at the next Retry
            mirror = nil
            failure = "Disconnected"
        }
        do {
            try await m.start()
        } catch {
            m.stop()
            failure = "\(error)"
            return
        }
        mirror = m
        while !Task.isCancelled { try? await Task.sleep(for: .seconds(3600)) }
        m.stop()
    }
}

struct BarButton: View {
    let title: String
    let icon: String
    var selected = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 14, weight: .medium)).frame(width: 30, height: 30).contentShape(.rect)
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct HingeControls: View {
    @Environment(Hub.self) private var hub
    let device: Device
    let hinge: Hinge
    @Binding var angle: Double?
    @State private var dragging = false

    var body: some View {
        let shown = angle ?? hinge.range.upperBound
        HStack(spacing: 2) {
            Divider().frame(height: 18).padding(.horizontal, 4)
            ForEach(hinge.postures) { p in
                BarButton(title: p.title, icon: p.icon, selected: angle.flatMap(hinge.posture) == p) {
                    Task {
                        await hub.fold(device, to: p)
                        angle = await hub.hingeAngle(device)
                    }
                }
            }
            Divider().frame(height: 18).padding(.horizontal, 4)
            Slider(value: Binding(get: { shown }, set: { angle = $0.rounded(); hub.setHinge(device, angle: $0) }), in: hinge.range) { dragging = $0 }
                .controlSize(.small)
                .frame(width: 110)
                .accessibilityLabel("Hinge Angle")
            Text("\(Int(shown))°")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
                .padding(.trailing, 6)
        }
        .task(id: device.serial) {
            // Polls so a fold made elsewhere (adb, another tool) shows up here too.
            while !Task.isCancelled {
                if let a = await hub.hingeAngle(device), !dragging { angle = a }
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

/// Device frame drawn around the screen, sized from the video's pixel dimensions.
struct Phone<Content: View>: View {
    let size: CGSize
    /// Screen corner radius, in video pixels.
    let radius: CGFloat
    /// Set for foldables, which draw each half of the frame on its own.
    var bend: Bend?
    /// The screen for half `i`. A phone that doesn't fold only asks for half 0.
    @ViewBuilder let content: (Int) -> Content

    var body: some View {
        Group {
            if let bend {
                ZStack {
                    ForEach(0..<2, id: \.self) { i in
                        shell(content(i))
                            .clipShape(HalfShape(half: i, vertical: bend.vertical))
                            .modifier(FoldEffect(bend: bend, half: i))
                    }
                }
            } else {
                shell(content(0))
            }
        }
        .aspectRatio(PhoneFrame.outer(size), contentMode: .fit)
    }

    private func shell(_ screen: some View) -> some View {
        let bezel = PhoneFrame.bezel(size)
        return GeometryReader { geo in
            let k = geo.size.width / PhoneFrame.outer(size).width
            let r = radius * k
            let shell = RoundedRectangle(cornerRadius: r + bezel * k, style: .continuous)
            ZStack {
                shell.fill(.black)
                shell.strokeBorder(
                    LinearGradient(colors: [Color(white: 0.6), Color(white: 0.28), Color(white: 0.5)], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: max(2, bezel * k * 0.3)
                )
                screen
                    .frame(width: size.width * k, height: size.height * k)
                    .clipShape(RoundedRectangle(cornerRadius: r, style: .continuous))
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
    }
}

enum PhoneFrame {
    static func bezel(_ size: CGSize) -> CGFloat { min(size.width, size.height) * 0.04 }

    static func outer(_ size: CGSize) -> CGSize {
        CGSize(width: size.width + bezel(size) * 2, height: size.height + bezel(size) * 2)
    }

    /// Where the screen sits in a frame of `frame` points.
    static func screen(video size: CGSize, in frame: CGSize) -> CGRect {
        let k = frame.width / outer(size).width
        return CGRect(x: bezel(size) * k, y: bezel(size) * k, width: size.width * k, height: size.height * k)
    }
}

/// A display's screen corners, from `dumpsys display`. Android 12 and later report them, in pixels of that display.
struct ScreenCorner: Equatable {
    let size: CGSize
    let radius: CGFloat

    static func parse(_ dump: String) -> [ScreenCorner] {
        dump.split(separator: "\n").compactMap { line in
            guard let s = line.firstMatch(of: #/, (\d+) x (\d+),/#), let r = line.firstMatch(of: #/RoundedCorner\{[^}]*radius=(\d+)/#),
                  let w = Double(s.1), let h = Double(s.2), let radius = Double(r.1) else { return nil }
            return ScreenCorner(size: CGSize(width: w, height: h), radius: radius)
        }
    }
}

extension [ScreenCorner] {
    /// Corner radius for a video of `size`, scaled from the display with the same shape. scrcpy may shrink the video, so this matches on shape, not size.
    func radius(for size: CGSize) -> CGFloat {
        func shape(_ s: CGSize) -> CGFloat { Swift.min(s.width, s.height) / Swift.max(s.width, s.height) }
        let off = { (c: ScreenCorner) in abs(shape(c.size) - shape(size)) }
        // A guess close to a Pixel's, for Android 11 and older.
        guard let match = filter({ off($0) < 0.02 }).min(by: { off($0) < off($1) }) else { return Swift.max(size.width, size.height) * 0.045 }
        return match.radius * Swift.min(size.width, size.height) / Swift.min(match.size.width, match.size.height)
    }
}

/// Hosts one of the mirror's video layers. The ScreenView on top takes the input.
struct VideoLayer: NSViewRepresentable {
    let layer: CALayer
    func makeNSView(context: Context) -> LayerHost { LayerHost(hosted: layer) }
    func updateNSView(_ view: LayerHost, context: Context) { view.hosted = layer }
}

final class LayerHost: NSView {
    var hosted: CALayer {
        didSet {
            guard hosted !== oldValue else { return }
            oldValue.removeFromSuperlayer()
            layer?.addSublayer(hosted)
            needsLayout = true
        }
    }

    init(hosted: CALayer) {
        self.hosted = hosted
        super.init(frame: .zero)
        wantsLayer = true
        layer?.addSublayer(hosted)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosted.frame = bounds
        CATransaction.commit()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}

struct Screen: NSViewRepresentable {
    let mirror: Mirror
    var bend = Bend.flat
    func makeNSView(context: Context) -> ScreenView { ScreenView(mirror: mirror) }
    func updateNSView(_ view: ScreenView, context: Context) { view.bend = bend }
}

/// Covers the device frame and turns mouse and keyboard input into Android events.
final class ScreenView: NSView {
    private let mirror: Mirror
    var bend = Bend.flat
    private var marked: String?
    private var touching = false
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
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Device screen")
    }

    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func viewDidMoveToWindow() {
        DispatchQueue.main.async { self.window?.makeFirstResponder(self) }
    }

    private var screen: CGRect { PhoneFrame.screen(video: mirror.size, in: bounds.size) }

    /// Mouse position on the screen, 0...1 on each axis.
    private func point(_ event: NSEvent) -> CGPoint {
        // Clicks land on the bent frame, so they get mapped back onto the flat screen first.
        let p = bend.unproject(convert(event.locationInWindow, from: nil), size: bounds.size)
        return CGPoint(x: (p.x - screen.minX) / screen.width, y: (p.y - screen.minY) / screen.height)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let p = point(event)
        // A click on the bezel isn't a touch.
        guard (0...1).contains(p.x), (0...1).contains(p.y) else { return }
        touching = true
        mirror.touch(0, at: p)
    }

    override func mouseDragged(with event: NSEvent) {
        if touching { mirror.touch(2, at: point(event)) }
    }

    override func mouseUp(with event: NSEvent) {
        if touching { mirror.touch(1, at: point(event)) }
        touching = false
    }
    override func rightMouseDown(with event: NSEvent) { mirror.key(4) }

    override func scrollWheel(with event: NSEvent) {
        // Trackpads report points and wheels report notches. Converting points at the
        // current zoom keeps the content under the fingers.
        let k = event.hasPreciseScrollingDeltas ? 1 / mirror.pointsPerNotch(viewWidth: screen.width) : 1
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

/// Being a text input client is what makes dead keys and input methods work: the
/// system composes "´" and "e" into "é" and hands over the finished text.
extension ScreenView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        marked = nil
        mirror.type((string as? NSAttributedString)?.string ?? string as? String ?? "")
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        marked = (string as? NSAttributedString)?.string ?? string as? String
    }

    func unmarkText() { marked = nil }
    func hasMarkedText() -> Bool { marked != nil }
    func markedRange() -> NSRange { NSRange(location: marked == nil ? NSNotFound : 0, length: (marked as NSString?)?.length ?? 0) }
    func selectedRange() -> NSRange { NSRange(location: NSNotFound, length: 0) }
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? { nil }
    func validAttributesForMarkedText() -> [NSAttributedString.Key] { [] }
    func characterIndex(for point: NSPoint) -> Int { NSNotFound }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        window?.convertToScreen(convert(bounds, to: nil)) ?? .zero
    }
}

struct SettingsView: View {
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
                    .accessibilityLabel("Show Taps")
                // 1599295570 is SYSPROPS_TRANSACTION: makes running apps pick up the new property.
                Toggle("Layout Bounds", isOn: apply($layoutBounds) { "setprop debug.layout \($0); service call activity 1599295570" })
                    .accessibilityLabel("Layout Bounds")
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

import Foundation
import Testing
@testable import DroidHub

@Test func readsTheSerialFromASelectLink() {
    #expect(Hub.serial(from: URL(string: "droidhub://select?serial=emulator-5572")!) == "emulator-5572")
}

@Test func ignoresOtherLinks() {
    #expect(Hub.serial(from: URL(string: "droidhub://open?serial=emulator-5572")!) == nil)
    #expect(Hub.serial(from: URL(string: "droidhub://select")!) == nil)
    #expect(Hub.serial(from: URL(string: "https://select?serial=emulator-5572")!) == nil)
}

import Foundation
import Testing
@testable import DroidHub

@Test func parsesThreadtime() throws {
    let line = try #require(LogLine("09-11 16:45:01.123  1234  5678 I ReactNativeJS: Running \"main\": ok"))
    #expect(line.time == "09-11 16:45:01.123")
    #expect(line.pid == "1234")
    #expect(line.level == "I")
    #expect(line.tag == "ReactNativeJS")
    #expect(line.message == "Running \"main\": ok")
    #expect(LogLine("--------- beginning of main") == nil)
}

@Test func groupsCrashes() {
    let buffer = """
    09-11 16:00:00.000  1234  1234 E AndroidRuntime: FATAL EXCEPTION: main
    09-11 16:00:00.000  1234  1234 E AndroidRuntime: Process: com.example, PID: 1234
    09-11 16:00:00.000  1234  1234 E AndroidRuntime: java.lang.RuntimeException: boom
    09-11 16:00:00.000  1234  1234 E AndroidRuntime: \tat com.example.Main.onCreate(Main.java:10)
    09-11 16:05:00.000  4321  4321 F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
    09-11 16:05:00.000  4321  4321 F DEBUG   : Process uptime: 3s
    09-11 16:05:00.000  4321  4321 F DEBUG   : pid: 999, tid: 999, name: example  >>> com.example.native <<<
    09-11 16:05:00.000  4321  4321 F DEBUG   : signal 11 (SIGSEGV), code 1 (SEGV_MAPERR), fault addr 0x0
    """
    let crashes = Crash.parse(buffer.split(separator: "\n").compactMap { LogLine($0) })
    #expect(crashes.map(\.process) == ["com.example.native", "com.example"])
    #expect(crashes[0].summary.hasPrefix("signal 11"))
    #expect(crashes[1].summary == "java.lang.RuntimeException: boom")
    #expect(crashes[1].text.hasPrefix("FATAL EXCEPTION: main\nProcess: com.example"))
}

// Shape of a real native crash from an Android 17 emulator's crash buffer.
@Test func nativeCrashKeepsLibcLineAndPrefersAbortMessage() {
    let buffer = """
    09-11 16:04:00.029   997  1185 F libc    : Fatal signal 6 (SIGABRT), code -1 (SI_QUEUE) in tid 1185 (gd_stack_thread), pid 997 (droid.bluetooth)
    09-11 16:04:00.201 23291 23291 F DEBUG   : *** *** *** *** *** *** *** *** *** *** *** *** *** *** *** ***
    09-11 16:04:00.201 23291 23291 F DEBUG   : pid: 997, ppid: 426, tid: 1185, name: gd_stack_thread  >>> com.google.android.bluetooth <<<
    09-11 16:04:00.201 23291 23291 F DEBUG   : esr: 0000000092000006 (Data Abort Exception 0x24)
    09-11 16:04:00.201 23291 23291 F DEBUG   : signal 6 (SIGABRT), code -1 (SI_QUEUE), fault addr --------
    09-11 16:04:00.201 23291 23291 F DEBUG   : Abort message: 'hci_layer.cc:565 on_hardware_error'
    """
    let crashes = Crash.parse(buffer.split(separator: "\n").compactMap { LogLine($0) })
    #expect(crashes.count == 1)
    #expect(crashes[0].process == "com.google.android.bluetooth")
    #expect(crashes[0].summary == "Abort message: 'hci_layer.cc:565 on_hardware_error'")
    #expect(crashes[0].time == "09-11 16:04:00.029")
}

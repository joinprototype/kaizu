import BrowserCore
import Testing

struct SitePermissionTests {
    @Test func jointCaptureRequestUsesEachDeviceChoice() {
        let both = ["camera", "microphone"]
        #expect(SitePermissionDecision.resolve(both, saved: [:]) == .ask(both))
        #expect(SitePermissionDecision.resolve(both, saved: ["camera": true]) == .ask(["microphone"]))
        #expect(SitePermissionDecision.resolve(both, saved: ["microphone": true]) == .ask(["camera"]))
        #expect(SitePermissionDecision.resolve(both, saved: ["camera": false]) == .deny)
        #expect(SitePermissionDecision.resolve(both, saved: ["camera": true, "microphone": false]) == .deny)
        #expect(SitePermissionDecision.resolve(both, saved: ["camera": true, "microphone": true]) == .allow)
        #expect(SitePermissionDecision.resolve(["camera"], saved: ["microphone": false]) == .ask(["camera"]))
    }
}

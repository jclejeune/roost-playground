import RoostPlayground
import Testing

@Test func browserAssetsAreBundledLocally() {
    #expect(LiveAssets.javascript(named: "esw-live.js")?.contains("class LiveClient") == true)
    #expect(LiveAssets.javascript(named: "idiomorph.js")?.contains("Idiomorph") == true)
    #expect(LiveAssets.javascript(named: "../LiveView.swift") == nil)
}

import Foundation
@testable import RoostPlayground
import Testing

private struct Codified: Codable, Equatable, Sendable { var count: Int }
private struct Reshaped: Codable, Sendable { var count: Int; var label: String }
private struct Opaque: Sendable { var count: Int }

@Test func codableStateTravelsToTheNextProcessUntilABrowserConnects() throws {
    let old = PreservedState<Codified>(seed: nil)
    old.record(Codified(count: 1))
    old.record(Codified(count: 3))
    let data = try #require(old.encodedLatest())
    let next = PreservedState<Codified>(seed: PreservedState<Codified>.decode(data))
    #expect(next.seed(connected: false) == Codified(count: 3), "Health checks and the first render see the carried state")
    #expect(next.seed(connected: true) == Codified(count: 3))
    #expect(next.seed(connected: false) == nil, "A later page load mounts fresh")
}

@Test func otherStatesStartFresh() throws {
    let opaque = PreservedState<Opaque>(seed: nil)
    opaque.record(Opaque(count: 3))
    #expect(opaque.encodedLatest() == nil)
    #expect(PreservedState<Codified>(seed: nil).encodedLatest() == nil, "Nothing rendered yet")
    let data = try JSONEncoder().encode(Codified(count: 3))
    #expect(PreservedState<Reshaped>.decode(data) == nil, "A changed shape cannot decode")
    #expect(PreservedState<Opaque>.decode(data) == nil)
}

import XCTest
@testable import Route_Builder

@MainActor
final class RouteDraftTests: XCTestCase {
    func testInitialsAndSectionLetter() {
        let pharmacy = makeStop(id: "1", name: "24/7 Pharmacy")
        let hardware = makeStop(id: "2", name: "Isaac's Hardware")
        XCTAssertEqual(pharmacy.initials, "2P")
        XCTAssertEqual(pharmacy.sectionLetter, "2")
        XCTAssertEqual(hardware.initials, "IH")
    }

    func testSectionsKeepServerOrderInsideALetter() {
        let stops = [
            makeStop(id: "n", name: "North Cafe"),
            makeStop(id: "a1", name: "Almond Patisserie"),
            makeStop(id: "a2", name: "Amber Wine Bar")
        ]
        let sections = StopGrouping.sections(stops)
        XCTAssertEqual(sections.map(\.letter), ["A", "N"])
        XCTAssertEqual(sections[0].stops.map(\.id), ["a1", "a2"])
        XCTAssertEqual(sections[1].stops.map(\.id), ["n"])
    }

    func testOneStopReplacesAndTappingAgainClears() {
        var draft = RouteDraft(mode: .oneStop)
        let first = makeStop(id: "a", name: "Almond")
        let second = makeStop(id: "b", name: "Bluebell")
        draft.select(first)
        draft.select(second)
        XCTAssertEqual(draft.stops.map(\.stopID), ["b"])
        draft.select(second)
        XCTAssertTrue(draft.stops.isEmpty)
    }

    func testMultiStopTogglesAndKeepsOrder() {
        var draft = RouteDraft(mode: .multiStop)
        let first = makeStop(id: "a", name: "Almond")
        let second = makeStop(id: "b", name: "Bluebell")
        draft.select(first)
        draft.select(second)
        draft.select(first)
        XCTAssertEqual(draft.stops.map(\.stopID), ["b"])
    }

    func testDefaultModeIsOneStop() {
        XCTAssertEqual(RouteDraft().mode, .oneStop)
    }

    func testSwitchingToOneStopKeepsTheFirstStop() {
        var draft = RouteDraft(mode: .multiStop)
        draft.select(makeStop(id: "a", name: "Almond"))
        draft.select(makeStop(id: "b", name: "Bluebell"))
        draft.setMode(.oneStop)
        XCTAssertEqual(draft.mode, .oneStop)
        XCTAssertEqual(draft.stops.map(\.stopID), ["a"])
    }

    func testPackageClamp() {
        var draft = RouteDraft()
        draft.select(makeStop(id: "a", name: "Almond", packagesMax: 4))
        draft.setPackages(stopID: "a", packages: 0)
        XCTAssertEqual(draft.stops[0].packages, 1)
        draft.setPackages(stopID: "a", packages: 9)
        XCTAssertEqual(draft.stops[0].packages, 4)
    }

    func testInstructionsStayWithin200Characters() {
        var draft = RouteDraft()
        draft.select(makeStop(id: "a", name: "Almond"))
        draft.setInstructions(stopID: "a", text: String(repeating: "x", count: 250))
        XCTAssertEqual(draft.stops[0].instructions.count, 200)
    }

    func testInvalidInstructionsUseTrimmedText() {
        var draft = RouteDraft(mode: .multiStop)
        draft.select(makeStop(id: "a", name: "Almond"))
        draft.select(makeStop(id: "b", name: "Bluebell"))
        draft.select(makeStop(id: "c", name: "Cafe"))
        draft.setInstructions(stopID: "b", text: "   ")
        draft.setInstructions(stopID: "c", text: "  hi ")
        XCTAssertEqual(draft.invalidStopIDs(), ["a", "b"])
    }

    func testRemoveDropsTheStop() {
        var draft = RouteDraft()
        draft.select(makeStop(id: "a", name: "Almond"))
        draft.setInstructions(stopID: "a", text: "Ring twice")
        draft.remove(stopID: "a")
        XCTAssertTrue(draft.stops.isEmpty)
    }

    func testSubtitleSumsPackages() {
        var draft = RouteDraft(mode: .multiStop)
        draft.select(makeStop(id: "a", name: "Almond"))
        draft.select(makeStop(id: "b", name: "Bluebell"))
        draft.setPackages(stopID: "a", packages: 2)
        draft.setPackages(stopID: "b", packages: 3)
        XCTAssertEqual(draft.subtitle, "5 packages | 2 stops")
    }

    func testStoreNotifiesOnce() async {
        let store = RouteDraftStore()
        let listener = DraftEventCounter()
        store.addListener(listener)
        store.update { $0.setMode(.oneStop) }
        XCTAssertEqual(listener.count, 1)
        XCTAssertEqual(store.draft.mode, .oneStop)
    }

    private func makeStop(id: String, name: String, packagesMax: Int = 9) -> Stop {
        Stop(id: id, name: name, address: "1 Road", phone: "020", zone: "north", packagesMax: packagesMax)
    }
}

nonisolated private final class DraftEventCounter: RouteDraftListener {
    var count = 0

    func routeDraftDidChange(_ draft: RouteDraft) {
        count += 1
    }
}

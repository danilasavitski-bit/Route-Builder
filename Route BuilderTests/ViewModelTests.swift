import XCTest
@testable import Route_Builder

@MainActor
final class ViewModelTests: XCTestCase {
    func testEmptySearchUsesTheLoadedCatalog() async {
        let api = FakeAPI()
        let cafe = makeStop(id: "c", name: "Cafe")
        api.stopsResult[""] = .success([cafe])
        let store = RouteDraftStore()
        let viewModel = StopsViewModel(api: api, store: store, debounceNanoseconds: 0)
        await viewModel.load()
        viewModel.searchTextChanged("")
        XCTAssertEqual(api.queries, [nil])
        XCTAssertEqual(viewModel.sections.map(\.letter), ["C"])
    }

    func testSearchAsksTheServerAndKeepsThePreviousListOnFailure() async {
        let api = FakeAPI()
        let cafe = makeStop(id: "c", name: "Cafe")
        api.stopsResult[""] = .success([cafe])
        api.stopsResult["North"] = .failure(APIError.transport)
        let viewModel = StopsViewModel(api: api, store: RouteDraftStore(), debounceNanoseconds: 0)
        await viewModel.load()
        viewModel.searchTextChanged("North")
        await waitUntil { viewModel.searchFailed }
        XCTAssertEqual(viewModel.sections.flatMap(\.stops).map(\.id), ["c"])
    }

    func testEmptySearchResultClearsSections() async {
        let api = FakeAPI()
        api.stopsResult[""] = .success([makeStop(id: "c", name: "Cafe")])
        api.stopsResult["ZZZ"] = .success([])
        let viewModel = StopsViewModel(api: api, store: RouteDraftStore(), debounceNanoseconds: 0)
        await viewModel.load()
        viewModel.searchTextChanged("ZZZ")
        await waitUntil { viewModel.sections.isEmpty && viewModel.query == "ZZZ" }
        XCTAssertFalse(viewModel.searchFailed)
    }

    func testFinishBlocksEmptyInstructions() async {
        let api = FakeAPI()
        let store = RouteDraftStore()
        store.update { $0.select(makeStop(id: "a", name: "Almond")) }
        let viewModel = InstructionsViewModel(api: api, store: store)
        await viewModel.finish()
        XCTAssertEqual(api.createCount, 0)
        XCTAssertEqual(viewModel.invalidStopIDs, ["a"])
        XCTAssertEqual(viewModel.consumeScrollRequest(), "a")
    }

    func testOverlappingFinishSendsOneRoute() async {
        let api = GateAPI()
        let store = filledStore()
        let viewModel = InstructionsViewModel(api: api, store: store)
        let first = Task { await viewModel.finish() }
        await waitUntil { api.createCount == 1 }
        let second = Task { await viewModel.finish() }
        await Task.yield()
        XCTAssertEqual(api.createCount, 1)
        api.resumeSuccess()
        await first.value
        await second.value
        XCTAssertEqual(api.createCount, 1)
        XCTAssertEqual(viewModel.submitState, .succeeded(routeID: "rt_1"))
    }

    func testValidationFailureSurfacesARetryMessage() async {
        let api = FakeAPI()
        api.createResult = .failure(APIError.validation(["stops": "required"]))
        let viewModel = InstructionsViewModel(api: api, store: filledStore())
        await viewModel.finish()
        XCTAssertEqual(viewModel.submitState, .failed("Could not send the route. Try again."))
    }

    func testFailedNotifyRetriesWithANewKey() async {
        let api = FakeAPI()
        api.notifyResult = NotifyResult(stopID: "a", status: "failed", reason: "carrier_rejected")
        let viewModel = InstructionsViewModel(api: api, store: filledStore())
        await viewModel.finish()
        XCTAssertEqual(viewModel.submitState, .succeeded(routeID: "rt_2000"))
        XCTAssertEqual(viewModel.notices.map(\.status), ["failed"])
        XCTAssertEqual(viewModel.notices.first?.reason, "carrier_rejected")
        api.notifyResult = NotifyResult(stopID: "a", status: "sent", reason: nil)
        await viewModel.retryFailedNotices()
        XCTAssertEqual(viewModel.notices.map(\.status), ["sent"])
        XCTAssertEqual(api.notifyKeys.count, 2)
        XCTAssertNotEqual(api.notifyKeys[0], api.notifyKeys[1])
    }

    func testManualAddressSelectsALocalStopWithTheFallbackLimit() async {
        let store = RouteDraftStore()
        let viewModel = StopsViewModel(api: FakeAPI(), store: store)
        viewModel.addManual(name: " Side door ", address: " 9 Dock ", phone: " 555 ")
        XCTAssertEqual(store.draft.stops.count, 1)
        XCTAssertEqual(store.draft.stops[0].name, "Side door")
        XCTAssertEqual(store.draft.stops[0].address, "9 Dock")
        XCTAssertEqual(store.draft.stops[0].phone, "555")
        XCTAssertEqual(store.draft.stops[0].packagesMax, 99)
        XCTAssertTrue(store.draft.stops[0].stopID.hasPrefix("local_"))
    }

    func testInstructionCardsKeepTheDesignHeightAndCanScroll() {
        let store = RouteDraftStore()
        store.update {
            $0.setMode(.multiStop)
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.select(makeStop(id: "b", name: "Birch"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
            $0.setInstructions(stopID: "b", text: "Leave at the door")
        }
        let controller = InstructionsViewController(
            viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
            store: store
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let collection = controller.view.subviews.compactMap { $0 as? UICollectionView }.first
        let height = collection?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0))?.frame.height ?? 0
        let textView = collection?.cellForItem(at: IndexPath(item: 0, section: 0)).flatMap(textView(in:))
        XCTAssertGreaterThan(height, 300)
        XCTAssertLessThan(height, (collection?.bounds.height ?? 0) - 80)
        XCTAssertGreaterThan(collection?.contentSize.height ?? 0, (collection?.bounds.height ?? 0) + 1)
        XCTAssertEqual(textView?.isScrollEnabled, false)
        XCTAssertEqual(textView?.panGestureRecognizer.isEnabled, false)
        collection?.setContentOffset(CGPoint(x: 0, y: 120), animated: false)
        controller.view.layoutIfNeeded()
        XCTAssertEqual(collection?.contentOffset.y ?? -1, 120)
    }

    func testBlurLeavesTheCardUnderTheFinger() {
        let store = RouteDraftStore()
        store.update {
            $0.setMode(.multiStop)
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.select(makeStop(id: "b", name: "Birch"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
            $0.setInstructions(stopID: "b", text: "Leave at the door")
        }
        let controller = InstructionsViewController(
            viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
            store: store
        )
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()

        let collection = controller.view.subviews.compactMap { $0 as? UICollectionView }.first
        let cell = collection?.cellForItem(at: IndexPath(item: 0, section: 0)) as? InstructionCardCell
        cell?.setActive(false)

        let text = cell.flatMap(textView(in:))
        var view: UIView? = text
        while let current = view {
            XCTAssertGreaterThan(current.alpha, 0.01)
            XCTAssertFalse(current.isHidden)
            view = current.superview
        }
        let blurred = cell.map { imageViews(in: $0).contains { !$0.isHidden && $0.image != nil } } ?? false
        XCTAssertTrue(blurred)
    }

    private func imageViews(in view: UIView) -> [UIImageView] {
        var found = view.subviews.compactMap { $0 as? UIImageView }
        for subview in view.subviews {
            found += imageViews(in: subview)
        }
        return found
    }

    private func textView(in view: UIView) -> UITextView? {
        if let textView = view as? UITextView { return textView }
        for subview in view.subviews {
            if let textView = textView(in: subview) { return textView }
        }
        return nil
    }

    func testEditingTheDraftClearsSuccess() async {
        let api = FakeAPI()
        let store = filledStore()
        let viewModel = InstructionsViewModel(api: api, store: store)
        await viewModel.finish()
        XCTAssertEqual(viewModel.submitState, .succeeded(routeID: "rt_2000"))
        viewModel.draftChanged()
        XCTAssertEqual(viewModel.submitState, .idle)
    }

    private func filledStore() -> RouteDraftStore {
        let store = RouteDraftStore()
        store.update {
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
        }
        return store
    }

    private func makeStop(id: String, name: String) -> Stop {
        Stop(id: id, name: name, address: "Road", phone: "1", zone: "north", packagesMax: 4)
    }

    private func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<50 where !condition() {
            await Task.yield()
        }
    }
}

@MainActor
private final class FakeAPI: DispatchAPI {
    var stopsResult: [String: Result<[Stop], Error>] = [:]
    var queries: [String?] = []
    var createResult: Result<CreatedRoute, Error> = .success(CreatedRoute(id: "rt_2000", status: "draft"))
    var createCount = 0
    var notifyResult = NotifyResult(stopID: "", status: "sent", reason: nil)
    var notifyKeys: [String] = []

    func fetchStops(query: String?) async throws -> [Stop] {
        queries.append(query)
        return try (stopsResult[query ?? ""] ?? .success([])).get()
    }

    func fetchPhotos(stopID: String) async throws -> [StopPhoto] { [] }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        createCount += 1
        return try createResult.get()
    }

    func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult {
        notifyKeys.append(idempotencyKey)
        return NotifyResult(stopID: stopID, status: notifyResult.status, reason: notifyResult.reason)
    }
}

@MainActor
private final class GateAPI: DispatchAPI {
    var createCount = 0
    private var continuations: [CheckedContinuation<CreatedRoute, Error>] = []

    func fetchStops(query: String?) async throws -> [Stop] { [] }

    func fetchPhotos(stopID: String) async throws -> [StopPhoto] { [] }

    func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult {
        NotifyResult(stopID: stopID, status: "sent", reason: nil)
    }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        createCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func resumeSuccess() {
        let pending = continuations
        continuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: CreatedRoute(id: "rt_1", status: "draft"))
        }
    }
}

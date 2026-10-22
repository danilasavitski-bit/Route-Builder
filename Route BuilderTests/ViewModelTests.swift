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

    func testEmptySearchOffersManualAddressSeparately() async {
        let api = FakeAPI()
        api.stopsResult[""] = .success([makeStop(id: "c", name: "Cafe")])
        api.stopsResult["ZZZ"] = .success([])
        let store = RouteDraftStore()
        let viewModel = StopsViewModel(api: api, store: store, debounceNanoseconds: 0)
        await viewModel.load()
        viewModel.searchTextChanged("ZZZ")
        await waitUntil { viewModel.sections.isEmpty && viewModel.query == "ZZZ" }
        autoreleasepool {
            let controller = StopsViewController(viewModel: viewModel, store: store, onContinue: {})
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            XCTAssertNotNil(label(in: controller.view, text: "No stop found"))
            XCTAssertNotNil(label(in: controller.view, text: "Try another street"))
            XCTAssertNotNil(buttonTitled("Enter an address", in: controller.view))
            XCTAssertNil(buttonTitled("Try another street or enter an address manually", in: controller.view))
            window.isHidden = true
            window.rootViewController = nil
        }
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

    func testNotifyUsesTheStopsThatWerePosted() async {
        let api = GateAPI()
        let store = filledStore()
        let viewModel = InstructionsViewModel(api: api, store: store)
        let task = Task { await viewModel.finish() }
        await waitUntil { api.createCount == 1 }
        store.update {
            $0.setMode(.multiStop)
            $0.select(makeStop(id: "b", name: "Birch"))
        }
        api.resumeSuccess()
        await task.value
        XCTAssertEqual(api.postedStopIDs, ["a"])
        XCTAssertEqual(viewModel.notices.map(\.stopID), ["a"])
        XCTAssertEqual(api.notifiedStopIDs, ["a"])
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

    func testFinishCanStartAgainWhileNoticesAreStillSending() async {
        let api = SplitGateAPI()
        let store = filledStore()
        let viewModel = InstructionsViewModel(api: api, store: store)
        let first = Task { await viewModel.finish() }
        await waitUntil { api.createCount == 1 }
        api.resumeCreate()
        await waitUntil { api.notifyStarted == 1 }
        viewModel.draftChanged()
        let second = Task { await viewModel.finish() }
        await waitUntil { api.createCount == 2 }
        XCTAssertEqual(api.createCount, 2)
        api.resumeCreate()
        await waitUntil { api.notifyStarted == 2 }
        api.resumeNotifies()
        await first.value
        await second.value
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

    func testRemovingAStopOnInstructionsRefreshesStops() async {
        let store = RouteDraftStore()
        store.update { $0.setMode(.multiStop) }
        let stops = StopsViewModel(api: FakeAPI(), store: store)
        let instructions = InstructionsViewModel(api: FakeAPI(), store: store)
        store.update {
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.select(makeStop(id: "b", name: "Birch"))
        }
        var refreshes = 0
        stops.onChange = { refreshes += 1 }
        instructions.remove(stopID: "a")
        XCTAssertEqual(store.draft.stops.map(\.stopID), ["b"])
        XCTAssertEqual(refreshes, 1)
    }

    func testInstructionCardShowsTheUpdatedPackageCount() async {
        let store = RouteDraftStore()
        store.update {
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
        }
        autoreleasepool {
            let controller = InstructionsViewController(
                viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
                store: store
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            XCTAssertNotNil(label(in: controller.view, text: "1×"))

            store.update { $0.setPackages(stopID: "a", packages: 3) }
            controller.render()
            XCTAssertNil(label(in: controller.view, text: "1×"))
            XCTAssertNotNil(label(in: controller.view, text: "3×"))
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testRemoveButtonDropsTheStop() async {
        let store = RouteDraftStore()
        store.update {
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
        }
        autoreleasepool {
            let controller = InstructionsViewController(
                viewModel: InstructionsViewModel(api: FakeAPI(), store: store),
                store: store
            )
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            let button = buttonTitled("Remove from route", in: controller.view)
            XCTAssertNotNil(button)
            button?.sendActions(for: .touchUpInside)
            XCTAssertTrue(store.draft.stops.isEmpty)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testSectionIndexSitsOnTheTrailingEdge() async {
        let api = FakeAPI()
        api.stopsResult[""] = .success([makeStop(id: "a", name: "Almond")])
        let store = RouteDraftStore()
        let viewModel = StopsViewModel(api: api, store: store, debounceNanoseconds: 0)
        await viewModel.load()
        autoreleasepool {
            let controller = StopsViewController(viewModel: viewModel, store: store, onContinue: {})
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 700))
            window.rootViewController = controller
            window.makeKeyAndVisible()
            controller.view.layoutIfNeeded()
            let index = stackOfLetters(in: controller.view)
            XCTAssertNotNil(index)
            XCTAssertGreaterThan(index?.frame.minX ?? 0, 360)
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testInstructionCardsKeepTheDesignHeightAndCanScroll() async {
        let store = RouteDraftStore()
        store.update {
            $0.setMode(.multiStop)
            $0.select(makeStop(id: "a", name: "Almond"))
            $0.select(makeStop(id: "b", name: "Birch"))
            $0.setInstructions(stopID: "a", text: "Ring the bell")
            $0.setInstructions(stopID: "b", text: "Leave at the door")
        }
        autoreleasepool {
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
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testBlurLeavesTheCardUnderTheFinger() {
        autoreleasepool {
            let cell = InstructionCardCell(frame: CGRect(x: 0, y: 0, width: 390, height: 420))
            let window = UIWindow(frame: cell.frame)
            window.addSubview(cell)
            window.makeKeyAndVisible()
            cell.setActive(false)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))

            let text = textView(in: cell)
            var view: UIView? = text
            while let current = view {
                XCTAssertGreaterThan(current.alpha, 0.01)
                XCTAssertFalse(current.isHidden)
                view = current.superview
            }
            let blurred = effectViews(in: cell).first { $0.effect != nil }
            XCTAssertNotNil(blurred)
            XCTAssertFalse(blurred?.isUserInteractionEnabled ?? true)

            cell.setActive(true)
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            XCTAssertFalse(effectViews(in: cell).contains { $0.effect != nil })
            window.isHidden = true
            window.rootViewController = nil
        }
    }

    func testDropOffButtonUsesOneLayout() {
        autoreleasepool {
            let narrow = laidOutCard(width: 220)
            let wide = laidOutCard(width: 390)
            XCTAssertEqual(dropOffTitle(in: narrow)?.frame.minX ?? -1, 42, accuracy: 0.5)
            XCTAssertEqual(dropOffTitle(in: wide)?.frame.minX ?? -1, 42, accuracy: 0.5)
            for window in hostedWindows {
                window.isHidden = true
                window.rootViewController = nil
            }
            hostedWindows.removeAll()
        }
    }

    private var hostedWindows: [UIWindow] = []

    private func laidOutCard(width: CGFloat) -> InstructionCardCell {
        let cell = InstructionCardCell(frame: .zero)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: width, height: 600))
        hostedWindows.append(window)
        window.addSubview(cell)
        window.makeKeyAndVisible()
        cell.frame = CGRect(x: 0, y: 0, width: width, height: 520)
        cell.layoutIfNeeded()
        return cell
    }

    private func dropOffTitle(in view: UIView) -> UILabel? {
        if let label = view as? UILabel, label.text == "Photo of the drop-off point" { return label }
        for subview in view.subviews {
            if let label = dropOffTitle(in: subview) { return label }
        }
        return nil
    }

    private func effectViews(in view: UIView) -> [UIVisualEffectView] {
        var found = view.subviews.compactMap { $0 as? UIVisualEffectView }
        for subview in view.subviews {
            found += effectViews(in: subview)
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

    private func label(in view: UIView, text: String) -> UILabel? {
        if let label = view as? UILabel, label.text == text { return label }
        for subview in view.subviews {
            if let label = label(in: subview, text: text) { return label }
        }
        return nil
    }

    private func buttonTitled(_ title: String, in view: UIView) -> UIButton? {
        if let button = view as? UIButton, button.currentTitle == title { return button }
        for subview in view.subviews {
            if let button = buttonTitled(title, in: subview) { return button }
        }
        return nil
    }

    private func stackOfLetters(in view: UIView) -> UIStackView? {
        if let stack = view as? UIStackView,
           stack.arrangedSubviews.count == 26,
           (stack.arrangedSubviews.first as? UIButton)?.currentTitle == "A" {
            return stack
        }
        for subview in view.subviews {
            if let stack = stackOfLetters(in: subview) { return stack }
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

    func testFailedPhotoLoadIsNotAnEmptyGallery() async {
        let api = FakeAPI()
        api.photoResults["a"] = .failure(APIError.transport)
        let store = RouteDraftStore()
        store.update { $0.select(makeStop(id: "a", name: "Almond")) }
        let viewModel = InstructionsViewModel(api: api, store: store)
        viewModel.loadPhotosIfNeeded(stopID: "a")
        await waitUntil { viewModel.photos["a"] != nil }
        XCTAssertEqual(viewModel.photos["a"], .failed)
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

nonisolated private final class FakeAPI: DispatchAPI {
    var stopsResult: [String: Result<[Stop], Error>] = [:]
    var queries: [String?] = []
    var createResult: Result<CreatedRoute, Error> = .success(CreatedRoute(id: "rt_2000", status: "draft"))
    var createCount = 0
    var notifyResult = NotifyResult(stopID: "", status: "sent", reason: nil)
    var notifyKeys: [String] = []
    var photoResults: [String: Result<[StopPhoto], Error>] = [:]

    func fetchStops(query: String?) async throws -> [Stop] {
        queries.append(query)
        return try (stopsResult[query ?? ""] ?? .success([])).get()
    }

    func fetchPhotos(stopID: String) async throws -> [StopPhoto] {
        try (photoResults[stopID] ?? .success([])).get()
    }

    func fetchImageData(from url: URL) async throws -> Data { Data() }

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
    var postedStopIDs: [String] = []
    var notifiedStopIDs: [String] = []
    private var continuations: [CheckedContinuation<CreatedRoute, Error>] = []

    func fetchStops(query: String?) async throws -> [Stop] { [] }

    func fetchPhotos(stopID: String) async throws -> [StopPhoto] { [] }

    func fetchImageData(from url: URL) async throws -> Data { Data() }

    func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult {
        notifiedStopIDs.append(stopID)
        return NotifyResult(stopID: stopID, status: "sent", reason: nil)
    }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        postedStopIDs = stops.map(\.stopID)
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

@MainActor
private final class SplitGateAPI: DispatchAPI {
    var createCount = 0
    var notifyStarted = 0
    private var createContinuations: [CheckedContinuation<CreatedRoute, Error>] = []
    private var notifyContinuations: [CheckedContinuation<NotifyResult, Error>] = []

    func fetchStops(query: String?) async throws -> [Stop] { [] }

    func fetchPhotos(stopID: String) async throws -> [StopPhoto] { [] }

    func fetchImageData(from url: URL) async throws -> Data { Data() }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        createCount += 1
        return try await withCheckedThrowingContinuation { continuation in
            createContinuations.append(continuation)
        }
    }

    func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult {
        notifyStarted += 1
        return try await withCheckedThrowingContinuation { continuation in
            notifyContinuations.append(continuation)
        }
    }

    func resumeCreate() {
        let pending = createContinuations
        createContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: CreatedRoute(id: "rt_1", status: "draft"))
        }
    }

    func resumeNotifies() {
        let pending = notifyContinuations
        notifyContinuations.removeAll()
        for continuation in pending {
            continuation.resume(returning: NotifyResult(stopID: "a", status: "sent", reason: nil))
        }
    }
}

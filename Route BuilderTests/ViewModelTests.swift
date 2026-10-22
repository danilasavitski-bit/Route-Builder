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

    func fetchStops(query: String?) async throws -> [Stop] {
        queries.append(query)
        return try (stopsResult[query ?? ""] ?? .success([])).get()
    }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        createCount += 1
        return try createResult.get()
    }
}

@MainActor
private final class GateAPI: DispatchAPI {
    var createCount = 0
    private var continuations: [CheckedContinuation<CreatedRoute, Error>] = []

    func fetchStops(query: String?) async throws -> [Stop] { [] }

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

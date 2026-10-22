import Foundation

enum StopsLoadState: Equatable {
    case loading
    case loaded
    case failed(String)
}

@MainActor
final class StopsViewModel: RouteDraftListener {
    private let api: DispatchAPI
    private let store: RouteDraftStore
    private let debounceNanoseconds: UInt64
    private var catalog: [Stop] = []
    private var searchTask: Task<Void, Never>?
    private var visibleSelection = ""

    private(set) var state: StopsLoadState = .loading
    private(set) var sections: [StopSection] = []
    private(set) var query = ""
    private(set) var searchFailed = false
    var onChange: (() -> Void)?

    init(api: DispatchAPI, store: RouteDraftStore, debounceNanoseconds: UInt64 = 300_000_000) {
        self.api = api
        self.store = store
        self.debounceNanoseconds = debounceNanoseconds
        visibleSelection = Self.selectionKey(store.draft)
        store.addListener(self)
    }

    func routeDraftDidChange(_ draft: RouteDraft) {
        let key = Self.selectionKey(draft)
        guard key != visibleSelection else { return }
        visibleSelection = key
        onChange?()
    }

    private static func selectionKey(_ draft: RouteDraft) -> String {
        let mode = draft.mode == .oneStop ? "one" : "multi"
        let rows = draft.stops.map { "\($0.stopID):\($0.packages)" }.joined(separator: "|")
        return "\(mode)|\(rows)"
    }

    func load() async {
        state = .loading
        onChange?()
        do {
            let stops = try await api.fetchStops(query: nil)
            catalog = stops
            if query.isEmpty {
                sections = StopGrouping.sections(catalog)
                searchFailed = false
            }
            state = .loaded
        } catch {
            state = .failed("Could not load stops.")
        }
        onChange?()
    }

    func searchTextChanged(_ text: String) {
        query = text
        searchTask?.cancel()
        if text.isEmpty {
            searchFailed = false
            sections = StopGrouping.sections(catalog)
            onChange?()
            return
        }
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: self?.debounceNanoseconds ?? 0)
            guard let self, !Task.isCancelled else { return }
            do {
                let stops = try await self.api.fetchStops(query: text)
                guard !Task.isCancelled else { return }
                self.searchFailed = false
                self.sections = StopGrouping.sections(stops)
            } catch {
                guard !Task.isCancelled else { return }
                self.searchFailed = true
            }
            self.onChange?()
        }
    }

    func select(_ stop: Stop) {
        store.update { $0.select(stop) }
    }

    func setMode(_ mode: SelectionMode) {
        store.update { $0.setMode(mode) }
    }

    func remove(stopID: String) {
        store.update { $0.remove(stopID: stopID) }
    }

    func savePackages(stopID: String, packages: Int) {
        store.update { $0.setPackages(stopID: stopID, packages: packages) }
    }

    func addManual(name: String, address: String, phone: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedAddress = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, !trimmedAddress.isEmpty else { return }
        let stop = Stop(
            id: "local_\(UUID().uuidString)",
            name: trimmedName,
            address: trimmedAddress,
            phone: phone.trimmingCharacters(in: .whitespacesAndNewlines),
            zone: "",
            packagesMax: 99
        )
        store.update { $0.select(stop) }
    }
}

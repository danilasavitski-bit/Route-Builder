import Foundation

enum SubmitState: Equatable {
    case idle
    case sending
    case failed(String)
    case succeeded(routeID: String)
}

@MainActor
final class InstructionsViewModel {
    private let api: DispatchAPI
    private let store: RouteDraftStore
    private var submitting = false
    private var pendingScrollID: String?

    private(set) var submitState: SubmitState = .idle
    private(set) var invalidStopIDs: [String] = []
    var onChange: (() -> Void)?

    init(api: DispatchAPI, store: RouteDraftStore) {
        self.api = api
        self.store = store
    }

    func consumeScrollRequest() -> String? {
        let identifier = pendingScrollID
        pendingScrollID = nil
        return identifier
    }

    func draftChanged() {
        guard case .succeeded = submitState else { return }
        submitState = .idle
        onChange?()
    }

    func instructionsChanged(stopID: String, text: String) {
        store.update { $0.setInstructions(stopID: stopID, text: text) }
        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            invalidStopIDs.removeAll { $0 == stopID }
        }
        onChange?()
    }

    func clear(stopID: String) {
        instructionsChanged(stopID: stopID, text: "")
    }

    func remove(stopID: String) {
        store.update { $0.remove(stopID: stopID) }
        invalidStopIDs.removeAll { $0 == stopID }
        onChange?()
    }

    func finish() async {
        guard !submitting else { return }
        if case .succeeded = submitState { return }
        let invalid = store.draft.invalidStopIDs()
        if !invalid.isEmpty {
            invalidStopIDs = invalid
            pendingScrollID = invalid.first
            onChange?()
            return
        }
        submitting = true
        submitState = .sending
        invalidStopIDs = []
        onChange?()
        defer { submitting = false }
        do {
            let created = try await api.createRoute(stops: store.draft.stops)
            submitState = .succeeded(routeID: created.id)
        } catch {
            submitState = .failed("Could not send the route. Try again.")
        }
        onChange?()
    }
}

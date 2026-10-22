import Foundation

enum SubmitState: Equatable {
    case idle
    case sending
    case failed(String)
    case succeeded(routeID: String)
}

struct DriverNotice: Equatable {
    let stopID: String
    let name: String
    var status: String
    var reason: String?
}

enum PhotoGallery: Equatable {
    case ready([StopPhoto])
    case failed

    var readyPhotos: [StopPhoto] {
        if case .ready(let photos) = self { return photos }
        return []
    }
}

@MainActor
final class InstructionsViewModel {
    private let api: DispatchAPI
    private let store: RouteDraftStore
    private var submitting = false
    private var pendingScrollID: String?
    private var photoTasks: [String: Task<Void, Never>] = [:]
    private var notifyGeneration = 0

    private(set) var submitState: SubmitState = .idle
    private(set) var invalidStopIDs: [String] = []
    private(set) var notices: [DriverNotice] = []
    private(set) var photos: [String: PhotoGallery] = [:]
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
        notifyGeneration += 1
        notices = []
        submitState = .idle
        onChange?()
    }

    func loadPhotosIfNeeded(stopID: String) {
        guard !stopID.hasPrefix("local_") else { return }
        guard photos[stopID] == nil, photoTasks[stopID] == nil else { return }
        photoTasks[stopID] = Task { [weak self] in
            guard let self else { return }
            let gallery: PhotoGallery
            do {
                gallery = .ready(try await self.api.fetchPhotos(stopID: stopID))
            } catch {
                gallery = .failed
            }
            self.photos[stopID] = gallery
            self.photoTasks[stopID] = nil
            self.onChange?()
        }
    }

    func imageData(for url: URL) async -> Data? {
        try? await api.fetchImageData(from: url)
    }

    func attachDropOffPhoto(stopID: String, path: String) {
        store.update { $0.setDropOffPhoto(stopID: stopID, path: path) }
        onChange?()
    }

    func retryFailedNotices() async {
        guard case .succeeded(let routeID) = submitState else { return }
        let generation = notifyGeneration
        let failedIDs = notices.filter { $0.status == "failed" }.map(\.stopID)
        for stopID in failedIDs {
            guard generation == notifyGeneration else { return }
            await sendNotice(routeID: routeID, stopID: stopID, generation: generation)
        }
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
        let posted = store.draft.stops
        defer { submitting = false }
        do {
            let created = try await api.createRoute(stops: posted)
            let generation = notifyGeneration
            notices = posted.map {
                DriverNotice(stopID: $0.stopID, name: $0.name, status: "sending", reason: nil)
            }
            submitState = .succeeded(routeID: created.id)
            onChange?()
            for stop in posted {
                guard generation == notifyGeneration else { return }
                await sendNotice(routeID: created.id, stopID: stop.stopID, generation: generation)
            }
        } catch {
            submitState = .failed("Could not send the route. Try again.")
            onChange?()
        }
    }

    private func sendNotice(routeID: String, stopID: String, generation: Int) async {
        guard generation == notifyGeneration else { return }
        if let index = notices.firstIndex(where: { $0.stopID == stopID }) {
            notices[index].status = "sending"
            notices[index].reason = nil
            onChange?()
        }
        let result: NotifyResult
        do {
            result = try await api.notify(
                routeID: routeID,
                stopID: stopID,
                idempotencyKey: UUID().uuidString
            )
        } catch {
            result = NotifyResult(stopID: stopID, status: "failed", reason: "Could not reach the driver.")
        }
        guard generation == notifyGeneration else { return }
        guard let index = notices.firstIndex(where: { $0.stopID == stopID }) else { return }
        let delivered = result.status == "sent"
        notices[index].status = delivered ? "sent" : "failed"
        notices[index].reason = delivered ? nil : (result.reason ?? "The driver was not notified.")
        onChange?()
    }
}

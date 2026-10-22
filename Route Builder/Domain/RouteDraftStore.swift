import Foundation

protocol RouteDraftListener: AnyObject {
    func routeDraftDidChange(_ draft: RouteDraft)
}

final class RouteDraftStore {
    private final class WeakListener {
        weak var value: RouteDraftListener?
        init(_ value: RouteDraftListener) { self.value = value }
    }

    private(set) var draft = RouteDraft()
    private var listeners: [WeakListener] = []

    func addListener(_ listener: RouteDraftListener) {
        listeners.append(WeakListener(listener))
    }

    func update(_ body: (inout RouteDraft) -> Void) {
        body(&draft)
        let snapshot = draft
        listeners.removeAll { $0.value == nil }
        listeners.forEach { $0.value?.routeDraftDidChange(snapshot) }
    }
}

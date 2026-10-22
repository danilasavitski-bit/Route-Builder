import Foundation

enum APIError: Error, Equatable {
    case transport
    case http(status: Int, code: String)
    case validation([String: String])
}

protocol DispatchAPI {
    func fetchStops(query: String?) async throws -> [Stop]
    func fetchPhotos(stopID: String) async throws -> [StopPhoto]
    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute
    func notify(routeID: String, stopID: String, idempotencyKey: String) async throws -> NotifyResult
}

import Foundation

enum APIError: Error, Equatable {
    case transport
    case http(status: Int, code: String)
    case validation([String: String])
}

protocol DispatchAPI {
    func fetchStops(query: String?) async throws -> [Stop]
    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute
}

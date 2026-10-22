import Foundation

protocol RetrySleeper {
    func pause(seconds: TimeInterval) async
}

struct TaskRetrySleeper: RetrySleeper {
    func pause(seconds: TimeInterval) async {
        let nanoseconds = UInt64(max(0, seconds) * 1_000_000_000)
        try? await Task.sleep(nanoseconds: nanoseconds)
    }
}

final class APIClient: DispatchAPI {
    private let baseURL: URL
    private let session: URLSession
    private let sleeper: any RetrySleeper

    static func live() -> APIClient {
        APIClient(baseURL: AppConfig.baseURL, session: liveSession(), sleeper: TaskRetrySleeper())
    }

    init(baseURL: URL, session: URLSession, sleeper: any RetrySleeper) {
        self.baseURL = baseURL
        self.session = session
        self.sleeper = sleeper
    }

    static func liveSession() -> URLSession {
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    func fetchStops(query: String?) async throws -> [Stop] {
        var collected: [Stop] = []
        var seen = Set<String>()
        var page = 1
        while true {
            let batch = try await fetchPage(page: page, query: query)
            if batch.isEmpty {
                return collected
            }
            var added = 0
            for stop in batch where seen.insert(stop.id).inserted {
                collected.append(stop)
                added += 1
            }
            if added == 0 {
                return collected
            }
            page += 1
        }
    }

    func createRoute(stops: [RouteStop]) async throws -> CreatedRoute {
        let payload: [String: Any] = [
            "stops": stops.map { stop -> [String: Any] in
                let trimmed = stop.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
                let packages = min(max(stop.packagesMax, 1), max(1, stop.packages))
                return [
                    "stop_id": stop.stopID,
                    "packages": packages,
                    "instructions": String(trimmed.prefix(200))
                ]
            }
        ]
        let body = try JSONSerialization.data(withJSONObject: payload)
        let request = makeRequest(path: "v1/routes", method: "POST", body: body)
        let (data, http) = try await send(request)
        let errorBody = try? JSONDecoder().decode(ErrorDTO.self, from: data)
        if http.statusCode == 422 {
            throw APIError.validation(errorBody?.fields ?? [:])
        }
        guard (200..<300).contains(http.statusCode) else {
            throw APIError.http(status: http.statusCode, code: errorBody?.error ?? "")
        }
        let created = try JSONDecoder().decode(CreatedDTO.self, from: data)
        return CreatedRoute(id: created.id, status: created.status)
    }

    private func fetchPage(page: Int, query: String?) async throws -> [Stop] {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: "50")
        ]
        if let query, !query.isEmpty {
            items.append(URLQueryItem(name: "q", value: query))
        }
        let request = makeRequest(path: "v1/stops", method: "GET", query: items)
        let (data, http) = try await send(request)
        guard (200..<300).contains(http.statusCode) else {
            let code = (try? JSONDecoder().decode(ErrorDTO.self, from: data))?.error ?? ""
            throw APIError.http(status: http.statusCode, code: code)
        }
        let pageDTO = try JSONDecoder().decode(PageDTO.self, from: data)
        return (pageDTO.items ?? []).map(\.stop)
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var attempt = 1
        while true {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw APIError.transport
            }
            guard let http = response as? HTTPURLResponse else {
                throw APIError.transport
            }
            if [429, 500, 503].contains(http.statusCode), attempt < 4 {
                await sleeper.pause(seconds: Self.delay(for: http, attempt: attempt))
                attempt += 1
                continue
            }
            return (data, http)
        }
    }

    private static func delay(for response: HTTPURLResponse, attempt: Int) -> TimeInterval {
        if let header = response.value(forHTTPHeaderField: "Retry-After"),
           let seconds = TimeInterval(header) {
            return min(5, max(0, seconds))
        }
        return 0.4 * Double(attempt)
    }

    private func makeRequest(path: String, method: String, query: [URLQueryItem] = [], body: Data? = nil) -> URLRequest {
        let url = baseURL.appendingPathComponent(path)
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if !query.isEmpty {
            components?.queryItems = query
        }
        var request = URLRequest(url: components?.url ?? url)
        request.httpMethod = method
        request.timeoutInterval = 20
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        return request
    }
}

private struct PageDTO: Decodable {
    let items: [StopDTO]?
}

private struct StopDTO: Decodable {
    let stop: Stop

    enum CodingKeys: String, CodingKey {
        case id, name, address, phone, zone
        case packagesMax = "packages_max"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let id = try container.decode(String.self, forKey: .id)
        let name = try container.decode(String.self, forKey: .name)
        let address = try container.decode(String.self, forKey: .address)
        let phone = try container.decode(String.self, forKey: .phone)
        let zone = (try? container.decode(String.self, forKey: .zone)) ?? ""
        stop = Stop(
            id: id,
            name: name,
            address: address,
            phone: phone,
            zone: zone,
            packagesMax: Self.packagesMax(from: container)
        )
    }

    private static func packagesMax(from container: KeyedDecodingContainer<CodingKeys>) -> Int {
        if let number = try? container.decode(Int.self, forKey: .packagesMax) {
            return number
        }
        if let string = try? container.decode(String.self, forKey: .packagesMax), let number = Int(string) {
            return number
        }
        return 9
    }
}

private struct CreatedDTO: Decodable {
    let id: String
    let status: String
}

private struct ErrorDTO: Decodable {
    let error: String?
    let fields: [String: String]?
}

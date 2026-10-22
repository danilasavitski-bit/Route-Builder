import XCTest
@testable import Route_Builder

@MainActor
final class APIClientTests: XCTestCase {
    private var recorded: [URLRequest] = []

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testPackagesMaxNormalizesNumberStringNullAndGarbage() async throws {
        let body = """
        {"items":[
          {"id":"n","name":"North","address":"A","phone":"1","zone":"north","packages_max":5,"last_delivery_at":1700000000,"notes":null},
          {"id":"s","name":"South","address":"A","phone":"1","zone":"south","packages_max":"6"},
          {"id":"e","name":"East","address":"A","phone":"1","zone":"east","packages_max":null},
          {"id":"g","name":"Gate","address":"A","phone":"1","zone":"center","packages_max":"nope"}
        ]}
        """
        stub { request in
            self.recorded.append(request)
            if self.page(request) == "2" {
                return (200, Data(#"{"items":[]}"#.utf8), [:])
            }
            XCTAssertEqual(request.timeoutInterval, 20)
            XCTAssertEqual(self.query(request, named: "page_size"), "50")
            return (200, Data(body.utf8), [:])
        }
        let stops = try await makeClient().fetchStops(query: nil)
        XCTAssertEqual(stops.map(\.packagesMax), [5, 6, 99, 99])
        XCTAssertEqual(recorded.map { self.page($0) }, ["1", "2"])
    }

    func testNullItemsEndsTheLoad() async throws {
        stub { request in
            self.recorded.append(request)
            return (200, Data(#"{"items":null,"has_more":true}"#.utf8), [:])
        }
        let stops = try await makeClient().fetchStops(query: nil)
        XCTAssertEqual(stops, [])
        XCTAssertEqual(recorded.map { self.page($0) }, ["1"])
    }

    func testDuplicateTailDoesNotFollowALyingHasMore() async throws {
        stub { request in
            self.recorded.append(request)
            switch self.page(request) {
            case "1":
                return (200, self.pageBody([("A", "Almond"), ("B", "Bluebell")], hasMore: true), [:])
            case "2":
                return (200, self.pageBody([("B", "Bluebell"), ("C", "Cafe")], hasMore: true), [:])
            default:
                return (200, self.pageBody([("C", "Cafe")], hasMore: true), [:])
            }
        }
        let stops = try await makeClient().fetchStops(query: nil)
        XCTAssertEqual(stops.map(\.id), ["A", "B", "C"])
        XCTAssertEqual(recorded.map { self.page($0) }, ["1", "2", "3"])
    }

    func testRetries503UsingRetryAfter() async throws {
        let sleeps = SleepLog()
        var hits = 0
        stub { request in
            if self.page(request) == "2" {
                return (200, Data(#"{"items":[]}"#.utf8), [:])
            }
            hits += 1
            if hits == 1 {
                return (503, Data(#"{"error":"upstream_unavailable"}"#.utf8), ["Retry-After": "2"])
            }
            return (200, self.pageBody([("A", "Almond")], hasMore: false), [:])
        }
        let stops = try await makeClient(sleep: sleeps).fetchStops(query: nil)
        XCTAssertEqual(stops.map(\.id), ["A"])
        XCTAssertEqual(sleeps.values, [2])
    }

    func testGivesUpAfterFourServerErrors() async throws {
        let sleeps = SleepLog()
        stub { _ in
            (500, Data(#"{"error":"internal_error"}"#.utf8), [:])
        }
        do {
            _ = try await makeClient(sleep: sleeps).fetchStops(query: nil)
            XCTFail("expected http error")
        } catch let error as APIError {
            XCTAssertEqual(error, .http(status: 500, code: "internal_error"))
        }
        XCTAssertEqual(sleeps.values.count, 3)
        XCTAssertEqual(sleeps.values[0], 0.4, accuracy: 0.001)
        XCTAssertEqual(sleeps.values[1], 0.8, accuracy: 0.001)
        XCTAssertEqual(sleeps.values[2], 1.2, accuracy: 0.001)
    }

    func testSearchKeepsTheTypedQuery() async throws {
        stub { request in
            self.recorded.append(request)
            if self.page(request) == "1" {
                XCTAssertEqual(self.query(request, named: "q"), "North")
            }
            return (200, Data(#"{"items":[]}"#.utf8), [:])
        }
        _ = try await makeClient().fetchStops(query: "North")
        XCTAssertEqual(query(recorded[0], named: "q"), "North")
    }

    func testCreateRouteTrimsClampsAndMapsValidation() async throws {
        var routeStop = RouteStop(stop: makeStop(id: "stp_1", name: "North", packagesMax: 3))
        routeStop.packages = 99
        routeStop.instructions = "  " + String(repeating: "a", count: 210) + "  "
        let captured = BodyBox()
        stub { request in
            captured.data = Self.bodyData(from: request)
            return (422, Data(#"{"error":"validation_failed","fields":{"stops":"required"}}"#.utf8), [:])
        }
        do {
            _ = try await makeClient().createRoute(stops: [routeStop])
            XCTFail("expected validation")
        } catch let error as APIError {
            XCTAssertEqual(error, .validation(["stops": "required"]))
        }
        let object = try JSONSerialization.jsonObject(with: captured.data ?? Data()) as? [String: Any]
        let stops = object?["stops"] as? [[String: Any]]
        XCTAssertEqual(stops?.first?["stop_id"] as? String, "stp_1")
        XCTAssertEqual(stops?.first?["packages"] as? Int, 3)
        XCTAssertEqual((stops?.first?["instructions"] as? String)?.count, 200)
    }

    func testNullPhotoURLIsKept() async throws {
        stub { _ in
            let body = """
            {"items":[
              {"id":"p0","url":null,"tag":"entrance","width":400,"height":250},
              {"id":"p1","url":"https://picsum.photos/seed/a/400/250","tag":"parking"}
            ]}
            """
            return (200, Data(body.utf8), [:])
        }
        let photos = try await makeClient().fetchPhotos(stopID: "stp_0001")
        XCTAssertEqual(photos.map(\.id), ["p0", "p1"])
        XCTAssertNil(photos[0].url)
        XCTAssertEqual(photos[0].title, "Entrance")
        XCTAssertEqual(photos[1].title, "Parking")
        XCTAssertEqual(photos[1].url?.absoluteString, "https://picsum.photos/seed/a/400/250")
    }

    func testImageDataUsesTheClientSession() async throws {
        stub { request in
            XCTAssertEqual(request.url?.absoluteString, "https://picsum.photos/seed/a/8/8")
            return (200, Data([0xFF, 0xD8]), [:])
        }
        let data = try await makeClient().fetchImageData(from: URL(string: "https://picsum.photos/seed/a/8/8")!)
        XCTAssertEqual(data, Data([0xFF, 0xD8]))
    }

    func testNotifyKeepsAFailedStatus() async throws {
        stub { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "key-1")
            return (200, Data(#"{"stop_id":"stp_1","status":"failed","reason":"carrier_rejected"}"#.utf8), [:])
        }
        let result = try await makeClient().notify(routeID: "rt_1", stopID: "stp_1", idempotencyKey: "key-1")
        XCTAssertEqual(result, NotifyResult(stopID: "stp_1", status: "failed", reason: "carrier_rejected"))
    }

    func testCancelledFetchIsNotATransportError() async {
        stub { _ in throw URLError(.cancelled) }
        do {
            _ = try await makeClient().fetchStops(query: nil)
            XCTFail("Expected cancellation")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .cancelled)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    func testOfflineFetchIsATransportError() async {
        stub { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await makeClient().fetchStops(query: nil)
            XCTFail("Expected transport error")
        } catch let error as APIError {
            XCTAssertEqual(error, .transport)
        } catch {
            XCTFail("Unexpected \(error)")
        }
    }

    private static func bodyData(from request: URLRequest) -> Data {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 1024)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: 1024)
            if count <= 0 { break }
            data.append(buffer, count: count)
        }
        return data
    }

    private func makeClient(sleep: SleepLog = SleepLog()) -> APIClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        return APIClient(baseURL: AppConfig.baseURL, session: session, sleeper: sleep)
    }

    private func stub(_ handler: @escaping (URLRequest) throws -> (Int, Data, [String: String])) {
        StubURLProtocol.handler = handler
    }

    private func page(_ request: URLRequest) -> String? {
        query(request, named: "page")
    }

    private func query(_ request: URLRequest, named name: String) -> String? {
        URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == name }?
            .value
    }

    private func pageBody(_ rows: [(String, String)], hasMore: Bool) -> Data {
        let items = rows.map { id, name in
            #"{"id":"\#(id)","name":"\#(name)","address":"Road","phone":"1","zone":"north","packages_max":4}"#
        }.joined(separator: ",")
        return Data(#"{"items":[\#(items)],"has_more":\#(hasMore)}"#.utf8)
    }

    private func makeStop(id: String, name: String, packagesMax: Int) -> Stop {
        Stop(id: id, name: name, address: "Road", phone: "1", zone: "north", packagesMax: packagesMax)
    }
}

final class BodyBox: @unchecked Sendable {
    var data: Data?
}

final class SleepLog: RetrySleeper, @unchecked Sendable {
    var values: [TimeInterval] = []

    func pause(seconds: TimeInterval) async {
        values.append(seconds)
    }
}

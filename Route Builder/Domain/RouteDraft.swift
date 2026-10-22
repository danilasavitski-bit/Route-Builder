import Foundation

struct Stop: Equatable, Identifiable {
    let id: String
    let name: String
    let address: String
    let phone: String
    let zone: String
    let packagesMax: Int

    var sectionLetter: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "#" }
        return String(first).uppercased()
    }

    var initials: String {
        let words = name.split(whereSeparator: \.isWhitespace)
        let characters = words.prefix(2).compactMap { word in
            word.first { $0.isLetter || $0.isNumber }
        }
        return String(characters).uppercased()
    }
}

enum SelectionMode: Equatable {
    case oneStop
    case multiStop
}

struct RouteStop: Equatable, Identifiable {
    var id: String { stopID }
    let stopID: String
    let name: String
    let address: String
    let phone: String
    let packagesMax: Int
    var packages: Int
    var instructions: String

    init(stop: Stop) {
        stopID = stop.id
        name = stop.name
        address = stop.address
        phone = stop.phone
        packagesMax = stop.packagesMax
        packages = 1
        instructions = ""
    }
}

struct StopSection: Equatable {
    let letter: String
    let stops: [Stop]
}

enum StopGrouping {
    static func sections(_ stops: [Stop]) -> [StopSection] {
        var order: [String] = []
        var grouped: [String: [Stop]] = [:]
        for stop in stops {
            let letter = stop.sectionLetter
            if grouped[letter] == nil {
                order.append(letter)
            }
            grouped[letter, default: []].append(stop)
        }
        return order.sorted().map { letter in
            StopSection(letter: letter, stops: grouped[letter] ?? [])
        }
    }
}

struct RouteDraft: Equatable {
    var mode: SelectionMode = .multiStop
    var stops: [RouteStop] = []

    var packageTotal: Int {
        stops.reduce(0) { $0 + $1.packages }
    }

    var subtitle: String {
        "\(packageTotal) packages | \(stops.count) stops"
    }

    func isSelected(_ id: String) -> Bool {
        stops.contains { $0.stopID == id }
    }

    mutating func select(_ stop: Stop) {
        if mode == .oneStop {
            if stops.count == 1, stops[0].stopID == stop.id {
                stops.removeAll()
                return
            }
            if let existing = stops.first(where: { $0.stopID == stop.id }) {
                stops = [existing]
            } else {
                stops = [RouteStop(stop: stop)]
            }
            return
        }
        if let index = stops.firstIndex(where: { $0.stopID == stop.id }) {
            stops.remove(at: index)
        } else {
            stops.append(RouteStop(stop: stop))
        }
    }

    mutating func setMode(_ mode: SelectionMode) {
        self.mode = mode
        if mode == .oneStop, stops.count > 1 {
            stops = Array(stops.prefix(1))
        }
    }

    mutating func setPackages(stopID: String, packages: Int) {
        guard let index = stops.firstIndex(where: { $0.stopID == stopID }) else { return }
        let limit = max(1, stops[index].packagesMax)
        stops[index].packages = min(limit, max(1, packages))
    }

    mutating func setInstructions(stopID: String, text: String) {
        guard let index = stops.firstIndex(where: { $0.stopID == stopID }) else { return }
        stops[index].instructions = String(text.prefix(200))
    }

    mutating func remove(stopID: String) {
        stops.removeAll { $0.stopID == stopID }
    }

    func invalidStopIDs() -> [String] {
        stops.compactMap { stop in
            stop.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? stop.stopID : nil
        }
    }
}

struct CreatedRoute: Equatable {
    let id: String
    let status: String
}

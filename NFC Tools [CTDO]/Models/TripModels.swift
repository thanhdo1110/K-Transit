import Foundation

// Trip leg (boarding/alighting event within a trip)
struct TripLeg: Identifiable, Sendable, Codable {
    var id = UUID()
    let isBoarding: Bool
    let transportType: UInt8
    let date: Date?
    let fare: Int
}

// Complete trip record (one or more legs with same counter)
struct TripRecord: Identifiable, Sendable, Codable {
    var id = UUID()
    let tripCounter: UInt8
    let totalFare: Int
    let distanceMeters: Int
    let balanceAfter: Int      // balance after this trip's charge (from SFI4)
    let legs: [TripLeg]

    var boardingDate: Date? { legs.last(where: { $0.isBoarding })?.date }
    var alightingDate: Date? { legs.first(where: { !$0.isBoarding })?.date }
    var isTransfer: Bool { legs.count > 2 }
    var distanceKm: Double { Double(distanceMeters) / 1000.0 }

    var transportDescription: String {
        let types = legs.map { leg -> String in
            switch leg.transportType {
            case 0x00: return L("버스")
            case 0x01: return L("지하철")
            case 0x02: return L("기차")
            default: return L("기타 교통")
            }
        }
        var seen = Set<String>()
        return types.filter { seen.insert($0).inserted }.joined(separator: " → ")
    }
}

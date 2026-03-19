import Foundation

struct ScanHistoryEntry: Identifiable, Codable {
    var id = UUID()
    let scanDate: Date
    let cardInfo: TransitCardInfo
}

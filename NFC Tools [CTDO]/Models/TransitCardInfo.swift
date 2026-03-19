import Foundation

struct RawDataEntry: Sendable, Codable {
    let key: String
    let value: String
}

struct TransitCardInfo: Sendable, Codable {
    var cardType: KoreanCardType = .unknown
    var cardUID: String = ""
    var balance: Int = 0
    var cardNumber: String = ""
    var transactions: [TransactionRecord] = []
    var trips: [TripRecord] = []
    var rawData: [RawDataEntry] = []
    var debugLog: [String] = []
    var tagType: String = ""

    mutating func dlog(_ msg: String) {
        print("[NFC-CTDO] \(msg)")
        debugLog.append(msg)
    }
}

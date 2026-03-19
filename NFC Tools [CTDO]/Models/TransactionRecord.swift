import Foundation

struct TransactionRecord: Identifiable, Sendable, Codable {
    var id = UUID()
    let amount: Int
    let balance: Int
    let date: Date?
    let type: TransactionType

    enum TransactionType: String, Sendable, Codable {
        case topUp = "충전"
        case payment = "결제"
        case transfer = "환승"
        case unknown = "기타"

        var displayName: String {
            L(rawValue)
        }

        var icon: String {
            switch self {
            case .topUp: return "plus.circle.fill"
            case .payment: return "minus.circle.fill"
            case .transfer: return "arrow.triangle.swap"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

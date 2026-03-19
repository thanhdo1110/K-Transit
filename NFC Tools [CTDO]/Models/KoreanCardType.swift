import Foundation

enum KoreanCardType: String, Sendable, Codable {
    case tmoney = "T-money (티머니)"
    case cashbee = "Cashbee (캐시비)"
    case railplus = "Rail Plus (레일플러스)"
    case unknown = "알 수 없음"

    var displayName: String {
        L(String.LocalizationValue(rawValue))
    }

    var icon: String {
        switch self {
        case .tmoney: return "bus.fill"
        case .cashbee: return "creditcard.fill"
        case .railplus: return "tram.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

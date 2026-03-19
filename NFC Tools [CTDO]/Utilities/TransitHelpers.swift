import SwiftUI

func transportIcon(_ type: UInt8) -> String {
    switch type {
    case 0x00: return "bus.fill"
    case 0x01: return "tram.fill"
    case 0x02: return "train.side.front.car"
    default: return "questionmark.circle"
    }
}

func cardColor(_ type: KoreanCardType) -> Color {
    switch type {
    case .tmoney: return .blue
    case .cashbee: return .orange
    case .railplus: return .purple
    case .unknown: return .gray
    }
}

func transactionIcon(_ type: TransactionRecord.TransactionType) -> String {
    switch type {
    case .topUp: return "plus.circle.fill"
    case .payment: return "bus.fill"
    case .transfer: return "arrow.triangle.swap"
    case .unknown: return "questionmark.circle"
    }
}

func transactionColor(_ type: TransactionRecord.TransactionType) -> Color {
    switch type {
    case .topUp: return .green
    case .payment: return .blue
    case .transfer: return .orange
    case .unknown: return .gray
    }
}

func transactionLabel(_ type: TransactionRecord.TransactionType) -> LocalizedStringKey {
    switch type {
    case .topUp: return "충전"
    case .payment: return "교통 이용"
    case .transfer: return "환승 이용"
    case .unknown: return "기타 이용"
    }
}

func cardGradient(_ type: KoreanCardType) -> [Color] {
    switch type {
    case .tmoney:
        return [Color(red: 0.15, green: 0.35, blue: 0.85),
                Color(red: 0.10, green: 0.55, blue: 0.95)]
    case .cashbee:
        return [Color(red: 0.90, green: 0.45, blue: 0.10),
                Color(red: 0.95, green: 0.60, blue: 0.20)]
    case .railplus:
        return [Color(red: 0.50, green: 0.20, blue: 0.80),
                Color(red: 0.65, green: 0.35, blue: 0.90)]
    case .unknown:
        return [Color(red: 0.40, green: 0.42, blue: 0.48),
                Color(red: 0.55, green: 0.57, blue: 0.62)]
    }
}

import Foundation

func formatKRW(_ amount: Int) -> String {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.currencyCode = "KRW"
    f.currencySymbol = "₩"
    f.maximumFractionDigits = 0
    return f.string(from: NSNumber(value: amount)) ?? "₩\(amount)"
}

func formatTime24h(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss"
    f.timeZone = TimeZone(identifier: "Asia/Seoul")
    return f.string(from: date)
}

func formatDate24h(_ date: Date) -> String {
    let f = DateFormatter()
    f.dateFormat = "yyyy-MM-dd"
    f.timeZone = TimeZone(identifier: "Asia/Seoul")
    return f.string(from: date)
}

func formatRelativeDate(_ date: Date) -> String {
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .short
    return f.localizedString(for: date, relativeTo: Date())
}

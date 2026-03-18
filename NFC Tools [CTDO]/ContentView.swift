import SwiftUI

struct ContentView: View {
    @StateObject private var reader = NFCCardReader()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    scanSection
                    if let error = reader.errorMessage {
                        errorBanner(error)
                    }
                    if let card = reader.cardInfo {
                        cardHeader(card)
                        if card.balance > 0 {
                            balanceCard(card)
                        }
                        if !card.transactions.isEmpty {
                            tripHistory(card.transactions)
                        } else if card.cardType != .unknown {
                            noTripsView
                        }
                        if !card.rawData.isEmpty {
                            rawDataSection(card.rawData)
                        }
                        if !card.debugLog.isEmpty {
                            debugLogSection(card.debugLog)
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("교통카드 리더")
            .background(Color(.systemGroupedBackground))
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.08))
                    .frame(width: 120, height: 120)
                Image(systemName: reader.isScanning
                      ? "antenna.radiowaves.left.and.right"
                      : "creditcard.and.123")
                    .font(.system(size: 48))
                    .foregroundStyle(reader.isScanning ? .blue : .secondary)
            }

            if !reader.statusMessage.isEmpty && reader.cardInfo == nil {
                Text(reader.statusMessage)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Button {
                reader.startScan()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "sensor.tag.radiowaves.forward.fill")
                    Text(reader.isScanning
                         ? LocalizedStringKey("스캔 중...")
                         : LocalizedStringKey("카드 스캔"))
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(reader.isScanning)

            HStack(spacing: 16) {
                tagLabel("T-money", icon: "bus.fill")
                tagLabel("Cashbee", icon: "creditcard.fill")
                tagLabel("Rail Plus", icon: "tram.fill")
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tagLabel(_ text: String, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundStyle(.tertiary)
    }

    // MARK: - Error

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
        }
        .padding()
        .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Card Header

    private func cardHeader(_ card: TransitCardInfo) -> some View {
        VStack(spacing: 14) {
            // Card type banner
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(cardColor(card.cardType).opacity(0.15))
                        .frame(width: 40, height: 40)
                    Image(systemName: card.cardType.icon)
                        .font(.title3)
                        .foregroundStyle(cardColor(card.cardType))
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.cardType.displayName)
                        .font(.headline)
                    if !reader.statusMessage.isEmpty {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                            Text(reader.statusMessage)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()
                Image(systemName: "wave.3.right")
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Card details grid
            VStack(spacing: 8) {
                if !card.tagType.isEmpty {
                    detailRow(icon: "tag.fill", label: "태그", value: card.tagType)
                }
                detailRow(icon: "number", label: "UID", value: card.cardUID)
                if !card.cardNumber.isEmpty {
                    detailRow(icon: "creditcard", label: "카드 번호", value: card.cardNumber)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func detailRow(icon: String, label: LocalizedStringKey, value: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .textSelection(.enabled)
        }
    }

    // MARK: - Balance

    private func balanceCard(_ card: TransitCardInfo) -> some View {
        VStack(spacing: 6) {
            HStack {
                Image(systemName: "wonsign.circle.fill")
                    .foregroundStyle(.blue)
                Text("잔액")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            Text(formatKRW(card.balance))
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.06), .cyan.opacity(0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 16)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.blue.opacity(0.15), lineWidth: 1)
        )
    }

    // MARK: - Trip History

    private func tripHistory(_ transactions: [TransactionRecord]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Image(systemName: "clock.arrow.circlepath")
                    .foregroundStyle(.blue)
                Text("이용 내역")
                    .font(.headline)
                Spacer()
                Text("\(transactions.count)건")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.secondary.opacity(0.1), in: Capsule())
            }

            ForEach(transactions) { tx in
                tripRow(tx)
                if tx.id != transactions.last?.id {
                    Divider().padding(.leading, 44)
                }
            }
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func tripRow(_ tx: TransactionRecord) -> some View {
        HStack(spacing: 12) {
            // Icon
            ZStack {
                Circle()
                    .fill(tripColor(tx.type).opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: tripIcon(tx.type))
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(tripColor(tx.type))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                Text(tripLabel(tx.type))
                    .font(.subheadline.weight(.medium))
                if let date = tx.date {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.caption2)
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Amount
            VStack(alignment: .trailing, spacing: 3) {
                HStack(spacing: 2) {
                    if tx.type == .topUp {
                        Image(systemName: "arrow.down.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }
                    Text((tx.type == .topUp ? "+" : "-") + formatKRW(tx.amount))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(tx.type == .topUp ? .green : .primary)
                }
                HStack(spacing: 4) {
                    Image(systemName: "wallet.pass")
                        .font(.caption2)
                    Text(formatKRW(tx.balance))
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var noTripsView: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray")
                .foregroundStyle(.secondary)
            Text("이용 내역이 없습니다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Raw Data

    private func rawDataSection(_ data: [(key: String, value: String)]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.key)
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)
                        Text(item.value)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(.vertical, 2)
                }
            }
            .padding(.top, 6)
        } label: {
            Label("Raw Data (\(data.count))", systemImage: "doc.text.magnifyingglass")
                .font(.subheadline.bold())
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Debug Log

    private func debugLogSection(_ lines: [String]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(debugColor(for: line))
                        .textSelection(.enabled)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 6)
        } label: {
            Label("Debug Log (\(lines.count))", systemImage: "ladybug.fill")
                .font(.subheadline.bold())
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: - Helpers

    private func formatKRW(_ amount: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "KRW"
        f.currencySymbol = "₩"
        f.maximumFractionDigits = 0
        return f.string(from: NSNumber(value: amount)) ?? "₩\(amount)"
    }

    private func cardColor(_ type: KoreanCardType) -> Color {
        switch type {
        case .tmoney: return .blue
        case .cashbee: return .orange
        case .railplus: return .purple
        case .unknown: return .gray
        }
    }

    private func tripIcon(_ type: TransactionRecord.TransactionType) -> String {
        switch type {
        case .topUp: return "plus.circle.fill"
        case .payment: return "bus.fill"
        case .transfer: return "tram.fill"
        case .unknown: return "questionmark.circle"
        }
    }

    private func tripColor(_ type: TransactionRecord.TransactionType) -> Color {
        switch type {
        case .topUp: return .green
        case .payment: return .blue
        case .transfer: return .purple
        case .unknown: return .gray
        }
    }

    private func tripLabel(_ type: TransactionRecord.TransactionType) -> String {
        switch type {
        case .topUp: return String(localized: "충전")
        case .payment: return String(localized: "교통 이용")
        case .transfer: return String(localized: "환승 이용")
        case .unknown: return String(localized: "기타 이용")
        }
    }

    private func debugColor(for line: String) -> Color {
        if line.contains("✅") { return .green }
        if line.contains("❌") { return .red }
        if line.contains("[CONNECT]") { return .orange }
        if line.contains("[SELECT]") { return .blue }
        if line.contains("[BALANCE]") { return .cyan }
        if line.contains("[TX]") { return .purple }
        return .primary
    }
}

#Preview {
    ContentView()
}

import SwiftUI

struct CheckTabView: View {
    @EnvironmentObject var reader: NFCCardReader
    @EnvironmentObject var historyStore: ScanHistoryStore
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedSection: ResultSection? = nil
    @State private var cardAppeared = false
    @State private var pulseScale: CGFloat = 1.0
    @State private var pulseOpacity: Double = 0.6

    enum ResultSection {
        case transactions, trips
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    scanSection

                    // Show guide when no card scanned yet
                    if reader.cardInfo == nil && reader.errorMessage == nil {
                        scanGuide
                    }

                    if let error = reader.errorMessage {
                        errorBanner(error)
                            .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if let card = reader.cardInfo {
                        virtualCard(card)
                            .transition(.scale(scale: 0.92).combined(with: .opacity))

                        sectionButtons(card)

                        // Selected section content
                        if selectedSection == .transactions && !card.transactions.isEmpty {
                            TransactionListView(transactions: card.transactions)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }
                        if selectedSection == .trips && !card.trips.isEmpty {
                            TripListView(trips: card.trips)
                                .transition(.opacity.combined(with: .move(edge: .bottom)))
                        }

                        if card.transactions.isEmpty && card.trips.isEmpty && card.cardType != .unknown {
                            noDataView
                        }

                        // Debug sections
                        if settings.debugMode {
                            if !card.rawData.isEmpty {
                                rawDataSection(card.rawData)
                            }
                            if !card.debugLog.isEmpty {
                                debugLogSection(card.debugLog)
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .animation(.spring(response: 0.45, dampingFraction: 0.8), value: reader.cardInfo != nil)
                .animation(.easeInOut(duration: 0.25), value: selectedSection == .transactions)
                .animation(.easeInOut(duration: 0.25), value: selectedSection == .trips)
            }
            .navigationTitle(Text("교통카드 리더"))
            .background(Color(.systemGroupedBackground))
        }
        .onChange(of: reader.cardInfo != nil) { hasCard in
            if hasCard, let card = reader.cardInfo {
                historyStore.save(card)
                // Auto-select first available section
                if !card.transactions.isEmpty {
                    selectedSection = .transactions
                } else if !card.trips.isEmpty {
                    selectedSection = .trips
                }
            }
            if !hasCard {
                cardAppeared = false
                selectedSection = nil
            }
        }
    }

    // MARK: - Scan Section

    // MARK: - Scan Guide (shown when no card scanned)

    private var scanGuide: some View {
        VStack(spacing: 24) {
            // Large illustration
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [.blue.opacity(0.08), .clear],
                            center: .center, startRadius: 20, endRadius: 80
                        )
                    )
                    .frame(width: 160, height: 160)

                Image(systemName: "iphone.gen3")
                    .font(.system(size: 60, weight: .thin))
                    .foregroundStyle(.secondary.opacity(0.4))

                Image(systemName: "creditcard.fill")
                    .font(.system(size: 28, weight: .light))
                    .foregroundStyle(.blue.opacity(0.6))
                    .offset(x: 30, y: -20)
                    .rotationEffect(.degrees(-15))

                Image(systemName: "wave.3.forward")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.blue.opacity(0.4))
                    .offset(x: 15, y: -5)
            }

            // Instructions
            VStack(spacing: 12) {
                guideStep(number: "1", text: L("카드 스캔"), icon: "hand.tap.fill")
                guideStep(number: "2", text: L("교통카드를 iPhone 뒷면에 가까이 대주세요"), icon: "iphone.rear.camera")
                guideStep(number: "3", text: L("이용 내역"), icon: "list.bullet.rectangle.portrait")
            }

            // Supported cards
            VStack(spacing: 8) {
                Text("Supported Cards")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 14) {
                    supportedCard(
                        name: "T-MONEY", icon: "bus.fill", color: .blue,
                        gradColors: [Color(red: 0.12, green: 0.30, blue: 0.80), Color(red: 0.20, green: 0.55, blue: 0.95)]
                    )
                    supportedCard(
                        name: "CASHBEE", icon: "creditcard.fill", color: .orange,
                        gradColors: [Color(red: 0.85, green: 0.40, blue: 0.08), Color(red: 0.95, green: 0.60, blue: 0.15)]
                    )
                    supportedCard(
                        name: "RAIL+", icon: "tram.fill", color: .purple,
                        gradColors: [Color(red: 0.45, green: 0.18, blue: 0.75), Color(red: 0.65, green: 0.35, blue: 0.90)]
                    )
                }
            }
        }
        .padding(.vertical, 20)
    }

    private func guideStep(number: String, text: String, icon: String) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(.blue.opacity(0.1))
                    .frame(width: 32, height: 32)
                Text(number)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.blue)
            }
            Text(text)
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 16)
    }

    private func supportedCard(name: String, icon: String, color: Color, gradColors: [Color]) -> some View {
        VStack(spacing: 6) {
            ZStack {
                // Card shape with premium gradient
                RoundedRectangle(cornerRadius: 8)
                    .fill(
                        LinearGradient(colors: gradColors,
                                       startPoint: .topLeading, endPoint: .bottomTrailing)
                    )
                    .frame(width: 80, height: 50)
                    // Shine overlay
                    .overlay(
                        LinearGradient(
                            colors: [.white.opacity(0.3), .white.opacity(0.05), .clear],
                            startPoint: .topLeading, endPoint: .center
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(.white.opacity(0.15), lineWidth: 0.5)
                    )
                    .shadow(color: gradColors.first?.opacity(0.4) ?? .clear, radius: 6, y: 3)

                // Card content
                VStack(spacing: 2) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .medium))
                    Text(name)
                        .font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(.white)
            }
        }
    }

    // MARK: - Scan Button

    private var scanSection: some View {
        Button {
            reader.startScan()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    if reader.isScanning {
                        Circle()
                            .stroke(Color.white.opacity(0.3), lineWidth: 1.5)
                            .frame(width: 44, height: 44)
                            .scaleEffect(pulseScale)
                            .opacity(pulseOpacity)
                            .onAppear {
                                withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                                    pulseScale = 1.5; pulseOpacity = 0.0
                                }
                            }
                            .onDisappear { pulseScale = 1.0; pulseOpacity = 0.6 }
                    }
                    Image(systemName: reader.isScanning ? "antenna.radiowaves.left.and.right" : "wave.3.right.circle.fill")
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(.white)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 3) {
                    Text(reader.isScanning ? LocalizedStringKey("스캔 중...") : LocalizedStringKey("카드 스캔"))
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                    Text("T-money · Cashbee · Rail+")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.6))
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                LinearGradient(
                    colors: reader.isScanning ? [.gray.opacity(0.6), .gray.opacity(0.4)] : [Color.blue, Color(red: 0.2, green: 0.5, blue: 1.0)],
                    startPoint: .leading, endPoint: .trailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(reader.isScanning)
        .buttonStyle(.plain)
    }

    // MARK: - Virtual Card

    private func virtualCard(_ card: TransitCardInfo) -> some View {
        let grad = cardGradient(card.cardType)
        return HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                // Card type
                HStack(spacing: 5) {
                    Image(systemName: card.cardType.icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(card.cardType.displayName)
                        .font(.system(size: 13, weight: .bold))
                }
                .opacity(0.9)

                // Balance
                Text(formatKRW(card.balance))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .monospacedDigit()

                // UID + CSN
                VStack(alignment: .leading, spacing: 1) {
                    Text(card.cardUID)
                        .font(.system(size: 9, design: .monospaced))
                        .opacity(0.6)
                    if !card.cardNumber.isEmpty {
                        Text(card.cardNumber)
                            .font(.system(size: 9, design: .monospaced))
                            .opacity(0.6)
                    }
                }
            }
            Spacer()
            Image(systemName: "wave.3.right")
                .font(.system(size: 28, weight: .ultraLight))
                .opacity(0.3)
        }
        .padding(18)
        .foregroundColor(.white)
        .background(
            LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing)
                .overlay(
                    LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .topLeading, endPoint: .center)
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: grad.first?.opacity(0.25) ?? .clear, radius: 10, y: 4)
        .scaleEffect(cardAppeared ? 1.0 : 0.95)
        .opacity(cardAppeared ? 1.0 : 0.0)
        .onAppear {
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { cardAppeared = true }
        }
    }

    // MARK: - Section Buttons

    private func sectionButtons(_ card: TransitCardInfo) -> some View {
        HStack(spacing: 10) {
            sectionButton(
                title: "이용 내역",
                icon: "clock.arrow.circlepath",
                section: .transactions,
                color: .blue,
                count: card.transactions.count
            )
            sectionButton(
                title: "교통 이용 내역",
                icon: "map.fill",
                section: .trips,
                color: .purple,
                count: card.trips.count
            )
        }
    }

    private func sectionButton(title: LocalizedStringKey, icon: String, section: ResultSection, color: Color, count: Int) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = isSelected ? nil : section
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(title)
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(
                        Capsule().fill(isSelected ? .white.opacity(0.25) : color.opacity(0.12))
                    )
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? .white : color)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? color : color.opacity(0.06))
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func badge(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(color.opacity(0.8))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.08), in: Capsule())
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(message).font(.subheadline)
            Spacer()
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(.red.opacity(0.06)))
    }

    private var noDataView: some View {
        HStack(spacing: 10) {
            Image(systemName: "tray").foregroundStyle(.tertiary)
            Text("이용 내역이 없습니다").font(.subheadline).foregroundStyle(.secondary)
            Spacer()
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private func rawDataSection(_ data: [RawDataEntry]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(Array(data.enumerated()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.key).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                        Text(item.value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                    }.padding(.vertical, 2)
                }
            }.padding(.top, 6)
        } label: {
            Label("Raw Data (\(data.count))", systemImage: "doc.text.magnifyingglass")
                .font(.system(size: 13, weight: .bold))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private func debugLogSection(_ lines: [String]) -> some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(debugColor(line))
                        .textSelection(.enabled)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
        } label: {
            Label("Debug Log (\(lines.count))", systemImage: "ladybug.fill")
                .font(.system(size: 13, weight: .bold))
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }

    private func debugColor(_ line: String) -> Color {
        if line.contains("✅") { return .green }
        if line.contains("❌") { return .red }
        if line.contains("[BALANCE]") { return .cyan }
        if line.contains("[TX]") { return .purple }
        return .primary
    }
}

// MARK: - Transaction List View

struct TransactionListView: View {
    let transactions: [TransactionRecord]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(transactions.enumerated()), id: \.element.id) { index, tx in
                HStack(spacing: 10) {
                    ZStack {
                        Circle()
                            .fill(transactionColor(tx.type).opacity(0.12))
                            .frame(width: 40, height: 40)
                        Image(systemName: transactionIcon(tx.type))
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(transactionColor(tx.type))
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text(transactionLabel(tx.type))
                            .font(.system(size: 14, weight: .semibold))
                        if let date = tx.date {
                            Text("\(formatDate24h(date)) \(formatTime24h(date))")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 3) {
                        Text((tx.type == .topUp ? "+" : "-") + formatKRW(tx.amount))
                            .font(.system(size: 14, weight: .bold))
                            .monospacedDigit()
                            .foregroundStyle(tx.type == .topUp ? .green : .primary)
                        Text(formatKRW(tx.balance))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.tertiary)
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(tx.type == .topUp ? Color.green.opacity(0.03) : Color.clear)

                if index < transactions.count - 1 {
                    Divider().padding(.leading, 62)
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
    }
}

// MARK: - Trip List View

struct TripListView: View {
    let trips: [TripRecord]

    var body: some View {
        VStack(spacing: 10) {
            ForEach(trips) { trip in
                tripCard(trip)
            }
        }
    }

    private func tripCard(_ trip: TripRecord) -> some View {
        let accent: Color = trip.isTransfer ? .orange : .blue
        return VStack(alignment: .leading, spacing: 10) {
            // Header
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9)
                        .fill(accent.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: trip.isTransfer ? "arrow.triangle.swap" : firstTransportIcon(trip))
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(accent)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(trip.transportDescription)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    HStack(spacing: 6) {
                        if let d = trip.boardingDate {
                            Text(formatDate24h(d)).font(.system(size: 10))
                        }
                        if trip.distanceMeters > 0 {
                            Text(String(format: "%.1f km", trip.distanceKm))
                                .font(.system(size: 10, weight: .medium))
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(accent.opacity(0.1), in: Capsule())
                        }
                        if trip.balanceAfter > 0 {
                            HStack(spacing: 2) {
                                Text(formatKRW(trip.balanceAfter + trip.totalFare))
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 6, weight: .bold))
                                Text(formatKRW(trip.balanceAfter))
                            }
                            .font(.system(size: 9, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(accent)
                        }
                    }
                    .foregroundStyle(.secondary)
                }
                Spacer()
                Text("-" + formatKRW(trip.totalFare))
                    .font(.system(size: 14, weight: .bold))
                    .monospacedDigit()
            }

            // Timeline with running balance
            let chrono = Array(trip.legs.reversed())
            // Compute sub-charges and running balance at each leg
            let subCharges: [Int] = chrono.enumerated().map { idx, leg in
                idx == 0 ? leg.fare : max(leg.fare - chrono[idx-1].fare, 0)
            }
            // Balance: work backward from balanceAfter
            // Last leg balance = balanceAfter, then add sub-charges going backward
            let legBalances: [Int] = {
                guard trip.balanceAfter > 0 else { return Array(repeating: 0, count: chrono.count) }
                var bals = Array(repeating: 0, count: chrono.count)
                bals[chrono.count - 1] = trip.balanceAfter
                for i in stride(from: chrono.count - 2, through: 0, by: -1) {
                    bals[i] = bals[i + 1] + subCharges[i + 1]
                }
                return bals
            }()
            VStack(spacing: 0) {
                ForEach(Array(chrono.enumerated()), id: \.offset) { idx, leg in
                    let sub = subCharges[idx]
                    let bal = legBalances[idx]
                    HStack(spacing: 0) {
                        // Timeline dot + line + transfer indicator
                        VStack(spacing: 0) {
                            if idx > 0 {
                                // Check if this is a transfer (prev was alight, now boarding)
                                let prevLeg = chrono[idx - 1]
                                if leg.isBoarding && !prevLeg.isBoarding {
                                    // Transfer point: alight → board again
                                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 2, height: 4)
                                    Image(systemName: "arrow.triangle.swap")
                                        .font(.system(size: 8, weight: .bold))
                                        .foregroundStyle(.orange)
                                        .frame(width: 14, height: 14)
                                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 2, height: 4)
                                } else {
                                    Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 2, height: 10)
                                }
                            } else {
                                Spacer().frame(width: 2, height: 6)
                            }
                            Circle()
                                .fill(leg.isBoarding ? Color.green : Color.red)
                                .frame(width: 8, height: 8)
                            if idx < chrono.count - 1 {
                                Rectangle().fill(Color.gray.opacity(0.2)).frame(width: 2, height: 6)
                            } else {
                                Spacer().frame(width: 2, height: 6)
                            }
                        }
                        .frame(width: 20)

                        HStack(spacing: 5) {
                            // Transport icon + direction
                            Image(systemName: transportIcon(leg.transportType))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundStyle(.secondary)
                                .frame(width: 12)
                            Image(systemName: leg.isBoarding ? "arrow.up.right" : "arrow.down.left")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(leg.isBoarding ? .green : .red)
                                .frame(width: 12)
                            // Time
                            if let date = leg.date {
                                Text(formatTime24h(date))
                                    .font(.system(size: 11, design: .monospaced))
                            } else {
                                Text("--:--:--")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.quaternary)
                            }
                            Spacer()
                            // Sub-charge
                            Text("-" + formatKRW(sub))
                                .font(.system(size: 11, weight: sub > 0 ? .semibold : .regular))
                                .monospacedDigit()
                                .foregroundStyle(sub > 0 ? .primary : .quaternary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .padding(.leading, 6)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.regularMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(
                            trip.isTransfer ? Color.orange.opacity(0.3) : Color.gray.opacity(0.1),
                            lineWidth: trip.isTransfer ? 1.5 : 1
                        )
                )
        )
    }

    private func firstTransportIcon(_ trip: TripRecord) -> String {
        let type = trip.legs.last(where: { $0.isBoarding })?.transportType ?? 0
        return transportIcon(type)
    }
}

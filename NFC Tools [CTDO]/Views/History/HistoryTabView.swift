import SwiftUI

struct HistoryTabView: View {
    @EnvironmentObject var historyStore: ScanHistoryStore
    @EnvironmentObject var settings: SettingsStore
    @State private var showClearAlert = false

    var body: some View {
        NavigationStack {
            Group {
                if historyStore.entries.isEmpty {
                    emptyState
                } else {
                    historyList
                }
            }
            .navigationTitle(Text("스캔 기록"))
            .toolbar {
                if !historyStore.entries.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .destructive) {
                            showClearAlert = true
                        } label: {
                            Image(systemName: "trash")
                                .font(.system(size: 14))
                        }
                    }
                }
            }
            .alert("전체 삭제", isPresented: $showClearAlert) {
                Button("삭제", role: .destructive) {
                    withAnimation { historyStore.clearAll() }
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("모든 스캔 기록을 삭제하시겠습니까?")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("스캔 기록이 없습니다")
                .font(.headline)
                .foregroundStyle(.secondary)
            Text("카드를 스캔하면 여기에 기록됩니다")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var historyList: some View {
        List {
            ForEach(historyStore.entries) { entry in
                NavigationLink {
                    HistoryDetailView(entry: entry)
                        .environmentObject(settings)
                } label: {
                    HistoryRowView(entry: entry)
                }
            }
            .onDelete { offsets in
                withAnimation { historyStore.delete(at: offsets) }
            }
        }
        .listStyle(.insetGrouped)
    }
}

// MARK: - History Row

struct HistoryRowView: View {
    let entry: ScanHistoryEntry

    var body: some View {
        HStack(spacing: 12) {
            // Card type icon
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(cardColor(entry.cardInfo.cardType).opacity(0.12))
                    .frame(width: 44, height: 44)
                Image(systemName: entry.cardInfo.cardType.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(cardColor(entry.cardInfo.cardType))
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.cardInfo.cardType.displayName)
                    .font(.system(size: 15, weight: .semibold))
                HStack(spacing: 8) {
                    Text(formatKRW(entry.cardInfo.balance))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.blue)
                    Text(formatRelativeDate(entry.scanDate))
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()
        }
        .padding(.vertical, 2)
    }
}

// MARK: - History Detail (reuses TransactionListView + TripListView from CheckTabView)

struct HistoryDetailView: View {
    let entry: ScanHistoryEntry
    @EnvironmentObject var settings: SettingsStore
    @State private var selectedSection: DetailSection? = nil

    enum DetailSection { case transactions, trips }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Virtual card (compact horizontal like Check tab)
                let grad = cardGradient(entry.cardInfo.cardType)
                HStack(spacing: 0) {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 5) {
                            Image(systemName: entry.cardInfo.cardType.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(entry.cardInfo.cardType.displayName)
                                .font(.system(size: 13, weight: .bold))
                        }
                        .opacity(0.9)

                        Text(formatKRW(entry.cardInfo.balance))
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .monospacedDigit()

                        HStack(spacing: 8) {
                            Text(entry.cardInfo.cardUID)
                                .font(.system(size: 9, design: .monospaced))
                            if !entry.cardInfo.cardNumber.isEmpty {
                                Text(entry.cardInfo.cardNumber)
                                    .font(.system(size: 9, design: .monospaced))
                            }
                        }
                        .opacity(0.5)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Image(systemName: "wave.3.right")
                            .font(.system(size: 24, weight: .ultraLight))
                            .opacity(0.3)
                        Spacer()
                        HStack(spacing: 3) {
                            Image(systemName: "calendar")
                                .font(.system(size: 9))
                            Text(entry.scanDate, format: .dateTime.month().day().hour().minute())
                                .font(.system(size: 10))
                        }
                        .opacity(0.6)
                    }
                }
                .padding(16)
                .foregroundColor(.white)
                .background(
                    LinearGradient(colors: grad, startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(LinearGradient(colors: [.white.opacity(0.15), .clear], startPoint: .topLeading, endPoint: .center))
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: grad.first?.opacity(0.2) ?? .clear, radius: 8, y: 4)

                // Slim section buttons (same style as Check tab)
                HStack(spacing: 8) {
                    slimButton(
                        title: "이용 내역", icon: "clock.arrow.circlepath",
                        section: .transactions, color: .blue, count: entry.cardInfo.transactions.count
                    )
                    slimButton(
                        title: "교통 이용 내역", icon: "map.fill",
                        section: .trips, color: .purple, count: entry.cardInfo.trips.count
                    )
                }

                // Content - reuse shared views from CheckTabView
                if selectedSection == .transactions && !entry.cardInfo.transactions.isEmpty {
                    TransactionListView(transactions: entry.cardInfo.transactions)
                        .transition(.opacity)
                }
                if selectedSection == .trips && !entry.cardInfo.trips.isEmpty {
                    TripListView(trips: entry.cardInfo.trips)
                        .transition(.opacity)
                }

                if settings.debugMode && !entry.cardInfo.rawData.isEmpty {
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(entry.cardInfo.rawData.enumerated()), id: \.offset) { _, item in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(item.key).font(.system(size: 10, weight: .bold)).foregroundStyle(.secondary)
                                    Text(item.value).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                                }.padding(.vertical, 2)
                            }
                        }.padding(.top, 6)
                    } label: {
                        Label("Raw Data (\(entry.cardInfo.rawData.count))", systemImage: "doc.text.magnifyingglass")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial))
                }
            }
            .padding(16)
            .animation(.easeInOut(duration: 0.2), value: selectedSection == .transactions)
            .animation(.easeInOut(duration: 0.2), value: selectedSection == .trips)
        }
        .navigationTitle(entry.cardInfo.cardType.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            selectedSection = !entry.cardInfo.transactions.isEmpty ? .transactions : .trips
        }
    }

    private func slimButton(title: LocalizedStringKey, icon: String, section: DetailSection, color: Color, count: Int) -> some View {
        let isSelected = selectedSection == section
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedSection = isSelected ? nil : section
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon).font(.system(size: 12, weight: .medium))
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(isSelected ? .white.opacity(0.25) : color.opacity(0.12)))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 9)
            .padding(.horizontal, 6)
            .foregroundStyle(isSelected ? .white : color)
            .background(RoundedRectangle(cornerRadius: 10).fill(isSelected ? color : color.opacity(0.06)))
        }
        .buttonStyle(.plain)
    }
}

import SwiftUI
import Combine

class ScanHistoryStore: ObservableObject {
    @Published var entries: [ScanHistoryEntry] = []

    private let storageKey = "scanHistory"
    private let maxEntries = 50

    init() {
        load()
    }

    func save(_ cardInfo: TransitCardInfo) {
        let entry = ScanHistoryEntry(scanDate: Date(), cardInfo: cardInfo)
        entries.insert(entry, at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        persist()
    }

    func delete(at offsets: IndexSet) {
        entries.remove(atOffsets: offsets)
        persist()
    }

    func clearAll() {
        entries.removeAll()
        persist()
    }

    private func load() {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return }
        do {
            entries = try JSONDecoder().decode([ScanHistoryEntry].self, from: data)
        } catch {
            print("[ScanHistory] Failed to load: \(error)")
        }
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(entries)
            UserDefaults.standard.set(data, forKey: storageKey)
        } catch {
            print("[ScanHistory] Failed to save: \(error)")
        }
    }
}

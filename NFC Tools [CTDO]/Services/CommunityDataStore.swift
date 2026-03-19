import SwiftUI
import Combine

struct CommunityInfo: Codable {
    var discordName: String = "CTDOTEAM"
    var discordMembers: Int = 0
    var discordOnline: Int = 0
    var discordIconHash: String = ""
    var discordInvite: String = "9efNP6df"
    var telegramSubscribers1: Int = 0
    var telegramSubscribers2: Int = 0
    var lastUpdated: Date = .distantPast

    var discordIconURL: URL? {
        guard !discordIconHash.isEmpty else { return nil }
        return URL(string: "https://cdn.discordapp.com/icons/1272188246797062256/\(discordIconHash).png?size=128")
    }

    var isStale: Bool {
        Date().timeIntervalSince(lastUpdated) > 300 // 5 minutes
    }
}

class CommunityDataStore: ObservableObject {
    @Published var info: CommunityInfo

    private let cacheKey = "communityData"

    init() {
        // Load cache
        if let data = UserDefaults.standard.data(forKey: cacheKey),
           let cached = try? JSONDecoder().decode(CommunityInfo.self, from: data) {
            self.info = cached
        } else {
            self.info = CommunityInfo()
        }
    }

    func refreshIfNeeded() {
        guard info.isStale else { return }
        Task {
            await fetchDiscord()
            await fetchTelegram()
            await MainActor.run {
                info.lastUpdated = Date()
                save()
            }
        }
    }

    // MARK: - Discord

    private func fetchDiscord() async {
        // Use invite API (public, no auth needed)
        guard let url = URL(string: "https://discord.com/api/invites/\(info.discordInvite)?with_counts=true") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let guild = json["guild"] as? [String: Any] {
                let name = guild["name"] as? String ?? info.discordName
                let icon = guild["icon"] as? String ?? info.discordIconHash
                let members = json["approximate_member_count"] as? Int ?? info.discordMembers
                let online = json["approximate_presence_count"] as? Int ?? info.discordOnline
                await MainActor.run {
                    info.discordName = name
                    info.discordIconHash = icon
                    info.discordMembers = members
                    info.discordOnline = online
                }
            }
        } catch {
            print("[Community] Discord fetch failed: \(error)")
        }
    }

    // MARK: - Telegram

    private func fetchTelegram() async {
        // Telegram doesn't have a simple public API for subscriber count
        // Parse from t.me page meta tags
        await fetchTelegramChannel("dothanh1110", isFirst: true)
        await fetchTelegramChannel("dothanh1110v2", isFirst: false)
    }

    private func fetchTelegramChannel(_ username: String, isFirst: Bool) async {
        guard let url = URL(string: "https://t.me/\(username)") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                // Parse subscriber count from meta or page content
                // Look for patterns like "2 039 subscribers" or "1,178 subscribers"
                let patterns = [
                    "([\\d\\s,]+)\\s*subscribers",
                    "([\\d\\s,]+)\\s*members"
                ]
                for pattern in patterns {
                    if let regex = try? NSRegularExpression(pattern: pattern),
                       let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
                       let range = Range(match.range(at: 1), in: html) {
                        let numStr = String(html[range])
                            .replacingOccurrences(of: " ", with: "")
                            .replacingOccurrences(of: ",", with: "")
                            .replacingOccurrences(of: "\u{00a0}", with: "")
                        if let count = Int(numStr) {
                            await MainActor.run {
                                if isFirst {
                                    info.telegramSubscribers1 = count
                                } else {
                                    info.telegramSubscribers2 = count
                                }
                            }
                            break
                        }
                    }
                }
            }
        } catch {
            print("[Community] Telegram fetch failed: \(error)")
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(info) {
            UserDefaults.standard.set(data, forKey: cacheKey)
        }
    }
}

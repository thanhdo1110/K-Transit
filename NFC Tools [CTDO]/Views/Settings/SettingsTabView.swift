import SwiftUI

struct SettingsTabView: View {
    @EnvironmentObject var settings: SettingsStore

    var body: some View {
        NavigationStack {
            List {
                // MARK: - Appearance
                Section {
                    Picker(selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    } label: {
                        Label("테마", systemImage: "paintbrush")
                    }
                } header: {
                    Text("외관")
                }

                // MARK: - Language
                Section {
                    Picker(selection: $settings.language) {
                        ForEach(AppLanguage.allCases, id: \.self) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    } label: {
                        Label("언어", systemImage: "globe")
                    }
                    .onChange(of: settings.language) { newLang in
                        UserDefaults.standard.set([newLang.rawValue], forKey: "AppleLanguages")
                    }
                } header: {
                    Text("언어")
                }

                // MARK: - Developer
                Section {
                    Toggle(isOn: $settings.debugMode) {
                        Label("디버그 모드", systemImage: "ladybug")
                    }
                } header: {
                    Text("개발자")
                } footer: {
                    Text("Raw 데이터와 디버그 로그를 표시합니다")
                }

                // MARK: - About
                Section {
                    HStack {
                        Text("버전")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Build")
                        Spacer()
                        Text(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("정보")
                }

                // MARK: - Community
                Section {
                    // Telegram Personal
                    socialLink(
                        url: "https://t.me/dothanh1110",
                        imageURL: "https://cdn5.telesco.pe/file/mJebRHpZmOEApRKwvBLIzjjFzn2KEuHLJcABwR2lwFIZ48W-qzH9LtV5yNyDkC1R7dwEr7PfnLt-KAuhP2Fk9i3LUeJKrga2EdewRO-oHATdmM3ZayxPKhYwuj0Bz8xcxCI8ta_yHq4mug3YIaM6PZgMdR6mdJhtaQZInvoTEECxK-saW7QSIJWnJyayKhBUa7gtUbUGMCwC4x_XWyAPFEqFGWDJ_5HN_N90qOjOi2p7SsGaP4yoWw1z93rikwq9FuGT-Ld4OtcS1vJE8dM9QUOK6MWE8T5Xsj1XlCfzWZIz4sBmMxZmDOqY7XKuDCPEFlis3lHVHTpyKH0FY6JOfQ.jpg",
                        title: "Đỗ Thành #1110",
                        subtitle: "@dothanh1110 · 2,039 subscribers",
                        fallbackIcon: "paperplane.fill",
                        accentColor: Color(red: 0.16, green: 0.63, blue: 0.89)
                    )

                    // Telegram Channel V2
                    socialLink(
                        url: "https://t.me/dothanh1110v2",
                        imageURL: "https://cdn5.telesco.pe/file/cXPiZ3qxd_CRp4EYpxJOuApVxptOpzALW2YEWR0QrhDlTCOw3HpDEVKU0Gwby5W3icp4TEUJmuF7X41NU23b8cIm1Gwm4SGsCMcijePuLcQYc6ryWa32FlVfdHlUoew8e-S_tpqcfb4BA67txX_zoPl70PRydvsX6OvFgJtWv_YAijaK1x_yjjxZHj6c5k-aI2J7wcyEfl3pm4DFJ_bEs8Kfgv5Xf_4mIFWLikKMziculI8tlX1eUedVSYyk9Hh5_mhPEcK7RLHLRQECAd4dyC4A0DsvRb0WNFqHSTlCLQE4wfpULz8G8kVXmZwyxqsVrIF5Ld53EIzCXho14WDZKg.jpg",
                        title: "Đỗ Thành #1110 [V2]",
                        subtitle: "@dothanh1110v2 · 1,178 subscribers",
                        fallbackIcon: "megaphone.fill",
                        accentColor: Color(red: 0.16, green: 0.63, blue: 0.89)
                    )

                    // Discord
                    socialLink(
                        url: "https://discord.com/invite/9efNP6df",
                        imageURL: "https://cdn.discordapp.com/icons/1272188246797062256/a98701be770571debcaeb7beb5fd56a9.png?size=128",
                        title: "CTDOTEAM",
                        subtitle: "Discord · 1,300 members · 183 online",
                        fallbackIcon: "bubble.left.and.bubble.right.fill",
                        accentColor: Color(red: 0.35, green: 0.40, blue: 0.95)
                    )
                    // Facebook Group
                    socialLink(
                        url: "https://www.facebook.com/groups/ctdo.net",
                        imageURL: nil,
                        title: "CTDO Community",
                        subtitle: "Facebook Group · ctdo.net",
                        fallbackIcon: "person.3.fill",
                        accentColor: Color(red: 0.23, green: 0.35, blue: 0.60)
                    )
                } header: {
                    Text("커뮤니티")
                }

                // MARK: - Credits
                Section {
                    VStack(spacing: 8) {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 40))
                            .foregroundStyle(.blue)
                        Text("NFC Tools [CTDO]")
                            .font(.system(size: 16, weight: .bold))
                        Text("by Đỗ Trung Thành")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        Text("CTDO.NET")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            }
            .navigationTitle(Text("설정"))
        }
    }

    // MARK: - Social Link Row

    private func socialLink(url: String, imageURL: String?, title: String, subtitle: String, fallbackIcon: String, accentColor: Color) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 12) {
                // Avatar
                if let imgURL = imageURL, let url = URL(string: imgURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 40, height: 40)
                                .clipShape(Circle())
                        default:
                            fallbackAvatar(icon: fallbackIcon, color: accentColor)
                        }
                    }
                } else {
                    fallbackAvatar(icon: fallbackIcon, color: accentColor)
                }

                // Info
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "arrow.up.right")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func fallbackAvatar(icon: String, color: Color) -> some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.12))
                .frame(width: 40, height: 40)
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(color)
        }
    }
}

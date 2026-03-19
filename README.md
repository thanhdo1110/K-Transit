<p align="center">
  <img src="https://img.shields.io/badge/iOS-16.0%2B-blue?style=flat-square&logo=apple" />
  <img src="https://img.shields.io/badge/Swift-5.9-orange?style=flat-square&logo=swift" />
  <img src="https://img.shields.io/badge/NFC-CoreNFC-green?style=flat-square" />
  <img src="https://img.shields.io/badge/License-MIT-yellow?style=flat-square" />
  <img src="https://img.shields.io/github/stars/thanhdo1110/K-Transit?style=flat-square" />
</p>

# K-Transit (케이트랜싯)

> Korean transit card reader for iOS — Read T-money, Cashbee & Rail Plus cards via NFC

K-Transit reads Korean public transit cards through your iPhone's NFC sensor, displaying real-time balance, complete transaction history, and detailed trip timelines with transfer tracking.

---

## Features

| Feature | Description |
|---------|-------------|
| **Balance Check** | Instant card balance reading via NFC |
| **Transaction History** | Financial log with dates, fares, balances |
| **Trip Timeline** | Boarding/alighting times, transfers, sub-charges |
| **Distance Tracking** | Per-trip distance in km (from card data) |
| **Transfer Detection** | Visual indicators for bus↔subway↔train transfers |
| **Multi-Card** | T-money, Cashbee, Rail Plus support |
| **Scan History** | Locally saved past scans with full detail |
| **3 Languages** | 한국어 · English · Tiếng Việt (instant switch) |
| **Dark Mode** | System / Light / Dark theme |
| **Debug Mode** | Raw APDU data & debug logs for developers |
| **Bank Card Detection** | Clear error message for unsupported EMV cards |

---

## Architecture

```
K-Transit/
├── Models/
│   ├── KoreanCardType.swift        # Card type enum (T-money, Cashbee, Rail Plus)
│   ├── TransactionRecord.swift     # Financial transaction model
│   ├── TripModels.swift            # TripRecord + TripLeg with transport info
│   ├── TransitCardInfo.swift       # Complete card scan result
│   └── ScanHistoryEntry.swift      # Persistent scan history entry
├── Services/
│   ├── NFCCardReader.swift         # Core NFC communication & APDU parsing
│   ├── ScanHistoryStore.swift      # Local persistence (UserDefaults + Codable)
│   ├── SettingsStore.swift         # App settings (language, theme, debug)
│   └── CommunityDataStore.swift    # Live community stats (Discord, Telegram)
├── Views/
│   ├── MainTabView.swift           # Root TabBar (Check / History / Settings)
│   ├── Check/
│   │   └── CheckTabView.swift      # Scan + card display + trip timeline
│   ├── History/
│   │   └── HistoryTabView.swift    # Saved scans list + detail view
│   └── Settings/
│       └── SettingsTabView.swift   # Language, theme, debug, social links
├── Utilities/
│   ├── Formatters.swift            # KRW currency, 24h time, date formatters
│   ├── TransitHelpers.swift        # Transport icons, colors, gradients
│   └── LocalizedString.swift       # L() helper for instant language switching
└── Localizable.xcstrings           # String catalog (ko/en/vi, 85+ keys)
```

---

## Technical Deep Dive

### NFC Communication Protocol

K-Transit communicates with transit cards using ISO 14443 / ISO 7816 APDU commands:

| Command | APDU | Description |
|---------|------|-------------|
| SELECT | `00 A4 04 00 [AID]` | Select transit application by AID |
| GET BALANCE | `90 4C 00 00 04` | Read card balance (4 bytes BE) |
| READ RECORD | `00 B2 XX [SFI]` | Read SFI records (up to 30 per file) |

### Card Data Structure

| SFI | Record Size | Content | Count |
|-----|-------------|---------|-------|
| SFI 3 | 52 bytes | Trip details (timestamps, transport type, distance) | Up to 20 |
| SFI 4 | 26B (Cashbee) / 46B (T-money) | Financial records (balance, fare, marker) | Up to 20 |
| SFI 5 | 46 bytes | Top-up history (T-money only) | Up to 5 |

### Timestamp Format (Reverse-Engineered)

SFI 3 bytes[11-14] use a **packed date-time format** — NOT seconds-from-epoch:

```
┌─────────────────┬──────────┬───────────┬────────────┐
│ Day Counter (16) │ Hour (5) │ Minute (6)│ Sec/2 (5)  │
│  from 1989-06-14 │  0-23    │   0-59    │  0-29      │
└─────────────────┴──────────┴───────────┴────────────┘

Example: 0x34729132
  Day:    0x3472 = 13426 → 2026-03-18
  Hour:   10010  = 18
  Minute: 001001 = 9
  Second: 10010  = 18 → 36sec
  Result: 2026-03-18 18:09:36 ✓
```

### Data Merging Strategy

```
SFI 3 (Trip Details)     SFI 4 (Financial)
┌──────────────────┐     ┌──────────────────┐
│ Timestamps ✓     │     │ Balance ✓        │
│ Transport Type ✓ │     │ Actual Fare ✓    │
│ Distance ✓       │  ⟹  │ Marker Type ✓    │
│ Base Fare        │     │ BCD Date (0x0720)│
│ Balance ✗        │     │ Timestamps ✗     │
└──────────────────┘     └──────────────────┘
         │                        │
         └────── Merge ───────────┘
                  │
         ┌───────▼────────┐
         │ Complete Record │
         │ Date + Balance  │
         │ + Actual Fare   │
         │ + Distance      │
         └────────────────┘
```

**Matching rules:**
- `0x4913` marker → standard transit charge → match with SFI 3 by position
- `0x0720` marker → sub-charge with BCD timestamp at bytes[26-32]
- `0x49XX` (non-0x4913) → transfer surcharge → no SFI 3 match
- Sub-charges computed from consecutive SFI 3 fare differences

### Distance Extraction

SFI 3 alighting records bytes[19-20] contain distance in **meters**:
```
0x1F4A = 8010 → 8.01 km ✓
0x529E = 21150 → 21.15 km ✓
```

---

## Supported Cards

| Card | AID | Balance | Transactions | Trips |
|------|-----|---------|--------------|-------|
| **T-money** | `D4100000030001` | ✅ | ✅ (20 records) | ✅ (20 records) |
| **Cashbee** | `D4100000140001` | ✅ | ✅ (20 records) | ✅ (20 records) |
| **Rail Plus** | `D4100000030003` | ✅ | ✅ | ✅ |
| **Bank Cards** (Visa/MC) | — | ❌ | ❌ | ❌ |

> **Note:** Bank/credit cards with transit function cannot be read on iOS due to Apple's security policy on EMV payment cards. This is an OS-level restriction affecting all third-party NFC apps.

---

## Requirements

- **iOS 16.0+**
- **iPhone 7** or later (NFC capable)
- Physical Korean transit card

---

## Build & Run

```bash
# Clone
git clone https://github.com/thanhdo1110/K-Transit.git

# Open in Xcode
open "NFC Tools [CTDO].xcodeproj"

# Configure
# 1. Set your development team in Signing & Capabilities
# 2. Ensure "NFC Tag Reading" capability is enabled
# 3. Build and run on a PHYSICAL device (NFC unavailable in simulator)
```

---

## Localization

All 85+ strings localized in Korean, English, and Vietnamese with instant in-app switching:

| | Korean | English | Vietnamese |
|--|--------|---------|------------|
| Tab | 확인 | Check | Kiểm tra |
| Tab | 기록 | History | Lịch sử |
| Tab | 설정 | Settings | Cài đặt |
| Transport | 버스 | Bus | Xe buýt |
| Transport | 지하철 | Subway | Tàu điện ngầm |
| Transport | 기차 | Train | Tàu hỏa |

---

## References

- [KS X 6924 Standard Paper](https://www.koreascience.or.kr/article/CFKO201202135240043.pdf)
- [Metrodroid](https://github.com/metrodroid/metrodroid) — Open source transit card reader (Android/iOS)
- [KoreaTransitCardBalanceChecker](https://github.com/happybono/KoreaTransitCardBalanceChecker) — Arduino NFC reader
- [BlackHat Asia 2017 — Breaking Korea Transit Card](https://blackhat.com/docs/asia-17/materials/asia-17-Kim-Breaking-Korea-Transit-Card-With-Side-Channel-Attack-Unauthorized-Recharging.pdf)

---

## Community

<p>
  <a href="https://t.me/dothanh1110"><img src="https://img.shields.io/badge/Telegram-@dothanh1110-26A5E4?style=flat-square&logo=telegram" /></a>
  <a href="https://t.me/dothanh1110v2"><img src="https://img.shields.io/badge/Channel-@dothanh1110v2-26A5E4?style=flat-square&logo=telegram" /></a>
  <a href="https://discord.com/invite/9efNP6df"><img src="https://img.shields.io/badge/Discord-CTDOTEAM-5865F2?style=flat-square&logo=discord&logoColor=white" /></a>
  <a href="https://www.facebook.com/groups/ctdo.net"><img src="https://img.shields.io/badge/Facebook-CTDO-1877F2?style=flat-square&logo=facebook&logoColor=white" /></a>
</p>

---

## License

[MIT](LICENSE) © 2026 [Đỗ Trung Thành](https://t.me/dothanh1110)

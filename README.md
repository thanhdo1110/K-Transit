# K-Transit (케이트랜싯)

Korean transit card reader for iOS. Read T-money, Cashbee, and Rail Plus cards via NFC.

## Features

- **Real-time balance check** — Instant card balance reading
- **Transaction history** — Detailed financial log with dates, fares, and balances
- **Trip details** — Boarding/alighting times, transfer indicators, distance (km), sub-charges
- **Multi-card support** — T-money, Cashbee, Rail Plus
- **Scan history** — Locally saved past scans
- **Multilingual** — Korean (한국어), English, Vietnamese (Tiếng Việt)
- **Theme** — System / Light / Dark mode
- **Debug mode** — Raw APDU data and debug logs for developers

## Screenshots

Coming soon.

## Technical Details

### NFC Communication
- ISO 14443 / ISO 7816 tag reading via CoreNFC
- APDU commands: `SELECT` (00 A4), `GET BALANCE` (90 4C), `READ RECORD` (00 B2)
- Reads SFI 3 (trip details, up to 20 records), SFI 4 (financial log, up to 20 records), SFI 5 (top-up history)

### Timestamp Format
SFI 3 bytes[11-14] use a packed date-time format (not seconds-from-epoch):
```
bits[31:16] = day counter (epoch: 1989-06-14)
bits[15:11] = hour (0-23)
bits[10:5]  = minute (0-59)
bits[4:0]   = second / 2 (0-29)
```

### Data Merging
- SFI 3 provides trip timestamps and distance
- SFI 4 provides real balance and actual fares (including distance surcharges)
- Merged positionally (both newest-first) for complete trip+balance data
- BCD timestamps parsed from 0x0720 marker records

### Architecture
```
Models/          — Data models (Codable for persistence)
Services/        — NFCCardReader, ScanHistoryStore, SettingsStore
Views/
  Check/         — Main scan tab with card display and trip timeline
  History/       — Saved scan history
  Settings/      — Language, theme, debug, social links
  Components/    — Reusable UI components
Utilities/       — Formatters, helpers, localization
```

## Requirements

- iOS 16.0+
- iPhone 7 or later (NFC capable)
- Physical Korean transit card (T-money or Cashbee)

> **Note:** Bank cards (Visa/Mastercard with transit function) cannot be read due to iOS security restrictions on EMV payment cards.

## Build

1. Open `NFC Tools [CTDO].xcodeproj` in Xcode
2. Set your development team in Signing & Capabilities
3. Ensure "NFC Tag Reading" capability is enabled
4. Build and run on a physical device (NFC not available in simulator)

## References

- [KS X 6924 Standard](https://www.koreascience.or.kr/article/CFKO201202135240043.pdf)
- [Metrodroid](https://github.com/metrodroid/metrodroid) — Open source transit card reader
- [KoreaTransitCardBalanceChecker](https://github.com/happybono/KoreaTransitCardBalanceChecker) — Arduino NFC reader

## License

MIT License

## Author

**Đỗ Trung Thành (Do Trung Thanh)**
- Telegram: [@dothanh1110](https://t.me/dothanh1110)
- Channel: [@dothanh1110v2](https://t.me/dothanh1110v2)
- Discord: [CTDOTEAM](https://discord.com/invite/9efNP6df)
- Facebook: [CTDO Community](https://www.facebook.com/groups/ctdo.net)

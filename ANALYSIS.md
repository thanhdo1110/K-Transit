# NFC Korean Transit Card - Analysis Notes

## Context
- Both cards bought: **December 2025** in Korea
- Current date: **March 18, 2026**
- All trip dates must be between Dec 2025 and Mar 2026

---

## Cards
| | T-money | Cashbee |
|---|---|---|
| AID | `D4100000030001` | `D4100000140001` |
| UID | `AF 4C CA B7` | `6F E2 1C 53` |
| Balance | 31,370 KRW | 17,400 KRW |
| Parsed Issue Date | 2024-05-20 (WRONG - factory date?) | 2025-10-21 (WRONG?) |

---

## Known Issues

### 1. Timestamp Epoch Wrong (SFI 3, 52B records)
- **Current epoch**: 1998-01-01 00:00:00 KST
- **Result**: dates show ~Nov 2025 (BEFORE purchase in Dec 2025)
- **Fix needed**: epoch should be ~2 months later (~1998-03-01?)
- **With corrected epoch**: dates become Jan 2026 (AFTER purchase) ✅
- **Timestamp location**: bytes[11-14] big-endian uint32, seconds from epoch
- **Example**: `34 71 91 40` = 879,530,304 sec

### 2. Timestamp Wrong (SFI 5 / 90 4E, 46B records)
- **Current logic**: bytes[14-15]=`07 20` marker → bytes[18-21] as seconds from 2000-01-01
- **Result**: dates show Jul 2025 (IMPOSSIBLE - card not purchased)
- **Fix needed**: find correct epoch or correct byte offsets
- **CLUE**: T-money SFI4#9 bytes[26-32] = `20 26 03 17 12 26 38` = BCD **2026-03-17 12:26:38** KST = yesterday's date! This might be last-NFC-read timestamp, not transaction date.

### 3. SFI 3 + SFI 4 Overlap
- SFI 3 (52B): trip detail with timestamps, no balance
- SFI 4 (26B Cashbee / 46B T-money): financial log with real balance, no timestamps
- They contain the SAME transactions from different perspectives
- **Need**: merge by matching counters (SFI3 bytes[4-5] vs SFI4 bytes[8-9])

### 4. Issue Date Parsing
- PurseInfo[17-20] parsed as BCD YYYYMMDD
- T-money: `20 24 05 20` → 2024-05-20 (user says bought Dec 2025)
- Cashbee: `20 25 10 21` → 2025-10-21
- Likely MANUFACTURING date, not purchase date. Or BCD parsing wrong.

### 5. Top-ups Mixed with Trips
- SFI 4 = recent trips (last 5), SFI 5 = top-up history (T-money only)
- Different time periods → balance chain breaks when shown together
- **Fix**: display as separate sections

### 6. Cashbee SFI 5 Garbage Record
- SFI5#1: `70 18 08 00 00 00 03 0B...` → type=112 (0x70), balance=0
- Not a valid transaction, needs filtering (type should be 01 or 02)

---

## Data Format Reference

### PurseInfo (47 bytes, inside FCI tag B0)
```
[0]     cardType
[1]     algorithm
[2]     key version
[3]     idCenter (issuer: 8=T-money, 11=Cashbee)
[4-11]  CSN (Card Serial Number, 8 bytes hex)
[12-16] idtr (authentication ID, 5 bytes)
[17-20] issueDate (BCD YYYYMMDD)
[21-24] expiryDate (BCD YYYYMMDD)
[26]    userCode (1=adult, 2=child, 3=senior, 4=teen, 5=disabled)
[27]    discount classification
[27-30] max balance
[31-32] branch code
[33-36] transaction limit
[37]    mobile carrier
[38]    financial institution
[39-46] reserved
```

### SFI 3 Record (52 bytes) - Trip Detail
```
[0-1]   record type (01 32)
[2]     0x00=boarding, 0x01=alighting
[3]     transport type (0x00=bus, 0x01=metro, 0x02=train)
[4-5]   trip counter (big-endian, same for boarding+alighting pair)
[6-8]   terminal data
[9]     unknown (01)
[10]    fee type? (FF or F4)
[11-14] TIMESTAMP (big-endian uint32, seconds from ~1998 epoch)
[15-17] unknown
[18]    unknown
[19-20] pre-charge balance? (only on boarding records)
[22-23] base fare (big-endian KRW)
[24-27] terminal/station ID
[28]    unknown (04)
[29]    unknown (01)
[36]    unknown (C0)
[40-41] base fare (duplicate?)
[44-45] unknown fare value
[48]    unknown (40 on some)
[50-51] distance surcharge (big-endian KRW, only on boarding records)
```

### SFI 4 Record - Financial Log
**Cashbee format (26 bytes):**
```
[0]     type: 01=transit, 02=topUp
[1]     0x18
[2-3]   0x00 0x00
[4-5]   balance AFTER transaction (big-endian KRW) ← REAL VALUE
[6-7]   0x00 0x00
[8-9]   sequence counter (big-endian, decreasing = newer)
[10-11] 0x00 0x00
[12-13] fare amount (big-endian KRW, 0=boarding entry)
[14-15] 0x49 0x13 (transit marker) or 0x00 0x00 (topup)
[16-17] unknown
[18-21] unknown (terminal ID?)
[22-25] unknown (MAC/signature?)
```

**T-money format (46 bytes):**
```
[0]     type: 01=transit, 02=topUp
[1]     0x2C
[2-5]   balance AFTER (big-endian uint32 KRW) ← REAL VALUE
[6-7]   0x00 0x00
[8-9]   sequence counter (big-endian)
[10-11] 0x00 0x00
[12-13] fare amount (big-endian KRW)
[14-15] marker: 0x49 0x13 (transit) or 0x07 0x20 (topup/special)
[16-17] unknown
[18-21] unknown (timestamp for 0720 records? epoch unclear)
[22-25] unknown
[26-32] BCD timestamp YYYYMMDDHHMMSS (seen on SFI4#9-10: last read time?)
[33-45] zeros/padding
```

### SFI 5 Record (T-money only, 46B) - Top-up History
Same format as T-money SFI 4, but type=0x02 and bytes[14-15]=0x0720

### Balance Command
```
APDU: 90 4C 00 00 04
Response: 4 bytes big-endian uint32 KRW
```

---

## APDU Commands Used
| Command | Description | Notes |
|---|---|---|
| `00 A4 04 00 [Lc] [AID]` | SELECT by AID | |
| `90 4C 00 00 04` | GET BALANCE | 4 bytes big-endian KRW |
| `90 78 XX 00 10` | GET RECORD (proprietary) | 16B records, T-money only |
| `90 4E 00 XX` | GET DATA (proprietary) | 46B record, T-money only |
| `00 B2 XX [SFI*8+4]` | READ RECORD (ISO 7816) | SFI 3-6 |

---

## Reference URLs
- https://github.com/happybono/KoreaTransitCardBalanceChecker - Arduino NFC reader for T-money/Cashbee
- https://github.com/metrodroid/metrodroid - Open source transit card reader (KSX6924Application.kt, TMoneyTrip.kt, KSX6924PurseInfo.kt)
- https://www.koreascience.or.kr/article/CFKO201202135240043.pdf - Korean transit card paper
- http://www.codil.or.kr/filebank/original/RK/OTKCRK170036/OTKCRK170036.pdf - Korean transit standard doc
- https://blackhat.com/docs/asia-17/materials/asia-17-Kim-Breaking-Korea-Transit-Card-With-Side-Channel-Attack-Unauthorized-Recharging.pdf - Cashbee/EZL crypto analysis

---

## Full Raw Hex Data

### Cashbee Card (UID: 6F E2 1C 53, Balance: 17,400 KRW)

**SELECT Response (FCI):**
```
6F 31 B0 2F 03 10 01 0B 10 40 12 99 37 02 65 17
12 11 24 79 33 20 25 10 21 20 30 10 20 04 00 00
07 A1 20 00 00 00 00 00 00 00 00 00 00 00 00 00
00 00 02
```

**SFI 3 (Trip Detail, 52B x 10):**
```
#01: 01 32 01 00 3D 41 96 90 80 01 FF 34 71 91 40 80 00 07 00 2A 76 00 04 88 AF 00 1D 09 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 00 00
#02: 01 32 00 00 3D 41 01 31 30 01 FF 34 71 8A F3 00 00 07 00 00 00 00 04 88 AF 00 1D 09 04 01 00 00 00 00 00 A4 C0 00 00 00 04 88 00 00 00 00 04 88 40 30 00 00
#03: 01 32 00 00 3C 41 12 00 00 01 F4 34 71 64 1A 00 80 01 00 00 00 00 04 88 CE 27 1B 5B 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 02 58
#04: 01 32 01 00 3B 41 96 90 80 01 FF 34 70 93 39 80 00 07 00 2A 76 00 04 88 AF 00 1D 09 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 00 00
#05: 01 32 00 00 3B 41 01 31 30 01 FF 34 70 8C 37 00 00 07 00 00 00 00 04 88 AF 00 1D 09 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 00 00
#06: 01 32 01 00 3A 41 78 93 90 01 F4 34 70 67 42 00 00 07 00 20 9E 00 04 88 C2 E6 1D 16 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 05 C8 00 00 00 00
#07: 01 32 00 00 3A 41 96 90 70 01 F4 34 70 63 51 80 80 07 00 00 00 00 04 88 C2 E6 1D 16 04 01 00 00 00 00 00 94 C0 00 00 00 04 88 00 00 00 00 04 88 40 20 01 90
#08: 01 32 00 00 39 41 01 31 30 01 F4 34 6F 99 99 00 80 07 00 00 00 00 04 88 C2 E6 1D 16 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 01 90
#09: 01 32 01 00 38 41 01 31 00 01 FF 34 6E AB 2E 00 00 07 00 28 64 00 04 88 CE 05 1D 09 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 00 00
#10: 01 32 00 00 38 41 96 90 70 01 FF 34 6E A5 86 00 00 07 00 00 00 00 04 88 CE 05 1D 09 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 00 00
```

**SFI 4 (Financial, 26B x 10):**
```
#01: 01 18 00 00 43 F8 00 00 01 A2 00 00 00 00 49 13 01 00 05 04 57 68 00 01 21 A8
#02: 01 18 00 00 43 F8 00 00 01 A1 00 00 06 68 49 13 01 00 05 09 66 43 00 02 A1 51
#03: 01 18 00 00 4A 60 00 00 01 A0 00 00 00 00 49 13 01 00 05 22 37 42 00 02 D1 1E
#04: 01 18 00 00 4A 60 00 00 01 9F 00 00 04 88 49 13 01 00 05 22 32 59 00 05 11 38
#05: 01 18 00 00 4E E8 00 00 01 9E 00 00 00 00 49 13 01 00 05 04 57 68 00 01 21 45
#06: 01 18 00 00 4E E8 00 00 01 9D 00 00 04 88 49 13 01 00 05 09 66 43 00 02 A0 A7
#07: 02 18 00 00 53 70 00 00 01 9C 00 00 4E 20 00 00 09 00 09 00 00 00 04 73 A9 C4
#08: 01 18 00 00 05 50 00 00 01 9C 00 00 00 00 49 13 01 00 05 23 57 22 00 01 AF 89
#09: 01 18 00 00 05 50 00 00 01 9A 00 00 05 C8 49 13 01 00 04 95 71 47 00 02 C6 4F
#10: 01 18 00 00 0B 18 00 00 01 99 00 00 04 88 49 13 01 00 04 95 71 47 00 02 C5 E4
```

**SFI 5 (1 record, garbage):**
```
#01: 70 18 08 00 00 00 03 0B 00 00 09 00 09 00 00 00 00 01 01 00 00 00 04 00 00 00
```

### T-money Card (UID: AF 4C CA B7, Balance: 31,370 KRW)

**SELECT Response (FCI):**
```
6F 31 B0 2F 00 10 01 08 10 10 01 03 33 52 44 86
05 58 64 89 33 20 24 05 20 20 29 05 19 04 00 00
07 A1 20 5C 00 00 00 00 00 00 00 00 00 00 00 00
00 00 00
```

**90 4E Response (46B):**
```
02 2C 00 00 07 D0 00 00 00 04 00 00 07 D0 07 20 09 00 30 00 42 12 00 09 AD 62 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

**SFI 3 (Trip Detail, 52B x 10):**
```
#01: 01 32 01 00 03 41 96 90 80 01 F4 34 72 91 32 00 00 07 00 1F 4A 00 0C E4 D2 1E 1D 16 01 02 00 00 00 00 00 00 C0 00 00 00 0C E4 00 00 00 00 10 04 00 00 00 00
#02: 01 32 00 00 03 41 01 31 30 01 F4 34 72 8C 15 80 80 07 00 00 00 00 0C E4 D2 1E 1D 16 01 02 00 00 00 00 01 4A C0 00 00 00 0C E4 00 00 00 00 0C E4 00 00 01 90
#03: 01 32 01 00 02 41 78 93 90 01 F4 34 72 68 24 00 00 01 00 20 DA 00 04 88 C2 C2 1B 5B 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 06 68 00 00 00 00
#04: 01 32 00 00 02 41 12 00 00 01 F4 34 72 63 78 80 80 01 00 00 00 00 04 88 C2 C2 1B 5B 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 02 58
#05: 01 32 01 00 01 41 96 90 80 01 F4 34 71 91 F6 00 00 07 00 1F 4A 00 04 88 BE 45 1D 16 04 01 00 00 00 00 00 00 C0 00 00 00 04 88 00 00 00 00 05 C8 00 00 00 00
#06: 01 32 00 00 01 41 01 31 30 01 F4 34 71 8C 17 00 80 07 00 00 00 00 04 88 BE 45 1D 16 04 01 00 00 00 00 00 74 C0 00 00 00 04 88 00 00 00 00 04 88 00 00 01 90
#07: 01 32 01 02 63 41 01 31 00 01 F4 34 71 68 37 80 08 01 00 52 9E 00 07 44 CE 27 1B 5B 04 01 00 00 00 00 00 00 C0 00 00 00 07 44 00 00 00 00 11 80 00 00 00 00
#08: 01 32 00 02 63 41 12 00 50 01 F4 34 71 64 A2 00 08 01 00 35 FC 00 07 44 CE 27 1B 5B 04 01 00 00 00 00 00 00 C0 00 00 00 07 44 00 00 00 00 0F A0 00 00 00 00
#09: 01 32 01 01 63 00 00 84 40 00 CA 34 71 63 53 00 08 00 00 35 FC 00 07 44 00 00 00 15 04 01 00 00 00 00 00 00 C0 00 00 00 07 44 00 00 0A 73 0B 18 00 00 00 00
#10: 01 32 00 01 63 00 00 84 90 00 CA 34 71 5E 66 00 08 00 00 06 54 00 07 44 00 00 00 2B 04 01 00 00 00 00 00 00 C0 00 00 00 07 44 00 00 0A 72 0A C8 00 00 00 00
```

**SFI 4 (Financial, 46B x 10):**
```
#01: 01 2C 00 00 7A 8A 00 00 02 7C 00 00 00 00 49 13 01 00 05 23 76 64 00 00 AC FC 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#02: 01 2C 00 00 7A 8A 00 00 02 7B 00 00 0C E4 49 13 01 00 05 18 51 61 00 01 65 9B 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#03: 01 2C 00 00 87 6E 00 00 02 7A 00 00 00 00 49 13 01 00 05 23 52 91 00 02 3D 17 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#04: 01 2C 00 00 87 6E 00 00 02 79 00 00 04 88 49 13 01 00 04 95 34 07 00 04 EA 91 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#05: 01 2C 00 00 8B F6 00 00 02 78 00 00 00 00 49 13 01 00 05 09 26 74 00 00 EF C0 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#06: 01 2C 00 00 8B F6 00 00 02 77 00 00 04 88 49 13 01 00 05 25 59 60 00 02 2E B2 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#07: 01 2C 00 00 90 7E 00 00 02 76 00 00 00 00 49 13 01 00 05 12 29 46 00 02 66 AF 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#08: 01 2C 00 00 90 7E 00 00 02 75 00 00 00 00 49 13 01 00 05 22 32 59 00 05 11 3C 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#09: 01 2C 00 00 90 7E 00 00 02 74 00 00 00 00 07 20 09 00 20 31 76 93 00 0B 62 28 20 26 03 17 12 26 38 00 00 00 00 00 00 00 00 00 00 00 00 00
#10: 01 2C 00 00 90 7E 00 00 02 73 00 00 00 00 07 20 09 00 20 31 67 46 00 0E 53 C2 20 26 03 17 11 51 12 00 00 00 00 00 00 00 00 00 00 00 00 00
```

**SFI 5 (Top-up History, 46B x 5):**
```
#01: 02 2C 00 00 D6 92 00 00 02 4C 00 00 C3 50 07 20 09 00 30 02 34 60 00 01 C6 25 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#02: 02 2C 00 00 CB CA 00 00 02 02 00 00 C3 50 07 20 09 00 30 02 34 60 00 01 C3 BB 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#03: 02 2C 00 00 DA C0 00 00 01 9B 00 00 C3 50 07 20 09 00 30 02 34 60 00 01 C0 F9 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#04: 02 2C 00 00 54 D8 00 00 01 7D 00 00 4E 20 07 20 09 00 30 00 42 13 00 09 18 D6 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
#05: 02 2C 00 00 0B 2C 00 00 01 7A 00 00 07 D0 07 20 09 00 30 00 53 75 00 09 9E AE 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
```

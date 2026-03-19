# Korean Transit Card — Technical Analysis & Reverse Engineering Notes

> Internal documentation for K-Transit NFC card reader development.
> Contains reverse-engineered data formats, verified against real card data and cross-referenced with BucaCheck app output.

---

## 1. Card Overview

| Property | T-money | Cashbee |
|----------|---------|---------|
| **AID** | `D4100000030001` | `D4100000140001` |
| **Standard** | KS X 6924 | KS X 6924 |
| **Issuer Code** | `0x08` | `0x0B` |
| **SFI 3 Records** | 20 (52B each) | 20 (52B each) |
| **SFI 4 Records** | 20 (46B each) | 20 (26B each) |
| **SFI 5 Records** | 5 (46B, top-up) | 1 (garbage, filtered) |
| **SFI 6-10** | Not present | Not present |

---

## 2. APDU Commands

| Command | CLA INS P1 P2 | Le | Description |
|---------|---------------|-----|-------------|
| SELECT AID | `00 A4 04 00` | Lc=AID | Select transit application |
| GET BALANCE | `90 4C 00 00` | 04 | Returns 4-byte big-endian KRW balance |
| READ RECORD | `00 B2 [rec] [SFI*8+4]` | — | Read SFI record by index |
| GET RECORD | `90 78 [idx] 00` | 10 | KS X 6924 proprietary (16B, T-money only) |
| GET DATA | `90 4E 00 [idx]` | — | Proprietary 46B record (T-money only) |

---

## 3. PurseInfo (47 bytes, FCI tag B0)

```
Offset  Size  Field
[0]     1     cardType
[1]     1     algorithm
[2]     1     keyVersion
[3]     1     idCenter (issuer: 0x08=T-money, 0x0B=Cashbee)
[4-11]  8     CSN (Card Serial Number, hex)
[12-16] 5     idtr (authentication ID)
[17-20] 4     issueDate (BCD YYYYMMDD — manufacturing date, NOT purchase date)
[21-24] 4     expiryDate (BCD YYYYMMDD)
[26]    1     userCode (1=adult, 2=child, 3=senior, 4=teen, 5=disabled)
[27]    1     discount classification
[27-30] 4     maxBalance
[31-32] 2     branchCode
[33-36] 4     transactionLimit
[37]    1     mobileCarrier
[38]    1     financialInstitution
[39-46] 8     reserved
```

---

## 4. SFI 3 — Trip Detail Record (52 bytes)

### Format
```
Offset  Size  Field
[0-1]   2     Record type (always 01 32)
[2]     1     Event: 0x00=boarding(승차), 0x01=alighting(하차)
[3]     1     Transport: 0x00=bus, 0x01=metro, 0x02=train
[4]     1     Trip counter (same for boarding+alighting pair)
[5]     1     Terminal data
[6-8]   3     Terminal/device ID
[9]     1     Unknown (01)
[10]    1     Fee type (FF or F4)
[11-14] 4     ★ TIMESTAMP (packed format — see below)
[15-17] 3     Unknown
[18]    1     Unknown
[19-20] 2     ★ DISTANCE in meters (big-endian, alighting records only)
[22-23] 2     Base fare (big-endian KRW)
[24-27] 4     Terminal/station ID
[28]    1     Unknown (04)
[29]    1     Unknown (01)
[36]    1     Unknown (C0)
[40-41] 2     Base fare (duplicate)
[44-45] 2     Unknown fare value
[46-47] 2     Unknown
[50-51] 2     Distance surcharge (big-endian KRW, boarding records)
```

### Packed Timestamp Format (bytes [11-14])

**NOT seconds-from-epoch.** This is a bit-packed date-time:

```
31                16 15    11 10     5 4      0
┌──────────────────┬────────┬────────┬────────┐
│   Day Counter    │  Hour  │ Minute │ Sec/2  │
│   (16 bits)      │ (5 b)  │ (6 b)  │ (5 b)  │
└──────────────────┴────────┴────────┴────────┘

Day Epoch: 1989-06-14
Second resolution: 2 seconds (value * 2)
```

**Verification (6 data points, all confirmed against BucaCheck):**

| Raw Hex | Day | Time | Expected | Match |
|---------|-----|------|----------|-------|
| `34729132` | 13426→2026-03-18 | 18:09:36 | 18:09:36 | ✅ |
| `34728C15` | 13426→2026-03-18 | 17:32:42 | 17:32:43 | ✅ ±1s |
| `34726824` | 13426→2026-03-18 | 13:01:08 | 13:01:08 | ✅ |
| `34726378` | 13426→2026-03-18 | 12:27:48 | 12:27:49 | ✅ ±1s |
| `347191F6` | 13425→2026-03-17 | 18:15:44 | 18:15:44 | ✅ |
| `34718C17` | 13425→2026-03-17 | 17:32:46 | 17:32:46 | ✅ |

> ±1 second error is expected due to 2-second quantization (5-bit field).

### Distance Field (bytes [19-20])

Big-endian uint16, value in **meters**. Only meaningful on alighting records.

| Raw | Meters | km | BucaCheck | Match |
|-----|--------|----|-----------|-------|
| `1F4A` | 8010 | 8.01 | 8.01 | ✅ |
| `20DA` | 8410 | 8.41 | 8.41 | ✅ |
| `529E` | 21150 | 21.15 | 21.15 | ✅ |
| `2A76` | 10870 | 10.87 | 10.87 | ✅ |

---

## 5. SFI 4 — Financial Record

### Cashbee Format (26 bytes)
```
Offset  Size  Field
[0]     1     Type: 0x01=transit, 0x02=topUp
[1]     1     0x18
[2-3]   2     0x00 0x00
[4-5]   2     ★ Balance AFTER transaction (big-endian KRW)
[6-7]   2     0x00 0x00
[8-9]   2     Sequence counter (big-endian, decreasing=newer)
[10-11] 2     0x00 0x00
[12-13] 2     ★ Fare amount (big-endian KRW, 0=boarding entry)
[14-15] 2     Marker: 0x4913=transit, 0x0720=sub-charge, 0x0000=topup
[16-25] 10    Terminal data / MAC
```

### T-money Format (46 bytes)
```
Offset  Size  Field
[0]     1     Type: 0x01=transit, 0x02=topUp
[1]     1     0x2C
[2-5]   4     ★ Balance AFTER (big-endian uint32 KRW)
[6-7]   2     0x00 0x00
[8-9]   2     Sequence counter (big-endian)
[10-11] 2     0x00 0x00
[12-13] 2     ★ Fare amount (big-endian KRW)
[14-15] 2     Marker (see below)
[16-17] 2     Unknown
[18-25] 8     Terminal data
[26-32] 7     BCD datetime YYYYMMDDHHMMSS (only on 0x0720 records)
[33-45] 13    Zeros/padding
```

### Marker Types

| Marker | Meaning | Has BCD Date | Match SFI 3 |
|--------|---------|:------------:|:-----------:|
| `0x4913` | Standard transit charge | ❌ | ✅ Positional |
| `0x4923` | Transfer surcharge | ❌ | ❌ |
| `0x0720` | Sub-charge / card-read event | ✅ bytes[26-32] | ❌ |
| `0x0000` | Top-up | ❌ | ❌ |

### BCD DateTime (0x0720 records, bytes [26-32])

```
Byte:  [26] [27] [28] [29] [30] [31] [32]
BCD:   YY   YY   MM   DD   HH   MM   SS

Example: 20 26 03 17 12 26 38
Parsed:  2026-03-17 12:26:38 KST
```

> Note: BCD parsing requires nibble-level decode: `0x20` → `(2*10+0)=20`, `0x26` → `(2*10+6)=26` → year=2026

---

## 6. Data Merging Algorithm

### Problem
SFI 3 has timestamps but no balance. SFI 4 has balance but no timestamps. They represent the same events from different perspectives.

### Solution: Positional Matching

1. Extract **alighting records** from SFI 3 (byte[2]==0x01), ordered newest-first
2. Extract **charge records** from SFI 4 (fare>0, marker==0x4913), ordered newest-first
3. Match 1:1 by position — both are newest-first so Nth alighting = Nth charge
4. For `0x0720` records (fare>0): parse BCD date, don't match with SFI 3
5. For `0x49XX` (non-0x4913): treat as sub-charge, don't match with SFI 3
6. Remaining SFI 3 alightings (beyond SFI 4 range): estimate balance backward

### Sub-Charge Computation

For transfer trips, individual leg charges are computed from **consecutive SFI 3 fare differences**:

```
Leg 1 (board):  SFI3 fare = 900   → sub = 900
Leg 2 (alight): SFI3 fare = 980   → sub = 980 - 900 = 80
Leg 3 (board):  SFI3 fare = 1860  → sub = 1860 - 980 = 880
Leg 4 (alight): SFI3 fare = 1860  → sub = 1860 - 1860 = 0

Total: 900 + 80 + 880 + 0 = 1860 ✅
```

---

## 7. iOS Limitations

### Bank Cards (EMV)
iOS blocks third-party apps from communicating with **payment NFC chips** (Visa, Mastercard, etc.). Error: `NFCError Code=2 "Missing required entitlement"`.

This is Apple's security policy — affects ALL iOS NFC apps including NFSee, Metrodroid (iOS version). Only Apple Pay can access payment card NFC.

**Detection:** Check `NSError.domain == "NFCError" && code == 2` → show user-friendly message.

### Comparison with Metrodroid
| Feature | K-Transit | Metrodroid |
|---------|-----------|------------|
| Timestamp source | SFI 3 packed format (every trip) | SFI 4 BCD (only 0x0720 records) |
| Sub-charges | ✅ Computed from fare differences | ❌ Not available |
| Distance | ✅ SFI 3 bytes[19-20] | ❌ Not parsed |
| SFI record count | 20 per SFI | 10 per SFI |
| Bank card detection | ✅ Clear error message | ❌ Generic error |

---

## 8. References

1. [KS X 6924 Standard Paper](https://www.koreascience.or.kr/article/CFKO201202135240043.pdf) — Korean transit card specification
2. [Metrodroid Source](https://github.com/metrodroid/metrodroid) — `KSX6924Utils.kt`, `TMoneyTrip.kt`
3. [KoreaTransitCardBalanceChecker](https://github.com/happybono/KoreaTransitCardBalanceChecker) — Arduino NFC reader
4. [BlackHat Asia 2017](https://blackhat.com/docs/asia-17/materials/asia-17-Kim-Breaking-Korea-Transit-Card-With-Side-Channel-Attack-Unauthorized-Recharging.pdf) — Cashbee crypto analysis
5. [Apple CoreNFC Documentation](https://developer.apple.com/documentation/corenfc) — iOS NFC API
6. [NFSee](https://github.com/nfcim/nfsee) — iOS NFC app (confirms bank card limitation)

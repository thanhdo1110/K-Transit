import Foundation
import Combine
import CoreNFC

// MARK: - Models

enum KoreanCardType: String, Sendable {
    case tmoney = "T-money (티머니)"
    case cashbee = "Cashbee (캐시비)"
    case railplus = "Rail Plus (레일플러스)"
    case unknown = "알 수 없음"

    var displayName: String {
        String(localized: String.LocalizationValue(rawValue))
    }

    var icon: String {
        switch self {
        case .tmoney: return "bus.fill"
        case .cashbee: return "creditcard.fill"
        case .railplus: return "tram.fill"
        case .unknown: return "questionmark.circle.fill"
        }
    }
}

struct TransactionRecord: Identifiable, Sendable {
    let id = UUID()
    let amount: Int
    let balance: Int
    let date: Date?
    let type: TransactionType

    enum TransactionType: String, Sendable {
        case topUp = "충전"
        case payment = "결제"
        case transfer = "환승"
        case unknown = "기타"

        var displayName: String {
            String(localized: String.LocalizationValue(rawValue))
        }

        var icon: String {
            switch self {
            case .topUp: return "plus.circle.fill"
            case .payment: return "minus.circle.fill"
            case .transfer: return "arrow.triangle.swap"
            case .unknown: return "questionmark.circle"
            }
        }
    }
}

struct TransitCardInfo: Sendable {
    var cardType: KoreanCardType = .unknown
    var cardUID: String = ""
    var balance: Int = 0
    var cardNumber: String = ""
    var transactions: [TransactionRecord] = []
    var rawData: [(key: String, value: String)] = []
    var debugLog: [String] = []
    var tagType: String = ""

    mutating func dlog(_ msg: String) {
        print("[NFC-CTDO] \(msg)")
        debugLog.append(msg)
    }
}

// MARK: - NFC Card Reader

class NFCCardReader: NSObject, ObservableObject {
    @Published var cardInfo: TransitCardInfo?
    @Published var isScanning = false
    @Published var errorMessage: String?
    @Published var statusMessage: String = ""

    private var session: NFCTagReaderSession?

    // Issuer codes from KS X 6924 purseInfo.idCenter
    private static let issuerMap: [UInt8: KoreanCardType] = [
        0x01: .tmoney,   // KFTC
        0x02: .tmoney,   // A-Cash
        0x08: .tmoney,   // T-Money
        0x09: .railplus, // Korail
        0x0B: .cashbee,  // EB Card / Cashbee
    ]

    private static let cardAIDs: [(aid: Data, type: KoreanCardType)] = [
        // T-money (KS X 6924)
        (Data([0xD4, 0x10, 0x00, 0x00, 0x03, 0x00, 0x01]), .tmoney),
        // Cashbee / EB Card
        (Data([0xD4, 0x10, 0x00, 0x00, 0x14, 0x00, 0x01]), .cashbee),
        // MOIBA
        (Data([0xD4, 0x10, 0x00, 0x00, 0x30, 0x00, 0x01]), .unknown),
        // K-Cash
        (Data([0xD4, 0x10, 0x65, 0x09, 0x90, 0x00, 0x20]), .unknown),
        // Legacy variants
        (Data([0xD4, 0x10, 0x00, 0x00, 0x03, 0x00, 0x02]), .cashbee),
        (Data([0xD4, 0x10, 0x00, 0x00, 0x03, 0x00, 0x03]), .railplus),
        (Data([0xD4, 0x10, 0x00, 0x00, 0x02, 0x00, 0x01]), .tmoney),
    ]

    private func log(_ msg: String) {
        print("[NFC-CTDO] \(msg)")
    }

    func startScan() {
        guard NFCTagReaderSession.readingAvailable else {
            errorMessage = String(localized: "이 기기는 NFC를 지원하지 않습니다")
            log("❌ NFC not available on this device")
            return
        }

        // Prevent double-tap: invalidate existing session first
        if let existing = session {
            log("⚠️ Invalidating previous session")
            existing.invalidate()
            session = nil
        }
        guard !isScanning else {
            log("⚠️ Already scanning, ignoring")
            return
        }

        // Check entitlements
        log("========================================")
        log("NFC SCAN START")
        log("NFCTagReaderSession.readingAvailable = true")
        if let entitlements = Bundle.main.infoDictionary {
            log("Info.plist keys: \(entitlements.keys.sorted())")
            if let aids = entitlements["com.apple.developer.nfc.readersession.iso7816.select-identifiers"] as? [String] {
                log("ISO7816 AIDs in Info.plist: \(aids)")
            } else {
                log("⚠️ No ISO7816 select-identifiers in Info.plist")
            }
        }
        if let entFile = Bundle.main.path(forResource: "embedded", ofType: "mobileprovision") {
            log("Provisioning profile: exists at \(entFile)")
        } else {
            log("⚠️ No embedded.mobileprovision found (debug build?)")
        }
        log("========================================")

        cardInfo = nil
        errorMessage = nil
        statusMessage = String(localized: "카드를 가까이 대주세요...")
        isScanning = true

        session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: .main
        )
        log("Session created: \(session != nil ? "OK" : "NIL")")
        session?.alertMessage = String(localized: "교통카드를 iPhone 뒷면에 가까이 대주세요")
        session?.begin()
        log("Session begun")
    }

    // MARK: - Helpers

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined(separator: " ")
    }

    private static func hexCompact(_ data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }

    nonisolated private static func tagTypeName(_ tag: NFCTag) -> String {
        switch tag {
        case .iso7816: return ".iso7816"
        case .miFare: return ".miFare"
        case .feliCa: return ".feliCa"
        case .iso15693: return ".iso15693"
        @unknown default: return ".unknown"
        }
    }

    // MARK: - APDU

    private func sendAPDU(
        tag: NFCISO7816Tag,
        cla: UInt8, ins: UInt8, p1: UInt8, p2: UInt8,
        data: Data = Data(), le: Int = 256
    ) async throws -> (Data, UInt8, UInt8) {
        let apdu = NFCISO7816APDU(
            instructionClass: cla, instructionCode: ins,
            p1Parameter: p1, p2Parameter: p2,
            data: data, expectedResponseLength: le
        )
        let (respData, sw1, sw2) = try await tag.sendCommand(apdu: apdu)

        // Handle SW 6CXX: wrong Le, retry with correct Le = sw2
        if sw1 == 0x6C {
            print("[NFC-CTDO] [APDU] Got 6C\(String(format: "%02X", sw2)) → retry with Le=\(sw2)")
            let retry = NFCISO7816APDU(
                instructionClass: cla, instructionCode: ins,
                p1Parameter: p1, p2Parameter: p2,
                data: data, expectedResponseLength: Int(sw2)
            )
            return try await tag.sendCommand(apdu: retry)
        }

        // Handle SW 61XX: more data available, send GET RESPONSE
        if sw1 == 0x61 {
            print("[NFC-CTDO] [APDU] Got 61\(String(format: "%02X", sw2)) → GET RESPONSE Le=\(sw2)")
            let getResp = NFCISO7816APDU(
                instructionClass: 0x00, instructionCode: 0xC0,
                p1Parameter: 0x00, p2Parameter: 0x00,
                data: Data(), expectedResponseLength: Int(sw2)
            )
            let (moreData, sw1b, sw2b) = try await tag.sendCommand(apdu: getResp)
            return (respData + moreData, sw1b, sw2b)
        }

        return (respData, sw1, sw2)
    }

    // MARK: - Tag Processing

    private func processISO7816Tag(_ tag: NFCISO7816Tag, session: NFCTagReaderSession) async {
        var info = TransitCardInfo()
        info.tagType = "ISO 7816"

        // --- Basic tag info ---
        let uid = tag.identifier
        info.cardUID = Self.hexCompact(uid)
        info.rawData.append(("UID", Self.hex(uid)))
        info.rawData.append(("UID (hex compact)", Self.hexCompact(uid)))
        info.dlog("[TAG] Type: ISO 7816")
        info.dlog("[TAG] UID: \(Self.hex(uid))")

        if let hist = tag.historicalBytes {
            info.rawData.append(("Historical Bytes", Self.hex(hist)))
            info.dlog("[TAG] Historical Bytes (\(hist.count)B): \(Self.hex(hist))")
        } else {
            info.dlog("[TAG] Historical Bytes: nil")
        }

        if let appData = tag.applicationData {
            info.rawData.append(("Application Data", Self.hex(appData)))
            info.dlog("[TAG] Application Data (\(appData.count)B): \(Self.hex(appData))")
        } else {
            info.dlog("[TAG] Application Data: nil")
        }

        let initialAID = tag.initialSelectedAID
        if !initialAID.isEmpty {
            info.rawData.append(("Initial Selected AID", initialAID))
            info.dlog("[TAG] Initial Selected AID: \(initialAID)")
        }

        // --- Try each Korean transit card AID ---
        info.dlog("")
        info.dlog("[SELECT] Trying Korean transit AIDs...")

        for (aid, cardType) in Self.cardAIDs {
            let aidHex = Self.hexCompact(aid)
            info.dlog("[SELECT] AID: \(aidHex) (\(cardType.rawValue))")

            do {
                let (data, sw1, sw2) = try await sendAPDU(
                    tag: tag, cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: aid
                )
                let swHex = String(format: "%02X%02X", sw1, sw2)
                info.dlog("[SELECT] Response SW: \(swHex), Data (\(data.count)B): \(Self.hex(data))")
                info.rawData.append(("SELECT \(aidHex) → SW", swHex))
                if !data.isEmpty {
                    info.rawData.append(("SELECT \(aidHex) → Data", Self.hex(data)))
                }

                guard sw1 == 0x90 && sw2 == 0x00 else {
                    info.dlog("[SELECT] ❌ Failed (SW≠9000)")
                    continue
                }

                info.dlog("[SELECT] ✅ AID matched: \(cardType.rawValue)")

                // Parse FCI - find B0 tag (purseInfo, 47 bytes)
                // FCI format: 6F [len] B0 [len] [purseInfo...]
                var purseData: Data?
                if data.count > 4 {
                    // Search for B0 tag in FCI
                    for idx in 0..<(data.count - 2) {
                        if data[idx] == 0xB0 {
                            let pLen = Int(data[idx + 1])
                            let start = idx + 2
                            if start + pLen <= data.count {
                                purseData = data[start..<(start + pLen)]
                                info.dlog("[FCI] Found B0 tag at \(idx), len=\(pLen)")
                                break
                            }
                        }
                    }
                }

                if let pd = purseData, pd.count >= 25 {
                    let base = pd.startIndex
                    // [3] idCenter (issuer)
                    let issuer = pd[base + 3]
                    let resolvedType = Self.issuerMap[issuer] ?? cardType
                    info.cardType = resolvedType
                    info.rawData.append(("Issuer (idCenter)", String(format: "%02X (%d)", issuer, issuer)))
                    info.dlog("[PURSE] Issuer: \(issuer) → \(resolvedType.rawValue)")

                    // [4-11] CSN (Card Serial Number, 8 bytes)
                    if pd.count >= base + 12 {
                        let csn = Self.hexCompact(pd[(base+4)...(base+11)])
                        info.cardNumber = csn
                        info.rawData.append(("Card Serial (CSN)", csn))
                        info.dlog("[PURSE] CSN: \(csn)")
                    }

                    // [17-20] Issue date (BCD YYYYMMDD)
                    if pd.count >= base + 21 {
                        let issueHex = Self.hexCompact(pd[(base+17)...(base+20)])
                        info.rawData.append(("Issue Date", issueHex))
                        info.dlog("[PURSE] Issue Date: \(issueHex)")
                    }

                    // [21-24] Expiry date (BCD YYYYMMDD)
                    if pd.count >= base + 25 {
                        let expHex = Self.hexCompact(pd[(base+21)...(base+24)])
                        info.rawData.append(("Expiry Date", expHex))
                        info.dlog("[PURSE] Expiry: \(expHex)")
                    }

                    // [0] cardType, [1] alg, [2] vk, [26] userCode
                    info.rawData.append(("Card Type", String(format: "%02X", pd[base])))
                    info.rawData.append(("Algorithm", String(format: "%02X", pd[base + 1])))
                    if pd.count >= base + 27 {
                        let userCode = pd[base + 26]
                        let userType: String
                        switch userCode {
                        case 1: userType = String(localized: "일반 (Adult)")
                        case 2: userType = String(localized: "어린이 (Child)")
                        case 3: userType = String(localized: "경로 (Senior)")
                        case 4: userType = String(localized: "청소년 (Teen)")
                        case 5: userType = String(localized: "장애인 (Disabled)")
                        default: userType = String(localized: "기타 (\(userCode))")
                        }
                        info.rawData.append(("User Type", userType))
                        info.dlog("[PURSE] User: \(userType)")
                    }
                } else {
                    // No B0 tag found, use raw parsing
                    info.cardType = cardType == .unknown ? .tmoney : cardType
                    info.dlog("[FCI] No B0 tag, raw parse")
                    if data.count >= 12 {
                        info.cardNumber = Self.hexCompact(data[4..<12])
                        info.rawData.append(("Card ID (raw)", Self.hexCompact(data[4..<12])))
                    }
                }

                // --- Read Balance ---
                info.dlog("")
                info.dlog("[BALANCE] Sending 90 4C 00 00 (Le=04)...")
                do {
                    let (balData, bsw1, bsw2) = try await sendAPDU(
                        tag: tag, cla: 0x90, ins: 0x4C, p1: 0x00, p2: 0x00, le: 4
                    )
                    let bswHex = String(format: "%02X%02X", bsw1, bsw2)
                    info.dlog("[BALANCE] SW: \(bswHex), Data (\(balData.count)B): \(Self.hex(balData))")
                    info.rawData.append(("Balance → SW", bswHex))
                    info.rawData.append(("Balance → Raw Data", Self.hex(balData)))

                    if bsw1 == 0x90 && bsw2 == 0x00 && balData.count >= 4 {
                        let bal = Int(balData[0]) << 24 | Int(balData[1]) << 16 | Int(balData[2]) << 8 | Int(balData[3])
                        info.balance = bal
                        info.dlog("[BALANCE] ✅ \(bal) KRW")
                    } else {
                        info.dlog("[BALANCE] ❌ Failed or unexpected response")
                    }
                } catch {
                    info.dlog("[BALANCE] ❌ Error: \(error.localizedDescription)")
                }

                // --- Read Transaction History ---
                info.dlog("")
                info.dlog("[TX] === Reading transaction history ===")

                // Method 1: 90 78 (KS X 6924 GET RECORD, 16B each, max 16)
                info.dlog("[TX] Method 1: 90 78 XX 00 10")
                var method1Supported = false
                for i: UInt8 in 0x00...0x0F {
                    do {
                        let (txData, tsw1, tsw2) = try await sendAPDU(
                            tag: tag, cla: 0x90, ins: 0x78, p1: i, p2: 0x00, le: 16
                        )
                        let tswHex = String(format: "%02X%02X", tsw1, tsw2)
                        guard tsw1 == 0x90 && tsw2 == 0x00 else {
                            info.dlog("[TX] 78#\(i) → SW:\(tswHex) (stopped)")
                            break
                        }
                        method1Supported = true
                        if txData.count >= 10, !txData.allSatisfy({ $0 == 0 }) {
                            info.dlog("[TX] 78#\(i) → (\(txData.count)B): \(Self.hex(txData))")
                            info.rawData.append(("TX 78#\(i)", Self.hex(txData)))
                            info.transactions.append(Self.parseTransaction(data: txData))
                        }
                    } catch { break }
                }
                if method1Supported {
                    info.dlog("[TX] 90 78: \(info.transactions.count) valid records")
                }

                // Method 2: 90 4E (proprietary GET DATA, 46B) - store separately
                var fallback4E: [TransactionRecord] = []
                if info.transactions.isEmpty {
                    info.dlog("[TX] Method 2: 90 4E (P1=00, P2=0..9)")
                    for i: UInt8 in 0...9 {
                        do {
                            let (txData, tsw1, tsw2) = try await sendAPDU(
                                tag: tag, cla: 0x90, ins: 0x4E, p1: 0x00, p2: i
                            )
                            let tswHex = String(format: "%02X%02X", tsw1, tsw2)
                            guard tsw1 == 0x90 && tsw2 == 0x00 && txData.count >= 10 else {
                                if tsw1 != 0x6C {
                                    info.dlog("[TX] 4E#\(i) → SW:\(tswHex) (stopped)")
                                    break
                                }
                                continue
                            }
                            if !txData.allSatisfy({ $0 == 0 }) {
                                info.dlog("[TX] 4E#\(i) → (\(txData.count)B): \(Self.hex(txData))")
                                info.rawData.append(("TX 4E#\(i)", Self.hex(txData)))
                                fallback4E.append(Self.parseTransaction(data: txData))
                            }
                        } catch { break }
                    }
                }

                // Method 3: READ RECORD on SFI 3-5 (always try - SFI may have more records)
                do {
                    info.dlog("[TX] Method 3: READ RECORD (00 B2) on SFIs")
                    let sfiValues: [(sfi: UInt8, p2: UInt8)] = [
                        (3, 0x1C), (4, 0x24), (5, 0x2C), (6, 0x34)
                    ]
                    for (sfi, p2) in sfiValues {
                        for i: UInt8 in 1...10 {
                            do {
                                let (txData, tsw1, tsw2) = try await sendAPDU(
                                    tag: tag, cla: 0x00, ins: 0xB2, p1: i, p2: p2
                                )
                                let tswHex = String(format: "%02X%02X", tsw1, tsw2)
                                guard tsw1 == 0x90 && tsw2 == 0x00 else {
                                    info.dlog("[TX] SFI\(sfi)#\(i) → SW:\(tswHex)")
                                    break
                                }
                                if txData.count >= 10, !txData.allSatisfy({ $0 == 0 }) {
                                    info.dlog("[TX] SFI\(sfi)#\(i) → (\(txData.count)B): \(Self.hex(txData))")
                                    info.rawData.append(("TX SFI\(sfi)#\(i)", Self.hex(txData)))
                                    info.transactions.append(Self.parseTransaction(data: txData))
                                }
                            } catch { break }
                        }
                    }
                } // end Method 3

                // Method 4: SELECT EF by file ID + READ BINARY
                if info.transactions.isEmpty {
                    info.dlog("[TX] Method 4: SELECT EF + READ BINARY")
                    let fileIDs: [Data] = [
                        Data([0x00, 0x04]), Data([0x00, 0x05]),
                        Data([0xDF, 0x00]), Data([0x00, 0x03]),
                    ]
                    for fid in fileIDs {
                        let fidHex = Self.hexCompact(fid)
                        do {
                            // SELECT EF by file ID (P1=02)
                            let (_, ssw1, ssw2) = try await sendAPDU(
                                tag: tag, cla: 0x00, ins: 0xA4, p1: 0x02, p2: 0x00, data: fid
                            )
                            guard ssw1 == 0x90 && ssw2 == 0x00 else {
                                info.dlog("[TX] SELECT EF \(fidHex) → SW:\(String(format: "%02X%02X", ssw1, ssw2))")
                                continue
                            }
                            // READ BINARY
                            let (rbData, rsw1, rsw2) = try await sendAPDU(
                                tag: tag, cla: 0x00, ins: 0xB0, p1: 0x00, p2: 0x00
                            )
                            let rswHex = String(format: "%02X%02X", rsw1, rsw2)
                            info.dlog("[TX] EF \(fidHex) READ → SW:\(rswHex) (\(rbData.count)B): \(Self.hex(rbData))")
                            if rsw1 == 0x90 && rsw2 == 0x00 && rbData.count >= 10 {
                                info.rawData.append(("EF \(fidHex)", Self.hex(rbData)))
                            }
                        } catch {
                            info.dlog("[TX] EF \(fidHex) error: \(error.localizedDescription)")
                        }
                    }
                    // Re-SELECT the transit AID since we changed the current DF
                    _ = try? await sendAPDU(tag: tag, cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: aid)
                }

                // Post-process:
                // SFI 3 (52B) = trip detail (dates, no balance)
                // SFI 4/5 (26B/46B) = financial (real balance, maybe dates)
                // They overlap! Prefer records with real balance.
                // Separate: SFI records (balance>0 from SFI4, or date from SFI3) vs 90 4E
                let sfiRecords = info.transactions.filter { $0.balance > 0 || ($0.date != nil && $0.balance == 0) }
                let hasSFIBalance = sfiRecords.contains { $0.balance > 0 }

                // If SFI has balance data, use ONLY SFI records (skip 90 4E duplicates)
                let withBalance: [TransactionRecord]
                let withDatesOnly: [TransactionRecord]
                if hasSFIBalance {
                    // SFI has balance data - use only SFI records
                    withBalance = info.transactions.filter { $0.balance > 0 }
                    withDatesOnly = []
                } else if !sfiRecords.isEmpty {
                    // SFI has dates but no balance - use with running calc
                    withBalance = []
                    withDatesOnly = sfiRecords.filter { $0.date != nil }
                } else {
                    // No SFI data at all - use 90 4E fallback
                    withBalance = fallback4E.filter { $0.balance > 0 }
                    withDatesOnly = fallback4E.filter { $0.date != nil && $0.balance == 0 }
                }

                if !withBalance.isEmpty {
                    // Use SFI 4/5 records (real balance from card)
                    info.transactions = withBalance
                    info.dlog("[TX] Using \(withBalance.count) records with real balance (SFI 4/5)")
                } else if !withDatesOnly.isEmpty {
                    // Fallback: SFI 3 records with running balance
                    info.transactions = withDatesOnly
                    var runBal = info.balance
                    var filled: [TransactionRecord] = []
                    for tx in info.transactions {
                        filled.append(TransactionRecord(amount: tx.amount, balance: runBal, date: tx.date, type: tx.type))
                        if tx.type == .topUp { runBal -= tx.amount }
                        else if tx.amount > 0 { runBal += tx.amount }
                    }
                    info.transactions = filled
                    info.dlog("[TX] Using \(filled.count) records with running balance (SFI 3)")
                }

                // Filter: remove fare=0 entries (boarding taps with no charge)
                info.transactions = info.transactions.filter { $0.amount > 0 }
                // Don't sort - records from card are already newest-first
                // SFI 4 = recent trips, SFI 5 = older top-ups

                // Print full summary to console
                print("[NFC-CTDO] ")
                print("[NFC-CTDO] ╔══════════════════════════════════════╗")
                print("[NFC-CTDO] ║        CARD READ SUMMARY            ║")
                print("[NFC-CTDO] ╠══════════════════════════════════════╣")
                print("[NFC-CTDO] ║ Card: \(info.cardType.rawValue)")
                print("[NFC-CTDO] ║ CSN:  \(info.cardNumber)")
                print("[NFC-CTDO] ║ UID:  \(info.cardUID)")
                print("[NFC-CTDO] ║ Balance: \(info.balance) KRW")
                print("[NFC-CTDO] ╠══════════════════════════════════════╣")
                print("[NFC-CTDO] ║ TRIPS: \(info.transactions.count) records")
                print("[NFC-CTDO] ╠══════════════════════════════════════╣")

                let df = DateFormatter()
                df.dateFormat = "yyyy-MM-dd HH:mm"
                df.timeZone = TimeZone(identifier: "Asia/Seoul")

                for (i, tx) in info.transactions.enumerated() {
                    let typeStr: String
                    let sign: String
                    switch tx.type {
                    case .topUp:    typeStr = "충전 (Top-up)  "; sign = "+"
                    case .payment:  typeStr = "승차 (Board)   "; sign = "-"
                    case .transfer: typeStr = "하차 (Alight)  "; sign = "-"
                    case .unknown:  typeStr = "기타 (Other)   "; sign = "-"
                    }
                    let dateStr = tx.date != nil ? df.string(from: tx.date!) : "날짜 없음"
                    let amountStr = "\(sign)\(tx.amount)₩"
                    let balStr = "잔액 \(tx.balance)₩"
                    print("[NFC-CTDO] ║ #\(String(format: "%02d", i+1)) \(typeStr) \(amountStr.padding(toLength: 10, withPad: " ", startingAt: 0)) \(balStr.padding(toLength: 14, withPad: " ", startingAt: 0)) \(dateStr)")
                }

                print("[NFC-CTDO] ╚══════════════════════════════════════╝")

                // FULL RAW HEX DUMP
                print("[NFC-CTDO] ")
                print("[NFC-CTDO] ═══════════════ FULL RAW HEX DUMP ═══════════════")
                print("[NFC-CTDO] ")
                for (i, item) in info.rawData.enumerated() {
                    print("[NFC-CTDO] [\(String(format: "%02d", i))] \(item.key)")
                    print("[NFC-CTDO]     \(item.value)")
                }
                print("[NFC-CTDO] ")
                print("[NFC-CTDO] ═══════════════ END RAW HEX DUMP ════════════════")
                print("[NFC-CTDO] ")
                info.dlog("[TX] Final: \(info.transactions.count) records")
                break // Found a working AID, stop trying others

            } catch {
                info.dlog("[SELECT] ❌ Error: \(error.localizedDescription)")
                continue
            }
        }

        cardInfo = info
        isScanning = false
        statusMessage = info.cardType == .unknown
            ? String(localized: "카드를 읽었지만 인식할 수 없는 카드입니다")
            : String(localized: "\(info.cardType.displayName) 읽기 완료!")

        session.alertMessage = String(localized: "카드 읽기 완료!")
        session.invalidate()
    }

    private func processMiFareTag(_ tag: NFCMiFareTag, session: NFCTagReaderSession) {
        var info = TransitCardInfo()
        info.cardUID = Self.hexCompact(tag.identifier)

        let familyName: String
        switch tag.mifareFamily {
        case .desfire: familyName = "DESFire"
        case .plus: familyName = "Plus"
        case .ultralight: familyName = "Ultralight"
        default: familyName = "Unknown (\(tag.mifareFamily.rawValue))"
        }
        info.tagType = "MIFARE \(familyName)"
        info.rawData.append(("UID", Self.hex(tag.identifier)))
        info.rawData.append(("MIFARE Family", familyName))
        info.dlog("[TAG] Type: MIFARE \(familyName)")
        info.dlog("[TAG] UID: \(Self.hex(tag.identifier))")

        if let hist = tag.historicalBytes {
            info.rawData.append(("Historical Bytes", Self.hex(hist)))
            info.dlog("[TAG] Historical Bytes: \(Self.hex(hist))")
        }

        cardInfo = info
        isScanning = false
        statusMessage = String(localized: "MIFARE \(familyName) 카드")

        session.alertMessage = String(localized: "카드 읽기 완료!")
        session.invalidate()
    }

    // Korean transit epoch: 1998-01-01 00:00:00 KST
    private static let koreanTransitEpoch: Date = {
        var c = DateComponents()
        c.year = 1998; c.month = 1; c.day = 1
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Asia/Seoul")
        return Calendar.current.date(from: c)!
    }()

    private static let epoch2000: Date = {
        var c = DateComponents()
        c.year = 2000; c.month = 1; c.day = 1
        c.timeZone = TimeZone(identifier: "Asia/Seoul")
        return Calendar.current.date(from: c)!
    }()

    private static func parseTransaction(data: Data) -> TransactionRecord {
        if data.count >= 50 {
            return parseSFI3Record(data: data)     // 52B boarding/alighting detail
        } else if data.count >= 30 {
            return parseTmoneyLongRecord(data: data) // 46B from 90 4E
        } else if data.count >= 20 {
            return parseSFI4Record(data: data)     // 26B finance record
        } else {
            return parseTmoneyShortRecord(data: data) // 16B from 90 78
        }
    }

    // SFI 3: 52-byte boarding/alighting detail record (KS X 6924)
    // [0-1]   record type (01 32)
    // [2]     0x00=boarding (승차), 0x01=alighting (하차)
    // [3]     transport: 0x00=bus, 0x01=metro, 0x02=train
    // [4-5]   counter
    // [11-14] timestamp (seconds from 1998-01-01 KST)
    // [22-23] base fare (big-endian KRW)
    // [24-27] terminal/station ID
    // [50-51] distance surcharge
    private static func parseSFI3Record(data: Data) -> TransactionRecord {
        let boarding = data.count > 2 ? data[2] == 0x00 : true
        let txType: TransactionRecord.TransactionType = boarding ? .payment : .transfer
        // byte[3] = transport type (for future use in display)

        // Timestamp: bytes 11-14
        var date: Date?
        if data.count >= 15 {
            let secs = UInt32(data[11]) << 24 | UInt32(data[12]) << 16 | UInt32(data[13]) << 8 | UInt32(data[14])
            if secs > 0 {
                let candidate = koreanTransitEpoch.addingTimeInterval(Double(secs))
                let year = Calendar.current.component(.year, from: candidate)
                if year >= 2010 && year <= 2035 {
                    date = candidate
                }
            }
        }

        // Fare: bytes 22-23
        let fare = data.count >= 24
            ? Int(data[22]) << 8 | Int(data[23])
            : 0

        // Distance surcharge: bytes 50-51
        let surcharge = data.count >= 52
            ? Int(data[50]) << 8 | Int(data[51])
            : 0

        let totalFare = fare + surcharge

        // Balance: not directly available in Cashbee record, use 0
        let balance = 0

        print("[NFC-CTDO] [PARSE] Cashbee: \(boarding ? "boarding" : "alighting") fare=\(fare) surcharge=\(surcharge) date=\(date?.description ?? "nil")")

        return TransactionRecord(amount: totalFare, balance: balance, date: date, type: txType)
    }

    // SFI 4: 26-byte finance record
    // [0]     type: 01=transit, 02=topUp
    // [4-5]   balance after transaction (big-endian, REAL value)
    // [8-9]   sequence counter
    // [12-13] fare/amount (0=boarding entry, >0=fare charged or topup amount)
    private static func parseSFI4Record(data: Data) -> TransactionRecord {
        let typeByte = data[0]
        let txType: TransactionRecord.TransactionType
        switch typeByte {
        case 0x02: txType = .topUp
        default: txType = .payment
        }

        let balance = data.count >= 6
            ? Int(data[4]) << 8 | Int(data[5])
            : 0

        let fare = data.count >= 14
            ? Int(data[12]) << 8 | Int(data[13])
            : 0

        // Skip entry records with 0 fare (boarding tap, no charge yet)
        // They'll be shown via SFI 3 detail records instead
        if fare == 0 && txType != .topUp {
            // Return with amount=0, will be filtered
        }

        print("[NFC-CTDO] [PARSE] SFI4: type=\(typeByte) bal=\(balance) fare=\(fare)")
        return TransactionRecord(amount: fare, balance: balance, date: nil, type: txType)
    }

    // T-money 30-46 byte record from 90 4E or SFI 4/5:
    // [0]     type: 01=transit, 02=topUp
    // [2-5]   balance after (big-endian)
    // [6-9]   counter
    // [10-13] cost (big-endian)
    // [14-15] if 0x0720 → bytes 18-21 = timestamp (secs from 2000-01-01)
    //         if 0x4913 → no timestamp (SFI 4 financial record)
    private static func parseTmoneyLongRecord(data: Data) -> TransactionRecord {
        let typeByte = data[0]
        let txType: TransactionRecord.TransactionType
        switch typeByte {
        case 0x02: txType = .topUp
        case 0x04, 0x05: txType = .transfer
        default: txType = .payment
        }

        let balance = data.count >= 6
            ? Int(data[2]) << 24 | Int(data[3]) << 16 | Int(data[4]) << 8 | Int(data[5])
            : 0

        let cost = data.count >= 14
            ? Int(data[10]) << 24 | Int(data[11]) << 16 | Int(data[12]) << 8 | Int(data[13])
            : 0

        // Only parse date if bytes 14-15 = 07 20 (90 4E / SFI 5 format)
        // Bytes 14-15 = 49 13 means SFI 4 financial record (no timestamp)
        var date: Date?
        if data.count >= 22 && data[14] == 0x07 && data[15] == 0x20 {
            let secs = UInt32(data[18]) << 24 | UInt32(data[19]) << 16 | UInt32(data[20]) << 8 | UInt32(data[21])
            if secs > 0 {
                let candidate = epoch2000.addingTimeInterval(Double(secs))
                let year = Calendar.current.component(.year, from: candidate)
                if year >= 2020 && year <= 2030 {
                    date = candidate
                }
            }
        }

        print("[NFC-CTDO] [PARSE] T-money long: type=\(typeByte) cost=\(cost) bal=\(balance) date=\(date?.description ?? "nil")")
        return TransactionRecord(amount: cost, balance: balance, date: date, type: txType)
    }

    // T-money 16-byte record from 90 78:
    // [0]     type
    // [2-5]   balance
    // [10-13] cost
    private static func parseTmoneyShortRecord(data: Data) -> TransactionRecord {
        let typeByte = data.count > 0 ? data[0] : 0xFF
        let txType: TransactionRecord.TransactionType
        switch typeByte {
        case 0x02: txType = .topUp
        case 0x04, 0x05: txType = .transfer
        default: txType = .payment
        }

        let balance = data.count >= 6
            ? Int(data[2]) << 24 | Int(data[3]) << 16 | Int(data[4]) << 8 | Int(data[5])
            : 0

        let cost = data.count >= 14
            ? Int(data[10]) << 24 | Int(data[11]) << 16 | Int(data[12]) << 8 | Int(data[13])
            : 0

        return TransactionRecord(amount: cost, balance: balance, date: nil, type: txType)
    }
}

// MARK: - NFCTagReaderSessionDelegate

extension NFCCardReader: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {
        print("[NFC-CTDO] ✅ Session active - ready to scan")
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        print("[NFC-CTDO] Session invalidated: \(error.localizedDescription)")
        print("[NFC-CTDO] Error domain: \((error as NSError).domain) code: \((error as NSError).code)")
        Task { @MainActor in
            if let nfcError = error as? NFCReaderError,
               nfcError.code != .readerSessionInvalidationErrorUserCanceled,
               nfcError.code != .readerSessionInvalidationErrorFirstNDEFTagRead {
                self.errorMessage = String(localized: "NFC 오류: \(error.localizedDescription)")
            }
            self.isScanning = false
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        var debugLines: [String] = []

        func dlog(_ msg: String) {
            print("[NFC-CTDO] \(msg)")
            debugLines.append(msg)
        }

        dlog("=== TAG DETECTED ===")
        dlog("[DETECT] Found \(tags.count) tag(s):")
        for (i, t) in tags.enumerated() {
            let name = Self.tagTypeName(t)
            dlog("[DETECT]   [\(i)] \(name)")
        }

        // Pick best tag: .iso7816 first, then .miFare
        let bestTag: NFCTag
        if let iso = tags.first(where: { if case .iso7816 = $0 { return true } else { return false } }) {
            bestTag = iso
            dlog("[PICK] → .iso7816")
        } else if let mifare = tags.first(where: { if case .miFare = $0 { return true } else { return false } }) {
            bestTag = mifare
            dlog("[PICK] → .miFare (no .iso7816)")
        } else {
            bestTag = tags[0]
            dlog("[PICK] → \(Self.tagTypeName(tags[0])) (fallback)")
        }

        Task { @MainActor in
            // Connect
            dlog("[CONNECT] Connecting to \(Self.tagTypeName(bestTag))...")
            do {
                try await session.connect(to: bestTag)
                dlog("[CONNECT] ✅ Success!")
            } catch {
                let nsErr = error as NSError
                dlog("[CONNECT] ❌ FAILED")
                dlog("[CONNECT] Error: \(error.localizedDescription)")
                dlog("[CONNECT] Domain: \(nsErr.domain) Code: \(nsErr.code)")
                dlog("[CONNECT] UserInfo: \(nsErr.userInfo)")
                var info = TransitCardInfo()
                info.debugLog = debugLines
                self.cardInfo = info
                self.errorMessage = String(localized: "카드 연결 실패: \(error.localizedDescription)")
                self.isScanning = false
                session.invalidate(errorMessage: String(localized: "연결 실패: \(error.localizedDescription)"))
                return
            }

            // Process tag
            switch bestTag {
            case .iso7816(let isoTag):
                await self.processISO7816Tag(isoTag, session: session)
                if var card = self.cardInfo {
                    card.debugLog = debugLines + [""] + card.debugLog
                    self.cardInfo = card
                }

            case .miFare(let mifareTag):
                self.processMiFareTag(mifareTag, session: session)
                if var card = self.cardInfo {
                    card.debugLog = debugLines + [""] + card.debugLog
                    self.cardInfo = card
                }

            default:
                dlog("[PROCESS] Unsupported: \(Self.tagTypeName(bestTag))")
                var info = TransitCardInfo()
                info.debugLog = debugLines
                self.cardInfo = info
                self.errorMessage = String(localized: "지원하지 않는 카드")
                self.isScanning = false
                session.invalidate(errorMessage: String(localized: "지원하지 않는 카드"))
            }
        }
    }
}

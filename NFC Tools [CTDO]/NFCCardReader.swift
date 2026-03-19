import Foundation
import Combine
import CoreNFC

// Models are defined in /Models/ folder (KoreanCardType, TransactionRecord, TripRecord, TripLeg, TransitCardInfo)

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
            errorMessage = L("이 기기는 NFC를 지원하지 않습니다")
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
        statusMessage = L("카드를 가까이 대주세요...")
        isScanning = true

        session = NFCTagReaderSession(
            pollingOption: [.iso14443],
            delegate: self,
            queue: .main
        )
        log("Session created: \(session != nil ? "OK" : "NIL")")
        session?.alertMessage = L("교통카드를 iPhone 뒷면에 가까이 대주세요")
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
        info.rawData.append(RawDataEntry(key: "UID", value: Self.hex(uid)))
        info.rawData.append(RawDataEntry(key: "UID (hex compact)", value: Self.hexCompact(uid)))
        info.dlog("[TAG] Type: ISO 7816")
        info.dlog("[TAG] UID: \(Self.hex(uid))")

        if let hist = tag.historicalBytes {
            info.rawData.append(RawDataEntry(key: "Historical Bytes", value: Self.hex(hist)))
            info.dlog("[TAG] Historical Bytes (\(hist.count)B): \(Self.hex(hist))")
        } else {
            info.dlog("[TAG] Historical Bytes: nil")
        }

        if let appData = tag.applicationData {
            info.rawData.append(RawDataEntry(key: "Application Data", value: Self.hex(appData)))
            info.dlog("[TAG] Application Data (\(appData.count)B): \(Self.hex(appData))")
        } else {
            info.dlog("[TAG] Application Data: nil")
        }

        let initialAID = tag.initialSelectedAID
        if !initialAID.isEmpty {
            info.rawData.append(RawDataEntry(key: "Initial Selected AID", value: initialAID))
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
                info.rawData.append(RawDataEntry(key: "SELECT \(aidHex) → SW", value: swHex))
                if !data.isEmpty {
                    info.rawData.append(RawDataEntry(key: "SELECT \(aidHex) → Data", value: Self.hex(data)))
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
                    info.rawData.append(RawDataEntry(key: "Issuer (idCenter)", value: String(format: "%02X (%d)", issuer, issuer)))
                    info.dlog("[PURSE] Issuer: \(issuer) → \(resolvedType.rawValue)")

                    // [4-11] CSN (Card Serial Number, 8 bytes)
                    if pd.count >= base + 12 {
                        let csn = Self.hexCompact(pd[(base+4)...(base+11)])
                        info.cardNumber = csn
                        info.rawData.append(RawDataEntry(key: "Card Serial (CSN)", value: csn))
                        info.dlog("[PURSE] CSN: \(csn)")
                    }

                    // [17-20] Issue date (BCD YYYYMMDD)
                    if pd.count >= base + 21 {
                        let issueHex = Self.hexCompact(pd[(base+17)...(base+20)])
                        info.rawData.append(RawDataEntry(key: "Issue Date", value: issueHex))
                        info.dlog("[PURSE] Issue Date: \(issueHex)")
                    }

                    // [21-24] Expiry date (BCD YYYYMMDD)
                    if pd.count >= base + 25 {
                        let expHex = Self.hexCompact(pd[(base+21)...(base+24)])
                        info.rawData.append(RawDataEntry(key: "Expiry Date", value: expHex))
                        info.dlog("[PURSE] Expiry: \(expHex)")
                    }

                    // [0] cardType, [1] alg, [2] vk, [26] userCode
                    info.rawData.append(RawDataEntry(key: "Card Type", value: String(format: "%02X", pd[base])))
                    info.rawData.append(RawDataEntry(key: "Algorithm", value: String(format: "%02X", pd[base + 1])))
                    if pd.count >= base + 27 {
                        let userCode = pd[base + 26]
                        let userType: String
                        switch userCode {
                        case 1: userType = L("일반 (Adult)")
                        case 2: userType = L("어린이 (Child)")
                        case 3: userType = L("경로 (Senior)")
                        case 4: userType = L("청소년 (Teen)")
                        case 5: userType = L("장애인 (Disabled)")
                        default: userType = L("기타 (\(userCode))")
                        }
                        info.rawData.append(RawDataEntry(key: "User Type", value: userType))
                        info.dlog("[PURSE] User: \(userType)")
                    }
                } else {
                    // No B0 tag found, use raw parsing
                    info.cardType = cardType == .unknown ? .tmoney : cardType
                    info.dlog("[FCI] No B0 tag, raw parse")
                    if data.count >= 12 {
                        info.cardNumber = Self.hexCompact(data[4..<12])
                        info.rawData.append(RawDataEntry(key: "Card ID (raw)", value: Self.hexCompact(data[4..<12])))
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
                    info.rawData.append(RawDataEntry(key: "Balance → SW", value: bswHex))
                    info.rawData.append(RawDataEntry(key: "Balance → Raw Data", value: Self.hex(balData)))

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

                // Separate collection arrays for merging
                var method1Records: [TransactionRecord] = []
                var fallback4E: [TransactionRecord] = []
                var sfi3Raw: [Data] = []
                var sfi4Raw: [Data] = []
                var sfi5Raw: [Data] = []

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
                            info.rawData.append(RawDataEntry(key: "TX 78#\(i)", value: Self.hex(txData)))
                            method1Records.append(Self.parseTransaction(data: txData))
                        }
                    } catch { break }
                }
                if method1Supported {
                    info.dlog("[TX] 90 78: \(method1Records.count) valid records")
                }

                // Method 2: 90 4E (proprietary GET DATA, 46B) - store separately
                if method1Records.isEmpty {
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
                                info.rawData.append(RawDataEntry(key: "TX 4E#\(i)", value: Self.hex(txData)))
                                fallback4E.append(Self.parseTransaction(data: txData))
                            }
                        } catch { break }
                    }
                }

                // Method 3: READ RECORD on SFI 3-5 (always try - SFI may have more records)
                do {
                    info.dlog("[TX] Method 3: READ RECORD (00 B2) on SFIs")
                    let sfiValues: [(sfi: UInt8, p2: UInt8)] = [
                        (3, 0x1C), (4, 0x24), (5, 0x2C), (6, 0x34),
                        (7, 0x3C), (8, 0x44), (9, 0x4C), (10, 0x54)
                    ]
                    for (sfi, p2) in sfiValues {
                        for i: UInt8 in 1...30 { // Read up to 30 records (card returns error when done)
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
                                    info.rawData.append(RawDataEntry(key: "TX SFI\(sfi)#\(i)", value: Self.hex(txData)))
                                    switch sfi {
                                    case 3: sfi3Raw.append(txData)
                                    case 4: sfi4Raw.append(txData)
                                    case 5: sfi5Raw.append(txData)
                                    default: break
                                    }
                                }
                            } catch { break }
                        }
                    }
                } // end Method 3

                // Method 4: SELECT EF by file ID + READ BINARY
                if method1Records.isEmpty && fallback4E.isEmpty && sfi4Raw.isEmpty {
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
                                info.rawData.append(RawDataEntry(key: "EF \(fidHex)", value: Self.hex(rbData)))
                            }
                        } catch {
                            info.dlog("[TX] EF \(fidHex) error: \(error.localizedDescription)")
                        }
                    }
                    // Re-SELECT the transit AID since we changed the current DF
                    _ = try? await sendAPDU(tag: tag, cla: 0x00, ins: 0xA4, p1: 0x04, p2: 0x00, data: aid)
                }

                // Post-process: merge SFI 3 (timestamps) with SFI 4 (balances)
                let isTmoney = info.cardType == .tmoney || info.cardType == .railplus
                if !sfi4Raw.isEmpty {
                    let merged = Self.mergeSFIData(
                        sfi3: sfi3Raw, sfi4: sfi4Raw, sfi5: sfi5Raw,
                        isTmoney: isTmoney
                    )
                    info.transactions = merged.transactions
                    info.trips = merged.trips
                    info.dlog("[TX] Merged \(info.transactions.count) transactions + \(info.trips.count) trips")
                } else if !method1Records.isEmpty {
                    info.transactions = method1Records.filter { $0.amount > 0 }
                    info.dlog("[TX] Using \(info.transactions.count) records from 90 78")
                } else if !fallback4E.isEmpty {
                    info.transactions = fallback4E.filter { $0.amount > 0 }
                    info.dlog("[TX] Using \(info.transactions.count) records from 90 4E")
                }

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
            ? L("카드를 읽었지만 인식할 수 없는 카드입니다")
            : L("\(info.cardType.displayName) 읽기 완료!")

        session.alertMessage = L("카드 읽기 완료!")
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
        info.rawData.append(RawDataEntry(key: "UID", value: Self.hex(tag.identifier)))
        info.rawData.append(RawDataEntry(key: "MIFARE Family", value: familyName))
        info.dlog("[TAG] Type: MIFARE \(familyName)")
        info.dlog("[TAG] UID: \(Self.hex(tag.identifier))")

        if let hist = tag.historicalBytes {
            info.rawData.append(RawDataEntry(key: "Historical Bytes", value: Self.hex(hist)))
            info.dlog("[TAG] Historical Bytes: \(Self.hex(hist))")
        }

        cardInfo = info
        isScanning = false
        statusMessage = L("MIFARE \(familyName) 카드")

        session.alertMessage = L("카드 읽기 완료!")
        session.invalidate()
    }

    // Korean transit timestamp: packed format [16-bit day][5-bit hour][6-bit minute][5-bit second/2]
    // Day 0 = 1989-06-14 (derived from cross-referencing raw card data with known trip dates)
    private static let transitDayEpoch: Date = {
        var c = DateComponents()
        c.year = 1989; c.month = 6; c.day = 14
        c.hour = 0; c.minute = 0; c.second = 0
        c.timeZone = TimeZone(identifier: "Asia/Seoul")
        return Calendar.current.date(from: c)!
    }()

    // Parse packed timestamp from SFI 3 bytes[11-14]
    // Format: bits[31:16]=day counter, bits[15:11]=hour, bits[10:5]=minute, bits[4:0]=second/2
    private static func parsePackedTimestamp(_ raw: UInt32) -> Date? {
        let dayCount = Int(raw >> 16)
        let timePart = raw & 0xFFFF
        let hour = Int((timePart >> 11) & 0x1F)
        let minute = Int((timePart >> 5) & 0x3F)
        let second = Int(timePart & 0x1F) * 2

        guard dayCount > 0, hour < 24, minute < 60, second < 60 else { return nil }

        let kst = TimeZone(identifier: "Asia/Seoul")!
        let calendar = Calendar.current
        guard let dayDate = calendar.date(byAdding: .day, value: dayCount, to: transitDayEpoch) else { return nil }

        var components = calendar.dateComponents(in: kst, from: dayDate)
        components.hour = hour
        components.minute = minute
        components.second = second

        return calendar.date(from: components)
    }

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
    // [11-14] timestamp (packed: [16-bit day from 1989-06-14][5h][6m][5s/2])
    // [22-23] base fare (big-endian KRW)
    // [24-27] terminal/station ID
    // [50-51] distance surcharge
    private static func parseSFI3Record(data: Data) -> TransactionRecord {
        let boarding = data.count > 2 ? data[2] == 0x00 : true
        let txType: TransactionRecord.TransactionType = boarding ? .payment : .transfer
        // byte[3] = transport type (for future use in display)

        // Timestamp: bytes 11-14, packed format [16-bit day][5h][6m][5s/2]
        var date: Date?
        if data.count >= 15 {
            let raw = UInt32(data[11]) << 24 | UInt32(data[12]) << 16 | UInt32(data[13]) << 8 | UInt32(data[14])
            date = parsePackedTimestamp(raw)
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

    // Merge SFI 3 (trip timestamps) with SFI 4 (financial/balance)
    // Returns: (transactions for financial history, trips for transit detail)
    private static func mergeSFIData(
        sfi3: [Data], sfi4: [Data], sfi5: [Data],
        isTmoney: Bool
    ) -> (transactions: [TransactionRecord], trips: [TripRecord]) {

        // === SECTION 1: Build financial transaction list (이용 내역) ===

        // Extract alighting dates from SFI 3 for matching with SFI 4
        struct SFI3Alight {
            let date: Date?
            let fare: Int
            let tripCounter: UInt8
        }
        var sfi3Alights: [SFI3Alight] = []
        for data in sfi3 {
            guard data.count >= 24, data[2] == 0x01 else { continue }
            let raw = UInt32(data[11]) << 24 | UInt32(data[12]) << 16 | UInt32(data[13]) << 8 | UInt32(data[14])
            let fare = Int(data[22]) << 8 | Int(data[23])
            sfi3Alights.append(SFI3Alight(date: parsePackedTimestamp(raw), fare: fare, tripCounter: data[4]))
        }

        var transactions: [TransactionRecord] = []
        var alightIdx = 0
        var lastSFI4Balance: Int? = nil
        // Map: SFI3 alight index → actual SFI4 fare and balance
        var actualFareByAlightIdx: [Int: Int] = [:]
        var actualBalanceByAlightIdx: [Int: Int] = [:]

        for data in sfi4 {
            guard data.count >= 14 else { continue }
            let typeByte = data[0]
            guard typeByte == 0x01 || typeByte == 0x02 else { continue }

            let isTopUp = typeByte == 0x02
            let balance: Int
            let fare: Int
            if isTmoney {
                balance = Int(data[2]) << 24 | Int(data[3]) << 16 | Int(data[4]) << 8 | Int(data[5])
                fare = Int(data[10]) << 24 | Int(data[11]) << 16 | Int(data[12]) << 8 | Int(data[13])
            } else {
                balance = Int(data[4]) << 8 | Int(data[5])
                fare = Int(data[12]) << 8 | Int(data[13])
            }
            lastSFI4Balance = balance

            if isTopUp {
                transactions.append(TransactionRecord(amount: fare, balance: balance, date: nil, type: .topUp))
                continue
            }
            guard fare > 0 else { continue }

            // Check marker at bytes[14-15]: 0x4913/0x49XX=standard transit, 0x0720=sub-charge/transfer
            let marker: UInt16 = data.count >= 16
                ? UInt16(data[14]) << 8 | UInt16(data[15])
                : 0x4913

            if marker != 0x4913 {
                // Non-standard marker (0x0720=sub-charge/transfer, 0x4923=transfer surcharge, etc.)
                // Parse BCD timestamp from bytes[26-32] if available
                // Parse BCD date: bytes = [YY YY MM DD HH MM SS]
                var bcdDate: Date? = nil
                if isTmoney && data.count >= 33 && data[26] != 0x00 {
                    let yearHi = Int(data[26] >> 4) * 10 + Int(data[26] & 0x0F) // 0x20 → 20
                    let yearLo = Int(data[27] >> 4) * 10 + Int(data[27] & 0x0F) // 0x26 → 26
                    let year = yearHi * 100 + yearLo // → 2026
                    let month = Int(data[28] >> 4) * 10 + Int(data[28] & 0x0F)
                    let day = Int(data[29] >> 4) * 10 + Int(data[29] & 0x0F)
                    let hour = Int(data[30] >> 4) * 10 + Int(data[30] & 0x0F)
                    let minute = Int(data[31] >> 4) * 10 + Int(data[31] & 0x0F)
                    let second = Int(data[32] >> 4) * 10 + Int(data[32] & 0x0F)
                    if year > 2000 && month >= 1 && month <= 12 && day >= 1 && day <= 31 {
                        var c = DateComponents()
                        c.year = year; c.month = month; c.day = day
                        c.hour = hour; c.minute = minute; c.second = second
                        c.timeZone = TimeZone(identifier: "Asia/Seoul")
                        bcdDate = Calendar.current.date(from: c)
                    }
                }
                transactions.append(TransactionRecord(amount: fare, balance: balance, date: bcdDate, type: .payment))
            } else {
                // 0x4913 = standard transit charge → match with SFI3 alighting
                var date: Date? = nil
                if alightIdx < sfi3Alights.count {
                    date = sfi3Alights[alightIdx].date
                    actualFareByAlightIdx[alightIdx] = fare
                    actualBalanceByAlightIdx[alightIdx] = balance
                    alightIdx += 1
                }
                transactions.append(TransactionRecord(amount: fare, balance: balance, date: date, type: .payment))
            }
        }

        // Add remaining SFI 3 alighting records (older trips beyond SFI 4 range)
        if alightIdx < sfi3Alights.count {
            var runBal = lastSFI4Balance ?? 0
            var seenCounters = Set<UInt8>()
            for i in alightIdx..<sfi3Alights.count {
                let alight = sfi3Alights[i]
                guard alight.fare > 0, seenCounters.insert(alight.tripCounter).inserted else { continue }
                transactions.append(TransactionRecord(
                    amount: alight.fare, balance: runBal, date: alight.date, type: .payment
                ))
                runBal += alight.fare
            }
        }

        // === SECTION 2: Build trip records (교통 이용 내역) ===

        // Parse ALL SFI 3 records into legs, group by trip counter
        struct ParsedLeg {
            let isBoarding: Bool
            let transportType: UInt8
            let tripCounter: UInt8
            let date: Date?
            let fare: Int
            let distanceMeters: Int // bytes[19-20] on alighting records
        }
        var allLegs: [ParsedLeg] = []
        for data in sfi3 {
            guard data.count >= 24 else { continue }
            let raw = UInt32(data[11]) << 24 | UInt32(data[12]) << 16 | UInt32(data[13]) << 8 | UInt32(data[14])
            let isAlighting = data[2] == 0x01
            // bytes[19-20] = distance in meters (only meaningful on alighting records)
            let dist = (isAlighting && data.count >= 21)
                ? Int(data[19]) << 8 | Int(data[20])
                : 0
            allLegs.append(ParsedLeg(
                isBoarding: !isAlighting,
                transportType: data[3],
                tripCounter: data[4],
                date: parsePackedTimestamp(raw),
                fare: Int(data[22]) << 8 | Int(data[23]),
                distanceMeters: dist
            ))
        }

        // Group legs by trip counter, preserving order (newest trips first)
        var tripMap: [UInt8: [ParsedLeg]] = [:]
        var tripOrder: [UInt8] = [] // preserve newest-first order
        for leg in allLegs {
            if tripMap[leg.tripCounter] == nil {
                tripOrder.append(leg.tripCounter)
            }
            tripMap[leg.tripCounter, default: []].append(leg)
        }

        // Build alight index lookup: trip counter → SFI3 alight index
        var counterToAlightIdx: [UInt8: Int] = [:]
        for (i, alight) in sfi3Alights.enumerated() {
            if counterToAlightIdx[alight.tripCounter] == nil {
                counterToAlightIdx[alight.tripCounter] = i
            }
        }

        var trips: [TripRecord] = []
        for counter in tripOrder {
            guard let legs = tripMap[counter] else { continue }
            // Total fare: prefer actual SFI4 fare (includes distance surcharge) over SFI3 base fare
            // Prefer alighting fare; fallback to boarding fare for incomplete trips
            let sfi3Fare = legs.first(where: { !$0.isBoarding })?.fare
                ?? legs.first(where: { $0.isBoarding })?.fare
                ?? 0
            let actualFare: Int
            if let aidx = counterToAlightIdx[counter], let sfi4Fare = actualFareByAlightIdx[aidx] {
                actualFare = sfi4Fare  // Real charge from SFI4
            } else {
                actualFare = sfi3Fare  // Fallback to SFI3 base fare
            }
            // Distance and balance from SFI4
            let distance = legs.first(where: { !$0.isBoarding })?.distanceMeters ?? 0
            let balAfter: Int
            if let aidx = counterToAlightIdx[counter], let bal = actualBalanceByAlightIdx[aidx] {
                balAfter = bal
            } else {
                balAfter = 0
            }
            let tripLegs = legs.map { TripLeg(
                isBoarding: $0.isBoarding,
                transportType: $0.transportType,
                date: $0.date,
                fare: $0.fare
            )}
            trips.append(TripRecord(tripCounter: counter, totalFare: actualFare, distanceMeters: distance, balanceAfter: balAfter, legs: tripLegs))
        }

        return (transactions, trips)
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

        // Note: bytes[14-15]=0x0720 records do NOT have reliable timestamps
        // bytes[18-21] are not seconds-from-epoch (verified with real card data)
        // bytes[26-32] contain BCD last-NFC-read time on some records, not transaction time
        let date: Date? = nil

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
                self.errorMessage = L("NFC 오류: \(error.localizedDescription)")
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

                // Detect bank/payment card (iOS blocks EMV cards for third-party apps)
                if nsErr.domain == "NFCError" && nsErr.code == 2 {
                    self.errorMessage = L("은행/신용카드는 iOS 보안 정책으로 읽을 수 없습니다. T-money, Cashbee 등 교통 전용 카드만 지원됩니다.")
                    session.invalidate(errorMessage: L("은행카드 미지원"))
                } else {
                    self.errorMessage = L("카드 연결 실패: \(error.localizedDescription)")
                    session.invalidate(errorMessage: L("연결 실패: \(error.localizedDescription)"))
                }
                self.isScanning = false
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
                self.errorMessage = L("지원하지 않는 카드")
                self.isScanning = false
                session.invalidate(errorMessage: L("지원하지 않는 카드"))
            }
        }
    }
}

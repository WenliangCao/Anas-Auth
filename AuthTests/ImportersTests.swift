import Foundation
import Testing
@testable import Auth

// 各来源导入器的解析结果与 ente 保持一致
struct ImportersTests {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    // MARK: - 密码学原语

    @Test func argon2idMatchesIndependentImplementation() throws {
        let key = try ImportCrypto.argon2id(
            password: "password", salt: Data("0123456789abcdef".utf8),
            opsLimit: 2, memLimit: 19 * 1024 * 1024, keyLength: 32
        )
        #expect(key == Data(hexString: ImportFixtures.argon2Proton))
    }

    // MARK: - ente

    @Test func entePlainTextFixture() throws {
        let codes = try EnteImporter.parsePlainText(EnteImportFixtures.entePlainText)
        #expect(codes.count == 2)
        #expect(codes[0].type == .totp && codes[0].issuer == "GitHub" && codes[0].accountName == "release.bot@github.demo")
        #expect(codes[1].type == .hotp && codes[1].issuer == "Yubico" && codes[1].counter == 1)
    }

    @Test func entePlainTextSkipsMalformedLinesAndHandlesCommas() throws {
        let mixed = """
        otpauth://totp/Example:valid@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example
        not-an-otp-uri
        """
        #expect(try EnteImporter.parsePlainText(mixed).map(\.accountName) == ["valid@example.com"])

        let commaInIssuer = """
        otpauth://totp/alice@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example,%20Inc
        otpauth://totp/bob@example.com?secret=GEZDGNBVGY3TQOJQ&issuer=Example
        """
        let codes = try EnteImporter.parsePlainText(commaInIssuer)
        #expect(codes.first?.issuer == "Example, Inc")

        let commaDelimited = "otpauth://totp/a@x.com?secret=JBSWY3DPEHPK3PXP&issuer=A,"
            + "otpauth://totp/b@x.com?secret=GEZDGNBVGY3TQOJQ&issuer=B"
        #expect(try EnteImporter.parsePlainText(commaDelimited).count == 2)
    }

    @Test func enteRichJSONKeepsDisplayAndSkipsTrash() throws {
        let codes = try EnteImporter.parsePlainText(EnteImportFixtures.enteRichJSON)
        // 5 条里 Dropbox 在回收站，跳过
        #expect(codes.map(\.issuer) == ["GitHub", "Stripe", "Steam", "Yubico"])
        #expect(codes[0].pinned && codes[0].tags == ["Work", "Admin"])
        #expect(codes[0].note == "Primary admin account. Keep recovery contacts current.")
        #expect(codes[1].digits == 8 && codes[1].algorithm == .sha256 && codes[1].period == 45)
        #expect(codes[1].accountName == "treasury+auth@stripe.demo")
        #expect(codes[2].type == .steam && codes[2].pinned)
        #expect(codes[3].type == .hotp && codes[3].counter == 42 && codes[3].algorithm == .sha512)
    }

    @Test func enteRejectsJSONWithoutItems() {
        #expect(throws: ImportProviderError.self) { try EnteImporter.parsePlainText(#"{"unexpected": []}"#) }
    }

    @Test func enteEncryptedExport() throws {
        let export = try EnteImporter.decodeEncryptedExport(data(ImportFixtures.enteEncrypted))
        let codes = try EnteImporter.decrypt(export, password: "test1234")
        #expect(codes.count == 2) // 第三条在回收站
        #expect(codes[0].issuer == "GitHub" && codes[0].pinned && codes[0].tags == ["Work"] && codes[0].note == "admin")
        #expect(codes[0].iconID == "github")
        #expect(codes[1].type == .hotp && codes[1].counter == 42)
        #expect(throws: ImportProviderError.incorrectPassword) { try EnteImporter.decrypt(export, password: "wrong") }
    }

    // MARK: - Aegis

    @Test func aegisPlainVault() throws {
        let vault = try AegisImporter.decode(data(ImportFixtures.aegisPlain))
        #expect(!AegisImporter.isEncrypted(vault))
        let codes = try AegisImporter.parse(vault, password: nil)
        #expect(codes.count == 3)
        #expect(codes[0].issuer == "GitHub" && codes[0].accountName == "alice@example.com")
        #expect(codes[0].algorithm == .sha256 && codes[0].digits == 8 && codes[0].period == 60)
        #expect(codes[0].pinned && codes[0].tags == ["Work"] && codes[0].note == "Recovery codes in safe")
        #expect(codes[1].type == .hotp && codes[1].counter == 5)
        #expect(codes[2].type == .steam && codes[2].digits == 5)
    }

    @Test func aegisEncryptedVault() throws {
        let vault = try AegisImporter.decode(data(ImportFixtures.aegisEncrypted))
        #expect(AegisImporter.isEncrypted(vault))
        let codes = try AegisImporter.parse(vault, password: "test")
        #expect(codes.map(\.issuer) == ["GitHub", "Yubico", "Steam"])
        #expect(throws: ImportProviderError.incorrectPassword) { try AegisImporter.parse(vault, password: "nope") }
    }

    @Test func aegisUnsupportedTypeFailsWithEntry() throws {
        let db: [String: Any] = ["entries": [["type": "yandex", "name": "x", "issuer": "Y", "info": ["secret": "JBSWY3DPEHPK3PXP"]]]]
        #expect {
            try AegisImporter.parseEntries(db)
        } throws: { error in
            guard case .invalidEntry(let entry, _) = error as? ImportProviderError else { return false }
            return entry.contains("yandex")
        }
    }

    // MARK: - 2FAS

    @Test func twoFASPlainBackup() throws {
        let backup = try TwoFASImporter.decode(data(ImportFixtures.twoFASPlain))
        let codes = try TwoFASImporter.parse(backup, password: nil)
        #expect(codes.count == 3)
        // issuer 为空时用服务名
        #expect(codes[0].issuer == "Google" && codes[0].accountName == "me@gmail.com" && codes[0].tags == ["Personal"])
        #expect(codes[1].type == .steam)
        #expect(codes[2].type == .hotp && codes[2].counter == 3 && codes[2].algorithm == .sha512 && codes[2].digits == 8)
    }

    @Test func twoFASEncryptedBackup() throws {
        let backup = try TwoFASImporter.decode(data(ImportFixtures.twoFASEncrypted))
        #expect(TwoFASImporter.isEncrypted(backup))
        #expect(try TwoFASImporter.parse(backup, password: "test").count == 3)
        #expect(throws: ImportProviderError.incorrectPassword) { try TwoFASImporter.parse(backup, password: "nope") }
    }

    @Test func twoFASRejectsUnsupportedSchema() {
        #expect(throws: ImportProviderError.self) { try TwoFASImporter.decode(Data(#"{"schemaVersion": 2}"#.utf8)) }
        #expect(throws: ImportProviderError.self) { try TwoFASImporter.decode(Data(#"{"services": []}"#.utf8)) }
    }

    // MARK: - andOTP

    @Test func andOTPPlainSkipsUnsupportedTypes() throws {
        let entries = try #require(AndOTPImporter.plainEntries(data(ImportFixtures.andOTPPlain)))
        let codes = try AndOTPImporter.parse(entries)
        #expect(codes.count == 2) // MOTP 跳过
        #expect(codes[0].issuer == "GitLab" && codes[0].tags == ["Work"])
        #expect(codes[1].type == .hotp && codes[1].counter == 9)
    }

    @Test func andOTPEncryptedBackup() throws {
        let file = try #require(Data(base64Encoded: ImportFixtures.andOTPEncrypted))
        #expect(AndOTPImporter.plainEntries(file) == nil)
        #expect(try AndOTPImporter.parse(AndOTPImporter.decrypt(file, password: "test")).count == 2)
        #expect(throws: ImportProviderError.incorrectPassword) { try AndOTPImporter.decrypt(file, password: "nope") }
    }

    // MARK: - Proton

    @Test func protonPlainExport() throws {
        let codes = try ProtonImporter.parse(ProtonImporter.decode(data(EnteImportFixtures.protonPlain)))
        #expect(codes.map(\.issuer) == [".env", "/e/", "ente", "reddit"])
        #expect(codes.map(\.accountName) == ["example@ente.io", "cool@ente.com", "simple@ente.sh", "r@ente.com"])
        #expect(codes[1].secret == "554VBDOGJRLDG2JV")
        #expect(codes.allSatisfy { $0.type == .totp && $0.digits == 6 && $0.period == 30 && $0.algorithm == .sha1 })
    }

    @Test func protonEncryptedExport() throws {
        let export = try ProtonImporter.decode(data(EnteImportFixtures.protonEncrypted1231246))
        #expect(ProtonImporter.isEncrypted(export))
        let codes = try ProtonImporter.parse(ProtonImporter.decrypt(export, password: "1231246"))
        let plain = try ProtonImporter.parse(ProtonImporter.decode(data(EnteImportFixtures.protonPlain)))
        #expect(codes.map(\.dedupeKey) == plain.map(\.dedupeKey))
        #expect(throws: ImportProviderError.incorrectPassword) { try ProtonImporter.decrypt(export, password: "wrong") }
    }

    // MARK: - OTP Auth

    @Test(arguments: ["otpAuthBackup10", "otpAuthBackup11"])
    func otpAuthBackups(_ fixture: String) throws {
        let file = try #require(Data(base64Encoded: fixture == "otpAuthBackup10"
            ? EnteImportFixtures.otpAuthBackup10 : EnteImportFixtures.otpAuthBackup11))
        let codes = try OTPAuthAppImporter.parse(file, password: "abc123")
        #expect(codes.count == 2)
        #expect(codes[0].type == .totp && codes[0].issuer == "Example TOTP" && codes[0].accountName == "alice@example.com")
        #expect(codes[0].secret == "MJQWG23VOAWXI33UOAWXGZLDOJSXI")
        #expect(codes[1].type == .hotp && codes[1].issuer == "Example HOTP" && codes[1].counter == 7)
        #expect(codes[1].secret == "MJQWG23VOAWWQ33UOAWXGZLDOJSXI")
        #expect(codes.allSatisfy { $0.algorithm == .sha1 && $0.digits == 6 && $0.period == 30 })
        #expect(throws: ImportProviderError.incorrectPassword) { try OTPAuthAppImporter.parse(file, password: "wrong-password") }
    }

    @Test func otpAuthSingleAccounts() throws {
        let legacy = try OTPAuthAppImporter.parse(
            #require(Data(base64Encoded: EnteImportFixtures.otpAuthAccount11)), password: "abc123"
        )
        #expect(legacy.map(\.issuer) == ["Legacy Account"])
        #expect(legacy.first?.secret == "ONUW4Z3MMUWWYZLHMFRXSLLTMVRXEZLU")
        let modern = try OTPAuthAppImporter.parse(
            #require(Data(base64Encoded: EnteImportFixtures.otpAuthAccount12)), password: "abc123"
        )
        #expect(modern.map(\.accountName) == ["modern@example.com"])
        #expect(modern.first?.secret == "ONUW4Z3MMUWW233EMVZG4LLTMVRXEZLU")
    }

    // MARK: - Bitwarden / LastPass / Raivo

    @Test func bitwardenExport() throws {
        let json = """
        {"folders":[{"id":"f1","name":"Work"}],"items":[
          {"name":"Example","folderId":"f1","notes":"in the safe","login":{"username":"me@example.com",
            "totp":"otpauth://totp/Example:me@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Example"}},
          {"name":"Steam","login":{"username":"gamer","totp":"steam://ONSWG4TFOQXG64RA"}},
          {"name":"Raw","login":{"username":"raw@example.com","totp":"GEZD GNBV GY3T QOJQ"}},
          {"name":"No TOTP","login":{"username":"x"}},
          {"name":"Card","type":3}
        ]}
        """
        let codes = try BitwardenImporter.parse(data(json))
        #expect(codes.count == 3)
        #expect(codes[0].tags == ["Work"] && codes[0].note == "in the safe")
        #expect(codes[1].type == .steam && codes[1].issuer == "Steam" && codes[1].accountName == "gamer")
        #expect(codes[2].issuer == "Raw" && codes[2].secret == "GEZDGNBVGY3TQOJQ")
    }

    @Test func lastPassExport() throws {
        let json = """
        {"version":3,"accounts":[{"issuerName":"Facebook","userName":"me@fb.com","secret":"JBSWY3DPEHPK3PXP",
          "algorithm":"SHA256","timeStep":30,"digits":6}]}
        """
        let code = try #require(try LastPassImporter.parse(data(json)).first)
        #expect(code.issuer == "Facebook" && code.accountName == "me@fb.com" && code.algorithm == .sha256)
    }

    @Test func raivoExport() throws {
        let json = """
        [{"issuer":"Twitter","account":"@me","secret":"JBSWY3DPEHPK3PXP","kind":"TOTP","algorithm":"SHA1","digits":"6","timer":"30","counter":"0"},
         {"issuer":"Bank","account":"me","secret":"GEZDGNBVGY3TQOJQ","kind":"HOTP","algorithm":"SHA512","digits":"8","timer":"30","counter":"12"}]
        """
        let codes = try RaivoImporter.parse(data(json))
        #expect(codes[0].issuer == "Twitter" && codes[0].digits == 6)
        #expect(codes[1].type == .hotp && codes[1].counter == 12 && codes[1].digits == 8)
    }

    // MARK: - 通用规则

    @Test func importedOTPNormalizesLikeEnte() throws {
        let totp = try ImportedOTP.make(kind: "totp", issuer: "E", account: "a", secret: "ASKZNWOU6SVYAMVS",
                                        algorithm: "SHA1", digits: 0, period: 0)
        #expect(totp.digits == 6 && totp.period == 30)
        #expect(throws: (any Error).self) {
            try ImportedOTP.make(kind: "totp", issuer: "E", account: "a", secret: "ASKZNWOU6SVYAMVS", algorithm: nil, digits: 11)
        }
        #expect(throws: (any Error).self) {
            try ImportedOTP.make(kind: "hotp", issuer: "E", account: "a", secret: "ASKZNWOU6SVYAMVS", algorithm: nil, digits: 6, counter: -1)
        }
        #expect(throws: (any Error).self) {
            try ImportedOTP.make(kind: "steam", issuer: "E", account: "a", secret: "ASKZNWOU6SVYAMVS", algorithm: nil, digits: 5, allowSteam: false)
        }
    }

    // MARK: - Google Authenticator 多张二维码

    private func migration(id: Int, size: Int, index: Int) -> GoogleMigrationParser.Migration {
        let code = OTPCode(issuer: "I\(index)", accountName: "a", secret: "JBSWY3DPEHPK3PXP")
        return .init(codes: [code], batchID: id, batchSize: size, batchIndex: index)
    }

    @Test func googleTrackerCollectsAllBatchesInOrder() throws {
        var tracker = GoogleMigrationTracker()
        #expect(try tracker.add(migration(id: 42, size: 3, index: 2)) == nil)
        #expect(try tracker.add(migration(id: 42, size: 3, index: 0)) == nil)
        #expect(try tracker.add(migration(id: 42, size: 3, index: 0)) == nil) // 重复不计数
        #expect(tracker.receivedCount == 2)
        let codes = try #require(try tracker.add(migration(id: 42, size: 3, index: 1)))
        #expect(codes.map(\.issuer) == ["I0", "I1", "I2"])
    }

    @Test func googleTrackerSingleAndMissingMetadata() throws {
        var tracker = GoogleMigrationTracker()
        #expect(try tracker.add(migration(id: 0, size: 0, index: 0)) != nil)
        #expect(try tracker.add(migration(id: 42, size: 1, index: 0)) != nil)
    }

    @Test func googleTrackerRejectsOtherExportsAndBadIndex() throws {
        var tracker = GoogleMigrationTracker()
        #expect(try tracker.add(migration(id: 42, size: 2, index: 0)) == nil)
        #expect(throws: GoogleMigrationTracker.TrackerError.differentExport) {
            try tracker.add(migration(id: 7, size: 2, index: 1))
        }
        var fresh = GoogleMigrationTracker()
        #expect(throws: GoogleMigrationTracker.TrackerError.invalidBatch) {
            try fresh.add(migration(id: 42, size: 2, index: 2))
        }
    }

    @Test func googleMigrationParsesBatchMetadata() throws {
        // OtpParameters{secret, name, issuer, algo=1, digits=1, type=2} + batch_size=3, batch_index=2, batch_id=42
        var params = Data([0x0A, 0x0A]) + Data([0x48, 0x65, 0x6C, 0x6C, 0x6F, 0x21, 0xDE, 0xAD, 0xBE, 0xEF])
        params += Data([0x12, 0x01, 0x61, 0x1A, 0x01, 0x47, 0x20, 0x01, 0x28, 0x01, 0x30, 0x02])
        var payload = Data([0x0A, UInt8(params.count)]) + params
        payload += Data([0x18, 0x03, 0x20, 0x02, 0x28, 0x2A])
        let url = "otpauth-migration://offline?data=" + payload.base64EncodedString()
            .addingPercentEncoding(withAllowedCharacters: .alphanumerics)!
        let migration = try GoogleMigrationParser.parseMigration(url)
        #expect(migration.batchSize == 3 && migration.batchIndex == 2 && migration.batchID == 42)
        #expect(migration.codes.first?.issuer == "G")
    }
}

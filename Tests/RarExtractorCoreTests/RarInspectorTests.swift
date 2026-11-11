import XCTest
@testable import RarExtractorCore

final class RarInspectorTests: XCTestCase {
    func test_plainRar4() {
        XCTAssertEqual(RarInspector.inspect(Fixture.url("basic.rar")),
                       RarInfo(isEncrypted: false, isMultiVolume: false))
    }

    func test_plainRar5() {
        XCTAssertEqual(RarInspector.inspect(Fixture.url("basic5.rar")),
                       RarInfo(isEncrypted: false, isMultiVolume: false))
    }

    func test_rar4DataEncrypted() {
        XCTAssertEqual(RarInspector.inspect(Fixture.url("encrypted.rar"))?.isEncrypted, true)
    }

    func test_rar4HeaderEncrypted() {
        XCTAssertEqual(RarInspector.inspect(Fixture.url("encrypted_header.rar"))?.isEncrypted, true)
    }

    func test_rar4MultiVolume() {
        XCTAssertEqual(RarInspector.inspect(Fixture.url("multi.part0001.rar"))?.isMultiVolume, true)
    }

    func test_notRar_returnsNil() {
        XCTAssertNil(RarInspector.inspect(Fixture.url("notrar.rar")))
    }

    func test_missingFile_returnsNil() {
        XCTAssertNil(RarInspector.inspect(URL(fileURLWithPath: "/nonexistent/x.rar")))
    }

    // RAR5 sintético: no hay fixture RAR5 cifrado en libarchive v3.7.4.
    private static let rar5Sig: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]

    private func writeTemp(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).rar")
        try Data(bytes).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func test_rar5ArchiveEncryptionHeader() throws {
        // CRC(4) size=2 type=4 flags=0
        let url = try writeTemp(Self.rar5Sig + [0, 0, 0, 0, 0x02, 0x04, 0x00])
        XCTAssertEqual(RarInspector.inspect(url)?.isEncrypted, true)
    }

    func test_rar5FileEncryptionRecord() throws {
        // main: CRC size=3 type=1 flags=0 archiveFlags=0
        let main: [UInt8] = [0, 0, 0, 0, 0x03, 0x01, 0x00, 0x00]
        // file: CRC size=6 type=2 flags=1(extra) extraSize=2 | extra record: size=1 type=1 (encryption)
        // (los campos propios del archivo se omiten: el inspector solo lee el área extra final)
        let file: [UInt8] = [0, 0, 0, 0, 0x05, 0x02, 0x01, 0x02, 0x01, 0x01]
        let url = try writeTemp(Self.rar5Sig + main + file)
        XCTAssertEqual(RarInspector.inspect(url), RarInfo(isEncrypted: true, isMultiVolume: false))
    }

    func test_rar5VolumeFlag() throws {
        let main: [UInt8] = [0, 0, 0, 0, 0x03, 0x01, 0x00, 0x01]
        let url = try writeTemp(Self.rar5Sig + main)
        XCTAssertEqual(RarInspector.inspect(url)?.isMultiVolume, true)
    }

    /// vint de 2^64 − 1.
    private static let hugeVint: [UInt8] = Array(repeating: 0xFF, count: 9) + [0x01]

    func test_rar5HugeDataSize_doesNotCrash() throws {
        // main: type=1 flags=2(data) dataSize=2^64-1 archiveFlags=0 → 13 bytes
        let header: [UInt8] = [0x01, 0x02] + Self.hugeVint + [0x00]
        let url = try writeTemp(Self.rar5Sig + [0, 0, 0, 0, UInt8(header.count)] + header + [0, 0, 0, 0])
        XCTAssertEqual(RarInspector.inspect(url), RarInfo(isEncrypted: false, isMultiVolume: false))
    }

    func test_rar5HugeExtraRecordSize_doesNotCrash() throws {
        // file: type=2 flags=1(extra) extraSize=11 | extra: size=2^64-1 type=2 (no es cifrado)
        let extra: [UInt8] = Self.hugeVint + [0x02]
        let header: [UInt8] = [0x02, 0x01, UInt8(extra.count)] + extra
        let url = try writeTemp(Self.rar5Sig + [0, 0, 0, 0, UInt8(header.count)] + header)
        XCTAssertEqual(RarInspector.inspect(url), RarInfo(isEncrypted: false, isMultiVolume: false))
    }

    func test_truncatedRar5_doesNotCrash() throws {
        let url = try writeTemp(Self.rar5Sig + [0, 0, 0, 0, 0xFF])
        XCTAssertEqual(RarInspector.inspect(url), RarInfo(isEncrypted: false, isMultiVolume: false))
    }
}

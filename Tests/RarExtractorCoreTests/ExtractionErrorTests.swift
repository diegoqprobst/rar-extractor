import XCTest
@testable import RarExtractorCore

final class ExtractionErrorTests: XCTestCase {
    func test_classify_encryptedData_viaHeaders() {
        let e = ExtractionError.classify(
            stderr: "foo.txt: Prefix found: Inappropriate file type or format\nbsdtar: Error exit delayed from previous errors.\n",
            exitCode: 1, archive: Fixture.url("encrypted.rar"))
        XCTAssertEqual(e, .encryptedUnsupported)
    }

    func test_classify_encryptedHeader_viaStderr() {
        let e = ExtractionError.classify(
            stderr: "bsdtar: RAR encryption support unavailable.\n",
            exitCode: 1, archive: URL(fileURLWithPath: "/nonexistent/x.rar"))
        XCTAssertEqual(e, .encryptedUnsupported)
    }

    func test_classify_multiVolume_viaHeaders() {
        let e = ExtractionError.classify(
            stderr: "ppmd_lzss_conversion_test.txt: Bad RAR file data: Inappropriate file type or format\n",
            exitCode: 1, archive: Fixture.url("multi.part0001.rar"))
        XCTAssertEqual(e, .multiVolumeUnsupported)
    }

    func test_classify_multiVolume_viaName() {
        let e = ExtractionError.classify(stderr: "Bad RAR file data", exitCode: 1,
                                         archive: URL(fileURLWithPath: "/nonexistent/x.part0002.rar"))
        XCTAssertEqual(e, .multiVolumeUnsupported)
        let r = ExtractionError.classify(stderr: "Bad RAR file data", exitCode: 1,
                                         archive: URL(fileURLWithPath: "/nonexistent/x.r01"))
        XCTAssertEqual(r, .multiVolumeUnsupported)
    }

    func test_classify_notAnArchive() {
        let e = ExtractionError.classify(
            stderr: "bsdtar: Error opening archive: Unrecognized archive format\n",
            exitCode: 1, archive: Fixture.url("notrar.rar"))
        XCTAssertEqual(e, .notAnArchive)
    }

    func test_classify_unknownFallsBackToToolFailed() {
        let e = ExtractionError.classify(stderr: "boom", exitCode: 1, archive: Fixture.url("basic.rar"))
        XCTAssertEqual(e, .toolFailed(code: 1, message: "boom"))
    }

    func test_userMessages_matchTable() {
        XCTAssertEqual(ExtractionError.archiveNotFound.userMessage, "No se encontró el archivo.")
        XCTAssertEqual(ExtractionError.notAnArchive.userMessage, "Este archivo no es un RAR válido o está dañado.")
        XCTAssertEqual(ExtractionError.encryptedUnsupported.userMessage,
                       "Este RAR tiene contraseña. Esta versión no abre RAR protegidos.")
        XCTAssertEqual(ExtractionError.multiVolumeUnsupported.userMessage,
                       "Este RAR está dividido en partes. Esta versión no abre RAR multiparte.")
        XCTAssertEqual(ExtractionError.destinationNotWritable.userMessage,
                       "No se puede escribir en la carpeta de destino.")
        XCTAssertEqual(ExtractionError.toolFailed(code: 1, message: "boom").userMessage,
                       "No se pudo descomprimir: boom")
    }
}

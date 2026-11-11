import XCTest
@testable import RarExtractorCore

final class BsdtarExtractorTests: XCTestCase {
    private var tmp: URL!
    private let fm = FileManager.default
    private let extractor = BsdtarExtractor()

    override func setUpWithError() throws {
        tmp = fm.temporaryDirectory.appendingPathComponent("Bsdtar-\(UUID().uuidString)")
        try fm.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let items = fm.enumerator(at: tmp, includingPropertiesForKeys: nil) {
            for case let url as URL in items { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path) }
        }
        try? fm.removeItem(at: tmp)
    }

    /// Copia un fixture al directorio temporal, opcionalmente con otro nombre.
    private func stage(_ fixture: String, as name: String? = nil) throws -> URL {
        let dst = tmp.appendingPathComponent(name ?? fixture)
        try fm.copyItem(at: Fixture.url(fixture), to: dst)
        return dst
    }

    private func entryNames(in dir: URL) throws -> Set<String> {
        let paths = try fm.subpathsOfDirectory(atPath: dir.path)
        return Set(paths)
    }

    private func assertThrows(_ expected: ExtractionError, _ body: () async throws -> URL,
                              file: StaticString = #filePath, line: UInt = #line) async {
        do {
            let url = try await body()
            XCTFail("Se esperaba \(expected), se obtuvo \(url.path)", file: file, line: line)
        } catch let e as ExtractionError {
            XCTAssertEqual(e, expected, file: file, line: line)
        } catch {
            XCTFail("Error inesperado \(error)", file: file, line: line)
        }
    }

    func test_extractsRar4() async throws {
        let archive = try stage("basic.rar")
        let dest = try await extractor.extract(archive: archive, intoParent: nil)
        XCTAssertEqual(dest.path, tmp.appendingPathComponent("basic").path)
        XCTAssertEqual(try entryNames(in: dest),
                       ["test.txt", "testlink", "testdir", "testdir/test.txt", "testemptydir"])
    }

    func test_extractsRar5() async throws {
        let archive = try stage("basic5.rar")
        let dest = try await extractor.extract(archive: archive, intoParent: nil)
        XCTAssertEqual(try entryNames(in: dest), ["helloworld.txt"])
    }

    func test_secondExtractionUsesNumberedFolder() async throws {
        let archive = try stage("basic5.rar")
        _ = try await extractor.extract(archive: archive, intoParent: nil)
        let second = try await extractor.extract(archive: archive, intoParent: nil)
        XCTAssertEqual(second.lastPathComponent, "basic5 2")
    }

    func test_unicodeAndSpacesInName() async throws {
        let archive = try stage("basic5.rar", as: "Mis fotos ñ 🎉.rar")
        let dest = try await extractor.extract(archive: archive, intoParent: nil)
        XCTAssertEqual(dest.lastPathComponent, "Mis fotos ñ 🎉")
        XCTAssertEqual(try entryNames(in: dest), ["helloworld.txt"])
    }

    func test_customParent() async throws {
        let archive = try stage("basic5.rar")
        let parent = tmp.appendingPathComponent("salida")
        try fm.createDirectory(at: parent, withIntermediateDirectories: false)
        let dest = try await extractor.extract(archive: archive, intoParent: parent)
        XCTAssertEqual(dest.path, parent.appendingPathComponent("basic5").path)
    }

    func test_zipSlipStaysInside() async throws {
        let inner = tmp.appendingPathComponent("inner")
        try fm.createDirectory(at: inner, withIntermediateDirectories: false)
        let slip = inner.appendingPathComponent("slip.rar")
        let py = Process()
        py.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        py.arguments = ["-I", "-c",
                        "import sys, zipfile; z = zipfile.ZipFile(sys.argv[1], 'w'); z.writestr('../escape.txt', 'x'); z.writestr('ok.txt', 'y'); z.close()",
                        slip.path]
        try py.run()
        py.waitUntilExit()
        XCTAssertEqual(py.terminationStatus, 0)

        _ = try? await extractor.extract(archive: slip, intoParent: nil)
        XCTAssertFalse(fm.fileExists(atPath: inner.appendingPathComponent("escape.txt").path))
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("escape.txt").path))
    }

    func test_notAnArchive_throwsAndCleansUp() async throws {
        let archive = try stage("notrar.rar")
        await assertThrows(.notAnArchive) { try await extractor.extract(archive: archive, intoParent: nil) }
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("notrar").path))
    }

    func test_encrypted_throwsAndCleansUp() async throws {
        let archive = try stage("encrypted.rar")
        await assertThrows(.encryptedUnsupported) { try await extractor.extract(archive: archive, intoParent: nil) }
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("encrypted").path))
    }

    func test_multiVolume_throws() async throws {
        let archive = try stage("multi.part0001.rar")
        await assertThrows(.multiVolumeUnsupported) { try await extractor.extract(archive: archive, intoParent: nil) }
        XCTAssertFalse(fm.fileExists(atPath: tmp.appendingPathComponent("multi").path))
    }

    func test_missingFile_throws() async {
        let archive = tmp.appendingPathComponent("nope.rar")
        await assertThrows(.archiveNotFound) { try await extractor.extract(archive: archive, intoParent: nil) }
    }

    func test_readOnlyParent_throws() async throws {
        let archive = try stage("basic5.rar")
        let ro = tmp.appendingPathComponent("ro")
        try fm.createDirectory(at: ro, withIntermediateDirectories: false)
        try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: ro.path)
        await assertThrows(.destinationNotWritable) { try await extractor.extract(archive: archive, intoParent: ro) }
    }
}

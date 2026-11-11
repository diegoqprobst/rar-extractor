import XCTest
@testable import RarExtractorCore

final class DestinationResolverTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("DestResolver-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tmp)
    }

    func test_baseName_stripsRarExtension() {
        XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/Fotos.rar")), "Fotos")
    }

    func test_baseName_stripsPartSuffix() {
        XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/Fotos.part01.rar")), "Fotos")
    }

    func test_baseName_isCaseInsensitive() {
        XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/A.PART2.RAR")), "A")
    }

    func test_baseName_keepsInnerDots() {
        XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/v1.2.rar")), "v1.2")
    }

    func test_unique_returnsSiblingWhenFree() {
        let archive = tmp.appendingPathComponent("Fotos.rar")
        XCTAssertEqual(DestinationResolver.uniqueDestination(for: archive).path,
                       tmp.appendingPathComponent("Fotos").path)
    }

    func test_unique_appendsNumberWhenTaken() throws {
        let fm = FileManager.default
        try fm.createDirectory(at: tmp.appendingPathComponent("Fotos"), withIntermediateDirectories: false)
        try fm.createDirectory(at: tmp.appendingPathComponent("Fotos 2"), withIntermediateDirectories: false)
        let archive = tmp.appendingPathComponent("Fotos.rar")
        XCTAssertEqual(DestinationResolver.uniqueDestination(for: archive).path,
                       tmp.appendingPathComponent("Fotos 3").path)
    }

    func test_unique_usesCustomParent() {
        let other = tmp.appendingPathComponent("otra")
        let archive = tmp.appendingPathComponent("Fotos.rar")
        XCTAssertEqual(DestinationResolver.uniqueDestination(for: archive, in: other).path,
                       other.appendingPathComponent("Fotos").path)
    }
}

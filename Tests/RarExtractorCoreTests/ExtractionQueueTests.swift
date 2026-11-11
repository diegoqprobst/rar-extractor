import XCTest
@testable import RarExtractorCore

/// Extractor falso: registra la concurrencia máxima y los parents recibidos.
private actor Recorder {
    var running = 0
    var maxRunning = 0
    var parents: [URL?] = []

    func begin(parent: URL?) { running += 1; maxRunning = max(maxRunning, running); parents.append(parent) }
    func end() { running -= 1 }
}

private struct FakeExtractor: Extracting {
    let recorder = Recorder()
    var failures: [String: ExtractionError] = [:]

    func extract(archive: URL, intoParent parent: URL?) async throws -> URL {
        await recorder.begin(parent: parent)
        try? await Task.sleep(nanoseconds: 20_000_000)
        await recorder.end()
        if let error = failures[archive.lastPathComponent] { throw error }
        return URL(fileURLWithPath: "/out").appendingPathComponent(DestinationResolver.baseName(for: archive))
    }
}

@MainActor
final class ExtractionQueueTests: XCTestCase {
    private func url(_ name: String) -> URL { URL(fileURLWithPath: "/in/\(name)") }

    private func waitUntilIdle(_ queue: ExtractionQueue, timeout: TimeInterval = 5) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while queue.jobs.contains(where: { $0.state == .waiting || $0.state == .running }) {
            if Date() > deadline { XCTFail("La cola no terminó"); return }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    func test_runsSequentially() async throws {
        let fake = FakeExtractor()
        let queue = ExtractionQueue(extractor: fake)
        queue.enqueue([url("a.rar"), url("b.rar"), url("c.rar")])
        try await waitUntilIdle(queue)
        let maxRunning = await fake.recorder.maxRunning
        XCTAssertEqual(maxRunning, 1)
        XCTAssertEqual(queue.jobs.map(\.state), [
            .done(URL(fileURLWithPath: "/out/a")), .done(URL(fileURLWithPath: "/out/b")), .done(URL(fileURLWithPath: "/out/c")),
        ])
    }

    func test_enqueueWhileRunningStaysSequential() async throws {
        let fake = FakeExtractor()
        let queue = ExtractionQueue(extractor: fake)
        queue.enqueue([url("a.rar")])
        queue.enqueue([url("b.rar")])
        try await waitUntilIdle(queue)
        let maxRunning = await fake.recorder.maxRunning
        XCTAssertEqual(maxRunning, 1)
        XCTAssertEqual(queue.jobs.count, 2)
    }

    func test_failureDoesNotStopQueue() async throws {
        let fake = FakeExtractor(failures: ["b.rar": .encryptedUnsupported])
        let queue = ExtractionQueue(extractor: fake)
        queue.enqueue([url("a.rar"), url("b.rar"), url("c.rar")])
        try await waitUntilIdle(queue)
        XCTAssertEqual(queue.jobs.map(\.state), [
            .done(URL(fileURLWithPath: "/out/a")),
            .failed("Este RAR tiene contraseña. Esta versión no abre RAR protegidos."),
            .done(URL(fileURLWithPath: "/out/c")),
        ])
    }

    func test_ignoresNonRar() {
        let queue = ExtractionQueue(extractor: FakeExtractor())
        queue.enqueue([url("a.zip"), url("b.RAR")])
        XCTAssertEqual(queue.jobs.map(\.archive.lastPathComponent), ["b.RAR"])
    }

    func test_passesDestinationParent() async throws {
        let fake = FakeExtractor()
        let queue = ExtractionQueue(extractor: fake)
        let parent = URL(fileURLWithPath: "/elegida")
        queue.destinationParent = parent
        queue.enqueue([url("a.rar")])
        try await waitUntilIdle(queue)
        let parents = await fake.recorder.parents
        XCTAssertEqual(parents, [parent])
    }

    func test_onFinishedCalledOnlyOnSuccess() async throws {
        let queue = ExtractionQueue(extractor: FakeExtractor(failures: ["b.rar": .notAnArchive]))
        var finished: [URL] = []
        queue.onFinished = { finished.append($0) }
        queue.enqueue([url("a.rar"), url("b.rar")])
        try await waitUntilIdle(queue)
        XCTAssertEqual(finished, [URL(fileURLWithPath: "/out/a")])
    }

    func test_clearFinishedKeepsPending() async throws {
        let queue = ExtractionQueue(extractor: FakeExtractor(failures: ["b.rar": .notAnArchive]))
        queue.enqueue([url("a.rar"), url("b.rar")])
        try await waitUntilIdle(queue)
        queue.clearFinished()
        XCTAssertTrue(queue.jobs.isEmpty)
    }
}

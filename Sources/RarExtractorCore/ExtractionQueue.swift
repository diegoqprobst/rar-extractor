import Foundation

public enum JobState: Equatable, Sendable {
    case waiting
    case running
    case done(URL)
    /// Mensaje para mostrar al usuario (`ExtractionError.userMessage`).
    case failed(String)

    public var isFinished: Bool {
        switch self {
        case .done, .failed: true
        case .waiting, .running: false
        }
    }
}

public struct Job: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let archive: URL
    public var state: JobState
}

/// Cola que descomprime los archivos de uno en uno, en orden de llegada.
@MainActor
public final class ExtractionQueue: ObservableObject {
    @Published public private(set) var jobs: [Job] = []
    /// `nil` = junto a cada archivo.
    @Published public var destinationParent: URL?
    /// Se llama con la carpeta creada tras cada extracción correcta.
    public var onFinished: ((URL) -> Void)?

    private let extractor: Extracting
    private var worker: Task<Void, Never>?

    public init(extractor: Extracting) {
        self.extractor = extractor
    }

    /// Ignora todo lo que no termine en `.rar` (sin distinguir mayúsculas).
    public func enqueue(_ archives: [URL]) {
        let rars = archives.filter { $0.pathExtension.lowercased() == "rar" }
        guard !rars.isEmpty else { return }
        jobs += rars.map { Job(id: UUID(), archive: $0, state: .waiting) }
        startIfNeeded()
    }

    public func clearFinished() {
        jobs.removeAll { $0.state.isFinished }
    }

    /// Hay trabajos esperando o en marcha.
    public var isBusy: Bool {
        jobs.contains { !$0.state.isFinished }
    }

    /// Detiene la extracción en curso (el extractor borra su carpeta a medias)
    /// y marca como cancelado todo lo pendiente. Vuelve cuando ya no corre nada.
    public func cancelAll() async {
        let running = worker
        running?.cancel()
        for i in jobs.indices where !jobs[i].state.isFinished {
            jobs[i].state = .failed(Self.cancelledMessage)
        }
        await running?.value
    }

    static let cancelledMessage = "Cancelado."

    private func startIfNeeded() {
        guard worker == nil else { return }
        worker = Task { [weak self] in
            await self?.drain()
        }
    }

    private func drain() async {
        while !Task.isCancelled, let index = jobs.firstIndex(where: { $0.state == .waiting }) {
            let id = jobs[index].id
            let archive = jobs[index].archive
            let parent = destinationParent
            setState(.running, for: id)
            do {
                let dest = try await extractor.extract(archive: archive, intoParent: parent)
                setState(.done(dest), for: id)
                onFinished?(dest)
            } catch is CancellationError {
                setState(.failed(Self.cancelledMessage), for: id)
            } catch let error as ExtractionError {
                setState(.failed(error.userMessage), for: id)
            } catch {
                setState(.failed(ExtractionError.toolFailed(code: -1, message: error.localizedDescription).userMessage), for: id)
            }
        }
        worker = nil
    }

    /// Busca por id: `clearFinished()` puede mover índices mientras se extrae.
    private func setState(_ state: JobState, for id: UUID) {
        guard let i = jobs.firstIndex(where: { $0.id == id }) else { return }
        jobs[i].state = state
    }
}

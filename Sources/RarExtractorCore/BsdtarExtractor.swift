import Foundation

public protocol Extracting: Sendable {
    /// Extrae `archive` en una carpeta nueva dentro de `parent` (o junto al archivo si es `nil`)
    /// y devuelve esa carpeta. Si falla, no deja la carpeta creada.
    func extract(archive: URL, intoParent parent: URL?) async throws -> URL
}

/// Extrae con el `bsdtar` de macOS (libarchive), que lee RAR 4 y RAR 5.
/// Nunca se pasa `-P`: bsdtar rechaza así las rutas absolutas y con `..`.
public struct BsdtarExtractor: Extracting {
    public let toolURL: URL

    public init(toolURL: URL = URL(fileURLWithPath: "/usr/bin/bsdtar")) {
        self.toolURL = toolURL
    }

    public func extract(archive: URL, intoParent parent: URL?) async throws -> URL {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: archive.path, isDirectory: &isDir), !isDir.boolValue else {
            throw ExtractionError.archiveNotFound
        }
        let folder = parent ?? archive.deletingLastPathComponent()
        guard fm.isWritableFile(atPath: folder.path) else {
            throw ExtractionError.destinationNotWritable
        }

        let dest = try makeDestination(for: archive, in: folder, fm: fm)
        let (code, stderr) = try await run(arguments: ["-x", "-f", archive.path, "-C", dest.path])
        guard code == 0 else {
            try? fm.removeItem(at: dest)
            throw ExtractionError.classify(stderr: stderr, exitCode: code, archive: archive)
        }
        return dest
    }

    /// Reserva la carpeta creándola. Si otra extracción ganó la carrera, prueba el siguiente nombre.
    private func makeDestination(for archive: URL, in folder: URL, fm: FileManager) throws -> URL {
        for _ in 0..<100 {
            let candidate = DestinationResolver.uniqueDestination(for: archive, in: folder, fileManager: fm)
            do {
                try fm.createDirectory(at: candidate, withIntermediateDirectories: false)
                return candidate
            } catch CocoaError.fileWriteFileExists {
                continue
            } catch {
                throw ExtractionError.destinationNotWritable
            }
        }
        throw ExtractionError.destinationNotWritable
    }

    private func run(arguments: [String]) async throws -> (Int32, String) {
        let process = Process()
        process.executableURL = toolURL
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        let errPipe = Pipe()
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            throw ExtractionError.toolFailed(code: -1, message: "No se pudo ejecutar \(toolURL.path)")
        }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                // Leer hasta EOF antes de esperar: si stderr llena el pipe, bsdtar se bloquearía.
                let data = errPipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let text = String(decoding: data, as: UTF8.self)
                continuation.resume(returning: (process.terminationStatus, text))
            }
        }
    }
}

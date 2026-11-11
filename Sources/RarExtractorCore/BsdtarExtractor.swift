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
        let code: Int32, stderr: String
        do {
            (code, stderr) = try await run(arguments: ["-x", "-f", archive.path, "-C", dest.path])
        } catch {
            try? fm.removeItem(at: dest)
            throw error
        }
        if Task.isCancelled {
            try? fm.removeItem(at: dest)
            throw CancellationError()
        }
        guard code == 0 else {
            try? fm.removeItem(at: dest)
            throw ExtractionError.classify(stderr: stderr, exitCode: code, archive: archive)
        }
        return flattenSingleRootFolder(dest, in: folder, fm: fm)
    }

    /// Si el archivo trae todo dentro de una única carpeta (`Fotos.rar` → `Fotos/…`),
    /// evita `Fotos/Fotos/…`: esa carpeta sustituye a la de destino, con su propio nombre
    /// (numerado si ya existe). Si algo falla al mover, se deja tal cual: nunca se pierde nada.
    private func flattenSingleRootFolder(_ dest: URL, in folder: URL, fm: FileManager) -> URL {
        guard let items = try? fm.contentsOfDirectory(at: dest, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              items.count == 1,
              let inner = items.first,
              let values = try? inner.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]),
              values.isDirectory == true, values.isSymbolicLink != true
        else { return dest }

        let staging = folder.appendingPathComponent(".rarextractor-\(UUID().uuidString)", isDirectory: true)
        do {
            try fm.moveItem(at: inner, to: staging)
        } catch {
            return dest
        }
        do {
            try fm.removeItem(at: dest) // ya está vacía
            let final = DestinationResolver.uniqueURL(named: inner.lastPathComponent, in: folder, fileManager: fm)
            try fm.moveItem(at: staging, to: final)
            return final
        } catch {
            // Vuelta atrás: dejar el contenido donde estaba.
            try? fm.createDirectory(at: dest, withIntermediateDirectories: false)
            try? fm.moveItem(at: staging, to: inner)
            return dest
        }
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

        // Se termina cuando bsdtar salió Y stderr llegó a EOF. No se usa `waitUntilExit`:
        // depende del run loop del hilo y se colgaba tras `terminate()`.
        let group = DispatchGroup()
        let stderrBox = DataBox()
        group.enter()
        process.terminationHandler = { _ in group.leave() }

        do {
            try process.run()
        } catch {
            throw ExtractionError.toolFailed(code: -1, message: "No se pudo ejecutar \(toolURL.path)")
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            // Leer hasta EOF mientras corre: si stderr llena el pipe, bsdtar se bloquearía.
            stderrBox.data = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        // Cancelar la Task mata bsdtar (SIGTERM); el llamador borra la carpeta a medias.
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                group.notify(queue: .global(qos: .userInitiated)) {
                    let text = String(decoding: stderrBox.data, as: UTF8.self)
                    continuation.resume(returning: (process.terminationStatus, text))
                }
            }
        } onCancel: {
            process.terminate()
        }
    }
}

/// Lo escribe un solo hilo y se lee después de `group.notify`, que ordena los accesos.
private final class DataBox: @unchecked Sendable {
    var data = Data()
}

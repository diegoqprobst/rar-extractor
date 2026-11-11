import Foundation

/// Calcula la carpeta destino de una extracción: hermana del archivo,
/// con su nombre base, y numerada ("Fotos 2", "Fotos 3"…) si ya existe.
public enum DestinationResolver {
    /// `Fotos.rar` → `Fotos`, `Fotos.part01.rar` → `Fotos`.
    public static func baseName(for archive: URL) -> String {
        var name = archive.lastPathComponent
        if name.lowercased().hasSuffix(".rar") {
            name = String(name.dropLast(4))
        }
        if let range = name.range(of: #"\.part\d+$"#, options: [.regularExpression, .caseInsensitive]) {
            name.removeSubrange(range)
        }
        return name.isEmpty ? "Archivo" : name
    }

    /// `parent == nil` usa la carpeta donde está el archivo.
    public static func uniqueDestination(
        for archive: URL,
        in parent: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL {
        let folder = parent ?? archive.deletingLastPathComponent()
        let base = baseName(for: archive)
        var candidate = folder.appendingPathComponent(base, isDirectory: true)
        var n = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = folder.appendingPathComponent("\(base) \(n)", isDirectory: true)
            n += 1
        }
        return candidate
    }
}

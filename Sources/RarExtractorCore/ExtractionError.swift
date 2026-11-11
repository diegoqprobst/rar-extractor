import Foundation

public enum ExtractionError: Error, Equatable, Sendable {
    case archiveNotFound
    case notAnArchive
    case encryptedUnsupported
    case multiVolumeUnsupported
    case destinationNotWritable
    case toolFailed(code: Int32, message: String)

    public var userMessage: String {
        switch self {
        case .archiveNotFound: "No se encontró el archivo."
        case .notAnArchive: "Este archivo no es un RAR válido o está dañado."
        case .encryptedUnsupported: "Este RAR tiene contraseña. Esta versión no abre RAR protegidos."
        case .multiVolumeUnsupported: "Este RAR está dividido en partes. Esta versión no abre RAR multiparte."
        case .destinationNotWritable: "No se puede escribir en la carpeta de destino."
        case let .toolFailed(_, message): "No se pudo descomprimir: \(message)"
        }
    }

    /// Traduce un fallo de bsdtar. Usa las cabeceras del RAR porque, con datos
    /// cifrados o volúmenes sueltos, bsdtar solo dice "Inappropriate file type or format".
    static func classify(stderr: String, exitCode: Int32, archive: URL) -> ExtractionError {
        let err = stderr.lowercased()
        let info = RarInspector.inspect(archive)

        if err.contains("encryption") || err.contains("encrypted") || info?.isEncrypted == true {
            return .encryptedUnsupported
        }
        let name = archive.lastPathComponent
        let looksLikeVolume = name.range(of: #"\.part\d+\.rar$"#, options: [.regularExpression, .caseInsensitive]) != nil
            || name.range(of: #"\.r\d\d$"#, options: [.regularExpression, .caseInsensitive]) != nil
        if info?.isMultiVolume == true || looksLikeVolume {
            return .multiVolumeUnsupported
        }
        if info == nil || err.contains("unrecognized archive format") {
            return .notAnArchive
        }
        return .toolFailed(code: exitCode, message: stderr.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

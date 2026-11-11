import Foundation

public struct RarInfo: Equatable, Sendable {
    public var isEncrypted: Bool
    public var isMultiVolume: Bool

    public init(isEncrypted: Bool, isMultiVolume: Bool) {
        self.isEncrypted = isEncrypted
        self.isMultiVolume = isMultiVolume
    }
}

/// Lee las cabeceras de un RAR (4.x y 5.x) para saber si está cifrado o es multiparte.
/// bsdtar no lo dice de forma fiable: con datos cifrados devuelve errores de formato genéricos.
/// No valida CRCs ni descomprime nada; ante datos truncados devuelve lo que alcanzó a ver.
enum RarInspector {
    private static let sig4: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x00]
    private static let sig5: [UInt8] = [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07, 0x01, 0x00]
    private static let maxHeaders = 256

    /// `nil` si el archivo no existe o no empieza con una firma RAR.
    static func inspect(_ url: URL) -> RarInfo? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let reader = Reader(handle: handle)
        guard let head = reader.bytes(at: 0, count: 8) else { return nil }
        if head.count >= 8, Array(head.prefix(8)) == sig5 {
            return inspect5(reader)
        }
        if head.count >= 7, Array(head.prefix(7)) == sig4 {
            return inspect4(reader)
        }
        return nil
    }

    // MARK: RAR 1.5–4.x

    private static func inspect4(_ r: Reader) -> RarInfo {
        var info = RarInfo(isEncrypted: false, isMultiVolume: false)
        var offset: UInt64 = 7
        for _ in 0..<maxHeaders {
            guard let h = r.bytes(at: offset, count: 7), h.count == 7 else { break }
            let type = h[2]
            let flags = UInt16(h[3]) | UInt16(h[4]) << 8
            let size = UInt64(UInt16(h[5]) | UInt16(h[6]) << 8)
            guard size >= 7 else { break }

            var addSize: UInt64 = 0
            if type == 0x74 || flags & 0x8000 != 0 {
                guard let a = r.bytes(at: offset + 7, count: 4), a.count == 4 else { break }
                addSize = a.enumerated().reduce(0) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
                if type == 0x74, flags & 0x0100 != 0,
                   let hi = r.bytes(at: offset + 32, count: 4), hi.count == 4 {
                    let high = hi.enumerated().reduce(UInt64(0)) { $0 | UInt64($1.element) << (8 * UInt64($1.offset)) }
                    addSize |= high << 32
                }
            }

            switch type {
            case 0x73: // cabecera principal
                if flags & 0x0001 != 0 { info.isMultiVolume = true }
                if flags & 0x0080 != 0 { info.isEncrypted = true; return info } // cabeceras cifradas
            case 0x74: // archivo
                if flags & 0x0004 != 0 { info.isEncrypted = true }
                return info // con la primera entrada basta
            case 0x7B: // fin del archivo
                return info
            default:
                break
            }
            let (next, overflow) = offset.addingReportingOverflow(size + addSize)
            guard !overflow else { break }
            offset = next
        }
        return info
    }

    // MARK: RAR 5.x

    private static func inspect5(_ r: Reader) -> RarInfo {
        var info = RarInfo(isEncrypted: false, isMultiVolume: false)
        var offset: UInt64 = 8
        for _ in 0..<maxHeaders {
            // CRC32 (4) + tamaño de cabecera (vint, hasta 3 bytes según la especificación)
            guard let pre = r.bytes(at: offset + 4, count: 10) else { break }
            var p = VintParser(bytes: pre)
            guard let headerSize = p.next(), headerSize > 0, headerSize <= 2 * 1024 * 1024 else { break }
            let headerStart = offset + 4 + UInt64(p.index)
            guard let header = r.bytes(at: headerStart, count: Int(headerSize)),
                  header.count == Int(headerSize) else { break }

            var hp = VintParser(bytes: header)
            guard let type = hp.next(), let flags = hp.next() else { break }
            let extraSize = flags & 0x1 != 0 ? hp.next() : 0
            let dataSize = flags & 0x2 != 0 ? hp.next() : 0
            guard let extraSize, let dataSize else { break }

            switch type {
            case 1: // principal
                if let archiveFlags = hp.next(), archiveFlags & 0x1 != 0 { info.isMultiVolume = true }
            case 2: // archivo
                if extraSize > 0, extraSize <= headerSize {
                    let extra = Array(header.suffix(Int(extraSize)))
                    if hasEncryptionRecord(extra) { info.isEncrypted = true }
                }
                return info
            case 4: // cabecera de cifrado del archivo entero
                info.isEncrypted = true
                return info
            case 5: // fin
                return info
            default:
                break
            }
            // dataSize es un vint sin límite: un archivo corrupto puede desbordar la suma.
            let (afterHeader, o1) = headerStart.addingReportingOverflow(headerSize)
            let (next, o2) = afterHeader.addingReportingOverflow(dataSize)
            guard !o1, !o2 else { break }
            offset = next
        }
        return info
    }

    private static func hasEncryptionRecord(_ extra: [UInt8]) -> Bool {
        var p = VintParser(bytes: extra)
        while p.index < extra.count {
            guard let size = p.next(), size > 0 else { return false }
            let recordStart = p.index
            guard let type = p.next() else { return false }
            if type == 1 { return true }
            guard size <= UInt64(extra.count - recordStart) else { return false }
            p.index = recordStart + Int(size)
        }
        return false
    }
}

private struct Reader {
    let handle: FileHandle

    func bytes(at offset: UInt64, count: Int) -> [UInt8]? {
        guard (try? handle.seek(toOffset: offset)) != nil,
              let data = try? handle.read(upToCount: count) else { return nil }
        return [UInt8](data)
    }
}

/// Entero de longitud variable de RAR5: 7 bits por byte, el bit alto indica que sigue otro byte.
private struct VintParser {
    let bytes: [UInt8]
    var index = 0

    init(bytes: [UInt8]) { self.bytes = bytes }

    mutating func next() -> UInt64? {
        var value: UInt64 = 0
        var shift: UInt64 = 0
        while index < bytes.count, shift < 64 {
            let b = bytes[index]
            index += 1
            value |= UInt64(b & 0x7F) << shift
            if b & 0x80 == 0 { return value }
            shift += 7
        }
        return nil
    }
}

import Foundation

/// Fixtures RAR tomados de libarchive v3.7.4 (libarchive/test/*.rar.uu, decodificados).
///
/// Salida real de bsdtar 3.5.3 / libarchive 3.7.4 (macOS 26.6.2):
/// - basic.rar (RAR 2.x): test.txt, testlink -> test.txt, testdir/, testdir/test.txt, testemptydir/. Exit 0.
/// - basic5.rar (RAR5): helloworld.txt. Exit 0.
/// - encrypted.rar (datos cifrados, cabeceras no): exit 1,
///   "foo.txt: Prefix found: Inappropriate file type or format". No menciona el cifrado.
/// - encrypted_header.rar (cabeceras cifradas): exit 1, "bsdtar: RAR encryption support unavailable."
/// - multi.part0001.rar (primer volumen de un multiparte): exit 1,
///   "ppmd_lzss_conversion_test.txt: Bad RAR file data: Inappropriate file type or format"
/// - notrar.rar ("hola\n"): exit 1, "bsdtar: Error opening archive: Unrecognized archive format"
enum Fixture {
    static func url(_ name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: base, withExtension: ext, subdirectory: "Fixtures") else {
            fatalError("Falta el fixture \(name)")
        }
        return url
    }
}

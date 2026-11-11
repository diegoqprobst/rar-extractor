# RarExtractor: plan de implementación

> **Para agentes:** SUB-SKILL REQUERIDA: usa superpowers:subagent-driven-development (recomendado) o superpowers:executing-plans para implementar este plan tarea por tarea. Los pasos usan checkboxes (`- [ ]`) para el seguimiento.

**Objetivo:** una app nativa de macOS que descomprime archivos `.rar` arrastrándolos a la ventana o al Dock, o con doble clic en Finder.

**Arquitectura:** un paquete SwiftPM con una librería `RarExtractorCore`, testeable y sin UI, que ejecuta `/usr/bin/bsdtar` con `Process` y traduce sus errores a mensajes en español. Encima va un ejecutable SwiftUI `RarExtractor`, empaquetado como `.app` con `build.sh` (el mismo patrón que `~/code/notch-player`, sin `.xcodeproj`).

**Stack:** Swift 5.10+, SwiftUI, AppKit (`NSApplicationDelegate`, `NSWorkspace`, `NSOpenPanel`), XCTest, `bsdtar 3.5.3 / libarchive 3.7.4` del sistema.

**Spec:** no hay documento aparte. Las decisiones salen de la conversación del 2026-11-11 y están fijadas en «Decisiones del spec».

## Decisiones del spec

- Motor: solo `/usr/bin/bsdtar`. No hay RAR con contraseña ni RAR multiparte en esta versión. Si aparecen, se muestra un mensaje claro, nunca un fallo silencioso.
- Destino por defecto: una carpeta hermana del archivo con su nombre base (`Fotos.rar` → `Fotos/`, `Fotos.part1.rar` → `Fotos/`). Si ya existe, se usa `Fotos 2`, `Fotos 3`… (como Finder).
- Botón «Elegir carpeta…» (`NSOpenPanel`) para cambiar la carpeta padre del destino durante la sesión. No se persiste.
- Si la extracción falla, se borra la carpeta de destino que creó la app. Nunca se dejan restos a medias.
- Al terminar bien, se revela la carpeta en Finder.
- Varios archivos a la vez: se encolan y se procesan de uno en uno.
- Sin sandbox; firma ad-hoc, como notch-player.

## Restricciones globales

- `platforms: [.macOS(.v14)]`, `swift-tools-version: 5.10`.
- Bundle id: `com.diego.rarextractor`. Nombre visible: `RarExtractor`.
- Ruta del proyecto: `/Users/diego/code/rar-extractor`.
- Toda la UI y los mensajes de error, en español, con el texto exacto de la tabla de la Tarea 2.
- Sin dependencias externas de SwiftPM.
- UTI que se declara para abrir: `com.rarlab.rar-archive`, extensión `rar`.

## Puntos de revisión

1. **Nombres con espacios, acentos y emoji** (`Mis fotos ñ 🎉.rar`): se extraen bien. Los argumentos van a `Process` como array, nunca por shell. → test en la Tarea 3.
2. **Archivo con rutas `../` (zip-slip)**: nada se escribe fuera del destino. bsdtar lo bloquea por defecto. Nunca se pasa `-P`. → test en la Tarea 3.
3. **Destino ya existente**: no se mezcla ni se sobrescribe nada; se crea `Nombre 2`. → test en la Tarea 1.
4. **Archivo con extensión `.rar` que no es RAR** (por ejemplo, un PDF renombrado): error `notAnArchive` y no queda ninguna carpeta. → test en la Tarea 3.
5. **Carpeta padre de solo lectura**: error `destinationNotWritable` antes de lanzar bsdtar. → test en la Tarea 3.

---

## Estructura de archivos

```
rar-extractor/
  Package.swift
  build.sh
  Resources/Info.plist
  Sources/RarExtractorCore/
    DestinationResolver.swift   # calcula la carpeta destino única
    ExtractionError.swift       # errores + mensajes en español
    BsdtarExtractor.swift       # protocolo Extracting + implementación con Process
    ExtractionQueue.swift       # cola secuencial observable (@MainActor)
  Sources/RarExtractor/
    RarExtractorApp.swift       # @main, AppDelegate (abrir desde Finder/Dock)
    ContentView.swift           # zona de soltar + lista de trabajos
  Tests/RarExtractorCoreTests/
    Fixtures/                   # .rar de prueba de libarchive v3.7.4
    DestinationResolverTests.swift
    BsdtarExtractorTests.swift
    ExtractionQueueTests.swift
```

---

### Tarea 1: Esqueleto del paquete y `DestinationResolver`

**Archivos:**
- Crear: `Package.swift`, `.gitignore` (`.build/`, `build/`), `Sources/RarExtractorCore/DestinationResolver.swift`
- Test: `Tests/RarExtractorCoreTests/DestinationResolverTests.swift`

**Interfaces:**
- Produce: `public enum DestinationResolver { public static func baseName(for archive: URL) -> String; public static func uniqueDestination(for archive: URL, in parent: URL? = nil, fileManager: FileManager = .default) -> URL }`. `parent == nil` quiere decir la carpeta del archivo.

- [ ] **Paso 1:** `git init` en `/Users/diego/code/rar-extractor`. Crear `Package.swift` con los productos `RarExtractorCore` (library), `RarExtractor` (executableTarget, depende de Core) y `RarExtractorCoreTests` (testTarget, `resources: [.copy("Fixtures")]`). Crear una carpeta `Fixtures/` vacía con un `.gitkeep`.
- [ ] **Paso 2: escribir los tests que fallan**

```swift
func test_baseName_stripsRarExtension()      { XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/Fotos.rar")), "Fotos") }
func test_baseName_stripsPartSuffix()        { XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/Fotos.part01.rar")), "Fotos") }
func test_baseName_isCaseInsensitive()       { XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/A.PART2.RAR")), "A") }
func test_baseName_keepsInnerDots()          { XCTAssertEqual(DestinationResolver.baseName(for: URL(fileURLWithPath: "/t/v1.2.rar")), "v1.2") }
func test_unique_returnsSiblingWhenFree()    // tmp/Fotos.rar → tmp/Fotos
func test_unique_appendsNumberWhenTaken()    // existe tmp/Fotos y tmp/Fotos 2 → tmp/Fotos 3
func test_unique_usesCustomParent()          // parent = tmp/otra → tmp/otra/Fotos
```

Cada test que toca disco usa su propia carpeta en `FileManager.default.temporaryDirectory` y la borra en `tearDown`.

- [ ] **Paso 3:** `swift test --filter DestinationResolverTests` → falla porque `DestinationResolver` no existe.
- [ ] **Paso 4:** implementar. Para `baseName`, quitar `.rar` y luego la regex `\.part\d+$` (sin distinguir mayúsculas). Para `uniqueDestination`, probar `name`, luego `name 2`, `name 3`… con `fileExists(atPath:)`.
- [ ] **Paso 5:** `swift test --filter DestinationResolverTests` → PASS.
- [ ] **Paso 6:** commit `feat: paquete base y DestinationResolver`.

---

### Tarea 2: Fixtures y mapa de errores de bsdtar

**Archivos:**
- Crear: `Tests/RarExtractorCoreTests/Fixtures/*.rar`, `Sources/RarExtractorCore/ExtractionError.swift`
- Test: `Tests/RarExtractorCoreTests/BsdtarExtractorTests.swift` (solo los tests de mensajes)

**Interfaces:**
- Produce:
  ```swift
  public enum ExtractionError: Error, Equatable {
    case archiveNotFound, notAnArchive, encryptedUnsupported,
         multiVolumeUnsupported, destinationNotWritable
    case toolFailed(code: Int32, message: String)
    public var userMessage: String { get }
    static func classify(stderr: String, exitCode: Int32, archive: URL) -> ExtractionError
  }
  ```

| Caso | `userMessage` exacto |
|---|---|
| `archiveNotFound` | `No se encontró el archivo.` |
| `notAnArchive` | `Este archivo no es un RAR válido o está dañado.` |
| `encryptedUnsupported` | `Este RAR tiene contraseña. Esta versión no abre RAR protegidos.` |
| `multiVolumeUnsupported` | `Este RAR está dividido en partes. Esta versión no abre RAR multiparte.` |
| `destinationNotWritable` | `No se puede escribir en la carpeta de destino.` |
| `toolFailed(_, m)` | `No se pudo descomprimir: \(m)` |

- [ ] **Paso 1:** en una carpeta vacía del scratchpad, descargar desde `https://raw.githubusercontent.com/libarchive/libarchive/v3.7.4/libarchive/test/` estos archivos: `test_read_format_rar.rar.uu`, `test_read_format_rar5_stored.rar.uu`, `test_read_format_rar_encryption_data.rar.uu`, `test_read_format_rar_multivolume.part0001.rar.uu`. Decodificarlos con `uudecode -o` y copiar a `Fixtures/` con estos nombres: `basic.rar`, `basic5.rar`, `encrypted.rar`, `multi.part0001.rar`. Si un nombre no existe en ese tag, buscar el equivalente en el listado de `libarchive/test/` del mismo tag y anotarlo en el commit.
- [ ] **Paso 2:** ejecutar `bsdtar -tf` sobre cada fixture y `bsdtar -xf … -C <tmp>` sobre `encrypted.rar`, `multi.part0001.rar` y un `notrar.rar` (`echo hola > notrar.rar`). Anotar en un comentario al inicio de `BsdtarExtractorTests.swift` el código de salida, el stderr literal y la lista de entradas de `basic.rar` y `basic5.rar`. Esos valores mandan en `classify` y en los tests de la Tarea 3.
- [ ] **Paso 3: tests que fallan**: `test_classify_encrypted`, `test_classify_notAnArchive` y `test_classify_multiVolume`. Cada uno pasa el stderr literal capturado en el paso 2 y comprueba el caso esperado. `test_classify_multiVolume` usa el nombre `x.part0001.rar`. Añadir `test_classify_unknownFallsBackToToolFailed` (stderr `"boom"`, código 1 → `.toolFailed(code: 1, message: "boom")`) y `test_userMessages_matchTable`, que compara los seis textos de la tabla.
- [ ] **Paso 4:** `swift test --filter BsdtarExtractorTests` → FAIL.
- [ ] **Paso 5:** implementar `classify` buscando subcadenas, sin distinguir mayúsculas, del stderr capturado. El orden es: cifrado, luego multiparte (por stderr o porque el nombre cumple `\.part\d+\.rar$` o `\.r\d\d$`), luego «no es archivo»; si nada encaja, `toolFailed`.
- [ ] **Paso 6:** tests → PASS. Commit `feat: fixtures RAR y ExtractionError`.

---

### Tarea 3: `BsdtarExtractor`

**Archivos:**
- Crear: `Sources/RarExtractorCore/BsdtarExtractor.swift`
- Test: `Tests/RarExtractorCoreTests/BsdtarExtractorTests.swift` (ampliar)

**Interfaces:**
- Consume: `DestinationResolver.uniqueDestination`, `ExtractionError.classify`
- Produce:
  ```swift
  public protocol Extracting: Sendable {
    func extract(archive: URL, intoParent parent: URL?) async throws -> URL  // devuelve la carpeta creada
  }
  public struct BsdtarExtractor: Extracting {
    public init(toolURL: URL = URL(fileURLWithPath: "/usr/bin/bsdtar"), fileManager: FileManager = .default)
  }
  ```

- [ ] **Paso 1: tests que fallan** (cada uno en su propia carpeta temporal):
  - `test_extractsRar4`: `basic.rar` → la carpeta devuelta contiene exactamente las entradas anotadas en la Tarea 2.
  - `test_extractsRar5`: lo mismo con `basic5.rar`.
  - `test_unicodeAndSpacesInName`: copia `basic.rar` como `Mis fotos ñ 🎉.rar` → crea `Mis fotos ñ 🎉/` con el contenido.
  - `test_zipSlipStaysInside`: crea `slip.rar` copiando un zip con la entrada `../escape.txt`, hecho con `python3 -I -c "import zipfile; zipfile.ZipFile(p,'w').writestr('../escape.txt','x')"`. Después de `extract`, haya éxito o error, `parent/escape.txt` no existe.
  - `test_notAnArchive_throwsAndCleansUp`: `notrar.rar` → lanza `.notAnArchive` y no queda la carpeta `notrar/`.
  - `test_encrypted_throws`: lanza `.encryptedUnsupported` y no queda carpeta.
  - `test_missingFile_throws`: lanza `.archiveNotFound`.
  - `test_readOnlyParent_throws`: parent con permisos `0o555` → lanza `.destinationNotWritable`. Restaurar `0o755` en `tearDown`.
- [ ] **Paso 2:** `swift test --filter BsdtarExtractorTests` → FAIL.
- [ ] **Paso 3:** implementar `extract`. Primero las comprobaciones: el archivo existe y `isWritableFile(atPath: parent)`. Luego `uniqueDestination`, `createDirectory` y `Process` con `executableURL = toolURL` y `arguments = ["-x", "-f", archive.path, "-C", dest.path]`. Leer stderr con un `Pipe` y esperar con `withCheckedThrowingContinuation` + `terminationHandler`. Si el código no es 0, `removeItem(dest)` y lanzar `classify(...)`.
- [ ] **Paso 4:** tests → PASS. Commit `feat: BsdtarExtractor con limpieza en errores`.

---

### Tarea 4: `ExtractionQueue`

**Archivos:**
- Crear: `Sources/RarExtractorCore/ExtractionQueue.swift`
- Test: `Tests/RarExtractorCoreTests/ExtractionQueueTests.swift`

**Interfaces:**
- Consume: `Extracting`
- Produce:
  ```swift
  public enum JobState: Equatable { case waiting, running, done(URL), failed(String) }  // String = userMessage
  public struct Job: Identifiable, Equatable { public let id: UUID; public let archive: URL; public var state: JobState }
  @MainActor public final class ExtractionQueue: ObservableObject {
    @Published public private(set) var jobs: [Job]
    public var destinationParent: URL?            // nil = junto al archivo
    public var onFinished: ((URL) -> Void)?       // la app lo usa para revelar en Finder
    public init(extractor: Extracting)
    public func enqueue(_ archives: [URL])        // ignora lo que no termina en .rar (sin distinguir mayúsculas)
    public func clearFinished()
  }
  ```

- [ ] **Paso 1: tests que fallan**, con un `FakeExtractor` (actor) que registra cuántos trabajos corren a la vez y devuelve un resultado por archivo:
  - `test_runsSequentially`: 3 archivos → concurrencia máxima registrada = 1, y los tres terminan en `.done`.
  - `test_failureDoesNotStopQueue`: el segundo lanza `.encryptedUnsupported` → el estado es `[.done, .failed("Este RAR tiene contraseña. Esta versión no abre RAR protegidos."), .done]`.
  - `test_ignoresNonRar`: `enqueue([a.zip, b.RAR])` → hay 1 trabajo.
  - `test_passesDestinationParent` y `test_onFinishedCalledOnlyOnSuccess`.
- [ ] **Paso 2:** `swift test --filter ExtractionQueueTests` → FAIL.
- [ ] **Paso 3:** implementar con una sola `Task` que procesa mientras haya trabajos en `.waiting`, sin lanzar otra si ya está corriendo.
- [ ] **Paso 4:** tests → PASS. Commit `feat: cola secuencial de extracción`.

---

### Tarea 5: App SwiftUI, Info.plist y build.sh

**Archivos:**
- Crear: `Sources/RarExtractor/RarExtractorApp.swift`, `Sources/RarExtractor/ContentView.swift`, `Resources/Info.plist`, `build.sh`

**Interfaces:**
- Consume: `ExtractionQueue`, `BsdtarExtractor`, `Job`, `JobState`

- [ ] **Paso 1:** `Info.plist` con `CFBundleIdentifier com.diego.rarextractor`, `CFBundleExecutable RarExtractor`, `LSMinimumSystemVersion 14.0`, y `CFBundleDocumentTypes` con un tipo `RAR` (`LSItemContentTypes = [com.rarlab.rar-archive]`, `CFBundleTypeRole = Viewer`, `LSHandlerRank = Alternate`). Añadir `UTImportedTypeDeclarations` para `com.rarlab.rar-archive` (conforma a `public.data` y `public.archive`, extensión `rar`).
- [ ] **Paso 2:** `RarExtractorApp`: `@main` con `WindowGroup`, una sola ventana de 420×320 y `@NSApplicationDelegateAdaptor`. El `AppDelegate` implementa `application(_:open urls:)` → `queue.enqueue(urls)`. Así funcionan el doble clic en Finder y soltar el archivo en el Dock. `queue.onFinished = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }`.
- [ ] **Paso 3:** `ContentView`:
  - Zona `.dropDestination(for: URL.self)` con el texto «Suelta aquí archivos .rar».
  - Lista de `jobs` con el nombre del archivo y su estado: `ProgressView` pequeño si está en marcha, ✓ si terminó, y el texto del error en rojo si falló.
  - Pie con «Destino: junto al archivo» o la ruta elegida, y los botones «Elegir carpeta…», «Junto al archivo» y «Limpiar».
- [ ] **Paso 4:** `build.sh` copiado del patrón de notch-player, sin la parte de launchd ni `pkill`: `swift build -c release`, armar `build/RarExtractor.app` y `codesign --force --sign - --identifier com.diego.rarextractor`.
- [ ] **Paso 5: verificación manual**, ejecutando `./build.sh && open build/RarExtractor.app`:
  - Soltar `Fixtures/basic.rar` en la ventana → se crea `basic/` y Finder la revela.
  - Soltarlo otra vez → se crea `basic 2/`.
  - Soltar `encrypted.rar` → aparece el mensaje de contraseña en rojo.
  - Clic derecho en un `.rar` en Finder → Abrir con → RarExtractor → se extrae. Si no aparece en la lista, ejecutar `/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f build/RarExtractor.app`.
- [ ] **Paso 6:** `swift test` completo → PASS. Commit `feat: app SwiftUI RarExtractor`.

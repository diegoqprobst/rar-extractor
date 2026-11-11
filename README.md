# RarExtractor

App nativa y ligera para macOS que descomprime archivos `.rar`. Arrastras el archivo a la ventana o al icono del Dock, o lo abres con doble clic, y aparece una carpeta con su contenido al lado.

- RAR 4 y RAR 5, sin instalar nada más: usa el `bsdtar` (libarchive) que ya trae macOS.
- Si el RAR ya trae su propia carpeta, no crea otra encima (`Fotos.rar` → `Fotos/…`, no `Fotos/Fotos/…`).
- Nunca sobrescribe: si la carpeta ya existe, crea `Fotos 2`, `Fotos 3`…
- Si algo falla, no deja archivos a medias.
- Varios archivos a la vez se descomprimen en cola, uno detrás de otro.
- Funciona en Apple Silicon y en Mac Intel, con macOS 14 o posterior.

**No abre** RAR con contraseña ni RAR divididos en partes (`.part1.rar`, `.r00`): en esos casos muestra un aviso claro.

## Descargar e instalar

1. Descarga `RarExtractor.zip` desde [Releases](../../releases/latest).
2. Descomprímelo y mueve `RarExtractor.app` a **Aplicaciones**.
3. La primera vez, macOS la bloquea porque no está firmada por un desarrollador de Apple:
   - Ábrela y, cuando salga el aviso, pulsa **Aceptar**.
   - Ve a **Ajustes del Sistema → Privacidad y seguridad**, baja hasta "RarExtractor se bloqueó…" y pulsa **Abrir igualmente**.

   O, desde Terminal:

   ```bash
   xattr -dr com.apple.quarantine /Applications/RarExtractor.app
   ```

Para que se abra con doble clic, en Finder haz clic derecho en un `.rar` → **Obtener información** → **Abrir con: RarExtractor** → **Cambiar todo…**.

## Compilar desde el código

Necesitas Xcode (o las Command Line Tools con Swift 5.10 o posterior).

```bash
./build.sh            # crea build/RarExtractor.app
./build.sh release zip  # además, crea build/RarExtractor.zip
swift test            # ejecuta las pruebas
```

## Créditos

Los archivos de prueba de `Tests/RarExtractorCoreTests/Fixtures/` vienen de la suite de pruebas de [libarchive](https://github.com/libarchive/libarchive) v3.7.4 (licencia BSD de 2 cláusulas).

## Licencia

MIT. Ver [LICENSE](LICENSE).

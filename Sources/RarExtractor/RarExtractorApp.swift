import AppKit
import RarExtractorCore
import SwiftUI

@main
struct RarExtractorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        // `Window` (no `WindowGroup`): una sola ventana aunque se abran varios archivos desde Finder.
        Window("RarExtractor", id: "main") {
            ContentView(queue: appDelegate.queue)
                .frame(minWidth: 420, minHeight: 320)
        }
        .defaultSize(width: 420, height: 320)
        .windowResizability(.contentMinSize)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let queue = ExtractionQueue(extractor: BsdtarExtractor())

    override init() {
        super.init()
        queue.onFinished = { folder in
            NSWorkspace.shared.activateFileViewerSelecting([folder])
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Un ejecutable de SwiftPM arranca como proceso de fondo; esto le da Dock y menú.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    /// Doble clic en Finder, "Abrir con…" o soltar archivos sobre el icono del Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        queue.enqueue(urls)
    }
}

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

    /// Con un único `Window`, SwiftUI cerraría la app al cerrar la ventana y perdería la cola.
    /// La app sigue viva; un clic en el Dock vuelve a abrir la ventana.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Al salir con trabajos pendientes se pregunta. Si el usuario confirma, se mata bsdtar
    /// y se borra la carpeta a medias antes de cerrar: nunca quedan restos.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard queue.isBusy else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Hay archivos descomprimiéndose"
        alert.informativeText = "Si sales ahora, se cancelarán y no quedará nada a medias."
        alert.addButton(withTitle: "Seguir descomprimiendo")
        alert.addButton(withTitle: "Salir")
        guard alert.runModal() == .alertSecondButtonReturn else { return .terminateCancel }
        Task { @MainActor in
            await queue.cancelAll()
            NSApp.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    /// Doble clic en Finder, "Abrir con…" o soltar archivos sobre el icono del Dock.
    func application(_ application: NSApplication, open urls: [URL]) {
        queue.enqueue(urls)
    }
}

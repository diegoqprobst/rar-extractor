import AppKit
import RarExtractorCore
import SwiftUI

struct ContentView: View {
    @ObservedObject var queue: ExtractionQueue
    @State private var isTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            dropZone
                .padding(16)
            if !queue.jobs.isEmpty {
                Divider()
                jobList
            }
            Divider()
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
    }

    private var dropZone: some View {
        RoundedRectangle(cornerRadius: 12)
            .strokeBorder(style: StrokeStyle(lineWidth: 2, dash: [6]))
            .foregroundStyle(isTargeted ? Color.accentColor : Color.secondary.opacity(0.5))
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isTargeted ? Color.accentColor.opacity(0.08) : Color.clear)
            )
            .overlay {
                VStack(spacing: 8) {
                    Image(systemName: "archivebox")
                        .font(.system(size: 32))
                        .foregroundStyle(.secondary)
                    Text("Suelta aquí archivos .rar")
                        .font(.headline)
                }
            }
            .frame(minHeight: 120)
            .dropDestination(for: URL.self) { urls, _ in
                queue.enqueue(urls)
                return true
            } isTargeted: { isTargeted = $0 }
    }

    private var jobList: some View {
        List(queue.jobs) { job in
            HStack(spacing: 8) {
                stateIcon(job.state)
                    .frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(job.archive.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if case let .failed(message) = job.state {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
                Spacer()
                if case let .done(folder) = job.state {
                    Button("Mostrar") {
                        NSWorkspace.shared.activateFileViewerSelecting([folder])
                    }
                    .buttonStyle(.link)
                }
            }
        }
        .listStyle(.inset)
        .frame(minHeight: 100)
    }

    @ViewBuilder
    private func stateIcon(_ state: JobState) -> some View {
        switch state {
        case .waiting:
            Image(systemName: "clock").foregroundStyle(.secondary)
        case .running:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(destinationLabel)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Button("Elegir carpeta…", action: chooseFolder)
            if queue.destinationParent != nil {
                Button("Junto al archivo") { queue.destinationParent = nil }
            }
            Button("Limpiar") { queue.clearFinished() }
                .disabled(!queue.jobs.contains { $0.state.isFinished })
        }
        .controlSize(.small)
    }

    private var destinationLabel: String {
        if let parent = queue.destinationParent {
            return "Destino: \(parent.path)"
        }
        return "Destino: junto al archivo"
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Elegir"
        if panel.runModal() == .OK, let url = panel.url {
            queue.destinationParent = url
        }
    }
}

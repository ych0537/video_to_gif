import AppKit
import SwiftUI
import UniformTypeIdentifiers
import VideoToGifCore

@main
struct VideoToGifMacApp: App {
    var body: some Scene {
        WindowGroup("Video2GIF") {
            ContentView()
                .frame(width: 760, height: 580)
        }
    }
}

struct ContentView: View {
    @State private var inputURL: URL?
    @State private var outputURL: URL?
    @State private var width = 800
    @State private var fps = 10
    @State private var start = 0.0
    @State private var duration = 0.0
    @State private var isConverting = false
    @State private var isPaused = false
    @State private var conversionFinished = false
    @State private var controller: ConversionController?
    @State private var progress = 0.0
    @State private var status = "Ready"
    @State private var logLines: [String] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            fileSection
            settingsSection
            progressSection
            Spacer(minLength: 0)
            actionBar
        }
        .padding(24)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Video2GIF")
                    .font(.system(size: 28, weight: .semibold))
                Text("Convert local videos up to 1 GB into shareable GIFs.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var fileSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                label("Input")
                pathField(inputURL?.path ?? "No video selected")
            Button("Choose...") {
                chooseInput()
            }
            .disabled(isConverting)
            }
            HStack(spacing: 12) {
                label("Output")
                pathField(outputURL?.path ?? "No output selected")
            Button("Save As...") {
                chooseOutput()
            }
            .disabled(isConverting || inputURL == nil)
            }
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                label("Width")
                Picker("Width", selection: $width) {
                    ForEach(allowedWidths, id: \.self) { value in
                        Text("\(value) px").tag(value)
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120, alignment: .leading)
                Spacer()
            }
            HStack(spacing: 12) {
                label("FPS")
                Picker("FPS", selection: $fps) {
                    ForEach(allowedFPS, id: \.self) { value in
                        Text("\(value)").tag(value)
                    }
                }
                .pickerStyle(.segmented)
            }
            HStack(spacing: 12) {
                label("Start")
                Stepper(value: $start, in: 0...999, step: 0.5) {
                    Text("\(formatSeconds(start)) s")
                        .frame(width: 72, alignment: .leading)
                }
                Spacer()
            }
            HStack(spacing: 12) {
                label("Duration")
                HStack(spacing: 10) {
                    Stepper(value: $duration, in: 0...999, step: 0.5) {
                        Text(duration == 0 ? "All" : "\(formatSeconds(duration)) s")
                            .frame(width: 72, alignment: .leading)
                    }
                    Button("All") {
                        duration = 0
                    }
                    .disabled(isConverting)
                }
                Spacer()
            }
        }
        .disabled(isConverting)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            ProgressView(value: progress)
            Text(status)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(logLines.suffix(8).enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 96)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
    }

    private var actionBar: some View {
        HStack {
            Button("Open Output") {
                if let outputURL {
                    NSWorkspace.shared.activateFileViewerSelecting([outputURL])
                }
            }
            .disabled(outputURL == nil || !FileManager.default.fileExists(atPath: outputURL?.path ?? ""))

            Spacer()

            Button(isPaused ? "继续" : "暂停") {
                togglePause()
            }
            .disabled(!isConverting || conversionFinished)

            Button("中止") {
                cancelConversion()
            }
            .disabled(!isConverting || conversionFinished)

            startButton
        }
    }

    private var startButton: some View {
        Button(isConverting ? "处理中..." : "开始") {
            convert()
        }
        .keyboardShortcut(.defaultAction)
        .disabled(isConverting || conversionFinished || inputURL == nil || outputURL == nil)
    }

    private func pathField(_ text: String) -> some View {
        Text(text)
            .lineLimit(1)
            .truncationMode(.middle)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(width: 64, alignment: .leading)
    }

    private func chooseInput() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = supportedExtensions.compactMap { UTType(filenameExtension: $0) }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        if panel.runModal() == .OK, let url = panel.url {
            inputURL = url
            outputURL = URL(fileURLWithPath: defaultOutputPath(for: url.path))
            status = "Ready"
            logLines.removeAll()
            progress = 0
            isPaused = false
            conversionFinished = false
            controller = nil
        }
    }

    private func chooseOutput() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = outputURL?.lastPathComponent ?? "output.gif"
        if panel.runModal() == .OK, let url = panel.url {
            outputURL = url.pathExtension.lowercased() == "gif" ? url : url.appendingPathExtension("gif")
        }
    }

    private func convert() {
        guard let inputURL, let outputURL else {
            return
        }

        let options = ConversionOptions(
            input: inputURL.path,
            output: outputURL.path,
            fps: fps,
            width: width,
            start: start,
            duration: duration
        )

        isConverting = true
        isPaused = false
        conversionFinished = false
        progress = 0
        status = "Starting..."
        logLines.removeAll()
        let activeController = ConversionController()
        controller = activeController

        Task.detached {
            do {
                try convertVideoToGif(options: options, controller: activeController) { event in
                    Task { @MainActor in
                        switch event {
                        case .message(let text):
                            status = text
                            logLines.append(text)
                        case .fraction(let value):
                            progress = min(max(value, 0), 1)
                        }
                    }
                }

                await MainActor.run {
                    progress = 1
                    status = "Done"
                    isConverting = false
                    isPaused = false
                    conversionFinished = true
                    controller = nil
                }
            } catch {
                await MainActor.run {
                    status = String(describing: error)
                    logLines.append("Error: \(error)")
                    isConverting = false
                    isPaused = false
                    conversionFinished = true
                    controller = nil
                }
            }
        }
    }

    private func togglePause() {
        guard let controller else {
            return
        }

        if isPaused {
            controller.resume()
            isPaused = false
            status = "Resuming..."
        } else {
            controller.pause()
            isPaused = true
            status = "Paused"
        }
    }

    private func cancelConversion() {
        controller?.cancel()
        isPaused = false
        status = "Cancelling..."
    }
}

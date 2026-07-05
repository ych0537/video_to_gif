import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct ConversionOptions: Sendable {
    public var input: String
    public var output: String
    public var fps: Int
    public var width: Int
    public var start: Double
    public var duration: Double

    public init(input: String, output: String, fps: Int = 10, width: Int = 800, start: Double = 0, duration: Double = 0) {
        self.input = input
        self.output = output
        self.fps = fps
        self.width = width
        self.start = start
        self.duration = duration
    }
}

public enum ConversionProgress: Sendable {
    case message(String)
    case fraction(Double)
}

public enum VideoToGifError: Error, CustomStringConvertible, Sendable {
    case message(String)

    public var description: String {
        switch self {
        case .message(let text):
            return text
        }
    }
}

public final class ConversionController: @unchecked Sendable {
    private let lock = NSLock()
    private var paused = false
    private var cancelled = false

    public init() {}

    public func pause() {
        lock.withLock {
            paused = true
        }
    }

    public func resume() {
        lock.withLock {
            paused = false
        }
    }

    public func cancel() {
        lock.withLock {
            cancelled = true
            paused = false
        }
    }

    public var isPaused: Bool {
        lock.withLock { paused }
    }

    public var isCancelled: Bool {
        lock.withLock { cancelled }
    }

    func waitIfPaused() throws {
        while true {
            if isCancelled {
                throw VideoToGifError.message("Conversion cancelled")
            }
            if !isPaused {
                return
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }
}

public let maxInputBytes: UInt64 = 1_024 * 1024 * 1024
public let supportedExtensions = Set(["mp4", "mov", "webm", "mkv", "avi", "flv", "wmv", "m4v", "3gp"])
public let allowedWidths = [160, 240, 320, 360, 480, 640, 800, 1024, 1280, 1440, 1600, 1920]
public let allowedFPS = [5, 10, 15, 20, 24, 30]

public func defaultOutputPath(for input: String) -> String {
    let url = URL(fileURLWithPath: input)
    let directory = url.deletingLastPathComponent()
    let name = url.deletingPathExtension().lastPathComponent
    return directory.appendingPathComponent("\(name).gif").path
}

public func validateConversionOptions(_ options: ConversionOptions) throws {
    guard allowedFPS.contains(options.fps) else {
        throw VideoToGifError.message("--fps must be one of: \(allowedFPS.map(String.init).joined(separator: ", "))")
    }
    guard allowedWidths.contains(options.width) else {
        throw VideoToGifError.message("--width must be one of: \(allowedWidths.map(String.init).joined(separator: ", "))")
    }
    guard options.start >= 0 else {
        throw VideoToGifError.message("--start must be zero or greater")
    }
    guard hasHalfSecondPrecision(options.start) else {
        throw VideoToGifError.message("--start supports 0.5 second precision, for example 0, 0.5, 1, 1.5")
    }
    guard options.duration >= 0 else {
        throw VideoToGifError.message("--duration must be zero or greater")
    }

    let inputURL = URL(fileURLWithPath: options.input)
    guard FileManager.default.fileExists(atPath: inputURL.path) else {
        throw VideoToGifError.message("Input file does not exist: \(inputURL.path)")
    }
    let inputExtension = inputURL.pathExtension.lowercased()
    guard supportedExtensions.contains(inputExtension) else {
        throw VideoToGifError.message("Unsupported input format .\(inputExtension). Supported formats: \(supportedExtensions.sorted().joined(separator: ", "))")
    }
    let inputAttributes = try FileManager.default.attributesOfItem(atPath: inputURL.path)
    let inputBytes = inputAttributes[.size] as? UInt64 ?? 0
    guard inputBytes <= maxInputBytes else {
        throw VideoToGifError.message("Input file is \(formatBytes(inputBytes)); maximum supported size is \(formatBytes(maxInputBytes))")
    }
}

public func hasHalfSecondPrecision(_ seconds: Double) -> Bool {
    let doubled = seconds * 2
    return abs(doubled.rounded() - doubled) < 0.000_001
}

public func convertVideoToGif(
    options: ConversionOptions,
    controller: ConversionController? = nil,
    progress: @Sendable (ConversionProgress) -> Void = { _ in }
) throws {
    try validateConversionOptions(options)

    let inputURL = URL(fileURLWithPath: options.input)
    let outputURL = URL(fileURLWithPath: options.output)

    if let ffmpegPath = findExecutable(named: "ffmpeg") {
        try convertVideoToGifWithFFmpeg(options: options, ffmpegPath: ffmpegPath, inputURL: inputURL, outputURL: outputURL, controller: controller, progress: progress)
        return
    }

    progress(.message("ffmpeg not found; using macOS native video reader. Some formats such as webm, mkv, flv, and wmv may require ffmpeg."))
    try convertVideoToGifWithAVFoundation(options: options, inputURL: inputURL, outputURL: outputURL, controller: controller, progress: progress)
}

func resizedImage(_ image: CGImage, maxWidth: Int) throws -> CGImage {
    guard image.width > maxWidth else {
        return image
    }

    let scale = Double(maxWidth) / Double(image.width)
    let targetWidth = maxWidth
    let targetHeight = max(1, Int((Double(image.height) * scale).rounded()))
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bitmapInfo = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue

    guard let context = CGContext(
        data: nil,
        width: targetWidth,
        height: targetHeight,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: bitmapInfo
    ) else {
        throw VideoToGifError.message("Could not create resize context")
    }

    context.interpolationQuality = CGInterpolationQuality.medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: targetWidth, height: targetHeight))

    guard let resized = context.makeImage() else {
        throw VideoToGifError.message("Could not resize frame")
    }
    return resized
}

func videoDurationSeconds(for asset: AVAsset) -> Double {
    let seconds = CMTimeGetSeconds(asset.duration)
    return seconds.isFinite ? seconds : 0
}

func convertVideoToGifWithAVFoundation(
    options: ConversionOptions,
    inputURL: URL,
    outputURL: URL,
    controller: ConversionController?,
    progress: @Sendable (ConversionProgress) -> Void
) throws {
    let asset = AVURLAsset(url: inputURL)
    let totalDuration = videoDurationSeconds(for: asset)
    guard totalDuration > 0 else {
        throw VideoToGifError.message("Could not read video duration")
    }
    guard options.start < totalDuration else {
        throw VideoToGifError.message("--start is beyond the end of the video")
    }

    let availableDuration = totalDuration - options.start
    let requestedDuration = options.duration == 0 ? availableDuration : options.duration
    let clipDuration = min(requestedDuration, availableDuration)
    let frameDelay = 1.0 / Double(options.fps)
    let frameCount = max(1, Int((clipDuration * Double(options.fps)).rounded(.up)))

    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero

    let gifType = UTType.gif.identifier as CFString
    guard let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, gifType, frameCount, nil) else {
        throw VideoToGifError.message("Could not create GIF at \(outputURL.path)")
    }

    let gifProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFLoopCount: 0
        ]
    ]
    CGImageDestinationSetProperties(destination, gifProperties as CFDictionary)

    let frameProperties: [CFString: Any] = [
        kCGImagePropertyGIFDictionary: [
            kCGImagePropertyGIFDelayTime: frameDelay,
            kCGImagePropertyGIFUnclampedDelayTime: frameDelay
        ]
    ]

    progress(.message("Input: \(inputURL.path)"))
    progress(.message("Output: \(outputURL.path)"))
    progress(.message("Settings: \(options.width) px, \(options.fps) fps, start \(String(format: "%.1f", options.start))s, duration \(String(format: "%.2f", clipDuration))s"))

    for frameIndex in 0..<frameCount {
        try controller?.waitIfPaused()
        autoreleasepool {
            do {
                let lastFrameOffset = max(0, clipDuration - 0.001)
                let seconds = options.start + min(Double(frameIndex) * frameDelay, lastFrameOffset)
                let time = CMTime(seconds: seconds, preferredTimescale: 600)
                let cgImage = try generator.copyCGImage(at: time, actualTime: nil)
                let outputImage = try resizedImage(cgImage, maxWidth: options.width)
                CGImageDestinationAddImage(destination, outputImage, frameProperties as CFDictionary)

                let completed = frameIndex + 1
                progress(.fraction(Double(completed) / Double(frameCount)))
                if completed == frameCount || completed % max(1, frameCount / 10) == 0 {
                    progress(.message("Progress: \(completed)/\(frameCount) frames"))
                }
            } catch {
                progress(.message("Failed to process frame \(frameIndex + 1): \(error)"))
            }
        }
    }

    guard CGImageDestinationFinalize(destination) else {
        throw VideoToGifError.message("Could not finalize GIF")
    }

    let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
    let bytes = outputAttributes[.size] as? UInt64 ?? 0
    progress(.fraction(1))
    progress(.message("Done: \(formatBytes(bytes))"))
}

func convertVideoToGifWithFFmpeg(
    options: ConversionOptions,
    ffmpegPath: String,
    inputURL: URL,
    outputURL: URL,
    controller: ConversionController?,
    progress: @Sendable (ConversionProgress) -> Void
) throws {
    let paletteURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("video-to-gif-\(UUID().uuidString)-palette.png")
    defer {
        try? FileManager.default.removeItem(at: paletteURL)
    }

    let startArgs = options.start > 0 ? ["-ss", formatSeconds(options.start)] : []
    let durationArgs = options.duration > 0 ? ["-t", formatSeconds(options.duration)] : []
    let scaleFilter = "fps=\(options.fps),scale=min(\(options.width)\\,iw):-1:flags=lanczos"

    progress(.message("Generating palette..."))
    try runProcess(
        executable: ffmpegPath,
        controller: controller,
        arguments: ["-y"] + startArgs + durationArgs + [
            "-i", inputURL.path,
            "-vf", "\(scaleFilter),palettegen",
            paletteURL.path
        ]
    )
    progress(.fraction(0.45))

    progress(.message("Rendering GIF..."))
    try runProcess(
        executable: ffmpegPath,
        controller: controller,
        arguments: ["-y"] + startArgs + durationArgs + [
            "-i", inputURL.path,
            "-i", paletteURL.path,
            "-lavfi", "\(scaleFilter)[x];[x][1:v]paletteuse=dither=bayer:bayer_scale=5",
            outputURL.path
        ]
    )

    let outputAttributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
    let bytes = outputAttributes[.size] as? UInt64 ?? 0
    progress(.message("Input: \(inputURL.path)"))
    progress(.message("Output: \(outputURL.path)"))
    progress(.message("Settings: \(options.width) px, \(options.fps) fps, start \(String(format: "%.1f", options.start))s, duration \(options.duration == 0 ? "full" : "\(formatSeconds(options.duration))s")"))
    progress(.fraction(1))
    progress(.message("Done: \(formatBytes(bytes))"))
}

func runProcess(executable: String, controller: ConversionController?, arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments

    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = pipe

    try process.run()

    var sentStop = false
    while process.isRunning {
        if controller?.isCancelled == true {
            process.terminate()
            process.waitUntilExit()
            throw VideoToGifError.message("Conversion cancelled")
        }

        if controller?.isPaused == true {
            if !sentStop {
                kill(process.processIdentifier, SIGSTOP)
                sentStop = true
            }
        } else if sentStop {
            kill(process.processIdentifier, SIGCONT)
            sentStop = false
        }

        Thread.sleep(forTimeInterval: 0.1)
    }

    guard process.terminationStatus == 0 else {
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? "Unknown ffmpeg error"
        throw VideoToGifError.message("ffmpeg failed: \(output)")
    }
}

extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

func findExecutable(named name: String) -> String? {
    if let bundledPath = Bundle.main.resourceURL?.appendingPathComponent(name).path,
       FileManager.default.isExecutableFile(atPath: bundledPath) {
        return bundledPath
    }

    let pathCandidates = (ProcessInfo.processInfo.environment["PATH"] ?? "")
        .split(separator: ":")
        .map(String.init)
    let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]

    for path in pathCandidates + commonPaths {
        let candidate = URL(fileURLWithPath: path).appendingPathComponent(name).path
        if FileManager.default.isExecutableFile(atPath: candidate) {
            return candidate
        }
    }
    return nil
}

public func formatSeconds(_ seconds: Double) -> String {
    if seconds.rounded() == seconds {
        return String(Int(seconds))
    }
    return String(format: "%.1f", seconds)
}

public func formatBytes(_ bytes: UInt64) -> String {
    let units = ["B", "KB", "MB", "GB"]
    var value = Double(bytes)
    var unitIndex = 0
    while value >= 1024, unitIndex < units.count - 1 {
        value /= 1024
        unitIndex += 1
    }
    return String(format: "%.1f %@", value, units[unitIndex])
}

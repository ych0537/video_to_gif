import Foundation
import VideoToGifCore

func printUsage() {
    print("""
    Convert a local video recording to a smaller GIF.

    Usage:
      video-to-gif <input-video> [output.gif] [options]

    Options:
      --width <pixels>      Max output width: 160, 240, 320, 360, 480, 640, 800. Default: 800
      --fps <value>         Frames per second: 5, 10, 15, 20, 24, 30. Default: 10
      --start <seconds>     Start time in seconds, with 0.5s precision. Default: 0
      --duration <seconds>  Clip duration in seconds. 0 means full remaining video. Default: 0
      -h, --help            Show this help

    Examples:
      video-to-gif screen.mov demo.gif --width 800 --fps 10
      video-to-gif screen.mov --start 2.5 --duration 6
    """)
}

func parseOptions(_ args: [String]) throws -> ConversionOptions {
    var fps = 10
    var width = 800
    var start = 0.0
    var duration = 0.0
    var positional: [String] = []
    var index = 0

    func value(after flag: String) throws -> String {
        let next = index + 1
        guard next < args.count else {
            throw VideoToGifError.message("Missing value for \(flag)")
        }
        index = next
        return args[next]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "-h", "--help":
            printUsage()
            exit(0)
        case "--fps":
            let raw = try value(after: arg)
            guard let parsed = Int(raw), allowedFPS.contains(parsed) else {
                throw VideoToGifError.message("--fps must be one of: \(allowedFPS.map(String.init).joined(separator: ", "))")
            }
            fps = parsed
        case "--width":
            let raw = try value(after: arg)
            guard let parsed = Int(raw), allowedWidths.contains(parsed) else {
                throw VideoToGifError.message("--width must be one of: \(allowedWidths.map(String.init).joined(separator: ", "))")
            }
            width = parsed
        case "--start":
            let raw = try value(after: arg)
            guard let parsed = Double(raw), parsed >= 0 else {
                throw VideoToGifError.message("--start must be zero or greater")
            }
            guard hasHalfSecondPrecision(parsed) else {
                throw VideoToGifError.message("--start supports 0.5 second precision, for example 0, 0.5, 1, 1.5")
            }
            start = parsed
        case "--duration":
            let raw = try value(after: arg)
            guard let parsed = Double(raw), parsed >= 0 else {
                throw VideoToGifError.message("--duration must be zero or greater")
            }
            duration = parsed
        default:
            if arg.hasPrefix("-") {
                throw VideoToGifError.message("Unknown option: \(arg)")
            }
            positional.append(arg)
        }
        index += 1
    }

    guard positional.count >= 1 else {
        throw VideoToGifError.message("Missing input video path")
    }
    guard positional.count <= 2 else {
        throw VideoToGifError.message("Too many positional arguments")
    }

    let input = positional[0]
    let output = positional.count == 2 ? positional[1] : defaultOutputPath(for: input)
    return ConversionOptions(input: input, output: output, fps: fps, width: width, start: start, duration: duration)
}

do {
    let options = try parseOptions(Array(CommandLine.arguments.dropFirst()))
    try convertVideoToGif(options: options) { event in
        switch event {
        case .message(let text):
            print(text)
        case .fraction:
            break
        }
    }
} catch {
    fputs("Error: \(error)\n\n", stderr)
    printUsage()
    exit(1)
}

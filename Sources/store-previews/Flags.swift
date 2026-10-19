import AppKit
import StorePreviewKit

// One-off rendering from flags, without a config file. One title applies to
// every screenshot; without -t the title comes from each file name.

let flagsUsage = """
Usage: store-previews -i <folder> [options]

Required:
  -i, --input <folder>        Folder containing screenshots

Options:
  -o, --output <folder>       Output folder (default: previews/ next to the input folder)
  -b, --background <hex>      Background color (default: #1C1C1E)
  -t, --title <text>          Title text (supports \\n for line breaks)
  -s, --subtitle <text>       Subtitle text below title
  --text-color <hex>          Text color (default: #FFFFFF)
  --font-name <name>          Font family name (default: system rounded bold)
  --font-size <pt>            Title font size in points (default: auto)
  --preset <name>             Output preset (default: mac-16; see `store-previews presets`)
  --size <WxH>                Canvas size in pixels (default: 2880x1800)
  --layout <mac|iphone|ipad>  Layout style (default: mac)
  --corner-radius <px>        Screenshot/device corner radius (default: auto)
  --padding <px>              Side padding in pixels (default: auto)
  --no-shadow                 Disable drop shadow
  --gradient <0-1>            How much darker the bottom of the background is (default: 0.3, 0 = flat)
  -h, --help                  Show this help
"""

struct FlagsConfig {
    var inputFolder: String
    var outputFolder: String?    // nil = previews/ next to the input
    var options: RenderOptions
}

func parseFlagArgs(_ args: [String]) throws -> FlagsConfig? {
    var input: String?
    var output: String?
    var bg = "#1C1C1E"
    var title = ""
    var subtitle = ""
    var textColor = "#FFFFFF"
    var fontName: String?
    var fontSize: CGFloat = 0
    var width = 2880
    var height = 1800
    var layout = Layout.mac
    var cornerRadius: CGFloat = -1
    var padding: CGFloat = 0
    var shadow = true
    var gradient: CGFloat = 0.3

    var i = 0
    func value(_ arg: String) throws -> String {
        i += 1
        guard i < args.count else { throw CLIError("\(arg) requires a value") }
        return args[i]
    }
    func number(_ arg: String) throws -> CGFloat {
        let text = try value(arg)
        guard let number = Double(text), number >= 0 else { throw CLIError("\(arg) needs a number, got '\(text)'") }
        return CGFloat(number)
    }

    while i < args.count {
        let arg = args[i]
        switch arg {
        case "-i", "--input": input = try value(arg)
        case "-o", "--output": output = try value(arg)
        case "-b", "--background": bg = try value(arg)
        case "-t", "--title": title = try value(arg)
        case "-s", "--subtitle": subtitle = try value(arg)
        case "--text-color": textColor = try value(arg)
        case "--font-name": fontName = try value(arg)
        case "--font-size": fontSize = try number(arg)
        case "--preset":
            let name = try value(arg)
            guard let preset = Preset.named(name) else { throw CLIError("Unknown preset: \(name)") }
            width = preset.width; height = preset.height; layout = preset.layout
        case "--size":
            guard let size = parseSize(try value(arg)) else {
                throw CLIError("Invalid size format. Use WxH (e.g., 2880x1800)")
            }
            width = size.width; height = size.height
        case "--layout":
            guard let parsedLayout = Layout(rawValue: try value(arg).lowercased()) else {
                throw CLIError("Invalid layout. Use mac, iphone, or ipad")
            }
            layout = parsedLayout
        case "--corner-radius": cornerRadius = try number(arg)
        case "--padding": padding = try number(arg)
        case "--no-shadow": shadow = false
        case "--gradient":
            gradient = try number(arg)
            guard gradient <= 1 else { throw CLIError("--gradient needs a number from 0 to 1, got \(gradient)") }
        case "-h", "--help": print(flagsUsage); return nil
        default: throw CLIError("Unknown option: \(arg)\n\n\(flagsUsage)")
        }
        i += 1
    }

    guard let inputFolder = input else { throw CLIError("--input is required\n\n\(flagsUsage)") }
    guard let bgColor = parseHexColor(bg) else { throw CLIError("Invalid background color: \(bg)") }
    guard let txtColor = parseHexColor(textColor) else { throw CLIError("Invalid text color: \(textColor)") }

    return FlagsConfig(
        inputFolder: inputFolder,
        outputFolder: output,
        options: RenderOptions(
            width: width,
            height: height,
            layout: layout,
            // Expand \n in title/subtitle to actual newlines
            title: title.replacingOccurrences(of: "\\n", with: "\n"),
            subtitle: subtitle.replacingOccurrences(of: "\\n", with: "\n"),
            backgroundColor: bgColor,
            textColor: txtColor,
            fontName: fontName,
            fontSize: fontSize,
            cornerRadius: cornerRadius,
            padding: padding,
            shadowEnabled: shadow,
            gradient: gradient
        )
    )
}

private func isDirectory(_ path: String) -> Bool {
    var isDirectory: ObjCBool = false
    return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
}

private func pathByAppending(_ component: String, to path: String) -> String {
    (path as NSString).appendingPathComponent(component)
}

private func parentPath(of path: String) -> String {
    (path as NSString).deletingLastPathComponent
}

private func resolveInputPath(_ path: String, layout: Layout) -> String {
    let layoutPath = pathByAppending(layout.rawValue, to: path)
    return isDirectory(layoutPath) ? layoutPath : path
}

private func resolveOutputPath(
    configuredOutput: String?,
    expandedInputPath: String,
    resolvedInputPath: String,
    layout: Layout
) -> String {
    guard let configuredOutput else {
        if resolvedInputPath != expandedInputPath {
            return pathByAppending(layout.rawValue, to: pathByAppending("previews", to: parentPath(of: expandedInputPath)))
        }

        let inputName = (expandedInputPath as NSString).lastPathComponent
        let inputParent = parentPath(of: expandedInputPath)
        if inputName == layout.rawValue && (inputParent as NSString).lastPathComponent == "screenshots" {
            return pathByAppending(layout.rawValue, to: pathByAppending("previews", to: parentPath(of: inputParent)))
        }

        return pathByAppending("previews", to: parentPath(of: expandedInputPath))
    }

    let expandedOutput = (configuredOutput as NSString).expandingTildeInPath
    let outputName = (expandedOutput as NSString).lastPathComponent
    let layoutOutput = pathByAppending(layout.rawValue, to: expandedOutput)
    if outputName == layout.rawValue {
        return expandedOutput
    }
    if outputName == "previews" || isDirectory(layoutOutput) {
        return layoutOutput
    }
    return expandedOutput
}

func runFlags(_ args: [String]) throws {
    guard let config = try parseFlagArgs(args) else { return }
    let layout = config.options.layout

    let expandedInputPath = (config.inputFolder as NSString).expandingTildeInPath
    let inputPath = resolveInputPath(expandedInputPath, layout: layout)
    let outputPath = resolveOutputPath(
        configuredOutput: config.outputFolder,
        expandedInputPath: expandedInputPath,
        resolvedInputPath: inputPath,
        layout: layout
    )

    guard FileManager.default.fileExists(atPath: inputPath) else {
        throw CLIError("Input folder not found: \(inputPath)")
    }
    if !FileManager.default.fileExists(atPath: outputPath) {
        try FileManager.default.createDirectory(atPath: outputPath, withIntermediateDirectories: true)
        print("Created output folder: \(outputPath)")
    }

    let screenshots = imageFiles(in: URL(fileURLWithPath: inputPath))
    guard !screenshots.isEmpty else {
        print("No image files found in \(inputPath)")
        return
    }

    let options = config.options
    print("Screenshots: \(screenshots.count)")
    print("Canvas:      \(options.width) x \(options.height)")
    print("Layout:      \(layout.rawValue)")
    print("Input:       \(inputPath)")
    print("Titles:      \(options.title.isEmpty ? "from filenames" : "\"\(options.title.replacingOccurrences(of: "\n", with: "\\n"))\"")")
    if !options.subtitle.isEmpty { print("Subtitle:    \"\(options.subtitle.replacingOccurrences(of: "\n", with: "\\n"))\"") }
    print("Output:      \(outputPath)")
    print()

    var failures = 0
    for file in screenshots {
        let name = file.deletingPathExtension().lastPathComponent
        print("[\(name)]")
        // Use filename as title unless -t was specified
        var fileOptions = options
        if fileOptions.title.isEmpty {
            fileOptions.title = titleFromFilename(name)
            print("  Title: \"\(fileOptions.title.replacingOccurrences(of: "\n", with: "\\n"))\"")
        }
        if layout != .mac {
            fileOptions.title = wrapAfterFirstWords(fileOptions.title, count: 3)
        }

        let outFile = (outputPath as NSString).appendingPathComponent("preview_\(name).png")
        do {
            // Device layouts render at 4x into bitmaps of a few hundred MB; release each before the next.
            try autoreleasepool {
                guard let image = NSImage(contentsOf: file) else {
                    throw CLIError("could not load \(file.path)")
                }
                try renderPreview(screenshot: image, options: fileOptions).write(to: URL(fileURLWithPath: outFile))
            }
            print("  -> \(outFile)")
        } catch {
            failures += 1
            print("  Error: \(error)")
        }
    }

    print("\nDone! Generated \(screenshots.count - failures) of \(screenshots.count) preview(s).")
    if failures > 0 { throw CLIError("\(failures) preview(s) failed") }
}

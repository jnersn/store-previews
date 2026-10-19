import AppKit
import StorePreviewKit

let usage = """
App Store Preview Generator

Usage:
  store-previews render <config.json> [--locale <id>] [--target <name>] [--clean] [--dry-run] [--background <hex>] [--text-color <hex>] [--gradient <0-1>]
  store-previews init <screenshots-folder> [-o <config.json>] [--preset <name>] [--force]
  store-previews presets
  store-previews -i <folder> [options]      One-off render from flags (run with -i -h for options)

render     Renders every target x locale x screen in the config. Output goes to
           <output>/[<locale>/]<target>/NN_<screen>.png, numbered in screen order.
           --locale / --target limit the run, --clean first deletes the NN_*.png
           files in the folders being written, --dry-run only lists the jobs.
           --background / --text-color / --gradient override every style in the config.
init       Writes a starter config next to the screenshots folder (default
           <folder>/../store-previews.json) with one target per mac/iphone/ipad
           subfolder and titles taken from the file names.
presets    Lists the output size presets.

Config format: https://github.com/jnersn/store-previews#config
"""

struct CLIError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
    exit(1)
}

func warn(_ message: String) {
    FileHandle.standardError.write(Data("Warning: \(message)\n".utf8))
}

/// Splits arguments into positionals, valued options and flags.
struct ParsedArgs {
    var positionals: [String] = []
    var values: [String: String] = [:]
    var flags: Set<String> = []

    init(_ args: ArraySlice<String>, valued: Set<String>, flags allowedFlags: Set<String>) throws {
        var iterator = args.makeIterator()
        while let arg = iterator.next() {
            if valued.contains(arg) {
                guard let value = iterator.next() else { throw CLIError("\(arg) requires a value") }
                values[arg] = value
            } else if allowedFlags.contains(arg) {
                flags.insert(arg)
            } else if arg.hasPrefix("-") {
                throw CLIError("unknown option \(arg)")
            } else {
                positionals.append(arg)
            }
        }
    }
}

func absoluteURL(_ path: String, isDirectory: Bool = false) -> URL {
    let expanded = (path as NSString).expandingTildeInPath
    return URL(fileURLWithPath: expanded, isDirectory: isDirectory).standardizedFileURL
}

func displayPath(_ url: URL) -> String {
    let cwd = FileManager.default.currentDirectoryPath + "/"
    return url.path.hasPrefix(cwd) ? String(url.path.dropFirst(cwd.count)) : url.path
}

func runRender(_ args: ArraySlice<String>) throws {
    let parsed = try ParsedArgs(args, valued: ["--locale", "--target", "--background", "--text-color", "--gradient"], flags: ["--clean", "--dry-run"])
    guard parsed.positionals.count == 1 else { throw CLIError("render takes one config file") }
    let configURL = absoluteURL(parsed.positionals[0])
    guard FileManager.default.fileExists(atPath: configURL.path) else {
        throw CLIError("config not found: \(configURL.path)")
    }

    let config = try ProjectConfig.load(from: configURL)
    var gradient: Double?
    if let text = parsed.values["--gradient"] {
        guard let value = Double(text) else { throw CLIError("--gradient needs a number from 0 to 1, got '\(text)'") }
        gradient = value
    }
    let plan = try config.plan(
        baseDirectory: configURL.deletingLastPathComponent(),
        locale: parsed.values["--locale"],
        target: parsed.values["--target"],
        styleOverride: StyleConfig(
            background: parsed.values["--background"], textColor: parsed.values["--text-color"], gradient: gradient
        )
    )
    plan.warnings.forEach(warn)
    guard !plan.jobs.isEmpty else { throw CLIError("nothing to render") }

    if parsed.flags.contains("--dry-run") {
        for job in plan.jobs {
            let caption = job.options.title.replacingOccurrences(of: "\n", with: "\\n")
            print("\(displayPath(job.screenshot)) -> \(displayPath(job.output))  \"\(caption)\"")
        }
        print("\(plan.jobs.count) image(s) would be rendered.")
        return
    }

    let fm = FileManager.default
    let sources = Set(plan.jobs.map { $0.screenshot.standardizedFileURL })
    for directory in plan.outputDirectories {
        if parsed.flags.contains("--clean") {
            for file in imageFiles(in: directory) where file.lastPathComponent.range(
                of: #"^\d{2}_.*\.png$"#, options: .regularExpression
            ) != nil && !sources.contains(file.standardizedFileURL) {
                try fm.removeItem(at: file)
            }
        }
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    var failures = 0
    for job in plan.jobs {
        do {
            // Device layouts render at 4x into bitmaps of a few hundred MB; release each before the next.
            try autoreleasepool {
                guard let image = NSImage(contentsOf: job.screenshot) else {
                    throw CLIError("could not load \(job.screenshot.path)")
                }
                try renderPreview(screenshot: image, options: job.options).write(to: job.output)
            }
            print("-> \(displayPath(job.output))")
        } catch {
            failures += 1
            warn("\(job.screen) (\(job.target)\(job.locale.map { ", \($0)" } ?? "")): \(error)")
        }
    }
    print("Rendered \(plan.jobs.count - failures) of \(plan.jobs.count) image(s).")
    if failures > 0 { exit(1) }
}

func runInit(_ args: ArraySlice<String>) throws {
    let parsed = try ParsedArgs(args, valued: ["-o", "--output", "--preset"], flags: ["--force"])
    guard parsed.positionals.count == 1 else { throw CLIError("init takes one screenshots folder") }
    let screenshotsURL = absoluteURL(parsed.positionals[0], isDirectory: true)

    var fallback = Preset.defaultPreset(for: .mac)
    if let name = parsed.values["--preset"] {
        guard let preset = Preset.named(name) else { throw ConfigError.unknownPreset(name) }
        fallback = preset
    }

    let configURL = (parsed.values["-o"] ?? parsed.values["--output"]).map { absoluteURL($0) }
        ?? screenshotsURL.deletingLastPathComponent().appendingPathComponent("store-previews.json")
    if FileManager.default.fileExists(atPath: configURL.path) && !parsed.flags.contains("--force") {
        throw CLIError("\(configURL.path) already exists (use --force to overwrite)")
    }

    let relative = relativePath(from: configURL.deletingLastPathComponent(), to: screenshotsURL)
    let config = ProjectConfig.scaffold(screenshotsRoot: screenshotsURL, relativePath: relative, fallback: fallback)
    guard !config.screens.isEmpty else { throw CLIError("no screenshots found in \(screenshotsURL.path)") }

    try config.encoded().write(to: configURL)
    print("Wrote \(displayPath(configURL)): \(config.targets.count) target(s), \(config.screens.count) screen(s).")
    if let locales = config.locales {
        print("Locales: \(locales.joined(separator: ", ")). Put the language of the default captions first.")
    }
    print("Edit the titles and subtitles, then run: store-previews render \(displayPath(configURL))")
}

func relativePath(from base: URL, to target: URL) -> String {
    let baseParts = base.standardizedFileURL.pathComponents
    let targetParts = target.standardizedFileURL.pathComponents
    var common = 0
    while common < min(baseParts.count, targetParts.count) && baseParts[common] == targetParts[common] {
        common += 1
    }
    let ups = Array(repeating: "..", count: baseParts.count - common)
    let parts = ups + targetParts[common...]
    return parts.isEmpty ? "." : parts.joined(separator: "/")
}

func runPresets() {
    for preset in Preset.all {
        let name = preset.name.padding(toLength: 15, withPad: " ", startingAt: 0)
        print("\(name) \(preset.width)x\(preset.height)  \(preset.layout.rawValue)")
    }
}

let arguments = CommandLine.arguments.dropFirst()
do {
    switch arguments.first {
    case nil, "-h", "--help", "help":
        print(usage)
    case "render":
        try runRender(arguments.dropFirst())
    case "init":
        try runInit(arguments.dropFirst())
    case "presets":
        runPresets()
    case let first? where first.hasPrefix("-"):
        try runFlags(Array(arguments))
    case let first?:
        throw CLIError("unknown command '\(first)'\n\n\(usage)")
    }
} catch {
    fail("\(error)")
}

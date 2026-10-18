import AppKit
import XCTest
@testable import StorePreviewKit

/// Checks that README.md matches the tool: the shell commands it shows run and
/// do what it says, the example config is valid, and the tables list what the
/// CLI and presets really offer. The library snippet is type-checked separately
/// by Scripts/check-readme-library.sh.
final class ReadmeTests: XCTestCase {
    private var workspace: URL!

    override func setUpWithError() throws {
        workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-previews-readme-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: workspace)
    }

    // MARK: - Tests

    func testQuickStartWorks() throws {
        let section = try Readme.section("Quick start")

        // Step 1: build the screenshot tree the README draws.
        let tree = try XCTUnwrap(section.blocks.first { $0.language.isEmpty }, "quick start has no folder tree")
        let files = Readme.files(inTree: tree.body)
        XCTAssertFalse(files.isEmpty, "could not read the folder tree")
        for file in files { try writeScreenshot(file) }

        // Steps 2-4: run the commands in order and check the files they promise.
        let commands = section.blocks.filter { $0.language == "sh" }.flatMap { Readme.commands(in: $0.body) }
        XCTAssertEqual(commands.map(\.arguments.first), ["init", "render"])
        for command in commands {
            let result = try run(command.arguments)
            XCTAssertEqual(result.status, 0, "`\(command.line)` failed:\n\(result.output)")
            if let promised = command.comment?.firstMatch(of: #/writes (\S+)/#)?.1 {
                XCTAssertTrue(exists(String(promised)), "`\(command.line)` did not write \(promised)")
            }
        }

        // "The images land in MyApp/previews/<target>/01_<screen>.png, 02_<screen>.png ..."
        let previews = workspace.appendingPathComponent("MyApp/previews")
        let targets = try FileManager.default.contentsOfDirectory(atPath: previews.path).filter { !$0.hasPrefix(".") }
        let layouts = Set(files.map { $0.split(separator: "/")[2] })
        XCTAssertEqual(targets.count, layouts.count, "expected one output folder per layout folder")
        for target in targets {
            let images = imageFiles(in: previews.appendingPathComponent(target)).map(\.lastPathComponent)
            let screensPerLayout = files.filter { $0.contains("/\(Layout.allCases.first { target.hasPrefix($0.rawValue) }!.rawValue)/") }
            XCTAssertEqual(images.count, screensPerLayout.count, target)
            XCTAssertEqual(images.map { String($0.prefix(3)) }, (1...images.count).map { String(format: "%02d_", $0) })
        }
    }

    func testFlagExamplesWork() throws {
        let section = try Readme.section("One-off renders from flags")
        let commands = section.blocks.filter { $0.language == "sh" }.flatMap { Readme.commands(in: $0.body) }
        XCTAssertFalse(commands.isEmpty)
        for layout in ["mac", "iphone"] { try writeScreenshot("screenshots/\(layout)/Example screen.png") }

        for command in commands {
            let before = Set(allFiles())
            let result = try run(command.arguments)
            XCTAssertEqual(result.status, 0, "`\(command.line)` failed:\n\(result.output)")
            let created = Set(allFiles()).subtracting(before)
            if command.arguments.contains("-h") {
                XCTAssertTrue(result.output.contains("Usage: store-previews -i"), command.line)
            } else {
                XCTAssertTrue(created.contains { $0.hasSuffix("/preview_Example screen.png") },
                              "`\(command.line)` wrote no preview_<name>.png:\n\(result.output)")
            }
        }
    }

    func testExampleConfigIsValid() throws {
        let block = try XCTUnwrap(try Readme.section("Config").blocks.first { $0.language == "json" })
        let configURL = workspace.appendingPathComponent("store-previews.json")
        try Data(block.body.utf8).write(to: configURL)
        let config = try ProjectConfig.load(from: configURL)

        let folders = try config.targets.map {
            try config.resolve($0, screenshotsRoot: workspace.appendingPathComponent("screenshots"),
                               locales: [], fileManager: .default).input
        }
        for folder in folders {
            for screen in config.screens { try writeScreenshot("screenshots/\(folder)/\(screen.file).png") }
        }

        let plan = try config.plan(baseDirectory: workspace)
        let locales = max(config.locales?.count ?? 0, 1)
        XCTAssertEqual(plan.jobs.count, locales * config.targets.count * config.screens.count)
        XCTAssertFalse(plan.warnings.contains { $0.contains("not found") || $0.contains("no screenshots") },
                       "\(plan.warnings)")
    }

    func testCommandsMatchUsage() throws {
        let help = try run(["--help"]).output
        let usageBlock = try XCTUnwrap(try Readme.section("Commands").blocks.first { $0.language.isEmpty })
        for line in usageBlock.body.split(separator: "\n") {
            // Compare the command and its options; usage text may say more.
            let words = line.split(separator: " ")
                .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: "[]")) }
                .filter { $0.hasPrefix("-") || $0 == "store-previews" }
            let command = line.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let helpLine = help.split(separator: "\n").first { $0.contains("store-previews \(command)") }
            XCTAssertNotNil(helpLine, "--help has no `store-previews \(command)` line")
            for word in words {
                XCTAssertTrue(helpLine?.contains(word) ?? false, "README option \(word) is not in --help for \(command)")
            }
        }

        // Every option in the render table is one `render` accepts.
        let renderOptions = try Readme.section("Commands").tableRows.compactMap {
            $0.first?.firstMatch(of: #/`(--[a-z-]+)/#)?.1
        }
        XCTAssertFalse(renderOptions.isEmpty)
        let renderLine = help.split(separator: "\n").first { $0.contains("store-previews render") } ?? ""
        for option in renderOptions {
            XCTAssertTrue(renderLine.contains(option), "README render option \(option) is not in --help")
        }
    }

    func testPresetsTableMatchesCode() throws {
        let rows = try Readme.section("Presets").tableRows.compactMap { row -> String? in
            guard row.count == 3, let name = row[0].firstMatch(of: #/`(.+)`/#)?.1 else { return nil }
            let size = row[1].replacingOccurrences(of: " × ", with: "x")
            return "\(name) \(size) \(row[2])"
        }
        let presets = Preset.all.map { "\($0.name) \($0.width)x\($0.height) \($0.layout.rawValue)" }
        XCTAssertEqual(Set(rows), Set(presets))
        XCTAssertEqual(rows.count, presets.count)
    }

    // MARK: - Helpers

    private func writeScreenshot(_ relativePath: String) throws {
        let url = workspace.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 120, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    private func exists(_ relativePath: String) -> Bool {
        FileManager.default.fileExists(atPath: workspace.appendingPathComponent(relativePath).path)
    }

    private func allFiles() -> [String] {
        let enumerator = FileManager.default.enumerator(atPath: workspace.path)
        return (enumerator?.allObjects as? [String] ?? []).map { "/" + $0 }
    }

    private func run(_ arguments: [String]) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = try Self.binary()
        process.arguments = arguments
        process.currentDirectoryURL = workspace
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// The `store-previews` executable SwiftPM builds next to the test bundle.
    private static func binary() throws -> URL {
        let bundle = try XCTUnwrap(Bundle.allBundles.first { $0.bundlePath.hasSuffix(".xctest") })
        let url = bundle.bundleURL.deletingLastPathComponent().appendingPathComponent("store-previews")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw ReadmeError("store-previews binary not found at \(url.path)")
        }
        return url
    }
}

// MARK: - README parsing

private struct ReadmeError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

private enum Readme {
    struct Block {
        let language: String
        let body: String
    }

    struct Section {
        var blocks: [Block] = []
        var tableRows: [[String]] = []
    }

    struct Command {
        let line: String
        let arguments: [String]   // without the leading `store-previews`
        let comment: String?
    }

    static func text() throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("README.md")
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// The code blocks and table rows under a `##` or `###` heading, up to the next heading.
    static func section(_ heading: String) throws -> Section {
        var section: Section?
        var block: (language: String, indent: Int, lines: [String])?
        for line in try text().components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = block {
                if trimmed == "```" {
                    section?.blocks.append(Block(language: open.language, body: open.lines.joined(separator: "\n")))
                    block = nil
                } else {
                    open.lines.append(String(line.dropFirst(min(open.indent, line.prefix { $0 == " " }.count))))
                    block = open
                }
                continue
            }
            if trimmed.hasPrefix("```") {
                block = (String(trimmed.dropFirst(3)), line.prefix { $0 == " " }.count, [])
            } else if let match = line.firstMatch(of: #/^#{2,3} (.+)$/#) {
                if section != nil { break }
                if match.1 == heading { section = Section() }
            } else if trimmed.hasPrefix("|"), !trimmed.hasPrefix("| ---"), section != nil {
                let cells = trimmed.split(separator: "|").map { $0.trimmingCharacters(in: .whitespaces) }
                section?.tableRows.append(cells)
            }
        }
        guard let section else { throw ReadmeError("README has no section '\(heading)'") }
        return section
    }

    /// `store-previews ...` lines in a shell block, split like a shell would
    /// (double quotes group words and keep backslashes).
    static func commands(in body: String) -> [Command] {
        body.split(separator: "\n").compactMap { rawLine in
            var line = String(rawLine)
            var comment: String?
            if let hash = line.range(of: "   #") ?? line.range(of: " # ") {
                comment = line[hash.upperBound...].trimmingCharacters(in: .whitespaces)
                line = String(line[..<hash.lowerBound])
            }
            line = line.trimmingCharacters(in: .whitespaces)
            var words: [String] = []
            var current = ""
            var inQuotes = false
            var hasWord = false
            for character in line {
                if character == "\"" {
                    inQuotes.toggle(); hasWord = true
                } else if character == " " && !inQuotes {
                    if hasWord { words.append(current) }
                    current = ""; hasWord = false
                } else {
                    current.append(character); hasWord = true
                }
            }
            if hasWord { words.append(current) }
            guard words.first == "store-previews" else { return nil }
            return Command(line: line, arguments: Array(words.dropFirst()), comment: comment)
        }
    }

    /// Paths from a folder tree such as:
    ///   MyApp/
    ///     screenshots/
    ///       iphone/  First screen.png  Second screen.png
    /// File names are separated by two or more spaces.
    static func files(inTree body: String) -> [String] {
        var stack: [(indent: Int, name: String)] = []
        var files: [String] = []
        for line in body.split(separator: "\n") {
            let indent = line.prefix { $0 == " " }.count
            let parts = line.trimmingCharacters(in: .whitespaces)
                .split(separator: #/\s{2,}/#).map(String.init)
            guard let folder = parts.first, folder.hasSuffix("/") else { continue }
            stack.removeAll { $0.indent >= indent }
            stack.append((indent, String(folder.dropLast())))
            let path = stack.map(\.name).joined(separator: "/")
            files += parts.dropFirst().map { "\(path)/\($0)" }
        }
        return files
    }
}

import AppKit
import XCTest
@testable import StorePreviewKit

final class StorePreviewKitTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("store-previews-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func writeImage(_ relativePath: String, width: Int = 40, height: Int = 80) throws {
        let url = root.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0
        )!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    func testPresetLookup() {
        XCTAssertEqual(Preset.named("iphone-6.9")?.width, 1290)
        XCTAssertEqual(Preset.named("IPAD-LANDSCAPE")?.name, "ipad-13-land")
        XCTAssertEqual(Preset.named("2880x1800")?.name, "mac-16")
        XCTAssertNil(Preset.named("watch"))
    }

    func testStyleLayering() {
        let screen = StyleConfig(fontSize: 90)
        let target = StyleConfig(background: "#000000", fontSize: 70)
        let project = StyleConfig(background: "#FFFFFF", textColor: "#111111")
        let merged = screen.over(target).over(project).over(.defaults)
        XCTAssertEqual(merged.fontSize, 90)
        XCTAssertEqual(merged.background, "#000000")
        XCTAssertEqual(merged.textColor, "#111111")
        XCTAssertEqual(merged.shadow, true)
    }

    func testDecodesConfigAndReportsMissingKeys() throws {
        let json = """
        {
          "targets": [{ "preset": "iphone-6.9" }],
          "screens": [{ "file": "01", "title": "Line one\\nLine two" }]
        }
        """
        let url = root.appendingPathComponent("a.json")
        try Data(json.utf8).write(to: url)
        let config = try ProjectConfig.load(from: url)
        XCTAssertEqual(config.screens.first?.title, "Line one\nLine two")

        try Data(#"{ "screens": [] }"#.utf8).write(to: url)
        XCTAssertThrowsError(try ProjectConfig.load(from: url)) { error in
            XCTAssertEqual("\(error)", "invalid config: missing 'targets'")
        }
    }

    func testPlanOrdersScreensAndLocalizes() throws {
        try writeImage("screenshots/iphone/Second.PNG")
        try writeImage("screenshots/iphone/First.png")
        try writeImage("screenshots/iphone/Extra.png")
        try writeImage("screenshots/fi/iphone/first.png")
        try writeImage("screenshots/ipad/First.png")

        let config = ProjectConfig(
            locales: ["en", "fi"],
            style: StyleConfig(background: "#202020"),
            targets: [
                TargetConfig(preset: "iphone-6.9"),
                TargetConfig(preset: "ipad-13", style: StyleConfig(background: "#F4F4F6")),
            ],
            screens: [
                ScreenConfig(file: "First", title: "Hello", subtitle: "Sub",
                             localized: ["fi": CaptionConfig(title: "Hei")]),
                ScreenConfig(file: "second.png", title: "Two"),
            ]
        )
        let plan = try config.plan(baseDirectory: root)

        let names = plan.jobs.map { "\($0.locale!)/\($0.target)/\($0.output.lastPathComponent)" }
        XCTAssertEqual(names, [
            "en/iphone-6.9/01_First.png", "en/iphone-6.9/02_second.png",
            "fi/iphone-6.9/01_First.png", "fi/iphone-6.9/02_second.png",
            "en/ipad-13/01_First.png", "fi/ipad-13/01_First.png",
        ])

        let fiFirst = plan.jobs[2]
        XCTAssertEqual(fiFirst.options.title, "Hei")
        XCTAssertEqual(fiFirst.options.subtitle, "Sub")
        XCTAssertEqual(fiFirst.screenshot.resolvingSymlinksInPath().path,
                       root.appendingPathComponent("screenshots/fi/iphone/first.png").resolvingSymlinksInPath().path)
        XCTAssertEqual(plan.jobs[3].screenshot.lastPathComponent, "Second.PNG")
        XCTAssertEqual(plan.jobs[4].options.layout, .ipad)
        XCTAssertEqual(plan.jobs[4].options.width, 2048)

        XCTAssertTrue(plan.warnings.contains { $0.contains("Extra.png in") && $0.contains("is not listed") })
        XCTAssertTrue(plan.warnings.contains { $0 == "fi: no translated caption for First, second.png; using the default" })
        XCTAssertTrue(plan.warnings.contains { $0 == "ipad-13 (en): second.png not found; skipped" })

        let filtered = try config.plan(baseDirectory: root, locale: "fi", target: "ipad-13")
        XCTAssertEqual(filtered.jobs.count, 1)
        XCTAssertThrowsError(try config.plan(baseDirectory: root, locale: "de"))
        XCTAssertThrowsError(try config.plan(baseDirectory: root, target: "mac-16"))
    }

    func testDeviceTitlesBreakAfterThreeWords() throws {
        try writeImage("screenshots/mac/a.png")
        try writeImage("screenshots/iphone/a.png")
        let config = ProjectConfig(
            targets: [TargetConfig(preset: "mac-16"), TargetConfig(preset: "iphone-6.9")],
            screens: [ScreenConfig(file: "a", title: "Track progress for every project")]
        )
        let titles = try config.plan(baseDirectory: root).jobs.map(\.options.title)
        XCTAssertEqual(titles, ["Track progress for every project", "Track progress for\nevery project"])
    }

    func testLocaleOnlyScreenshots() throws {
        try writeImage("screenshots/en/iphone/a.png")
        try writeImage("screenshots/fi/iphone/b.png")
        let config = ProjectConfig(
            locales: ["en", "fi"],
            targets: [TargetConfig(preset: "iphone-6.9")],
            screens: [ScreenConfig(file: "a")]
        )
        let plan = try config.plan(baseDirectory: root)
        XCTAssertEqual(plan.jobs.map { "\($0.locale!)/\($0.output.lastPathComponent)" }, ["en/01_a.png"])
        XCTAssertTrue(plan.warnings.contains { $0 == "iphone-6.9 (fi): a not found; skipped" })
        XCTAssertTrue(plan.warnings.contains { $0.contains("b.png in") && $0.contains("is not listed") })
    }

    func testPlanRejectsInvalidConfigs() throws {
        let screens = [ScreenConfig(file: "a")]
        func error(_ config: ProjectConfig) -> ConfigError? {
            do { _ = try config.plan(baseDirectory: root); return nil } catch { return error as? ConfigError }
        }
        XCTAssertEqual(error(ProjectConfig(targets: [], screens: screens)), .noTargets)
        XCTAssertEqual(error(ProjectConfig(targets: [TargetConfig(preset: "nope")], screens: screens)),
                       .unknownPreset("nope"))
        XCTAssertEqual(error(ProjectConfig(targets: [TargetConfig(preset: "mac-16"), TargetConfig(preset: "2880x1800")],
                                           screens: screens)), .duplicateTarget("mac-16"))
        XCTAssertEqual(error(ProjectConfig(targets: [TargetConfig(preset: "mac-16")],
                                           screens: [ScreenConfig(file: "a.png"), ScreenConfig(file: "A")])),
                       .duplicateScreen("A"))
        XCTAssertEqual(error(ProjectConfig(targets: [TargetConfig(size: "100x200")], screens: screens)),
                       .invalidTarget("size '100x200' needs a layout (mac, iphone or ipad)"))
        XCTAssertEqual(error(ProjectConfig(locales: ["fi", "fi"], targets: [TargetConfig(preset: "mac-16")],
                                           screens: screens)), .duplicateLocale("fi"))
        XCTAssertEqual(error(ProjectConfig(targets: [TargetConfig(preset: "mac-16", name: "../x")], screens: screens)),
                       .invalidFolderName("../x"))

        try writeImage("screenshots/a.png")
        XCTAssertEqual(error(ProjectConfig(style: StyleConfig(background: "red"),
                                           targets: [TargetConfig(preset: "mac-16")], screens: screens)),
                       .invalidColor("red"))
    }

    func testScaffoldUsesLayoutFoldersAndFileNames() throws {
        try writeImage("shots/iphone/Track every habit.PNG")
        try writeImage("shots/ipad/Track every habit.PNG")
        try writeImage("shots/ipad/Dark - mode.png")

        let config = ProjectConfig.scaffold(
            screenshotsRoot: root.appendingPathComponent("shots"), relativePath: "shots"
        )
        XCTAssertEqual(config.targets.map(\.preset), ["iphone-6.9", "ipad-13"])
        XCTAssertEqual(config.screens.map(\.file), ["Track every habit", "Dark - mode"])
        XCTAssertEqual(config.screens.map(\.title), ["Track every habit", "Dark\nmode"])

        try writeImage("shots/mac/x.png")
        try writeImage("shots/y.png")
        let mixed = ProjectConfig.scaffold(screenshotsRoot: root.appendingPathComponent("shots"), relativePath: "shots")
        XCTAssertEqual(mixed.targets.map(\.name), [nil, nil, nil, "mac-16-root"])
        XCTAssertNoThrow(try mixed.plan(baseDirectory: root))

        let decoded = try JSONDecoder().decode(ProjectConfig.self, from: config.encoded())
        XCTAssertEqual(decoded, config)
    }

    func testRenderProducesRequestedSize() throws {
        try writeImage("shot.png", width: 300, height: 600)
        let image = try XCTUnwrap(NSImage(contentsOf: root.appendingPathComponent("shot.png")))
        for (width, height, layout) in [(400, 250, Layout.mac), (200, 400, .iphone)] {
            let options = RenderOptions(
                width: width, height: height, layout: layout, title: "Title", subtitle: "Sub",
                backgroundColor: parseHexColor("#1C1C1E")!, textColor: .white
            )
            let data = try renderPreview(screenshot: image, options: options)
            let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
            XCTAssertEqual(rep.pixelsWide, width)
            XCTAssertEqual(rep.pixelsHigh, height)
        }
    }

    func testOutputMayNotBeAScreenshotFolder() throws {
        try writeImage("iphone/01_Home.png")
        let config = ProjectConfig(
            screenshots: ".", output: ".",
            targets: [TargetConfig(preset: "iphone-6.9", name: "iphone")],
            screens: [ScreenConfig(file: "01_Home")]
        )
        XCTAssertThrowsError(try config.plan(baseDirectory: root)) { error in
            guard case ConfigError.outputIsInputFolder = error else { return XCTFail("\(error)") }
        }
    }

    func testFirstLocaleNeedsNoTranslation() throws {
        try writeImage("screenshots/mac/a.png")
        let config = ProjectConfig(
            locales: ["en", "fi"],
            targets: [TargetConfig(preset: "mac-16")],
            screens: [ScreenConfig(file: "a", title: "Hello")]
        )
        XCTAssertEqual(try config.plan(baseDirectory: root).warnings,
                       ["fi: no translated caption for a; using the default"])
    }

    func testScaffoldFindsLocaleFolders() throws {
        try writeImage("shots/fi/iphone/b.png")
        try writeImage("shots/en/iphone/a.png")
        try writeImage("shots/en/mac/a.png")
        let config = ProjectConfig.scaffold(screenshotsRoot: root.appendingPathComponent("shots"), relativePath: "shots")
        XCTAssertEqual(config.locales, ["en", "fi"])
        XCTAssertEqual(config.targets.map(\.preset), ["mac-16", "iphone-6.9"])
        XCTAssertEqual(Set(config.screens.map(\.file)), ["a", "b"])
        XCTAssertNoThrow(try config.plan(baseDirectory: root))
    }

    func testRenderAcceptsNonRGBColors() throws {
        try writeImage("shot.png", width: 30, height: 60)
        let image = try XCTUnwrap(NSImage(contentsOf: root.appendingPathComponent("shot.png")))
        let options = RenderOptions(width: 100, height: 200, layout: .iphone, title: "Hi",
                                    backgroundColor: .black, textColor: .white)
        XCTAssertNoThrow(try renderPreview(screenshot: image, options: options))
    }

    func testSanitizeKeepsNamesReadable() {
        XCTAssertEqual(sanitize("plan your week"), "plan-your-week")
        XCTAssertEqual(sanitize("stats at a glance!"), "stats-at-a-glance")
        XCTAssertEqual(sanitize("***"), "screen")
    }
}

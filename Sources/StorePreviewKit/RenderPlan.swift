import AppKit

public struct RenderJob {
    public let screenshot: URL
    public let output: URL
    public let options: RenderOptions
    public let locale: String?
    public let target: String
    public let screen: String
}

/// The resolved list of images a config produces, plus non-fatal problems.
public struct RenderPlan {
    public var jobs: [RenderJob] = []
    public var warnings: [String] = []
    /// Folders the jobs write into, in first-use order.
    public var outputDirectories: [URL] = []
}

struct ResolvedTarget {
    let name: String
    let width: Int
    let height: Int
    let layout: Layout
    let input: String
    let style: StyleConfig?
}

extension ProjectConfig {
    /// Resolves the config into render jobs. Paths are relative to `baseDirectory`
    /// (the folder holding the config file). `locale` and `target` limit the plan.
    /// `styleOverride` wins over every style in the config, e.g. a background
    /// given on the command line.
    public func plan(
        baseDirectory: URL,
        locale onlyLocale: String? = nil,
        target onlyTarget: String? = nil,
        styleOverride: StyleConfig? = nil,
        fileManager: FileManager = .default
    ) throws -> RenderPlan {
        guard !targets.isEmpty else { throw ConfigError.noTargets }
        guard !screens.isEmpty else { throw ConfigError.noScreens }

        let screenshotsRoot = baseDirectory.appendingPathComponent(screenshots ?? "screenshots", isDirectory: true)
        let outputRoot = baseDirectory.appendingPathComponent(output ?? "previews", isDirectory: true)

        var seenScreens = Set<String>()
        for screen in screens {
            let key = screenKey(screen.file)
            guard seenScreens.insert(key).inserted else { throw ConfigError.duplicateScreen(screen.file) }
        }

        let configLocales = locales ?? []
        var seenLocales = Set<String>()
        for locale in configLocales {
            guard isSafeFolderName(locale) else { throw ConfigError.invalidFolderName(locale) }
            guard seenLocales.insert(locale).inserted else { throw ConfigError.duplicateLocale(locale) }
        }

        var resolved = try targets.map {
            try resolve($0, screenshotsRoot: screenshotsRoot, locales: configLocales, fileManager: fileManager)
        }
        var seenTargets = Set<String>()
        for target in resolved {
            guard isSafeFolderName(target.name) else { throw ConfigError.invalidFolderName(target.name) }
            guard seenTargets.insert(target.name).inserted else { throw ConfigError.duplicateTarget(target.name) }
        }
        if let onlyTarget {
            resolved = resolved.filter { $0.name == onlyTarget }
            guard !resolved.isEmpty else { throw ConfigError.unknownTarget(onlyTarget) }
        }

        let allLocales: [String?] = configLocales.isEmpty ? [nil] : configLocales.map { $0 }
        var runLocales = allLocales
        if let onlyLocale {
            guard allLocales.contains(onlyLocale) else { throw ConfigError.unknownLocale(onlyLocale) }
            runLocales = [onlyLocale]
        }

        // Every folder screenshots are read from. Output must never land in one,
        // or rendering (and --clean) would mix with or delete the originals.
        var inputFolders = Set<String>()
        for target in resolved {
            for locale in [nil] + configLocales.map { Optional($0) } {
                var folder = screenshotsRoot
                if let locale { folder.appendPathComponent(locale, isDirectory: true) }
                inputFolders.insert(canonicalPath(folder.appendingPathComponent(target.input, isDirectory: true)))
            }
        }

        var plan = RenderPlan()
        var warned = Set<String>()
        func warn(_ message: String) {
            if warned.insert(message).inserted { plan.warnings.append(message) }
        }

        for target in resolved {
            let baseFolder = screenshotsRoot.appendingPathComponent(target.input, isDirectory: true)
            let baseImages = imageFiles(in: baseFolder, fileManager: fileManager)
            let listed = Set(screens.map { screenKey($0.file) })
            func warnUnlisted(_ images: [URL], in folder: URL) {
                for image in images where !listed.contains(screenKey(image.lastPathComponent)) {
                    warn("\(target.name): \(image.lastPathComponent) in \(folder.path) is not listed in screens; skipped")
                }
            }
            warnUnlisted(baseImages, in: baseFolder)

            for locale in runLocales {
                let localeFolder = locale.map {
                    screenshotsRoot.appendingPathComponent($0, isDirectory: true)
                        .appendingPathComponent(target.input, isDirectory: true)
                }
                let localeImages = localeFolder.map { imageFiles(in: $0, fileManager: fileManager) } ?? []
                if let localeFolder { warnUnlisted(localeImages, in: localeFolder) }
                if baseImages.isEmpty && localeImages.isEmpty {
                    warn("\(target.name)\(locale.map { " (\($0))" } ?? ""): no screenshots in "
                        + ([localeFolder, baseFolder].compactMap { $0?.path }.joined(separator: " or ")))
                    continue
                }
                var untranslated: [String] = []
                var targetOutput = outputRoot
                if let locale { targetOutput.appendPathComponent(locale, isDirectory: true) }
                targetOutput.appendPathComponent(target.name, isDirectory: true)
                guard !inputFolders.contains(canonicalPath(targetOutput)) else {
                    throw ConfigError.outputIsInputFolder(targetOutput.path)
                }

                for (index, screen) in screens.enumerated() {
                    guard let screenshot = find(screen.file, in: localeImages) ?? find(screen.file, in: baseImages) else {
                        warn("\(target.name)\(locale.map { " (\($0))" } ?? ""): \(screen.file) not found; skipped")
                        continue
                    }

                    var title = screen.title ?? ""
                    var subtitle = screen.subtitle ?? ""
                    if let locale {
                        let caption = screen.localized?[locale]
                        // The default captions are written in the first locale, so it needs no translation.
                        let isSourceLocale = locale == configLocales.first
                        if !isSourceLocale,
                           (!title.isEmpty && caption?.title == nil) || (!subtitle.isEmpty && caption?.subtitle == nil) {
                            untranslated.append(screen.file)
                        }
                        title = caption?.title ?? title
                        subtitle = caption?.subtitle ?? subtitle
                    }

                    let merged = (styleOverride ?? StyleConfig())
                        .over(screen.style)
                        .over(target.style)
                        .over(style)
                        .over(.defaults)
                    // Device titles break after three words for a two-line caption
                    // unless the caption already has a line break.
                    if target.layout != .mac { title = wrapAfterFirstWords(title, count: 3) }
                    let options = try renderOptions(
                        style: merged, target: target, title: title, subtitle: subtitle
                    )
                    let name = String(format: "%02d_%@.png", index + 1, sanitize(screenName(screen.file)))
                    if !plan.outputDirectories.contains(targetOutput) {
                        plan.outputDirectories.append(targetOutput)
                    }
                    plan.jobs.append(RenderJob(
                        screenshot: screenshot,
                        output: targetOutput.appendingPathComponent(name),
                        options: options,
                        locale: locale,
                        target: target.name,
                        screen: screen.file
                    ))
                }
                if let locale, !untranslated.isEmpty {
                    warn("\(locale): no translated caption for \(untranslated.joined(separator: ", ")); using the default")
                }
            }
        }
        return plan
    }

    func resolve(
        _ target: TargetConfig,
        screenshotsRoot: URL,
        locales: [String],
        fileManager: FileManager
    ) throws -> ResolvedTarget {
        let width: Int
        let height: Int
        let layout: Layout
        let defaultName: String
        if let presetName = target.preset {
            guard let preset = Preset.named(presetName) else { throw ConfigError.unknownPreset(presetName) }
            width = preset.width
            height = preset.height
            layout = target.layout ?? preset.layout
            defaultName = preset.name
        } else if let sizeText = target.size {
            guard let size = parseSize(sizeText) else {
                throw ConfigError.invalidTarget("size '\(sizeText)' must be WxH, e.g. 2880x1800")
            }
            guard let targetLayout = target.layout else {
                throw ConfigError.invalidTarget("size '\(sizeText)' needs a layout (mac, iphone or ipad)")
            }
            width = size.width
            height = size.height
            layout = targetLayout
            defaultName = "\(size.width)x\(size.height)"
        } else {
            throw ConfigError.invalidTarget("each target needs a preset, or a size and layout")
        }

        let input: String
        if let configured = target.input {
            input = configured
        } else {
            // The layout folder counts if it exists shared or under any locale.
            let candidates = [screenshotsRoot] + locales.map { screenshotsRoot.appendingPathComponent($0) }
            let hasLayoutFolder = candidates.contains { root in
                var isDirectory: ObjCBool = false
                let folder = root.appendingPathComponent(layout.rawValue).path
                return fileManager.fileExists(atPath: folder, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            input = hasLayoutFolder ? layout.rawValue : ""
        }

        return ResolvedTarget(
            name: target.name ?? defaultName,
            width: width,
            height: height,
            layout: layout,
            input: input,
            style: target.style
        )
    }
}

func renderOptions(style: StyleConfig, target: ResolvedTarget, title: String, subtitle: String) throws -> RenderOptions {
    let backgroundHex = style.background ?? StyleConfig.defaults.background!
    let textHex = style.textColor ?? StyleConfig.defaults.textColor!
    guard let background = parseHexColor(backgroundHex) else { throw ConfigError.invalidColor(backgroundHex) }
    guard let text = parseHexColor(textHex) else { throw ConfigError.invalidColor(textHex) }
    let gradient = style.gradient ?? StyleConfig.defaults.gradient!
    guard (0...1).contains(gradient) else { throw ConfigError.invalidGradient(gradient) }
    return RenderOptions(
        width: target.width,
        height: target.height,
        layout: target.layout,
        title: title,
        subtitle: subtitle,
        backgroundColor: background,
        textColor: text,
        fontName: style.fontName,
        fontSize: CGFloat(style.fontSize ?? 0),
        cornerRadius: CGFloat(style.cornerRadius ?? -1),
        padding: CGFloat(style.padding ?? 0),
        shadowEnabled: style.shadow ?? true,
        gradient: CGFloat(gradient)
    )
}

/// A screen's file name without an image extension.
func screenName(_ file: String) -> String {
    let url = URL(fileURLWithPath: file)
    return imageExtensions.contains(url.pathExtension.lowercased())
        ? url.deletingPathExtension().lastPathComponent
        : url.lastPathComponent
}

/// A screen's identity: its name compared case-insensitively.
func screenKey(_ file: String) -> String {
    screenName(file).lowercased()
}

func canonicalPath(_ url: URL) -> String {
    url.resolvingSymlinksInPath().standardizedFileURL.path
}

func isSafeFolderName(_ name: String) -> Bool {
    !name.isEmpty && name != "." && name != ".." && !name.contains("/")
}

func find(_ file: String, in images: [URL]) -> URL? {
    let key = screenKey(file)
    return images.first { screenKey($0.lastPathComponent) == key }
}

func sanitize(_ name: String) -> String {
    let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
    let mapped = name.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
    let collapsed = String(mapped).split(separator: "-", omittingEmptySubsequences: true).joined(separator: "-")
    return collapsed.isEmpty ? "screen" : collapsed
}

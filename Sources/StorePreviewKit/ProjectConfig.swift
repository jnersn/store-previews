import AppKit

/// Style settings. Every field is optional so a target or screen can override
/// only what it changes; unset fields fall back to the next level up
/// (screen -> target -> project -> built-in defaults).
public struct StyleConfig: Codable, Equatable {
    public var background: String?
    public var textColor: String?
    public var fontName: String?
    public var fontSize: Double?
    public var cornerRadius: Double?
    public var padding: Double?
    public var shadow: Bool?
    /// How much darker the bottom of the background is than the top, 0 (flat) to 1 (black).
    public var gradient: Double?

    public init(
        background: String? = nil,
        textColor: String? = nil,
        fontName: String? = nil,
        fontSize: Double? = nil,
        cornerRadius: Double? = nil,
        padding: Double? = nil,
        shadow: Bool? = nil,
        gradient: Double? = nil
    ) {
        self.background = background
        self.textColor = textColor
        self.fontName = fontName
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.shadow = shadow
        self.gradient = gradient
    }

    /// Returns `self` with unset fields taken from `base`.
    public func over(_ base: StyleConfig?) -> StyleConfig {
        guard let base else { return self }
        return StyleConfig(
            background: background ?? base.background,
            textColor: textColor ?? base.textColor,
            fontName: fontName ?? base.fontName,
            fontSize: fontSize ?? base.fontSize,
            cornerRadius: cornerRadius ?? base.cornerRadius,
            padding: padding ?? base.padding,
            shadow: shadow ?? base.shadow,
            gradient: gradient ?? base.gradient
        )
    }

    public static let defaults = StyleConfig(background: "#1C1C1E", textColor: "#FFFFFF", shadow: true, gradient: 0.3)
}

public struct CaptionConfig: Codable, Equatable {
    public var title: String?
    public var subtitle: String?

    public init(title: String? = nil, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }
}

public struct ScreenConfig: Codable, Equatable {
    /// Screenshot file name, with or without extension, looked up in each target's folder.
    public var file: String
    public var title: String?
    public var subtitle: String?
    public var style: StyleConfig?
    /// Translated captions keyed by locale. Missing fields fall back to `title`/`subtitle`.
    public var localized: [String: CaptionConfig]?

    public init(
        file: String,
        title: String? = nil,
        subtitle: String? = nil,
        style: StyleConfig? = nil,
        localized: [String: CaptionConfig]? = nil
    ) {
        self.file = file
        self.title = title
        self.subtitle = subtitle
        self.style = style
        self.localized = localized
    }
}

public struct TargetConfig: Codable, Equatable {
    /// A preset name such as `iphone-6.9`. Alternatively give `size` and `layout`.
    public var preset: String?
    public var size: String?
    public var layout: Layout?
    /// Screenshot folder relative to the project's `screenshots` folder.
    /// Defaults to the layout name (`mac`, `iphone`, `ipad`) when that folder exists.
    public var input: String?
    /// Output folder name. Defaults to the preset name or the size.
    public var name: String?
    public var style: StyleConfig?

    public init(
        preset: String? = nil,
        size: String? = nil,
        layout: Layout? = nil,
        input: String? = nil,
        name: String? = nil,
        style: StyleConfig? = nil
    ) {
        self.preset = preset
        self.size = size
        self.layout = layout
        self.input = input
        self.name = name
        self.style = style
    }
}

/// The contents of a `store-previews.json` file.
public struct ProjectConfig: Codable, Equatable {
    /// Screenshot root, relative to the config file. Default: `screenshots`.
    public var screenshots: String?
    /// Output root, relative to the config file. Default: `previews`.
    public var output: String?
    /// Locales to render. When set, output goes to `<output>/<locale>/<target>/`
    /// and `<screenshots>/<locale>/<input>/` is preferred when it has the file.
    /// The default `title`/`subtitle` are in the first locale.
    public var locales: [String]?
    public var style: StyleConfig?
    public var targets: [TargetConfig]
    /// Screens in App Store order.
    public var screens: [ScreenConfig]

    public init(
        screenshots: String? = nil,
        output: String? = nil,
        locales: [String]? = nil,
        style: StyleConfig? = nil,
        targets: [TargetConfig],
        screens: [ScreenConfig]
    ) {
        self.screenshots = screenshots
        self.output = output
        self.locales = locales
        self.style = style
        self.targets = targets
        self.screens = screens
    }

    public static func load(from url: URL) throws -> ProjectConfig {
        let data = try Data(contentsOf: url)
        do {
            return try JSONDecoder().decode(ProjectConfig.self, from: data)
        } catch let error as DecodingError {
            throw ConfigError.invalidJSON(describe(error))
        }
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}

public enum ConfigError: Error, Equatable, CustomStringConvertible {
    case invalidJSON(String)
    case noTargets
    case noScreens
    case unknownPreset(String)
    case invalidTarget(String)
    case duplicateTarget(String)
    case duplicateScreen(String)
    case invalidColor(String)
    case invalidGradient(Double)
    case unknownLocale(String)
    case unknownTarget(String)
    case duplicateLocale(String)
    case invalidFolderName(String)
    case outputIsInputFolder(String)

    public var description: String {
        switch self {
        case .invalidJSON(let detail): return "invalid config: \(detail)"
        case .noTargets: return "config has no targets"
        case .noScreens: return "config has no screens"
        case .unknownPreset(let name): return "unknown preset '\(name)' (run `store-previews presets`)"
        case .invalidTarget(let detail): return "invalid target: \(detail)"
        case .duplicateTarget(let name): return "two targets share the output name '\(name)'; set `name` on one"
        case .duplicateScreen(let file): return "screen '\(file)' is listed twice"
        case .invalidColor(let value): return "invalid color '\(value)', expected #RRGGBB"
        case .invalidGradient(let value): return "invalid gradient \(value), expected a number from 0 to 1"
        case .unknownLocale(let locale): return "locale '\(locale)' is not in the config's locales"
        case .unknownTarget(let name): return "no target named '\(name)'"
        case .duplicateLocale(let locale): return "locale '\(locale)' is listed twice"
        case .invalidFolderName(let name):
            return "'\(name)' can't be used as a folder name (no '/', '.' or '..')"
        case .outputIsInputFolder(let path):
            return "output folder \(path) is also a screenshot folder; set a different `output` or target `name`"
        }
    }
}

private func describe(_ error: DecodingError) -> String {
    func path(_ context: DecodingError.Context) -> String {
        let keys = context.codingPath.map { $0.intValue.map { "[\($0)]" } ?? ".\($0.stringValue)" }.joined()
        return keys.isEmpty ? "" : " at \(keys.hasPrefix(".") ? String(keys.dropFirst()) : keys)"
    }
    switch error {
    case .keyNotFound(let key, let context): return "missing '\(key.stringValue)'\(path(context))"
    case .typeMismatch(_, let context), .valueNotFound(_, let context), .dataCorrupted(let context):
        return "\(context.debugDescription)\(path(context))"
    @unknown default: return "\(error)"
    }
}

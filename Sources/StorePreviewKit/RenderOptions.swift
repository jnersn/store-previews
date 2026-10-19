import AppKit

public enum Layout: String, Codable, CaseIterable {
    case mac
    case iphone
    case ipad
}

public struct Preset: Equatable {
    public let name: String
    public let width: Int
    public let height: Int
    public let layout: Layout
    public let aliases: [String]

    public static let all: [Preset] = [
        Preset(name: "mac-16", width: 2880, height: 1800, layout: .mac, aliases: ["macbook-16"]),
        Preset(name: "mac-13", width: 2560, height: 1600, layout: .mac, aliases: ["macbook-13"]),
        Preset(name: "iphone-6.9", width: 1290, height: 2796, layout: .iphone, aliases: ["iphone-69"]),
        Preset(name: "iphone-6.9-lg", width: 1320, height: 2868, layout: .iphone, aliases: ["iphone-69-lg"]),
        Preset(name: "iphone-6.3", width: 1179, height: 2556, layout: .iphone, aliases: ["iphone-63"]),
        Preset(name: "iphone-6.5", width: 1284, height: 2778, layout: .iphone, aliases: ["iphone-65"]),
        Preset(name: "ipad-13", width: 2048, height: 2732, layout: .ipad,
               aliases: ["ipad-129", "ipad-12.9", "ipad-portrait"]),
        Preset(name: "ipad-13-land", width: 2732, height: 2048, layout: .ipad,
               aliases: ["ipad-129-land", "ipad-12.9-land", "ipad-landscape"]),
    ]

    /// Looks up a preset by name, alias or its `WxH` size.
    public static func named(_ name: String) -> Preset? {
        let key = name.lowercased()
        return all.first { $0.name == key || $0.aliases.contains(key) || "\($0.width)x\($0.height)" == key }
    }

    /// The preset `init` uses for screenshots in a `mac`, `iphone` or `ipad` folder.
    public static func defaultPreset(for layout: Layout) -> Preset {
        switch layout {
        case .mac: return named("mac-16")!
        case .iphone: return named("iphone-6.9")!
        case .ipad: return named("ipad-13")!
        }
    }
}

/// Everything needed to render one preview image.
public struct RenderOptions {
    public var width: Int
    public var height: Int
    public var layout: Layout
    public var title: String
    public var subtitle: String
    public var backgroundColor: NSColor
    public var textColor: NSColor
    public var fontName: String?
    public var fontSize: CGFloat        // 0 = auto
    public var cornerRadius: CGFloat    // < 0 = auto
    public var padding: CGFloat         // 0 = auto
    public var shadowEnabled: Bool
    public var gradient: CGFloat        // 0 = flat, 1 = bottom fades to black

    public init(
        width: Int,
        height: Int,
        layout: Layout,
        title: String = "",
        subtitle: String = "",
        backgroundColor: NSColor,
        textColor: NSColor,
        fontName: String? = nil,
        fontSize: CGFloat = 0,
        cornerRadius: CGFloat = -1,
        padding: CGFloat = 0,
        shadowEnabled: Bool = true,
        gradient: CGFloat = 0.3
    ) {
        self.width = width
        self.height = height
        self.layout = layout
        self.title = title
        self.subtitle = subtitle
        self.backgroundColor = backgroundColor
        self.textColor = textColor
        self.fontName = fontName
        self.fontSize = fontSize
        self.cornerRadius = cornerRadius
        self.padding = padding
        self.shadowEnabled = shadowEnabled
        self.gradient = gradient
    }
}

public func parseHexColor(_ hex: String) -> NSColor? {
    var h = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if h.hasPrefix("#") { h.removeFirst() }
    guard h.count == 6, let val = UInt64(h, radix: 16) else { return nil }
    return NSColor(
        red: CGFloat((val >> 16) & 0xFF) / 255,
        green: CGFloat((val >> 8) & 0xFF) / 255,
        blue: CGFloat(val & 0xFF) / 255,
        alpha: 1
    )
}

public func parseSize(_ text: String) -> (width: Int, height: Int)? {
    let parts = text.lowercased().split(separator: "x")
    guard parts.count == 2, let w = Int(parts[0]), let h = Int(parts[1]), w > 0, h > 0 else { return nil }
    return (w, h)
}

/// Derives a title from a filename.
/// - Underscores and hyphens become spaces
/// - A literal " - " (space-dash-space) in the filename acts as a line break
public func titleFromFilename(_ filename: String) -> String {
    filename
        .replacingOccurrences(of: " - ", with: "\n")
        .replacingOccurrences(of: "_", with: " ")
        .replacingOccurrences(of: "-", with: " ")
}

public func wrapAfterFirstWords(_ text: String, count: Int) -> String {
    guard !text.contains("\n") else { return text }
    let words = text.split(separator: " ")
    guard words.count > count else { return text }
    return words.prefix(count).joined(separator: " ")
        + "\n"
        + words.dropFirst(count).joined(separator: " ")
}

let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "tiff", "bmp"]

/// Image files directly inside `directory`, sorted by name.
public func imageFiles(in directory: URL, fileManager: FileManager = .default) -> [URL] {
    let files = (try? fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
    return files
        .filter { imageExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
}

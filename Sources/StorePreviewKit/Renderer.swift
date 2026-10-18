import AppKit

public enum RenderError: Error, CustomStringConvertible {
    case bitmapCreationFailed
    case pngEncodingFailed

    public var description: String {
        switch self {
        case .bitmapCreationFailed: return "failed to create bitmap"
        case .pngEncodingFailed: return "failed to encode PNG"
        }
    }
}

// MARK: - Font Resolution

func resolveFont(name: String?, size: CGFloat, weight: NSFont.Weight = .bold) -> NSFont {
    if let name = name, let font = NSFont(name: name, size: size) {
        return font
    }
    // Prefer SF Pro Rounded if available, fall back to system bold
    if let descriptor = NSFont.systemFont(ofSize: size, weight: weight).fontDescriptor.withDesign(.rounded),
       let rounded = NSFont(descriptor: descriptor, size: size) {
        return rounded
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

// MARK: - Text Drawing

struct TextBlock {
    let string: NSAttributedString
    let boundingSize: CGSize
}

func makeTextBlock(text: String, font: NSFont, color: NSColor, maxWidth: CGFloat) -> TextBlock {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = 4

    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: style
    ]
    let attrStr = NSAttributedString(string: text, attributes: attrs)
    let bounds = attrStr.boundingRect(
        with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    return TextBlock(string: attrStr, boundingSize: CGSize(width: ceil(bounds.width), height: ceil(bounds.height)))
}

// MARK: - Preview Generation

func makeBitmapRep(width: Int, height: Int) -> NSBitmapImageRep? {
    NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )
}

func downsample(rep: NSBitmapImageRep, width: Int, height: Int) -> NSBitmapImageRep? {
    guard let outputRep = makeBitmapRep(width: width, height: height) else { return nil }
    guard let outputContext = NSGraphicsContext(bitmapImageRep: outputRep) else { return nil }

    let outputSize = CGSize(width: width, height: height)
    rep.size = outputSize

    let image = NSImage(size: outputSize)
    image.addRepresentation(rep)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = outputContext
    outputContext.imageInterpolation = .high

    let cg = outputContext.cgContext
    cg.setShouldAntialias(true)
    cg.setAllowsAntialiasing(true)
    cg.interpolationQuality = .high

    image.draw(
        in: CGRect(origin: .zero, size: outputSize),
        from: CGRect(origin: .zero, size: outputSize),
        operation: .copy,
        fraction: 1.0
    )

    NSGraphicsContext.restoreGraphicsState()

    return outputRep
}

/// Renders one App Store preview and returns it as PNG data.
public func renderPreview(screenshot: NSImage, options: RenderOptions) throws -> Data {
    let cw = CGFloat(options.width)
    let ch = CGFloat(options.height)
    let renderScale = options.layout == .mac ? 1 : 4

    // Create bitmap
    guard let rep = makeBitmapRep(width: options.width * renderScale, height: options.height * renderScale) else {
        throw RenderError.bitmapCreationFailed
    }

    guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
        throw RenderError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    ctx.imageInterpolation = .high
    let cg = ctx.cgContext
    cg.scaleBy(x: CGFloat(renderScale), y: CGFloat(renderScale))
    cg.setShouldAntialias(true)
    cg.setAllowsAntialiasing(true)
    cg.interpolationQuality = .high

    // 1. Fill background with vertical gradient (top to bottom)
    do {
        // Component accessors need an RGB color; callers may pass e.g. NSColor.black (grayscale).
        let background = options.backgroundColor.usingColorSpace(.sRGB) ?? .black
        let topColor = background.cgColor
        // Derive bottom color: darken by blending toward black
        let bottomColor = NSColor(
            red: background.redComponent * 0.7,
            green: background.greenComponent * 0.7,
            blue: background.blueComponent * 0.7,
            alpha: 1
        ).cgColor
        let colors = [topColor, bottomColor] as CFArray
        if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                     colors: colors, locations: [0, 1]) {
            // In AppKit coords: y=ch is top, y=0 is bottom
            cg.drawLinearGradient(
                gradient,
                start: CGPoint(x: cw / 2, y: ch),
                end: CGPoint(x: cw / 2, y: 0),
                options: []
            )
        }
    }

    switch options.layout {
    case .mac:
        drawMacPreview(screenshot: screenshot, options: options, context: cg, canvasSize: CGSize(width: cw, height: ch))
    case .iphone:
        drawIPhonePreview(screenshot: screenshot, options: options, context: cg, canvasSize: CGSize(width: cw, height: ch))
    case .ipad:
        drawIPadPreview(screenshot: screenshot, options: options, context: cg, canvasSize: CGSize(width: cw, height: ch))
    }

    NSGraphicsContext.restoreGraphicsState()

    let outputRep: NSBitmapImageRep
    if renderScale > 1 {
        guard let downsampledRep = downsample(rep: rep, width: options.width, height: options.height) else {
            throw RenderError.bitmapCreationFailed
        }
        outputRep = downsampledRep
    } else {
        outputRep = rep
    }

    // 7. Encode PNG
    guard let pngData = outputRep.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncodingFailed
    }
    return pngData
}

func drawMacPreview(screenshot: NSImage, options: RenderOptions, context cg: CGContext, canvasSize: CGSize) {
    let cw = canvasSize.width
    let ch = canvasSize.height

    // 2. Layout calculations
    let sidePadding = options.padding > 0 ? options.padding : cw * 0.06
    let textMaxWidth = cw - sidePadding * 2
    let hasTitle = !options.title.isEmpty
    let hasSubtitle = !options.subtitle.isEmpty

    // Build text blocks
    let titleFontSize = options.fontSize > 0 ? options.fontSize : ch * 0.056
    let subtitleFontSize = titleFontSize * 0.55

    var titleBlock: TextBlock?
    var subtitleBlock: TextBlock?
    var totalTextHeight: CGFloat = 0
    let textGap: CGFloat = ch * 0.015

    if hasTitle {
        let font = resolveFont(name: options.fontName, size: titleFontSize, weight: .bold)
        titleBlock = makeTextBlock(text: options.title, font: font, color: options.textColor, maxWidth: textMaxWidth)
        totalTextHeight += titleBlock!.boundingSize.height
    }
    if hasSubtitle {
        let font = resolveFont(name: options.fontName, size: subtitleFontSize, weight: .medium)
        subtitleBlock = makeTextBlock(text: options.subtitle, font: font, color: options.textColor.withAlphaComponent(0.8), maxWidth: textMaxWidth)
        totalTextHeight += subtitleBlock!.boundingSize.height
        if hasTitle { totalTextHeight += textGap }
    }

    // Title zone: top portion of canvas
    let topMargin = ch * 0.02
    let titleZoneTop = ch - topMargin
    let titleZoneBottom: CGFloat
    if hasTitle || hasSubtitle {
        titleZoneBottom = titleZoneTop - totalTextHeight - ch * 0.06
    } else {
        titleZoneBottom = ch - ch * 0.04
    }

    // Draw title and subtitle centered in title zone
    if totalTextHeight > 0 {
        let titleZoneHeight = titleZoneTop - titleZoneBottom
        var textY = titleZoneBottom + (titleZoneHeight - totalTextHeight) / 2

        // Draw subtitle first (lower y = drawn first in bottom-up coordinates)
        if let sub = subtitleBlock {
            let subRect = CGRect(
                x: sidePadding,
                y: textY,
                width: textMaxWidth,
                height: sub.boundingSize.height
            )
            sub.string.draw(in: subRect)
            textY += sub.boundingSize.height + textGap
        }

        if let ttl = titleBlock {
            let ttlRect = CGRect(
                x: sidePadding,
                y: textY,
                width: textMaxWidth,
                height: ttl.boundingSize.height
            )
            ttl.string.draw(in: ttlRect)
        }
    }

    // 3. Screenshot placement — anchored at top, overflows bottom edge
    let screenshotSize = screenshot.size
    let screenshotAreaTop = titleZoneBottom - ch * 0.02
    let screenshotSidePadding = sidePadding * 0.6  // tighter padding for the screenshot
    let availableWidth = cw - screenshotSidePadding * 2

    // Scale to fill available width; height overflows naturally at bottom
    let scale = availableWidth / screenshotSize.width
    let scaledW = screenshotSize.width * scale
    let scaledH = screenshotSize.height * scale

    let ssX = (cw - scaledW) / 2
    let ssY = screenshotAreaTop - scaledH  // negative = overflows past bottom edge

    let screenshotRect = CGRect(x: ssX, y: ssY, width: scaledW, height: scaledH)
    let cornerRadius = options.cornerRadius >= 0 ? options.cornerRadius : 20

    // Helper: path with only top corners rounded (bottom extends off-canvas)
    func topRoundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let minX = rect.minX, maxX = rect.maxX
        let minY = rect.minY, maxY = rect.maxY
        let r = min(radius, rect.width / 2, rect.height / 2)
        path.move(to: CGPoint(x: minX, y: minY))                          // bottom-left
        path.addLine(to: CGPoint(x: maxX, y: minY))                       // bottom-right
        path.addLine(to: CGPoint(x: maxX, y: maxY - r))                   // right edge up
        path.addArc(tangent1End: CGPoint(x: maxX, y: maxY),
                    tangent2End: CGPoint(x: maxX - r, y: maxY), radius: r) // top-right corner
        path.addLine(to: CGPoint(x: minX + r, y: maxY))                   // top edge
        path.addArc(tangent1End: CGPoint(x: minX, y: maxY),
                    tangent2End: CGPoint(x: minX, y: maxY - r), radius: r) // top-left corner
        path.closeSubpath()
        return path
    }

    // 4. Draw screenshot with shadow using a transparency layer
    //    The shadow is derived from the layer's alpha, so it follows the
    //    screenshot's own shape (including macOS window rounded corners).
    //    Transparent corners naturally show the background color.
    cg.saveGState()
    if options.shadowEnabled {
        cg.setShadow(
            offset: CGSize(width: 0, height: -10),
            blur: 40,
            color: NSColor.black.withAlphaComponent(0.5).cgColor
        )
    }
    cg.beginTransparencyLayer(auxiliaryInfo: nil)

    let clipPath = topRoundedRectPath(screenshotRect, radius: cornerRadius)
    cg.addPath(clipPath)
    cg.clip()
    screenshot.draw(
        in: screenshotRect,
        from: NSRect(origin: .zero, size: screenshotSize),
        operation: .sourceOver,
        fraction: 1.0
    )

    cg.endTransparencyLayer()
    cg.restoreGState()
}

func drawIPhonePreview(screenshot: NSImage, options: RenderOptions, context cg: CGContext, canvasSize: CGSize) {
    drawDevicePreview(
        screenshot: screenshot,
        options: options,
        context: cg,
        canvasSize: canvasSize,
        style: DevicePreviewStyle(
            sidePaddingRatio: 0.075,
            titleFontRatio: 0.036,
            subtitleFontRatio: 0.48,
            textGapRatio: 0.009,
            titleTopMarginRatio: 0.04,
            screenshotGapRatio: 0.034,
            bezelWidthRatio: 0.02,
            cornerRadiusRatio: 0.14,
            screenCornerBezelMultiplier: 0.75,
            shadowOffset: CGSize(width: 0, height: -8),
            shadowBlur: 34,
            shadowOpacity: 0.32
        )
    )
}

func drawIPadPreview(screenshot: NSImage, options: RenderOptions, context cg: CGContext, canvasSize: CGSize) {
    drawDevicePreview(
        screenshot: screenshot,
        options: options,
        context: cg,
        canvasSize: canvasSize,
        style: DevicePreviewStyle(
            sidePaddingRatio: 0.06,
            titleFontRatio: 0.034,
            subtitleFontRatio: 0.48,
            textGapRatio: 0.008,
            titleTopMarginRatio: 0.04,
            screenshotGapRatio: 0.032,
            bezelWidthRatio: 0.014,
            cornerRadiusRatio: 0.03,
            screenCornerBezelMultiplier: 0.75,
            shadowOffset: CGSize(width: 0, height: -8),
            shadowBlur: 34,
            shadowOpacity: 0.28
        )
    )
}

struct DevicePreviewStyle {
    let sidePaddingRatio: CGFloat
    let titleFontRatio: CGFloat
    let subtitleFontRatio: CGFloat
    let textGapRatio: CGFloat
    let titleTopMarginRatio: CGFloat
    let screenshotGapRatio: CGFloat
    let bezelWidthRatio: CGFloat
    let cornerRadiusRatio: CGFloat
    let screenCornerBezelMultiplier: CGFloat
    let shadowOffset: CGSize
    let shadowBlur: CGFloat
    let shadowOpacity: CGFloat
}

func drawDevicePreview(
    screenshot: NSImage,
    options: RenderOptions,
    context cg: CGContext,
    canvasSize: CGSize,
    style: DevicePreviewStyle
) {
    let cw = canvasSize.width
    let ch = canvasSize.height

    let sidePadding = options.padding > 0 ? options.padding : cw * style.sidePaddingRatio
    let textMaxWidth = cw - sidePadding * 2
    let hasTitle = !options.title.isEmpty
    let hasSubtitle = !options.subtitle.isEmpty

    let titleFontSize = options.fontSize > 0 ? options.fontSize : ch * style.titleFontRatio
    let subtitleFontSize = titleFontSize * style.subtitleFontRatio
    let textGap = ch * style.textGapRatio
    let titleTopMargin = ch * style.titleTopMarginRatio
    let screenshotGap = ch * style.screenshotGapRatio
    let bottomPadding = sidePadding

    var titleBlock: TextBlock?
    var subtitleBlock: TextBlock?
    var totalTextHeight: CGFloat = 0

    if hasTitle {
        let font = resolveFont(name: options.fontName, size: titleFontSize, weight: .bold)
        titleBlock = makeTextBlock(text: options.title, font: font, color: options.textColor, maxWidth: textMaxWidth)
        totalTextHeight += titleBlock!.boundingSize.height
    }
    if hasSubtitle {
        let font = resolveFont(name: options.fontName, size: subtitleFontSize, weight: .medium)
        subtitleBlock = makeTextBlock(text: options.subtitle, font: font, color: options.textColor.withAlphaComponent(0.82), maxWidth: textMaxWidth)
        totalTextHeight += subtitleBlock!.boundingSize.height
        if hasTitle { totalTextHeight += textGap }
    }

    let textTop = ch - titleTopMargin
    var textBottom = textTop
    if totalTextHeight > 0 {
        let textY = textTop - totalTextHeight
        textBottom = textY

        if let ttl = titleBlock {
            let ttlRect = CGRect(
                x: sidePadding,
                y: textY + (subtitleBlock == nil ? 0 : subtitleBlock!.boundingSize.height + textGap),
                width: textMaxWidth,
                height: ttl.boundingSize.height
            )
            ttl.string.draw(in: ttlRect)
        }

        if let sub = subtitleBlock {
            let subRect = CGRect(
                x: sidePadding,
                y: textY,
                width: textMaxWidth,
                height: sub.boundingSize.height
            )
            sub.string.draw(in: subRect)
        }
    } else {
        textBottom = ch - titleTopMargin
    }

    let screenshotSize = screenshot.size
    let screenshotTop = textBottom - screenshotGap
    let availableHeight = max(1, screenshotTop - bottomPadding)
    let availableWidth = cw - sidePadding * 2
    let bezelWidth = cw * style.bezelWidthRatio

    let scale = min(
        (availableWidth - bezelWidth * 2) / screenshotSize.width,
        (availableHeight - bezelWidth * 2) / screenshotSize.height
    )
    let scaledW = screenshotSize.width * scale
    let scaledH = screenshotSize.height * scale
    let outerW = scaledW + bezelWidth * 2
    let outerH = scaledH + bezelWidth * 2
    let outerX = (cw - outerW) / 2
    let outerY = bottomPadding
    let outerRect = CGRect(x: outerX, y: outerY, width: outerW, height: outerH)
    let ssX = outerX + bezelWidth
    let ssY = outerY + bezelWidth
    let screenshotRect = CGRect(x: ssX, y: ssY, width: scaledW, height: scaledH)
    let cornerRadius = options.cornerRadius >= 0 ? options.cornerRadius : cw * style.cornerRadiusRatio
    let screenCornerRadius = max(0, cornerRadius - bezelWidth * style.screenCornerBezelMultiplier)

    cg.saveGState()
    if options.shadowEnabled {
        cg.setShadow(
            offset: style.shadowOffset,
            blur: style.shadowBlur,
            color: NSColor.black.withAlphaComponent(style.shadowOpacity).cgColor
        )
    }
    cg.beginTransparencyLayer(auxiliaryInfo: nil)

    let outerPath = CGPath(
        roundedRect: outerRect,
        cornerWidth: cornerRadius,
        cornerHeight: cornerRadius,
        transform: nil
    )
    let screenPath = CGPath(
        roundedRect: screenshotRect,
        cornerWidth: screenCornerRadius,
        cornerHeight: screenCornerRadius,
        transform: nil
    )

    cg.saveGState()
    cg.addPath(outerPath)
    cg.clip()
    screenshot.draw(
        in: screenshotRect,
        from: NSRect(origin: .zero, size: screenshotSize),
        operation: .sourceOver,
        fraction: 1.0
    )
    cg.restoreGState()

    let bezelPath = CGMutablePath()
    bezelPath.addPath(outerPath)
    bezelPath.addPath(screenPath)
    cg.addPath(bezelPath)
    cg.setFillColor(NSColor.black.cgColor)
    cg.drawPath(using: .eoFill)

    cg.addPath(outerPath)
    cg.setStrokeColor(NSColor.black.withAlphaComponent(0.35).cgColor)
    cg.setLineWidth(1.5)
    cg.strokePath()

    cg.endTransparencyLayer()
    cg.restoreGState()
}

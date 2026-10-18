import Foundation

extension ProjectConfig {
    /// Builds a starter config from a screenshot folder. Each `mac`, `iphone` or
    /// `ipad` subfolder becomes a target with that layout's default preset; loose
    /// images in the root become a `fallback` preset target. Other subfolders that
    /// hold layout folders (`en/iphone`, `fi/iphone`) become `locales`, in name
    /// order. Screens are the union of file names, titled from their file names.
    public static func scaffold(
        screenshotsRoot: URL,
        relativePath: String,
        fallback: Preset = Preset.defaultPreset(for: .mac),
        fileManager: FileManager = .default
    ) -> ProjectConfig {
        var targets: [TargetConfig] = []
        var names: [String] = []

        func collect(_ images: [URL]) {
            for image in images {
                let name = image.deletingPathExtension().lastPathComponent
                if !names.contains(where: { screenKey($0) == screenKey(name) }) { names.append(name) }
            }
        }

        let layoutNames = Set(Layout.allCases.map(\.rawValue))
        let subfolders = ((try? fileManager.contentsOfDirectory(
            at: screenshotsRoot, includingPropertiesForKeys: [.isDirectoryKey]
        )) ?? [])
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .map(\.lastPathComponent)
            .filter { !layoutNames.contains($0) && !$0.hasPrefix(".") }
            .sorted()
        var locales: [String] = []

        for layout in Layout.allCases {
            let shared = imageFiles(
                in: screenshotsRoot.appendingPathComponent(layout.rawValue, isDirectory: true),
                fileManager: fileManager
            )
            var found = !shared.isEmpty
            collect(shared)
            for locale in subfolders {
                let images = imageFiles(
                    in: screenshotsRoot.appendingPathComponent(locale).appendingPathComponent(layout.rawValue),
                    fileManager: fileManager
                )
                guard !images.isEmpty else { continue }
                found = true
                if !locales.contains(locale) { locales.append(locale) }
                collect(images)
            }
            if found { targets.append(TargetConfig(preset: Preset.defaultPreset(for: layout).name)) }
        }

        let rootImages = imageFiles(in: screenshotsRoot, fileManager: fileManager)
        if !rootImages.isEmpty {
            // Keep the output folder distinct from a layout-folder target with the same preset.
            let clashes = targets.contains { $0.preset == fallback.name }
            targets.append(TargetConfig(preset: fallback.name, input: "", name: clashes ? "\(fallback.name)-root" : nil))
            collect(rootImages)
        }

        return ProjectConfig(
            screenshots: relativePath,
            output: "previews",
            locales: locales.isEmpty ? nil : locales.sorted(),
            style: StyleConfig.defaults,
            targets: targets,
            screens: names.map { ScreenConfig(file: $0, title: titleFromFilename($0), subtitle: "") }
        )
    }
}

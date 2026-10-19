# store-previews

A command line tool for macOS that turns app screenshots into App Store preview
images: a gradient background, a title and subtitle, and the screenshot in an
iPhone or iPad frame or as a Mac window. Captions, screen order, translations
and styling live in a small JSON file next to your screenshots, so a single
command re-renders every size and language.

The rendering is also available as a Swift library, `StorePreviewKit`.

## Requirements

- macOS 13 or later
- Swift 5.10 or later (Xcode or the Command Line Tools)

## Install

With [Homebrew](https://brew.sh):

```sh
brew install jnersn/tap/store-previews
```

Homebrew builds the tool from the release source, which takes about a minute.
To use the short name `brew install store-previews`, tap and trust the tap
once: `brew tap jnersn/tap && brew trust jnersn/tap`.

With [Mint](https://github.com/yonaskolb/Mint): `mint install jnersn/store-previews`.

From source:

```sh
git clone https://github.com/jnersn/store-previews.git
cd store-previews
swift build -c release
cp .build/release/store-previews /usr/local/bin/   # or anywhere on your PATH
```

If `swift` can't find the macOS SDK or XCTest, point it at Xcode:
`export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

## Quick start

1. Put your screenshots in a folder with one subfolder per layout: `mac`,
   `iphone` and/or `ipad`. Use the same file name for the same screen in every
   subfolder.

   ```
   MyApp/
     screenshots/
       iphone/  Your week at a glance.png  Track every habit.png
       ipad/    Your week at a glance.png  Track every habit.png
   ```

2. Create a config. `init` adds one target per layout subfolder and one screen
   per file name. Each title is the file name, with `_` and `-` turned into
   spaces and ` - ` into a line break:

   ```sh
   store-previews init MyApp/screenshots      # writes MyApp/store-previews.json
   ```

3. Edit `MyApp/store-previews.json`: put the screens in App Store order, write
   the titles and subtitles, and set colours.

4. Render:

   ```sh
   store-previews render MyApp/store-previews.json --clean
   ```

   The images land in `MyApp/previews/<target>/01_<screen>.png`,
   `02_<screen>.png` and so on, numbered so they upload in the right order.
   `<screen>` is the file name with spaces and punctuation turned into `-`,
   for example `01_Your-week-at-a-glance.png`.

Commit the config with your app and keep generated previews out of version
control.

## Commands

```
store-previews render <config.json> [--locale <id>] [--target <name>] [--clean] [--dry-run] [--background <hex>] [--text-color <hex>] [--gradient <0-1>]
store-previews init <screenshots-folder> [-o <config.json>] [--preset <name>] [--force]
store-previews presets
store-previews -i <folder> [options]
```

| `render` option | Effect |
| --- | --- |
| `--locale <id>` | Render only this locale |
| `--target <name>` | Render only this target (its output folder name) |
| `--clean` | Delete the `NN_*.png` files in the folders being written first, so removed or renamed screens don't linger |
| `--dry-run` | List screenshot → output → title without rendering |
| `--background` / `--text-color` | `#RRGGBB` that overrides every `background` / `textColor` in the config, for trying colors without editing it |
| `--gradient <0-1>` | Overrides every `gradient` in the config |

`render` prints warnings on stderr for screenshots that aren't listed in the
config, listed screens missing from a target's folder, and untranslated
captions. They don't stop the run.

`init` takes `--preset` for the target it creates when screenshots sit directly
in the folder rather than in layout subfolders (default `mac-16`). If the
screenshots are per language instead (`screenshots/en/iphone/`,
`screenshots/fi/iphone/`), `init` lists those folders as `locales`, in name
order; move the language of your default captions to the front.

### Presets

| Preset | Size | Layout |
| --- | --- | --- |
| `mac-16` | 2880 × 1800 | mac |
| `mac-13` | 2560 × 1600 | mac |
| `iphone-6.9` | 1290 × 2796 | iphone |
| `iphone-6.9-lg` | 1320 × 2868 | iphone |
| `iphone-6.5` | 1284 × 2778 | iphone |
| `iphone-6.3` | 1179 × 2556 | iphone |
| `ipad-13` | 2048 × 2732 | ipad |
| `ipad-13-land` | 2732 × 2048 | ipad |

Any other size works with `"size": "WxH"` and a `layout`. Check Apple's current
[screenshot specifications](https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications)
for which sizes App Store Connect requires.

## Config

Paths are relative to the config file. JSON strings use `\n` for a line break.

```json
{
  "screenshots": "screenshots",
  "output": "previews",
  "locales": ["en", "fi"],
  "style": { "background": "#1C1C1E", "textColor": "#FFFFFF" },
  "targets": [
    { "preset": "iphone-6.9" },
    { "preset": "ipad-13", "style": { "background": "#F4F4F6", "textColor": "#111111" } },
    { "size": "2560x1600", "layout": "mac", "input": "mac", "name": "mac-custom" }
  ],
  "screens": [
    {
      "file": "Your week at a glance",
      "title": "Your week\nat a glance",
      "subtitle": "Every plan in one place",
      "localized": {
        "fi": { "title": "Viikkosi yhdellä\nsilmäyksellä", "subtitle": "Kaikki suunnitelmat yhdessä paikassa" }
      }
    },
    { "file": "Track every habit", "title": "Track every habit", "style": { "fontSize": 110 } }
  ]
}
```

| Key | Meaning |
| --- | --- |
| `screenshots` | Screenshot root. Default `screenshots` |
| `output` | Output root. Default `previews` |
| `locales` | Optional. Each locale renders to `<output>/<locale>/<target>/`. The default captions are in the first locale; the others are translated with `localized`. A screenshot in `<screenshots>/<locale>/<input>/` is used before the shared one, for localized UI; the shared folder can be left out entirely |
| `style` | Project-wide style (see below) |
| `targets[].preset` | Output size and layout (see [Presets](#presets)) |
| `targets[].size` + `layout` | Custom `WxH` size instead of a preset; `layout` is `mac`, `iphone` or `ipad` |
| `targets[].input` | Screenshot subfolder. Default: the layout name if that folder exists, else the root |
| `targets[].name` | Output folder name. Default: the preset name or size |
| `screens[]` | The screens, in App Store order |
| `screens[].file` | Screenshot file name, with or without extension, matched case-insensitively |
| `screens[].title` / `subtitle` | Caption. Empty or missing means none |
| `screens[].localized` | Per-locale `title` / `subtitle`; a missing one falls back to the default caption |

Style keys, all optional: `background` and `textColor` (`#RRGGBB`), `fontName`
(the PostScript name of a font installed on the Mac, such as `Avenir-Heavy`; an
unknown name falls back to the default font), `fontSize` (title size in pixels;
the subtitle scales with it), `cornerRadius` and `padding` (pixels),
`shadow` (true or false), `gradient` (how much darker the bottom of the
background is than the top, from `0` for a flat color to `1` for black; a light
background looks best around `0.1`). A screen's `style` overrides its target's, which
overrides the project's, which overrides the defaults: `#1C1C1E` background,
white text, the rounded system font, automatic sizes, shadow on, gradient `0.3`.

On iPhone and iPad targets a title without `\n` breaks after its third word;
add your own `\n` to break it elsewhere. Target names and locales become folder
names, so they can't contain `/`.

## One-off renders from flags

Without a command, `store-previews` renders a whole folder from flags: one
title for every screenshot, or each file name as its title. Output is
`preview_<name>.png` in a `previews` folder next to the input folder, or in
the folder given with `-o`.

```sh
store-previews -i ./screenshots --preset iphone-6.9 -b "#111111"
store-previews -i ./screenshots -t "Line one\nLine two" -s "Subtitle" --size 2560x1600 -o ./store-assets
store-previews -i . -h   # all flags
```

## Using the library

```swift
// Package.swift
.package(url: "https://github.com/jnersn/store-previews.git", from: "0.2.0"),
// target dependency
.product(name: "StorePreviewKit", package: "store-previews"),
```

```swift
import AppKit
import StorePreviewKit

// Render one image
let options = RenderOptions(
    width: 1290, height: 2796, layout: .iphone,
    title: "Your week\nat a glance",
    backgroundColor: parseHexColor("#1C1C1E")!, textColor: .white
)
let png = try renderPreview(screenshot: NSImage(contentsOf: screenshotURL)!, options: options)

// Or resolve a whole config into render jobs
let config = try ProjectConfig.load(from: configURL)
let plan = try config.plan(baseDirectory: configURL.deletingLastPathComponent())
plan.warnings.forEach { print("warning:", $0) }
for directory in plan.outputDirectories {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
}
for job in plan.jobs {
    try renderPreview(screenshot: NSImage(contentsOf: job.screenshot)!, options: job.options).write(to: job.output)
}
```

The library uses AppKit, so it runs on macOS only.

## Development

```sh
swift build
swift test                          # includes ReadmeTests
Scripts/check-readme-library.sh     # compiles the library example above
```

`ReadmeTests` keeps this README honest: it runs every `store-previews` command
shown in the quick start and flag examples, validates the example config, and
checks the commands, options and presets tables against the tool. If you change
the README, run the tests.

## License

MIT. See [LICENSE](LICENSE).

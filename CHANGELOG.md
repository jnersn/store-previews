# Changelog

The project uses semantic versioning. Before 1.0.0, a minor version may change the command line interface, the config format or the `StorePreviewKit` API.

## Unreleased

- `store-previews render --background <hex>` and `--text-color <hex>` override the config's colors for one run.
- Style key `gradient` (0 to 1, default 0.3) sets how much darker the bottom of the background is; `--gradient` sets it from the command line in both `render` and flag mode.
- Mac layout: the whole app window now fits inside the preview instead of running off the bottom edge. The transparent shadow margin of a macOS window capture is trimmed, so the window itself is fitted and centered under the caption.

## 0.1.0

First public release.

- `store-previews render`: renders App Store previews from a JSON config with per-screen captions, screen order, locales (translated captions and screenshots) and layered style overrides. Options `--locale`, `--target`, `--clean` and `--dry-run`.
- `store-previews init`: creates a starter config from a screenshots folder.
- `store-previews presets`: lists the built-in Mac, iPhone and iPad sizes.
- Flag mode (`store-previews -i <folder> ...`) for one-off renders without a config.
- `StorePreviewKit`: the renderer and config handling as a library.

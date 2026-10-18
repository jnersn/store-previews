# Changelog

The project uses semantic versioning. Before 1.0.0, a minor version may change the command line interface, the config format or the `StorePreviewKit` API.

## 0.1.0

First public release.

- `store-previews render`: renders App Store previews from a JSON config with per-screen captions, screen order, locales (translated captions and screenshots) and layered style overrides. Options `--locale`, `--target`, `--clean` and `--dry-run`.
- `store-previews init`: creates a starter config from a screenshots folder.
- `store-previews presets`: lists the built-in Mac, iPhone and iPad sizes.
- Flag mode (`store-previews -i <folder> ...`) for one-off renders without a config.
- `StorePreviewKit`: the renderer and config handling as a library.

#!/bin/sh
# Type-checks the "Using the library" section of README.md: builds a throwaway
# package from its Package.swift lines (pointed at this checkout) and its code.
set -eu

repo=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# Swift code blocks in the section, numbered 1, 2, ...
awk -v out="$work/block" '
    /^## / { inside = ($0 == "## Using the library") }
    inside && /^```swift/ { n++; capture = 1; next }
    capture && /^```/ { capture = 0; next }
    capture { print > (out n) }
' "$repo/README.md"

[ -f "$work/block1" ] && [ -f "$work/block2" ] || {
    echo "README: expected two swift blocks under '## Using the library'" >&2
    exit 1
}

dependency=$(grep '\.package(' "$work/block1" | sed 's/[[:space:]]*,[[:space:]]*$//') || true
product=$(grep '\.product(' "$work/block1" | sed 's/[[:space:]]*,[[:space:]]*$//') || true
[ -n "$product" ] || { echo "README: no .product(...) line in the Package.swift block" >&2; exit 1; }
case "$dependency" in
    *'.package(url: "https://github.com/jnersn/store-previews.git"'*) ;;
    *) echo "README: unexpected package line: $dependency" >&2; exit 1 ;;
esac

# The package must be named after the checkout folder for the product line to resolve.
mkdir -p "$work/store-previews-readme/Sources/Example"
ln -s "$repo" "$work/store-previews"
cat > "$work/store-previews-readme/Package.swift" <<EOF
// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "store-previews-readme",
    platforms: [.macOS(.v13)],
    dependencies: [.package(path: "../store-previews")],
    targets: [.executableTarget(name: "Example", dependencies: [$product])]
)
EOF

# Placeholders for the values the snippet assumes exist.
cat > "$work/store-previews-readme/Sources/Example/Inputs.swift" <<'EOF'
import Foundation

let screenshotURL = URL(fileURLWithPath: "screenshot.png")
let configURL = URL(fileURLWithPath: "store-previews.json")
EOF
cp "$work/block2" "$work/store-previews-readme/Sources/Example/main.swift"

swift build --package-path "$work/store-previews-readme"
echo "README library example compiles."

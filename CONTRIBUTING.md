# Writing a Widget

You'll need macOS 14+, Xcode 15+, and some Swift/SwiftUI experience.

## Prerequisites

Make sure you have these installed before building:

- **Xcode Command Line Tools** - install with `xcode-select --install` if you don't have them
- **Swift** - comes with Xcode. Verify with `swift --version`
- **Python 3** - the build script uses it to parse `widget.json`. Verify with `python3 --version`. Comes preinstalled on macOS, or install via `brew install python3`

## What you're building

A widget is a folder in `Widgets/` with:
- `widget.json` - metadata about your widget
- `.swift` files - your plugin class and SwiftUI view(s)

These get compiled into macOS `.bundle` files that DockDoor Pro loads at runtime.

## 1. Create your widget folder

Your folder name becomes the bundle filename and download URL, so it must only contain letters, numbers, and hyphens. No spaces or special characters.

```
Widgets/
└── MyWidget/
    ├── widget.json
    ├── MyWidgetPlugin.swift
    └── MyWidgetView.swift
```

## 2. Write `widget.json`

```json
{
    "id": "my-widget",
    "name": "My Widget",
    "author": "your-github-username",
    "description": "Short description of what it does",
    "iconSymbol": "star",
    "principalClass": "MyWidgetPlugin",
    "sources": ["MyWidgetPlugin.swift", "MyWidgetView.swift"]
}
```

- **id** - must be globally unique across all widgets. This is how the app identifies your widget for updates. Pick something descriptive like `"storage-monitor"` or `"cpu-usage"`
- **name** - display name shown in the marketplace
- **iconSymbol** - any [SF Symbol](https://developer.apple.com/sf-symbols/) name
- **principalClass** - must match your plugin class name exactly
- **sources** - all your `.swift` files, order doesn't matter

## 3. Write the plugin class

This is the entry point. Subclass `WidgetPlugin`, conform to `DockDoorWidgetProvider`:

```swift
import DockDoorWidgetSDK
import SwiftUI

final class MyWidgetPlugin: WidgetPlugin, DockDoorWidgetProvider {
    var id: String { "my-widget" }
    var name: String { "My Widget" }
    var iconSymbol: String { "star" }
    var widgetDescription: String { "Short description" }

    @MainActor
    func makeBody(size: CGSize, isVertical: Bool) -> AnyView {
        AnyView(MyWidgetView(size: size, isVertical: isVertical))
    }
}
```

## 4. Write your view

Your view gets two things from the host app:

- **`size`** - the content area you can draw in. **Don't apply `.frame()` yourself**, the host handles that.
- **`isVertical`** - `true` when the dock is on the left or right side of the screen.

You need to handle both **compact** (single slot) and **extended** (double slot) layouts, and all 4 dock positions.

```swift
struct MyWidgetView: View {
    let size: CGSize
    let isVertical: Bool

    private var dim: CGFloat { min(size.width, size.height) }

    // true when placed in a double-width/height slot
    private var isExtended: Bool {
        isVertical
            ? size.height > size.width * 1.5
            : size.width > size.height * 1.5
    }

    var body: some View {
        Group {
            if isExtended {
                extendedLayout
            } else {
                compactLayout
            }
        }
    }

    // single slot: icon + small label
    private var compactLayout: some View {
        VStack(spacing: 1) {
            Image(systemName: "star")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: dim * WidgetMetrics.sfSymbolScale)
                .foregroundStyle(.secondary)
            Text("Label")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    // double slot: layout depends on dock orientation
    private var extendedLayout: some View {
        Group {
            if isVertical {
                // left/right dock: tall slot, stack vertically
                VStack(spacing: dim * WidgetMetrics.spacingScale) {
                    // icon on top, labels below
                }
            } else {
                // top/bottom dock: wide slot, stack horizontally
                HStack(spacing: dim * 0.1) {
                    // icon on left, labels on right
                }
            }
        }
    }
}
```

### Sizing constants

Use `WidgetMetrics` so your widget matches the built-in ones:

| Constant | Value | What it's for |
|----------|-------|---------------|
| `contentScale` | 0.85 | main icon/image size relative to `dim` |
| `sfSymbolScale` | 0.55 | SF Symbol size relative to `dim` |
| `spacingScale` | 0.08 | spacing between elements relative to `dim` |

The host computes the actual content area from the slot config (single = `iconSize`, double = `iconSize * 2 + 4`, minus card padding). You just use what you're given.

## 5. Settings (optional)

Don't write your own settings UI. Declare what you need and the app renders it natively:

From the StorageMonitor example widget:

```swift
func settingsSchema() -> [WidgetSetting] {
    [
        .toggle(key: "showPercentage", label: "Show Percentage Instead of GB", defaultValue: false),
        .slider(key: "warningThreshold", label: "Warning Threshold (%)", range: 50...95, step: 5, defaultValue: 75),
        .picker(key: "ringStyle", label: "Ring Style", options: ["Rounded", "Flat"], defaultValue: "Rounded"),
    ]
}
```

Read values at runtime:

```swift
let showPercentage = WidgetDefaults.bool(key: "showPercentage", widgetId: id)
let threshold = WidgetDefaults.double(key: "warningThreshold", widgetId: id, default: 75)
let ringStyle = WidgetDefaults.string(key: "ringStyle", widgetId: id, default: "Rounded")
```

## What you can't do

I review every PR manually. These will get rejected:

- `Process`, `NSTask`, `dlopen`, `dlsym`, `system()`, `popen()` - no spawning processes
- network requests without a good reason
- file system access outside standard read-only locations
- private framework imports
- applying `.frame()` on your root view (the host does this)

CI also runs a lint pass for these.

## Testing locally

1. Clone the repo and `cd` into it
2. Run the build script:
   ```bash
   bash scripts/build-widgets.sh
   ```
   This builds the SDK, compiles every widget in `Widgets/`, and outputs `.bundle` files to `build/`.
3. Check the output:
   ```bash
   ls build/*.bundle
   ```
4. Copy your bundle into the DockDoor Pro widgets directory:
   ```bash
   cp -r build/YourWidget.bundle ~/Library/Application\ Support/DockDoor\ Pro/Widgets/
   ```
5. Restart DockDoor Pro. Your widget should show up in the widget picker.

To rebuild a single widget instead of all of them:
```bash
bash scripts/build-widgets.sh Widgets/YourWidget
```

## Submitting

1. Fork this repo
2. Add your widget in `Widgets/YourWidget/`
3. Test it with `build-widgets.sh`
4. Open a PR

CI will check that it compiles and passes lint. I'll review the code and merge if it's good.

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
    "orientations": ["horizontal"],
    "principalClass": "MyWidgetPlugin",
    "sources": ["MyWidgetPlugin.swift", "MyWidgetView.swift"]
}
```

- **id** - must be globally unique across all widgets. This is how the app identifies your widget for updates. Pick something descriptive like `"storage-monitor"` or `"cpu-usage"`
- **name** - display name shown in the marketplace
- **iconSymbol** - any [SF Symbol](https://developer.apple.com/sf-symbols/) name
- **orientations** - `"horizontal"` (bottom/top dock), `"vertical"` (left/right dock), or both. You need at least one. If you list an orientation, you need to handle both compact and extended layouts for it. Missing this field = won't show up in the marketplace.
- **maxSlotSpan** (optional) - `2` or `3`. Set `3` if your widget also renders a triple-width slot (see [Triple slot](#triple-slot-optional)). Leave it out for the default of `2`. The host never gives your widget a slot span you didn't declare, so only opt in once your layouts actually handle it.
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
    var supportedOrientations: [WidgetOrientation] { [.horizontal] }

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

You need to handle both **compact** (single slot) and **extended** (double slot) layouts for each orientation you listed in `widget.json`.

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

### Triple slot (optional)

Users can size a stack to span three dock slots. Support is opt-in: declare `"maxSlotSpan": 3` in `widget.json` and handle the extra layout. Widgets that don't opt in are simply hidden from triple-sized stacks — nothing breaks.

Use `WidgetSlotSpan.detect` from the SDK instead of hand-rolling aspect-ratio checks:

```swift
private var slotSpan: WidgetSlotSpan {
    WidgetSlotSpan.detect(size: size, isVertical: isVertical)
}

var body: some View {
    switch slotSpan {
    case .compact: compactLayout
    case .extended: extendedLayout
    case .triple: tripleLayout
    }
}
```

`.detect` returns `.compact` for a single slot, `.extended` for double, `.triple` for triple, using the same thresholds as the `isExtended` example above — so you can adopt it without changing how your existing layouts trigger. It's also safe on older app versions: the SDK inlines the detection into your bundle, so a widget built against the current SDK still loads on hosts that predate triple slots (they just never hand you a triple-sized area).

If you declare `"maxSlotSpan": 3` for an orientation you support, handle all three layouts for it.

### Sizing

All sizing should be proportional to the shortest side of the content area. The view example above defines `dim` as `min(size.width, size.height)` and uses `WidgetMetrics` constants (`contentScale`, `sfSymbolScale`, `spacingScale`) to stay consistent with built-in widgets. See `StorageMonitorView.swift` for a full example.

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

### Table settings

For list-style configuration (custom entries the user adds and removes), declare a `.table` setting. The app renders it with column headers, an add-row button, and a delete button per row:

```swift
.table(
    key: "customEngines",
    label: "Custom Search Engines",
    description: "Use {searchTerms} in the URL to insert the query.",
    columns: [
        WidgetTableColumn(key: "type", title: "Type", kind: .picker(options: ["Query", "Static"])),
        WidgetTableColumn(key: "prefix", title: "Prefix", kind: .text(placeholder: "yt")),
        WidgetTableColumn(key: "url", title: "URL", kind: .text(placeholder: "https://…"), width: .expanding),
    ]
)
```

Read the saved rows at runtime — each row is a `[columnKey: value]` dictionary:

```swift
for row in WidgetDefaults.tableRows(key: "customEngines", widgetId: id) {
    let prefix = row["prefix"] ?? ""
    let url = row["url"] ?? ""
}
```

Table settings require a DockDoor Pro version that ships SDK table support. On older app versions the settings view cannot interpret a `.table` entry, so only declare one when you actually need it.

## 6. Panel (optional)

Long-press, right-click, or hover-activate can show a panel. Return a view from `makePanelBody` and the host takes care of the rest. Return `nil` (the default) if you don't need one.

```swift
@MainActor
func makePanelBody(dismiss: @escaping () -> Void) -> AnyView? {
    AnyView(
        VStack(spacing: 12) {
            Text("Detailed View")
                .font(.headline)
            Button("Done") { dismiss() }
        }
        .padding()
    )
}
```

Call `dismiss` to close the panel. The host handles positioning and chrome.

## 7. Scroll input (optional)

Conform your plugin to `WidgetScrollHandling` (in addition to `DockDoorWidgetProvider`) to receive scroll events while the pointer is over your widget:

```swift
final class MyPlugin: WidgetPlugin, DockDoorWidgetProvider, WidgetScrollHandling {
    func handleScroll(delta: CGFloat, isTrackpad: Bool) -> Bool {
        cycleSelection(forward: delta > 0)
        return true // consume; return false to let the dock handle it
    }

    func scrollSessionEnded() {
        commitSelection() // optional — default does nothing
    }
}
```

Rules, matching the built-in Now Playing volume scroll:

- Your handler is only active while your widget is the **only widget in its stack**. Multi-widget stacks use scroll to page between widgets.
- Return `false` to fall through to the dock's own scroll gesture (file tray open/close). Consume only what you use.
- Momentum-phase trackpad events are filtered out by the host.
- `scrollSessionEnded()` fires when the pointer leaves your widget — commit any in-progress state there.

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
   cp -r build/YourWidget.bundle ~/Library/Application\ Support/DockDoorPro/Widgets/
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

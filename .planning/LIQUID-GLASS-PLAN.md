# Liquid Glass Bezel UI Plan

## Context
The bezel HUD currently uses `.ultraThinMaterial` and `.regularMaterial` for its background. macOS 26 introduces the Liquid Glass design language with `.glassEffect()`. We want to adopt it while keeping the macOS 15.0 deployment target via `#available(macOS 26, *)` runtime checks.

## API Reference

### Core Modifier
```swift
.glassEffect(_ glass: Glass = .regular, in shape: S, isEnabled: Bool = true)
```

### Variants
| Variant | Purpose |
|---------|---------|
| `.regular` | Default; balanced transparency — most UI elements |
| `.clear` | High transparency with dimming — controls over photos/media |
| `.identity` | No effect — conditional toggling |

### Shapes
```swift
.glassEffect(.regular, in: .capsule)
.glassEffect(.regular, in: .circle)
.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
.glassEffect(.regular, in: .rect(cornerRadius: .containerConcentric))
```

### Tinting
```swift
.glassEffect(.regular.tint(.blue))
.glassEffect(.regular.tint(.purple.opacity(0.6)))
```

### GlassEffectContainer
Groups multiple glass elements for morphing transitions:
```swift
GlassEffectContainer {
    HStack(spacing: 20) {
        Image(systemName: "pencil")
            .frame(width: 44, height: 44)
            .glassEffect(.regular)
        Image(systemName: "eraser")
            .frame(width: 44, height: 44)
            .glassEffect(.regular)
    }
}
```

### Accessibility
Automatically adapts for reduced transparency, increased contrast, reduced motion. Can override:
```swift
@Environment(\.accessibilityReduceTransparency) var reduceTransparency
.glassEffect(reduceTransparency ? .identity : .regular)
```

## Approach

Apply a single `.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))` to the outer bezel VStack on macOS 26+, falling back to the current `.ultraThinMaterial` on older systems. Inner section backgrounds (`.regularMaterial` on search field and footer) become transparent on macOS 26 so the glass shows through uniformly.

### Why single glass, not multiple regions
- A floating HUD should look like one cohesive glass panel
- Multiple glass regions risk visual seams/fragmentation
- Matches how Apple's own HUD panels work in macOS 26
- Simpler code

## Changes

### BezelView.swift (3 edits)

**1. Replace outer background + clipShape:**
```swift
// Before:
.background(
    RoundedRectangle(cornerRadius: 16)
        .fill(.ultraThinMaterial)
)
.clipShape(RoundedRectangle(cornerRadius: 16))

// After:
if #available(macOS 26, *) {
    .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
} else {
    .background(RoundedRectangle(cornerRadius: 16).fill(.ultraThinMaterial))
    .clipShape(RoundedRectangle(cornerRadius: 16))
}
```

**2. Search field `.background(.regularMaterial)` → conditional:**
```swift
// macOS 26: .background(.clear)  (glass shows through)
// macOS <26: .background(.regularMaterial)  (current behavior)
```

**3. Footer `.background(.regularMaterial)` → same treatment**

### BezelController.swift — no changes needed
Current NSPanel config (`isOpaque = false`, `backgroundColor = .clear`, `hasShadow = true`) is already compatible with Liquid Glass. The `alphaValue` transparency setting continues to work at the window level.

## Notes
- `#available(macOS 26, *)` is a runtime check that compiles with `MACOSX_DEPLOYMENT_TARGET = 15.0`
- Requires Xcode 26+ to compile (macOS 26 SDK must be present)
- No GlassEffectContainer needed (single glass region, no morphing)
- Dividers work correctly inside glass
- Transparency slider (`bezelAlpha` → `alphaValue`) still works — operates at NSWindow level

## Sources
- [Apple: Applying Liquid Glass to custom views](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
- [Apple: Build a SwiftUI app with the new design (WWDC25)](https://developer.apple.com/videos/play/wwdc2025/323/)
- [Liquid Glass Reference (community)](https://github.com/conorluddy/LiquidGlassReference)

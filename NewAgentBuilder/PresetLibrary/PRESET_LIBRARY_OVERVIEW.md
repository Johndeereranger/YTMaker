# Preset Library - Project Overview

## Purpose

Build a library of reusable edit presets extracted from FCPXML files. This allows you to learn from existing Final Cut Pro projects and reapply those edit patterns programmatically.

---

## Status: Phase 2A Foundation

| Task | Status |
|------|--------|
| Folder structure | ✅ Done |
| Base models (EditPreset protocol) | ✅ Done |
| TransformPreset model | ✅ Done |
| TextOverlayPreset model | ✅ Done |
| TransitionPreset model | ✅ Done |
| BRollPreset model | ✅ Done |
| FCPXMLParser service | ✅ Done |
| PresetStorageService | ✅ Done |
| PresetLibraryHomeView | ✅ Done |
| FCPXMLImportView | ✅ Done |
| PresetDetailView | ✅ Done |
| Add to App Navigation | ❌ TODO |
| Test with real FCPXML | ❌ TODO |

---

## Architecture

```
PresetLibrary/
├── Models/
│   ├── EditPreset.swift        # Base protocol, common types (Point2D, RGBAColor, Keyframe, etc.)
│   ├── TransformPreset.swift   # Position, scale, rotation animations
│   ├── TextOverlayPreset.swift # Title/text styles
│   ├── TransitionPreset.swift  # Cross dissolve, wipes, etc.
│   └── BRollPreset.swift       # Video overlay patterns
├── Views/
│   ├── PresetLibraryHomeView.swift  # Main browse view
│   ├── FCPXMLImportView.swift       # Import flow
│   └── PresetDetailView.swift       # View/edit a preset
└── Services/
    ├── FCPXMLParser.swift          # Parse FCPXML files
    └── PresetStorageService.swift  # Save/load presets
```

---

## Key Concepts

### Preset Types

| Type | Description | Example |
|------|-------------|---------|
| Transform | Position, scale, rotation animations | Ken Burns zoom, recentering shift |
| TextOverlay | Title/text styles | Lower third, subtitles |
| Transition | Effects between clips | Cross dissolve, fade to black |
| B-Roll | Video overlay patterns | Insert shots with transforms |

### Anchor Types

How presets attach to the timeline (for future script-driven application):

| Anchor | Usage |
|--------|-------|
| `phrase` | Start of a transcript phrase |
| `phraseEnd` | End of a transcript phrase |
| `word` | Specific word in transcript |
| `cutPoint` | A cut/edit boundary |
| `previousEditEnd` | Chain after last edit |
| `absolute` | Specific timecode |

### Timing

All timing uses `CodableCMTime` (rational time) for frame-accurate representation:
- Matches FCPXML format exactly
- No floating point drift
- Lossless round-trip

---

## Workflow

### Import Flow

1. User selects FCPXML file from Final Cut Pro
2. Parser extracts:
   - Resources (effects, formats, assets)
   - Transforms (adjust-transform elements)
   - Titles (title elements with text styles)
   - Transitions (transition elements)
   - B-Roll (asset-clip on lane 1+)
3. Shows summary of extracted presets
4. User confirms import
5. Presets saved to local storage

### Browse Flow

1. User opens Preset Library
2. Views all presets or filters by type
3. Search by name or tags
4. Favorite frequently used presets
5. View/edit preset details

### Future: Apply Flow (Phase 2B)

1. Select a transcript phrase/word
2. Choose a preset
3. Apply preset at anchor point
4. Preview result
5. Export to FCPXML

---

## FCPXML Elements Parsed

### Transforms
```xml
<adjust-transform>
    <param name="position">
        <keyframeAnimation>
            <keyframe time="..." value="x y"/>
        </keyframeAnimation>
    </param>
</adjust-transform>
```

### Titles
```xml
<title ref="r3" lane="2" offset="..." duration="...">
    <text><text-style ref="ts1">Content</text-style></text>
    <text-style-def id="ts1">
        <text-style font="..." fontSize="..." fontColor="..."/>
    </text-style-def>
</title>
```

### Transitions
```xml
<transition name="Cross Dissolve" offset="..." duration="...">
    <filter-video ref="r14" name="Cross Dissolve">
        <param name="..." value="..."/>
    </filter-video>
</transition>
```

### B-Roll (Asset Clips on Lane 1+)
```xml
<asset-clip ref="r6" lane="1" offset="..." start="..." duration="..."
            name="Clip Name" format="r7">
</asset-clip>
```

---

## Storage

Presets are stored as JSON files in Application Support:

```
~/Library/Application Support/PresetLibrary/
├── transforms/
│   └── {uuid}.json
├── textOverlays/
│   └── {uuid}.json
├── transitions/
│   └── {uuid}.json
└── bRolls/
    └── {uuid}.json
```

---

## Next Steps

1. **Add to App Navigation** - Wire up PresetLibraryHomeView to the app's navigation
2. **Test with real FCPXML** - Import actual FCP projects and verify parsing
3. **Refine parser** - Handle more FCPXML variations
4. **Phase 2B** - Implement preset application to timeline

---

*Created: 2026-02-03*

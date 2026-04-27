# Final Cut Pro Edit Mental Models

This document defines the mental models for each edit type we support. As we define each one, we document it here to maintain consistency and avoid breaking established patterns.

---

## Core Concepts

### Rational Timing (CMTime)

**DECISION (2026-02-03): Use `CMTime` throughout the app, not `TimeInterval`.**

FCPXML uses rational numbers for all timing: `numerator/denominator` (e.g., `13100/6000s` = 2.183s)

**Why rational?**
- Frame-accurate: No floating point drift
- Timescale-aware: Different formats (24fps, 30fps, 60fps) have different natural timescales
- Lossless round-trip: Import → Edit → Export without precision loss

**Why CMTime specifically?**
- Apple's native rational time type
- AVFoundation already uses it everywhere
- Handles arithmetic across different timescales automatically
- No risk of overflow or precision bugs - Apple solved this

**Common timescales in FCPXML:**
- 6000 = 60fps (100/6000s = 1 frame)
- 30000 = 30fps with sub-frame precision
- 2500 = 25fps (PAL)

**Migration from TimeInterval:**
Phase 1 code currently uses `TimeInterval` (Double). This will be migrated to `CMTime`:
- `DetectedGap.startTime/endTime` → `CMTime`
- `TranscribedWord` timestamps → `CMTime`
- `WaveformData` keeps sample-based indexing internally, but public API uses `CMTime`
- `CutBoundaryRefiner` calculations → `CMTime`

The waveform is the one place where conversion happens: `CMTime` → sample index for lookup.

### Lanes
FCPXML uses lanes to stack elements:
- Lane 0 = Main storyline (primary video)
- Lane 1, 2, 3... = Video overlays (B-roll, graphics, titles)
- Lane -1, -2, -3... = Audio overlays (SFX, music) — **FUTURE PHASE**

### Resources
Effects, formats, and assets are defined once in `<resources>` and referenced by ID:
```xml
<effect id="r3" name="Basic Title" uid="..."/>
...
<title ref="r3" ...>  <!-- References the effect -->
```

---

## Edit Type 1: Transform

### What It Is
A motion applied to a clip: position shift, scale change, or rotation.

### Mental Model
All transforms are **two-point animations**:
```
Start Value → End Value (over edit duration)
```

The transform has an **anchor edge** that determines which value "sticks" to the edit point:

| Anchor | Meaning |
|--------|---------|
| `.start` | The start value is locked to edit begin; animates toward end value |
| `.end` | The end value is locked to edit end; animates from start value |

### Example: "Shift Left" Recentering
- **Purpose:** Camera is slightly off-center, shift to correct framing
- **Position:** `(0, 0)` → `(-23, 0)`
- **Duration:** Matches the underlying edit duration
- **Anchor:** `.end` (the corrected position is the "destination")

### FCPXML Representation
```xml
<adjust-transform>
    <param name="position">
        <keyframeAnimation>
            <keyframe time="119200/6000s" value="0 0"/>
            <keyframe time="120300/6000s" value="-23.1481 0"/>
        </keyframeAnimation>
    </param>
</adjust-transform>
```

### Preset Data Model (Conceptual)
```
TransformPreset:
    positionStart: Point?
    positionEnd: Point?
    scaleStart: Float?
    scaleEnd: Float?
    rotationStart: Float?
    rotationEnd: Float?
    anchorEdge: .start | .end
```

### Open Questions
- [ ] Do we need easing curves? (FCPXML supports `curve="linear"`)
- [ ] Static transforms (no animation) - just store single value with no end?

---

## Edit Type 2: Text Overlay

### What It Is
Text displayed on screen with styling.

### Mental Model
Text overlays have:
1. **Content** - The actual text string
2. **Style** - Font, size, color, stroke, alignment
3. **Timing** - When it appears (relative to edit anchor)
4. **Position** - Where on screen (often from a title template)

### FCPXML Representation
```xml
<title ref="r3" lane="2" offset="21606200/6000s" name="My Title" start="3600s" duration="13000/6000s">
    <text>
        <text-style ref="ts1">The actual text content</text-style>
    </text>
    <text-style-def id="ts1">
        <text-style font="Helvetica" fontSize="63" fontFace="Regular"
                    fontColor="1 1 1 1" alignment="center"/>
    </text-style-def>
</title>
```

### Preset Data Model (Conceptual)
```
TextOverlayPreset:
    templateRef: String          // e.g., "Basic Title" - assumes FCP has it
    text: String                 // Placeholder or actual text
    font: String
    fontSize: Float
    fontColor: Color (RGBA 0-1)
    strokeColor: Color?
    strokeWidth: Float?
    alignment: .left | .center | .right
    position: Point?             // If template allows repositioning
```

### Open Questions
- [ ] Do we store template reference only, or full style definition?
- [ ] Multi-line text handling
- [ ] Text with multiple styles (rich text)

---

## Edit Type 3: B-Roll Insert

### What It Is
A video clip placed over the main storyline (on lane 1+).

### Mental Model
B-roll is a **visual replacement** for a portion of the timeline:
- Covers the A-roll (main footage) visually
- A-roll audio typically continues underneath
- Has its own in/out points from the source media

### FCPXML Representation
```xml
<asset-clip ref="r6" lane="1" offset="100500/6000s"
            name="Deer_s_Eye_View" start="24300/6000s" duration="1228800/1536000s"
            format="r7" tcFormat="NDF" audioRole="dialogue">
    <conform-rate scaleEnabled="0" srcFrameRate="24"/>
</asset-clip>
```

### Preset Data Model (Conceptual)
```
BRollPreset:
    mediaReference: ???         // How do we reference the actual video?
    sourceIn: RationalTime      // Where in the source clip to start
    duration: RationalTime      // How long
    transform: TransformPreset? // Optional repositioning/scaling
```

### Open Questions
- [ ] How do we handle media that doesn't exist on the target system?
- [ ] Should preset store thumbnail only? Path? Both?
- [ ] What about clips from the user's media library vs. bundled assets?

---

## Edit Type 4: Transition

### What It Is
An animated effect between two clips (Cross Dissolve, Spin, Page Curl, etc.)

### Mental Model
Transitions are **boundary effects**:
- Applied at cut points between clips
- Have a duration that overlaps both clips
- Reference a built-in FCP effect by UID

### FCPXML Representation
```xml
<transition name="Cross Dissolve" offset="7800/6000s" duration="700/6000s">
    <filter-video ref="r14" name="Cross Dissolve">
        <param name="Look" key="1" value="11 (Video)"/>
        <param name="Amount" key="2" value="50"/>
        <param name="Ease" key="50" value="2 (In &amp; Out)"/>
        <param name="Ease Amount" key="51" value="0"/>
    </filter-video>
</transition>
```

### Preset Data Model (Conceptual)
```
TransitionPreset:
    effectUID: String           // FCP's unique identifier for the effect
    effectName: String          // Human-readable name
    duration: RationalTime      // Default duration
    parameters: [String: Any]   // Effect-specific params (Look, Amount, Ease, etc.)
```

### Open Questions
- [ ] Do we need to bundle effect UIDs? Or trust FCP has standard effects?
- [ ] Custom Motion templates - how to handle?
- [ ] Audio crossfade - separate or bundled with video transition?

---

## Universal Timing Model

### Anchor Types (from Phase 2 planning)
How an edit attaches to the timeline:

| Anchor Type | Meaning |
|-------------|---------|
| `phrase` | Start of a transcript phrase |
| `phraseEnd` | End of a transcript phrase |
| `word` | Specific word in transcript |
| `cutPoint` | A cut/edit boundary |
| `previousEditEnd` | Chains to wherever the last edit ended |

### Duration
- **Explicit:** Preset specifies exact duration (in rational time)
- **Inherited:** Duration matches the underlying element (phrase, word, etc.)
- **Flexible:** User can adjust after application

---

## Implementation Notes

### FCPXML Version
Targeting **version 1.13** (Final Cut Pro 10.6+)

### Required Resources
When exporting FCPXML, we must include:
- Format definitions for any referenced formats
- Effect references (UIDs) for titles, transitions, generators
- Asset references for any media

### Round-Trip Fidelity
Goal: Import FCPXML → Extract presets → Apply to new timeline → Export FCPXML should produce valid, working FCP project.

---

*Last updated: 2026-02-03*

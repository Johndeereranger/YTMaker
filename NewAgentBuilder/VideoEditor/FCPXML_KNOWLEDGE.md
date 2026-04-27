# FCPXML Knowledge Base

Everything we've learned about FCPXML structure from analyzing real exports.

---

## Source File Analyzed
- **File:** `Example WorkTrimmed UP.fcpxmld`
- **FCPXML Version:** 1.13
- **Date Analyzed:** 2026-02-03

---

## Document Structure

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE fcpxml>

<fcpxml version="1.13">
    <resources>
        <!-- Definitions: formats, effects, assets, compound clips -->
    </resources>

    <library>
        <event>
            <project>
                <sequence>
                    <spine>
                        <!-- Main timeline content -->
                    </spine>
                </sequence>
            </project>
        </event>
    </library>
</fcpxml>
```

---

## Resources Section

Resources define reusable elements referenced by ID throughout the document.

### Format Definitions
Video format specifications:
```xml
<format id="r1" name="FFVideoFormat3840x2160p60"
        frameDuration="100/6000s"
        width="3840" height="2160"
        colorSpace="1-1-1 (Rec. 709)"/>
```

**Key fields:**
- `id` - Reference ID used by clips
- `frameDuration` - Rational time per frame (100/6000s = 1/60th second)
- `width`, `height` - Resolution
- `colorSpace` - Color profile

### Effect Definitions
Built-in FCP effects (titles, transitions, generators):
```xml
<effect id="r3" name="Basic Title"
        uid=".../Titles.localized/Bumper:Opener.localized/Basic Title.localized/Basic Title.moti"/>

<effect id="r14" name="Cross Dissolve"
        uid="FxPlug:4731E73A-8DAC-4113-9A30-AE85B1761265"/>

<effect id="r23" name="Spin"
        uid="FxPlug:196B9DB2-28FD-420F-9BA1-3F0E9EEBBAAA"/>
```

**Key fields:**
- `id` - Reference ID
- `name` - Human-readable name
- `uid` - FCP's unique identifier (path for Motion templates, FxPlug UUID for built-in)

**Effect Types Found:**
| Name | Type | UID Pattern |
|------|------|-------------|
| Basic Title | Title template | `.../Titles.localized/.../Basic Title.moti` |
| Cross Dissolve | Transition | `FxPlug:4731E73A-...` |
| Spin | Transition | `FxPlug:196B9DB2-...` |
| Page Curl | Transition | (has effectConfig data blob) |
| Shapes | Generator | `.../Generators.localized/.../Shapes.motn` |
| Custom | Generator (solid) | `.../Generators.localized/Solids.localized/Custom.motn` |

### Asset Definitions
Media files with bookmarks:
```xml
<asset id="r4" name="C0153" uid="FD02B6ABEC9A75AF859BC6D2FC3B6E8A"
       start="0s" duration="101232000/100000s"
       hasVideo="1" format="r5" hasAudio="1"
       videoSources="1" audioSources="1" audioChannels="2" audioRate="48000">
    <media-rep kind="original-media" sig="FD02B6ABEC9A75AF859BC6D2FC3B6E8A"
               src="file:///Volumes/LaCie/...C0153.mp4">
        <bookmark>base64-encoded-bookmark-data</bookmark>
    </media-rep>
    <metadata>
        <md key="com.apple.proapps.mio.ingestDate" value="2025-11-08 13:27:03 -0400"/>
    </metadata>
</asset>
```

**Key fields:**
- `id` - Reference ID
- `name` - Clip name
- `uid` - Unique media signature
- `start`, `duration` - Source media timing
- `hasVideo`, `hasAudio` - Media type flags
- `format` - Reference to format definition
- `media-rep` - File location with macOS bookmark for reconnection

### Compound Clips (Media)
Pre-built sequences that can be referenced:
```xml
<media id="r10" name="QuestionCard" uid="R/F8+6rPSpC/DH0lWkElIA" modDate="...">
    <sequence format="r1" duration="10s" tcStart="0s" tcFormat="NDF"
              audioLayout="stereo" audioRate="48k">
        <spine>
            <!-- Nested timeline content -->
        </spine>
    </sequence>
</media>
```

---

## Timeline Elements

### Main Spine
The primary storyline - lane 0:
```xml
<spine>
    <video>...</video>
    <asset-clip>...</asset-clip>
    <mc-clip>...</mc-clip>
    <!-- Elements in sequence -->
</spine>
```

### Lanes
Vertical stacking of elements:
- **Lane 0** = Main storyline (implicit, inside `<spine>`)
- **Lane 1, 2, 3...** = Video overlays (B-roll, graphics, titles)
- **Lane -1, -2, -3...** = Audio overlays (SFX, music)

```xml
<asset-clip ref="r4" offset="13100/6000s" ...>
    <!-- This is on lane 0 (main spine) -->

    <asset-clip ref="r6" lane="1" offset="100500/6000s" ...>
        <!-- B-roll on lane 1 -->
    </asset-clip>

    <asset-clip ref="r8" lane="-1" offset="12664651/720000s" ...>
        <!-- Sound effect on lane -1 -->
    </asset-clip>

    <title ref="r3" lane="2" offset="21606200/6000s" ...>
        <!-- Text overlay on lane 2 -->
    </title>
</asset-clip>
```

### Nested Spines
Overlays can contain their own spine for complex compositions:
```xml
<spine lane="1" offset="1063/60s" format="r1">
    <ref-clip ref="r10" offset="0s" name="QuestionCard" duration="8500/6000s">
        <adjust-transform position="-69.2694 -6.25289" scale="0.263542 0.263542"/>
    </ref-clip>
    <transition name="Cross Dissolve" offset="7800/6000s" duration="700/6000s">
        ...
    </transition>
</spine>
```

---

## Timing Format

All times are **rational numbers**: `numerator/denominator` + unit

### Examples
| Rational | Decimal | Notes |
|----------|---------|-------|
| `100/6000s` | 0.0167s | 1 frame at 60fps |
| `13100/6000s` | 2.183s | |
| `3600s` | 3600s | Integer seconds allowed |
| `300300/30000s` | 10.01s | |

### Common Timescales
| Timescale | Frame Rate | Example |
|-----------|------------|---------|
| 6000 | 60fps | `100/6000s` = 1 frame |
| 30000 | 30fps | `1001/30000s` = 1 frame (29.97fps) |
| 2500 | 25fps | `100/2500s` = 1 frame |
| 24000 | 24fps | `1001/24000s` = 1 frame (23.976fps) |

### Time Attributes
- `offset` - Position on timeline (where element starts)
- `start` - In-point within source media
- `duration` - Length of element
- `tcStart` - Timecode start (usually `0s` or `3600s` for 1-hour start)

---

## Edit Types

### 1. Transform (`<adjust-transform>`)

Static transform:
```xml
<adjust-transform position="0.434028 -1.2963" scale="1.27998 1.27998"/>
```

Animated transform with keyframes:
```xml
<adjust-transform rotation="1">
    <param name="position">
        <keyframeAnimation>
            <keyframe time="119200/6000s" value="0 0"/>
            <keyframe time="120300/6000s" value="2.31481 0"/>
        </keyframeAnimation>
    </param>
    <param name="scale">
        <keyframeAnimation>
            <keyframe time="119200/6000s" value="1.15 1.15"/>
            <keyframe time="120300/6000s" value="1.5 1.5"/>
        </keyframeAnimation>
    </param>
</adjust-transform>
```

**Transform properties:**
- `position` - X Y offset (normalized? pixels? TBD)
- `scale` - X Y scale factors
- `rotation` - Degrees
- `anchor` - Transform anchor point

**Keyframe attributes:**
- `time` - Rational time within the clip
- `value` - Property value at that time
- `curve` - Interpolation type (optional, e.g., `"linear"`)

### 2. Text Overlay (`<title>`)

```xml
<title ref="r3" lane="2" offset="21606200/6000s"
       name="Intro Highlight Points - Basic Title"
       start="3600s" duration="13000/6000s">
    <param name="Flatten" key="9999/999166631/999166633/2/351" value="1"/>
    <param name="Alignment" key="9999/999166631/999166633/2/354/3296726676/401" value="1 (Center)"/>
    <text>
        <text-style ref="ts1">Intro Highlight Points
</text-style>
    </text>
    <text-style-def id="ts1">
        <text-style font="Helvetica" fontSize="63" fontFace="Regular"
                    fontColor="1 1 1 1" alignment="center"/>
    </text-style-def>
</title>
```

**Text style attributes:**
- `font` - Font family name
- `fontSize` - Point size
- `fontFace` - Weight/style (Regular, Bold, etc.)
- `fontColor` - RGBA (0-1 scale, space-separated)
- `strokeColor` - Outline color (optional)
- `strokeWidth` - Outline width, negative = inside stroke
- `alignment` - left, center, right

**Styled text example (large red text):**
```xml
<text-style font="Chewy" fontSize="262" fontFace="Regular"
            fontColor="0.986252 0.00723597 0.027423 1" alignment="center"/>
```

### 3. B-Roll Insert (`<asset-clip>` on lane 1+)

```xml
<asset-clip ref="r6" lane="1" offset="100500/6000s"
            name="Deer_s_Eye_View_Video_Sequence"
            start="24300/6000s" duration="1228800/1536000s"
            format="r7" tcFormat="NDF" audioRole="dialogue">
    <conform-rate scaleEnabled="0" srcFrameRate="24"/>
</asset-clip>
```

**Key attributes:**
- `ref` - Reference to asset in resources
- `lane` - Must be 1+ for video overlay
- `offset` - Where on timeline
- `start` - In-point in source
- `duration` - How long
- `audioRole` - Audio handling (dialogue, music, effects)

**With transform:**
```xml
<asset-clip ref="r6" lane="1" ...>
    <conform-rate scaleEnabled="0" srcFrameRate="24"/>
    <adjust-transform position="0 11.5741" scale="1.23 1.23"/>
</asset-clip>
```

### 4. Transition (`<transition>`)

```xml
<transition name="Cross Dissolve" offset="7800/6000s" duration="700/6000s">
    <filter-video ref="r14" name="Cross Dissolve">
        <data key="effectConfig">base64-encoded-config</data>
        <param name="Look" key="1" value="11 (Video)"/>
        <param name="Amount" key="2" value="50"/>
        <param name="Ease" key="50" value="2 (In &amp; Out)"/>
        <param name="Ease Amount" key="51" value="0"/>
    </filter-video>
</transition>
```

**Transition attributes:**
- `name` - Human-readable name
- `offset` - Where transition starts (overlaps preceding clip)
- `duration` - Transition length

**Filter-video attributes:**
- `ref` - Reference to effect definition
- `data` - Base64-encoded effect configuration (some effects)
- `param` - Effect parameters with key-value pairs

**Transitions found in example:**
| Name | Parameters |
|------|------------|
| Cross Dissolve | Look, Amount, Ease, Ease Amount |
| Spin | Direction, Center, Angle |
| Page Curl | Preset, Direction, Angle, Rotation, Radius |

### 5. Audio (Lane -1 and below) - FUTURE PHASE

```xml
<asset-clip ref="r8" lane="-1" offset="12664651/720000s"
            name="PopSound" duration="351085/720000s"
            format="r9" audioRole="dialogue"/>
```

With volume adjustment:
```xml
<asset-clip ref="r16" lane="-1" ...>
    <adjust-volume amount="12dB">
        <param name="amount">
            <fadeIn type="easeIn" duration="197384/720000s"/>
            <fadeOut type="easeIn" duration="159102/720000s"/>
        </param>
    </adjust-volume>
</asset-clip>
```

---

## Other Elements Found

### Multicam Clips
```xml
<mc-clip ref="r17" offset="222500/30000s" name="Take2MultiCam"
         start="2276900/30000s" duration="500/30000s">
    <conform-rate scaleEnabled="0" srcFrameRate="25"/>
    <adjust-volume amount="9dB"/>
    <mc-source angleID="flBipD7DSz+e6SpJzGZ4ug" srcEnable="audio"/>
    <mc-source angleID="vRF2MY1nSomvQ5kOYsGdYA" srcEnable="video">
        <adjust-transform>...</adjust-transform>
    </mc-source>
</mc-clip>
```

### Reference Clips (Compound Clips)
```xml
<ref-clip ref="r10" offset="0s" name="QuestionCard" duration="8500/6000s">
    <adjust-transform position="-69.2694 -6.25289" scale="0.263542 0.263542"/>
</ref-clip>
```

### Conform Rate
Frame rate handling for mixed-rate media:
```xml
<conform-rate scaleEnabled="0" srcFrameRate="24"/>
```

### Blend Modes
```xml
<adjust-blend mode="25 (Stencil Alpha)"/>
```

---

## Coordinate System

**Position values** appear to be in a normalized or point-based system:
- Small values like `0.434028 -1.2963` suggest normalized (-1 to 1 range?)
- Larger values like `-69.2694 -6.25289` suggest pixels or points

**Need to verify:** What coordinate system does FCP use for position?

---

## Questions Answered

1. **FCPXML Version:** 1.13 (FCP 10.6+)
2. **Timing format:** Rational numbers (numerator/denominator + "s")
3. **How effects are referenced:** By ID in resources, with UID for FCP lookup
4. **Lane system:** 0 = main, positive = video overlays, negative = audio
5. **Keyframe structure:** `<keyframeAnimation>` with `<keyframe time="" value=""/>` elements

---

## Questions Still Open

1. **Position coordinate system:** Normalized? Pixels? Points?
2. **Effect UIDs:** Do we need to include these, or does FCP find them by name?
3. **Bookmark data:** Required for media reconnection? Can we skip?
4. **effectConfig data blobs:** What format? Do we need to preserve them?
5. **Param keys:** What do the numeric keys mean? (e.g., `key="9999/988461322/100/988461395/2/100"`)

---

*Last updated: 2026-02-03*

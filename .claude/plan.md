# Plan: Add Copy Chunk Button to Markov Input Tab

## What
Add a `CompactCopyButton` to each chunk card in the Markov Script Writer Input tab that copies all chunk data as a formatted text block to the pasteboard.

## Where
**Single file change**: `MarkovScriptWriterView.swift`

## Changes

### 1. Add a helper method to format a RamblingGist as copyable text

Add a private method `formatGistForCopy(_ gist: RamblingGist) -> String` that builds a multi-line string containing all chunk data:

```
── Chunk 3 ──
Move: hidden-truth (85%)
Frame: reveal

GistA (Deterministic)
  Subject: topic1, topic2
  Premise: One neutral sentence about the chunk
  Frame: reveal

GistB (Flexible)
  Subject: phrase1, phrase2
  Premise: What this chunk accomplishes
  Frame: reveal

Source Text:
  The original rambling text content here...

Telemetry:
  Stance: ASSERTING
  1P: 3  2P: 0  3P: 2
  Numbers: 1  Temporal: 0  Contrast: 2  Questions: 1  Quotes: 0  Spatial: 0  Technical: 1
```

- Move label and confidence included when present
- Telemetry section only included when telemetry exists
- All fields from the RamblingGist are represented

### 2. Add CompactCopyButton to the card header HStack

In `ramblingGistCard()`, place a `CompactCopyButton` in the header row between the confidence percentage and the expand/collapse chevron. This keeps it always visible (not just when expanded) and uses the existing `CompactCopyButton` from `FadeOutCopyButton.swift` which already handles:
- Icon swap: `doc.on.doc` → `checkmark.circle.fill`
- Color swap: secondary → green
- 2-second reset timer (will change from 1.5 to 2.0 per CLAUDE.md requirement)
- Pasteboard save (cross-platform UIKit/AppKit)

The copy button will use `formatGistForCopy(gist)` as its text parameter.

### 3. Fix CompactCopyButton duration

CLAUDE.md requires copy buttons keep their changed icon for 2 seconds. `CompactCopyButton` currently uses 1.5s — will update to 2.0s.

## Files Modified
1. `NewAgentBuilder/YouTube/MarkovScriptWriter/MarkovScriptWriterView.swift` — add format helper + copy button in card header
2. `NewAgentBuilder/YouTube/GistScriptWriter/FadeOutCopyButton.swift` — change CompactCopyButton default fadeDuration from 1.5 to 2.0

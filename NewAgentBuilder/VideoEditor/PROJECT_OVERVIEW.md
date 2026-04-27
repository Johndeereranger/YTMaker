# Video Editor Project Overview

## Project Goal
Build an "edit-by-script" pipeline that treats video editing as a DECLARATIVE process rather than manual timeline manipulation.

---

## Phase 1A: Core Infrastructure ✅ COMPLETE

| Task | Status | Notes |
|------|--------|-------|
| Video/Audio Import | ✅ Done | iOS app running on Mac Catalyst |
| Whisper Transcription | ✅ Done | WhisperKit with word-level timestamps |
| Core Data Models | ✅ Done | TranscribedWord, SpeechSegment, DetectedGap, RepeatedPhrase |
| Basic Timeline Visualization | ✅ Done | Waveform + words on timeline |

**Files:**
- `Services/WhisperTranscriptionService.swift`
- `Services/AudioWaveformService.swift`
- `Models/VideoProject.swift`

---

## Phase 1B: Pause Detection & Take Selection 🔄 IN PROGRESS

| Task | Status | Notes |
|------|--------|-------|
| Silence/Pause Detection | ✅ Done | GapDetectionService detects gaps from waveform |
| Gap Review UI | ✅ Done | VideoEditorProjectView shows gaps with keep/cut controls |
| Duplicate Phrase Detection | ✅ Done | Fuzzy text matching finds repeated takes |
| Duplicate Review UI | ✅ Done | DuplicateReviewView for comparing/selecting takes |
| Cut Boundary Refinement | ✅ Done | Uses waveform to find TRUE silence, not Whisper approximations |
| Preview Composition | ✅ Done | AVMutableComposition with cuts applied in-memory |
| Export Clean Timeline | ❌ TODO | Actual file export not yet implemented |

**Cut Boundary Refinement Details (2026-02-03):**
- Silence threshold: 0.02 (on dB-normalized scale where 0.0 = -60dB true silence)
- Search window: 500ms
- Search directions: BACKWARD for cut start, FORWARD for cut end
- Buffer: 80ms into silence (not at edge)
- Waveform uses dB normalization, true silence is 0.0-0.02

**Files:**
- `Services/GapDetectionService.swift`
- `Services/DuplicateDetectionService.swift`
- `Services/CutBoundaryRefiner.swift`
- `Services/PreviewCompositionService.swift`
- `Views/VideoEditorProjectView.swift`
- `Views/DuplicateReviewView.swift`

---

## Phase 2: Visual Cue Preset Library 🔄 IN PROGRESS

### Phase 2A: Foundation & Preset Library

| Task | Status | Notes |
|------|--------|-------|
| CMTime Migration | ✅ Done | Refactored Phase 1 from TimeInterval → CMTime |
| FCPXML Parser | ✅ Done | Import FCPXML, extract edits |
| Preset Data Models | ✅ Done | Transform, TextOverlay, BRoll, Transition |
| Preset Storage | ✅ Done | Save/load presets locally |
| Preset Library UI | ✅ Done | Browse, favorites, recents, filtering |
| Preset Creation Flow | 🔄 WIP | Import FCPXML → Review each edit with video preview → Save as preset |

### Phase 2B: Manual Edit Application

| Task | Status | Notes |
|------|--------|-------|
| Apply Preset to Timeline | ❌ TODO | Place edit at specified anchor point |
| Edit Review UI | ❌ TODO | See applied edits, adjust timing |
| Edit List View | ❌ TODO | All edits on current project |
| FCPXML Export | ❌ TODO | Generate valid FCPXML with edits |

### Phase 2C: Script-Driven Editing (Later)

| Task | Status | Notes |
|------|--------|-------|
| Visual Cue Document Model | ❌ TODO | Link presets to script chunks |
| Chunk-to-Timeline Mapping | ❌ TODO | Match script to transcript |
| Batch Apply | ❌ TODO | Apply all cues from script |

**Key Concept:** Build the preset library FIRST, then connect it to script-driven workflow.

**Documentation:** See `FCP_EDIT_MODELS.md` for detailed mental models of each edit type.

---

## Phase 3: Music Intelligence ❌ NOT STARTED

| Task | Status | Notes |
|------|--------|-------|
| Audio Separation (Demucs) | ❌ TODO | Separate vocals from music in template videos |
| Template Creator Analyzer | ❌ TODO | Learn music usage patterns from creators |
| LLM Mood Detection | ❌ TODO | Detect mood from script text |
| Pattern Learning Database | ❌ TODO | Store mood→music correlations |
| Music Library Auto-Tagging | ❌ TODO | Local library with BPM, energy, mood tags |
| Apply Patterns | ❌ TODO | Suggest music for your content based on patterns |

---

## Open Questions

### Resolved
- ✅ **FCPXML Version:** Targeting 1.13 (FCP 10.6+)
- ✅ **Timing Format:** CMTime throughout (not TimeInterval)
- ✅ **Audio Overlays:** Separate future phase, not in Phase 2

### Still Open
1. **B-Roll Media Handling:** How to reference media in presets? Path? Thumbnail? Library reference?
2. **Demucs Integration:** Local Python vs Replicate API (~$0.02/min)?
3. **Audio Analysis Tool:** Essentia (comprehensive) vs librosa (simpler)?
4. **Chunk Detection:** How to auto-break content into chunks?

---

## Technical Notes

### CMTime Usage (Decision: 2026-02-03)
All timeline timing uses `CMTime` (rational time) instead of `TimeInterval`:
- Frame-accurate, no floating point drift
- Matches FCPXML rational format exactly
- AVFoundation native type

**Files requiring migration:**
- `Models/VideoProject.swift` - TranscribedWord, SpeechSegment timestamps
- `Models/DetectedGap.swift` - startTime, endTime
- `Services/GapDetectionService.swift` - gap calculations
- `Services/CutBoundaryRefiner.swift` - refinement logic
- `Services/AudioWaveformService.swift` - public API (internal stays sample-based)

### Waveform Amplitude Scale
The waveform uses dB normalization:
- 0.0 = -60dB (true silence)
- 0.5 = -30dB (quiet)
- 1.0 = 0dB (loud)

True silence ([BLANK_AUDIO]) reads as 0.0-0.02 on this scale.

### Cut Boundary Logic
1. Whisper gives approximate timestamps
2. CutBoundaryRefiner searches waveform for actual silence
3. Search BACKWARD from cut start to find where preceding silence ends
4. Search FORWARD from cut end to find where following silence begins
5. Add 80ms buffer to cut deeper INTO silence (not at edge)

---

*Last updated: 2026-02-03 (CMTime decision, Phase 2 restructured)*

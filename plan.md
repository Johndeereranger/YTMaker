# Plan: Pass 2 Prompt Overhaul — Gap-Aware Structural Expansion

## Problem

Pass 2 reuses the exact same prompts as Pass 1 with only one difference: `effectiveRamblingText` appends the supplemental rambling after a `SUPPLEMENTAL RAMBLING (responding to narrative gaps):` separator. The prompt engine has zero awareness that this is Pass 2, zero awareness of what gaps were identified, and gives zero instruction to expand the beat structure. The model reads the same core rambling, builds the same 10-beat spine, and stuffs the supplemental content into existing beats' `contentTag` fields rather than creating new beats.

## Root Cause

The supplemental content is treated as "bonus context" rather than "structural expansion material." The model has no idea:
- What specific gaps were identified
- What structural moves (expected-path, mechanism, complication, etc.) are missing
- That the Pass 1 beat count is a floor, not a target
- That each gap response should be evaluated as a potential new beat

## Data Already Available

The `GapAnalysisRun` (from the gap detection phase) contains `GapFinding` objects with:
- `type` — structural, causal, content-density, viewer-state, payoff, creator-signature
- `action` — RESHAPE, SURFACE, CONTENT_GAP
- `location` — where in the spine the gap exists
- `whatsMissing` — what's missing
- `whyItMatters` — why it matters structurally
- `questionToRambler` — the question the user answered
- `priority` — HIGH, MEDIUM, LOW
- `effectiveQuestion` — refined question if available

The G6 synthesis path produces a merged/deduped best-of set. This is the ideal source for gap context.

## Implementation

### Step 1: Add `gapFindings` property to `ArcComparisonViewModel`

**File:** `ArcComparisonViewModel.swift`

Add a `@Published var gapFindings: [GapFinding] = []` property. For `isPass2` instances, this gets populated from the gap VM's current run (the G6 synthesis findings, or all findings if G6 isn't available). This is wired in `ArcPipelineView` alongside the existing `wirePass2Dependencies()` call.

### Step 2: Add gap findings parameter to `ArcComparisonRunner`

**File:** `ArcComparisonRunner.swift`

Add `let gapFindings: [GapFinding]` to the runner struct (defaulting to `[]`). Pass it through to each `runP1`...`runP5` static method. When non-empty, pass it to the prompt engine's new Pass 2 variants.

### Step 3: Add Pass 2 prompt variants to `ArcComparisonPromptEngine`

**File:** `ArcComparisonPromptEngine.swift`

This is the core change. Add:

**A) A `renderGapContext` helper** that formats the gap findings into a prompt section:

```
## Gap Analysis Context

A previous spine was built from the original rambling alone. Gap analysis identified the
following structural weaknesses. The supplemental rambling below was recorded specifically
to address these gaps.

CRITICAL INSTRUCTIONS FOR THIS PASS:
- The supplemental rambling contains answers to identified structural gaps
- Each gap response should be evaluated as a potential NEW beat, not just enrichment
- The beat count from the initial spine is a FLOOR, not a target — add MORE beats
- Actively look for these specific missing structural moves in the combined material

### Identified Gaps (ordered by priority)

1. [HIGH] [structural] Between beats 3-4
   Missing: expected-path — The conventional approach that was tried and failed
   Why it matters: The reframe has no contrast
   Question answered: "What did you try first before discovering this approach?"

2. [HIGH] [causal] After beat 7
   Missing: mechanism — The behavioral science explaining WHY
   ...
```

**B) Pass 2 variants of each path prompt function.** For paths that receive `rawRambling` directly (P1, P4), the gap context section is inserted between the rules and the raw rambling. For paths that use content inventory (P2, P3, P5), the gap context is inserted into the content inventory prompt AND the spine construction prompt so the inventory step also captures the new content atoms.

The key additions to each prompt:
- The gap context block (from `renderGapContext`)
- An explicit rule: "The supplemental rambling addresses specific structural gaps. Content from it that maps to an identified gap should become its own beat with the function label the gap analysis identified as missing."
- Modified beat count guidance: "This material has been enriched with gap responses. The target beat count should be HIGHER than a first-pass spine because there is more structural content."

### Step 4: Wire gap findings through the pipeline

**File:** `ArcComparisonViewModel.swift` — In `startRun()`, pass `gapFindings` to the runner.

**File:** `ArcPipelineView.swift` — In `wirePass2Dependencies()` (and after gap run auto-load), populate `pass2VM.gapFindings` from the gap VM's current run findings.

### Step 5: Pass findings through runner to prompt engine

**File:** `ArcComparisonRunner.swift` — Each `runPX` method checks if `gapFindings` is non-empty. If so, it calls the Pass 2 prompt variant instead of the Pass 1 variant from the prompt engine.

## Files Changed

1. **`ArcComparisonPromptEngine.swift`** — Add `renderGapContext()`, add Pass 2 prompt variants for all 5 paths (or conditional gap context injection into existing functions)
2. **`ArcComparisonRunner.swift`** — Add `gapFindings` parameter, route to Pass 2 prompts when present
3. **`ArcComparisonViewModel.swift`** — Add `gapFindings` property, pass to runner in `startRun()`
4. **`ArcPipelineView.swift`** — Wire `pass2VM.gapFindings` from gap VM results

## What's NOT Changing

- The gap analysis pipeline itself (G1-G6) — untouched
- The `GapFinding` model — already has all the data we need
- The `effectiveRamblingText` concatenation — the supplemental rambling still gets appended the same way. The gap context is ADDITIONAL structured metadata injected into the prompt, not a replacement for the raw rambling append.
- Pass 1 prompts — completely untouched. Only Pass 2 (when gap findings exist) gets the new treatment.
- The JSON output format — unchanged. The model still returns the same spine JSON schema.

## Design Decision: Conditional Variants vs. Separate Functions

Rather than creating 5 entirely new prompt functions (p1Pass2, p2Pass2, etc.), each existing prompt function gains an optional `gapFindings: [GapFinding] = []` parameter. When non-empty, the gap context block is injected into the appropriate location in the prompt. This avoids duplicating the entire prompt template and keeps the diff minimal. If a gap finding list is empty, the prompt is identical to Pass 1.

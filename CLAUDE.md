# Project Instructions for Claude Code
If Doing any Debuging printing: Every debug output must answer three questions at every decision point: WHAT did the algorithm decide, WHAT did the raw data actually show, and WHY did the algorithm interpret the raw data the way it did. If any of those three are missing, the debug is incomplete. The 'why' layer specifically means showing the scoring/threshold logic that transformed raw observations into scores — not just the inputs and not just the outputs, but the transfer function between them.  All Copy Buttons must change icon upon press and keep that change for 2 seconds and needs to save to paste board.  There are likely Multiple copy buttons already in the code.

# Reusable Components
- **FlowLayout** — a shared horizontal-wrapping `Layout` lives in `Helpers/FlowLayout.swift`. Use it directly, do NOT create private copies in other files.

# Gotchas & Footguns
- **Never use `%s` in Swift `String(format:)`** — it expects a C `char*` pointer and will crash with EXC_BAD_ACCESS. Use `.padding(toLength:withPad:startingAt:)` for aligned columns, or `%@` for simple (non-width-formatted) strings.
- **Never use `.claude35Sonnet` for ClaudeModelAdapter** — the model `claude-3-5-sonnet-20241022` is deprecated and returns HTTP 404. Always use `.claude4Sonnet` (or `.claude4Opus` for heavy tasks). Check `AIModel.swift` for available model enum cases.

# Parallel LLM Calls
- **Target concurrency: 10–15 simultaneous LLM calls.** Meter with a task group concurrency limit if batches exceed that.
- **`@MainActor` services serialize LLM calls.** If a `@MainActor` class wraps `ClaudeModelAdapter`, every `await adapter.generate_response(...)` hops to MainActor and back, effectively running one at a time. Fix: use a `nonisolated static` method that creates its own `ClaudeModelAdapter` per call — see `NarrativeSpineService.extractSpineParallel(...)` for the pattern.
- **Each parallel task needs its own adapter instance.** Shared adapter instances may have internal state that serializes. Create `ClaudeModelAdapter(model:)` inside the task closure or the static method.
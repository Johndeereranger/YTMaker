## Implementation Rules

- NEVER add, create, modify, wire up, suggest, or run automated tests unless the user explicitly asks for tests in that specific request.
- This prohibition includes XCTest files, test targets, snapshot tests, integration tests, smoke tests, fixtures created for tests, and any other validation scaffolding whose purpose is testing.
- DO NOT touch `project.pbxproj` for test-related reasons unless the user explicitly requests test setup.
- If a task would normally benefit from tests, skip them silently unless the user explicitly asks for them.
- Default to no tests, no test files, no test targets, and no test-related project changes.

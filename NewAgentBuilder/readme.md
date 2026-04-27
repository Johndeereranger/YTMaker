
# 🧠 Agent Builder

## Prompt Engineering Made Tangible

Agent Builder is a Swift-based app for creating, running, and refining AI workflows through structured prompt sequences. Design multi-step agents, track every detail of execution, and systematically improve your prompt engineering.

**From chaotic prompt hacking to structured AI development.**

---

## 📋 Quick Reference Guide

| File/Component | Purpose | Key Details |
|----------------|---------|-------------|
| `AgentListView` | Entry point showing all agents | Navigation to detail/runner views and session history |
| `AgentDetailView` | Backend configuration of agents | Add/edit/reorder prompt steps |
| `AgentRunnerView` | Execute agents step-by-step | Process inputs, view outputs, provide feedback |
| `PromptInspector` | Performance diagnostics | View runs, metrics, and feedback for a prompt step |

---

## 🧱 Core Data Models

### Agent (The Orchestrator)
```swift
struct Agent: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var name: String
    var description: String?
    var category: String?
    var promptSteps: [PromptStep]
    var enabledPromptStepIds: [UUID] = []
    var chatSessions: [ChatSession] = []
}
```
The central entity that defines an AI workflow. Contains a sequence of prompt steps and tracks all execution sessions.

### PromptStep (The Individual Task)
```swift
struct PromptStep: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var title: String
    var prompt: String
    var notes: String
}
```
A single stage in an agent's process flow, containing the instructions (prompt) for that specific task.

### ChatSession (The Execution Context)
```swift
struct ChatSession: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var agentId: UUID
    var title: String
    var createdAt: Date
}
```
A record of one run of an agent, grouping related prompt runs together.

### PromptRun (The Individual Execution)
```swift
struct PromptRun: Identifiable, Codable, Equatable, Hashable {
    var id: UUID
    var promptStepId: UUID
    var chatSessionId: UUID?
    var basePrompt: String
    var userInput: String
    var finalPrompt: String
    var response: String
    var createdAt: Date
    var inputID: String?
    var purpose: PromptRunPurpose = .normal
    var feedbackRating: Int?
    var feedbackNote: String?
    
    // Diagnostic fields
    var modelUsed: String?
    var promptTokenCount: Int?
    var completionTokenCount: Int?
    var totalTokenCount: Int?
    var finishReason: String?
    var openAIRequestId: String?
    var cachedTokens: Int?
    var imageURL: String?
}
```
The atomic unit of execution, capturing every AI call with full context, inputs/outputs, and performance metrics.

### PromptRunPurpose (Execution Intent)
```swift
enum PromptRunPurpose: String, Codable, CaseIterable {
    case normal     // Standard execution
    case retry      // Re-running to test consistency
    case fork       // Testing a prompt variation
    case inputVariation // Testing different inputs
    case diagnostic // For troubleshooting
}
```
Categorizes why a specific run was performed, enabling structured prompt engineering.

---

## 🔄 Application Flow & View Relationships

### 1. Agent List View
- **Entry Point**: Displays all available agents
- **Navigation Options**:
  - → Agent Detail View (for editing)
  - → Agent Runner View (for execution)
  - → Sessions History (past runs)
- **Implementation Notes**: 
  - Primary dashboard showing agent name, category, and last run date
  - Each agent card has a context menu for actions

### 2. Agent Detail View
- **Purpose**: Backend configuration interface
- **Key Functions**:
  - Add new prompt steps
  - Reorder existing steps
  - Edit step content
  - Access the Prompt Inspector
- **Child Views**:
  - Prompt Step Create/Edit View 
  - → Prompt Inspector (diagnostics for individual steps)
- **Implementation Notes**:
  - Uses a list with drag-to-reorder functionality
  - Disclosure groups for each prompt step

### 3. Prompt Inspector
- **Purpose**: Analytics dashboard for a specific prompt step
- **Displays**:
  - All historical runs of the step
  - Performance metrics (tokens, time)
  - Inputs/outputs
  - User feedback
- **Implementation Notes**:
  - Filterable by feedback score and purpose
  - Groups runs by inputID for comparison

### 4. Agent Runner View
- **Purpose**: Execution environment
- **Flow**:
  1. Session header (displays agent and step info)
  2. Current prompt step display
  3. Input field for user content
  4. Run button with "thinking" indicator
  5. Results display with disclosure groups
  6. Feedback interface (rating + notes)
- **Actions**:
  - **Retry**: Re-run with same prompt/input
  - **Use This Result**: Move to next step (current output becomes next input)
  - **Ask AI for Help**: Meta-prompt for improvement suggestions
  - **Fork**: Create a variant prompt
  - **Copy All**: Export prompt/input/output
- **Implementation Notes**:
  - Stateful view tracking current step index
  - Disclosure groups to hide/show details
  - Real-time token counting

---

## 🔍 Key Technical Concepts

### Prompt Construction Logic
- **Base Prompt**: The core instructions defined in the PromptStep
- **User Input**: Variable content being processed
- **Final Prompt**: Combined prompt sent to AI (base + input)
- **Critical Note**: Base prompt contains detailed instructions, not just a brief system message

### Data Relationships
- Agent (1) → PromptSteps (many)
- Agent (1) → ChatSessions (many)
- ChatSession (1) → PromptRuns (many)
- PromptStep (1) → PromptRuns (many)

### Input Tracking
- **inputID**: Groups related runs using the same input
- Enables comparing different prompts against identical inputs
- Critical for systematic prompt engineering

### Prompt Evolution
- **Fork**: Creates a new prompt variation
- Each fork preserves the original's context
- Enables branching exploration of prompt design

### Feedback System
- 1-5 star rating + optional notes
- Used to track quality over iterations
- Powers the "Ask AI for Help" feature

---

## 💡 Implementation Focus Areas

### 1. Data Persistence
- Current implementation uses local storage
- Structure supports future Firestore integration
- All models conform to `Codable` for serialization

### 2. UI/UX Considerations
- **AgentListView**: Grid or list layout with search/filter
- **AgentDetailView**: Drag-reorder interface for prompt steps
- **AgentRunnerView**: Step indicator, clear action buttons, feedback UI
- **PromptInspector**: Data visualization for metrics, comparison tools

### 3. Performance Tracking
- Token counting for cost estimation
- Response time measurement
- Model identification
- Caching capability for repeated runs

### 4. Extensibility Points
- **imageURL** field supports future image generation
- Structure allows for future integration with external APIs
- Authentication layer can be added for multi-user scenarios

---

## 🚦 Usage Workflows

### Creating a New Agent
1. From AgentListView, tap "+" to create a new agent
2. Name it and optionally add description/category
3. In AgentDetailView, add prompt steps
4. For each step, define:
   - Title (purpose of the step)
   - Prompt (detailed instructions)
   - Notes (implementation details, expected behavior)
5. Save and return to AgentListView

### Running an Agent
1. From AgentListView, select an agent and tap "Run"
2. AgentRunnerView shows the first prompt step
3. Enter input text and tap "Run"
4. Review the AI response
5. Provide feedback (1-5 rating + notes)
6. Choose next action:
   - Move to next step
   - Retry with same parameters
   - Fork to try a variation
   - Ask AI for help improving the prompt
7. Continue until all steps complete
8. Session is saved in history

### Analyzing Performance
1. From AgentDetailView, select a prompt step
2. Open PromptInspector
3. View all historical runs of that step
4. Analyze:
   - Token usage patterns
   - Response quality (via feedback)
   - Different variations (via purpose and inputID)
5. Use insights to improve the prompt

---

## 🔮 Future Direction 

The current architecture supports these planned enhancements:

### Near-term
- True chat-based agents (multi-turn conversations)
- Prompt templates library
- Export/import of agents and prompt steps

### Medium-term
- Integration with AI image generators
- Database/API connectors for external data
- Cost tracking and optimization tools

### Long-term
- Cross-agent communication
- Collaborative agent building
- Marketplace for sharing agents

---

## 🚀 Getting Started for Developers

### Prerequisites
- Xcode 14+
- Swift 5.7+
- iOS 16+ (for deployment)

### Setup
1. Clone the repository
2. Open the project in Xcode
3. Build and run

### Key Files
- `Models/`: Contains all data model definitions
- `Views/`: UI components organized by main view
- `Services/`: API clients and business logic
- `Utils/`: Helper functions and extensions

---

## Behind the Scenes: The Mental Model

Agent Builder is built around the philosophy of "AI thought as a pipeline":

1. Each **Agent** represents a solution to a specific problem
2. Each **PromptStep** is a discrete thinking stage
3. The sequence of steps creates a logical flow
4. Each **PromptRun** is a snapshot of AI reasoning
5. **ChatSessions** group these snapshots into a coherent story

This mental model scales from simple prompt testing to complex, multi-stage AI workflows.

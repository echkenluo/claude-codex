# Claude Code - Multi-AI Pipeline Project

> **IMPORTANT**: This project uses a subagent-based orchestrator workflow. The main Claude Code thread coordinates subagents for planning, implementation, and internal reviews. Codex is called only at key checkpoints.

## Architecture Overview

```
Main Claude Code Thread (Orchestrator)
  │
  ├── Subagents (do the work):
  │     ├── planner         → Drafts and refines plans
  │     ├── researcher      → Gathers codebase context
  │     ├── implementer     → Writes code
  │     ├── reviewer-sonnet → Fast internal review (code + security + tests)
  │     └── reviewer-opus   → Deep internal review (code + security + tests)
  │
  └── Codex (final reviews only):
        ├── End of planning phase
        └── End of implementation phase
```

---

## When User Asks to Implement Something

Guide users to use the orchestrator workflow:

```
This project uses a subagent-based orchestrator (Claude subagents + Codex reviews).

To implement your request:

1. Create your request:
   echo "Your feature description here" > .task/user-request.txt

2. Start the pipeline:
   ./scripts/state-manager.sh set plan_drafting ""
   ./scripts/orchestrator.sh

The pipeline will:
- Create and refine a plan (planner + researcher subagents)
- Run internal reviews (reviewer-sonnet + reviewer-opus)
- Final plan review (Codex)
- Implement the code (implementer subagent)
- Run internal reviews (reviewer-sonnet + reviewer-opus)
- Final code review (Codex)

For status: ./scripts/orchestrator.sh status
For recovery: ./scripts/recover.sh
```

---

## How the Orchestrator Works

The orchestrator displays the current state and what action to take:

```bash
$ ./scripts/orchestrator.sh
[INFO] Current state: plan_drafting

ACTION: Invoke 'planner' subagent

Task: Create initial plan from user request
Input: .task/user-request.txt
Output: .task/plan.json

After completion, transition state:
  ./scripts/state-manager.sh set plan_refining "$(jq -r .id .task/plan.json)"
```

### Workflow Steps

1. **Read the ACTION** - See which subagent to invoke
2. **Invoke the subagent** - Use Task tool with the specified agent
3. **Write output file** - Subagent writes to the specified output location
4. **Transition state** - Run the shown state-manager command
5. **Run orchestrator again** - See the next action

---

## Subagents

Located in `.claude/agents/`:

| Subagent | Purpose | Model |
|----------|---------|-------|
| `planner` | Drafts and refines plans | opus |
| `researcher` | Gathers codebase context | opus |
| `implementer` | Writes code | opus |
| `reviewer-sonnet` | Fast review (code + security + tests) | sonnet |
| `reviewer-opus` | Deep review (code + security + tests) | opus |

> **Dual Review Model**: Internal reviewers run in parallel with both sonnet and opus models to get different perspectives. Both must approve before proceeding to Codex.

### Invoking Subagents

Use the Task tool to invoke subagents:

```
Task: planner
Prompt: "Create an initial plan for the user request in .task/user-request.txt. Output to .task/plan.json"
```

---

## State Machine

```
idle
  ↓
plan_drafting (planner subagent)
  ↓
plan_refining (planner + researcher + reviewer internal loop)
  ↓
plan_reviewing (Codex final review) ←──────────────────┐
  ↓                                                    │
  [needs_changes] → back to plan_refining ─────────────┘
  ↓ [approved]
implementing (implementer + internal reviewers loop)
  ↓
reviewing (Codex final review) ←───────────────────────┐
  ↓                                                    │
  [needs_changes] → fixing → back to reviewing ────────┘
  ↓ [approved]
complete
```

---

## Shared Knowledge

Read these docs before any work:
- `docs/standards.md` - Coding standards and review criteria
- `docs/workflow.md` - Pipeline process and output formats

---

## Output Formats

### Plan Creation Output
Write to: `.task/plan.json`

```json
{
  "id": "plan-YYYYMMDD-HHMMSS",
  "title": "Short descriptive title",
  "description": "What the user wants to achieve",
  "requirements": ["req1", "req2"],
  "created_at": "ISO8601",
  "created_by": "planner"
}
```

### Plan Refinement Output
Write to: `.task/plan-refined.json`

```json
{
  "id": "plan-001",
  "title": "Feature title",
  "description": "What the user wants",
  "requirements": ["req 1", "req 2"],
  "technical_approach": "Detailed description of how to implement",
  "files_to_modify": ["path/to/existing/file.ts"],
  "files_to_create": ["path/to/new/file.ts"],
  "dependencies": ["any new packages needed"],
  "estimated_complexity": "low|medium|high",
  "potential_challenges": [
    "Challenge 1 and how to address it",
    "Challenge 2 and how to address it"
  ],
  "refined_by": "planner",
  "refined_at": "ISO8601"
}
```

### Implementation Output
Write to: `.task/impl-result.json`

```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

### Internal Review Outputs (Dual-Model)

| File | Reviewer |
|------|----------|
| `.task/internal-review-sonnet.json` | reviewer-sonnet |
| `.task/internal-review-opus.json` | reviewer-opus |

---

## Review Handling

### Internal Reviews (Subagents)

**Both planning and implementation phases**:
- Run 2 reviewers in parallel: reviewer-sonnet + reviewer-opus
- Each reviewer covers code quality, security, and test coverage
- Both must approve before proceeding to Codex

If any reviewer returns `needs_changes`, fix and re-review.

### Codex Final Reviews

Codex is called at two checkpoints:
1. **End of planning** → `./scripts/run-codex-plan-review.sh`
2. **End of implementation** → `./scripts/run-codex-review.sh`

If Codex requests changes:
- Return to previous phase (plan_refining or fixing)
- Address ALL concerns
- Re-run internal reviews
- Submit for Codex review again

---

## Strict Loop-Until-Pass Model

- Reviews loop until approved
- No debate mechanism - accept all review feedback
- Fix ALL issues raised by any reviewer

> **Note**: Loop limits (planReviewLoopLimit: 10, codeReviewLoopLimit: 15) are defined in `pipeline.config.json` for reference. The main Claude thread should track iterations and enforce limits manually.

---

## Asking for Clarification

If a plan or task is too ambiguous, add to your output:

```json
{
  "needs_clarification": true,
  "questions": [
    "Question 1 for the user?",
    "Question 2 for the user?"
  ]
}
```

The orchestrator will transition to `needs_user_input` state.

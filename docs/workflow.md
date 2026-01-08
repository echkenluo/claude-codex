# Pipeline Workflow

## Architecture Overview

This pipeline uses a **skill-based sequential architecture**:

- **Main Claude Code thread** = Does planning, research, and implementation directly
- **Reviewer Skills** = Sequential reviews with forked context isolation
- **Codex** = Final review via skill (invokes Codex CLI)

### Reviewer Skills

Located in `.claude/skills/`:

| Skill | Purpose | Model |
|-------|---------|-------|
| `review-sonnet` | Fast review (code + security + tests) | sonnet |
| `review-opus` | Deep review (architecture + subtle bugs) | opus |
| `review-codex` | Final review via Codex CLI | codex |

> **Why sequential?** Each model reviews only ONCE per cycle, providing progressive refinement (fast → deep → final) without re-reviewing the same content.

> **Context isolation**: Skills run with `context: fork` to isolate review feedback and preserve token efficiency.

---

## Quick Start with `/multi-ai`

The easiest way to use this pipeline:

```
/multi-ai Add user authentication with JWT tokens
```

This command handles the entire workflow automatically.

### Manual Start

1. Create `.task/user-request.txt` with your request
2. Set state: `./scripts/state-manager.sh set plan_drafting ""`
3. Run: `./scripts/orchestrator.sh`

---

## Workflow Phases

### Phase 1: Planning

```
plan_drafting
     ↓ (main thread creates initial plan)
plan_refining
     ↓ (main thread researches and refines)
     ↓ Sequential reviews:
     │   1. /review-sonnet → fix issues
     │   2. /review-opus → fix issues
     │   3. /review-codex → fix issues (restart from step 1 if needed)
     ↓ [all approved]
implementing
```

**Flow:**
1. Main thread → Creates initial plan from user request
2. Main thread → Researches codebase and refines plan with technical details
3. **Sequential Reviews**:
   - `/review-sonnet` → Fast scan, if issues: fix, continue
   - `/review-opus` → Deep analysis, if issues: fix, continue
   - `/review-codex` → Final review, if issues: fix, restart from sonnet

### Phase 2: Implementation

```
implementing
     ↓ (main thread writes code)
     ↓ Sequential reviews:
     │   1. /review-sonnet → fix issues
     │   2. /review-opus → fix issues
     │   3. /review-codex → fix issues (restart from step 1 if needed)
     ↓ [all approved]
complete
```

**Flow:**
1. Main thread → Writes code following standards
2. **Sequential Reviews**:
   - `/review-sonnet` → Code quality + security + tests
   - `/review-opus` → Architecture + subtle bugs + test quality
   - `/review-codex` → Final approval via Codex CLI

---

## Using the Orchestrator

The orchestrator shows the current state and what action to take next:

```bash
./scripts/orchestrator.sh
```

Example output:
```
[INFO] Current state: plan_refining

ACTION: Refine plan with technical details (main thread)

Task: Research codebase and refine plan
Input: .task/plan.json
Output: .task/plan-refined.json

After completion, run SEQUENTIAL reviews (each model reviews once):
  1. Invoke /review-sonnet → .task/review-sonnet.json
     If needs_changes: fix issues, then continue to step 2
  2. Invoke /review-opus → .task/review-opus.json
     If needs_changes: fix issues, then continue to step 3
  3. Invoke /review-codex → .task/review-codex.json
     If needs_changes: fix issues, restart from step 1
     If approved: transition to implementing

When all reviews pass:
  ./scripts/state-manager.sh set implementing "$(jq -r .id .task/plan-refined.json)"
```

### Commands

| Command | Purpose |
|---------|---------|
| `./scripts/orchestrator.sh` | Show current state and next action |
| `./scripts/orchestrator.sh status` | Show current state details |
| `./scripts/orchestrator.sh reset` | Reset pipeline to idle |
| `./scripts/orchestrator.sh dry-run` | Validate setup |

---

## State Machine

### States

| State | Description |
|-------|-------------|
| `idle` | No active task |
| `plan_drafting` | Creating initial plan |
| `plan_refining` | Refining plan + sequential skill reviews |
| `implementing` | Writing code + sequential skill reviews |
| `complete` | Task finished |
| `error` | Pipeline error |
| `needs_user_input` | Waiting for user clarification |

> **Note**: States `plan_reviewing`, `reviewing`, and `fixing` are deprecated. Reviews now happen within `plan_refining` and `implementing` states using sequential skill invocation.

### Full Flow

```
idle
  ↓
plan_drafting (main thread creates plan)
  ↓
plan_refining (main thread refines + sequential skill reviews)
  │   sonnet → fix → opus → fix → codex
  │          ↑__________________________|  (restart if codex finds issues)
  ↓ [all approved]
implementing (main thread implements + sequential skill reviews)
  │   sonnet → fix → opus → fix → codex
  │          ↑__________________________|  (restart if codex finds issues)
  ↓ [all approved]
complete
```

### State Transitions

| From | To | Trigger |
|------|----|---------|
| `idle` | `plan_drafting` | User sets state with user-request.txt |
| `plan_drafting` | `plan_refining` | Main thread creates initial plan |
| `plan_refining` | `implementing` | All reviewers approve (sonnet → opus → codex) |
| `implementing` | `complete` | All reviewers approve (sonnet → opus → codex) |
| `*` | `error` | Failure after retries |
| `*` | `needs_user_input` | Main thread needs clarification |

---

## Output Formats

### plan.json (Initial plan)
```json
{
  "id": "plan-YYYYMMDD-HHMMSS",
  "title": "Short descriptive title",
  "description": "What the user wants to achieve",
  "requirements": ["req1", "req2"],
  "created_at": "ISO8601",
  "created_by": "claude"
}
```

### plan-refined.json (Refined plan)
```json
{
  "id": "plan-001",
  "title": "Feature title",
  "description": "What the user wants",
  "requirements": ["req 1", "req 2"],
  "technical_approach": "How to implement",
  "files_to_modify": ["path/to/file.ts"],
  "files_to_create": ["path/to/new.ts"],
  "dependencies": [],
  "estimated_complexity": "low|medium|high",
  "potential_challenges": ["challenge 1"],
  "refined_by": "claude",
  "refined_at": "ISO8601"
}
```

### Review outputs (sequential)

Each skill outputs to its own file:

| File | Skill | Model |
|------|-------|-------|
| `.task/review-sonnet.json` | /review-sonnet | sonnet |
| `.task/review-opus.json` | /review-opus | opus |
| `.task/review-codex.json` | /review-codex | codex |

Format:
```json
{
  "status": "approved|needs_changes",
  "review_type": "plan|code",
  "reviewer": "review-sonnet",
  "model": "sonnet",
  "reviewed_at": "ISO8601",
  "summary": "Review summary",
  "issues": [
    {
      "severity": "error|warning|suggestion",
      "category": "code|security|test|plan",
      "file": "path/to/file.ts",
      "line": 42,
      "message": "Issue description",
      "suggestion": "How to fix"
    }
  ]
}
```

### impl-result.json (Implementation result)
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

---

## Orchestrator Safety Features

### Atomic Locking

The orchestrator uses PID-based locking for destructive operations:

- Lock file: `.task/.orchestrator.lock`
- Only used by `reset` command (not `run` or `status`)
- Stale locks (dead PID) are automatically cleaned up

```bash
# If you see "Another orchestrator is running" but it's stale:
rm .task/.orchestrator.lock
```

### Dry-Run Validation

Validate setup before running:

```bash
./scripts/orchestrator.sh dry-run
```

Checks:
- `.task/` directory exists
- `state.json` valid (or will be created)
- `pipeline.config.json` valid
- Required scripts executable (4 scripts)
- Required skills exist (3 review skills)
- Required docs exist
- `.task` in `.gitignore`
- CLI tools available

### Phase-Aware Recovery

The recovery tool respects which phase failed:

- Errors in `plan_drafting` → retry from `plan_drafting`
- Errors in `plan_refining` → retry from `plan_refining`
- Errors in `implementing` → retry from `implementing`

```bash
# Interactive recovery
./scripts/recover.sh

# Check previous state
cat .task/state.json | jq '.previous_state'
```

### Local Config Overrides

Create `pipeline.config.local.json` for local overrides (gitignored):

```json
{
  "autonomy": {
    "planReviewLoopLimit": 5,
    "codeReviewLoopLimit": 10
  }
}
```

---

## Codex Session Resume

Codex reviews use `resume --last` for subsequent reviews to save tokens.

### How It Works

- **First review** (new task): Full prompt with all context
- **Subsequent reviews**: Uses `resume --last` + changes summary

### Session Tracking

Uses `.task/.codex-session-active` marker file:
- Created after first successful Codex call
- Cleared on pipeline reset or new task

---

## Current Sprint Context

Add sprint-specific context here as needed. This section is referenced by the orchestrator when starting new features.

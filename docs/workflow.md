# Pipeline Workflow

## Architecture Overview

This pipeline uses a **subagent-based architecture**:

- **Main Claude Code thread** = Orchestrator only (coordinates work)
- **Subagents** = Do the actual work (planning, coding, reviewing)
- **Codex** = Final review checkpoints only (end of planning, end of implementation)

### Subagents

Located in `.claude/agents/`:

| Subagent | Purpose | Model |
|----------|---------|-------|
| `planner` | Drafts and refines plans | opus |
| `implementer` | Writes code | opus |
| `researcher` | Codebase exploration | opus |
| `code-reviewer-sonnet` | Quick code/plan review | sonnet |
| `code-reviewer-opus` | Deep code/plan review | opus |
| `security-reviewer-sonnet` | Quick security scan | sonnet |
| `security-reviewer-opus` | Deep security analysis | opus |
| `test-reviewer-sonnet` | Quick test coverage check | sonnet |
| `test-reviewer-opus` | Deep test quality review | opus |

> **Dual Review Model**: Internal reviewers run in parallel with both sonnet and opus to get different perspectives. All reviews must approve before proceeding.

---

## Starting a New Task

1. Create `.task/user-request.txt` with your request
2. Set state: `./scripts/state-manager.sh set plan_drafting ""`
3. Run: `./scripts/orchestrator.sh`

---

## Workflow Phases

### Phase 1: Planning

```
plan_drafting
     ↓ (planner subagent creates initial plan)
plan_refining
     ↓ (planner + researcher subagents refine)
     ↓ (code-reviewer subagent internal review)
     ↓ [loop until internally approved]
plan_reviewing
     ↓ (Codex final review)
     ↓ [approved] → implementing
     ↓ [needs_changes] → back to plan_refining
```

**Subagent Flow:**
1. `planner` → Creates initial plan from user request
2. `researcher` → Gathers codebase context
3. `planner` → Refines plan with technical details
4. `code-reviewer` → Internal review (loops until solid)
5. **Codex** → Final plan review (only Codex call in planning phase)

### Phase 2: Implementation

```
implementing
     ↓ (implementer subagent writes code)
     ↓ (code-reviewer + security-reviewer + test-reviewer internal reviews)
     ↓ [loop until internally approved]
reviewing
     ↓ (Codex final review)
     ↓ [approved] → complete
     ↓ [needs_changes] → fixing → reviewing
```

**Subagent Flow:**
1. `implementer` → Writes code following standards
2. `code-reviewer` → Internal code quality check
3. `security-reviewer` → Security assessment
4. `test-reviewer` → Test coverage check
5. **Codex** → Final code review (only Codex call in implementation phase)

---

## Using the Orchestrator

The orchestrator shows the current state and what action to take next:

```bash
./scripts/orchestrator.sh
```

Example output:
```
[INFO] Current state: plan_drafting

ACTION: Invoke 'planner' subagent

Task: Create initial plan from user request
Input: .task/user-request.txt
Output: .task/plan.json

After completion, transition state:
  ./scripts/state-manager.sh set plan_refining "$(jq -r .id .task/plan.json)"
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
| `plan_refining` | Refining plan with technical details |
| `plan_reviewing` | Codex final plan review |
| `implementing` | Writing code |
| `reviewing` | Codex final code review |
| `fixing` | Fixing issues from code review |
| `complete` | Task finished |
| `error` | Pipeline error |
| `needs_user_input` | Waiting for user clarification |

### Full Flow

```
idle
  ↓
plan_drafting (planner subagent)
  ↓
plan_refining (planner + researcher + code-reviewer internal loop)
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

### State Transitions

| From | To | Trigger |
|------|----|---------|
| `idle` | `plan_drafting` | User sets state with user-request.txt |
| `plan_drafting` | `plan_refining` | Planner creates initial plan |
| `plan_refining` | `plan_reviewing` | Both code reviewers approve (sonnet + opus) |
| `plan_reviewing` | `plan_refining` | Codex requests changes |
| `plan_reviewing` | `implementing` | Codex approves → Claude Code runs plan-to-task.sh |
| `implementing` | `reviewing` | All internal reviews approve (6 reviewers) |
| `reviewing` | `complete` | Codex approves |
| `reviewing` | `fixing` | Codex requests changes |
| `reviewing` | `error` | Codex rejects (fundamentally flawed) |
| `fixing` | `reviewing` | Implementer fixes issues |
| `*` | `error` | Failure after retries |
| `*` | `needs_user_input` | Subagent needs clarification |

> **Note**: `rejected` status means the task is fundamentally flawed and cannot be fixed with minor changes. Use `./scripts/recover.sh` to restart with a new approach.

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
  "created_by": "planner"
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
  "refined_by": "planner",
  "refined_at": "ISO8601"
}
```

### Internal review outputs (dual-model)

Each review type runs with both sonnet and opus models in parallel:

| File | Reviewer |
|------|----------|
| `.task/internal-review-sonnet.json` | code-reviewer-sonnet |
| `.task/internal-review-opus.json` | code-reviewer-opus |
| `.task/security-review-sonnet.json` | security-reviewer-sonnet |
| `.task/security-review-opus.json` | security-reviewer-opus |
| `.task/test-review-sonnet.json` | test-reviewer-sonnet |
| `.task/test-review-opus.json` | test-reviewer-opus |

> **Planning phase**: 2 code reviewers must approve (code-reviewer-sonnet + opus).
> **Implementation phase**: All 6 reviewers must approve before proceeding to Codex final review.

Format:
```json
{
  "status": "approved|needs_changes",
  "reviewer": "code-reviewer-sonnet",
  "model": "sonnet",
  "reviewed_at": "ISO8601",
  "summary": "Review summary",
  "issues": [
    {
      "severity": "error|warning|suggestion",
      "file": "path/to/file.ts",
      "line": 42,
      "issue": "Description",
      "suggestion": "How to fix"
    }
  ]
}
```

### plan-review.json (Codex final plan review)
```json
{
  "status": "approved|needs_changes",
  "summary": "Overall assessment",
  "concerns": [
    {
      "severity": "error|warning|suggestion",
      "area": "requirements|approach|complexity|risks|feasibility",
      "message": "Description of concern",
      "suggestion": "How to address"
    }
  ],
  "reviewed_by": "codex",
  "reviewed_at": "ISO8601"
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

### review-result.json (Codex final code review)
Schema enforced via --output-schema.
See docs/schemas/review-result.schema.json

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
./scripts/validate-config.sh  # Strict config validation
./scripts/orchestrator.sh dry-run
```

Checks:
- `.task/` directory exists
- `state.json` valid (or will be created)
- `pipeline.config.json` valid
- Required scripts executable
- Required subagents exist
- Required docs exist
- `.task` in `.gitignore`
- CLI tools available

### Phase-Aware Recovery

The recovery tool respects which phase failed:

- Errors in `plan_drafting` → retry from `plan_drafting`
- Errors in `plan_refining`/`plan_reviewing` → retry from `plan_refining`
- Errors in `implementing`/`reviewing`/`fixing` → retry from `implementing`

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
    "planReviewLoopLimit": 15,
    "codeReviewLoopLimit": 20
  }
}
```

---

## Codex Session Resume

Codex reviews use `resume --last` to carry forward context from previous sessions:

```bash
codex exec resume --last \
  --full-auto \
  --model o3 \
  --output-schema docs/schemas/review-result.schema.json \
  -o .task/review-result.json \
  "Review the implementation..."
```

This reduces token usage by maintaining context across review iterations.

---

## Current Sprint Context

Add sprint-specific context here as needed. This section is referenced by the orchestrator when starting new features.

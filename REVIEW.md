# Migration Review: claude-codex-gemini → claude-codex

## Overview

This document reviews the migration from a 3-AI orchestration system (Gemini + Claude + Codex) to a 2-AI system (Claude + Codex), removing the Gemini dependency due to API quota limitations.

## Architecture Changes

### Before (claude-codex-gemini)
```
Gemini CLI ─── Orchestrator/Coordinator (no code writing)
Claude Code ── Plan Refiner + Implementation Coder
Codex CLI ──── Plan Reviewer + Code Reviewer
```

### After (claude-codex)
```
Claude Code ── Orchestrator + Plan Creator + Plan Refiner + Implementation Coder
Codex CLI ──── Plan Reviewer + Code Reviewer
```

## Key Design Decisions

### 1. Claude Takes Over Orchestration
- **Rationale**: Gemini's orchestration role was primarily coordination and plan creation, which Claude can handle
- **Impact**: Simplified architecture, one less API dependency
- **Trade-off**: Claude now has more responsibilities, but this is acceptable given its capabilities

### 2. Strict Loop-Until-Pass Model
- **Rationale**: User preference for deterministic behavior over debate mechanism
- **Implementation**: `debate.enabled: false` in config
- **Behavior**: Reviews loop until approved or limit reached (no negotiation)

### 3. User Request Entry Point
- **New Workflow**: Users create `.task/user-request.txt` instead of manually creating plan.json
- **Rationale**: Cleaner UX, Claude creates the initial plan from natural language
- **State Flow**: `idle` → `plan_drafting` → `plan_refining` → `plan_reviewing` → ...

### 4. Orchestrator Controls State Transitions
- **Rationale**: Centralized state management prevents race conditions
- **Implementation**: Individual scripts (run-claude-*.sh, run-codex-*.sh) only produce output files; orchestrator.sh handles all state transitions

### 5. Higher Loop Limits
- **Plan Review**: 10 iterations (was 3)
- **Code Review**: 15 iterations (was 5)
- **Rationale**: User wanted more iterations before failure

## Files Changed/Created

### New Files
| File | Purpose |
|------|---------|
| `scripts/run-claude-plan-create.sh` | Creates initial plan from user request |
| `scripts/validate-config.sh` | Strict config validation with proper jq checks |
| `.task/user-request.txt` | Entry point for new features (user creates this) |

### Modified Files
| File | Changes |
|------|---------|
| `scripts/orchestrator.sh` | Added `plan_drafting` state handling, removed Gemini CLI check, removed debate handling |
| `scripts/state-manager.sh` | `init_state()` now creates full schema |
| `pipeline.config.json` | All models use Claude, debate disabled, higher loop limits |
| `CLAUDE.md` | Updated for orchestrator role, clarified state management |
| `README.md` | Updated workflow, removed Gemini references |
| `.gitignore` | Changed to `.task/*` pattern to allow negations |

### Removed Files
| File | Reason |
|------|--------|
| `GEMINI.md` | No longer needed |
| `scripts/run-gemini-*.sh` | No longer needed |

## Configuration Schema

```json
{
  "version": "1.0.0",
  "autonomy": {
    "mode": "semi-autonomous",
    "approvalPoints": {...},
    "autoCommit": false,
    "maxAutoRetries": 3,
    "reviewLoopLimit": 10,
    "planReviewLoopLimit": 10,
    "codeReviewLoopLimit": 15
  },
  "models": {
    "orchestrator": { "provider": "claude", "model": "claude-opus-4.5", "temperature": 0.7 },
    "coder": { "provider": "claude", "model": "claude-opus-4.5", "temperature": 0.3 },
    "reviewer": { "provider": "openai", "model": "gpt-5.2-codex", "reasoning": "high", "temperature": 0.2 }
  },
  "debate": { "enabled": false, "maxRounds": 0, "timeoutSeconds": 0 },
  ...
}
```

## State Machine

```
idle
  ↓ (user creates user-request.txt, sets state to plan_drafting)
plan_drafting
  ↓ (Claude creates plan.json)
plan_refining
  ↓ (Claude refines to plan-refined.json)
plan_reviewing
  ↓ (Codex reviews)
  ├── needs_changes → plan_refining (loop, max 10)
  └── approved → implementing (auto-converts plan to task)
implementing
  ↓ (Claude implements)
reviewing
  ↓ (Codex reviews code)
  ├── needs_changes → fixing → reviewing (loop, max 15)
  └── approved → complete (or committing if autoCommit)
complete
```

## Scripts Inventory (10 total)

| Script | Role | Invoked By |
|--------|------|------------|
| `orchestrator.sh` | Main loop, state machine | User |
| `state-manager.sh` | State read/write utilities | All scripts |
| `run-claude-plan-create.sh` | Create initial plan | Orchestrator |
| `run-claude-plan.sh` | Refine plan | Orchestrator |
| `run-claude.sh` | Implement/fix code | Orchestrator |
| `run-codex-plan-review.sh` | Review plan | Orchestrator |
| `run-codex-review.sh` | Review code | Orchestrator |
| `plan-to-task.sh` | Convert approved plan to task | Orchestrator |
| `recover.sh` | Interactive recovery tool | User |
| `validate-config.sh` | Strict config validation | Orchestrator (dry-run) |

## Validation Results

```
$ ./scripts/orchestrator.sh dry-run
Task directory: OK
State file: OK (status: idle)
Config file: OK
Scripts: OK (10 scripts)
docs/standards.md: OK
docs/workflow.md: OK
.gitignore (.task): OK
CLI jq: OK
CLI claude: OK
CLI codex: OK
Dry run: PASSED

$ ./scripts/validate-config.sh
Validating pipeline.config.json...
Config validation: PASSED
```

## Risk Assessment

### Low Risk
- State machine logic is well-tested pattern
- JSON schema validation ensures consistent output
- Recovery script provides escape hatch for stuck states

### Medium Risk
- Claude handling more responsibilities could increase token usage
- Higher loop limits (10/15) could lead to longer runs on difficult tasks

### Mitigations
- Config is easily adjustable for loop limits
- `semi-autonomous` mode requires manual commit approval
- Error state preserves `previous_state` for intelligent recovery

## Usage Quick Reference

```bash
# Start fresh
echo "Your feature description" > .task/user-request.txt
./scripts/state-manager.sh set plan_drafting ""
./scripts/orchestrator.sh

# Check status
./scripts/orchestrator.sh status

# Recover from errors
./scripts/recover.sh

# Validate setup
./scripts/orchestrator.sh dry-run
./scripts/validate-config.sh
```

## Post-Migration Bug Fixes

### Fix 1: plan_drafting Recovery (High Priority)

**Issue**: When `plan_drafting` failed, the error recovery would retry from `plan_refining`, which fails because `plan.json` doesn't exist yet. This could strand the pipeline in an error/retry loop.

**Fix**:
- `orchestrator.sh`: Added special case in `handle_error()` to detect `plan_drafting` as `previous_state` and retry from `plan_drafting` instead of `plan_refining`
- `recover.sh`: Added `plan_drafting` case to retry from plan creation

**Files Changed**:
- `scripts/orchestrator.sh:362-389`
- `scripts/recover.sh:57-60`

### Fix 2: Workflow Documentation (Low Priority)

**Issue**: `docs/workflow.md` state transition table showed `reviewing → fixing` on "Codex rejects", but the code actually sends `rejected` to `error` state. Only `needs_changes` goes to `fixing`.

**Fix**: Updated state transition table to correctly document:
- `reviewing` → `fixing` on `needs_changes`
- `reviewing` → `error` on `rejected`

**Files Changed**:
- `docs/workflow.md:178-179, 191-193, 235`

### Fix 3: README Validation Claims (Low Priority)

**Issue**: README claimed `dry-run` validates "pipeline.config.json validity (all required keys)", but dry-run only checks JSON syntax. Required-key validation is in `validate-config.sh`.

**Fix**: Updated README to clearly distinguish:
- `dry-run`: Basic validation (JSON syntax, scripts, docs, CLI tools)
- `validate-config.sh`: Strict config validation (all required keys, types)

**Files Changed**:
- `README.md:270-293`

## Conclusion

The migration successfully removes the Gemini dependency while preserving all functionality. The system is simpler (2 AI agents vs 3), more deterministic (strict loop-until-pass), and provides a cleaner entry point via `user-request.txt`. All validation checks pass.

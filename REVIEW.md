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

---

## Fix 4: Interactive Mode Blocking Issue (High Priority)

### Problem

When running `./scripts/orchestrator.sh` in interactive mode, Claude Code would execute:
```bash
./scripts/state-manager.sh set reviewing "" && ./scripts/orchestrator.sh 2>&1
```

The orchestrator would **block indefinitely** waiting for output files to be created, preventing Claude Code from doing anything. The scripts had a `while` loop waiting for files that would never be created because Claude Code was stuck waiting for the bash command to complete.

### Root Cause

The `run-claude*.sh` scripts in interactive mode would:
1. Output the task prompt
2. **Block in a loop** waiting for the output file to be created
3. Never exit until someone else created the file

This created a deadlock: Claude Code couldn't execute the task because it was waiting for the bash command to finish, and the bash command wouldn't finish until the task was executed.

### Solution

#### 1. Non-blocking Claude Scripts

Changed `run-claude.sh`, `run-claude-plan.sh`, and `run-claude-plan-create.sh` to:
- Output the task with clear formatting
- Exit immediately with code 100 (signaling "task pending for Claude Code")
- NOT wait in a blocking loop

**Before:**
```bash
if [[ "${CLAUDE_INTERACTIVE:-}" == "1" ]]; then
  echo "$PROMPT"
  rm -f .task/impl-result.json
  while [[ ! -f .task/impl-result.json ]]; do  # BLOCKS FOREVER
    sleep 2
  done
  exit 0
fi
```

**After:**
```bash
if [[ "${CLAUDE_INTERACTIVE:-}" == "1" ]]; then
  echo "═══════════════════════════════════════════════════════════════"
  echo "  CLAUDE TASK: Implementation"
  echo "═══════════════════════════════════════════════════════════════"
  echo "$PROMPT"
  echo "═══════════════════════════════════════════════════════════════"
  echo "  OUTPUT REQUIRED: .task/impl-result.json"
  echo "  THEN RUN: ./scripts/orchestrator.sh"
  echo "═══════════════════════════════════════════════════════════════"
  rm -f .task/impl-result.json
  exit 100  # EXIT IMMEDIATELY
fi
```

#### 2. Orchestrator Handles Exit Code 100

Updated `orchestrator.sh` to detect exit code 100 and exit gracefully:

```bash
run_implementation
result=$?
if [[ $result -eq 100 ]]; then
  log_info "Task output above. Execute it, then run: ./scripts/orchestrator.sh"
  exit 0  # Let Claude Code take over
elif [[ $result -ne 0 ]]; then
  set_state "error" "$(get_task_id)"
fi
```

#### 3. Updated Documentation

- **CLAUDE.md**: Added "Interactive Mode: How It Works" section with step-by-step instructions
- **README.md**: Updated interactive mode description
- **docs/workflow.md**: Updated interactive mode description

### New Interactive Flow

```
1. User runs: ./scripts/orchestrator.sh
2. Orchestrator outputs Claude task and exits
3. Claude Code reads the task, executes it, writes output file
4. Claude Code runs: ./scripts/orchestrator.sh
5. Orchestrator checks output, runs Codex review (subprocess), continues
6. Repeat until complete
```

### Files Changed

| File | Change |
|------|--------|
| `scripts/run-claude.sh` | Exit immediately with code 100 in interactive mode |
| `scripts/run-claude-plan.sh` | Exit immediately with code 100 in interactive mode |
| `scripts/run-claude-plan-create.sh` | Exit immediately with code 100 in interactive mode |
| `scripts/orchestrator.sh` | Handle exit code 100, exit gracefully for Claude Code |
| `CLAUDE.md` | Added interactive mode workflow documentation |
| `README.md` | Updated interactive mode description |
| `docs/workflow.md` | Updated interactive mode description |

### Testing

To test the fix:

1. Create a user request:
   ```bash
   echo "Add a hello world function" > .task/user-request.txt
   ```

2. Start the pipeline:
   ```bash
   ./scripts/state-manager.sh set plan_drafting ""
   ./scripts/orchestrator.sh
   ```

3. Verify the orchestrator:
   - Outputs the task clearly
   - Exits immediately (doesn't block)
   - Shows "THEN RUN: ./scripts/orchestrator.sh"

4. Execute the task and write the output file

5. Run `./scripts/orchestrator.sh` again to continue

### Backward Compatibility

- **Headless mode** (`./scripts/orchestrator.sh headless`) is unchanged
- Exit code 100 is only used in interactive mode
- Codex scripts are unchanged (they still run as subprocesses)

---

## Fix 5: Interactive Mode File Handling (High Priority)

### Problem 1: Output File Deletion Loop

When Claude Code writes an output file and reruns the orchestrator, the orchestrator calls the Claude script again, which **deletes the output file** before checking if it exists. This creates an infinite loop where the file is always deleted before it can be consumed.

### Problem 2: `set -e` Aborts on Exit Code 100

With `set -e` at the top of `orchestrator.sh`, running a script that exits with code 100 causes the entire orchestrator to abort before the exit code handling logic runs.

### Solution

#### 1. Orchestrator Checks for Existing Output First

Before calling any Claude script, the orchestrator now checks if the output file already exists and is valid JSON. If so, it skips calling the script and proceeds with the result:

```bash
# Check if output already exists (from previous interactive mode run)
if [[ -f .task/plan.json ]] && jq empty .task/plan.json 2>/dev/null; then
  log_info "Plan already exists, proceeding..."
  # ... process the existing file
  return 0
fi
```

#### 2. Disable `set -e` Around Script Calls

Before calling Claude scripts, temporarily disable `set -e` to capture the exit code:

```bash
# Disable set -e to capture exit code
set +e
"$SCRIPT_DIR/run-claude-plan-create.sh" "$user_request"
local exit_code=$?
set -e

# Now handle exit code properly
if [[ $exit_code -eq 100 ]]; then
  return 100
# ...
```

#### 3. Remove File Deletion from Scripts

Removed the `rm -f` commands from the interactive mode blocks in all Claude scripts, since the orchestrator now handles file existence checking:

```bash
# Before:
rm -f .task/impl-result.json  # DELETED

# After:
# Note: Do NOT delete output file - orchestrator checks for it on rerun
exit 100
```

### Files Changed

| File | Change |
|------|--------|
| `scripts/orchestrator.sh` | Check for existing output files before calling scripts; use `set +e`/`set -e` around script calls |
| `scripts/run-claude.sh` | Removed `rm -f .task/impl-result.json` |
| `scripts/run-claude-plan.sh` | Removed `rm -f .task/plan-refined.json` |
| `scripts/run-claude-plan-create.sh` | Removed `rm -f .task/plan.json` |

### New Flow (Initial Attempt - Had Issues)

```
1. User runs: ./scripts/orchestrator.sh
2. Orchestrator checks: does .task/plan.json exist?
   - NO: Call run-claude-plan-create.sh → outputs task, exits 100
         Orchestrator detects 100, prints instructions, exits 0
   - YES: Skip script, use existing file, proceed to next phase
3. Claude Code executes task, writes .task/plan.json
4. Claude Code runs: ./scripts/orchestrator.sh
5. Orchestrator checks: .task/plan.json exists → proceeds to plan_refining
6. Repeat for each phase
```

---

## Fix 6: Awaiting Output State Flag (Critical - Final Solution)

### Problem 1: `set -e` Still Aborting in main_loop

Even with `set +e` around individual script calls, the `run_*` functions return non-zero on errors, which triggers `set -e` abort before the main_loop case handling runs.

### Problem 2: File Existence Check Causes Infinite Loop

The simple "file exists" check from Fix 5 caused a critical bug: when Codex returns `needs_changes`, the orchestrator loops back to `plan_refining`, but the file already exists from the previous iteration. The check would skip calling the Claude script, meaning no updates would be applied - creating an infinite loop without progress.

### Solution

#### 1. Move `set +e` to main_loop Level

Instead of wrapping each script call, disable `set -e` for the entire main loop:

```bash
# Main orchestration loop
main_loop() {
  # Disable set -e for the loop since we handle exit codes manually
  set +e

  while true; do
    # ... all case handling
  done
}
```

#### 2. Add `awaiting_output` State Flag

Added new functions to `state-manager.sh`:

```bash
# Set awaiting_output flag (for interactive mode)
set_awaiting_output() {
  local output_file="$1"
  jq --arg f "$output_file" \
    '.awaiting_output = $f | .updated_at = (now | todate)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}

# Get awaiting_output flag
get_awaiting_output() {
  jq -r '.awaiting_output // empty' "$STATE_FILE"
}

# Clear awaiting_output flag (after output received)
clear_awaiting_output() {
  jq 'del(.awaiting_output) | .updated_at = (now | todate)' \
    "$STATE_FILE" > "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "$STATE_FILE"
}
```

#### 3. Update All run_* Functions

Changed from simple file existence check to `awaiting_output` flag check:

**Before (Fix 5):**
```bash
if [[ -f .task/plan.json ]] && jq empty .task/plan.json 2>/dev/null; then
  log_info "Plan already exists, proceeding..."
  # ... short-circuit to next phase
fi
```

**After (Fix 6):**
```bash
local awaiting
awaiting=$(get_awaiting_output)
if [[ "$awaiting" == ".task/plan.json" ]] && [[ -f .task/plan.json ]] && jq empty .task/plan.json 2>/dev/null; then
  log_info "Resuming: plan.json received from Claude Code"
  clear_awaiting_output
  # ... proceed to next phase
fi
```

#### 4. Set Flag on Exit 100

In main_loop, set the flag before exiting:

```bash
run_plan_creation
result=$?
if [[ $result -eq 100 ]]; then
  set_awaiting_output ".task/plan.json"
  log_info "Task output above. Execute it, then run: ./scripts/orchestrator.sh"
  exit 0
elif [[ $result -ne 0 ]]; then
  set_state "error" ""
fi
```

### Why This Works

The `awaiting_output` flag distinguishes between two scenarios:

1. **Resuming after Claude Code wrote a file** (flag is set): Skip script call, consume the file
2. **New iteration after review feedback** (flag is NOT set): Call script to apply changes

This prevents the infinite loop because:
- On exit 100, the flag is set to the expected output file
- When Claude Code writes the file and reruns orchestrator, the flag matches → consume file, clear flag
- When Codex returns `needs_changes`, state transitions to `plan_refining` WITHOUT setting flag
- Orchestrator calls the script because flag doesn't match → Claude applies review feedback

### Files Changed

| File | Change |
|------|--------|
| `scripts/state-manager.sh` | Added `set_awaiting_output`, `get_awaiting_output`, `clear_awaiting_output` functions |
| `scripts/orchestrator.sh` | Moved `set +e` to main_loop; updated all run_* functions to use awaiting_output flag; set flag on exit 100 |

### Corrected Flow

```
1. User runs: ./scripts/orchestrator.sh
2. State: plan_drafting
   - awaiting_output is empty
   - Call run-claude-plan-create.sh → outputs task, exits 100
   - Set awaiting_output = ".task/plan.json"
   - Exit 0

3. Claude Code executes task, writes .task/plan.json
4. Claude Code runs: ./scripts/orchestrator.sh

5. State: plan_drafting (unchanged)
   - awaiting_output = ".task/plan.json" ← matches!
   - File exists and valid JSON → consume file, clear flag
   - Transition to plan_refining

6. State: plan_refining
   - awaiting_output is empty (was cleared)
   - Call run-claude-plan.sh → outputs task, exits 100
   - Set awaiting_output = ".task/plan-refined.json"
   - Exit 0

... (similar pattern for each phase)

N. Codex returns needs_changes:
   - Transition to plan_refining
   - awaiting_output is NOT set (Codex didn't set it)
   - Call run-claude-plan.sh → Claude applies review feedback
   - Claude writes updated plan-refined.json, exits 100
   - Set awaiting_output, exit 0
   - On next run, consume updated file, proceed to plan_reviewing
```

---

## Fix 7: Clear awaiting_output in Recovery/Reset Flows

### Problem

The `awaiting_output` flag persists through recovery and reset flows. If a user:
1. Runs orchestrator → Claude script outputs task, sets `awaiting_output`, exits
2. Writes the output file manually
3. Uses `./scripts/recover.sh` or `./scripts/orchestrator.sh reset` instead of rerunning orchestrator

The stale flag + existing output file would cause the next run to "resume" and skip re-running Claude, even though the user intended to start fresh.

### Solution

Clear `awaiting_output` in all recovery and reset paths:

```bash
# In recover.sh reset_to_idle()
set_state "idle" ""
clear_awaiting_output  # NEW
rm -f .task/impl-result.json .task/review-result.json

# In recover.sh retry_current()
# Clear any stale awaiting_output flag from previous interactive run
clear_awaiting_output  # NEW (at start of function)

# In orchestrator.sh reset command
set_state "idle" ""
clear_awaiting_output  # NEW
rm -f .task/impl-result.json ...
```

Also added `rm -f .task/plan.json` to the `plan_drafting` retry case in `recover.sh` to ensure a clean retry.

### Files Changed

| File | Change |
|------|--------|
| `scripts/recover.sh` | Added `clear_awaiting_output` to `reset_to_idle()` and `retry_current()` |
| `scripts/orchestrator.sh` | Added `clear_awaiting_output` to reset command |
| `.task/state.json` | Reset to clean state (updated_at: null) |

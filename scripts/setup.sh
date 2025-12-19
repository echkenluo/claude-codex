#!/bin/bash
# Setup script for multi-AI pipeline
# Detects global CLAUDE.md conflicts and configures workflow preferences

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

GLOBAL_CLAUDE_MD="$HOME/.claude/CLAUDE.md"
PREFERENCES_FILE=".task/preferences.json"

# Check for global CLAUDE.md
check_global_claude_md() {
  if [[ -f "$GLOBAL_CLAUDE_MD" ]]; then
    echo -e "${YELLOW}⚠ Detected global CLAUDE.md at:${NC}"
    echo -e "  $GLOBAL_CLAUDE_MD"
    echo ""
    echo -e "${CYAN}This project uses a multi-AI orchestrator workflow (Claude + Codex)${NC}"
    echo -e "${CYAN}which differs from the standard PLAN.md workflow.${NC}"
    echo ""
    echo -e "Your global CLAUDE.md may instruct Claude Code to use a different"
    echo -e "workflow (like PLAN.md), which could conflict with this project."
    echo ""
    return 0  # Found
  else
    echo -e "${GREEN}✓ No global CLAUDE.md detected${NC}"
    echo ""
    return 1  # Not found
  fi
}

# Get existing preference
get_existing_preference() {
  if [[ -f "$PREFERENCES_FILE" ]]; then
    jq -r '.workflow_mode // empty' "$PREFERENCES_FILE" 2>/dev/null
  fi
}

# Save preference
save_preference() {
  local mode="$1"
  mkdir -p .task

  if [[ -f "$PREFERENCES_FILE" ]]; then
    jq --arg mode "$mode" '.workflow_mode = $mode | .configured_at = (now | todate)' \
      "$PREFERENCES_FILE" > "$PREFERENCES_FILE.tmp"
    mv "$PREFERENCES_FILE.tmp" "$PREFERENCES_FILE"
  else
    cat > "$PREFERENCES_FILE" << EOF
{
  "workflow_mode": "$mode",
  "configured_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
  fi
}

# Update CLAUDE.md based on preference
update_claude_md() {
  local mode="$1"

  case "$mode" in
    orchestrator)
      cat > "$PROJECT_ROOT/CLAUDE.md" << 'CLAUDE_EOF'
# Claude Code - Multi-AI Pipeline Project

> **IMPORTANT**: This project uses a multi-AI orchestrator workflow, NOT the standard PLAN.md workflow. These instructions override any global CLAUDE.md settings for this project.

## When User Asks to Implement Something

If a user directly asks you to implement a feature or make changes in this project, guide them to use the orchestrator workflow:

```
This project uses a multi-AI orchestrator (Claude + Codex) for implementations.

To implement your request:

1. Create your request:
   echo "Your feature description here" > .task/user-request.txt

2. Start the pipeline:
   ./scripts/state-manager.sh set plan_drafting ""
   ./scripts/orchestrator.sh

The pipeline will:
- Create and refine a plan (Claude)
- Review the plan (Codex) - loops until approved
- Implement the code (Claude)
- Review the code (Codex) - loops until approved

For quick status: ./scripts/orchestrator.sh status
For recovery: ./scripts/recover.sh
```

Do NOT use the PLAN.md workflow for this project. The orchestrator handles planning, implementation, and review automatically.

---

## Agent Instructions (When Invoked by Orchestrator)

You are the **implementation agent** in a two-AI development pipeline.

## Your Three Roles

### Role 1: Plan Creator
When invoked via `run-claude-plan-create.sh`:
- Read user request from script argument
- Create initial plan in `.task/plan.json`
- Exit (orchestrator handles state transition)

### Role 2: Plan Refiner
When invoked via `run-claude-plan.sh` (state is `plan_refining`):
- Read initial plan from `.task/plan.json`
- Read any previous review feedback from `.task/plan-review.json`
- Add technical details
- Write to `.task/plan-refined.json`
- Exit (orchestrator handles state transition)

### Role 3: Code Implementer
When invoked via `run-claude.sh` (state is `implementing` or `fixing`):
- Read task from `.task/current-task.json`
- Read any previous review feedback from `.task/review-result.json`
- Implement following standards
- Write to `.task/impl-result.json`
- Exit (orchestrator handles state transition)

## Important: Orchestrator Controls State
- You do NOT modify `.task/state.json`
- The orchestrator script handles all state transitions
- Your job is to complete the task and write output files

## Shared Knowledge
Read these docs before any work:
- `docs/standards.md` - Coding standards and review criteria
- `docs/workflow.md` - Pipeline process and output formats

## Strict Loop-Until-Pass Model
- Reviews loop until Codex approves
- No debate mechanism - accept all review feedback
- Fix ALL issues raised by reviewer
- Loop limits: planReviewLoopLimit (10), codeReviewLoopLimit (15)

## Pipeline Integration

### Plan Creation Output
Write to: `.task/plan.json`

Format:
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

### Plan Refinement Output
Write to: `.task/plan-refined.json`

Format:
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
  "refined_by": "claude",
  "refined_at": "ISO8601"
}
```

### Implementation Output
Write to: `.task/impl-result.json`

Format:
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

## Handling Review Feedback

### On Plan Review Feedback
If invoked after plan review feedback:
1. Read `.task/plan-review.json`
2. Address ALL concerns raised by Codex
3. Update `.task/plan-refined.json` with improvements

### On Code Review Feedback
If invoked after code review feedback:
1. Read `.task/review-result.json`
2. Address ALL `error` severity issues
3. Address ALL `warning` severity issues
4. Consider `suggestion` severity issues

## Asking for Clarification

If the plan or task is too ambiguous, add to your output:
```json
{
  "needs_clarification": true,
  "questions": [
    "Question 1 for the user?",
    "Question 2 for the user?"
  ]
}
```

Only use this for truly blocking questions.
CLAUDE_EOF
      ;;

    hybrid)
      cat > "$PROJECT_ROOT/CLAUDE.md" << 'CLAUDE_EOF'
# Claude Code - Multi-AI Pipeline Project (Hybrid Mode)

This project supports two workflows. Choose based on task complexity:

## Quick Tasks → Use Your Normal Workflow
For simple changes, bug fixes, or small features, you can use your normal workflow (e.g., PLAN.md if configured globally).

## Complex Tasks → Use the Orchestrator
For larger features requiring multiple review cycles, use the multi-AI orchestrator:

```bash
# 1. Create your request
echo "Your feature description" > .task/user-request.txt

# 2. Run the pipeline
./scripts/state-manager.sh set plan_drafting ""
./scripts/orchestrator.sh
```

The orchestrator provides:
- Automated plan review (Codex reviews Claude's plan)
- Automated code review (Codex reviews Claude's implementation)
- Loop-until-approved workflow (max 10 plan reviews, 15 code reviews)

---

## Agent Instructions (When Invoked by Orchestrator)

You are the **implementation agent** in a two-AI development pipeline.

## Your Three Roles

### Role 1: Plan Creator
When invoked via `run-claude-plan-create.sh`:
- Read user request from script argument
- Create initial plan in `.task/plan.json`
- Exit (orchestrator handles state transition)

### Role 2: Plan Refiner
When invoked via `run-claude-plan.sh` (state is `plan_refining`):
- Read initial plan from `.task/plan.json`
- Read any previous review feedback from `.task/plan-review.json`
- Add technical details
- Write to `.task/plan-refined.json`
- Exit (orchestrator handles state transition)

### Role 3: Code Implementer
When invoked via `run-claude.sh` (state is `implementing` or `fixing`):
- Read task from `.task/current-task.json`
- Read any previous review feedback from `.task/review-result.json`
- Implement following standards
- Write to `.task/impl-result.json`
- Exit (orchestrator handles state transition)

## Important: Orchestrator Controls State
- You do NOT modify `.task/state.json`
- The orchestrator script handles all state transitions
- Your job is to complete the task and write output files

## Shared Knowledge
Read these docs before any work:
- `docs/standards.md` - Coding standards and review criteria
- `docs/workflow.md` - Pipeline process and output formats

## Strict Loop-Until-Pass Model
- Reviews loop until Codex approves
- No debate mechanism - accept all review feedback
- Fix ALL issues raised by reviewer
- Loop limits: planReviewLoopLimit (10), codeReviewLoopLimit (15)

## Pipeline Integration

### Plan Creation Output
Write to: `.task/plan.json`

Format:
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

### Plan Refinement Output
Write to: `.task/plan-refined.json`

Format:
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
  "refined_by": "claude",
  "refined_at": "ISO8601"
}
```

### Implementation Output
Write to: `.task/impl-result.json`

Format:
```json
{
  "status": "completed|failed|needs_clarification",
  "summary": "What was implemented",
  "files_changed": ["path/to/file.ts"],
  "tests_added": ["path/to/test.ts"],
  "questions": []
}
```

## Handling Review Feedback

### On Plan Review Feedback
If invoked after plan review feedback:
1. Read `.task/plan-review.json`
2. Address ALL concerns raised by Codex
3. Update `.task/plan-refined.json` with improvements

### On Code Review Feedback
If invoked after code review feedback:
1. Read `.task/review-result.json`
2. Address ALL `error` severity issues
3. Address ALL `warning` severity issues
4. Consider `suggestion` severity issues

## Asking for Clarification

If the plan or task is too ambiguous, add to your output:
```json
{
  "needs_clarification": true,
  "questions": [
    "Question 1 for the user?",
    "Question 2 for the user?"
  ]
}
```

Only use this for truly blocking questions.
CLAUDE_EOF
      ;;
  esac

  echo -e "${GREEN}✓ Updated CLAUDE.md for $mode mode${NC}"
}

# Show current preference
show_current_preference() {
  local current
  current=$(get_existing_preference)

  if [[ -n "$current" ]]; then
    echo -e "${BLUE}Current workflow mode: ${BOLD}$current${NC}"
    echo ""
  fi
}

# Main setup flow
main() {
  show_current_preference

  if check_global_claude_md; then
    echo -e "${BOLD}How would you like to handle this?${NC}"
    echo ""
    echo "  1) ${BOLD}Orchestrator Only${NC} (Recommended)"
    echo "     Force all implementations to use the multi-AI pipeline."
    echo "     Claude will guide users to use the orchestrator workflow."
    echo ""
    echo "  2) ${BOLD}Hybrid Mode${NC}"
    echo "     Allow both workflows - use your normal workflow for quick tasks,"
    echo "     orchestrator for complex tasks requiring multiple reviews."
    echo ""
    echo "  3) ${BOLD}Skip${NC}"
    echo "     Keep current settings, don't change anything."
    echo ""

    read -p "Select option (1-3): " choice

    case "$choice" in
      1)
        save_preference "orchestrator"
        update_claude_md "orchestrator"
        echo ""
        echo -e "${GREEN}✓ Configured for orchestrator-only mode${NC}"
        echo -e "  Claude will guide users to use the orchestrator workflow."
        ;;
      2)
        save_preference "hybrid"
        update_claude_md "hybrid"
        echo ""
        echo -e "${GREEN}✓ Configured for hybrid mode${NC}"
        echo -e "  Users can choose between normal workflow and orchestrator."
        ;;
      3)
        echo ""
        echo -e "${YELLOW}Skipped - no changes made${NC}"
        ;;
      *)
        echo -e "${RED}Invalid option${NC}"
        exit 1
        ;;
    esac
  else
    echo -e "No global CLAUDE.md conflict detected."
    echo -e "The orchestrator workflow will be used by default."
    echo ""

    # Still save preference for consistency
    if [[ -z "$(get_existing_preference)" ]]; then
      save_preference "orchestrator"
      echo -e "${GREEN}✓ Default preference saved: orchestrator${NC}"
    fi
  fi

  echo ""
  echo -e "${BOLD}Next steps:${NC}"
  echo "  1. Run: ./scripts/state-manager.sh init"
  echo "  2. Run: ./scripts/orchestrator.sh dry-run"
  echo "  3. Run: ./scripts/validate-config.sh"
  echo ""
}

# Show header (only for interactive modes)
show_header() {
  echo ""
  echo -e "${BOLD}=========================================${NC}"
  echo -e "${BOLD}   Multi-AI Pipeline Setup${NC}"
  echo -e "${BOLD}=========================================${NC}"
  echo ""
}

# Entry point
case "${1:-}" in
  --check)
    # Silent check mode - just detect and report (no header)
    if [[ -f "$GLOBAL_CLAUDE_MD" ]]; then
      echo "global_claude_md=true"
      echo "path=$GLOBAL_CLAUDE_MD"
    else
      echo "global_claude_md=false"
    fi

    current=$(get_existing_preference)
    if [[ -n "$current" ]]; then
      echo "workflow_mode=$current"
    else
      echo "workflow_mode=not_configured"
    fi
    ;;
  --reconfigure)
    # Force reconfiguration
    show_header
    main
    ;;
  *)
    # Normal interactive setup
    show_header
    main
    ;;
esac

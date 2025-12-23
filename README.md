# Multi-AI Orchestration Pipeline

A development pipeline that orchestrates multiple AI agents to plan, implement, review, and iterate on code changes.

## Recommended Subscriptions

| Service | Subscription | Purpose |
|---------|--------------|---------|
| **Claude Code** | MAX 20 | Orchestrator + Subagents (planning, coding, internal reviews) |
| **Codex CLI** | Plus | Final reviews only (end of planning, end of implementation) |

> **Note**: This architecture minimizes Codex usage by using Claude subagents for internal review loops, calling Codex only at key checkpoints.

## Architecture

- **Claude Code (Main Thread)** - Orchestrator only, coordinates subagents
- **Claude Subagents** - Specialized agents for planning, implementing, code review, security review, test review
- **Codex CLI** - Final plan review + Final code review (2 calls per feature)

> **Interested in running 3 AIs?** Check out [claude-codex-gemini](https://github.com/Z-M-Huang/claude-codex-gemini) which adds Gemini as a dedicated orchestrator.

## How It Works

Claude Code (main thread) orchestrates the workflow based on `./scripts/orchestrator.sh` instructions.

### Phase 1: Planning

```
User Request → planner (opus) → researcher (opus)
                                       ↓
              code-reviewer-sonnet + code-reviewer-opus (parallel)
                        ↑              ↓
                        └── loop until both approve
                                       ↓
                        Codex (FINAL plan review)
                                       ↓
              Claude Code runs plan-to-task.sh → implementing
```

### Phase 2: Implementation

```
Task → implementer (opus)
              ↓
   6 internal reviewers in parallel:
   - code-reviewer-sonnet + code-reviewer-opus
   - security-reviewer-sonnet + security-reviewer-opus
   - test-reviewer-sonnet + test-reviewer-opus
              ↑              ↓
              └── loop until all 6 approve
                             ↓
              Codex (FINAL code review)
                             ↓
                        complete
```

1. User creates `.task/user-request.txt` with feature description
2. User sets state to `plan_drafting` and runs orchestrator
3. Claude Code invokes **planner** subagent → creates `plan.json`
4. Claude Code invokes **planner + researcher** → refines plan
5. Claude Code invokes **code-reviewer-sonnet + opus** in parallel (both must approve)
6. Claude Code runs **Codex final plan review**
7. If needs changes, back to step 4 (max 10 iterations)
8. Claude Code runs **plan-to-task.sh** → converts to task
9. Claude Code invokes **implementer** subagent
10. Claude Code invokes **6 internal reviewers** in parallel (all must approve)
11. Claude Code runs **Codex final code review**
12. If needs changes, back to step 9 (max 15 iterations)
13. Complete

## Prerequisites

- [Claude Code](https://claude.ai/code) installed and authenticated
- [Codex CLI](https://github.com/openai/codex) installed and authenticated
- `jq` for JSON processing

## Quick Start

### Option A: Use as Template (New Projects)

1. **Clone/copy this repository:**

   ```bash
   git clone https://github.com/Z-M-Huang/claude-codex.git my-project
   cd my-project
   rm -rf .git
   git init
   ```

2. **Customize for your project:**

   ```bash
   # Edit standards to match your project
   vim docs/standards.md

   # Update workflow documentation
   vim docs/workflow.md

   # Configure models and autonomy level
   vim pipeline.config.json
   ```

3. **Run setup (detects workflow conflicts):**

   ```bash
   ./scripts/setup.sh
   ```

   This checks for global `~/.claude/CLAUDE.md` that might conflict with the orchestrator workflow and lets you choose:
   - **Orchestrator Only**: Force all implementations through the multi-AI pipeline
   - **Hybrid Mode**: Allow both your normal workflow and the orchestrator

4. **Initialize the pipeline:**

   ```bash
   ./scripts/state-manager.sh init

   # Tell git to ignore local changes to state files
   git update-index --skip-worktree .task/state.json .task/tasks.json
   ```

5. **Create a user request:**

   ```bash
   cat > .task/user-request.txt << 'EOF'
   Add user authentication with JWT tokens.
   - POST /api/login endpoint
   - POST /api/logout endpoint
   - JWT token validation middleware
   - Unit tests for auth functions
   EOF
   ```

6. **Run the planning phase:**

   ```bash
   ./scripts/state-manager.sh set plan_drafting ""
   ./scripts/orchestrator.sh
   # Orchestrator shows current state and next action
   # You invoke subagents via Task tool, then transition state
   # Repeat until pipeline completes
   ```

7. **Check status anytime:**
   ```bash
   ./scripts/orchestrator.sh status
   ```

### Option B: Adopt for Existing Projects

1. **Copy the pipeline files to your project:**

   ```bash
   # From the claude-codex directory
   cp -r scripts/ /path/to/your/project/
   cp -r docs/ /path/to/your/project/
   cp -r .claude/ /path/to/your/project/    # Subagents (required)
   cp pipeline.config.json /path/to/your/project/
   cp CLAUDE.md AGENTS.md /path/to/your/project/
   mkdir -p /path/to/your/project/.task
   ```

2. **Add to .gitignore:**

   ```bash
   echo ".task/*" >> /path/to/your/project/.gitignore
   echo "!.task/state.json" >> /path/to/your/project/.gitignore
   echo "!.task/tasks.json" >> /path/to/your/project/.gitignore
   ```

3. **Customize docs/standards.md for your project:**

   Update the coding standards to match your existing conventions:

   - Naming conventions (files, classes, functions)
   - Code style rules
   - Testing requirements
   - Security requirements

4. **Update the agent config files:**

   Edit `CLAUDE.md` and `AGENTS.md` to reference your project-specific context.

5. **Configure the pipeline:**

   The provided `pipeline.config.json` works out of the box. Customize as needed:

   ```json
   {
     "version": "1.0.0",
     "autonomy": {
       "mode": "semi-autonomous",
       "approvalPoints": { "planning": false, "implementation": false, "review": false, "commit": true },
       "maxAutoRetries": 3,
       "reviewLoopLimit": 10,
       "planReviewLoopLimit": 10,
       "codeReviewLoopLimit": 15
     },
     "models": {
       "orchestrator": { "provider": "claude", "model": "opus", "temperature": 0.7 },
       "coder": { "provider": "claude", "model": "opus", "temperature": 0.3 },
       "reviewer": { "provider": "openai", "model": "gpt-5.2-codex", "reasoning": "high", "temperature": 0.2 }
     },
     "errorHandling": { "autoResolveAttempts": 3, "pauseOnUnresolvable": true, "notifyOnError": true, "errorLogRetention": "30d" },
     "commit": { "strategy": "per-task", "messageFormat": "conventional", "signOff": true, "branch": { "createFeatureBranch": true, "namePattern": "feature/{task-id}-{short-title}" } },
     "notifications": { "onTaskComplete": true, "onReviewFeedback": true, "onError": true, "onPipelineIdle": true },
     "timeouts": { "implementation": 600, "review": 300, "autoResolve": 180 },
     "debate": { "enabled": false, "maxRounds": 0, "timeoutSeconds": 0 }
   }
   ```

6. **Initialize and run:**
   ```bash
   cd /path/to/your/project
   ./scripts/state-manager.sh init
   ```

## After Cloning

The `.task/` folder contains initial state files that are tracked in git but should not have local changes committed. After cloning, run:

```bash
git update-index --skip-worktree .task/state.json .task/tasks.json
```

This tells git to ignore your local modifications to these files.

**To check skip-worktree status:**

```bash
git ls-files -v .task/ | grep '^S'  # S = skip-worktree is set
```

**To undo (if you need to commit changes):**

```bash
git update-index --no-skip-worktree .task/state.json
```

## Project Structure

```
your-project/
├── pipeline.config.json      # Pipeline configuration
├── CLAUDE.md                 # Claude orchestrator instructions
├── AGENTS.md                 # Codex reviewer instructions
├── .claude/
│   └── agents/               # Claude Code subagents (9 agents)
│       ├── planner.md        # Plan drafting/refinement
│       ├── implementer.md    # Code implementation
│       ├── researcher.md     # Codebase exploration
│       ├── code-reviewer-sonnet.md   # Quick code review (sonnet)
│       ├── code-reviewer-opus.md     # Deep code review (opus)
│       ├── security-reviewer-sonnet.md  # Quick security scan
│       ├── security-reviewer-opus.md    # Deep security analysis
│       ├── test-reviewer-sonnet.md   # Quick test check
│       └── test-reviewer-opus.md     # Deep test review
├── docs/
│   ├── standards.md          # Coding + review standards
│   ├── workflow.md           # Process documentation
│   └── schemas/
│       ├── review-result.schema.json   # Code review output schema
│       └── plan-review.schema.json     # Plan review output schema
├── scripts/
│   ├── orchestrator.sh       # Main pipeline loop (status/reset/dry-run)
│   ├── run-codex-review.sh   # Codex final code review
│   ├── run-codex-plan-review.sh  # Codex final plan review
│   ├── plan-to-task.sh       # Convert approved plan to task
│   ├── state-manager.sh      # State management
│   ├── validate-config.sh    # Config validation
│   ├── recover.sh            # Recovery tool
│   └── setup.sh              # Setup wizard
└── .task/                    # Runtime state (gitignored except state files)
    ├── state.json            # Pipeline state
    ├── tasks.json            # Task queue
    ├── user-request.txt      # User's feature request (input)
    ├── plan.json             # Initial plan
    ├── plan-refined.json     # Refined plan
    ├── plan-review.json      # Plan review (Codex)
    ├── current-task.json     # Active task
    ├── impl-result.json      # Implementation output
    └── review-result.json    # Code review (Codex)
```

## Usage

### Starting from a User Request

**Step 1: Create the user request file**

```bash
cat > .task/user-request.txt << 'EOF'
Add user authentication with JWT-based tokens.
Requirements:
- POST /api/login endpoint
- POST /api/logout endpoint
- JWT token validation middleware
- Unit tests for auth functions
EOF
```

**Step 2: Start the pipeline from plan drafting**

```bash
./scripts/state-manager.sh set plan_drafting ""
./scripts/orchestrator.sh
```

The orchestrator will show the current state and next action. You invoke the appropriate subagent, then transition state. The workflow proceeds through these phases:

1. **Plan drafting** → planner subagent creates initial plan
2. **Plan refining** → planner + researcher subagents refine
3. **Internal plan review** → code-reviewer-sonnet + code-reviewer-opus (parallel)
4. **Codex plan review** → final plan approval
5. **Implementing** → implementer subagent writes code
6. **Internal code reviews** → 6 reviewers in parallel (sonnet + opus for code/security/test)
7. **Codex code review** → final code approval
8. **Complete** → commit changes manually

### Check Status

```bash
./scripts/orchestrator.sh status
```

### Dry Run (Validation)

Validate your pipeline setup without running it:

```bash
# Basic validation (JSON syntax, scripts, docs, CLI tools)
./scripts/orchestrator.sh dry-run

# Strict config validation (all required keys present)
./scripts/validate-config.sh
```

**dry-run** checks:
- `.task/` directory and state file validity
- `pipeline.config.json` valid JSON syntax
- Required scripts present and executable (8 scripts)
- Required subagents in `.claude/agents/` (9 agents with dual-model reviewers)
- Required docs (`standards.md`, `workflow.md`)
- `.task` in `.gitignore`
- CLI tools (`jq` required, `claude`/`codex` optional)
- Global CLAUDE.md conflict detection (warns if setup not run)

**validate-config.sh** checks:
- All required top-level keys present
- All required nested keys (autonomy, models, etc.)
- Correct value types (numbers, booleans)

### Recovery

```bash
# Interactive recovery menu
./scripts/recover.sh

# Or reset directly
./scripts/orchestrator.sh reset
```

### Handling User Input Requests

If Claude needs clarification, the pipeline pauses with `needs_user_input` state:

```bash
# Check what questions need answering
cat .task/state.json | jq '.previous_state'  # See which phase
cat .task/plan-refined.json | jq '.questions'  # Plan phase questions
cat .task/impl-result.json | jq '.questions'   # Implementation questions

# After providing answers, resume:
./scripts/state-manager.sh set plan_refining plan-001  # or implementing task-001
./scripts/orchestrator.sh
```

## Configuration

### pipeline.config.json

| Setting                             | Description                                   | Default           |
| ----------------------------------- | --------------------------------------------- | ----------------- |
| `autonomy.mode`                     | `autonomous`, `semi-autonomous`, `supervised` | `semi-autonomous` |
| `autonomy.reviewLoopLimit`          | Max review iterations (legacy, fallback)      | `10`              |
| `autonomy.planReviewLoopLimit`      | Max plan review iterations                    | `10`              |
| `autonomy.codeReviewLoopLimit`      | Max code review iterations                    | `15`              |
| `errorHandling.autoResolveAttempts` | Retries before pausing                        | `3`               |
| `models.orchestrator.model`         | Claude orchestrator model                     | `claude-opus-4.5` |
| `models.coder.model`                | Claude coder model                            | `claude-opus-4.5` |
| `models.reviewer.model`             | Codex reviewer model                          | `gpt-5.2-codex`   |
| `debate.enabled`                    | Debate mechanism (disabled)                   | `false`           |

### Local Config Overrides

Create `pipeline.config.local.json` to override settings without modifying the tracked config:

```json
{
  "autonomy": {
    "planReviewLoopLimit": 5,
    "codeReviewLoopLimit": 10
  }
}
```

This file is gitignored and will be merged on top of `pipeline.config.json`.

### Autonomy Modes

| Mode              | Planning | Implementation | Review | Commit     |
| ----------------- | -------- | -------------- | ------ | ---------- |
| `autonomous`      | Auto     | Auto           | Auto   | Auto       |
| `semi-autonomous` | Auto     | Auto           | Auto   | **Manual** |
| `supervised`      | Manual   | Manual         | Manual | Manual     |

## Customization

### Adding Project-Specific Standards

Edit `docs/standards.md`:

```markdown
# Project Standards

## Coding Standards

- Use TypeScript strict mode
- All functions must have JSDoc comments
- No console.log in production code

## Review Checklist

### Must Check (severity: error)

- No hardcoded secrets
- All API endpoints have auth middleware
- Database queries use parameterized statements
```

### Modifying Review Schema

Edit `docs/schemas/review-result.schema.json` to add custom checklist items:

```json
{
  "checklist": {
    "properties": {
      "security": { "enum": ["PASS", "WARN", "FAIL"] },
      "performance": { "enum": ["PASS", "WARN", "FAIL"] },
      "your_custom_check": { "enum": ["PASS", "WARN", "FAIL"] }
    }
  }
}
```

## Troubleshooting

### Pipeline stuck in error state

```bash
./scripts/recover.sh
# Select option 1 to reset to idle
```

### Claude not creating output file

Check that Claude has the right permissions:

```bash
# Verify CLAUDE.md instructions mention the output file
grep "impl-result.json" CLAUDE.md
```

### Codex review failing

Verify the schema is valid:

```bash
jq empty docs/schemas/review-result.schema.json
```

### View error logs

```bash
ls -la .task/errors/
cat .task/errors/error-*.json | jq
```

## License

GPL-3.0 license

# Multi-AI Orchestration Pipeline

A development pipeline that orchestrates multiple AI models to plan, implement, review, and iterate on code changes.

## Recommended Subscriptions

| Service | Subscription | Purpose |
|---------|--------------|---------|
| **Claude Code** | MAX 20 | Main thread (planning, coding) + Review skills |
| **Codex CLI** | Plus | Final reviews (invoked via skill) |

> **Note**: This architecture uses skill-based sequential reviews with forked context isolation for token efficiency.

## Architecture

- **Claude Code (Main Thread)** - Does planning, research, and implementation directly
- **Review Skills** - Three skills for sequential review (sonnet → opus → codex)
- **Codex CLI** - Invoked by review-codex skill for final reviews

> **Interested in running 3 AIs?** Check out [claude-codex-gemini](https://github.com/Z-M-Huang/claude-codex-gemini) which adds Gemini as a dedicated orchestrator.

## How It Works

### Quick Start with `/multi-ai`

The easiest way to use this pipeline:

```
/multi-ai Add user authentication with JWT tokens
```

This command:
1. Cleans up previous task files
2. Creates and refines a plan
3. Runs sequential reviews (sonnet → opus → codex)
4. Implements the code
5. Runs sequential reviews (sonnet → opus → codex)
6. Marks complete

### Sequential Review Flow

Reviews run **sequentially** - each model reviews only ONCE per cycle:

```
Plan/Code → /review-sonnet → fix → /review-opus → fix → /review-codex → fix (restart)
```

**Key benefits**:
- Each model provides unique perspective without re-reviewing
- Progressive refinement (fast → deep → final)
- Token-efficient (forked context isolation)

### Phase 1: Planning

```
User Request → Main Thread (creates & refines plan)
                                       ↓
                         /review-sonnet (fast review)
                                       ↓
                         /review-opus (deep review)
                                       ↓
                         /review-codex (final review)
                                       ↓
                              implementing
```

### Phase 2: Implementation

```
Plan → Main Thread (implements code)
                    ↓
       /review-sonnet (fast review)
                    ↓
       /review-opus (deep review)
                    ↓
       /review-codex (final review)
                    ↓
               complete
```

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

   # Configure models and autonomy level
   vim pipeline.config.json
   ```

3. **Run setup (detects workflow conflicts):**

   ```bash
   ./scripts/setup.sh
   ```

4. **Copy skills to personal directory (for hot-reload):**

   ```bash
   cp -r .claude/skills/* ~/.claude/skills/
   ```

5. **Start the pipeline:**

   ```bash
   /multi-ai Add your feature description here
   ```

### Option B: Manual Workflow

1. **Create a user request:**

   ```bash
   cat > .task/user-request.txt << 'EOF'
   Add user authentication with JWT tokens.
   - POST /api/login endpoint
   - POST /api/logout endpoint
   - JWT token validation middleware
   - Unit tests for auth functions
   EOF
   ```

2. **Run the pipeline:**

   ```bash
   ./scripts/state-manager.sh set plan_drafting ""
   ./scripts/orchestrator.sh
   ```

3. **Follow orchestrator instructions** to create plan, run reviews, implement, etc.

## Project Structure

```
your-project/
├── pipeline.config.json      # Pipeline configuration
├── CLAUDE.md                 # Claude orchestrator instructions
├── AGENTS.md                 # Codex reviewer instructions
├── .claude/
│   └── skills/               # Review and orchestration skills
│       ├── review-sonnet/    # Fast review (sonnet model)
│       ├── review-opus/      # Deep review (opus model)
│       ├── review-codex/     # Final review (codex)
│       └── multi-ai/         # Pipeline entry point command
├── docs/
│   ├── standards.md          # Coding + review standards
│   ├── workflow.md           # Process documentation
│   └── schemas/
│       ├── review-result.schema.json   # Code review output schema
│       └── plan-review.schema.json     # Plan review output schema
├── scripts/
│   ├── orchestrator.sh       # Main pipeline loop (status/reset/dry-run)
│   ├── state-manager.sh      # State management
│   ├── recover.sh            # Recovery tool
│   └── setup.sh              # Setup wizard
└── .task/                    # Runtime state (gitignored except state files)
    ├── state.json            # Pipeline state
    ├── user-request.txt      # User's feature request (input)
    ├── plan.json             # Initial plan
    ├── plan-refined.json     # Refined plan
    ├── impl-result.json      # Implementation output
    ├── review-sonnet.json    # Sonnet review output
    ├── review-opus.json      # Opus review output
    └── review-codex.json     # Codex review output
```

## Skills

| Skill | Model | Purpose |
|-------|-------|---------|
| `/review-sonnet` | sonnet | Fast review (code + security + tests) |
| `/review-opus` | opus | Deep review (architecture + subtle issues) |
| `/review-codex` | codex | Final review via Codex CLI |
| `/multi-ai` | - | Pipeline entry point (starts full workflow) |

## Usage

### Check Status

```bash
./scripts/orchestrator.sh status
```

### Dry Run (Validation)

```bash
./scripts/orchestrator.sh dry-run
```

**Checks**:
- `.task/` directory and state file validity
- `pipeline.config.json` valid JSON syntax
- Required scripts present and executable (4 scripts)
- Required skills in `.claude/skills/` (3 review skills)
- Required docs (`standards.md`, `workflow.md`)
- `.task` in `.gitignore`
- CLI tools (`jq` required, `claude`/`codex` optional)

### Recovery

```bash
# Interactive recovery menu
./scripts/recover.sh

# Or reset directly
./scripts/orchestrator.sh reset
```

## Configuration

### pipeline.config.json

| Setting                             | Description                                   | Default           |
| ----------------------------------- | --------------------------------------------- | ----------------- |
| `autonomy.mode`                     | `autonomous`, `semi-autonomous`, `supervised` | `semi-autonomous` |
| `autonomy.planReviewLoopLimit`      | Max plan review iterations                    | `10`              |
| `autonomy.codeReviewLoopLimit`      | Max code review iterations                    | `15`              |
| `errorHandling.autoResolveAttempts` | Retries before pausing                        | `3`               |
| `models.reviewer.model`             | Codex reviewer model                          | `gpt-5.2-codex`   |

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

## Troubleshooting

### Pipeline stuck in error state

```bash
./scripts/recover.sh
# Select option 1 to reset to idle
```

### Skills not being detected

Copy skills to personal directory for hot-reload:

```bash
cp -r .claude/skills/* ~/.claude/skills/
```

### View error logs

```bash
ls -la .task/errors/
cat .task/errors/error-*.json | jq
```

## License

GPL-3.0 license

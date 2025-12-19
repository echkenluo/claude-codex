#!/bin/bash
set -e

# This script allows Claude to create initial plans
# Previously done by Gemini orchestrator

STANDARDS=$(cat docs/standards.md)
WORKFLOW=$(cat docs/workflow.md)

# Read user request from argument (argv only, no stdin)
USER_REQUEST="${1:-}"
if [[ -z "$USER_REQUEST" ]]; then
  echo "Usage: $0 'description of what you want to build'" >&2
  echo "Example: $0 'Add user authentication with JWT tokens'" >&2
  exit 1
fi

# Generate plan ID
PLAN_ID="plan-$(date +%Y%m%d-%H%M%S)"

PROMPT="## Project Standards

$STANDARDS

---

## Workflow Documentation

$WORKFLOW

---

## User Request

$USER_REQUEST

---

## Your Task

Create an initial plan for this request. Write to .task/plan.json using this format:

{
  \"id\": \"$PLAN_ID\",
  \"title\": \"Short descriptive title\",
  \"description\": \"What the user wants to achieve\",
  \"requirements\": [
    \"Requirement 1\",
    \"Requirement 2\"
  ],
  \"created_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\",
  \"created_by\": \"claude\"
}

Be specific about requirements. Break down the request into clear, actionable items."

# Execute Claude
claude -p "$PROMPT" \
  --output-format json \
  --allowedTools "Read,Write,Edit,Glob,Grep" \
  --permission-mode acceptEdits

# Verify output
if [[ ! -f .task/plan.json ]]; then
  echo "ERROR: Claude did not create .task/plan.json" >&2
  exit 1
fi

if ! jq empty .task/plan.json 2>/dev/null; then
  echo "ERROR: .task/plan.json is not valid JSON" >&2
  exit 1
fi

echo "Plan created: .task/plan.json"
cat .task/plan.json | jq '{id, title}'

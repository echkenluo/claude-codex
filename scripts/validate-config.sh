#!/bin/bash
set -e

# Strict config validation - fails on any missing required key

CONFIG="pipeline.config.json"

echo "Validating $CONFIG..."

if [[ ! -f "$CONFIG" ]]; then
  echo "FAIL: $CONFIG not found"
  exit 1
fi

if ! jq empty "$CONFIG" 2>/dev/null; then
  echo "FAIL: $CONFIG is not valid JSON"
  exit 1
fi

# Required top-level keys (each must exist)
jq -e 'has("version")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'version'"; exit 1; }
jq -e 'has("autonomy")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy'"; exit 1; }
jq -e 'has("models")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'models'"; exit 1; }
jq -e 'has("errorHandling")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'errorHandling'"; exit 1; }
jq -e 'has("commit")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'commit'"; exit 1; }
jq -e 'has("notifications")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'notifications'"; exit 1; }
jq -e 'has("timeouts")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'timeouts'"; exit 1; }
jq -e 'has("debate")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'debate'"; exit 1; }

# Required autonomy keys
jq -e '.autonomy | has("mode")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.mode'"; exit 1; }
jq -e '.autonomy | has("approvalPoints")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.approvalPoints'"; exit 1; }
jq -e '.autonomy | has("autoCommit")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.autoCommit'"; exit 1; }
jq -e '.autonomy | has("maxAutoRetries")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.maxAutoRetries'"; exit 1; }
jq -e '.autonomy | has("reviewLoopLimit")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.reviewLoopLimit'"; exit 1; }
jq -e '.autonomy | has("planReviewLoopLimit")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.planReviewLoopLimit'"; exit 1; }
jq -e '.autonomy | has("codeReviewLoopLimit")' "$CONFIG" >/dev/null || { echo "FAIL: missing 'autonomy.codeReviewLoopLimit'"; exit 1; }

# Required model keys
jq -e '.models | has("orchestrator") and has("coder") and has("reviewer")' "$CONFIG" >/dev/null || { echo "FAIL: missing model definitions"; exit 1; }
jq -e '.models.orchestrator | has("provider") and has("model") and has("temperature")' "$CONFIG" >/dev/null || { echo "FAIL: incomplete 'models.orchestrator'"; exit 1; }
jq -e '.models.coder | has("provider") and has("model") and has("temperature")' "$CONFIG" >/dev/null || { echo "FAIL: incomplete 'models.coder'"; exit 1; }
jq -e '.models.reviewer | has("provider") and has("model") and has("reasoning") and has("temperature")' "$CONFIG" >/dev/null || { echo "FAIL: incomplete 'models.reviewer'"; exit 1; }

# Validate types
jq -e '.autonomy.planReviewLoopLimit | type == "number"' "$CONFIG" >/dev/null || { echo "FAIL: planReviewLoopLimit must be number"; exit 1; }
jq -e '.autonomy.codeReviewLoopLimit | type == "number"' "$CONFIG" >/dev/null || { echo "FAIL: codeReviewLoopLimit must be number"; exit 1; }
jq -e '.debate.enabled | type == "boolean"' "$CONFIG" >/dev/null || { echo "FAIL: debate.enabled must be boolean"; exit 1; }

echo "Config validation: PASSED"

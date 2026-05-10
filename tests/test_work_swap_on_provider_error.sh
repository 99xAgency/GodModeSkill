#!/usr/bin/env bash
# Integration test: fake-codex-1 shows "Error from provider" in its tmux pane →
# check_for_errors fires → retry → 2s later second error → swap to fake-codex-2 →
# substitutions[0].reason == "provider_error".
set -euo pipefail

SCRIPT_DIR="$(dirname "$(realpath "$0")")"
WORK="$SCRIPT_DIR/../skill/work"

scratch="$(mktemp -d)"
SESS_CDX1="fake-pe-cdx1-$$"
SESS_CDX2="fake-pe-cdx2-$$"
SESS_GEM1="fake-pe-gem1-$$"
SESS_OC1="fake-pe-oc1-$$"

cleanup() {
  tmux kill-session -t "$SESS_CDX1" 2>/dev/null || true
  tmux kill-session -t "$SESS_CDX2" 2>/dev/null || true
  tmux kill-session -t "$SESS_GEM1" 2>/dev/null || true
  tmux kill-session -t "$SESS_OC1"  2>/dev/null || true
  rm -rf "$scratch"
}
trap cleanup EXIT

# ── Fake tmux sessions ───────────────────────────────────────────────────
tmux new-session -d -s "$SESS_CDX1"
tmux new-session -d -s "$SESS_CDX2"
tmux new-session -d -s "$SESS_GEM1"
tmux new-session -d -s "$SESS_OC1"

# Inject provider-error text into cdx1 pane so check_for_errors fires.
tmux send-keys -t "$SESS_CDX1" "echo 'Error from provider: rate limit exceeded'" Enter

out="$scratch/out"
mkdir -p "$out"

# ── Per-agent nudge scripts ──────────────────────────────────────────────
# fake-codex-1: keeps injecting error text on every retry (never recovers)
cat > "$scratch/nudge-cdx1.sh" <<NUDGE_EOF
#!/usr/bin/env bash
tmux send-keys -t "$SESS_CDX1" "echo 'Error from provider: rate limit exceeded'" Enter
exit 0
NUDGE_EOF
chmod +x "$scratch/nudge-cdx1.sh"

# fake-codex-2: instant-done (swap target)
cat > "$scratch/nudge-cdx2.sh" <<NUDGE_EOF
#!/usr/bin/env bash
cat > "$out/fake-codex-2-findings.md" <<'EOF'
<findings>
  <verdict agree="true"><reasoning>fake instant agree</reasoning></verdict>
</findings>
## DONE
EOF
NUDGE_EOF
chmod +x "$scratch/nudge-cdx2.sh"

# fake-gemini-1: instant-done
cat > "$scratch/nudge-gem1.sh" <<NUDGE_EOF
#!/usr/bin/env bash
cat > "$out/fake-gemini-1-findings.md" <<'EOF'
<findings>
  <verdict agree="true"><reasoning>fake instant agree</reasoning></verdict>
</findings>
## DONE
EOF
NUDGE_EOF
chmod +x "$scratch/nudge-gem1.sh"

# fake-opencode-1: instant-done
cat > "$scratch/nudge-oc1.sh" <<NUDGE_EOF
#!/usr/bin/env bash
cat > "$out/fake-opencode-1-findings.md" <<'EOF'
<findings>
  <verdict agree="true"><reasoning>fake instant agree</reasoning></verdict>
</findings>
## DONE
EOF
NUDGE_EOF
chmod +x "$scratch/nudge-oc1.sh"

# ── Fake agents.json ─────────────────────────────────────────────────────
cat > "$scratch/agents.json" <<AGENTS_EOF
{"agents": [
  {"name": "fake-codex-1",   "type": "codex",
   "tmux_session": "$SESS_CDX1", "tmux_env_var": "FAKE_PE_CDX1_SESS",
   "nudge_command": "$scratch/nudge-cdx1.sh"},
  {"name": "fake-codex-2",   "type": "codex",
   "tmux_session": "$SESS_CDX2", "tmux_env_var": "FAKE_PE_CDX2_SESS",
   "nudge_command": "$scratch/nudge-cdx2.sh"},
  {"name": "fake-gemini-1",  "type": "gemini",
   "tmux_session": "$SESS_GEM1", "tmux_env_var": "FAKE_PE_GEM1_SESS",
   "nudge_command": "$scratch/nudge-gem1.sh"},
  {"name": "fake-opencode-1","type": "opencode",
   "tmux_session": "$SESS_OC1",  "tmux_env_var": "FAKE_PE_OC1_SESS",
   "nudge_command": "$scratch/nudge-oc1.sh"}
]}
AGENTS_EOF

# ── State dir ────────────────────────────────────────────────────────────
mkdir -p "$scratch/state"
echo '{}' > "$scratch/state/state.json"
echo '{}' > "$scratch/state/agent-lru.json"

# ── Invoke work ──────────────────────────────────────────────────────────
# WORK_ERROR_RETRY_DELAY=2: triggers second-error path 2s after first retry.
# WORK_TIMEOUT=30: enough headroom for 2 error cycles + swap.
result=$(
  AGENTS_JSON="$scratch/agents.json" \
  STATE_DIR="$scratch/state" \
  WORK_TIMEOUT=30 \
  WORK_ERROR_RETRY_DELAY=2 \
  "$WORK" review \
    --mode plan \
    --task "fake task for provider-error test" \
    --task-id fake-pe-1 \
    --round 1 \
    --agents "fake-codex-1,fake-gemini-1,fake-opencode-1" \
    --out "$out" 2>/dev/null
) || true

echo "$result" > "$scratch/result.json"

# ── Assertions ───────────────────────────────────────────────────────────
jq -e '.substitutions | length >= 1' "$scratch/result.json" \
  || { echo "FAIL: substitutions array empty"; exit 1; }
jq -e '.substitutions[0].lineage == "codex"' "$scratch/result.json" \
  || { echo "FAIL: substitutions[0].lineage != codex"; exit 1; }
jq -e '.substitutions[0].from == "fake-codex-1"' "$scratch/result.json" \
  || { echo "FAIL: substitutions[0].from != fake-codex-1"; exit 1; }
jq -e '.substitutions[0].to == "fake-codex-2"' "$scratch/result.json" \
  || { echo "FAIL: substitutions[0].to != fake-codex-2"; exit 1; }
jq -e '.substitutions[0].reason == "provider_error"' "$scratch/result.json" \
  || { echo "FAIL: substitutions[0].reason != provider_error"; exit 1; }

echo "PASS: swap on provider_error"

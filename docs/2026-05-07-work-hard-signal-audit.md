# /work hard-signal coverage audit — 2026-05-07

Audited: `skill/work` (1165 lines), `skill/work-converge` (311 lines).
Branch: `feature/chorus-quorum-gates`.

---

## `try_lineage_swap` callsites

```
skill/work:615:try_lineage_swap() {
skill/work:736:if try_lineage_swap "$name"; then
```

One definition (line 615), one call-site (line 736), inside `check_for_errors`.
No other paths call `try_lineage_swap`.

---

## Failure modes vs. try_lineage_swap coverage

| Mode | Detection (file:line) | Triggers try_lineage_swap? | Notes |
|------|----------------------|---------------------------|-------|
| Provider error string (ERROR_RE) | work:499 (regex def), work:711 (grep in check_for_errors), work:730-736 (give-up branch) | YES — at second error after ≥60s grace | First hit → nudge-retry. Second hit (≥60s later) → `try_lineage_swap`. If swap fails → stub DONE written, lineage marked missing by work-converge. |
| Permission prompt (PROMPT_RE, NUMBERED_PROMPT_RE, OPENCODE_PROMPT_RE) | work:478-487 (regex defs), work:522-572 (check_and_approve_prompts) | NO | Auto-approved every 30s debounce (line 545). Destructive prompts blocked and left stuck (line 532-539) — no swap, no stub, just hangs until timeout. This is intentional. |
| Modal popup / opencode @ or / trigger (OPENCODE_POPUP_RE) | work:520 (regex def), work:580-607 (check_for_popups) | NO | Escape×2 + re-nudge (lines 597-605). Not a failure; recovered in-place. Only fires for opencode type. |
| inotifywait timeout reached without `## DONE` written | work:419-422 (timeout branch in watcher loop) | NO — timeout is NOT a trigger | Loop breaks silently with `✗ TIMEOUT` printed. work-converge then reads whatever is in the findings file; no `## DONE` → `done_marker=False` → verdict=None → lineage classified as `missing` → decision=`incomplete`. No swap attempted at timeout. **GAP.** |
| Tmux session dies mid-flight (after VALID population) | Not detected inside the watcher loop | NO — not detected | Session liveness checked once at launch (work:271-274). Mid-flight death is invisible to the loop: `tmux capture-pane` returns empty/error (silently `|| true` at lines 586, 710), `check_for_errors` sees no ERROR_RE match in empty pane, loop keeps waiting until timeout. **GAP.** |
| Agent binary / nudge command ENOENT on session start | work:266 (agents.json lookup), work:271-274 (tmux liveness) | NO | Caught pre-flight: missing agents.json entry → skip (line 266), dead tmux session → skip (line 272). Agent is never added to VALID so work-converge sees it as absent, not failed. Binary failure during the `env ... nudge` call (line 387) is unchecked — no `|| true`, but `set -euo pipefail` would abort cmd_review entirely rather than continuing gracefully. Subtle: if nudge binary is missing, the whole `work review` exits 1, not a per-agent failure. **MINOR GAP** (in error reporting, not in correctness). |

---

## Gaps

### GAP-1 — inotifywait timeout does not trigger try_lineage_swap (MEDIUM severity)

**Location:** `work:419-422` (timeout break) and `work:436` (inotifywait 5s safety-wake).

**Detail:** When a reviewer neither writes `## DONE` nor produces an ERROR_RE-matching pane line
within the `--timeout` window (default 600s), the watcher loop breaks and falls through to
`work-converge`. The findings file is a stub (only the "in progress" header written at line 371).
work-converge classifies the lineage as `missing` → `decision=incomplete`.

`try_lineage_swap` is never called. A same-lineage peer with quota could have been tried but
wasn't. The 600s wall-clock is wasted before Claude sees the `incomplete` result.

**Proposed fix (Tasks 2-7 scope):** Add a per-agent deadline tracking array; when an agent has
been in-flight for more than `N` seconds (e.g. 300s, half the wall timeout) without writing
`## DONE` and its pane is idle (no new output for 60s), call `try_lineage_swap` speculatively.
Alternatively, on timeout break write a stub and call `try_lineage_swap` for each still-pending
agent before handing off to work-converge.

### GAP-2 — Tmux session death mid-flight is undetected (MEDIUM severity)

**Location:** watcher loop `work:406-437`; pane-capture at `work:586`, `work:710`.

**Detail:** `tmux capture-pane ... 2>/dev/null || true` on a dead session returns empty string.
`check_for_errors` at line 711 (`grep -qiE "$ERROR_RE"`) sees no match in an empty string and
returns 0. The agent is silently treated as "still running" until the 600s timeout fires.
`try_lineage_swap` is not called.

**Proposed fix:** In the watcher loop, for any agent not yet done, check
`tmux has-session -t "${SESS[$name]}" 2>/dev/null || <handle dead>`. If session is gone,
immediately write a stub findings file (same pattern as check_for_errors escalation path,
lines 747-772) and call `try_lineage_swap`.

### GAP-3 — Nudge binary ENOENT aborts entire cmd_review (LOW severity)

**Location:** `work:387` — `env "${ENVVAR[$name]}=${SESS[$name]}" "${NUDGE[$name]}" "$prompt"` with
no error handling, under `set -euo pipefail`.

**Detail:** If the nudge binary path in agents.json is wrong or the binary is removed, the
`env` call fails and `set -e` causes cmd_review to exit 1 immediately, killing all in-flight
reviewers mid-nudge. This is not a per-agent graceful skip.

**Proposed fix (low priority):** Wrap the nudge invocation: `... >/dev/null || { echo "  ✗ $name nudge failed" >&2; VALID=("${VALID[@]/$name}"); continue; }`. Would require restructuring the loop slightly. Or pre-validate nudge binary existence before the nudge loop.

---

## Recommendation

No gaps are blocking for the current chorus/quorum-gates work. The system reaches a correct
(if slow) `incomplete` outcome for both GAP-1 and GAP-2 — Claude is correctly notified and can
intervene manually. The 600s wait before that notification is the real cost.

GAP-1 (timeout without swap) and GAP-2 (silent mid-flight tmux death) are the highest-value
targets for Tasks 2-7: adding a per-agent liveness probe and a mid-flight `try_lineage_swap`
call on timeout would reduce worst-case wall-clock from 600s to ~300s and make the swap
mechanism work for the most common real-world failure mode (session crash / rate-limit silence).

GAP-3 is cosmetic — mis-configured agents.json is an operator error, not a runtime failure mode.

**Summary: 0 blocking gaps. 2 medium gaps (GAP-1, GAP-2) that are worth fixing in Tasks 2-7
to improve latency and swap coverage. 1 low gap (GAP-3) that is acceptable to leave.**

---

## Status update — 2026-05-10

- GAP-1: CLOSED in commit 1899f96 — `try_lineage_swap` called for each incomplete agent on timeout; resets timer and continues if any swap performed.
- GAP-2: CLOSED in commit 590acf2 — `tmux has-session` guard added at top of `check_for_errors`; dead sessions with no `## DONE` immediately attempt lineage swap.
- GAP-3: DEFERRED (LOW severity; init-time, not hot-path; pre-launch error catches it earlier)

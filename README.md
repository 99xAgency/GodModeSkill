# GodModeSkill

A multi-LLM cross-review workflow for Claude Code. Build `/work`, a single command that orchestrates code review consensus across **3 different model families** before any merge happens.

## What it does

When you ask Claude to plan a feature, implement code, or fix a bug, `/work`:

1. Auto-discovers context (CLAUDE.md, planning docs, related memory files, prior decisions)
2. Sends an XML pack to **3 reviewer LLMs in parallel** (1 Codex + 1 Gemini + 1 OpenCode)
3. Waits event-driven (zero token burn during the wait)
4. Requires **all 3 lineages to agree** before the gate opens
5. If they disagree, Claude revises and re-runs (max 3 rounds)
6. Auto-handles git (branch, commit, push, PR), but **always asks before merge** with a 4-question checklist

## Why

Single-model AI coding fails silently. Code looks reasonable, tests pass, but there's a subtle bug or design drift that only shows up later. Having a different model family read the same code from scratch catches a startling amount of it.

Same-family models share blind spots. Three Codex sessions reviewing the same code is mostly an echo chamber. Lineage diversity (Codex + Gemini + OpenCode) is the actual unlock.

## Modes

| Mode | When to use | What happens |
|------|-------------|--------------|
| `plan` | New feature design | Propose → review → converge → write `planning/<feature>.md` |
| `implement` | Build the agreed plan | Design review → code → test → code review → PR → merge gate |
| `major-bug` | Real bug fix | Failing test (TDD) → fix-plan review → code → test → code review → PR |
| `minor-bug` | Typo / one-liner | Just fix it. No LLM gates. |

## Prerequisites

You need at least **3 different model families**. Recommended setup:

- **Claude Code** (any plan)
- **Codex CLI** (ChatGPT subscription — Plus or Pro)
- **Gemini CLI** (Google AI Pro)
- **OpenCode CLI** with at least one of:
  - OpenCode Go subscription (gives Kimi + DeepSeek + others, flat-fee)
  - OR direct API keys (Moonshot, DeepSeek)

System tools: `tmux`, `jq`, `inotify-tools`, `git`, `python3`.

If you only have 2 families, the lineage-quorum will fail (you need 1 of each: codex + gemini + opencode). You can still use the framework with 2 if you edit `work-converge` to relax the quorum rule, but you lose the diversity insight.

## How to install

There are two ways:

### Option 1 — paste a prompt into Claude (recommended)

Open Claude Code and paste the contents of [`INSTALL.md`](INSTALL.md). Claude will ask which CLIs you have, then install everything for you.

### Option 2 — manual

```bash
git clone https://github.com/99xAgency/GodModeSkill.git
cd GodModeSkill
# Inspect skill/ to understand the layout, then copy each file to its target.
```

Targets:
- `skill/work*` + `skill/agent-status` → `~/.local/bin/`
- `skill/commands/work.md` → `~/.claude/commands/work.md`
- `skill/agent-sessions/*` → `~/.config/agent-sessions/` (rename `agents.json.template` → `agents.json` and edit)
- `skill/gemini/settings.snippet.json` → merge into `~/.gemini/settings.json`
- `skill/gemini/GEMINI.snippet.md` → append to `~/.gemini/GEMINI.md`
- `skill/gemini/policies/00-deny-destructive.toml` → `~/.gemini/policies/`
- `skill/opencode/opencode.snippet.json` → merge into `~/.config/opencode/opencode.json`
- `skill/examples/AGENTS.md` → put in each opencode session working dir

Make all `skill/work*` files executable: `chmod +x ~/.local/bin/work*`

## Usage

In Claude Code:

```
/work plan an oauth login flow for the admin panel
/work implement the planning/oauth-login.md design
/work fix bug: detail page crashes on null verdict
/work fix typo in nav header
```

Claude figures out the mode, picks 3 reviewers, builds the pack, runs the loop, and asks for your sign-off at the merge gate.

## Costs

Roughly $0 incremental on top of the subscriptions you already have, if you use plan-priced reviewers (ChatGPT subscription + Google AI Pro + OpenCode Go).

If you use API keys for Kimi/DeepSeek instead of OpenCode Go, expect ~cents per review depending on pack size (~50KB packs typical).

## How the lineage quorum works

`work-converge` parses each reviewer's XML response, extracts the `<verdict agree="true|false|partial">` block, and groups by lineage:

- `codex` agents (your cdx-* sessions)
- `gemini` agents (your gem-* sessions)
- `opencode` agents (kimi, deepseek, etc.)

Quorum passes only when **at least one agent of each lineage** returns `agree`. Partial verdicts count as agree only if no critical/high findings.

If a lineage is **missing** (agent died, no agent available), exit code is 2 (incomplete). If any lineage **disagrees**, exit code is 1 (revise + retry). If all three agree, exit code is 0.

## How the wait is zero-token

When `/work` is waiting for reviewers, Claude is suspended on a Bash tool call. The Bash call uses `inotifywait` to block until any findings file changes. So:

- Claude tokens burned during wait: **0**
- CPU during wait: **0** (inotify is kernel-level)
- Latency between reviewer finishing and Claude resuming: **<1s** (filesystem event)

A 5-second safety wakeup also re-checks for permission prompts (auto-approves safe ones, refuses destructive ones), modal popups (opencode "Select agent" / "Select model" pickers — auto-dismissed with Escape), and provider errors (Moonshot/DeepSeek 5xx, rate limits — see *Resilience* below).

## Pre-merge checklist

Before any actual merge, Claude fills out and shows you:

```
1. Coding principles (CLAUDE.md): [followed | drifted: what + why]
2. Architecture guidelines:        [followed | drifted: what + why]
3. Tests:                          [PASS | FAIL: which]
4. Reviewer consensus:             [agree | overridden: reason]

Merge?
1. Yes — merge now
2. No — fix drift / failures first
3. Override and merge anyway (give reason)
```

You pick 1, 2, or 3. Catches a lot of "I think it's done" moments where the model has quietly drifted from the plan.

## Adding more agents

Edit `~/.config/agent-sessions/agents.json`. Add a new entry with the same shape as existing ones. `work pick-agents` will automatically include it in the LRU rotation for its lineage.

Common cases:
- Add a 4th Codex on a new ChatGPT account: `cdx-4` with its own `CODEX_HOME`
- Add a 2nd Gemini: `gem-2` (e.g. for parallel review)
- Add a Claude reviewer running in tmux: `claude-1` with `type: "claude"` (you'd need to extend `work-pack-build` quorum logic to recognize it)

## Resilience — what happens when a reviewer breaks

Real reviewer failures fall into three classes. `/work` handles each automatically and only escalates to Claude when it can't recover.

| Failure | Detection | Recovery |
|---|---|---|
| **Provider error** (Moonshot/DeepSeek 5xx, rate limit, gateway hiccup, "Error from provider", context overflow) | `ERROR_RE` matched in pane within 5s | Auto-retry the nudge once. If a second error fires within 60s: opencode lineage gets a peer-swap (kimi ⇄ deepseek), other lineages get a stub findings file ending `## DONE` so the watcher exits fast and Claude takes over. |
| **TUI modal popup** (opencode "Select agent" / "Select model" / "Ask: No results found" — triggered by `/` or `@` chars at chunk boundaries during paste) | `OPENCODE_POPUP_RE` matched in pane within 5s | Send `Escape` twice + re-nudge. Popup dismissed silently. Pre-flight `Escape×2` also runs before every opencode nudge. |
| **Permission prompt for shell command** (CLI prompts the reviewer for `cat`/`tee`/`bash` execution) | `PROMPT_RE` matched in pane | Auto-approve with the right keystrokes (codex `y`, gemini numbered `2`, opencode arrow `Right Enter` for "Allow always"). Logs the command to `approvals.log` so you can later add it to your CLI's permanent allow-list. |
| **Destructive command** (`rm -rf`, `sudo`, `git push --force`, `DROP TABLE`, ~25 patterns) | `DESTRUCTIVE_RE` matched in pane | **NOT auto-approved.** Agent stays stuck, orchestrator prints `tmux attach -t <session>`, logs to `destructive-blocks.log`. Visible-stuck > silent-rejection. |

**See what's been stuck across runs:**
```
work permissions          # last 30 auto-approvals + repeating commands + destructive blocks
```

This lets you spot bash patterns that prompt repeatedly and add them to your CLI config (e.g. `~/.config/opencode/opencode.json`'s `permission.bash` block) so they're allowed permanently — no orchestrator round-trip.

## Per-CLI prompt format

Each CLI's TUI handles multi-line input differently, so `/work` builds a per-CLI prompt:

| CLI | Format | Why |
|---|---|---|
| Codex | Multi-paragraph (bracketed-paste safe) | Codex handles `[Pasted Content N chars]` blocks correctly |
| Gemini | **Single line** with `@/abs/path/to/pack.xml` (inline file attach) | Gemini's TUI treats every `\n` as Submit — multi-paragraph paste fragments into N separate one-line queries |
| Opencode (kimi+deepseek) | **Single line**, plain text path (no leading `/` or `@`) | tmux paste-buffer splits into ~1.5KB chunks; `/` or `@` at a chunk boundary opens slash-command or agent-picker mid-paste, swallowing the rest |

## Pack truncation safety

When a review's pack exceeds `MAX_CTX_BYTES` (800KB default — sized for Opus 4.7 / Gemini 3.1 Pro / Kimi K2.6's 1M+ context), `work-pack-build` drops journals → memory files → diff in that order. When the diff itself gets truncated, the pack emits an explicit `<reviewer-instruction priority="critical">` block ordering the reviewer to verify each finding against the full `<code_file>` blocks before reporting. This prevents the failure mode where reviewers anchor on the truncated diff and hallucinate findings about the cut-off portion.

## Customization

- **Quorum rule**: edit `quorum_check()` in `work-converge`
- **Pack context + cap**: `MAX_CTX_BYTES` (default 800KB) and discovery functions in `work-pack-build`
- **Permission patterns**: `PROMPT_RE` (auto-approve), `DESTRUCTIVE_RE` (block), `ERROR_RE` (retry), `OPENCODE_POPUP_RE` (dismiss) in `work`
- **Opencode peer-swap**: `OPENCODE_PARTNER` map in `work` (default `kimi ⇄ deepseek`)
- **Modes**: edit `~/.claude/commands/work.md` for the slash command behavior

## Safety

- Destructive shell ops are caught and refused at multiple layers (CLI configs, runtime guard in `work`, Gemini policy file)
- Reviewers see prompts they can't auto-approve (rm -rf, sudo, force-push, etc.) — agent stays stuck so you notice and decide manually
- Gemini does NOT run in yolo mode (yolo has wiped repos for others). It runs in `auto_edit` — file-write tools auto-approved, shell prompts caught and approved by orchestrator
- All git operations log to a destructive-blocks file in the run directory

## Troubleshooting

**Reviewer hangs forever**
- Check the findings file: did it end with `## DONE`?
- Check the tmux pane: is the reviewer stuck on a permission prompt, modal popup, or "Error from provider" toast?
- Check the per-run log dir (`/tmp/work-<task>-r<n>-<ts>/`):
  - `error-retries.log` — provider errors + retries + peer-swaps + escalations
  - `popup-dismissals.log` — opencode modal popups dismissed
  - `approvals.log` — bash permission prompts auto-approved (and the command line)
  - `destructive-blocks.log` — destructive commands refused (agent stuck on purpose)
- Run `work permissions` for an aggregate view across all recent runs.

**Quorum never passes**
- Check `agents.json` — at least one alive agent per lineage?
- Check `agent-status` — any agent rate-limited?
- Check the per-run log dir for an `<agent>-findings.md` containing `⚠️ AGENT ESCALATED TO CLAUDE` — that means the orchestrator gave up after retries/swaps; Claude should pick the next step from the 3 numbered options in the stub.

**Reviewer reports findings about code that isn't in the diff**
- Likely cause: pack hit the diff truncation cap. Check `pack-meta.json` for `diff_bytes`. If it equals `50026`, truncation fired and the reviewer should have seen a `<reviewer-instruction priority="critical">` warning telling them to cross-check `<code_file>` blocks. If they hallucinated anyway, file an issue — that reviewer model isn't following the instruction.
- Workaround: bump `MAX_CTX_BYTES` higher in `work-pack-build` (default 800KB; reviewers have 1M+ context).

**Wrong file paths**
- Make sure `~/.local/bin` is in your `PATH`
- All scripts use `$HOME` or `Path.home()` — should work for any Unix user

## License

MIT — do whatever you want.

## Contributing

PRs welcome. Especially:
- Support for more CLI types (claude code as a reviewer, ollama agents, etc.)
- Better permission-prompt regex patterns for new CLI versions
- Smarter context discovery in `work-pack-build`

## Credits

Built incrementally over April 2026 by trial and error. The lineage diversity insight came from Reddit discussion about Claude blind spots in self-review loops. The /clear-between-rounds rule came from watching opencode CLIs go conversational mid-orchestration.

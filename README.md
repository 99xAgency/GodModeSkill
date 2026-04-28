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

A 15-second safety wakeup also re-checks for permission prompts (auto-approves safe ones, refuses destructive ones).

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

## Customization

- **Quorum rule**: edit `quorum_check()` in `work-converge`
- **Pack context**: edit `find_arch_docs()`, `discover_memory_files()`, `discover_journals()` in `work-pack-build`
- **Permission patterns**: edit `PROMPT_RE` and `DESTRUCTIVE_RE` in `work`
- **Modes**: edit `~/.claude/commands/work.md` for the slash command behavior

## Safety

- Destructive shell ops are caught and refused at multiple layers (CLI configs, runtime guard in `work`, Gemini policy file)
- Reviewers see prompts they can't auto-approve (rm -rf, sudo, force-push, etc.) — agent stays stuck so you notice and decide manually
- Gemini does NOT run in yolo mode (yolo has wiped repos for others). It runs in `auto_edit` — file-write tools auto-approved, shell prompts caught and approved by orchestrator
- All git operations log to a destructive-blocks file in the run directory

## Troubleshooting

**Reviewer hangs forever**
- Check the findings file: did it end with `## DONE`?
- Check the tmux pane: is the reviewer stuck on a permission prompt?
- Check `work` runtime guard logs (stderr) — did it auto-approve, or refuse?

**Quorum never passes**
- Check `agents.json` — at least one alive agent per lineage?
- Check `agent-status` — any agent rate-limited?

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

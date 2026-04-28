# 🧠 GodModeSkill

> **`/work`** — a single Claude Code command that runs every plan, feature, and bugfix past **3 different model families** before any merge.

Codex + Gemini + OpenCode (Kimi/DeepSeek) review your work in parallel. Quorum must agree, or Claude revises and retries. Zero token-burn while waiting. Auto-handles git. Always asks before merge.

---

## ✨ Why this exists

🤖 **Single-model AI coding fails silently.** Code looks reasonable, tests pass — but a subtle bug or design drift only shows up later.

👯 **Same-family models share blind spots.** Three Codex sessions reviewing each other is an echo chamber.

✅ **Lineage diversity is the unlock.** A different model family reading the same code from scratch catches a startling amount of what the author missed.

---

## 🚀 Quick start

### Option 1 — paste-and-go (recommended)

Open Claude Code and paste [`INSTALL.md`](INSTALL.md). Claude asks which CLIs you have, then installs everything.

### Option 2 — manual

```bash
git clone https://github.com/99xAgency/GodModeSkill.git
cd GodModeSkill
# Read skill/ layout, then copy each file to its target (see "Install layout" below)
```

---

## 🎯 Modes

| Mode | When to use | What happens |
|------|-------------|--------------|
| 📐 `plan` | New feature design | Propose → review → converge → write `planning/<feature>.md` |
| 🛠️ `implement` | Build the agreed plan | Design review → code → test → code review → PR → merge gate |
| 🐛 `major-bug` | Real bug fix | Failing test (TDD) → fix-plan review → code → test → code review → PR |
| ✏️ `minor-bug` | Typo / one-liner | Just fix it. No LLM gates. |

```
/work plan an oauth login flow for the admin panel
/work implement the planning/oauth-login.md design
/work fix bug: detail page crashes on null verdict
/work fix typo in nav header
```

Claude picks the mode, picks 3 reviewers, builds the pack, runs the loop, and asks for sign-off at the merge gate.

---

## 📋 Prerequisites

You need at least **3 different model families**:

- 🟣 **Claude Code** — any plan
- 🟠 **Codex CLI** — ChatGPT subscription (Plus or Pro)
- 🔵 **Gemini CLI** — Google AI Pro
- 🟢 **OpenCode CLI** — one of:
  - OpenCode Go subscription (gives Kimi + DeepSeek + others, flat-fee) ← **recommended**
  - Direct API keys (Moonshot, DeepSeek)

System tools: `tmux`, `jq`, `inotify-tools`, `git`, `python3`.

> ⚠️ Only have 2 families? The lineage quorum will fail (you need 1 of each: codex + gemini + opencode). You can edit `work-converge` to relax the rule, but you lose the diversity insight.

---

## 💸 Cost

**~$0 incremental** if you use plan-priced reviewers (ChatGPT subscription + Google AI Pro + OpenCode Go).

If you use API keys for Kimi/DeepSeek instead of OpenCode Go, expect **~cents per review** depending on pack size (~50KB packs typical).

---

## 🧬 How the lineage quorum works

`work-converge` parses each reviewer's XML response, extracts the `<verdict agree="true|false|partial">` block, and groups by lineage:

| Lineage | Sessions |
|---------|----------|
| 🟠 codex | `cdx-*` |
| 🔵 gemini | `gem-*` |
| 🟢 opencode | `kimi`, `deepseek`, … |

✅ **Quorum passes** only when **at least one agent of each lineage** returns `agree`.
🟡 Partial verdicts count as agree only if no critical/high findings.

| Outcome | Exit | Meaning |
|---------|------|---------|
| 🟢 all 3 agree | `0` | merge gate opens |
| 🔴 any disagree | `1` | revise + retry |
| ⚪ lineage missing | `2` | escalate to user |

---

## ⚡ How the wait is zero-token

When `/work` is waiting for reviewers, Claude is suspended on a **single Bash tool call** running `inotifywait`:

| Metric | Value |
|--------|-------|
| 🪙 Claude tokens during wait | **0** |
| 🔋 CPU during wait | **0** (kernel inotify) |
| ⏱️ Resume latency | **<1 s** (filesystem event) |

A **5-second safety wakeup** also re-checks for permission prompts, modal popups, and provider errors — see *Resilience* below.

---

## ✅ Pre-merge checklist

Before any merge, Claude fills out and shows you:

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

Catches a lot of "I think it's done" moments where the model has quietly drifted.

---

## 🛡️ Resilience — what happens when a reviewer breaks

`/work` handles each failure class automatically and only escalates to Claude when it can't recover.

| 💥 Failure | 🔍 Detection (≤5 s) | 🔧 Recovery |
|---|---|---|
| **Provider error** — Moonshot/DeepSeek 5xx, rate limit, gateway hiccup, "Error from provider", context overflow | `ERROR_RE` matches in pane | Retry the nudge **once**. If a 2nd error fires within 60 s: opencode lineage gets a **peer-swap** (kimi ⇄ deepseek). Other lineages get a stub findings file ending `## DONE` so the watcher exits fast and Claude takes over. |
| **TUI modal popup** — opencode "Select agent" / "Select model" / "Ask: No results found" (triggered by `/` or `@` at chunk boundaries during paste) | `OPENCODE_POPUP_RE` matches | Send `Escape` ×2 + re-nudge. **Pre-flight `Escape ×2`** also runs before every opencode nudge (defensive). |
| **Permission prompt** — CLI prompts the reviewer for `cat`/`tee`/`bash` execution | `PROMPT_RE` matches | Auto-approve with the right keystrokes (codex `y`, gemini `2`, opencode `Right Enter` for "Allow always"). Logs the command to `approvals.log`. |
| **Destructive command** — `rm -rf`, `sudo`, `git push --force`, `DROP TABLE`, ~25 patterns | `DESTRUCTIVE_RE` matches | 🛑 **NOT auto-approved.** Agent stays stuck, orchestrator prints `tmux attach -t <session>`, logs to `destructive-blocks.log`. |

**Peer-swap works for ALL lineages, not just opencode:**

| Lineage | Swap chain | When |
|---|---|---|
| 🟠 Codex | `cdx-1 → cdx-2 → cdx-3` (or however many you have) | One ChatGPT account hits its 5h/weekly limit |
| 🔵 Gemini | `gem-1 → gem-2 → …` | First Google AI account hits daily quota |
| 🟢 Opencode | `kimi ⇄ deepseek` | OpenCode Go gateway hiccup on one provider |

`try_lineage_swap` finds any alive agent of the same `type` in `agents.json` not already in the run, copies the prompt over, /clears the partner, nudges. Stays on subscription pricing — picks from agents you've already configured.

**See what's been stuck across runs:**

```bash
work status        # snapshot of current run: who's working, errored, popup-stuck, done
work status --watch # refresh every 2s
work permissions   # last 30 auto-approvals + repeating commands + destructive blocks
```

`work status` replaces ad-hoc `tmux capture-pane` debugging. Surfaces a one-line state per agent (WORKING / ERRORED / POPUP-STUCK / PERM-PROMPT / DONE) plus log-line counts.

`work permissions` surfaces bash patterns that prompt repeatedly. Add them to your CLI config (e.g. `~/.config/opencode/opencode.json`'s `permission.bash` block) so they're allowed permanently — no orchestrator round-trip.

---

## 💬 Per-CLI prompt format

Each CLI's TUI handles multi-line input differently, so `/work` builds a **per-CLI prompt**:

| CLI | 📝 Format | 💡 Why |
|---|---|---|
| 🟠 Codex | Multi-paragraph (bracketed-paste safe) | Handles `[Pasted Content N chars]` blocks correctly |
| 🔵 Gemini | **Single line** with `@/abs/path/to/pack.xml` (inline file attach) | Every `\n` is Submit — multi-paragraph paste fragments into N separate queries |
| 🟢 Opencode | **Single line**, plain-text path (no leading `/` or `@`) | tmux splits paste at ~1.5 KB chunks; `/` or `@` at a chunk boundary opens slash-command or agent-picker mid-paste |

---

## 📦 Pack truncation safety

When a review pack exceeds `MAX_CTX_BYTES` (**800 KB** default — sized for 1M-context reviewers like Opus 4.7 / Gemini 3.1 Pro / Kimi K2.6), `work-pack-build` drops:

1. Journals
2. Memory files
3. Diff (last resort, truncated to 50 KB)

When the diff itself gets truncated, the pack emits:

```xml
<diff truncated="true" original-bytes="N" shown-bytes="50000">…</diff>
<reviewer-instruction priority="critical">
  Verify each finding against the full <code_file> blocks
  before reporting — do NOT rely on the truncated diff alone.
</reviewer-instruction>
```

Prevents reviewers from anchoring on the truncated diff and hallucinating findings about the cut-off portion.

## 🔁 Cross-round packs are diff-only

When a review goes to round 2 (after disagreement + revision), the pack **drops `<related-memory>` and `<related-journals>`** — they don't change between rounds and the reviewer already saw them in round 1. Typical saving: **~65% pack size reduction** on round 2+.

Replaced with a stub:

```xml
<stable-context-skipped reason="round-2-no-change-since-round-1"
                        memory-files-omitted="6" journals-omitted="3"/>
```

Architecture docs, code files, diff, and `<prior-rounds>` (which grows each round) are still included — all the things that matter for re-review. Reviewers are reminded in the `<ask>` block that round-2+ context was intentionally trimmed.

## 🎯 Self-consistency check (anti-hallucination)

Findings now require structured evidence:

```xml
<finding severity="critical" category="bug">
  <claim>Unquoted variable in test causes syntax error on empty input.</claim>
  <evidence>
    <file-path>scripts/greet.sh</file-path>
    <line-number>5</line-number>
    <quoted-line><![CDATA[if [ $name == "admin" ]; then]]></quoted-line>
  </evidence>
  <suggestion>Quote it: if [ "$name" = "admin" ]; then</suggestion>
</finding>
```

`work-converge` greps the cited file for the `<quoted-line>` (whitespace-tolerant). Findings whose quote can't be located are flagged `verified: false` — likely hallucinations. The output JSON exposes:

```json
{ "verified_findings": 7, "unverified_findings": 1,
  "unverified_blockers": [ /* critical/high findings that failed verification */ ] }
```

Claude can then weight unverified findings lower or ignore them. Direct counter to the gem-1-style anchor-bias hallucination class.

---

## ⚙️ Install layout (manual install only)

```
skill/work*           → ~/.local/bin/
skill/agent-status    → ~/.local/bin/
skill/commands/work.md → ~/.claude/commands/work.md
skill/agent-sessions/ → ~/.config/agent-sessions/
                        (rename agents.json.template → agents.json, edit)
skill/gemini/settings.snippet.json → merge into ~/.gemini/settings.json
skill/gemini/GEMINI.snippet.md     → append to  ~/.gemini/GEMINI.md
skill/gemini/policies/00-deny-destructive.toml → ~/.gemini/policies/
skill/opencode/opencode.snippet.json → merge into ~/.config/opencode/opencode.json
skill/examples/AGENTS.md → put in each opencode session working dir
```

Make all `skill/work*` files executable: `chmod +x ~/.local/bin/work*`

---

## 🔧 Customization

| What | Where |
|---|---|
| Quorum rule | `quorum_check()` in `work-converge` |
| Pack cap + context discovery | `MAX_CTX_BYTES` (800 KB) + discovery fns in `work-pack-build` |
| Auto-approve patterns | `PROMPT_RE` in `work` |
| Destructive block list | `DESTRUCTIVE_RE` in `work` |
| Provider-error patterns | `ERROR_RE` in `work` |
| Opencode popup patterns | `OPENCODE_POPUP_RE` in `work` |
| Opencode peer-swap map | `OPENCODE_PARTNER` in `work` (default `kimi ⇄ deepseek`) |
| Mode workflows | `~/.claude/commands/work.md` |

---

## ➕ Adding more agents

Edit `~/.config/agent-sessions/agents.json`. New entries are auto-included in the LRU rotation for their lineage.

- 4th Codex on a new ChatGPT account → `cdx-4` with its own `CODEX_HOME`
- 2nd Gemini → `gem-2` (parallel review)
- Claude reviewer in tmux → `claude-1` with `type: "claude"` (extend `work-converge` quorum logic)

---

## 🛟 Troubleshooting

<details>
<summary><strong>🪧 Reviewer hangs forever</strong></summary>

- Did the findings file end with `## DONE`?
- Is the tmux pane stuck on a permission prompt, modal popup, or "Error from provider" toast?
- Check the per-run log dir `/tmp/work-<task>-r<n>-<ts>/`:
  - `error-retries.log` — provider errors + retries + peer-swaps + escalations
  - `popup-dismissals.log` — opencode modal popups dismissed
  - `approvals.log` — bash prompts auto-approved (with command line)
  - `destructive-blocks.log` — destructive commands refused
- Run `work permissions` for the aggregate view.

</details>

<details>
<summary><strong>🚫 Quorum never passes</strong></summary>

- `agents.json` has at least one alive agent per lineage?
- `agent-status` shows nobody rate-limited?
- Look in the per-run log dir for an `<agent>-findings.md` containing `⚠️ AGENT ESCALATED TO CLAUDE` — orchestrator gave up after retries/swaps. Pick from the 3 numbered options in the stub.

</details>

<details>
<summary><strong>👻 Reviewer reports findings about code that isn't in the diff</strong></summary>

Likely the pack hit the diff truncation cap. Check `pack-meta.json` for `diff_bytes` — if it's `50026`, truncation fired. The reviewer should have seen a `<reviewer-instruction priority="critical">` warning. If they hallucinated anyway, the model isn't following the instruction — file an issue.

**Workaround:** bump `MAX_CTX_BYTES` higher in `work-pack-build`.

</details>

<details>
<summary><strong>📁 Wrong file paths</strong></summary>

- `~/.local/bin` in `$PATH`?
- All scripts use `$HOME` / `Path.home()` — should work for any Unix user.

</details>

---

## 🔒 Safety guarantees

- 🛑 Destructive shell ops blocked at **3 layers**: CLI configs, runtime guard in `work`, Gemini policy file
- 👀 Destructive prompts → agent stays **visibly stuck** so a human notices and decides
- 🚫 **Gemini does NOT run in `yolo` mode** — `yolo` has wiped repos for others (write_file overwriting source with empty content). It runs in `auto_edit`: file-write tools auto-approved, shell prompts caught and approved by orchestrator
- 📜 All blocks logged to `destructive-blocks.log` in the run directory

---

## 📜 License

MIT — do whatever you want.

---

## 🤝 Contributing

PRs welcome. Especially:

- Support for more CLI types (Claude Code as a reviewer, Ollama agents, …)
- Better permission-prompt regex patterns for new CLI versions
- Smarter context discovery in `work-pack-build`

---

## 🌱 Credits

Built incrementally over April 2026 by trial and error. The **lineage diversity** insight came from Reddit discussion about Claude blind spots in self-review loops. The **`/clear` between rounds** rule came from watching opencode CLIs go conversational mid-orchestration. The **provider-error escalation** + **kimi ⇄ deepseek peer-swap** came from real OpenCode Go gateway hiccups. The **single-line gemini prompt** came from spotting that Gemini's TUI was treating each `\n` as Submit.

# GodModeSkill installer prompt

Open Claude Code and paste everything between the `=====` markers below into a fresh conversation. Claude will ask you which CLIs you have, then install the whole `/work` orchestration system end-to-end.

You'll need permission to run `sudo` for installing system tools (`tmux`, `jq`, `inotify-tools`) if they aren't already on your machine.

---

```
=================================================================
GODMODESKILL INSTALLER — paste this entire block into Claude Code
=================================================================

You are going to install GodModeSkill on this machine — a multi-LLM cross-review workflow that adds a `/work` command to Claude Code. The command orchestrates code review consensus across 3 different model families (Codex + Gemini + OpenCode) before any merge.

Reference repo: https://github.com/99xAgency/GodModeSkill

## STEP 1: Discover what I have

Before building anything, ask me which CLIs and subscriptions I have. Use this exact numbered format and wait for my reply:

```
Which CLIs do you have set up? Reply with the relevant numbers + answers.

CODEX (OpenAI ChatGPT subscription)
  1. How many separate ChatGPT accounts will you use? (typical: 1-3)

GEMINI (Google AI subscription)
  2. Do you have Gemini CLI authed? (yes / no)

OPENCODE (Kimi / DeepSeek)
  3. OpenCode Go subscription, direct API keys, or none? (go / api / none)

SYSTEM TOOLS
  4. tmux installed? (Claude can check via `which tmux`)
  5. jq installed?
  6. inotify-tools installed?

PROJECT
  7. Is there a specific project dir you want to use as the default Claude
     working dir? (e.g. ~/dev/myproject) — used for setting up planning/ etc.
```

After I reply, install missing system tools with `sudo apt install -y <pkg>` (Ubuntu/Debian) or `brew install <pkg>` (macOS).

If I don't have at least 3 different model families (1 codex + 1 gemini + 1 opencode), STOP and warn me — `/work`'s lineage quorum requires all three. Ask if I want to install the missing ones first or proceed with a relaxed quorum.

## STEP 2: Clone the source files

Clone the GodModeSkill repo to a working dir:

```bash
git clone https://github.com/99xAgency/GodModeSkill.git ~/dev/GodModeSkill
```

If git clone fails (no network, etc.), tell me and stop.

## STEP 3: Install the orchestrator binaries

Copy these from `~/dev/GodModeSkill/skill/` to `~/.local/bin/`:
- `work` (main bash orchestrator)
- `work-pack-build` (Python XML pack assembler)
- `work-converge` (Python lineage-quorum checker)
- `work-fleet-restart` (tmux session restarter)
- `agent-status` (fleet status table + reset-time setter)

Make them executable: `chmod +x ~/.local/bin/work* ~/.local/bin/agent-status`

Verify `~/.local/bin` is in my `PATH`. If not, append `export PATH="$HOME/.local/bin:$PATH"` to my `~/.bashrc` or `~/.zshrc` and tell me to reload my shell.

## STEP 4: Install the Claude slash command

Copy `~/dev/GodModeSkill/skill/commands/work.md` → `~/.claude/commands/work.md`

If `~/.claude/commands/` doesn't exist, create it.

## STEP 5: Set up agent fleet config

Copy `~/dev/GodModeSkill/skill/agent-sessions/` → `~/.config/agent-sessions/`

Then EDIT `~/.config/agent-sessions/agents.json` based on what I told you in Step 1:

- If I said "1 codex account": keep only `cdx-1` entry
- If I said "2 codex accounts": keep `cdx-1` and `cdx-2`. cdx-2 needs a separate `CODEX_HOME=~/.codex-cdx-2` directory. Tell me to log into the second ChatGPT account in cdx-2 after first launch.
- If I said "3 codex accounts": keep cdx-1/2/3 with separate CODEX_HOMEs.
- If I said "no opencode": remove kimi and deepseek entries (warn that lineage quorum will then require relaxation).
- If I said "opencode api keys" instead of Go: edit kimi and deepseek launch commands to use `moonshot/kimi-k2.6` and `deepseek/deepseek-v4-pro` instead of `opencode-go/...`. Also tell me to put MOONSHOT_API_KEY and DEEPSEEK_API_KEY in `~/.config/opencode/.env` (mode 600).
- If I said "no gemini": remove gem-1 entry (warn about lineage quorum).

Rename `agents.json.template` → `agents.json` after editing.

## STEP 6: Configure Codex (if I have it)

For each codex account I have:
- Make sure `~/.codex-<name>/config.toml` has:
  ```toml
  approval_policy = "never"
  sandbox_mode = "workspace-write"
  [sandbox_workspace_write]
  network_access = true
  [projects."<my-default-project-dir>"]
  trust_level = "trusted"
  ```
- For multi-account: copy `~/.codex/config.toml` to `~/.codex-cdx-2/`, `~/.codex-cdx-3/` etc. NEVER copy `~/.codex/auth.json` — each account has its own.

## STEP 7: Configure Gemini (if I have it)

- Merge `~/dev/GodModeSkill/skill/gemini/settings.snippet.json` into my existing `~/.gemini/settings.json` (don't replace the whole file; just add the `general.defaultApprovalMode = "auto_edit"` and `model.name = "gemini-3.1-pro-preview"` keys).
- Copy `~/dev/GodModeSkill/skill/gemini/policies/00-deny-destructive.toml` → `~/.gemini/policies/`
- Append the contents of `~/dev/GodModeSkill/skill/gemini/GEMINI.snippet.md` to my existing `~/.gemini/GEMINI.md` (or create the file if it doesn't exist).

## STEP 8: Configure OpenCode (if I have it)

- Merge `~/dev/GodModeSkill/skill/opencode/opencode.snippet.json` into my existing `~/.config/opencode/opencode.json`. The `permission` block is the critical part — `external_directory: allow` is required for reviewers to read /tmp/work-* packs.
- Create working dirs:
  ```bash
  mkdir -p ~/dev/kimi-session ~/dev/deepseek-session
  cp ~/dev/GodModeSkill/skill/examples/AGENTS.md ~/dev/kimi-session/AGENTS.md
  cp ~/dev/GodModeSkill/skill/examples/AGENTS.md ~/dev/deepseek-session/AGENTS.md
  ```

## STEP 9: Set up the codex-bridge nudgers

`/work` uses tmux nudger scripts to send prompts into each tmux session. The repo doesn't ship these (they're tmux-paste-buffer specific). Create them:

```bash
mkdir -p ~/dev/codex-bridge
```

Create `~/dev/codex-bridge/nudge` with this content (atomic paste-buffer + Enter for bubbletea TUIs):

```bash
#!/usr/bin/env bash
set -euo pipefail
SESSION="${CDX_TMUX_SESSION:-cdx}"
PROMPT="${1:-$(cat)}"
tmux has-session -t "$SESSION" 2>/dev/null || { echo "no session $SESSION" >&2; exit 2; }
tmux set-buffer -b nudge "$PROMPT"
tmux paste-buffer -b nudge -t "$SESSION"
sleep 0.5
tmux send-keys -t "$SESSION" Enter
sleep 0.3
tmux send-keys -t "$SESSION" Enter
```

Make it executable: `chmod +x ~/dev/codex-bridge/nudge`

Create symlinks for the other CLI types (they all use the same paste-buffer mechanism, just default to different session names):

```bash
cd ~/dev/codex-bridge
for n in nudge-gem nudge-kimi nudge-deepseek; do
  cp nudge "$n"
done
# Patch each to default to its session name
sed -i 's|CDX_TMUX_SESSION:-cdx|GEM_TMUX_SESSION:-gem-1|' nudge-gem
sed -i 's|CDX_TMUX_SESSION:-cdx|KIMI_TMUX_SESSION:-kimi|' nudge-kimi
sed -i 's|CDX_TMUX_SESSION:-cdx|DEEPSEEK_TMUX_SESSION:-deepseek|' nudge-deepseek
```

## STEP 10: Spawn the tmux sessions

Run `~/.local/bin/work-fleet-restart` to spawn all configured agents:

```bash
work-fleet-restart --dry-run    # preview first
work-fleet-restart              # do it
```

For each Codex session that's never been authed: tell me to attach (`tmux attach -t cdx-1`) and sign in with the right ChatGPT account, then detach with Ctrl-B then D.

For OpenCode sessions: tell me to attach and run `opencode providers login` to authenticate the Go plan (or set up the API keys in `.env`).

For Gemini: should auth automatically if `~/.gemini/oauth_creds.json` exists.

## STEP 11: Verify

Run these and show me the output:

```bash
work pick-agents       # should print 1 codex + 1 gemini + 1 opencode JSON
agent-status            # should show all alive agents
work --help             # should print subcommand list
```

If anything fails, diagnose and fix before continuing.

## STEP 12: Smoke test (optional but recommended)

If I want, run a tiny `/work` review on a fake task to confirm the pipeline works end-to-end. Use `--mode plan --task "tiny test"` with a 60-second timeout. Tell me what the reviewers said.

## STEP 13: Hand-off

Tell me:
1. `/work` is installed. Try: `/work plan a small feature` or similar.
2. Where the slash command spec lives so I can customize it: `~/.claude/commands/work.md`
3. Where to add more agents later: `~/.config/agent-sessions/agents.json`
4. The full README is at `~/dev/GodModeSkill/README.md`

DONE.
=================================================================
END OF INSTALLER PROMPT
=================================================================
```

## After install

Try it:

```
/work plan a small feature for testing the workflow
```

Claude will pick 3 reviewers, build an XML pack with auto-discovered context, fan it out, wait for consensus, and walk you through any disagreements.

## Updating

```bash
cd ~/dev/GodModeSkill && git pull
cp skill/work* ~/.local/bin/
chmod +x ~/.local/bin/work*
```

The slash command spec and snippets are intentionally separate copies — change them freely without affecting future updates.

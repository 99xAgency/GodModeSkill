# bin/ — Fleet launcher scripts

Scripts that run outside Claude Code to manage the multi-LLM fleet environment.

## godmode

Zellij layout launcher that opens a tiled terminal with all fleet agents side-by-side.

**Requires:** [zellij](https://zellij.dev/), tmux, and pre-existing tmux sessions for each agent (created by `work-fleet-restart`).

### What it does

1. Generates a temporary `.kdl` layout file scoped to the current project directory
2. Opens zellij with two tabs:
   - **Fleet** — three vertical panes, each attached to an agent's tmux session (cdx-1, claude-sonnet, deepseek)
   - **Status** — `agent-status` with manual refresh (press Enter)
3. Cleans up the temp layout on exit

### Usage

```bash
cd /path/to/project
godmode
```

Session names are project-scoped: `{agent}-{project_slug}`, where the slug is `basename $(pwd)`. Run `work-fleet-restart` first to create the tmux sessions.

### Install

```bash
cp bin/godmode ~/.local/bin/godmode
chmod +x ~/.local/bin/godmode
```

The installed copy at `~/.local/bin/godmode` is the one that actually runs. This repo copy is the source of truth — after editing, re-copy to `~/.local/bin/`.

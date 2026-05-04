---
description: Multi-LLM workflow orchestrator with lineage-weighted quorum. Routes to plan / implement / major-bug / minor-bug modes. Builds XML packs, fans to reviewers (1 per enabled lineage), waits for `## DONE` (inotifywait on Linux, poll on macOS — zero token burn), loops on disagreement. Auto-modifies git; asks before merge.
---

# /work — multi-LLM workflow

Single command for the four daily workflow shapes. Modes:

- **plan** — propose, multi-LLM review, converge, write `planning/<feature>.md`
- **implement** — design review → code → test → code review → PR → merge gate
- **major-bug** — failing test (TDD) → fix-plan review → code → test → code review → PR
- **minor-bug** — fast path: fix → test → commit (NO LLM gates)

The bash binary at `~/.local/bin/work` is the executor. THIS command is the conductor — Claude orchestrates phases, asks the user where required, and never blindly merges.

## Disambiguation — always ask if unclear

If the user request doesn't make the mode obvious, ask in numbered form:

```
Which workflow?
1. Plan a new feature (with multi-LLM review)
2. Implement (PR + multi-LLM code review + merge)
3. Major bug fix (failing test + multi-LLM review + PR)
4. Minor bug (just fix it, no review)
```

## Hard rules (non-negotiable)

1. **Never hardcode agent names.** Always call `work pick-agents` (LRU rotation across cdx-1/2/3, automatically uses cdx-4 / gem-2 if added later to `agents.json`).
2. **Lineage diversity required.** Quorum needs ≥1 agent per enabled lineage agreeing. Lineages are detected from `agents.json` types — disabled or unconfigured lineages don't block quorum. Enforced by `work-converge` — Claude does NOT override the quorum rule lightly.
3. **`/clear` between different PRs.** Handled automatically by `work` based on `task_id` change. Don't pass `--clear` flags by hand.
4. **Event-driven wait.** `work review` blocks on `inotifywait` (Linux) or 5s poll (macOS) — zero tokens during wait. Do NOT add monitoring loops in Claude.
5. **Auto-modify git** for branch / commit / PR open / push. NEVER auto-merge — always ask user via the pre-merge checklist.
6. **All user clarification = numbered options, simple English.**
7. **Disagreement loop**: Claude (the proposer) revises, then re-runs `work review --round N+1`. Reviewers see prior rounds via `--prior-rounds-file`. Max 3 rounds before escalating to user.

---

## Mode 1: plan

Use when user wants to design a new feature.

### Phase A — derive the task

1. Get task statement from user. If vague, ask numbered clarifying questions.
2. Derive `task_id`:
   - If on a feature branch (`feat/foo`, `feature/foo`): use `foo`
   - Else: ask user for a slug (numbered: 1. derive from feature name, 2. user provides)
3. Decide planning doc path: `planning/<task_id>.md` in the active repo. Confirm with user.

### Phase B — write the proposal

1. Write the initial proposal as `planning/<task_id>.md`. Cover: problem, approach, alternatives considered, edge cases, risks, test strategy.
2. Show the user the proposal — confirm before review.

### Phase C — multi-LLM review (loop)

```bash
work review \
  --mode plan \
  --task "<task statement>" \
  --task-id "<task_id>" \
  --round 1 \
  --planning-doc "planning/<task_id>.md"
```

Bash blocks (event-driven) until all reviewers write `## DONE`. Returns JSON with `decision` field.

**Process the result:**
- `decision: "agree"` → proceed to Phase D
- `decision: "disagree"` → revise the planning doc based on the per-agent findings. Build a `prior-rounds-file` summarizing what changed between rounds. Re-run with `--round 2 --prior-rounds-file ...`. Max 3 rounds.
- `decision: "incomplete"` → an agent died/rate-limited. Ask user (numbered): 1. retry that agent, 2. swap in another via `work pick-agents --exclude <dead>`, 3. abort.

After 3 rounds without `agree`, ask user:
```
3 rounds without quorum. Disagreeing reviewers: <list>. What now?
1. Override and proceed (give reason — recorded in plan doc)
2. Revise the plan further (round 4)
3. Park this — needs human design discussion
```

### Phase D — finalize

1. Append a `## Reviewer agreement` section to the planning doc with the lineage-status line and any caveats.
2. Commit `planning/<task_id>.md` to the current branch.
3. Confirm done.

---

## Mode 2: implement

Use when there's an approved plan (or user says "just build X" with confidence).

### Phase A — preflight

1. Verify a planning doc exists. If not, ask numbered: 1. run /work plan first, 2. proceed without plan (record reason), 3. abort.
2. Check git state:
   - On main? → ask: 1. create feature branch, 2. abort (refuse to commit to main)
   - Already on feature branch? → use it
3. Set `task_id` from branch name.

### Phase B — design review (LLMs see plan + relevant code, NO diff yet)

```bash
work review --mode plan --task "<plan summary>" --task-id "<task_id>" \
  --round 1 --planning-doc "planning/<task_id>.md"
```

Same loop semantics as Mode 1 Phase C.

### Phase C — implement

1. Write code per agreed plan.
2. After every Edit/Write on code files, Read back the changed section to confirm it applied. Per CLAUDE.md verification rule.
3. Run typecheck / lint / format.

### Phase D — test gate (BLOCKING)

1. Run the test suite (or relevant subset for the change).
2. If RED: fix and re-run. Don't proceed until GREEN.

### Phase E — code review (LLMs see diff)

```bash
work review --mode implement --task "<what was built>" --task-id "<task_id>" \
  --round 1 --planning-doc "planning/<task_id>.md"
```

`work-pack-build` automatically pulls `git diff` against merge-base with main. Loop on disagreement (max 3 rounds).

### Phase F — git ops (auto)

1. Commit with conventional message (`feat: <task_id> — ...`).
2. Push branch.
3. Open PR via `gh pr create` with summary including reviewer-consensus block from `converge.json`.
4. Wait for CI (or skip if no CI).

### Phase G — pre-merge checklist (ASK USER)

Show this exact block before the merge prompt. Claude self-fills the answers based on what actually happened in the session.

```
═══════════════════════════════════════════════════
PRE-MERGE CHECKLIST — Task: <task_id>  PR: #<num>
═══════════════════════════════════════════════════
1. Coding principles (CLAUDE.md):
   <followed | drifted: what + why>

2. Architecture guidelines (planning/<task_id>.md + CODING-PRINCIPLES.md):
   <followed | drifted: what + why>

3. Tests:
   <pass: N/M | fail: which>

4. Reviewer consensus (lineage-weighted):
   <agree: round N | overridden: reason>
═══════════════════════════════════════════════════

Merge?
1. Yes — merge now (gh pr merge --squash)
2. No — fix drift / failures first
3. Override and merge anyway (give reason — appended to PR comment)
```

User picks 1/2/3. Only on `1` (or `3` with reason) does Claude run `gh pr merge`.

---

## Mode 3: major-bug

Same shape as implement but TDD-first.

### Phase A — preflight

Same as Mode 2 Phase A.

### Phase B — write failing test (REPRO)

1. Reproduce the bug via a failing unit/integration test in the repo's test dir.
2. Run it; capture the failure output.
3. Show user the failing test + output. Confirm it captures the actual bug (numbered: 1. yes proceed, 2. no, refine).

### Phase C — fix-plan review (LLMs see failing test + diagnosis, NO patch)

Write a brief fix plan to `planning/bugfix-<task_id>.md`: root cause, proposed fix, regression risks.

```bash
work review --mode major-bug \
  --task "<bug description>" \
  --task-id "<task_id>" \
  --round 1 \
  --planning-doc "planning/bugfix-<task_id>.md" \
  --failing-test "<path/to/failing_test.py>" \
  --failing-test-output "/tmp/work-failing-output.txt"
```

Loop on disagreement (max 3 rounds).

### Phase D — implement fix

Same discipline as Mode 2 Phase C.

### Phase E — test gate

Failing test must now PASS. Full suite must not regress.

### Phase F — code review

```bash
work review --mode major-bug \
  --task "fix: <task_id>" \
  --task-id "<task_id>" \
  --round 1 \
  --planning-doc "planning/bugfix-<task_id>.md" \
  --failing-test "<path>"
```

Diff included automatically.

### Phase G — git ops + Phase H pre-merge

Same as Mode 2 Phase F + G.

---

## Mode 4: minor-bug

Fast path. NO LLM gates.

1. Reproduce or read the bug.
2. Fix.
3. Run relevant tests (single test file is fine, not full suite for trivial fixes).
4. Commit (`fix: <description>`).
5. Push if on a branch; ask before opening PR.

If the user invokes `/work` for what looks like minor-bug but the diff turns out to be >50 lines or touches >3 files, ask:
```
This grew larger than a minor bug. Switch modes?
1. Treat as major-bug (add LLM review)
2. Stay minor-bug (proceed without review, on you)
```

---

## How disagreement loops work in practice

After `work review` returns `decision: "disagree"`:

1. Read each `<agent>-findings.md` in the out dir.
2. Identify which findings are valid vs which are reviewer hallucinations (verify against actual code).
3. Revise the proposal/plan/code to address valid findings.
4. Build `prior-rounds-file` — a markdown summary like:

```
## Round 1 (rejected — codex + gemini disagreed)

### Reviewer findings addressed:
- gem-1: missing edge case for empty input → added handler at foo.py:42
- cdx-1: race condition in queue claim → switched to FOR UPDATE SKIP LOCKED

### Reviewer findings rejected (with reason):
- kimi: suggested adding retry logic → out of scope, will track separately
```

5. Re-run `work review --round 2 --prior-rounds-file <path>`.

Reviewers will see prior rounds and judge whether their previous findings have been addressed — they're prompted not to invent new critiques unless the revision opened them.

---

## Output discipline

End each significant phase with a one-line status:
```
✓ Phase D done — quorum achieved round 2 (codex+gemini+opencode all agree)
```

Don't dump full reviewer findings in chat. Summarize. The full files are in `<out>/SUMMARY.md` and `<out>/<agent>-findings.md` — link them.

## When to skip /work entirely

- Pure conversation / answering questions
- Reading code without modifying
- One-line typo fixes (just edit)
- Configuration tweaks that aren't shipping anywhere

The user invoking `/work` IS the trigger. Don't auto-launch from any other slash command.

## Escape hatch

User can always say `/work override "<reason>"` to skip the next quorum gate. Recorded in the planning doc / PR comment for traceability. Use sparingly.

## Files this command controls

- `~/.local/bin/work` — main bash orchestrator (subcommands: pick-agents, review, state-get, state-set)
- `~/.local/bin/work-pack-build` — Python XML pack assembler with auto context discovery
- `~/.local/bin/work-converge` — Python response parser + lineage-weighted quorum
- `~/.work/state.json` — last task_id (for /clear decisions)
- `~/.work/agent-lru.json` — per-agent last-used timestamp for LRU rotation

## When `/review-llm` should be used instead

Don't use `/review-llm` for new work — `/work` absorbs it. The old slash command remains on disk for ad-hoc one-off fan-outs but is deprecated. Anything PR/feature/bug-shaped goes through `/work`.

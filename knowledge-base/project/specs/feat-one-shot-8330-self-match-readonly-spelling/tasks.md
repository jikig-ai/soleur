# Tasks: hooks-self-match-guard-readonly-ps-grep-spelling

Plan: `knowledge-base/project/plans/2026-09-19-fix-hooks-self-match-guard-readonly-ps-grep-spelling-plan.md` (issue #8330). Phase numbers mirror the plan's §Implementation Phases.

## Phase 0: Preconditions (verify, no edits)

- [ ] 0.1 Run `bash .claude/hooks/pkill-self-match-guard.test.sh` and record the baseline `=== 14 verdicts, 0 failed ===`
- [ ] 0.2 Confirm `strip_heredocs()` and `emit_incident()` exist in `.claude/hooks/lib/incidents.sh` (one grep hit each)
- [ ] 0.3 Re-measure the wrapper premise from the Bash tool: `ps -o args= -p $$` begins with `/usr/bin/bash -c`; note the date for the hook header
- [ ] 0.4 Edit only with Write/Edit tools; never write the hook or suite via a Bash heredoc and never type a probe carrying the signal spelling (the live hook denies both — it did so twice during planning)

## Phase 1: RED — suite rows first

- [ ] 1.1 Add deny rows D1–D19 to `.claude/hooks/pkill-self-match-guard.test.sh` exactly as enumerated in the plan's §Test Scenarios (D11 as a dedicated single-envelope case using `jq -s length` and discriminating on the `-f` reason's `BLOCKED:` prefix; D4 uses `-i NGINX`; D17 self-matching pipeline first; D18 `fgrep`; D19 the accepted `;`-in-quotes false deny)
- [ ] 1.2 Add allow rows A1–A23, with A6 as an inline synthesized doc-shaped heredoc fixture preceded by its non-vacuity control (`ps -eo args | grep -c` present) AND its positive control (same text without the heredoc wrapper → deny); A12/A14 carry a QUOTED inner pattern; A23 is the `egrep` alias of A1
- [ ] 1.3 Add the Devin `exec` wire-name row for the read-only arm (D2's command → deny)
- [ ] 1.4 Add the telemetry row using a fresh `INCIDENTS_REPO_ROOT=$(mktemp -d)` (+ `.claude/`) per invocation: D2 → one `pkill-self-match-guard-readonly` line; D11 → no line (the envelope count is D11's own assertion)
- [ ] 1.5 Raise `MIN_ASSERTIONS` to `N − 3` from the printed verdict total (expected around 60; AC1 checks `N >= 55`)
- [ ] 1.6 Run the suite: every new D row FAILs against the unmodified hook (RED)

## Phase 2: GREEN — the read-only arm in `.claude/hooks/pkill-self-match-guard.sh`

- [ ] 2.1 Header: rewrite the opening summary (drop "when <pat> also appears ELSEWHERE"), add the read-only spelling, measured wrapper line with re-verify command + date, measured counts, #8231 anecdote (durations from the issue body), simulation rule, `-v` honouring, fail-open arms, the new-idiom notes (`while [[ =~ ]]` consumption loop, `${BASH_REMATCH[n]-}`), and the accepted-gap list (the only place gaps are recorded, including the snapshot/`grep-rewrite` prefix false-allow and the D19 false deny); keep the `-f` mechanism paragraphs verbatim
- [ ] 2.2 Step-0 pre-trigger: `ps` token at a command boundary on raw `$CMD` before any fork; otherwise exit 0
- [ ] 2.3 Source `lib/incidents.sh` fail-soft; if `strip_heredocs` is undefined, WARN to stderr and `exit 0` before the arm (fail-open, no shim); define `emit()` (background-poll-prefer-monitor precedent); define `TO=()` with the `command -v timeout` guard (`TO=(timeout -k 1 2)`)
- [ ] 2.4 Restructure the `-f` arm to `if <trigger>; then <existing reason + envelope>; exit 0; fi` — reason string byte-identical, no `emit` added
- [ ] 2.5 Implement the read-only arm per plan §Proposed Solution steps 1–4: `SCAN` from `strip_heredocs`, `MODEL="bash -c ${CMD}"` newlines preserved, args-showing/self-listing `ps` predicate with the `-p`/`--pid`/`-q`/`--quick-pid` exemption, per-pipeline stage walk over `SCAN` with the terminator set (walk ends fail-open at any non-matcher stage), grep/awk pattern extraction and flavour rules, `-v` honouring, per-pipeline fail-open via `continue`, `"${TO[@]}" command grep -q … <<<"$MODEL"` with rc 0 = match / 1 = no match / anything else fail-open, `${BASH_REMATCH[n]-}` on every optional group
- [ ] 2.6 Deny envelope `{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:…}}` with reason = read-only paragraph + recipe block (one-off look: `| grep -v grep`, `pgrep -a <name>`; count: `list_runs`, exact-argv awk slot, captured PID) with `\$1`/`\$2`/`\$!`/`\"` escaped; `emit "pkill-self-match-guard-readonly" deny "<first 80 chars>" "$CMD"` before the envelope
- [ ] 2.7 Run the suite green; run `bash .claude/hooks/grep-q-pipe-guard.test.sh`, `bash .claude/hooks/incident-sandbox-coverage.test.sh` and `bash .claude/hooks/hookeventname-coverage.test.sh`

## Phase 3: Mutation battery, doc verification, docs

- [ ] 3.1 Drive Guard Contract rows M1–M13 and H1–H4 on scratch copies (H1 deletes four rows; H3 has two edits); record one RED evidence line per row for the PR body (AC8)
- [ ] 3.2 Verify detection against the repo docs once and record both allows for the PR body (AC4): the `review/SKILL.md` bullet anchored on "A process count that greps its own pattern can never reach zero", and the learning section "### The instruments that were counting themselves" with its one signal-spelling line filtered by `grep -vE` over the `-f` trigger regex — each wrapped as `cat > /dev/null <<'EOF' … EOF` and piped through the hook → empty stdout; build the probe from variables so the session's own command never carries the signal spelling; leave the probe command as a comment in the suite for reproducibility
- [ ] 3.3 `plugins/soleur/skills/review/SKILL.md`: replace "the `ps … | grep` spelling is unguarded (#8330), which is the guard-written-against-one-spelling shape" with "the `ps … | grep` spelling is guarded since #8330 (the hook simulates the pattern against `bash -c <command>`)"
- [ ] 3.4 `.claude/hooks/README.md` `## Hook roster`: add the row for `pkill-self-match-guard.sh` (Denies 2, rule id `pkill-self-match-guard-readonly`, note the `-f` arm emits none) after the `worktree-write-guard.sh` row
- [ ] 3.5 Run `TEST_GROUP=scripts bash scripts/test-all.sh` (or the per-suite fallback in AC12)

## Phase 4: Acceptance criteria check

- [ ] 4.1 Walk AC1–AC14 in the plan; every command passes as written
- [ ] 4.2 Leave a comment on #7994 noting the new arm scans `strip_heredocs` while the `-f` arm stays on raw `$CMD` (disposition: acknowledge)

---
title: "A dispatch arm's grader must admit the first-apply verb of every resource it -targets — and pool pins bind by resolved IP, not member name"
date: 2026-11-01
tags: [plan-gates, terraform, cf-lb-overlay, dispatch-arms, doppler, followthroughs, 6027, 11181]
---

# Learning: grade the *plan the arm can actually emit*, and trace every resource's reachability end-to-end

## Problem

PR #11766 (web-2 drained pool member + two gated dispatch arms) passed a 12-seat review
that found the arm could never run: `cf_lb_gate_ga_pool_update` admitted only
`["update"]` verbs, but its `-target` set included the NEW
`cloudflare_notification_policy.web_lb_health`, whose first plan necessarily emits
`["create"]`. Routine apply excluded it (`OPERATOR_APPLIED_EXCLUSIONS`), so the arm was
the policy's only apply path — and the arm self-refused on first dispatch, verified by
five seats independently executing the grader. The suite even pinned the defective
behavior as correct (the only pass fixture gave the policy `["update"]` — a shape no
real first plan can emit).

A second cluster: the drain pin checked the weight of origins **named** `web-2` — a
renamed or duplicated origin at web-2's IP with `weight=1` passed, defeating the drain
the arm exists to enforce. Origins checks were ⊆-only: a pool dropping web-1 entirely
passed (zero serving origins = outage). And bare `exit 0` from the §(c) gate chain was
consumed as authorization — the wrapper has a standby branch that prints
`SHAPE-ONLY — NOT weight-flip authorization` and exits 0 without evaluating the flip
preconditions.

## Solution

1. **Per-verb allow-sets, not a uniform verb.** Pool/LB admit `["update"]` only; the
   policy admits `["create"]|["update"]`; replace/delete/forget/`[]` refuse on all.
   The rule: for every resource in a gate's allow-set, ask "what does its FIRST
   legitimate plan emit?" — a gate that only models steady-state verbs is a wedge.
2. **Membership + presence + weights, all bound by resolved IP.** Every origin must
   resolve to a declared host's plan IP; every ip-N origin gets the mode's weight
   (`{1,0}` drain, `{1,1}` serve); dup names AND dup addresses refuse; named↔IP
   misbinding refuses; `after.origins` absent/empty refuses distinctly.
3. **The marker is the proof, not the exit code.** The serve step captures wrapper
   output and requires `requires_runtime_bind_probe=true` — the string only the
   flip-authorization branch emits. A gate chain that can exit 0 vacuously is not
   fail-closed.
4. **Two Doppler configs = two scoped tokens.** `secrets.DOPPLER_TOKEN` is
   `prd_terraform`-scoped; `-c prd` needs `DOPPLER_TOKEN_PRD`, the marker config needs
   `DOPPLER_TOKEN_WORKSPACES_LUKS_MARKER`. One `DOPPLER_TOKEN` env cannot serve both —
   scope per call: `env DOPPLER_TOKEN="$DOPPLER_TOKEN_PRD" doppler run -c prd -- env
   DOPPLER_TOKEN="$DOPPLER_TOKEN_LUKS_MARKER" bash wrapper`. Adding a second holder of
   a write-scoped token means updating its census guard in the same diff.
5. **Follow-through probes live under `env -i`.** The sweeper forwards only PATH,
   `SOLEUR_FT_EARLIEST`, and declared `secrets=` names — a required env var outside
   that set = permanently TRANSIENT, never a verdict. Derive windows from
   `SOLEUR_FT_EARLIEST`; `secrets=` must equal required env exactly; optional secrets
   use `${VAR:-}` → exit 3, never unbound-exit-1 (rc 1 reopens the tracker).
6. **Bearer-on-argv is linted.** `-H "Authorization: Bearer $TOK"` puts the token in
   `/proc/<pid>/cmdline`; the repo form is
   `curl --disable --noproxy '*' ... --config - < <(printf 'header = "Authorization: Bearer %s"\n' "$TOK")`
   — and plan-doc snippets must show the same form or `lint-shell-trace-credential-refusal.py` reds.

## Key Insight

Three of the blockers were the same shape: **the guard modeled the steady state, not
the state it would actually see.** First-apply verbs, renamed members, standby-branch
exits, remnant-only re-dispatch plans — each gate graded the path it expected and
silently refused (or admitted) the path it would get. The structural-enumeration seat's
question is the antidote: enumerate every plan the arm CAN emit and every member the
set CAN contain, then check the grader against the enumeration, not the intent.

Also: `(.enabled // true)` swallowed boolean `enabled=false` AGAIN at origin level
(the 2026-10-30 learning documented the same pitfall at resource level and prescribed
`if has("x") ...` / null-only default). Learnings applied one level down are not
learnings applied.

## Session Errors

1. `pipeline-tally.sh` invoked with an unsupported flag → `SOLEUR_TALLY_ERROR`. **Prevention:** read `--help` before first use of a tally/gate script; the script selfchecks and is fail-open.
2. `emit-review-trailer.sh` rejected `--agents-missing ""` (empty value) then `--agents-ran 21 > --agents-expected 16` (miscounted expected). **Prevention:** expected = the seat count the classification called for; extra seats still count in ran — emit 21/21, not ran>expected.
3. Conflict-resolution regex assumed non-empty sides; the empty theirs-side block didn't match and the conflicted file was staged with markers. **Prevention:** resolve conflicts by literal block replacement or `git checkout --theirs/--ours`, never blind regex; grep for markers before `git add`.
4. `git rebase --continue` blocked on `$EDITOR` in a non-interactive shell. **Prevention:** always `GIT_EDITOR=true git -c core.editor=true rebase --continue` in agent shells.
5. `fix-round-seats.sh --finding-seats` expects comma-separated values, not space-separated. **Prevention:** usage check first.

## References

- `tests/scripts/lib/cf-lb-overlay-gate.sh` (the rewritten graders), sibling learning
  `2026-10-30-gate-allow-sets-bound-which-resources-not-what-they-say.md`.
- `scripts/sweep-followthroughs.sh` (the `env -i` contract), `post-deploy-incident-soak.sh`
  (the `SOLEUR_FT_EARLIEST` derivation precedent).
- `workspaces-luks-verify-workflow.test.sh` `g3_token_holders` (single-holder census on
  write-scoped tokens).

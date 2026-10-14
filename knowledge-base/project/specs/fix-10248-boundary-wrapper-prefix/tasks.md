# Tasks — fix-10248-boundary-wrapper-prefix

Plan: `knowledge-base/project/plans/2026-10-14-fix-boundary-anchored-gates-wrapper-prefix-plan.md`
Issue: #10248 | Base: `feat-fcc-token-optimizations` (PR #10227) — rebase `--onto origin/main` after it merges.
Draft PR: #10288.

## Phase 1 — Shared fragment + parity pin (RED-first)

- [ ] 1.1 Create `plugins/soleur/scripts/lib/wrapper-boundary.sh`: `SOLEUR_ENV_ASN_RE`,
      `SOLEUR_LAUNCHER_RE`, `SOLEUR_RTK_RE`, composed `SOLEUR_BOUNDARY_PFX`, consumption-idiom comment,
      `SOLEUR_BOUNDARY_PFX_LOADED=1` sentinel, canonical-TSV pin note in the header.
- [ ] 1.2 Add additive `flag-global` / `flag-string` class rows to
      `plugins/soleur/scripts/lib/ext-filter-grammar.tsv` (globals `-v/-vv/-vvv/--verbose`, `--skip-env`;
      string-flags `-c/--command/--shell`). Verify all six existing parity arms still green
      (`bash plugins/soleur/test/rtk-grammar-parity.test.sh`).
- [ ] 1.3 Extend `rtk-grammar-parity.test.sh`: extraction arms for `SOLEUR_RTK_RE` exec-subs vs TSV exec
      rows and globals vs `flag-global` rows — set-equality both directions.
- [ ] 1.4 Create `plugins/soleur/test/boundary-prefix.test.sh`: (a) both-directions behavioral matrix
      from the plan's Test Matrix section; (b) consumption census — comment-stripped grep derive the
      boundary-anchored gated-command sites across `.claude/hooks/*.sh` + `plugins/soleur/scripts/*.sh`,
      assert each carries `${SOLEUR_BOUNDARY_PFX` or sits in the justified-exemption registry, plus a
      site-count floor; (c) count-form verdicts only, no `! grep -q`.
- [ ] 1.5 Confirm RED: census fails (no site interpolates yet); fragment-level must-match rows pass,
      must-not-match rows pass (fragment is honest — the failure is consumption).

## Phase 2 — Carrier + canonical check

- [ ] 2.1 `.claude/hooks/lib/incidents.sh`: `unset` the exported names, nested `source` of
      `../../../plugins/soleur/scripts/lib/wrapper-boundary.sh` in the `[[ -f ]] && source … 2>/dev/null || true`
      idiom (`incidents.sh:18-19`, `:57-63` precedents); load failure routes `headless_or_stderr warn`.
- [ ] 2.2 `plugins/soleur/scripts/precommit-guard.sh`: source `$(dirname …)/lib/wrapper-boundary.sh`
      (fail-soft), `COMMIT_RE` → `(${SOLEUR_BOUNDARY_PFX:-}[[:space:]]+)*` form, amend the
      "Self-contained by design" header for the one same-dir lib.
- [ ] 2.3 Verify `bash plugins/soleur/scripts/precommit-guard.sh 'rtk git commit'` exits 1 on main, and
      from a tmpdir copy of script+`lib/` with no `.claude/` tree (plugin-cache simulation).
- [ ] 2.4 `guardrails.sh:145` interpolation (raw-`$COMMAND` arm).

## Phase 3 — Site consumption sweep (severity order)

- [ ] 3.1 `pre-merge-rebase.sh:123` trigger + `:129` `_merge_args` — grep AND sed per Design Note A
      (the `^[^g]*` strip breaks on `g`-bearing env prefixes).
- [ ] 3.2 `gh pr merge`/`gh pr ready` family: `pre-merge-auto-close-scan.sh:96`,
      `cla-signed-author-gate.sh:75`, `ship-unpushed-commits-gate.sh:85`,
      `ship-net-issue-flow-gate.sh:97`, `ship-operator-step-gate.sh:83`, `ship-runbook-ssh-gate.sh:63`,
      `ship-soak-followthrough-gate.sh:75`.
- [ ] 3.3 `follow-through-directive-gate.sh:81` (`gh issue create`).
- [ ] 3.4 `guardrails.sh:395` (`git commit`/`--continue`), `:478` (`git stash`), `:570–571`
      (`gh issue create` trigger + count — lockstep).
- [ ] 3.5 `prod-write-defer-gate.sh:179,180,182` (git-push-main, terraform-apply, doppler-secrets rows).
- [ ] 3.6 Test-fixture restatements: `ship-operator-step-gate.test.sh:30`,
      `ship-runbook-ssh-gate.test.sh:21` — `CMD_RE` consumes the fragment.
- [ ] 3.7 Per-hook `rtk`-spelling rows in each affected hook's `*.test.sh` (trigger + verdict + the
      must-not-match rows relevant to that gate).

## Phase 4 — Verify + docs

- [ ] 4.1 Full `.claude/hooks` suite + `scripts/test-all.sh` (scripts group) green; parity suite green
      with new arms.
- [ ] 4.2 `#10248` disclosure comments in the three base-planted files updated to past tense; same
      callout style at newly-fixed sites.
- [ ] 4.3 `known-external-tools.md` line noting the boundary class is covered (if the parent's doc names
      the deferred class).
- [ ] 4.4 Re-run the enumeration grep post-change — zero unexempted boundary-anchored gated-command
      regexes without the fragment.

## Deferred / follow-ups (not this PR)

- [ ] Launcher arg-grammars (`sudo -u`, `env -C`, `timeout N`) — pre-existing gap; file tracking issue
      if none exists.
- [ ] `rtk run -c`/`summary --shell` opaque-payload `unparsed-wrapper` ask at boundary sites — joins
      `bash -c` lexical-limit class for now; see decision-challenges.md.
- [ ] pkill `PFX` ↔ shared-fragment consolidation — separate surface by design.

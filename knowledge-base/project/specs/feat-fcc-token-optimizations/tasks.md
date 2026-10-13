# Tasks — feat-fcc-token-optimizations (issue #10230)

Derived from `knowledge-base/project/plans/2026-10-13-feat-external-filter-defensive-bundle-plan.md`
(post-review). Plan is the source of truth; phase order is load-bearing
(Phase 3 evidence gates the Phase-2 posture-constant flip and Phase-4 doc
wording).

## Phase 1 — Unwrap fixes (security surface)

- [ ] 1.1 `plugins/soleur/hooks/destructive-command-guard.sh` — all six sites:
  - [ ] 1.1.1 header prose (46–57) — verified RTK grammar, version-pinned
  - [ ] 1.1.2 `wrap_skip` `rtk` arm — exec set `run|err|test|proxy|summary`
    (case-sensitive), option-skip ↔ exec-word loop, `-c`/`--command`/`--shell`
    (+ `=` forms) → `unparsed-wrapper`, string-join payloads (quoted/metachar
    under `err|test|summary`) → `unparsed-wrapper`, unknown `-*` after exec
    word → `unparsed-wrapper`
  - [ ] 1.1.3 `fold_name` `rtk` arm (uppercase `RTK` → macOS class)
  - [ ] 1.1.4 `decide_walk` alternation (:1222) += `rtk`
  - [ ] 1.1.5 `redact_word` allowlist (:337) += `rtk`
  - [ ] 1.1.6 `long_word_judged` (:526) += `rtk`
  - [ ] 1.1.7 Re-verify exec-subcommand set + flag arity vs `rtk --help` /
    `rtk <sub> --help` at work time; record the source consulted (if rtk
    absent on work host: re-fetch RTK README and record that)
- [ ] 1.2 `plugins/soleur/test/destructive-command-guard-hook.test.sh`:
  - [ ] 1.2.1 `STUB_NAMES` (:226) += `rtk`
  - [ ] 1.2.2 python oracle `unwrap()` arm + `decide` dispatch tuple (:601) —
    oracle keeps its OWN literal arm (parity by extraction, not shared eval)
  - [ ] 1.2.3 `X` rows: `rtk rm -rf ~` deny, `rtk git push --force` ask,
    `rtk run rm -rf ~` deny, `rtk err rm -rf ~` deny, `rtk test rm -rf ~`
    deny, `rtk proxy git push -f` ask, `rtk summary rm -rf ~` deny,
    `rtk -v run rm -rf ~` deny, `sudo rtk rm -rf ~` deny, `rtk env rm -rf ~`
    (pinned false-deny), `rtk rtk rm -rf ~` deny; ask rows for
    `-c`/`--command`/`--shell`/post-subcommand-flag/quoted-string payloads;
    `rtk -- rm -rf ~` + `rtk run -- rm -rf ~` pin rows on `--` retry
  - [ ] 1.2.4 `L` row: uppercase `RTK rm -rf ~` → deny
  - [ ] 1.2.5 `redact_word`/`long_word_judged` enumerated rows
  - [ ] 1.2.6 must-allow rows: `rtk git status`, `rtk ls`, bare `rtk run`,
    `rtk gain`
  - [ ] 1.2.7 `MIN_CASES` (:2823) bump by new assertion count
  - [ ] 1.2.8 mutation suite: named mutants join M-battery with `DCG_ROWS`
    selectors (`destructive-command-guard-mutation.test.sh`)
  - [ ] 1.2.9 `.claude/hooks/README.md` roster + `plugins/soleur/README.md`
    pinned NOT-DECIDED sentence sync (suite pins both)
- [ ] 1.3 `.claude/hooks/pkill-self-match-guard.sh`: `PFX` regex += `rtk`;
  `stage_word` consumes the exec-subcommand word; `.claude/hooks/
  pkill-self-match-guard.test.sh`: `rtk` + `rtk run` rows
- [ ] 1.4 `plugins/soleur/scripts/lib/proc.sh`: `_PROC_WRAPPERS` += `rtk` +
  wrapper walk consumes exec-subcommand word;
  `plugins/soleur/test/proc.test.sh`: `rtk bash x.sh`, `rtk run bash x.sh`,
  `rtk -v run bash x.sh` rows
- [ ] 1.5 `.claude/hooks/lib/filing-shape.test.sh`: `rtk`-prefix LEXER row
  (`rtk gh issue create` → detected filing)
- [ ] 1.6 `plugins/soleur/test/rtk-grammar-parity.test.sh` (new): extract
  exec-subcommand set from every site + canonical table in
  known-external-tools.md; assert set equality

## Phase 2 — Detection

- [ ] 2.1 `plugins/soleur/hooks/ext-filter-detect.sh` (new):
  - [ ] 2.1.1 detection arms: `command -v rtk`, `command -v headroom`,
    settings-file hook-entry grep, `ANTHROPIC_BASE_URL` proxy check
  - [ ] 2.1.2 marker strictly key=value: `SOLEUR_EXT_FILTER tool=<t>
    version=<v> posture=<p> via=path|settings-hook|proxy-env
    measured_at=<date|-> ref=known-external-tools`
  - [ ] 2.1.3 epistemics: corroborated-named-posture rule; bare PATH →
    `via=path posture=unmeasured`; proxy arm → `tool=proxy posture=unknown`
    (never named); `version=unknown` → posture floors `unmeasured`;
    `posture=measured-incompatible` only when corroborated AND version ≤
    eval version
  - [ ] 2.1.4 `tool=none` on clean detection; dedup across arms
  - [ ] 2.1.5 `SOLEUR_DISABLE_EXT_FILTER_DETECT=1` first executable
    statement; fail-open `trap 'exit 0' EXIT`; bounded `timeout 5 cat`
    stdin read; `SOLEUR_HOOK_TRACE=1` → stderr; harness skips mirror
    version-banner (`CODEX_THREAD_ID`, `PLUGIN_ROOT`); `path=` fields
    tilde-collapsed; `--self-test` mode
- [ ] 2.2 `plugins/soleur/hooks/hooks.json`: SessionStart group,
  `startup|resume|clear|compact`, `timeout: 10`, quoted bash command
- [ ] 2.3 `.claude/hooks/devin-dispositions.tsv`: row (mirror version-banner
  disposition)
- [ ] 2.4 `plugins/soleur/test/ext-filter-detect-hook.test.sh` (new):
  stub-PATH fixtures per Guard 2 matrix + registration checks (hooks.json
  group + matcher + timeout + command spelling)

## Phase 3 — Evidence gate

- [ ] 3.1 `plugins/soleur/scripts/ext-filter-divergence.sh` + corpus (new):
  corpus = read-only deterministic offline commands emitting >3 lines;
  per-literal-class divergence table (file:line, SHA/PR, SOLEUR_*, eval-gate,
  rule-ids, gh --json fields, porcelain, pipeline-tally, SOLEUR_* echoes);
  control arm (`head -3`) UNCONDITIONAL → zero control divergence =
  `INSTRUMENT-DEFECT` non-zero exit; `SKIPPED reason=rtk-absent` exit 0 for
  the rtk arm only; `GRAMMAR-DRIFT` non-fatal when `rtk --help` disagrees
  with the canonical set
- [ ] 3.2 Run on operator host (rtk installed); persist report to
  `knowledge-base/project/specs/feat-fcc-token-optimizations/
  ext-filter-divergence-report.md`
- [ ] 3.3 Conjunctive pass (rtk-arm==0 AND control>0) → flip hook posture
  constant `unmeasured`→`literal-clean` + `measured_at=` in the same commit;
  any failure → stays `unmeasured`, doc ships pending wording, report still
  lands

## Phase 4 — Support surface

- [ ] 4.1 `plugins/soleur/docs/pages/known-external-tools.md` (new):
  canonical grammar table (version-pinned); posture table stamped
  measured-version+date + re-run note; Headroom inline eval scope
  (0.37.0/date/library-mode/244-of-581/restructuring example); tier
  definitions; symmetric-methodology line; marker stable-contract line;
  three-rung diagnostic + no-marker non-Claude path; footguns (NO
  `RTK_DISABLED`); dated+sourced telemetry defaults; no vendor-maturity
  copy; FCC = reachability framing only
- [ ] 4.2 `plugins/soleur/README.md`: Known Issues third entry (one sentence
  + link); NOT-DECIDED sentence sync (with 1.2.9)
- [ ] 4.3 `.github/ISSUE_TEMPLATE/bug_report.yml`: `filter:` dropdown +
  `session-start-marker` field (Claude-Code-only note, `via=`/`measured_at=`
  paste instruction) + `filtered-vs-verbatim` textarea (redact hint) +
  triage instruction to apply `external-env` when filter ≠ none
- [ ] 4.4 `gh label create external-env`; verify `gh label list`
- [ ] 4.5 Boundary-anchor deferral issue: CONCUR recorded; body-file own
  call; `Mandated-By:`/`User-Impact:` + `## Scope-Out Justification`;
  `--label deferred-scope-out` + `--milestone` (resolve via
  `gh api …/milestones`); census grep incl. `precommit-guard.sh:49`;
  severity ranking (`pre-merge-rebase.sh` first); shared boundary-fragment
  mandate; canonical-table reference; verify `gh issue view`; PR body gets
  `Tracks #<issue>` + `Mandated-By:`

## Verification

- [ ] V.1 `bash plugins/soleur/test/destructive-command-guard-hook.test.sh`
- [ ] V.2 `bash plugins/soleur/test/ext-filter-detect-hook.test.sh`
- [ ] V.3 `bash plugins/soleur/test/rtk-grammar-parity.test.sh`
- [ ] V.4 `bash .claude/hooks/pkill-self-match-guard.test.sh` +
  `bash plugins/soleur/test/proc.test.sh` +
  `bash .claude/hooks/lib/filing-shape.test.sh`
- [ ] V.5 `bash plugins/soleur/scripts/ext-filter-divergence.sh` (control
  arm at minimum; rtk arm on operator host)
- [ ] V.6 devin-matcher-parity + Eleventy build + markdownlint on new doc
- [ ] V.7 AC checklist against plan §Acceptance Criteria 1–6

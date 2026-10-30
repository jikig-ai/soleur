# Security Sentinel Review — PR #11603

**Seat:** soleur:engineering:review:security-sentinel
**Branch:** feat-one-shot-11600-job-log-step-attribution (closes #11600)
**Diff scope:** `git diff origin/main...HEAD` — 7 files, +608/−20. Code surface: `scripts/followthroughs/web-first-deploy-10585.sh` (+74/−20) and `web-first-deploy-10585.test.sh` (+143). Remainder is plan/spec/runbook docs (synthesized content, no secrets).
**Suite:** `bash scripts/followthroughs/web-first-deploy-10585.test.sh` → **69 passed, 0 failed** (ran in-session).

## Verdict

**PASS — mergeable.** No P0/P1/P2 findings. The diff adds a read-path recovery to an internal, notify-only watchdog probe. Credential posture is untouched (xtrace refusal + never-0/never-1 trap ordering intact and suite-pinned), all new attacker-influenceable fields are charset-validated before reaching output or awk `-v`, and every new failure branch degrades toward CANNOT ESTABLISH (exit 3) on success jobs rather than a quiet pass. Findings: 1 low, 4 info.

## Threat model applied

Attacker-influenceable inputs: GitHub jobs-API fields (`id`, `conclusion`, step `conclusion`, step `started_at`) and the `gh run view --job --log` body (job/step/ts/content). Externally writable only to the extent someone can author CI log content on this repo's `workflow_dispatch` runs — i.e., repo-write-equivalent actors. Outputs: verdict text posted by the sweeper to tracker #11583, and the Better Stack SQL built from extracted keys. Secrets in scope: `GH_TOKEN`, `BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}`.

## Detailed findings

### F1 (Low, detection-integrity) — A partial recovered region produces a quiet miss on a success job; the "loud on success" claim overstates coverage

**Location:** `scripts/followthroughs/web-first-deploy-10585.sh:305-336` (recovery + grep gate + tripwire); claim at `:95-99`.

The post-recovery tripwire fires only when `trail` is empty. The new gate at `:317` credits a recovered region containing **either** trail literal (`pointer|fresh_boot_ready`). A region-boundary anomaly can therefore yield a **non-empty partial** trail — e.g. pointer rows retained but the `fresh_boot_ready` row truncated by an early `##[group]Run ` boundary, or a skew-selected region carrying one literal class. Then: `trail` non-empty → tripwire skipped → `ready_ts` empty (`:337-340` `pointer without fresh_boot_ready = no proven boot`) → the job silently contributes nothing → potential quiet exit 2 while a genuinely proven boot was mis-sliced. The RESIDUALS note claims skew is "loud on a success job (empty region still tripwires)" — true only for empty or zero-pattern regions, not partial ones.

The same partial-trail semantics exist on the named path by design (a legitimate pointer-only trail means "no proven boot"), so this is largely an inherent residual of the 8178 technique — but the diff **widens** the collision surface in one new way: the added global strips `log=${log//$'\r'/}` and `log=${log//$'\357\273\277'/}` (`:290-291`) turn content like `\r##[group]Run x` or a BOM-prefixed `##[group]Run ` line into a region boundary that would not have matched the header regex pre-strip.

**Remediation:** (a) correct the claim — "loud on success" covers empty/no-pattern regions only; (b) optionally tighten the header regex to require a full timestamp shape (`^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z? ##`) so `\r`-spliced or BOM-prefixed content can't become a boundary post-normalization; (c) optionally treat a recovered success-job trail with pointer rows but zero ready rows as ambiguous (documented as accepted if left — the legitimate pointer-only shape makes this indistinguishable, which is itself worth stating).

### F2 (Info) — Log-derived `ready_ts`/`BOOT_ISO` is echoed into the tracker comment without `san()`

**Location:** `:348` (`BOOT_ISO[$key]=$ready_ts`), `:462` (`printf 'ACTION REQUIRED: %s (%s) was proven fresh-booted at %s …'`, `$b`).

Pre-existing path; the recovery widens which log lines can supply it. `ready_ts` is the pre-first-space token of a pattern-matched line and can carry control bytes (TAB, ESC) — though a hostile ts must also survive `ts_to_epoch`→`date -d` to create an obligation, which rejects most non-printable input (loud exit 3, `san`'d). Cheap hardening: `$(san "$b")` at the print, matching every other log/API fragment the probe echoes. Related pre-existing note: `san()` retains `\n\t` by design — a multi-line Better Stack error fragment (`san "${out:0:200}"`) can inject extra lines into a CANNOT ESTABLISH comment; unchanged by this diff.

### F3 (Info, hygiene) — `usrc()` fixture builder is defined but never called

**Location:** `web-first-deploy-10585.test.sh:157`. The ANSI-echo arm inside a recovered region IS exercised (case 18 passes an inline `$'\033[36;1m…'` payload through `ulog`), so coverage is not lost — but an unused builder invites drift (e.g. someone assumes the `usrc` shape is exercised when it is not). Use it in case 18 or drop it.

### F4 (Info, message precision) — `recovery_cause` mislabels the "header found, empty region" case

**Location:** `:311-312`. `region` empty means either "no `##[group]Run ` header at/after `started_at`" **or** "a header ≥ `started_at` opened an empty region" — the ULOG_EARLY_HDR fixture exercises the latter (the bounding `Post job cleanup` header opens then hits EOF). Verdict is correct (exit 3); the operator-facing cause can mislead triage. Suggest distinguishing or rewording.

### F5 (Info) — Named path retains the phantom `\t`-row edge the recovery path just closed

**Location:** `:296` vs `:317`. A named-attributed line with an empty field-3 makes `emit_rows` emit a bare `\t` row → `trail` non-empty → success-job tripwire skipped → quiet empty-trail. Identical semantics pre-diff (old awk emitted `\t` for the same input), and gh always emits field 3 — so this is a pre-existing edge, not a regression; noted because the new grep gate (`:317`) guards only the recovery path. Optionally apply the same pattern gate to `trail` unconditionally.

## Checks performed (all clean unless cited above)

- **Quoting/expansion:** every new expansion quoted (`<<<"$log"`, `<<<"$region"`, `-v ps="${jstart:0:19}"`, `<<<"$trail"`). `for id in $ids` is pre-existing and `id` is `^[0-9]+$`-validated before use in URL/`--job`.
- **API-field validation:** `jstart` is regex-gated `^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}` before any use; `${jstart:0:19}` reaching the awk `-v` and the `recovery_cause` message is therefore restricted to `[0-9TZ:.-]`-class bytes — no awk `-v` escape-injection, no comment injection. Embedded tab/newline in API fields degrades to loud exit 3 (non-numeric `jid` gate) or regex-fail → recovery skip. `--jq` pairs `conclusion`/`started_at` via `.[0]` on the same `select` ordering — consistent.
- **Injection to verdict:** `recovery_cause` is fixed literals + the validated ts prefix; `jid`/`id` numeric-validated; `key` constrained to `web-[0-9]+` by the extraction regex (also bounds the `host`→`VERDICT_SQL` interpolation to `[a-z0-9-]` — no SQLi); `url` constructed from validated numerics. Log content is never eval'd, never used as a regex/pattern operand, never executed.
- **Credentials:** xtrace refusal remains first executable block, EXIT trap directly after (suite pins both); `env -i` contract and stub `GH_TOKEN=ft10585-stub` literal in tests (not a real secret); no new credential surface, no log of `$log` content verbatim to output.
- **Fail direction:** every new recovery miss (`no started_at`, no qualifying header, empty region, zero trail-pattern lines) → exit 3 on success jobs; `jq`/`awk`/`emit_rows` substitution failures degrade to empty `trail`/`region` → same loud path (`pipefail` on, `set -e` correctly absent so failures fall through to the tripwire).
- **Fixture fidelity/synthesis:** fabricated ids/timestamps/hosts only (cq-test-fixtures-synthesized-only); `mktemp -d` + `assert_fixture_dir` + `! -L` on scratch; stub `gh` refuses unanticipated argv (exit 64) and evaluates the probe's own `--jq`; `bsq` host extraction constrained to `soleur-[a-z0-9-]+` (no traversal into `$GH_FX/bs.*`).
- **Multi-org R1–R6:** not dispatched (no Supabase/workspace-surface paths or symbols in diff).
- **Checklist items:** `san()` strips `\x7f`/U+2028-29 bytes under `LC_ALL=C` where applied; no filesystem-walking (fixture reads keyed on numeric-validated `jid`); no third-party CLI over tenant content; no workflow-file changes (no mutable-action surface).

## Risk matrix

| Sev | Count | Items |
|---|---|---|
| Critical/High | 0 | — |
| Medium | 0 | — |
| Low | 1 | F1 partial-region quiet miss / overstated "loud on success" |
| Info | 4 | F2 unsanitized `BOOT_ISO` echo; F3 dead `usrc()`; F4 cause-message precision; F5 named-path phantom row |

## Remediation roadmap

None blocking. Suggested follow-ups (post-merge acceptable): F1(a/b), F2 `san "$b"`, F3 use-or-drop `usrc`, F4 reword cause, F5 uniform pattern gate.

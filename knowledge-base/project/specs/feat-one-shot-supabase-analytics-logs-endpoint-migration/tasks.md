# Tasks — Supabase retained-log querying + Management API call-site guard

Derived from
[`knowledge-base/project/plans/2026-08-26-feat-supabase-analytics-logs-endpoint-migration-plan.md`](../../plans/2026-08-26-feat-supabase-analytics-logs-endpoint-migration-plan.md)
after 7-agent plan review. Ships as **three PRs** — see the plan's §Delivery Split.

Legend: `[ ]` pending · **PR-A** legal · **PR-B** deadline (2026-09-23) · **PR-C** follow-up.

---

## 1. Preconditions (PR-B)

- [ ] 1.1 Re-probe both endpoints; confirm the four contract differences and all six failure
      modes (A dialect-200, B typo-source, C non-monotonic window, D HTTP 500, E
      uninstrumented source, F wrong-but-valid ref).
- [ ] 1.2 Confirm `SUPABASE_ACCESS_TOKEN` resolves from Doppler `soleur/prd`.
- [ ] 1.3 Confirm `bash scripts/test-all.sh --print-suite-globs` still excludes
      `scripts/*.test.sh` (so the explicit `run_suite` line is required).
- [ ] 1.4 Re-derive the next free ADR ordinal across **all** `origin/*` refs. ADR-197 is
      provisional; 196 was highest across 60 refs at plan time.
- [ ] 1.5 `gh issue view 5697` before asserting its status anywhere.
- [ ] 1.6 Record the exact `git grep` pathspec (magic included) that defines the guard's
      assembly — decide explicitly whether `*.test.sh` is in scope (it changes N from 2 to 3).

## 2. Mutation fixtures BEFORE the guards (PR-B)

- [ ] 2.1 Write every §Guard Contract matrix row as an executable fixture first — including
      the two proofs that would otherwise ship green: file-scoped extraction (Guard 1) and
      the inverted quantifier (Guard 1 host-pin arm).
- [ ] 2.2 Confirm each row is genuinely drivable before writing either guard.

## 3. The assembly guard (PR-B)

- [ ] 3.1 `scripts/lint-supabase-deprecated-endpoints.sh` — **deprecation arm**: enumerate
      tracked non-doc files containing the host literal; resolve `$API` / `${REF}` /
      `$PROJECT_REF` **file-scoped**, never line-scoped.
      *(Line-scoped finds zero deprecated paths on this tree: the live `advisors/security`
      call sits 131 lines below its `API=` literal.)*
- [ ] 3.2 Exclude comments, the egress-allowlist hostname, and assertion strings
      (`scan-workflow.test.sh:260,263`; `cron-supabase-advisor-scan.test.ts:94-95` asserts
      *absence* while containing the token). Exemptions dated + inline-justified.
- [ ] 3.3 **Host-pin arm — invert the quantifier.** Assembly =
      `/v1/projects/|SUPABASE_ACCESS_TOKEN|SUPABASE_PAT`; membership assertion = contains the
      bare literal, or is on a dated non-caller allowlist. A literal-keyed assembly cannot
      see a redirected host, which makes Property 5 unenforceable.
- [ ] 3.4 Triage the eight files carrying a PAT var or `/v1/projects/` path with no host
      literal into the allowlist, each with a reason.
- [ ] 3.5 Assert the **host span only** (no expansion before the first `/v1`) — a whole-line
      interpolation check reds ~8 correctly-pinned files including the TS template literal.
- [ ] 3.6 Inline the denylist as a commented array: `analytics/endpoints/logs.all` (no
      waiver) + `advisors/security` (waived). **Do not** list `advisors/performance` — zero
      non-doc callers.
- [ ] 3.7 Emit a parseable census line; commit `.highwater` with the ratchet-down-only
      header; implement `--check-highwater`. Floors must satisfy AP-023 (`printf >&2` +
      `exit 1`, counter at the call site, never inside `$( )`).
- [ ] 3.8 `grep -c` semantics throughout; never `grep -q` mid-pipe.
- [ ] 3.9 `tests/scripts/test-lint-supabase-deprecated-endpoints.sh` covering all Guard 1
      rows, incl. the TS-shape fixture.
- [ ] 3.10 Wire as an **advisory** step in `lint-bot-statuses` (`.github/workflows/ci.yml`).
      Make no merge-gating claim anywhere.

## 4. The helper (PR-B)

- [ ] 4.1 **Nine fixtures**, `tests/scripts/fixtures/supabase-logs/`: success, dialect-error
      200, typo-source, wide-window truncation, HTTP 500, per-source tail, **zero+full
      coverage**, **zero+partial coverage**, **window-predates-retention**.
- [ ] 4.2 **Synthesize every row body.** Capture the envelope/field names only. The repo is
      public and the captures are production rows from a live GDPR exposure window; no gate
      covers `tests/scripts/fixtures/**`.
- [ ] 4.3 `scripts/supabase-logs-query.sh` — flags `--ref --source --since --until --limit
      --json --help`; `--since/--until/--limit` deliberately match `betterstack-query.sh`.
- [ ] 4.4 Host pin as a bare literal, no env override.
- [ ] 4.5 Auth via env-read header; `scrub_pat()` (`sbp_[A-Za-z0-9]{20,}`) at every print
      site. Unset-creds message mirrors `betterstack-query.sh`: names the exact `doppler run`
      re-invocation and says *do not conclude "no access / can't verify"*.
- [ ] 4.6 Default `--ref` to the pinned prd literal; validate `^[a-z0-9]{20}$` (**not**
      alpha-only); echo resolved ref + project on **every** output path.
- [ ] 4.7 One `group by source` call over a pinned `INSTRUMENTATION_SPAN_DAYS=30` — validates
      `--source` (kills B) and supplies full-span counts (kills E). Span must be pinned:
      an unbounded "full retained span" query is itself finding C.
- [ ] 4.8 Monotonicity probe when window > 7d, **then auto-narrow**: binary-search the cap,
      re-issue over slices, union per-slice coverage into one verdict. Print exact slice
      commands if auto-narrow is refused. Document both false-pass modes and that the probe
      cannot fire when the whole window predates retention.
- [ ] 4.9 Fail closed on non-null `.error`, `result: null`, non-2xx. **Re-issue a 500 once at
      half width** before classifying transient.
- [ ] 4.10 Atomic evidence block: count + ref + project + covered window + per-source
      instrumentation + verdict as one inseparable unit. `--json` emits **one object**;
      human mode puts the block on stderr.
- [ ] 4.11 Bind verdict to exit code: **3** = INCONCLUSIVE/UNINSTRUMENTED, 0 = COVERED,
      1 = transient, 2 = auth/config. Document the `betterstack-query.sh` exit-3 divergence.
- [ ] 4.12 Every failure mode names the next action; mode E routes to the sources that *are*
      instrumented; mode A says *do not hand-write a query — file an issue*.
- [ ] 4.13 Bounded `--limit` default; no `tee`, no `>` to a path, no `$GITHUB_OUTPUT`, no
      `upload-artifact`, no `mktemp`.
- [ ] 4.14 Shared verdict logic in `scripts/lib/` (auto-registers via SUITE_GLOBS).
- [ ] 4.15 `tests/scripts/test-supabase-logs-query.sh` — fake-curl PATH shim, offline.
- [ ] 4.16 Add the explicit `run_suite` lines to `scripts/test-all.sh` for **both** suites.
      *(The orphan lint is blind to `tests/scripts/` — assert registration directly.)*

## 5. Discoverability (PR-B — the MCP cut depends on this)

- [ ] 5.1 Add the `doppler run`-wrapped invocation to
      `plugins/soleur/skills/incident/SKILL.md` (Toolchain sentence, :35),
      `plugins/soleur/skills/reproduce-bug/SKILL.md` (:28),
      `plugins/soleur/agents/engineering/review/observability-coverage-reviewer.md` (:48).
- [ ] 5.2 Add it to `runbooks/dsar-export-failed-job.md` and
      `dsar-manual-supply-excluded-tables.md`.
- [ ] 5.3 Create `runbooks/supabase-log-query.md` (tool entry point), leading with the
      `doppler run` invocation.
- [ ] 5.4 Create `runbooks/breach-access-log-investigation.md` — promote GATE G-ESCALATE out
      of the June plan blockquote; steps 2 and 3 execute the helper.
- [ ] 5.5 Give it `triggers:` frontmatter. *(Zero runbooks carry it today, so
      `incident/SKILL.md:154`'s routing scan is inert repo-wide; this activates it.)*
- [ ] 5.6 Reference it from `knowledge-base/legal/statutory-response-catalog.md` §Breach
      step 4 (`:73`).

## 6. Evidence addenda — append-only (PR-B)

- [ ] 6.1 `gate-g-escalate-evidence.md` — dated addendum with the **working replacement SQL**
      (`from logs where source = 'postgres_logs'`), ClickHouse note, helper + runbook links.
      **Do not edit line 35** — it is a true statement about 2026-06-29.
- [ ] 6.2 The determination — dated addendum recording the migration and the retention
      change, stating explicitly it does **not** alter the access-log determination
      (`edge_logs` uninstrumented). Do not insert an endpoint reference to "correct".
- [ ] 6.3 `post-mortems/inngest-prd-rls-disabled-exposure-postmortem.md` — same treatment
      (stale figure at :48 and :126).
- [ ] 6.4 Reconcile sibling cross-references across all three in the same edit.
- [ ] 6.5 Delimit every addendum with explicit `<!-- ADDENDUM-2026-08-26 START/END -->`
      sentinels so region-scoped ACs are extractable (an awk range self-matches).

## 7. ADR + learning (PR-B)

- [ ] 7.1 ADR-197 — scoped to one invariant **above the vendor**: *a zero from any log
      surface is not evidence of absence without a coverage and instrumentation assertion.*
      Cite both vendor proofs (#6288 Better Stack hot-window; this endpoint's non-monotonic
      cap). Record the chokepoint's documented limitations and what non-vacuity rests on
      after `advisors/*` migrates.
- [ ] 7.2 Learning file generalizing "a short answer is the bug" across both log surfaces.

## 8. Tracking issues (PR-B files them; work is elsewhere)

- [ ] 8.1 `compliance/critical` — Art. 30 transcription, scoped **wider than one record**:
      audit every determination in `legal/audits/` for register transcription.
- [ ] 8.2 Promote the guard to blocking — enumerate the four coupled steps (composite-action
      preflight reproduction, `required-checks.txt`, the ruleset, ADR-139 re-derivation).
- [ ] 8.3 `advisors/*` — **no replacement path exists**; monitor for a successor or an
      announced removal date. Discharged by PR-C's spec diff.
- [ ] 8.4 PA-8 register placeholders (`__TBD_BETTERSTACK_RETENTION__`,
      `__TBD_OBSERVED_VOLUME__` ×2, `__TBD_DPA_DATE__`).
- [ ] 8.5 C4 `supabaseMgmtApi` element (deferred).
- [ ] 8.6 `SUPABASE_PAT` / `SUPABASE_ACCESS_TOKEN` unification (debt).
- [ ] 8.7 Close `lint-orphan-test-suites.sh`'s `tests/scripts/` producer gap.
- [ ] 8.8 Widen `triggers:` frontmatter to existing runbooks.
- [ ] 8.9 Annotate #5697 with the 2026-08-26 observation and its caveats — **keep OPEN**.

## 9. Legal lane (PR-A — ships first, independently)

- [ ] 9.1 Transcribe the Art. 33(5) record into `knowledge-base/legal/article-30-register.md`
      with a link to the determination, **dated 2026-08-26** so no reader infers it existed
      since June.
- [ ] 9.2 Add the `compliance-posture.md` Active Items row.
- [ ] 9.3 **No retention TOM, no new `__TBD_` placeholder.**
- [ ] 9.4 `legal-compliance-auditor` pass over the register edit.
- [ ] 9.5 Watch for conflicts: two open branches already touch the 379 KB register.

## 10. Recurrence poller (PR-C)

- [ ] 10.1 Append one step to `.github/workflows/scheduled-supabase-advisor-scan.yml`
      (`workflow_dispatch:`-only, Inngest-dispatched, already holds the token at :54).
      **Do not create a new `schedule:` workflow** — a PreToolUse hook denies it (ADR-033).
- [ ] 10.2 Diff `.deprecated == true` paths against the committed denylist.
- [ ] 10.3 **AP-021:** assert HTTP 200 **and** JSON content-type **and**
      `jq -e 'type=="object"'`, plus a parse floor (≥N paths, ≥1 deprecated). A spec parsing
      to zero deprecated paths is `channel_dark`, never `no_drift`.
- [ ] 10.4 **AP-022:** clear errexit explicitly where the curl status is captured.
- [ ] 10.5 Reuse `scheduled-marketplace-drift.yml`'s dedupe hardening: bootstrap the label
      first; capture `gh issue list` **and its exit code**; refuse to file on a failed lookup.
- [ ] 10.6 Route waiver expiry here via the `expenses-verify-by-check.sh` `verify_by` shape —
      never a red CI check.

## 11. Pre-deadline open item

- [ ] 11.1 Attribute Supabase's own Management API request log for `logs.all` over the last
      30 days, or record it as accepted-unknown with the blast radius named. Nothing else in
      the plan detects a non-repo caller, and this is the only item that can bite on
      2026-09-23.

## 12. Verification

- [ ] 12.1 Run all 30 acceptance criteria.
- [ ] 12.2 `python3 scripts/lint-guard-contract.py <plan>` → exit 0 **and `2 guard entries`**.
- [ ] 12.3 `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` → 0.
- [ ] 12.4 `bash scripts/test-all.sh` full battery at `/ship` Phase 4.
- [ ] 12.5 Re-verify the ADR ordinal against freshly-fetched `origin/*` immediately before
      merge.

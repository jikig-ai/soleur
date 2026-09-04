# Tasks — fix(gdpr-gate) freshness writer and scan output

Plan: `knowledge-base/project/plans/2026-09-04-fix-gdpr-gate-staleness-posture-vs-scan-plan.md`
Branch: `feat-one-shot-7710-gdpr-gate-prescan-refusal` · Closes `#7710`
Lane: `cross-domain` · Brand-survival threshold: `single-user incident`

Ordering is a dependency chain, not a preference. Phase 1 must land before Phase 2: before the
registry is complete the cron compares 5 of 8 files, because `upstream-files` derives from the same
frontmatter — so a zero-drift result is not evidence about the corpus.

## Phase 0 — Preconditions

- [ ] 0.1 Re-measure upstream drift for all 8 lifted paths against live `goSprinto/compliance-skills`.
      The plan's `8 SAME / 0 DRIFTED` reading was taken 2026-09-04 and must not be assumed to hold.
      If drift is found, follow the plan's withheld branch: every phase still ships, and the
      re-vendor becomes its own issue routed through `content-vendoring.md` §6.
- [ ] 0.2 Re-derive the ADR ordinal against freshly-fetched `origin/main` **and** every `origin/*`
      ref. Plan-time reading: `origin/main` tops at ADR-200, ADR-202 claimed on a branch, so ADR-203.
      If it moved, sweep the plan, this file and every acceptance criterion naming it in one edit.
- [ ] 0.3 Confirm `references/legacy/legal-consent-v1-prose.md` still exists and still matches neither
      `references/*.md` nor `references/layers/*.md` — its disposition is load-bearing for 1.3.

## Phase 1 — Reconcile the canonical record

- [ ] 1.1 For each of `references/layers/{auth-sessions,frontend,testing-seeding}.md`: fetch the
      upstream blob at its pinned `upstream-blob-sha`, diff against the local file, and confirm the
      delta equals the documented Soleur extension plus the attribution header. **Do not pin before
      the delta matches** — pin-what-you-find launders an unreviewed edit into an attested one.
- [ ] 1.2 Add the three `lifted-files` entries (`upstream-path`, `upstream-blob-sha`,
      `local-blob-sha`, `status`). Recomputed SHAs must agree with the plan's measured values; a
      disagreement means the tree changed and 1.1 must be redone.
- [ ] 1.3 Add a `soleur-authored` list to the NOTICE frontmatter carrying a `local-blob-sha` per file
      for `non-negotiables.md`, `legal-consent.md` and `legacy/legal-consent-v1-prose.md`. Never a
      `lifted-files` row for any of them — that would attest third-party MIT provenance for Soleur's
      own writing. Omitting `legacy/**` makes 1.6's assertion red at merge.
- [ ] 1.4 Teach `vendor-pin-integrity.sh` to check `soleur-authored` SHAs exactly as it checks
      `lifted-files`, without treating them as upstream-derived.
- [ ] 1.5 Repoint `vendor-pin-integrity.sh`'s mismatch message — it names a vendor-drift workflow
      deleted in `#4483`, and it is the only exit a blocked contributor gets.
- [ ] 1.6 Add the reverse parity assertion (glob ⊇ NOTICE) to `vendor-pin-integrity.test.sh`. Its
      existing assertion is one-directional, which is why three files sat unpinned for 117 days with
      a green suite.
- [ ] 1.7 Correct the stale count in all three artifacts: `compliance-posture.md`,
      `content-vendoring.md`, and `ADR-026`'s C4 component block. The third is worded differently and
      is invisible to the other two greps.
- [ ] 1.8 Correct `lefthook.yml`'s comment claiming the glob covers the whole `references/` subtree;
      both patterns are single-level.
- [ ] 1.9 Update `notice-frontmatter.test.sh` — **both** hardcoded counts (`lifted-files` and
      `upstream-files`).
- [ ] 1.10 Write the framing in the PR body as a records reconciliation that **relaxes** those three
      files, never as closing an integrity hole. They were rejected outright before this change.

## Phase 2 — Fix the comparison, then let it write

All inside `step.run` boundaries with a deterministic per-step return shape, replay-safe under
`retries: 1` (`ADR-033` I1/I5).

- [ ] 2.1 Split the comparison's third state: a fetch that did not answer is `ERROR`, never `SAME`.
      Return `{filesExamined, filesSame, filesDrifted, filesError}`.
- [ ] 2.2 Populate `aggDiffParts`. It is declared and never written, so the classifier always sees an
      empty diff and returns `no-op` — which is what makes the second `return { drift: "none" }`
      reachable after drift was detected.
- [ ] 2.3 Gate the write on `filesExamined === <registry entry count> && filesDrifted === 0 &&
      filesError === 0`. **Never on `detectResult.drift`** — that reaches the `classifyRc === 0`
      return and would advance the attestation over a corpus the same run found drift in.
- [ ] 2.4 Route the write through `safeCommitAndPr` with `mergeMode: "direct"`. The helper has no
      direct-to-branch mode, and a raw push is blocked by rulesets whose bypass actors are all
      `bypass_mode: "pull_request"`. Note this is a new call site — the helper is not invoked on the
      no-drift path today.
- [ ] 2.5 Make the heartbeat conditional: a zero-drift run that produced no committed advance must
      post non-OK. Today `postSentryHeartbeat({ok: true})` runs unconditionally after routing, so the
      cron can compare clean, fail to commit, and report healthy.
- [ ] 2.6 Emit one event carrying `filesExamined`, `filesSame`, `filesDrifted`, `filesError`,
      `wroteAttestation` and `commitSha` together — four hypotheses a single boolean cannot separate.
- [ ] 2.7 Correct the PR-body template's claim that `last-verified` is bumped at PR-creation time.
      This is the task that makes it true.
- [ ] 2.8 Extend `cron-content-vendor-drift.test.ts`: three-state totals, the write predicate across
      all five exits, and replay safety.

## Phase 3 — Give the scan an output of its own

- [ ] 3.1 Emit a stdout line from `gdpr-gate.sh` reporting paths examined and matched. **Counts only,
      never path names** — the line reaches customer stdout, and `#7331` is the scar behind
      `hr-third-party-content-grep-on-undertaking`.
- [ ] 3.2 Verify the line contains neither `days stale` nor `POSTURE_FAIL`, and that the existing
      negative assertion in `gdpr-gate.test.ts` is preserved unmodified.
- [ ] 3.3 Amend the banner-fatigue comment to what is true: the `#3541` relevance property is
      delivered by the lefthook glob, not by the matched-path conditional.
- [ ] 3.4 Add the glob-liveness test — materialise a regulated fixture path, run the pre-commit hook,
      assert `gdpr-gate-advisory` was not skipped. A line emitted by the script cannot witness the
      script not running, and this repo has shipped that trap twice.
- [ ] 3.5 Extend `gdpr-gate-self-test.test.sh` with the matched and unmatched cases.
- [ ] 3.6 Leave the 30d/90d values untouched, keep `exit 0`, do not relevance-gate the banners.

## Phase 4 — Policy and the posture record

- [ ] 4.1 Add `content-vendoring.md` §6a, "Verification-Only Refresh (no drift)" — §6 governs the
      drift-detected path only, and nothing covers re-verified-no-drift.
- [ ] 4.2 Correct §4's layer count, which already undercounts on `main` by omitting
      `vendor-pin-verify.yml`. Frame it as a standing error, not a consequence of this change.
- [ ] 4.3 Widen the Active Items schema comment — it admits only `OPEN | IN-PROGRESS`, and scopes the
      section to critical-finding handshakes. Both must admit a posture-derived item.
- [ ] 4.4 Append the Active Items row. Notes carry regulatory content only: the 117-day window; that
      the corpus never drifted, so this is Art. 5(2) demonstrability and weakly Art. 32(1)(d) — not
      Art. 32(1)(a)–(c), not Art. 33/34, no incident vocabulary; why the chain did not run; that the
      `POSTURE_FAIL` fired only into a gitignored ledger; and that the 5→8 figure was a registry
      undercount, **not** an unguarded-file window. Status `IN-PROGRESS` until the writer is observed.
- [ ] 4.5 Apply the `compliance/critical` label to `#7710`. Do not write a justification for its
      absence into the compliance record.
- [ ] 4.6 Repair the pointer `gdpr-gate.sh` prints — both the fragment (`#8-posture_fail-operator-chain`;
      underscores are retained by GitHub's slugger) and the path, which is not shipped inside the
      plugin. Fix the link, not the heading — dropping the numeral breaks every §8 citation.
- [ ] 4.7 Repoint §8 step 5's `ci/vendor-drift-*` clause to `ci/content-vendor-drift-*`. It is stale,
      not dead — do not delete a live step.

## Phase 5 — Correct the skill's account of itself

- [ ] 5.1 Fix `gdpr-gate.sh`'s header promise of a `gdpr-gate-touch` event it never emits (it emits
      `hr-gdpr-gate-on-regulated-data-surfaces`, which also does not match the `gdpr-gate-*` branch of
      the allow-list in `rule-incident-marker-capture.sh`). Fix the header or the emit.
- [ ] 5.2 Document the scan line, the restored writer and the lefthook glob in `SKILL.md` Sharp edges.
      Leave the "on every invocation" sentence — it scopes to the hook and is true of it.
- [ ] 5.3 Keep the operator-attested banner literal byte-identical across its three sites; the
      self-test enforces grep parity.

## Phase 6 — Records, filings and durability

- [ ] 6.1 Write `ADR-203`. One decision — a weekly cron acquires write access to the default branch
      for a compliance attestation, via a self-merging bot PR gated on a same-run comparison — plus
      four named residuals: the `ADR-026`/`ADR-197` D-2 tension; `#7255` leaving anti-backdating
      inert; `pushed_at` age unchecked, so an abandoned-but-unarchived upstream stays green; and the
      deliberate bypass of `CODEOWNERS` routing. Do **not** argue containment from `CODEOWNERS` — no
      ruleset carries a `pull_request` rule, so no review gate exists to contain anything.
- [ ] 6.2 File the enforcement-chain issue: of five gate surfaces one is mechanical and cannot block,
      and `plan`/`work` both "skip silently", so an omitted gate and a correct skip are
      byte-identical — `#7710`'s thesis applied to the rule itself. Labels `compliance/critical`,
      `domain/engineering`.
- [ ] 6.3 Leave `#7255` open; add the candidacy note. Nothing in the PR body may read as resolving it.
- [ ] 6.4 Re-milestone `#7710` to *Phase 4: Validate + Scale*, raise to `priority/p1-high`.
- [ ] 6.5 Write `scripts/followthroughs/gdpr-gate-attestation-advances-7710.sh` and enrol it on a
      tracking issue with `earliest=<merge+8d>` and `secrets=GH_TOKEN` (the sweeper runs probes under
      `env -i`, and the probe uses `gh`). Both the directive **and** the issue are required — the
      sweeper walks open issues, so a script alone never runs. Assert at least one bot-authored
      advance since merge.
- [ ] 6.6 Enrol the second probe at `earliest=<merge+91d>`: `days-stale` ≤ 8 (not merely under 30,
      which cannot distinguish a healthy weekly writer from one that stopped three weeks ago) and
      ≥ 10 distinct advancing commits since merge.

## Phase 7 — Verification

- [ ] 7.1 Exercise every Guard Contract mutation and harness row; each must behave as specified.
- [ ] 7.2 Run the full battery at `/ship` Phase 4, including `gdpr-gate-self-test.test.sh`,
      `notice-frontmatter.test.sh`, `vendor-pin-integrity.test.sh`, `gdpr-gate.test.ts`,
      `gdpr-gate-repo-scan.test.ts` and `cron-content-vendor-drift.test.ts`.
- [ ] 7.3 Walk the 25 acceptance criteria in the plan; record the command and its output for each.
- [ ] 7.4 Capture the session learning — directory `knowledge-base/project/learnings/`, topic: a
      freshness threshold whose writer was deleted by a substrate migration, and the review round that
      reversed three plan decisions. Let the author pick the date at write time.

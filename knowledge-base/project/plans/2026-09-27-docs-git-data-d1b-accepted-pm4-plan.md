---
title: "docs: record ADR-220 D1b and ADR-239 as accepted after the clear git-data proof run (#8211 PR2 PM4)"
type: docs
date: 2026-09-27
slug: docs-git-data-d1b-accepted-pm4
branch: feat-one-shot-8211-pr2-pm4-docs
issue: 8211
closes: []
priority: p2-medium
domain: engineering
brand_survival_threshold: none
requires_cpo_signoff: false
lane: cross-domain
---

# docs: record ADR-220 D1b and ADR-239 as accepted after the clear git-data proof run (#8211 PR2 PM4)

Spec lacks valid lane: — defaulted to cross-domain (TR2 fail-closed).

## Enhancement Summary

**Deepened on:** 2026-09-27
**Sections enhanced:** 6 (Phase 1, Phase 3, Phase 4, Phase 5, Observability, Acceptance Criteria)
**Agents used:**

- `soleur:engineering:review:architecture-strategist`;
- a verify-the-claims pass (general-purpose, `standard` tier), which re-ran every attribution and
  every AC against the pre-edit tree, including live Hetzner and Better Stack re-reads;
- halt gates 4.6, 4.7, 4.8, 4.9, 4.10, 4.11 and 4.55.

### Key Improvements

1. **A stale C4 claim was found (P1).** The `gitDataStore` element still says "no host serves the
   store until the forward fix (#5274) boots". The fix booted on 2026-09-25, and that boot is the
   ADR-239 evidence. Phase 5 step 4 now corrects the claim, and AC4 asserts its absence.
2. **The ADR-220 entry is now complete:**
   - why `probe=config` has no notice;
   - the verbatim 2026-09-27 caveat;
   - the D4 first residual closed through ADR-237;
   - the D2–D3 #7226 limb now met.
3. **The ADR-239 amendment now cites more evidence:**
   - the committed rung-2 evidence file (`git-data-rung2-boot-evidence.env`) for the rehearsal
     precondition;
   - the discharge of the 2026-09-24 amendment's production proof (`plaintext_journal=dirty
     plaintext_empty=yes`).
4. **Phase 1 re-reads the boot line as well as the Hetzner server,** because an in-place rebuild
   keeps the server id.
5. **An `## Observability` block now satisfies Phase 4.7.** A `.github/workflows` path is not
   pure-docs to that gate. The block has a probe-verb-gated `grep` probe.

### New Considerations Discovered

- The verify pass confirmed every PR, issue, run, SHA and quoted-anchor claim. It corrected two
  minor facts: the annotation list order, and the count of suites that read the workflow (8).
- The pass reported that host-key item 4 already carries a Done record. This was checked and is
  wrong: the only 36119817656 citation is in the Preconditions `[x] Step 4` sub-item, so Phase 6
  step 2 stays.
- The halt gates found nothing to stop on. There are no PAT-shaped variables, no UI surface, no
  new store or connection, no guard deliverable and no downtime operation. User-Brand Impact is
  present with a scoped-out `none`.

## Overview

This is the post-merge docs PR (PM4) for #8211 PR2. The proof-half PR (#9048) merged. Its
post-merge dry run from `main`, `git-data-cutover.yml` run
[36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990), concluded
`verdict=clear` with both SSH hops pinned. The run is recorded on #5914
(issuecomment-5859802570).

This PR records what that evidence settles:

1. **ADR-220 D1b** goes from `proposed` to `accepted`, through a new dated amendment-log entry.
2. **The C4 `github -> gitDataStore` edge**: its "root authentication TARGET until ADR-220 D1b
   flips" marker becomes LIVE.
3. **`.github/workflows/git-data-cutover.yml`**: the header comment that PR #9048 held back (its
   commit `0f5cf8934f`) is re-applied, byte for byte.
4. **ADR-239** goes from `adopting` to `accepted`. Its own flip rule is met by the current production
   instance's `boot_complete`, which was read during planning.
5. **Runbook `git-data-luks-cutover-5274.md`**:
   - the #7226 precondition is ticked;
   - host-key step 4 gets a Done line;
   - "Post-merge order (#8189)" step 5 is marked done.

The workflow edit makes this PR **UNTRUSTED-CI**, so auto-merge is the only merge path and there is
no agent `--admin` fallback. The PR closes no issue: #8211 stays open for the flip half, and #5914
stays open for host-key steps 5 and 6.

## Research Reconciliation — Spec vs. Codebase

The branch base is `2b41ad60e4`. `origin/main` is at `4170460eea` (#9088), and that commit touches
none of the target files (checked with `git diff --stat 2b41ad60e4 origin/main -- <targets>`).

### "Tick the issue-7226 item under Preconditions" (host-key step 4)

- **Reality:**
  - The Preconditions `[x] Step 4` sub-item was already ticked by PR #9036 (run 36119817656).
  - The parent bullet `**#7226 / #5914**` has no checkbox of its own.
  - #7226 is CLOSED (2026-09-22, by PR #8511).
- **Plan response:**
  - Add a ticked `#7226` child item under that bullet (the operator's stated direction).
  - Add a one-line Done record to host-key item 4.
  - Re-tick nothing that is already ticked.

### "PM1–PM3 are done"

- **Reality:** PM1 and PM2 are on #5914 (issuecomment-5859802570). That comment ends "Next is step
  5, discharging the erasures left pending". No host-key step-5 discharge record carrying the
  (a)–(d) chain is on #5914 as of 21:03Z.
- **Plan response:** out of scope. Host-key step 5 stays `[ ]`, and this PR makes no claim about
  it.

### "Mark Post-merge order (#8189) step 5 done, citing run 36339208990"

- **Reality:**
  - The first dry run to meet step 5 was run
    [35119099336](https://github.com/jikig-ai/soleur/actions/runs/35119099336), on 2026-09-16 from
    `main` at `2d9177bec2`. Its annotations: `role=web`, `role=git-data-jump` and
    `role=git-data-auth` all `verdict=ok`; `probe=store-mounted`, `store-not-cut-over` and
    `store-empty` all `verdict=ok`; then `verdict=clear`.
  - #8189 and #6680 were closed on that evidence.
  - That run predates the fence probe (2026-09-21) and host-key pinning.
  - The step's current wording ("clear the store probes and the fence probe") is met by 36339208990.
- **Plan response:** the Done record cites 36339208990 as the run that meets the step as now
  worded, and names 35119099336 as the run that first met it, under the older wording.

### "Settle ADR-239's status"

- **Reality:**
  - The rule: a **production** `hcloud_server.git_data` emits `stage:boot_complete` reading
    `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes`.
  - The 2026-09-27 amendment defers the flip to "the ADR-220 D1b docs PR, which reads the current
    instance's `boot_complete`".
- **Plan response:** the rule was read and found met during planning (Research Insights). Flip to
  `accepted` with a dated amendment.

### "Flip ADR-220 D1b"

- **Reality:**
  - The frontmatter carries the least-advanced decision status, `proposed` (D5 note).
  - D2–D3 stay `proposed`.
  - The 2026-09-15 D1b condition was already met on 2026-09-16 (run 35119099336, unpinned), but it
    was never recorded.
- **Plan response:**
  - Flip only the D1b row, against its current (2026-09-27) condition.
  - Name the unrecorded 2026-09-16 run in one sentence.
  - The frontmatter stays `proposed`.

### The deferred workflow header text

- **Reality:**
  - `git diff 0f5cf8934f HEAD -- .github/workflows/git-data-cutover.yml` is empty.
  - `0f5cf8934f` is **not** reachable from `origin/main` (#9048 was squash-merged).
  - It is reachable from `refs/pull/9048/head` (`5b7868fd24`).
- **Plan response:**
  - Fetch `refs/pull/9048/head` first, then apply the inverse of `0f5cf8934f`.
  - The acceptance check greps for the target text; it does not use the SHA as the oracle.

## Research Insights

### Premise Validation (Phase 0.6)

- #8211 is OPEN (the flip half remains).
- #5914 is OPEN (host-key steps 5 and 6 remain).
- #7226 is CLOSED (2026-09-22T12:07:02Z, by PR #8511).
- #8189 and #6680 are CLOSED (2026-09-16, on run 35119099336).
- #8634 is OPEN; it owns Art. 30 activation for ADR-239.
- PR #9048 is MERGED (`59745cf049`). PR #9036 is MERGED; it flipped ADR-237 and is the shape
  precedent for this PR. Draft PR #9094 is open on this branch.
- **Run 36339208990:**
  - `workflow_dispatch` on `main` at `ab4a07e5e0ab26a84a4b08b61cbe02a99e410acb`, `conclusion=success`;
  - one job, `cutover`, id 108675849067;
  - `git merge-base --is-ancestor ab4a07e5e0 origin/main` passes, and `ab4a07e5e0` contains
    `59745cf049`.
- **Annotations** (`gh api repos/jikig-ai/soleur/check-runs/108675849067/annotations`; the API lists
  newest first): nine notices, namely `verdict=clear`, then `probe=fence-shape`, `store-empty`,
  `store-verified`, `store-on-mapper` and `store-mounted`, then `role=git-data-auth`,
  `git-data-jump` and `web`, every one `verdict=ok`. There are also two warnings: the expected
  `TOFU_ARM present` (listed last) and a Node 20 deprecation (listed first).
- **Pinned lines, cited by the step that printed each one:**
  - `write-known-hosts: pinned web-1 ecdsa-sha2-nistp256 SHA256:ARBTzhY4hCGXKwWZ2j9aOc4zZefBYgAxJncoVglvuok`
    was printed in the `CF Tunnel SSH bridge` step and again in the `Write git-data ssh_config` step.
  - `write-known-hosts: pinned git-data ssh-ed25519 SHA256:4eErmLfOuKM17zzNd+2so+26zojG0tsv9NMVNCuXpCs`
    was printed in the `Write git-data ssh_config` step.
  - `git_data_pin=present` was printed in the `Flag precheck` step. That is the CI's read of Doppler,
    not the running app.
  - `StrictHostKeyChecking=yes` appears in `WEB_HOST_SSH` and in the `gd-ssh-config` heredoc.
- **The ADR-239 boot line, read 2026-09-27.** Command:

  ```bash
  doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh \
    --table t520508_soleur_git_data_prd_logs --table-s3 t520508_soleur_git_data_prd_s3 \
    "SELECT dt, raw FROM (SELECT dt, raw FROM remote(\$BS_TABLE) UNION ALL SELECT dt, raw FROM s3Cluster(primary, \$BS_TABLE_S3) WHERE _row_type = 1) WHERE dt > fromUnixTimestamp(1790328235) AND JSONExtractString(raw,'stage') = 'boot_complete' AND JSONExtractString(raw,'host_name') = 'soleur-git-data' ORDER BY dt DESC LIMIT 3 FORMAT JSONEachRow"
  ```

  This is the runbook's host-key step 5 (b) query, with the raw row printed rather than piped
  through that step's three-field `jq`. The anchor `1790328235` is replace run 36118115758's
  `boot-trail anchor`.

  The result is one row, `dt=2026-09-25 09:25:30.904561`, reading:
  - `luks_mounted=yes`, `fence_on_mapper=yes`, `erasure_probe=yes`, `luks_reopen_unit=yes`;
  - `plaintext_volume=present`, `plaintext_empty=yes`, `served_repos=0`,
    `plaintext_journal=dirty`.

  The `host_name` filter excludes rehearsal hosts, which report `soleur-git-data-rehearsal-<run>`.
- **Same instance.** `doppler run -p soleur -c prd_terraform -- sh -c 'curl --disable --noproxy "*" -sS -H "Authorization: Bearer $HCLOUD_TOKEN" "https://api.hetzner.cloud/v1/servers?name=soleur-git-data"'`
  returns id `167392038`, created `2026-09-25T09:24:32Z`, `running`. That is inside replace run
  36118115758 (09:23:01Z to 09:25:52Z). The only later `apply-web-platform-infra.yml` dispatch,
  36327637204, ran `inngest_host_replace`.
- **The rung-2 rehearsal** that the ADR-239 Status paragraph requires before that replace is run
  36029201848 (2026-09-24, `main`, `success`).

### Property List (Phase 0.6b)

- **P1.** A reader of ADR-220 finds D1b recorded as `accepted` against its current condition, and
  no dated text is rewritten.
- **P2.** A reader of the C4 model sees root authentication on the CI-to-git-data edge as LIVE.
- **P3.** The workflow's header describes what the proof checks today.
- **P4.** ADR-239's frontmatter status matches its own flip rule, which is met.
- **P5.** The runbook's progress records match reality, and nothing unproven is ticked.

### Cut List (Phase 0.6b and plan review)

- **Editing the in-body ADR-220 D5 table, or any ADR Status paragraph:** cut. These are dated text.
  The amendment log and a frontmatter change carry P1 and P4, as #9036 did.
- **Editing `knowledge-base/legal/article-30-register.md`'s "(`adopting`, authored in PR #8564)"
  parentheticals:** cut. They sit inside dated 2026-09-23/24 markers, and #8634 owns activation.
- **Ticking runbook "Post-merge order (#8189)" steps 1–4, or host-key steps 1–3:** cut. #9036
  declined these for lack of per-step records.
- **Appending the 36339208990 re-read to the already-ticked `[x] Step 4` sub-item:** cut (plan
  review). That item is ADR-237 evidence, and the new run is recorded where it belongs.
- **Re-reading immutable evidence at work time** (the run's conclusion and its annotations): cut
  (plan review). Those were read at plan time and are quoted above. Only the mutable facts are
  re-read: that no newer git-data host exists, and that no newer boot exists. The second read was
  restored at deepen-plan, because an in-place rebuild keeps the Hetzner id.
- **Post-merge PM1 (a status re-read) and PM2 (a comment on #8211):** cut. `Ref #8211`
  cross-links, and the squash merge carries the same bytes.
- **Run ids in the C4 label:** cut. The ADR-220 amendment is the single home of the evidence.

### Relevant files (read on this branch)

- `.github/workflows/git-data-cutover.yml`: header items 4–5 and the sentence after them.
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md`:
  - `## Status`, `### D5 — Statuses`, and the `## Amendment log`;
  - the log's last entry is `### 2026-09-27 (#8211 PR2): the store probes read the LUKS-served
    store`, which restates the D1b condition: "a dispatch from `main` that reads
    `role=git-data-auth verdict=ok` with the store probes and the fence probe clear".
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md`:
  - frontmatter `status: adopting`, and the flip rule in `## Status`;
  - the last amendment, `## Amendment 2026-09-27 — the proof reads the LUKS-served store (#8211
    PR2, proof half)`, then `## References`.
- `knowledge-base/engineering/architecture/decisions/ADR-237-ssh-host-keys-are-pinned.md`,
  `## Addendum — 2026-09-27 (#7226)`: the shape precedent. Do not edit it.
- `knowledge-base/engineering/architecture/diagrams/model.c4`:
  - the comment block under `// #6680 / ADR-220 — CI's cutover access to the store.`;
  - the `github -> gitDataStore` label, which begins `"Transport LIVE; root authentication TARGET
    until ADR-220 D1b flips`;
  - its clause `Host keys PINNED on both hops (ADR-237; effective when the strict dry run after the
    first key-rotating git-data replace reads role=git-data-auth verdict=ok)`.
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json`: regenerated.
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md`:
  - `## Preconditions for the real cutover`: the bullet `**#7226 / #5914**`;
  - `## Post-merge order (#8189)`: item `5. **Dry run.**`;
  - `## Host-key pinning post-merge sequence (#7226, #5914)`: item `4. **Strict dry run.**`.
- PM4 is defined in the archived #9048 plan:
  `knowledge-base/project/plans/archive/20260927-171719-2026-09-27-feat-git-data-cutover-proof-on-luks-mapper-plan.md`
  (§"Post-merge" PM4; §Phase 6 item 1 holds the header text).

### Conventions and constraints

- **Records:**
  - Dated records are append-only. A status flip is a frontmatter change plus a new dated section
    (#9036).
  - **Add lines only in the ADRs and the runbook.** Never append to an existing line: an appended
    line shows as a deletion in `numstat`.
  - Cite content anchors, not line numbers (`cq-cite-content-anchor-not-line-number`).
  - A CI log line is evidence only about the `##[group]Run` step that printed it.
- **Commit and ship:**
  - Commit with `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test`. CI is the test battery.
  - Required checks must pass by name on the exact head SHA.
  - Export `CLAUDE_PLUGIN_ROOT` before ship's Phase 7 poll.
  - `.github/workflows/**` in the diff makes the PR UNTRUSTED-CI: auto-merge only.
- **Other:**
  - The Sentry org is `jikigai-eu`. No Sentry read is needed.
  - Markdown lint runs through `bash scripts/markdown-lint.sh` (the pinned single invoker).
  - No planned path matches preflight's `SENSITIVE_PATH_RE` (checked).
  - `c4-count-parity.test.sh` is green on the base (12/12).

### Institutional learnings

- `2026-09-27-a-log-line-is-evidence-about-the-step-that-printed-it.md`: each pinned line is cited
  by its step.
- `2026-09-17-evidence-verdicts-need-verbatim-provenance-not-summarized-attribution.md`: each flip
  cites the verbatim annotation or field it rests on, with the command that read it.
- `2026-06-29-c4-source-edit-requires-regenerate-model-json-orphan-suite.md`: regenerate
  `model.likec4.json` in the same commit.
- `2026-06-18-c4-impact-requires-reading-all-diagrams-and-enumerating-external-actors.md`: the
  Phase 5 enumeration.
- `best-practices/2026-06-18-doc-insertion-stales-cross-artifact-line-citations.md`: this plan cites
  anchors only.
- The #9036 plan (`plans/archive/20260927-132247-2026-09-27-docs-adr-237-accepted-host-key-step-4-plan.md`)
  kept the Status paragraph byte-identical. Nothing parses ADR `status:` (re-checked for ADR-220 and
  ADR-239: no test or script reads either).

### Plan review provenance

Kieran, DHH and code-simplicity reviewed v1 of this plan. The mechanical fixes applied in v2:

- **The #8189 step-5 record:** it now names run 35119099336, which is also the true history behind
  #6680's closure.
- **Deletion checks:** `numstat` replaces `grep '^-[^-]'`, which cannot see a deleted bullet.
- **The workflow check:** YAML equality plus `grep -F` for the target text, instead of relying on an
  unreachable SHA.
- **The fetch:** `refs/pull/9048/head` is fetched before the apply.
- **The #7226 item wording:** it no longer contradicts the unticked steps 1–3 beside it.
- **Lint:** it runs through `scripts/markdown-lint.sh`.
- **The positive C4 check:** added.
- **Removed:** the line-number PM1 and the duplicate test tables.

The taste splits are recorded in
`knowledge-base/project/specs/feat-one-shot-8211-pr2-pm4-docs/decision-challenges.md`.

## Implementation Phases

### Phase 1 — make the source commit reachable, and re-read the one mutable fact

1. Run `git fetch origin pull/9048/head`, then check
   `git cat-file -e 0f5cf8934f^{commit}`.
2. Confirm that `git diff 0f5cf8934f HEAD -- .github/workflows/git-data-cutover.yml` prints nothing.
3. Confirm that no newer git-data host or boot exists. Two reads (the exact commands are in
   Research Insights):
   - The Hetzner `GET` must still return id `167392038`, created `2026-09-25T09:24:32Z`.
   - The Better Stack `boot_complete` query must still return exactly one row, at
     `2026-09-25 09:25:30`. An in-place rebuild keeps the id but boots again, so a newer row would
     mean a different current boot.

   If either read differs, ADR-239 must not flip on the 2026-09-25 boot line: stop and re-plan
   Phase 4.

### Phase 2 — workflow header (re-apply the held-back text)

```bash
git show 0f5cf8934f -- .github/workflows/git-data-cutover.yml | git apply -R
```

Result (comment lines only):

```text
#   4. the store is served by the LUKS mapper with the bootstrap's store marker bound to it, is
#      not frozen, and its repositories directory holds no entry (git-data-cutover.sh store
#      probes, read in one ssh session, ADR-239).
…
# called systemd units that do not exist. This dry run is the `proof`; the flip and rollback
# are rebuilt on real mechanisms in #8211.
```

### Phase 3 — ADR-220: D1b accepted (append one amendment-log entry)

After the last entry, append `### 2026-09-27 (#8211 PR2, post-merge): D1b is accepted`, with about
four statements:

- **The condition as restated by the entry above is met.** Run
  [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990), from `main` at
  `ab4a07e5e0`, 2026-09-27, read:
  - `role=git-data-auth verdict=ok`;
  - `store-mounted`, `store-on-mapper`, `store-verified`, `store-empty` and `fence-shape`, each
    `verdict=ok`;
  - `verdict=clear`.

  Both hops were pinned (ADR-237 `accepted`, PR #9036).
- **History, stated once.** The 2026-09-15 form of the condition was first met by run
  [35119099336](https://github.com/jikig-ai/soleur/actions/runs/35119099336) on 2026-09-16. That run
  was unpinned and predates the fence probe. It closed #8189 and #6680, but the flip was not
  recorded then.
- **`probe=config`** emits no `ok` notice, because it annotates only on refusal. It passed: the
  run reached the access gate and ended `verdict=clear`.
- **The caveat, as restated on 2026-09-27:** a pinned host authenticates the host, not the truth
  of its answers, so `store_not_empty` and the bounded probes stay.
- **D5, restated for the D1b row:** D1b authenticated hop is `accepted` (2026-09-27). D1a is
  unchanged. D2–D3 stay `proposed`: their #7226 limb is now met (ADR-237 `accepted`), while the
  #8211 limb and ADR-241 R1/R7 remain. D4 stays standing constraints, except its first residual,
  which closed when ADR-237 became `accepted` (per the 2026-09-21 entry).
- **The frontmatter stays `proposed`,** because D2–D3 are `proposed`. Dated text above is
  unchanged.

### Phase 4 — ADR-239: accepted

1. Change the frontmatter from `status: adopting` to `status: accepted`. Leave `## Status`
   byte-identical.
2. Before `## References`, append `## Amendment 2026-09-27 — accepted (#8211 PR2, post-merge)`:
   - **The flip rule in Status is met in production.** `hcloud_server.git_data` (Hetzner id
     167392038, created 2026-09-25T09:24:32Z by replace run
     [36118115758](https://github.com/jikig-ai/soleur/actions/runs/36118115758), after rung-2
     rehearsal run 36029201848) emitted `stage:boot_complete` at 2026-09-25T09:25:30Z. It read
     `luks_mounted=yes fence_on_mapper=yes erasure_probe=yes`. The query was the runbook's host-key
     step 5 (b), with the raw row printed.
   - **It is the current instance.** No git-data replace or create has succeeded since.
   - **The rung-2 precondition in Status is met.** Rehearsal run 36029201848 is bound by the
     committed evidence `apps/web-platform/infra/git-data-rung2-boot-evidence.env` ("Rehearsal host
     : soleur-git-data-rehearsal-36029201848", landed by PR #8751). The replace gate refuses without
     it.
   - **The same row proves the 2026-09-24 amendment in production:** `plaintext_journal=dirty
     plaintext_empty=yes`. That amendment named this flip rule as its production proof.
   - **What `accepted` does not change:** `GIT_DATA_STORE_ENABLED` stays off. The flip, the
     flag-off rollback, the redeploy and the ADR-220 D6 rotation remain on #8211.

### Phase 5 — C4

1. **The comment block.** Replace the sentences from `Root authentication is TARGET:` through `…with
   the store probes and the fence probe clear).` with one line:
   `Root authentication is LIVE (ADR-220 D1b accepted 2026-09-27).` Keep the `github`-vs-`hetzner`
   sourcing rationale.
2. **The label.** Replace `Transport LIVE; root authentication TARGET until ADR-220 D1b flips (the
   post-merge root-key apply, fingerprint PR and git-data replace deliver the key, then a dispatch
   from main reads role=git-data-auth verdict=ok with the store probes and the fence probe clear).`
   with `Transport and root authentication LIVE (ADR-220 D1b accepted 2026-09-27).`
3. **The ADR-237 clause in the same label.** Replace `(ADR-237; effective when the strict dry run
   after the first key-rotating git-data replace reads role=git-data-auth verdict=ok)` with
   `(ADR-237, accepted 2026-09-27)`.

   This is a taste call, kept: the LIVE authentication claim depends on those pins, and the old
   clause presents them as pending. See `decision-challenges.md`.
4. **The `gitDataStore` element description (deepen-plan, architecture review).** It still says
   "…FATALed on that volume's dirty journal, so no host serves the store until the forward fix
   (#5274) boots." The forward fix booted on 2026-09-25, and that boot is the evidence ADR-239
   flips on. Replace `, so no host serves the store until the forward fix (#5274) boots.` with:
   `; the forward fix (ADR-239 amendment 2026-09-24) booted 2026-09-25 (replace run 36118115758)
   and serves the still-empty store from the LUKS mapper (ADR-239 accepted 2026-09-27).`
5. **Regenerate.** Run `bash scripts/regenerate-c4-model.sh` and commit `model.likec4.json`.
6. **C4 completeness.** All three `.c4` files were read:
   - In `model.c4`, the truth of two things changes: this edge, and the `gitDataStore`
     description's "no host serves the store" clause (step 4).
   - The `claude -> gitDataStore` "TARGET state … store is empty until the LUKS cutover" label
     concerns the store's contents, and it stays true.
   - The `gitDataStore -> betterstack` label's "Post-#8178 read path: TARGET state, unobserved
     until the first post-merge git-data dispatch" is stale (#8178 is closed, and two replaces have
     polled that channel since). It is not a D1b or ADR-239 marker, so it is seen and left alone
     here.
   - In `views.c4` and `spec.c4`, nothing changes.
   - Actors, systems, containers and access relationships are all unchanged.
   - No cardinality is added, and `c4-count-parity` must stay green.

### Phase 6 — runbook `git-data-luks-cutover-5274.md` (add lines only)

1. **Preconditions, bullet `**#7226 / #5914**`.** Insert a new first sub-item:

   ```markdown
   - [x] #7226 — closed 2026-09-22 by PR #8511; ADR-237 is `accepted` (PR #9036, host-key step 4).
   ```

   Leave every existing line as it is, including the dated `[x] Mechanism: PR #8511 (pending merge
   at the time of writing)` line.
2. **Host-key item `4. **Strict dry run.**`** Insert one new continuation line after the item's
   text:

   ```markdown
   **Done (2026-09-25):** run [36119817656](https://github.com/jikig-ai/soleur/actions/runs/36119817656); ADR-237 `accepted` (PR #9036).
   ```

3. **Post-merge order item `5. **Dry run.**`** Insert one new continuation line:

   ```markdown
   **Done:** first met by run [35119099336](https://github.com/jikig-ai/soleur/actions/runs/35119099336) (2026-09-16, before the fence probe and host-key pinning); met as now worded by run [36339208990](https://github.com/jikig-ai/soleur/actions/runs/36339208990) (2026-09-27, `verdict=clear`, #5914 issuecomment-5859802570).
   ```

4. **Tick nothing else.** Host-key steps 1–3, 5 and 6 and Post-merge order steps 1–4 stay as they
   are.

### Phase 7 — verify and ship

- **Checks.** Run the Acceptance Criteria checks locally (they are all cheap), then push and let CI
  run.
- **Commit.** Use `LEFTHOOK_EXCLUDE=bun-test,plugin-component-test git commit …`.
- **Ship.** Export `CLAUDE_PLUGIN_ROOT` before the Phase 7 poll.
  - Merge by auto-merge only (`gh pr merge --auto --squash`), because the PR is UNTRUSTED-CI. Say so
    in the PR body.
  - The required checks must be green by name on the exact head SHA.
  - The PR body carries `Ref #8211` and `Ref #5914`, and no `Closes`.

## Files to Edit

- `.github/workflows/git-data-cutover.yml` (header comment only)
- `knowledge-base/engineering/architecture/decisions/ADR-220-git-data-root-access-via-web-1-jump-and-a-dedicated-terraform-minted-key.md` (append only)
- `knowledge-base/engineering/architecture/decisions/ADR-239-git-data-serves-from-luks-at-birth.md` (frontmatter `status:` plus an appended amendment)
- `knowledge-base/engineering/architecture/diagrams/model.c4`
- `knowledge-base/engineering/architecture/diagrams/model.likec4.json` (regenerated)
- `knowledge-base/engineering/operations/runbooks/git-data-luks-cutover-5274.md` (add lines only)

The pipeline also writes this plan and `knowledge-base/project/specs/feat-one-shot-8211-pr2-pm4-docs/`
(`tasks.md`, `decision-challenges.md`, and any `session-state.md`), and it may regenerate
`knowledge-base/INDEX.md`.

## Files to Create

None beyond the pipeline artifacts above.

## Open Code-Review Overlap

None. The 86 open `code-review` issues were checked against the five target files, with no match.

## Architecture Decision (ADR/C4)

### ADR

No new ordinal. Two existing ADRs record status changes, both as in-scope tasks:

- ADR-220: the D1b row, through the amendment log (Phase 3);
- ADR-239: the frontmatter plus an amendment (Phase 4).

### C4 views

In the Container view, only the `github -> gitDataStore` edge prose changes (Phase 5). The
enumeration against all three `.c4` files is in Phase 5 step 5, backed by a green `c4-count-parity`
run.

### Sequencing

No soak. Both flips rest on evidence that already exists.

## User-Brand Impact

- **If this lands broken, the user experiences:** nothing at runtime. The PR changes Markdown, the C4
  model and a YAML comment. The flag stays off and the store holds no repository. The real risk is a
  false record: an ADR reading `accepted` when its rule is unmet would mislead the next cutover
  decision. The evidence is quoted with its commands, and Phase 1 re-reads the one fact that can
  change.
- **If this leaks, the user's data is exposed via:** no vector. The records carry run ids, a Hetzner
  server id and public host-key fingerprints, all already public. No `workspace_id` and no erasure id
  enters the diff.
- **Brand-survival threshold:** `none`
  - threshold: none, reason: a docs/comment-only change with no runtime, data or credential surface,
    and no path matching preflight's `SENSITIVE_PATH_RE`.

## Observability

This PR changes no runtime surface: the workflow edit is comment-only (AC1 proves YAML equality).
The block exists because deepen-plan Phase 4.7 counts any `.github/workflows/*.yml` path as
non-docs. It declares the existing signals that the records point at.

```yaml
liveness_signal:
  what: "git-data-cutover.yml run conclusion plus its check-run notices (role=*, probe=*, verdict=clear)"
  cadence: "on dispatch only (workflow_dispatch; this PR adds no trigger)"
  alert_target: "the dispatching session reads the annotations; no page (read-only proof)"
  configured_in: ".github/workflows/git-data-cutover.yml (unchanged by this PR except header comments)"
error_reporting:
  destination: "GitHub Actions job annotations (::notice/::warning/::error) on the cutover job"
  fail_loud: "yes: any non-clear verdict exits non-zero and reds the run"
failure_modes:
  - mode: "the re-applied header text drifts from the proof's real checks"
    detection: "AC1 greps plus YAML equality at PR time"
    alert_route: "red required check on the PR"
  - mode: "the C4 model is edited without regenerating model.likec4.json"
    detection: "plugins/soleur/test/c4-model-freshness.test.sh in CI"
    alert_route: "red required check on the PR"
logs:
  where: "GitHub Actions run logs for git-data-cutover.yml"
  retention: "GitHub default Actions log retention"
discoverability_test:
  command: "grep -c -F -e 'ADR-220 D1b accepted 2026-09-27' knowledge-base/engineering/architecture/diagrams/model.c4"
  expected_output: "2"
```

The probe passed `plugins/soleur/skills/preflight/scripts/probe-verb-gate.sh` (rc 0). It prints `0`
before the edit, and `2` after it (the comment line and the label).

## Domain Review

**Domains relevant:** none

No cross-domain implications at plan time. **Amended at review (CLO ruling, 2026-09-27):** the
Art. 30 register's PA-36 (g)(13) said the root key "will authenticate" while this PR records root
authentication as LIVE, so the CLO ruled an append-only, tense-only Superseded marker there plus a
dated discharge addendum in `knowledge-base/legal/audits/2026-09-counsel-review-8189.md`. PA-36
stays declared, not live; #8634 still owns Art. 30 activation for ADR-239.

## Acceptance Criteria

### Pre-merge (PR)

- [x] **AC1. Workflow: comment-only and on target.**
  - The YAML is equal to base:

    ```bash
    python3 -c 'import yaml,subprocess as s; a=yaml.safe_load(s.check_output(["git","show","origin/main:.github/workflows/git-data-cutover.yml"])); b=yaml.safe_load(open(".github/workflows/git-data-cutover.yml")); assert a==b'
    ```

    It must exit 0.
  - `grep -cF "the store is served by the LUKS mapper with the bootstrap's store marker bound to it, is" .github/workflows/git-data-cutover.yml`
    prints `1`.
  - `grep -cF 'This dry run is the' .github/workflows/git-data-cutover.yml` prints `1` (the closing
    sentence that names the dry run as the `proof`).
  - `grep -cF 'mounted on a plaintext device' .github/workflows/git-data-cutover.yml` prints `0`.
- [x] **AC2. ADR-220 is append-only.**
  - `git diff --numstat origin/main...HEAD -- <ADR-220> | awk '{print $2}'` prints `0`.
  - `grep -cF '### 2026-09-27 (#8211 PR2, post-merge): D1b is accepted' <ADR-220>` prints `1`.
  - `grep -m1 '^status:' <ADR-220>` prints `status: proposed`.
- [x] **AC3. ADR-239 flips, and nothing else is removed.**
  - `git diff --numstat origin/main...HEAD -- <ADR-239> | awk '{print $2}'` prints `1`.
  - `git diff origin/main...HEAD -- <ADR-239> | grep -E '^-([^-]|$)|^--[^-]'` prints exactly
    `-status: adopting`.
  - `grep -m1 '^status:' <ADR-239>` prints `status: accepted`.
  - `grep -cF '## Amendment 2026-09-27 — accepted (#8211 PR2, post-merge)' <ADR-239>` prints `1`.
- [x] **AC4. C4.**
  - `git grep -c 'TARGET until ADR-220 D1b' -- knowledge-base/engineering/architecture/diagrams/`
    prints nothing.
  - `git grep -c 'no host serves the store until the forward fix' -- knowledge-base/engineering/architecture/diagrams/`
    prints nothing.
  - `git grep -c 'Transport and root authentication LIVE (ADR-220 D1b accepted 2026-09-27)' -- knowledge-base/engineering/architecture/diagrams/model.c4`
    prints `…model.c4:1`.
  - `bash plugins/soleur/test/c4-model-freshness.test.sh` and
    `bash plugins/soleur/test/c4-count-parity.test.sh` are green.
- [x] **AC5. Runbook: add-only, exact ticks.**
  - `git diff --numstat origin/main...HEAD -- <runbook> | awk '{print $2}'` prints `0`.
  - `grep -cF -- '- [x] #7226 — closed 2026-09-22 by PR #8511' <runbook>` prints `1`.
  - `grep -c '35119099336' <runbook>` prints `1`, and `grep -c '36339208990' <runbook>` prints `2`
    (amended at review: the host-key step 4 Done line also cites the clean re-run, per the #5914
    comment that names 36339208990 as that step's run too).
- [x] **AC6.** `bash scripts/markdown-lint.sh <ADR-220> <ADR-239> <runbook>` exits 0.

## Test Scenarios

The Acceptance Criteria are the scenarios. CI additionally runs every suite that reads the workflow
file (`git grep -l git-data-cutover.yml -- '*.test.*'`, 8 files) and the
`apps/web-platform/test/c4-*.test.ts` render and syntax suites. All of them must be green on the
head SHA.

## Sharp Edges

- **Add lines only in the ADRs and the runbook.** Appending text to an existing line turns into a
  deletion, and AC2/AC5 will red. Do not "fix" dated records next to the new lines: the `Mechanism
  … pending merge` line and ADR-237's "step 5 … is blocked on #8211 PR2" both stay.
- **`0f5cf8934f` exists only via `refs/pull/9048/head`.** Fetch it first. If `main` has touched the
  workflow header before this lands, `git apply -R` fails. In that case, re-apply the text from
  `0f5cf8934f^:.github/workflows/git-data-cutover.yml` over the new base by hand, keeping `main`'s
  other changes; AC1's YAML equality and greps still decide the result.
- **Re-read `model.likec4.json` after any sync.** A Phase 7 sync of `main` that edits `model.c4`
  requires regenerating it again.
- **The Hetzner read is `GET` only.** `prd_terraform` is read, never written.

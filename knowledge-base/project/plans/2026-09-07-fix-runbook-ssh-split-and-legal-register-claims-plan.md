---
title: "Runbook SSH three-way split, legal off-host log claims, Art. 30 PA8 log-retention bound, and register-lint promotion"
type: fix
date: 2026-09-07
slug: fix-runbook-ssh-split-and-legal-register-claims
branch: feat-one-shot-7874-7786-6474-7787-runbook-ssh-legal-registers
issue: 7786
closes: 7786, 6474, 7874, 7787
priority: p1-high
domain: legal, engineering
brand_survival_threshold: single-user incident
requires_cpo_signoff: true
lane: cross-domain
---

# Runbook SSH three-way split, legal off-host log claims, Art. 30 PA8 log-retention bound, and register-lint promotion

## Overview

Four open issues, **one PR**, from one branch.

- **#7874** — the residual SSH-in-runbook debt across three runbooks, split three ways so no
  future reader mistakes a preserved diagnostic for removable debt.
- **#7786** — three published legal documents (and their three Eleventy mirrors) deny
  off-host log shipping in one clause while disclosing it in another.
- **#6474** — the Art. 30 register's PA8 §(f) cites a container-log cap the running
  container does not use, anchored to a line number that has already rotted.
- **#7787** — promote `scripts/lint-legal-registers.sh` from advisory to blocking.

**#6474 parts (3), (4) and (5) are already discharged** — the two `__TBD_*__` placeholders by
PR #7782, the DSAR runbook's `docker inspect … .LogPath` step by PR #7872, and the "open PR"
referent is closed issue #3754. **No `TC_VERSION` bump**: the bump rubric is scoped to
`docs/legal/terms-and-conditions.md`, which this PR does not touch.

No `spec.md` exists for this branch (the pipeline entered at `plan`), so `lane:` defaulted to
`cross-domain` (TR2 fail-closed).

---

## Enhancement Summary

**Deepened 2026-09-07.** Panels: 7 plan-review agents (DHH, Kieran, code-simplicity,
architecture-strategist, spec-flow-analyzer, CTO devex, CPO) + a scoped strong-model consult;
then 5 deepen agents (observability-coverage-reviewer, git-history-analyzer,
legal-compliance-auditor, test-design-reviewer, network-outage deep-dive). All halt gates
(4.6 user-brand, 4.7 observability, 4.8 PAT, 4.9 wireframe, 4.10 encryption, 4.11 guard contract)
pass; 4.5 and 4.7 telemetry emitted. Citation verification: **56/56 confirmed** — no fabricated or
retired rule ID, ADR, PR, SHA, label or milestone.

**Five claims in earlier drafts of this plan were measured FALSE and are retracted in place.**
That is the enhancement worth recording, because each would have shipped:

1. *"The ship hook is a second consumer of the heading."* Its `last-resort` grep sits behind two
   early exits on **added** lines; this PR adds no `SSH_RE`-matching line, so it never fires.
2. *"Pseudonymised at the VRL boundary."* A production record pulled 2026-09-07 carries
   `pii_scrub_applied: "drop_userdata+string"` — no `+structured`. The HMAC transform
   short-circuits; the hash is computed in the application's pino logger. This would have
   published a misattribution of the same class the PR exists to retire, one clause away.
3. *"The lint harness has no case-count floor."* `MIN_CASES=51` exists and is exactly pinned. The
   real hazard is the inverse — adding cases without raising it disarms the floor.
4. *"`CORRECTION_NOTE` matches the register's bracket form."* It does not, and the probe never
   reads `knowledge-base/legal/` at all.
5. *"#7851 tracks the 'paid-tier default' retention statement."* Zero live instances in the
   published copies (#7772 discharged them); the only one is in the DPA template, outside #7851's
   scope. Deferring it would have left it tracked by nothing.

**Two defects were found in the plan's own new machinery**, both measured GREEN as originally
specified: the Phase 0 carve leaks across an adjacent `Resolved` heading (fixed: assign, not OR),
and the anti-vacuity floor `checked == len(SURFACES) * len(DOCS)` is satisfied by `DOCS = []` at
`0 == 0` (fixed: absolute literals). Five of Guard 1's six mutation rows were GREEN against the
real 51-case harness; three named fixtures now close them.

**Scope grew on evidence, not appetite:** a third `30 MB` site in the register (§(b)(vi)) and a
fourth wrong date inside §(f) itself; a second `gdpr-policy.md` occurrence carrying none of the
retired literals; the §2.3(m) dual-enumeration collision across six citing sites; seven DPA-template
sites; `model.likec4.json`; and a `re_evaluation_triggers` entry in a signed-off counsel review that
Phase 6 fires and nothing discharged.

---

## Research Reconciliation — Issue Claims vs. Codebase

Only the rows that **changed the plan's shape**. Each was measured, not inferred.

| Claim | Reality (measured) | Plan response |
|---|---|---|
| 7874(b): "move the probes under that heading so the gate's ignore-region applies" | The heading carve exists but is **unreachable for a fenced host-login line**: `scan_text` handles a fence at step 3 and `continue`s before the carve check at step 5. Reproduced both ways. Corpus-wide, `git grep -nE '^#{1,6}[[:space:]]*Last-resort diagnosis' -- '*.md'` returns **zero** — the arm is untested dead code with no users. | Make the heading work rather than route around it. Phase 0 adds a 3-line, heading-scoped lint fix; Phase 1 renames the two probe subsections in place so the carve reaches them. See `## The Design Question, Answered`. |
| 7874(b): "move those probes" (relocation) | Relocation breaks both runbooks. `admin-ip-drift.md` `## Diagnosis` states "L3 (firewall) must be cleared before any L7 hypothesis"; the `## Symptom` transcript is the discriminator that routes the reader to `ssh-fail2ban-unban.md`; that runbook's probe is **Step 6 of a numbered 6-step procedure**. | Nothing moves. Only two subsection *titles* change, in place. |
| 7874(a): "do not edit the 3 false positives" | **Not achievable.** `changed_files()` selects *paths* while `scan_text` reads whole files, so grandfathering is file-granular: touching `admin-ip-drift.md` surfaces all **five** of its findings. The teeth are **lefthook** (`lefthook.yml`, `{staged_files}` into the same whole-file scanner) — **the commit is blocked locally**. The CI arm is advisory: `lint-bot-statuses` is absent from `scripts/required-checks.txt` and `ci.yml` says twice that a PR can merge with it red. | The three get their own **inline, same-line** ignore markers, labelled and owned by **#6806**, prose untouched — plus a comment on #6806 recording the same-PR coupling, because a note in a suppressed file has no trigger. |
| *(not in any issue)* | **PA8 §(b)(vi) is a THIRD `30 MB` site**, outside §(f) and outside any bracket: "for diagnostic recall beyond the 30 MB Hetzner Docker json-file buffer **in §(f)**". It also carries "post-PR #4279", the wrong date for the application stream. | Phase 4.1 corrects three sites, not two. Without this the sweep AC cannot pass, and the register would point at a cell that has just retracted the figure. |
| *(not in any issue)* | **`docs/legal/data-protection-disclosure.md` §2.3(m) numbers twice inside one bullet** — an outer (i)/(ii) over the two telemetry streams, and an inner (i)/(ii) over Better Stack's two recipient roles. `privacy-policy.md` §5.14, the register's Better Stack vendor row and `gdpr-policy.md` §3.7 all cite the **inner** numbering; Phase 3 rewrites the **outer** (i). | Disambiguate the outer pair to `(A)`/`(B)` and sweep all four citing sites. Without it the PR makes a published cross-reference — "§2.3(m)(i) … carries no personal data" — newly false. |
| *(not in any issue)* | `knowledge-base/legal/data-processing-agreement-template.md` Schedule 4 item 12 says "Pino structured logs (**Hetzner Docker rolling buffer**)" and item 11 "post-2026-05-21 #4279"; §8.3 and item 9 point at DPD §2.3(m). A customer-facing contract carrying the same false mechanism and the wrong date. | Folded into Phase 3. |
| 7874(b): "4 findings, all the same" | **Two sub-classes.** `admin-ip-drift.md:22` and `ssh-fail2ban-unban.md:23` are `$`-prefixed failure **transcripts** in a ` ```text ` fence under `## Symptom`. `admin-ip-drift.md:177` and `ssh-fail2ban-unban.md:126` are the genuine terminal verification probes. | Named separately in the diff and the PR body. |
| 7874(c): "reach the host via cloud-init / Terraform" | **Unavailable today.** The target is the Phase-2 **Robot dedicated GEX44** — the runbook states "not Cloud/`hcloud`", "**Not** Cloud TF birth". Robot uses `installimage`, not cloud-init; `git ls-files '*.tf'` shows no root for grok/GEX. | Defer with a tracked issue. `hr-all-infrastructure-provisioning-servers` **binds** (real debt); `hr-fresh-host-provisioning-reachable-from-terraform-apply` does **not** (not a prod service under `apps/<app>/infra/`). |
| 7786: "four files" | **Six.** `docs/legal/privacy-policy.md` (§5.10) and its mirror carry the same claim and are in no issue's scope. Verified: `grep -rn 'no off-host'` → 6 files. | Fold both in. |
| 7786: "live since 2026-05-21" | **Two streams.** `f08ac4c46` (2026-05-21, #4279) shipped **host** journald + host_metrics. `223364c14` (2026-06-02, #4786) added `[sources.app_container_journald]` matching `CONTAINER_NAME = ["soleur-web-platform"]` — the **application container's** stdout, which is what the stale clause is about. | The replacement clause carries **2026-06-02 (#4786)** for the application stream, 2026-05-21 (#4279) for the host plane. |
| 7786: "do NOT caveat the Better Stack disclosure" | Honoured for the **conclusion**. But §2.3(m)(ii) contains a **falsified ground** — "under processor-DPA terms" — while the register and `compliance-posture.md` record Better Stack as "NOT EXECUTED — no Art. 28(3) instrument recorded". The register's 2026-09-03 correction (#7717) **assigns that published sentence to #7786's scope**. | Re-ground on the register's three limbs (no Art. 4(12) event; intra-EU CZ → `eu-central-1a`; payload pseudonymised in the application before egress). The conclusion is untouched. |
| 6474: scope is the register | The same false mechanism is **in the published corpus**: `docs/legal/data-protection-disclosure.md` §2.3(m) and `docs/legal/privacy-policy.md` §5.14 both say "30 MB Hetzner Docker json-file rolling buffer", plus both mirrors. Verified: `grep -rn '30 MB'` → 4 files. | #6474 and #7786 cannot be separated. Same phase. |
| 6474(1): "correct §(f)" | Live, and **worse than filed**: the claim appears **twice** in the cell — the opening clause *and* "The **mechanism is the record**: 30 MB rolling per container". The 2026-09-03 correction rested the whole Art. 30(1)(f) discharge on it. Its anchor `cloud-init.yml:303-310` is already rotted (the block is ~458-461). | Correct both sites; re-anchor to an executable assertion. |
| 7787: promotion trigger | **Discharged with margin.** 14/14 green `test-scripts` runs on `main` since the gate landed (`5d8a12736`, 2026-09-04); **zero** `::warning::lint-legal-registers` ever emitted, across two substantive legal amendments (#7803, #7838). Replaying predicate (a) over all 12 legal-corpus commits since 2026-06-01: 4 post-gate → 0 hits; 7 pre-gate → 1 hit each, and that hit was a **true positive** fixed by #7782. | Promote. No scope change is a precondition. |
| 7787: "delete `--advisory`, nothing else" | The `# PROMOTION: delete the --advisory flag on the next line` comment becomes a **false instruction** the moment the flag is gone. | Documented deviation: the comment block is rewritten in the same edit. Recorded in `decision-challenges.md`. |
| *(not in any issue)* | **`/ship` Phase 5.5's Counsel-Review CLO-Attestation Gate fires on this PR** (`legal_touch` non-empty AND `brand_survival_threshold: single-user incident`) and **mandates** producing `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md`. Every prior such file quotes Art. 4(12)/33(5), matching `lint-legal-registers.sh` predicate (c)'s producer. | **Without mitigation, Phase 6 would red the required `test` context on the PR that promotes the gate.** Phase 5 pre-authors the waivers; Phase 6 is gated on a post-Phase-5.5 green run. This is the most consequential thing research found. |

---

## The Design Question, Answered (#7874)

The issue asks *"which heading the gate actually honours, and whether the ignore-region or the
section name is the contract."* Verified against source **and by execution**.

**1. The carve exists.** `scripts/lint-infra-no-human-steps.py`, `_is_carve_heading`:

```python
if re.match(r"Last-resort diagnosis\b", t, re.IGNORECASE):
    return True
```

Prefix-anchored with a trailing `\b` (so a suffix still carves); case-insensitive; any heading
level; leading non-alpha decoration stripped. The region ends at the next heading of
**equal-or-higher** level (`elif carve and level <= carve_level`). `Last resort diagnosis`
(no hyphen) does **not** carve.

**2. It is unreachable for the only form these findings take.** `scan_text`'s loop order is
(1) ignore-region, (2) fence toggle, (3) `if in_fence:` → the #7286 host-login exception sets
`actor[i] = imper[i] = True` and `continue`s, (4) heading/carve toggle, (5) `if carve: continue`.
Step 3 returns before step 5. Measured:

| Fixture | Result |
|---|---|
| Fenced host-login under `## Last-resort diagnosis` | `FAIL: 1 prescribed human-run infra step(s)` |
| Same, wrapped in a `lint-infra-ignore` region | `OK: no human-run infra steps in 1 scanned file(s)` |
| Unfenced prose under `## Last-resort diagnosis` | `OK` |
| Same prose, heading renamed | `FAIL` |

**3. The ignore region is the only thing that works today — and that is the wrong answer.**
Three artifacts assume a contract the linter does not implement: `hr-no-ssh-fallback-in-runbooks`
("SSH-class goes in a 'Last-resort diagnosis' section ONLY, after 3 tries"), the ship hook's
remediation text, and `recover-userid-from-pino-stdout.md`'s prose. Shipping regions alone would
make this PR the first user of a heading that does nothing, and would establish that an SSH probe
can be suppressed **anywhere** with an HTML comment and no last-resort framing — the exact
gaming-the-gate reading the rule exists to prevent.

**4. `.claude/hooks/ship-runbook-ssh-gate.sh` is NOT a consumer of this diff.** Its last-resort
grep sits behind two early exits on **added** lines:

```bash
added=$(git diff --unified=0 "$BASE"...HEAD -- "$f" | grep -E '^\+[^+]' | sed 's/^+//')
[[ -z "$added" ]] && continue
hits=$(printf '%s\n' "$added" | grep -niE "$SSH_RE" || true)
[[ -z "$hits" ]] && continue
```

This PR adds no line matching `SSH_RE`, so `hits` is empty and the filter never executes. An
earlier draft of this plan claimed the hook as a second consumer; that claim was **false** and is
retracted here.

**5. The answer: the SECTION NAME is the contract, and this PR makes that true.** Phase 0 makes
the carve reach a fenced host-login line **only** under a `Last-resort diagnosis` heading —
never under the sibling `Resolved` arm, and never generically. That is not a revert of #7286
(whose fix was "look inside fences at all"); it is the one heading the hard rule names.
**Measured blast radius: zero** — no such heading exists anywhere in the corpus, so nothing that
passes today starts failing and nothing that fails today starts passing.

Ignore regions survive for exactly the two cases where no last-resort framing applies and the
suppression means something different: **class (a)** (a false positive owned by #6806) and
**class (c)** (real debt deferred to a tracked issue).

---

## Hypotheses

The gate fired on `SSH`/`firewall`/`unreachable`/`handshake` and
`hr-ssh-diagnosis-verify-firewall` telemetry was emitted. This plan edits the runbooks that
*encode* the L3→L7 diagnosis rather than diagnosing a live outage, so the four layers are
dispositioned against **the edit's change surface**. Per the checklist's own rule,
"obvious"/"unlikely" without an artifact is not a valid opt-out — each row carries one.

| Layer | Disposition | Artifact |
|---|---|---|
| **L3 — firewall allow-list** | **Preserved, verified.** No prescribed edit touches `admin-ip-drift.md` `## Diagnosis` (egress IP → Doppler → `hcloud firewall describe` → diff). | The lint's finding lines are `admin-ip-drift.md:22,37,177,210,227` and `ssh-fail2ban-unban.md:23,126` — **every edit site is outside `## Diagnosis`**. A rename-only simulation clears 177 alone; 210 and 227 still flag, proving the carve terminates at `## Prevention` and does not bleed into `## Sharp Edges` / `## Do NOT`. |
| **L3 — DNS / routing** | **Opt-out with artifact.** Neither runbook resolves a hostname on the SSH path — the host is addressed as a literal IP at every step, so there is no resolver hop for the edit to reorder and the edit adds none. | `grep -nE '135\.181\.45\.178\|soleur\.ai'` over both runbooks: six literal-IP sites on the SSH path, one hostname site (`## Symptom`'s "HTTPS 200 on `app.soleur.ai`"), and that site is prose **below** the wrapped fence, outside every edit. |
| **L7 — TLS / proxy** | **Opt-out with artifact.** The change surface is two markdown files; no HTTPS path is modified. | The cross-layer discriminator ("host is otherwise reachable: `hcloud server list` shows `running`, HTTPS 200 on …") sits below the ` ```text ` fence the Phase 1.2 region wraps; verified byte-identical after a simulated edit. |
| **L7 — application (sshd journal)** | **Preserved, verified.** The journal-absence signal is the load-bearing routing discriminator and is untouched in both files. | The three inline markers land at `## Root Cause`, `## Sharp Edges` and `## Do NOT` — none in `## Symptom` or `## Diagnosis`. |

**Ordering discipline survives.** `admin-ip-drift.md` `## Diagnosis` states it in its own words
("L3 (firewall) must be cleared before any L7 (sshd, fail2ban) hypothesis is considered. This
ordering is enforced by AGENTS.md `hr-ssh-diagnosis-verify-firewall`"), carries the fall-through
to `ssh-fail2ban-unban.md`, and that runbook carries the reverse pointer. All four carriers are
prose outside every wrapped fence and every marker.

**Blast radius of Phase 0, measured corpus-wide:** a before/after finding-set diff over all 9,562
tracked `*.md` files is **0 lines**.

**Constraints this yields on the edit** — the only shape that satisfies all four layers is
*suppress and reframe in place*: the `## Symptom` transcript is the discriminator and cannot move
or be reworded; Step 6 of 6 cannot be relocated. Relocation is ruled out on evidence, not taste.

---

## Mechanism Minimality

**Property list:**

| # | Property |
|---|---|
| P1 | A future reader of the diff cannot mistake a preserved diagnostic for removable debt. |
| P2 | The three runbooks pass `lint-infra-no-human-steps.py` without any diagnostic losing its meaning or its L3→L7 position. |
| P3 | No published legal document asserts that application logs have no off-host copy. |
| P4 | No published or statutory document asserts a log-retention mechanism the running container does not use. |
| P5 | The false claims in P3/P4 cannot silently return **after merge**. |
| P6 | A finding in the legal registers fails CI; an "I cannot decide" fails it regardless of advisory mode. |
| P7 | No architecture record describes the same data flow more narrowly than the corrected legal record. |

**Cut list:**

| Mechanism | Property | Why cut |
|---|---|---|
| A generic widening of the carve to all fenced content | P2 | Reverts #7286's deliberate scoping. Phase 0 is heading-scoped instead. |
| Relocating the probes to a bottom section | P2 | Violates the three diagnostic constraints above. |
| Binding every `lint-infra-ignore` region to a carve heading | P1/P2 | 139 `lint-infra-ignore start` occurrences under `knowledge-base/`, 41 in runbooks + ADRs across ~24 files. Non-zero protected surface ⇒ grandfathering. Deferred (Phase 8.1). |
| A Terraform root for the GEX44 host | 7874(c) | Robot dedicated is not `hcloud`-managed; no cloud-init channel exists. Deferred. |
| Bumping `TC_VERSION` | P3 | Rubric not engaged; would force every user to re-accept the Terms for a notice-document change. |
| A caveat on the Better Stack disclosure | P3 | Out of scope per #7786; the stale clause is the false one. |
| A new corpus-truth guard | P5 | `scripts/probe_legal_corpus_truth.py` already iterates `{canonical, mirror} × {privacy-policy, gdpr-policy, data-protection-disclosure}` with a `FORBIDDEN` list, a `REQUIRED` positive arm and a `CORRECTION_NOTE` stripper. Extend and wire it — do not rebuild it. |
| A `## Last-resort diagnosis` section containing only a pointer | P1/P2 | Buys nothing once Phase 0 lands: the renamed subsections carry the heading, so a separate empty section has no consumer. |

---

## User-Brand Impact

- **If this lands broken, the user experiences:** the published page at
  `https://soleur.ai/legal/data-protection-disclosure/` §2.3(m) continues to tell them, in
  clause (i), that their application logs sit in a Hetzner-local buffer with "no off-host
  copies", while clause (ii) of the *same bullet* names Better Stack as a recipient. The same
  contradiction stands on `https://soleur.ai/legal/privacy-policy/` §5.10 against §5.14. A user
  cannot answer "where do my logs go?" from our own page.
- **If this leaks, the user's workflow content is exposed via:** pino WARN/ERROR/FATAL lines
  from the user-serving `soleur-web-platform` container — carrying `userIdHash`, conversation
  identifiers, request metadata and error stack traces — egressing through
  `[sources.app_container_journald]` → `[transforms.app_container_warn_filter]`
  (`level_int >= 40`) in `apps/web-platform/infra/vector.toml` to Better Stack Logs source
  `2457081`, retained 90 days, under an Art. 28(3) instrument the Art. 30 vendor mapping records
  as "NOT EXECUTED" (#7529, #7825).
- **If this lands half-corrected, the user experiences:** a register that *looks* reviewed while
  `docs/legal/privacy-policy.md` §5.14 still cites "the 30 MB Hetzner Docker json-file rolling
  buffer" — a corpus still false, having consumed the next reviewer's suspicion.
- **Brand-survival threshold:** `single-user incident`

CPO sign-off obtained at plan time (see `## Domain Review`). `user-impact-reviewer` runs at
review time.

---

## Implementation Phases

Phases are ordered by dependency. **Phase 6 is last and is gated on Phase 5.5 having run** —
see the hazard in `## Research Reconciliation`'s final row.

### Phase 0 — make the sanctioned heading actually work (`scripts/lint-infra-no-human-steps.py`)

1. Split `_is_carve_heading` into two predicates, or have it report which arm matched: add
   `_is_last_resort_heading(title)` carrying the existing `Last-resort diagnosis` regex verbatim.
   `_is_carve_heading` keeps both arms so the `Resolved` behaviour is unchanged.
2. Track `carve_last_resort` alongside `carve` / `carve_level`. **Assign, never OR** — set it
   with `carve_last_resort = _is_last_resort_heading(title)` *inside* the
   `if _is_carve_heading(title):` branch, and clear it in the `elif`.

   **This is load-bearing and the obvious form is wrong.** The existing clearing rule lives only
   in the `elif`, which is skipped whenever the *next* heading is itself a carve heading. So the
   sequence `## Last-resort diagnosis` → `## Resolved` (equal or shallower level) takes the `if`
   branch, resets `carve_level`, and would leave `carve_last_resort` still true — silently
   suppressing a fenced host-login line under `## Resolved`. Not reachable today (zero
   last-resort headings exist), but Phase 1 creates the first two. Guard 1 row 7 pins it.
3. In the in-fence branch, gate the host-login exception:
   `if HOST_LOGIN_RE.search(raw) and not carve_last_resort:`.
4. Extend `scripts/lint-infra-no-human-steps.test.sh` with the fixtures Guard 1 names — including
   the three currently-missing ones, without which five of its six mutation rows are GREEN.
5. **Raise `MIN_CASES` to the new exact total in the same edit.** An earlier draft of this plan
   claimed "the harness has no case-count floor today; add one". **That was false** — the floor is
   at `scripts/lint-infra-no-human-steps.test.sh`, `MIN_CASES=51`, and it is *exactly* pinned
   (measured `PASS=51 FAIL=0 TOTAL=51`), so deleting a case reds right now. Retracted here as an
   `hr-verify-repo-capability-claim-before-assert` miss in the plan's own prose.

   The real hazard is the opposite: adding k cases and leaving `51` alone gives the floor k lines
   of slack and **disarms harness row (a) by the very edit meant to strengthen it**. Set it to the
   new exact `TOTAL`, with a comment that the value is exactly pinned, not a slack floor. Note the
   second-order limit: `TOTAL` is incremented by both `pass()` and `fail()`, so the floor detects a
   *deleted* case but never a *neutered* one — asserting the sorted set of case names would, and is
   the better shape if the floor is ever revisited.
6. Leave the `Resolved` arm, the ignore-region ordering and every other behaviour untouched.
7. **Pin the two predicates together.** After 0.1 the literal `Last-resort diagnosis` lives in
   both `_is_carve_heading` and `_is_last_resort_heading`. Derive one from the other, or assert
   they agree — nothing else does.
8. **Make full-scan mode fail-closed.** With zero collected files `main()` prints
   `OK … 0 scanned file(s)` and exits 0. Guard 1's dispatch row is unreachable through `run_case`
   (every case passes an explicit positional path, and `main()` short-circuits on `if args.paths:`),
   so the durable fix is in the SUT: zero collected files in full-scan mode exits 2.

Blast radius is measured at zero: no `Last-resort diagnosis` heading exists in the corpus.

### Phase 1 — #7874(a)(b): the two SSH-diagnosis runbooks

Files: `knowledge-base/engineering/operations/runbooks/admin-ip-drift.md`,
`.../ssh-fail2ban-unban.md`.

1. **Class (b-probe) — no ignore region needed once Phase 0 lands.** Rename the two enclosing
   subsection titles so the carve reaches the fenced probes, in place, with no content moved.
   **The disambiguation must reach the HEADING, not only the prose below it** — the misreading
   happens at the heading (table of contents, skim, `grep -i 'last.resort'`):

   - `### Step R3 -- Verify` →
     `### Last-resort diagnosis (SSH channel, after the no-SSH probes) — Step R3: confirm SSH is restored`
   - `### Step 6: Verify from the operator machine` →
     `### Last-resort diagnosis (SSH channel — not the noVNC channel of last resort) — Step 6: confirm SSH is restored`

   The title must **begin** with `Last-resort diagnosis`; the parenthetical is verified safe
   against the real predicate (prefix-anchored `re.match` with a trailing `\b`, decoration
   stripped), and it matches the existing house convention — `inngest-server.md` and
   `oauth-probe-failure.md` both write *"Last-resort diagnosis (on-host, only if the HTTP route
   is itself down):"*. These are the **only two removed lines** in the whole runbook diff.

   This also removes the need to split `admin-ip-drift.md`'s Step R3 fence: the carve covers the
   whole section (bounded by `## Prevention`, measured), so the `hcloud firewall describe` line
   beside the probe is not hidden by a region that would also absorb future additions.

   **The collision is directional, and there are three senses — not two.**
   `ssh-fail2ban-unban.md` declares *"Channel of last resort: Hetzner Cloud Console (noVNC
   in-browser)"* about the **whole procedure**, whose premise is that SSH is down. The renamed
   Step 6 is the one step that **is** SSH, from the operator laptop. A heading-skimming reader
   would get "when all else fails, try SSH from your laptop" — the inversion of the runbook's
   premise — and be routed away from `## If This Runbook Does Not Work`, the document's actual
   terminal section. A third sense already exists in the sibling file: `admin-ip-drift.md`
   carries `# Last-resort fallback:` inside `## Diagnosis` Step 1's curl chain (the third
   IP-echo service), which is an L3 probe, not an SSH step.

   Each renamed section therefore gains a reader-visible sentence that **opens by naming the
   section terminal**, before it carries the precondition:

   > *This is the terminal verification of the recovery above, not an entry point — do not start
   > here. Reach it only after Steps 1–N have run and the no-SSH probes are exhausted, per
   > `hr-no-ssh-fallback-in-runbooks`.*

   plus, in `ssh-fail2ban-unban.md`: *"last resort" here names the SSH **probe**, not the
   recovery **channel** — the channel of last resort is the noVNC console named in the header,
   and the escalation path when this runbook fails is `## If This Runbook Does Not Work`*;
   plus, in `admin-ip-drift.md`: *distinct from the `# Last-resort fallback:` curl service in
   `## Diagnosis` Step 1, which is an L3 probe.*

   Neither section moves, so the L3→L7 order and both numbered procedures stay intact, and no
   new `##`-level entry point is created. No separate `## Last-resort diagnosis` section is
   appended: it would have no reader path into it and would duplicate
   `## If This Runbook Does Not Work`, which already serves that role.
2. **Class (b-transcript)** — the two `## Symptom` fences. Pasted failure transcripts, not steps;
   the `## Symptom` heading cannot be renamed because it is the reader's entry point and the
   discriminator that routes between the two runbooks. Wrap each **fence** in a
   `lint-infra-ignore` region (block-form markers are safe here — a fence is not a paragraph or a
   list), rationale on the start marker: *transcript, not a prescribed step; owner #7874.*
3. **Class (a-false-positive) — three separate INLINE, SAME-LINE markers.** The three findings in
   `admin-ip-drift.md` are prose, and two of them sit inside constructs a block-form HTML comment
   would damage: the operator-egress-IP sentence is **mid-paragraph** under `## Root Cause`, the
   "until the operator confirms" finding is **inside a `## Sharp Edges` list item**, and the
   prohibition is **inside a `## Do NOT` list item**. A CommonMark HTML block interrupts a
   paragraph and terminates a list, and `grep '^-[^-]'` cannot detect that because insertions are
   not deletions.

   `IGNORE_START_RE`/`IGNORE_END_RE` use `.search()` on the raw line and `continue`, so a
   start+end pair **on the same line suppresses exactly that line and nothing else**. Precedent:
   `knowledge-base/engineering/operations/runbooks/git-data-birth.md`, the single-line region
   beside its bootstrap step. Rationale rides the start marker
   (the `lint-infra-ignore start: …` marker form; precedent `web-host-replace.md`).

   **Three markers, never one region.** A single region spanning the first to the last finding
   would cover ~190 lines — `## Diagnosis` Steps 1–4, both Recovery sections, `## Prevention` and
   all of `## Sharp Edges` — suppressing every future violation in the operative body of the
   runbook, invisibly.

   Each rationale states: negation-context / possessive-actor false positive, **owner #6806,
   remove in the same PR that narrows the lint's producer**, and that the marker exists only
   because the scanner reads whole files. **The prose is unchanged.**
4. **Post a comment on #6806** listing the three markers by file + content anchor and recording
   that the marker removal and the producer narrowing must land in the same PR, or
   `admin-ip-drift.md` reds. A note in the suppressed file has no trigger — `harvest-debt`
   excludes `*.md` by pathspec (Phase 8.5). The issue comment is the mechanism.
5. Unaffected by this PR, recorded so the next author does not re-derive it:
   `inngest-server.md` and `oauth-probe-failure.md` carry an **inline bold-prose** "Last-resort
   diagnosis (on-host, …)" convention beside the step it governs. Those files contain no
   host-login command, so neither the carve nor a region applies to them; Phase 0 does not change
   their behaviour. The heading form introduced here is the enforceable one.

### Phase 2 — #7874(c): the grok dogfood provisioning debt

File: `knowledge-base/engineering/operations/runbooks/grok-build-hetzner-dogfood.md`.

1. File the deferral issue: *"grok GEX44 dogfood host has no IaC birth path (Robot dedicated, not
   `hcloud`)"* — `domain/engineering`, `type/chore`, `priority/p3-low`, milestone
   `Post-MVP / Later`. Body records the three host-login lines under
   `### Bootstrap (after OS is up)`; that `hr-all-infrastructure-provisioning-servers` binds and
   `hr-fresh-host-provisioning-reachable-from-terraform-apply` does not; that
   `hr-every-new-terraform-root-must-include-an` binds on remediation; and the two candidate
   paths (Robot `installimage` post-install script, or a first-boot systemd unit baked at order
   time). Re-evaluation trigger: the GEX44 order being placed (#6546 gates on spend ack).
2. Wrap the fenced block in a `lint-infra-ignore` region naming that issue and the binding-rule
   analysis in one line. **Class (c) — REAL DEBT, deferred with a named remediation path.** Not a
   false positive, not a sanctioned diagnostic. The heading is *not* renamed: this is not a
   last-resort diagnosis, it is provisioning, and framing it as the former would be the
   gaming-the-gate move.
3. The existing in-fence `hr-ssh-diagnosis-verify-firewall` pointer stays.

### Phase 3 — #7786 + #6474 published corpus: retire both false claims

| File | off-host sites | 30 MB sites |
|---|---|---|
| `docs/legal/data-protection-disclosure.md` | 2 (§2.3(m)(i) + Retention limb) | 1 (§2.3(m)) |
| `docs/legal/gdpr-policy.md` | **2** (§3.7 — the second carries NO retired literal, see below) | 0 |
| `docs/legal/privacy-policy.md` | 1 (§5.10) | 1 (§5.14) |
| `plugins/soleur/docs/pages/legal/data-protection-disclosure.md` | 2 | 1 |
| `plugins/soleur/docs/pages/legal/gdpr-policy.md` | **2** | 0 |
| `plugins/soleur/docs/pages/legal/privacy-policy.md` | 1 | 1 |

1. **Framing: affirmative, one sentence, register language.** The minimal framing (delete the
   parenthetical, let the existing disclosure carry it) is **rejected on the facts**: §2.3(m)(ii)
   says the Vector agent "reads journald (which mirrors pino stdout from
   `inngest-server.service`)" and §5.14 says "the Web Platform **inngest plane**" — both name the
   *background job server only*. The `soleur-web-platform` stream is a different emitter,
   disclosed nowhere. Deleting the parenthetical converts a self-announcing contradiction into a
   silent omission, which is strictly worse.
2. Replacement content: the container runs under the journald log driver; on-host retention is
   journald-governed, bounded by `min(SystemMaxUse=1G, free space − SystemKeepFree=2G)` and
   **shared with every unit on the host**. (This also retires "rolling **Docker** log buffer",
   false independently of the off-host clause.)

   **Do not write "floored by `SystemKeepFree=2G`".** That inverts the control: the config file
   states it plainly — journald *stops writing* when free space drops below 2 GB, and it
   *"overrides SystemMaxUse when disk is tight"*. It can only **shorten** retention, driven by
   unrelated disk usage; a data subject would read "floored" as a guaranteed minimum. Publishing
   that would be a fresh misleading retention statement inside the clause being corrected.

   **Say that the on-host journal retains ALL levels.** Only the `level >= 40` subset egresses;
   the config file's own comment records the distinction. Stating only the egress filter would
   let a reader conclude it bounds what is retained anywhere.

   **Say that the 1 GB cap is shared.** Because it is host-wide, the record cannot express a
   limit "for the different categories of data" at all — this container's window is a function of
   other units' emission. Stating that explicitly is what stops `SystemMaxUse=1G` being read as a
   per-stream bound, i.e. the same class of error being retracted.

   The `level >= 40` subset of the user-serving application container's logs has shipped to
   Better Stack Logs since **2026-06-02 (PR #4786)**; host journald and `host_metrics` since
   2026-05-21 (PR #4279); retention there is 90 days.
3. **Attribute the pseudonymisation to the APPLICATION, not to Vector — this was measured live
   and the obvious framing is false.** A production record pulled 2026-09-07 via
   `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep userIdHash`
   carries `source_kind: "app_container"`, pino `level: 50`, an intact `userIdHash`, and the tag
   `pii_scrub_applied: "drop_userdata+string"` — **no `+structured`**.
   `[transforms.pii_scrub_structured]` short-circuits on `if !exists(parsed_obj.userIdHash)`, so
   the HMAC stage never runs on this stream: the hash is computed **in the application's pino
   logger, before the line reaches journald**. Vector contributes the Art. 9 key drop and the
   string backstop, and is a no-op HMAC backstop here.

   So "pseudonymised at the VRL boundary" is not wrong about raw-`userId` lines — **it does not
   govern this stream**, which is precisely the "governs other containers, not this one" shape
   this PR exists to retire. Publishing it as a ground for the no-Art. 4(12) conclusion would
   reproduce the defect one clause away from its correction. Ground it on what the live tag
   proves. The register's carve-out still applies separately: the `soleur-registry` direct zot
   shipper traverses no Vector and computes no `userIdHash` at all.
4. **No correction bracket on a published page.** Dated `**[… CORRECTION …]**` brackets are the
   register's convention. Published pages get currently-true statements plus a `Last Updated`
   bump; the audit trail goes in the register (Phase 4).
5. Correct the Better Stack limb's three defects: date + emitting unit; the falsified ground
   "under processor-DPA terms" (re-grounded on the register's three limbs — no Art. 4(12) event,
   intra-EU CZ → `eu-central-1a`, and the payload pseudonymised in the application before
   egress per Phase 3.3 — NOT "at the VRL boundary"; the no-notification **conclusion** is
   untouched); and the stale `AC15 of PR #4293` pointer, whose escalation is
   now **#7529**. **That pointer is live at four sites, not two** — DPD and its mirror, plus
   `docs/legal/privacy-policy.md` §5.14 and its mirror. Sweep all four.

   **This limb is owned by #7851, not #7786.** `knowledge-base/legal/audits/2026-09-counsel-review-7717.md`
   records three published statements describing an executed instrument — §2.3(m)'s "under
   processor-DPA terms", §5.14's "SCCs incorporated", and both copies' "Better Stack paid-tier
   default" retention — and files them at **#7851, separately from #7786**. This PR discharges
   the first because leaving a known-false Art. 28(3) assertion beside a corrected clause is not
   an option; it does **not** touch the other two. See `## Open Code-Review Overlap`.

5b. **Disambiguate §2.3(m)'s dual enumeration before rewriting outer (i).** The bullet numbers
   twice: an outer `(i)`/`(ii)` over the two telemetry streams, and an inner `(i)`/`(ii)` over
   Better Stack's two recipient roles. Three published/statutory sites cite the **inner**
   numbering — `privacy-policy.md` §5.14 ("the heartbeat surface disclosed in … §2.3(m)(i) …
   carries no personal data"), the register's Better Stack vendor row, and `gdpr-policy.md` §3.7.
   Rewriting outer (i) into an affirmative shipping clause makes those pointers **newly false**.
   Renumber the outer pair to `(A)`/`(B)`, leave the inner `(i)`/`(ii)` alone, and sweep **six**
   citing sites (an earlier draft said three): `privacy-policy.md` §5.14 + mirror,
   `gdpr-policy.md` §3.7 + mirror, the register's Better Stack vendor row, **the register's PA8
   §(d)** ("recorded in DPD §2.3(m)(i)"), **`compliance-posture.md`** ("recorded in DPD
   §2.3(m)(i)"), and **the DPA template's Schedule 2 reconciliation note** ("disclosed in DPD
   §2.3(m)(ii)"). `compliance-posture.md` is one of the four files the promoted lint scans, so a
   stale pointer there is also a Phase 6 hazard.

5c. **`gdpr-policy.md` §3.7 routes the reader to `DPD §4.2` for processors, and §4.2 has no
   Better Stack row.** After the edit §3.7 affirmatively discloses off-host shipping and still
   points at a table that does not name the recipient. Add the row, or repoint the sentence at
   `privacy-policy.md` §5.14 — the corpus already records the §4.2 refresh as a pre-existing
   reconciliation gap, so adding one row is the smaller change.

5d. **`knowledge-base/legal/data-processing-agreement-template.md`** — a customer-facing
   contract carrying the same false mechanism. **Seven sites, not four:** Schedule 4 item 12
   ("Pino structured logs (**Hetzner Docker rolling buffer**)"), item 11 ("post-2026-05-21 #4279"
   — the wrong date for the application stream), and item 9 plus §8.3 pointing at DPD §2.3(m).
   Then three more that no issue's scope reaches.
   **Schedule 2's "Operational telemetry" retention cell** reads "90 days (Sentry) + Hetzner
   rolling buffer + Better Stack paid-tier default"; without it, after this PR Schedule 4 says
   journald while Schedule 2 still says "Hetzner rolling buffer" — a contradiction **inside one
   customer-facing contract, newly created by this PR** — and it is the only live "paid-tier
   default" instance in the repo (see `## Open Code-Review Overlap`).
   **The Schedule 2 reconciliation note** says the DPD §4.2 vendor-table refresh "is a
   pre-existing reconciliation gap, tracked for the next legal-doc consistency sweep"; Phase 3.5c
   closes that gap, so the note becomes false on merge, and the plan cites this very note as its
   *justification* for 5c — it must retire it in the same commit.
   **Schedule 4 item 16** — "Sentry + Better Stack detection mediated by `userIdHash`
   pseudonymisation" — is the blanket claim Phase 3.3 forbids in the published corpus; apply the
   same scoping here.
6. Carry `[DRAFT — pending CLO/counsel review per #7786]` markers on the edited clauses. `/ship`
   Phase 5.5 strips them on DISCHARGED; they are what makes the gate's draft-marker arm fire
   deterministically rather than depending on the threshold arm alone.
7. `Last Updated` moves in **nine places** (an earlier draft said six): 3 canonical body lines,
   3 mirror hero `<p>` lines, 3 mirror body lines — `apps/web-platform/test/legal-doc-consistency.test.ts`
   compares heading sequence plus `**Last Updated:**` parity across the mirror hero `<p>` and the
   body line.
8. Refresh `LEGAL_DOC_SHAS["data-protection-disclosure"]`, `["gdpr-policy"]`,
   `["privacy-policy"]` in `apps/web-platform/lib/legal/legal-doc-shas.ts` via
   `sha256sum docs/legal/<doc>.md`. **Unconditional** — there is no equivalent of the
   `TC_VERSION`-bump bypass for notice documents.
9. **Do not enrol** these three in `BODY_EQUIVALENCE_DOCS`; they are drifting and enrolling a
   drifted document turns a required check red on arrival. Correct
   `knowledge-base/legal/tc-version-bump-policy.md` §"Body-equivalence scope (interim)", which is
   stale against the shipped array.
10. **Add an operational-log retention entry to the two sections a reader actually consults for
    "how long".** `docs/legal/privacy-policy.md` §7 (Data Retention) and
    `docs/legal/gdpr-policy.md` §8.5 (Third-Party Retention) carry **no** operational-log or
    telemetry entry today — §8.5 names Anthropic, GitHub and R2 only. This PR newly puts a 90-day
    off-host window into §5.10/§5.14/§3.7, and the bump policy's Tier 1 list names *"new retention
    period"* explicitly, so a retention section that omits the period the PR just classified is
    internally inconsistent. One sentence each, cross-referencing §5.10/§5.14 and §3.7 — the
    wider per-processor retention rebuild (aligning §7's category axis with §5's processor axis,
    adding Sentry) is properly separate and goes to Phase 8.8.
11. Correct `knowledge-base/engineering/operations/runbooks/betterstack-log-query.md`
    (`**Container log retention moved to journald.**` bullet): it says the explicit `SystemMaxUse`
    sizing "is tracked as a follow-up infra task" — that follow-up landed in PR #4800. It asserts
    the wrong bound in the opposite direction from the register.

### Phase 4 — #6474: PA8 §(f), the trigger lists, and the accountability record

1. `knowledge-base/legal/article-30-register.md` PA8 §(f) — **additive dated bracket**, the file's
   own convention. It must:
   - **Retract the misattribution at both sites** — the opening clause and the `NOT RECORDED`
     paragraph's "The **mechanism is the record**: 30 MB rolling per container". The json-file cap
     is not wrong about the *daemon default*; it governs other containers, not this one. Say
     misattributed, not deleted.
   - **State the redirect with both PRs and the gap window.** Driver switch: `223364c14` /
     **PR #4786** (issue #4773). Bound: `faf9ea95e` / **PR #4800** (issue #4792). Between them the
     effective bound was journald's implicit default. State what is true **today**:
     `SystemMaxUse=1G`, floored by `SystemKeepFree=2G` (which overrides it when disk is tight),
     `RuntimeMaxUse=200M` pre-flush, **shared with every unit on the host — not a per-container
     bound at all**.
   - **Preserve the `NOT RECORDED` disposition.** Art. 30(1)(f) requires the envisaged time limit
     "where possible"; a capacity-bounded buffer has none, and journald is also capacity-bounded.
     But "where possible" is not a licence for "we did not look": the discharge is lawful only
     where the record states why no limit exists, **what bound does govern**, and the unblocking
     condition. It currently gets the middle one wrong — which is why the cell is not presently a
     valid discharge. **Deliver all three.** The only unblocking condition in the cell today
     belongs to the *Better Stack* limb, which #7772 has since DISCHARGED at 90 days, so the
     on-host limb would otherwise ship failing the plan's own stated test: either prescribe an
     unblocking condition for it or state in-cell that none exists and why.
   - **Re-anchor to executable evidence** (`cq-cite-content-anchor-not-line-number`):
     `apps/web-platform/infra/journald-config.test.sh` → the assertion `assert "SystemMaxUse=1G"`
     with condition `grep -qE '^SystemMaxUse=1G$' '$DROPIN'`, under the block heading
     `--- AC1: journald-soleur.conf [Journal] section + caps ---`; plus its CI registration, the
     `.github/workflows/infra-validation.yml` step named `Run journald persistent-storage tests`.
     The existing `cloud-init.yml:303-310` anchor is rotted and is itself a live rule violation.
   - **Do not produce an observed-volume figure.** §(f) warns "the mechanism is the durable record
     and a single day's rate is not". No MB/day measurement exists in the repo; the only committed
     figure is ~101,000 rows/day, which is rows on a different plane.
   - **Correct the wrong date inside §(f) itself** — the Better Stack limb reads "off-host copy,
     post-PR #4279". For the application-container stream the date is #4786 / 2026-06-02. It sits
     in the very cell being rewritten and would otherwise ship un-amended beside the correction.
   - **Correct the THIRD site: PA8 §(b) Purposes, limb (vi)** — "Off-host long-tail operational
     log aggregation (Better Stack Logs, post-PR #4279) for diagnostic recall beyond the 30 MB
     Hetzner Docker json-file buffer **in §(f)**". Bare prose, outside §(f) and outside any
     bracket. Both the figure and the date are wrong, and the pointer would send a reader to a
     cell that has just retracted the figure. Phase 4.1 corrects **three** sites, not two.
2. **Amend the CLOSED trigger list — both copies, and bring them to PARITY, same PR.**
   `recover-userid-from-pino-stdout.md` `### Re-verification triggers` states: *"The trigger list
   is **closed** — adding a fifth trigger requires updating the PA8 §(f) row and this runbook in
   the same PR."* Add trigger **5**: any change to `apps/web-platform/infra/journald-soleur.conf`
   (anchor on the `SystemMaxUse=` line), and mirror it into §(f)'s differently-worded
   `**Re-verification triggers:**` clause.

   **The closure clause is already breached and this PR must repair it.** §(f)'s 2026-09-04
   (#7772) bracket added a *second* trigger clause — "any change to a source's `logs_retention`;
   the creation of any further source on team `520508`" — **without** the runbook update the
   closure clause mandates. Fold those two into the runbook's numbered list (as 6 and 7, marked
   FIRED/discharged per its existing convention). Otherwise this PR leaves the runbook at 5 and
   §(f) at 7 while committing prose that asserts the lockstep held. The AC asserts **list
   parity**, not the presence of one trigger.

   **Re-scope trigger 2 in the same edit.** It anchors on `cloud-init.yml`'s `daemon.json` block
   (the `"log-driver": "json-file"` line) — the mechanism this very PR retracts as non-governing.
   A closed trigger list whose second entry watches a surface the register has just declared
   irrelevant is the Art. 5(2) defect Phase 4.4 is filing, reproduced two steps earlier. Either
   re-point it at the `docker run --log-driver` invocation or mark it superseded by trigger 5.
3. Lockstep the runbook's two descriptions of the register's claim with the corrected §(f).
4. `knowledge-base/legal/compliance-posture.md` `## Active Compliance Items` — the
   trigger-that-did-not-operate row. Trigger 2 anchors on the `daemon.json` block and **did not
   fire** when #4786/#4773 moved the container to the journald driver, because the change was to
   the `docker run` invocation. Trigger 4 covered it in principle and **also did not operate** —
   marked FIRED only retroactively on 2026-09-06, roughly three months late. A closed trigger list
   that does not fire is an **Art. 5(2) accountability defect in the control itself**. Use the row
   schema committed as an HTML comment in that section, and anchor the row on the runbook's
   trigger **numbering** rather than restating the trigger text — `compliance-posture.md` is a
   file the promoted lint scans, and restating the text would rot three files instead of two on
   the next trigger edit. The defect itself is not repaired here; Phase 8.6 owns it.
5. CLO attestation to `knowledge-base/legal/audits/` — per-artifact verdict plus
   DISCHARGED/BLOCKED disposition, and a `tier_classification:` frontmatter field declaring
   **Tier 1** (peer precedent: `2026-09-04-betterstack-source-split-7772.md`,
   `2026-08-counsel-review-7440.md`). **Auto-routed via the `clo` agent, never an operator task.**

   **It must also discharge a re-evaluation trigger this PR fires.**
   `knowledge-base/legal/audits/2026-09-counsel-review-7717.md` frontmatter lists, verbatim:

   > `- "Promotion of scripts/lint-legal-registers.sh from advisory to blocking (#7787) — the gate's scope changes what the register's completeness claim is worth."`

   **Phase 6 IS that promotion.** A signed-off counsel review names this PR's own terminal commit
   as its re-evaluation condition, and nothing else in the plan discharges it. The attestation
   must record the trigger as FIRED, state what the promotion changes about the register's
   completeness claim, and dispose of it — otherwise Phase 6 silently invalidates the standing
   review it depends on. This is the strongest available objection to Phase 6 and it is closed
   here rather than left for a reviewer to find.

   Note also that the bump policy's "counsel-review ledger" has **no artifact in the repo**
   (`git grep -l 'counsel-review-ledger'` returns only the policy and planning docs). The
   `audits/` tree is the ledger; say so in the attestation rather than leaving the policy
   implying a file that does not exist.
6. **Waiver pair, in the same commit as the attestation.** The attestation's subject matter is a
   bullet whose own text names the Article 33 breach-notification timeline, and Phase 3.5's
   re-grounding says "no Art. 4(12) event" — so it matches `DETERMINATION_PATTERN`
   (`4[[:space:]]*\(12\)|33[[:space:]]*\(5\)|Art\.?[[:space:]]*33|…`) and predicate (c) will
   demand it be indexed or waived. Add the `NOT_TRANSCRIBED` entry to
   `scripts/lint-legal-registers.sh` in the committed `"path | reason citing #NNNN"` shape (an
   uncited waiver is a `die2` refusal, not a pass) **and** the matching `## Excluded records` row
   in `knowledge-base/legal/breach-register.md`, because predicate (d) asserts the two copies
   agree. Do the same for any counsel-review file `/ship` Phase 5.5 emits.

### Phase 5 — durability: wire the corpus-truth probe, and pre-empt the gate it would trip

1. `scripts/probe_legal_corpus_truth.py` — append to `FORBIDDEN` the **five** retired phrasings:
   `no off-host log shipping is configured`, `no off-host copies`,
   `30 MB Hetzner Docker json-file rolling buffer`, `rolling Docker log buffer` (Phase 3.2 retires
   that wording too), and **`fixed-capacity Hetzner-local rolling buffer`**.

   That fifth entry is load-bearing and was nearly missed. `docs/legal/gdpr-policy.md` §3.7 states
   the false mechanism **twice**, and the second occurrence — *"pino stdout retained in the
   fixed-capacity Hetzner-local rolling buffer (see DPD §2.3(m) and §4.2)"* — carries **none** of
   the other four literals. Measured: `grep -o 'Hetzner-local rolling buffer' | wc -l` returns 2
   for that file and its mirror, 1 for every other. Without this entry the second occurrence is
   invisible to AC11's regex, to AC12's `30 MB` grep, and to the durability guard, so P5 would not
   hold for it. This is the same "the claim appears twice in the cell" defect the plan caught in
   PA8 §(f) and had not applied to the published corpus.
1b. **Promote `REQUIRED` from a single string to a list, and add the affirmative anchor.** Today
   `REQUIRED = "EU-US Data Privacy Framework"` — the Chapter V safeguard, unrelated to log
   shipping. With only `FORBIDDEN` extended, the new property is guarded by **absence alone**:
   deleting the clause wholesale passes. That is precisely the framing CPO rejected on the facts.
   Add an affirmative anchor (the Better Stack recipient naming plus the 2026-06-02 date) so the
   probe can tell a correction from a deletion, and iterate `REQUIRED` in the same loop.
2. **Add the anti-vacuity floor — with ABSOLUTE literals, not an expression over the constants
   being mutated.** Count the documents actually examined, assert
   `checked >= MIN_SURFACES * MIN_DOCS` with `MIN_SURFACES = 2` and `MIN_DOCS = 3` as
   hand-ratcheted literals, and **print the count** beside `CORPUS-OK`.

   **The obvious form is vacuous and was measured so.** `checked == len(SURFACES) * len(DOCS)` is
   satisfied by `DOCS = []` — `0 == 0` — and prints `CORPUS-OK (0 document(s) examined)` at rc=0.
   That is exactly the shape of the learning cited two lines below, reproduced inside the floor
   meant to prevent it. The repo already uses the absolute form three times: `MIN_TRACKED_SUITES`,
   `MIN_CHECKS`, `MIN_CASES`. Today the
   probe prints `CORPUS-OK` on zero checks; wiring a vacuous-pass guard as blocking would ship the
   defect this repo has already documented five times
   (`2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md`).
3. **Wire it** into `scripts/test-all.sh` beside the other legal-corpus gates:
   `run_suite "scripts/probe-legal-corpus-truth-live" bash scripts/probe-legal-corpus-truth.sh`.
   A comment records the deliberate live-only registration (no `*.test.sh` exists, so
   `lint-orphan-test-suites.sh` does not require a unit sibling) and names Phase 8.2 as the owner
   of the unit arm. Without this, P5 is bought by nothing: the probe is referenced today only by
   its own docstring and its wrapper's `exec`.
3b. **Register it in `REQUIRED_RUNNERS`** — `scripts/lint-orphan-test-suites.sh`. Add
   `"scripts/probe-legal-corpus-truth.sh"` to the array and raise its hand-ratcheted floor from
   `< 6` to `< 7` in the same edit. **Without this the wiring is a one-line disarm:** deleting the
   `run_suite` line from `test-all.sh` would silently un-gate the corpus with no signal anywhere.
   That array's own comment records this exact failure being fixed for `lint-legal-registers.sh`
   at #7717 — *"deleting its `run_suite … --advisory` line from test-all.sh was the cheapest
   single-line disarm on the guard"*. Repeating it for a guard whose subject is a silently-false
   published claim would reproduce the learning rather than discharge it. This is also what makes
   Guard 2's mutation row 6 true; without the registration that row is GREEN.
4. **Pre-author the waivers for this PR's own legal artifacts.** `/ship` Phase 5.5 mandates
   `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md`, and Phase 4.5 adds a CLO
   attestation; both will quote Art. 4(12)/33(5) and match `lint-legal-registers.sh` predicate
   (c)'s producer. Add a `NOT_TRANSCRIBED` entry for each in `scripts/lint-legal-registers.sh`, in
   the committed `"path | reason citing #NNNN"` shape, plus the matching `§Excluded records` rows
   (predicate (d) checks parity). **This is what stops Phase 6 from reddening the PR that
   promotes the gate.**

### Phase 6 — #7787: promote the register lint to blocking

**Runs last, after Phase 5.5's artifacts exist and `bash scripts/lint-legal-registers.sh` is
green over the tree including them.**

1. Delete the trailing `--advisory` token (together with its leading space) from the
   `run_suite "scripts/lint-legal-registers-live"` line
   in `scripts/test-all.sh`. `--advisory` is not a `run_suite` flag —
   `run_suite() { local label="$1"; shift; … "$@" || rc=$?; }` passes argv through verbatim — so
   the blast radius is exactly this invocation.
2. Rewrite the `# ADVISORY FOR ONE MERGE CYCLE (#7717)` comment block to record the promotion:
   date, PR, evidence summary, retained asymmetry. Leaving
   `# PROMOTION: delete the --advisory flag on the next line` would ship a false instruction.
3. **Do not** remove the `--advisory)` parse arm, its `--help` string, or the three assertions in
   `scripts/lint-legal-registers.test.sh` — they pin the rc=2 asymmetry, which stays load-bearing.
4. **Phase 6 is its own terminal commit**, and the PR body names that commit as the revert unit —
   so an unrelated red is a one-commit revert rather than a rollback of the published-corpus
   correction. This is what the three-PR split was really protecting, obtained without the split.
5. Record five hazards in the PR body. None blocks, but the first three were missing from the
   original framing and the fourth is the one that matters most:
   - **The gate is diff-independent shared state.** `lint-legal-registers-live` sits in the
     `scripts` shard, which the required `test` context depends on for **every** PR, and it scans
     a fixed 4-file array plus the whole `audits/` tree — never the diff. After promotion, drift
     on `main` reds **every open PR and the merge queue**, not only PRs touching the registers.
     "The blast radius is exactly this one invocation" is true of argv passthrough and false of
     the gate's reach.
   - **The producer is not scoped to reviews "of the register".** It is
     `find "$AUDITS_DIR" -type f -name '*.md' | xargs grep -lE "$DETERMINATION_PATTERN"` — **any**
     `audits/` file quoting those article numbers on **any** subject. Three of the ten live
     waivers are already about unrelated matters. Precision is 4/14 ≈ 29%, and 7 of 10 waivers
     are this shape.
   - **Rename or archive of a cited canonical source reds it.** Predicate (b) fails on a cited
     path that is untracked, a symlink, or unresolvable — and `/soleur:archive-kb` moves
     knowledge-base artifacts into `archive/`, which the producer still walks recursively. A
     legitimate future archive breaks the register's pointer and reds every PR until repaired.
   - **A local run before `git add` reds rather than warns.** Predicate (b) requires cited paths
     be git-**tracked**, so the new attestation must be staged before the AC21 measurement means
     anything.
   - `MIN_CHECKS=7` against `checks=7` — zero headroom. (`fail()` also increments `checks`, so a
     genuine finding does not trip the floor; the risk is a future *code* edit removing a `pass`.)
     Append one line to the failure message naming the remedy.

### Phase 7 — C4 lockstep (property P7)

`knowledge-base/engineering/architecture/diagrams/model.c4`. Two edits, both correctness fixes on
the same omission. No element is added, so no `views.c4` change: `betterstack` is already
`#external` and already included in both views. Scope owned by P7, declared rather than
volunteered.

1. **The Vector `hetzner -> betterstack` edge.** There are **two** `hetzner -> betterstack`
   relations; name the target by content anchor, not line number
   (`cq-cite-content-anchor-not-line-number`): the one whose description begins *"Ships journald +
   host_metrics via Vector to the shared Logs source 2457081 (per-host host_name discriminator…"*
   — **not** the sibling carrying `SOLEUR_PRIVATE_NIC` via curl. It under-describes the flow in
   exactly the way the legal corpus does: it names the host telemetry plane and omits the
   user-serving container's pino WARN+ stream carrying `userIdHash`.
2. **The `betterstack` element description.** It enumerates what source `2457081` receives and
   reasons **explicitly about which emitters are Vector-scrubbed for PII** — and never names the
   application container's pino stream, which is the highest-sensitivity payload on that source.
   That is the one description a reader consults for PII reasoning. One clause, same commit.

3. **Regenerate `model.likec4.json` in the same commit.**
   `plugins/soleur/test/c4-model-freshness.test.sh` renders the `.c4` sources and **byte-diffs**
   the committed JSON, and that JSON embeds the edge description verbatim. It is also what
   `apps/web-platform/app/api/kb/c4/[...path]/route.ts` serves to users — so editing only
   `model.c4` both reds the freshness test and leaves the *user-visible* diagram still
   under-describing the flow, which is the exact P7 property this phase exists for.

**Recorded, not fixed:** the model records this egress only at the host layer — there is no
relationship from any application container to `betterstack`, so a reader of the container view
cannot see that application-level logs leave the boundary. That is the same gap one abstraction
level up. It needs no `views.c4` change (both elements are already included) but it is a
modelling decision rather than a label correction, and it is deferred to Phase 8.7 rather than
smuggled into a compliance PR. The C4 enumeration table below records it as a known gap rather
than asserting completeness.

### Phase 8 — follow-up issues (file, do not inline)

1. **The carve/fence precedence divergence, generalised.** Phase 0 fixes the one heading the hard
   rule names; the underlying structural defect remains — signal-setting arms in `scan_text` do
   not route through a shared suppression predicate, and `lint-infra-ignore` regions are
   heading-agnostic so a probe can still be suppressed anywhere. Body carries the deferred Guard
   Contract sketch, the 139/41/~24 grandfathering count, and the note that a fix is ADR-132 class
   (*infra-sentinel suppression precedence*) and needs an ADR.
2. **Unit arm for the corpus-truth probe** — `probe_legal_corpus_truth.test.sh` with a mutation
   matrix, so the live registration Phase 5.3 adds gains its `#7387`-convention sibling.
3. **Narrow `lint-legal-registers.sh` predicate (c)'s producer.** Scope the exclusion on
   frontmatter `type: counsel-review` / `type: clo-attestation` plus a `governing_record:` key and
   the absence of a fact-pattern marker — **not** on "a review *of* the register", which retires
   only 3 of the 7. This is a CLO scoping ruling (#7717, ADR-200), not a devex tweak, which is why
   it does not ride in an already-Tier-1 PR.
4. **grok GEX44 IaC birth path** — filed in Phase 2.1.
5. **`harvest-debt` cannot see in-place deferrals in prose.**
   `plugins/soleur/skills/harvest-debt/scripts/harvest-debt.sh` excludes `*.md` by pathspec, so
   every `SOLEUR-DEBT:` marker in a runbook, ADR or register is invisible to the repo's own
   harvester — the exact shape this PR adds four more of. Independent of this PR.
6. **Make a re-verification trigger actually fire.** Phase 4.4 records that trigger 2 did not
   fire and trigger 4 did not operate — and Phase 4.2 then adds a fifth trigger of the identical
   non-firing kind: prose in a runbook plus a register cell, with no mechanical actuation. That
   is a **live Art. 5(2) compliance defect**, not a documentation one, and this PR diagnoses it
   without remediating it. Candidate mechanism: a path-triggered check (the files named by each
   trigger are all in-repo) that fails when a trigger's anchor file changes without a
   corresponding dated review entry — the same shape as the `#7387` write-time gates. Filed per
   `wg-when-deferring-a-capability-create-a`.
7. **Model the application-to-Better-Stack relationship in C4** (Phase 7's recorded gap): the
   egress is represented only at the host layer, so the container view cannot show that
   application-level logs carrying `userIdHash` leave the boundary.

---

## Decisions taken, not deferred

**PR granularity: ONE PR.** CLO, CTO and CPO each argued for a split on different grounds. It is
resolved here rather than surfaced, because PR granularity is a technical fork and
`hr-technical-fork-is-not-an-operator-question` reserves operator questions for authorization,
cost and scope. Three findings decide it:

- The CLO ruling that the `docs/legal/**` lockstep "must not ride inside a statutory-register
  change" **cannot be honoured by any split**, because the same false "30 MB json-file" mechanism
  is in both the register and four published files. Separating them ships the identical defect
  class this PR exists to fix. (CPO reached this independently and overrode the CLO split.)
- Ordering commits buys nothing on its own: CI evaluates the PR head with every phase applied.
  What de-risks the promotion is the **measurement** — a blocking-mode run of the register lint
  over the tree as this PR leaves it, including the Phase 5.5 artifacts.
- The one real hazard behind the split argument — Phase 5.5's mandated counsel-review file
  tripping the newly-promoted gate — is neutralised mechanically by Phase 5.4's pre-authored
  waivers, not by ordering.

`decision-challenges.md` retains only the two genuine **scope** challenges: the additions to the
"nothing else" in #7787 (the false comment block, and the two waivers the promotion needs in order
to survive), and the reduction of the seven-part scope in #6474 to four live parts.

---

## Open Code-Review Overlap

`gh issue list --label code-review --state open --limit 200` → 63 issues; every path in
`## Files to Edit` / `## Files to Create` matched against their bodies with
`jq --arg path … | contains($path)`. **None.**

Recorded by subject rather than label:

- **#6806** — the negation-context / possessive-actor suppression class. **Acknowledged, not
  folded in:** a lint change with ~41 latent findings is a different risk class from this PR. The
  coupling is written into #6806 itself by Phase 1.4, which is the removal trigger.
- **#7851** — owns the three published statements describing an executed Art. 28(3) instrument.
  **Partially folded in, deliberately:** Phase 3.5 discharges the first ("under processor-DPA
  terms" in §2.3(m)) because leaving a known-false assertion beside a corrected clause in the same
  bullet is not an option. §5.14's "SCCs incorporated" is
  **explicitly out of scope** and remains #7851's; the PR body must say so and must not use
  `Closes #7851`. **The third statement is NOT tracked by anyone, and an earlier draft of this
  plan said it was.** Measured: `git grep -rn 'paid-tier default' -- docs/ plugins/soleur/docs/`
  returns **zero** — #7772 already discharged it in the published copies (both now read
  `**Retention:** **90 days**`). The only live instance is
  `knowledge-base/legal/data-processing-agreement-template.md` Schedule 2, which #7851's
  published-copy scope does not reach. Phase 3.5d folds it in. Deferring it to #7851 would have
  left a reviewer believing it was tracked when nothing tracked it.
- **#7529 / #7825** — the Better Stack Art. 28(3) gap that Phase 3 makes more visible.
  **Acknowledged:** both stay OPEN with a 2026-11-13 re-evaluation; this PR must not read as
  closing them.

---

## Files to Edit

**Lint + guards:** `scripts/lint-infra-no-human-steps.py`,
`scripts/lint-orphan-test-suites.sh` (`REQUIRED_RUNNERS` + its floor),
`scripts/lint-infra-no-human-steps.test.sh`, `scripts/probe_legal_corpus_truth.py`,
`scripts/lint-legal-registers.sh` (two `NOT_TRANSCRIBED` waivers), `scripts/test-all.sh` (the
`lint-legal-registers-live` line + its comment block; the new `probe-legal-corpus-truth-live` line).

**Runbooks:** `knowledge-base/engineering/operations/runbooks/{admin-ip-drift,ssh-fail2ban-unban,grok-build-hetzner-dogfood,recover-userid-from-pino-stdout,betterstack-log-query}.md`.

**Published legal corpus:** `docs/legal/{data-protection-disclosure,gdpr-policy,privacy-policy}.md`
and the three mirrors under `plugins/soleur/docs/pages/legal/`;
`apps/web-platform/lib/legal/legal-doc-shas.ts`;
`knowledge-base/legal/tc-version-bump-policy.md`;
`knowledge-base/legal/data-processing-agreement-template.md` (Schedule 4 items 9/11/12, §8.3).

**Statutory record:** `knowledge-base/legal/article-30-register.md`,
`knowledge-base/legal/breach-register.md` (`§Excluded records` parity rows),
`knowledge-base/legal/compliance-posture.md`.

**Architecture:** `knowledge-base/engineering/architecture/diagrams/model.c4` and the committed
`model.likec4.json` it renders to (byte-diffed by `c4-model-freshness.test.sh`, and served to
users by the KB C4 route).

## Files to Create

- `knowledge-base/legal/audits/<date>-clo-attestation-7786-off-host-log-claims.md` (Phase 4.5)
- `knowledge-base/legal/audits/<YYYY-MM>-counsel-review-<issue>.md` (produced by `/ship` Phase 5.5
  — declared here because Phase 5.4 must waive it)
- `knowledge-base/project/specs/<branch>/decision-challenges.md`
- `knowledge-base/project/specs/<branch>/tasks.md`

---

## Observability

The Phase 2.9 trigger does not strictly fire (no file under `apps/*/server/`, `apps/*/src/`,
`apps/*/infra/` or `plugins/*/scripts/`; no infrastructure introduced). The block is supplied in
full anyway — the deliverable includes three gates, and deepen-plan Phase 4.7's own trigger
(anything not exclusively `knowledge-base/`, `docs/` or `*.md`) does fire on the `scripts/*`,
`.ts` and `.c4` edits.

```yaml
liveness_signal:
  what: "the `scripts/lint-legal-registers-live` and `scripts/probe-legal-corpus-truth-live` suites inside the `test-scripts` job — the two gates this PR promotes and wires"
  cadence: "per push and per merge-queue entry"
  alert_target: "the required `test` context on the PR; a red blocks merge"
  configured_in: ".github/workflows/ci.yml job test-scripts (run: bash scripts/test-all.sh scripts); registrations in scripts/test-all.sh beside the #7387 legal-corpus gates"

error_reporting:
  destination: "GitHub Actions annotations — ::error::lint-legal-registers (rc 1 and rc 2), CORPUS-FALSE on stderr from the truth probe, and lint-infra-no-human-steps FAIL lines. No Sentry surface: these are build-time gates, not runtime code"
  fail_loud: "non-zero rc from run_suite; suite_exit_class maps every non-zero, non-signal rc to failed, so an 'I cannot decide' (rc 2) already blocks today and keeps doing so after the promotion"

failure_modes:
  - mode: "A retired false claim is reintroduced into the published legal corpus"
    detection: "scripts/probe_legal_corpus_truth.py FORBIDDEN arm over both surfaces x three documents, wired blocking in scripts/test-all.sh by Phase 5.3"
    alert_route: "CORPUS-FALSE on stderr, rc=1, red on the required `test` context"
  - mode: "The corpus-truth probe passes while examining nothing"
    detection: "the checked-count floor added in Phase 5.2 (the run_suite wiring is Phase 5.3); the count is printed beside CORPUS-OK"
    alert_route: "rc=1 before any FORBIDDEN comparison is trusted"
  - mode: "An unresolved marker lands in a legal register"
    detection: "scripts/lint-legal-registers.sh predicate (a) over the fixed 4-file REGISTER_FILES list"
    alert_route: "::error:: annotation, rc=1, blocking after Phase 6"
  - mode: "The register lint is disarmed rather than satisfied (a pass call removed)"
    detection: "MIN_CHECKS=7 floor, which exits 1 unconditionally and never consults --advisory"
    alert_route: "::error::lint-legal-registers: only N assertion(s) ran, expected >= 7"
  - mode: "A new host-login step is added to a runbook outside a sanctioned section"
    detection: "scripts/lint-infra-no-human-steps.py, lefthook pre-commit + the CI --changed step"
    alert_route: "commit blocked locally by lefthook (the only blocking arm); lint-bot-statuses annotates in CI but is NOT in scripts/required-checks.txt and does not block merge. Layer 6 — GitHub Actions run log, gh run view --log --job"
  - mode: "An SSH probe is suppressed by an ignore region with no last-resort framing"
    detection: "not covered — regions remain heading-agnostic after Phase 0"
    alert_route: "Phase 8.1; recorded as a known gap rather than claimed as covered"
  - mode: "A section is RENAMED into the Last-resort diagnosis carve to suppress a host-login line that has no last-resort framing"
    detection: "not covered by any standing check — Phase 0 opens this as a SECOND and cheaper suppression channel than the ignore region, and unlike a region (AC7) a carve heading carries no rationale or owning-issue requirement. Detected in THIS PR only by AC3's one-shot whole-corpus finding-set diff"
    alert_route: "Phase 8.1, alongside the heading-agnostic-region gap; both are the same missing control — suppression that names no owner"

logs:
  where: "GitHub Actions run logs for the test-scripts job — gh run view <id> --log --job <jobid>; no host logs are produced or consumed by this change"
  retention: "90 days (GitHub Actions default log retention)"

discoverability_test:
  command: "bash scripts/probe-legal-corpus-truth.sh"
  expected_output: "CORPUS-OK, with a non-zero examined-document count printed beside it (the floor Phase 5.2 adds)"
```

`bash` is on preflight Check 10's `PROBE_VERB_ALLOWLIST`; the wrapper exists because Check 10
rejects shell-active tokens in an inline chain. No credentials; it reads committed files only.

**Encryption Posture:** skipped per Phase 2.11 — no persistent store and no new cross-component
connection. The pre-existing Better Stack egress is described more accurately here, not created.

---

## Guard Contract

### Guard 1 — the `Last-resort diagnosis` carve reaches fenced host-login lines

**Property.** A fenced host-login command is suppressed if and only if it sits inside a
`Last-resort diagnosis` carve region — never under any other carve heading, and never by default.

**Assembly.** Every arm of `scan_text` that writes `actor[i]`/`imper[i]`, and the carve-state
machine that arm must consult. Today there are two such arms (the in-fence `HOST_LOGIN_RE`
exception and the plain-line arm). **Members drift — the guard's contract is that the arms
consult the carve state, not that today's two are correct.** `_is_last_resort_heading` is the
single predicate the state derives from; the `Resolved` arm must remain unable to reach it.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Delete `and not carve_last_resort` from the in-fence arm | RED — the suppression stops working |
| 2 | Make `_is_last_resort_heading` also match the `Resolved` arm, then place a fenced host-login under `## Resolved` | RED via `F-a` — over-suppression; the carve must stay heading-scoped. Measured GREEN without `F-a` |
| 3 | Add a **third** signal-setting arm that bypasses the carve state — concretely: hoist the host-login detection above `if carve: continue` — after arms 1 and 2 are compliant | RED via `F-b`. Second member after a compliant first; without `F-b` this row has no runnable form and reports the baseline |
| 4 | **Guard's own dispatch:** make path collection return `[]` so the run reports `0 scanned file(s)` | RED — but **not reachable through `run_case`**, which always passes an explicit positional path. Closed by Phase 0.8 making full-scan mode exit 2 on zero collected files, which is durable rather than one-shot |
| 5 | Change the literal to `Last resort diagnosis` (no hyphen) | RED — pins the section-name contract |
| 6 | Move the `in_ignore` check to after fence handling | RED via `F-c` — pins the ordering the class (a)/(c) regions depend on. Measured GREEN without `F-c` |
| 7 | **Adjacency:** `## Last-resort diagnosis` → `## Resolved` (equal level) → a fenced host-login line under `## Resolved` | RED — the carve must not leak across an adjacent carve heading. Row 2 tests the predicate; only this row tests the STATE MACHINE, and the obvious `carve_last_resort \|= …` form passes row 2 while failing this one |

**Three fixtures the suite lacks, named here because without them rows 2, 3 and 6 are GREEN — I
measured all three against the real 51-case harness, which stays `PASS=51 FAIL=0` under every one
of those mutants:**

- `F-a` — fenced host-login under `## Resolved` → **rc=1**. Catches row 2. Nothing today asserts a
  carve fixture at all.
- `F-b` — **prose** host-login under a `Last-resort diagnosis` heading → **rc=0**. Catches row 3,
  whose realization (the host-login arm hoisted above `if carve: continue`) is otherwise invisible
  to all 51 cases.
- `F-c` — an ignore-region-wrapped fence containing a host-login → **rc=0**. Catches row 6, and it
  is the direct regression test for **Phase 1.2's own suppression**, which exists nowhere today.
  Measured: moving the `in_ignore` check past the `if in_fence:` block flips this 0→1 while the
  harness stays green.

**Harness rows.** (a) Delete `F-a` and require the suite's floor to fail — see Phase 0.5 for why
that requires *raising* `MIN_CASES` to the new exact total rather than adding a floor.
(b) **Must-PASS, non-canonical:** a fenced host-login line under
`#### Last-resort diagnosis — read-only` (level 4, suffixed, deeper than the surrounding `##`)
must PASS at rc=0, pinning prefix-match + any-level + suffix tolerance in one case that is not the
canonical fixture.

### Guard 2 — the legal-corpus truth probe, wired and non-vacuous

**Property.** No document in the published legal corpus, on either surface, asserts a factual
claim that a dated correction has retired — and the probe cannot report success without having
examined every document.

**Assembly.** The nested loop in `main()` over `SURFACES × DOCS`, each file `CORRECTION_NOTE`-
stripped and tested against every `FORBIDDEN` entry plus the `REQUIRED` positive arm, and the
checked-count floor Phase 5.2 adds. The chokepoint is that single loop; every surface, document
and claim reaches the assertion through it. **`FORBIDDEN` and `DOCS` both grow — the contract is
the loop's total coverage, not today's 3×2×N.**

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Reintroduce `no off-host copies` into `docs/legal/privacy-policy.md` §5.10 | RED (`CORPUS-FALSE: canonical/privacy-policy.md`) |
| 2 | Reintroduce it into the **mirror only**, canonical left correct | RED (`mirror/privacy-policy.md`) — second member after a compliant first |
| 3 | **Guard's own dispatch:** set `DOCS = []` | RED via the Phase 5.2 floor. *Before Phase 5.2 this printed `CORPUS-OK` — that is the defect Phase 5.2 closes.* |
| 4 | **Delete** the corrected clause from `docs/legal/data-protection-disclosure.md` wholesale, rather than correcting it | RED via the **affirmative** `REQUIRED` anchor Phase 5.1b adds. Without that anchor this row is GREEN — a `FORBIDDEN`-only guard cannot tell a correction from a deletion, which is the framing CPO rejected |
| 5 | Reintroduce `30 MB Hetzner Docker json-file rolling buffer` into §2.3(m) | RED |
| 6 | Remove the `run_suite` line Phase 5.3 adds | RED via `lint-orphan-test-suites.sh` REQUIRED_RUNNERS, or the probe silently stops running |

**Harness rows.** (a) Delete row 3's zero-dispatch case from the Phase-8.2 unit suite and require
its case-count floor to fail. (b) **Must-PASS, non-canonical:** a synthetic corpus where the
retired wording appears **only** inside a `*(Corrected YYYY-MM-DD, ref #NNNN: …)*` span must PASS,
pinning the mention-vs-assertion carve-out. **Two claims an earlier draft made about this row were
false and are retracted:** `CORRECTION_NOTE` matches only that `*(Corrected …)*` form and **not**
the `**[YYYY-MM-DD CORRECTION (#NNNN)]**` shape Phase 4.1 mandates; and `SURFACES` is
`{docs/legal, plugins/soleur/docs/pages/legal}`, so the probe **never reads
`knowledge-base/legal/`** at all. The stripper is therefore unexercised by this PR — the row is a
synthetic fixture guarding a real code path, not a rehearsal of Phase 4's output.

### Guard 3 — `lint-legal-registers` promoted to blocking

**Property.** A finding in any of the four legal register files fails the required `test` context,
and an "I cannot decide" fails it regardless of advisory mode.

**Assembly.** One `run_suite` call site invoking one script over the fixed `REGISTER_FILES` array;
`run_suite` passes argv verbatim and `suite_exit_class` maps every non-zero, non-signal rc to
`failed`. The asymmetry's chokepoint is the single `if [[ $fails -gt 0 ]]` branch — the only site
reading `ADVISORY` — with all 11 `die2` exits outside it. One advisory call site among 194, so
there is no sibling to keep consistent.

**Mutation matrix:**

| # | Mutation | Expected |
|---|---|---|
| 1 | Inject one standalone unresolved marker into a register; run **without** `--advisory` | RED, rc=1 |
| 2 | Same injection **with** `--advisory` | rc=0 with `::warning::` — the control proving the flag does exactly one thing |
| 3 | `bash scripts/lint-legal-registers.sh --advisory --bogus` | RED, **rc=2** — `die2` never consults `ADVISORY` |
| 4 | **Guard's own dispatch:** remove one `pass` call so `checks` drops to 6 | RED, rc=1 via `MIN_CHECKS=7`, also never consulting `ADVISORY` |
| 5 | Add a **second** register file to `REGISTER_FILES` carrying a marker, after the first four are clean | RED — the predicate quantifies over the array, not the first entry |
| 6 | Add a determination-shaped file to `audits/` with **no** waiver and no index row | RED via predicate (c) — the exact hazard Phase 5.4 pre-empts |

**Harness rows.** (a) Delete the three `--advisory` assertions from
`scripts/lint-legal-registers.test.sh` and require the unit arm to fail — they are the only thing
pinning the rc=2 asymmetry once the flag leaves `test-all.sh`, so they must not be reaped as dead.
**This requires tightening the floor in the same edit:** that suite runs 36 assertions against
`MIN_ASSERTIONS=34` — two lines of slack. Deleting all three reds (33 < 34), but deleting **two**,
including the rc=2 asymmetry case the plan calls load-bearing, leaves 34 and passes. Pin it to 36.
(b) **Must-PASS, non-canonical:** a register whose only unresolved marker sits inside an
inline-code span. Recorded honestly: this case **already exists** in that suite, so it is a
standing regression test rather than new evidence this PR adds.

---

## Architecture Decision (ADR/C4)

**ADR: none required.** No ownership or tenancy boundary moves, no new substrate or integration
pattern, no trust-boundary change. Phase 0's lint change is deliberately heading-scoped and
changes no suppression *precedence*; the general precedence refactor is Phase 8.1, is ADR-132
class (*infra-sentinel: neutralize filenames, not tool anchors*), and the follow-up body says so.

**C4 views.** Enumerated against all three model files
(`{model.c4,views.c4,spec.c4}`), not a keyword grep:

| Category | Enumerated | Modelled? |
|---|---|---|
| External human actors | `founder` (reads the published corpus; runs the runbooks) | Yes — no new actor, no changed relationship |
| External systems / vendors | Better Stack (log recipient), GitHub (CI gate surface), Cloudflare Pages (publishes the Eleventy mirror) | All three `#external`, all in both views |
| Containers / data stores | `hetzner` (the host whose journald bound §(f) records); no store added or removed | Yes |
| Access relationships | two `hetzner -> betterstack` edges (Vector journald; `SOLEUR_PRIVATE_NIC` via curl), `inngest -> betterstack`, `betterstack -> founder` | Present — **one label and one element description incomplete; one relationship genuinely absent** |

Two corrections in Phase 7 (the Vector edge's label, named by content anchor because two edges
share the endpoints; and the `betterstack` element description, which reasons about PII scrubbing
and omits the highest-sensitivity stream on that source). `inngest -> betterstack` is **not**
falsified — its source is `[sources.inngest_journald]`, `include_units = ["inngest-server.service"]` —
but after Phase 7 the two edges describe the same vendor with divergent specificity, so it gains
one clause saying what it does *not* carry.

**Known gap, deferred to Phase 8.7 rather than asserted as complete:** there is no relationship
from any application container to `betterstack`, so the container view cannot show that
application-level logs leave the boundary. `c4-code-syntax.test.ts` and `c4-render.test.ts` remain
the gate; neither checks label completeness, which is why this enumeration is done by reading all
three model files rather than by grep.

---

## Domain Review

**Domains relevant:** Legal, Engineering, Product (sign-off only — no UI surface)

### Legal

**Status:** reviewed
**Assessment:** four corrections, all adopted. (1) The stale clause is in **six** files —
`privacy-policy.md` and its mirror were in no issue's scope. (2) The `TC_VERSION` rubric is **not
engaged** (T&C untouched); correct outcome is a **Tier 1** classification, an unconditional
refresh of three `LEGAL_DOC_SHAS` literals, and a CLO attestation — no bump, no re-consent.
(3) #6474 parts (3)(4)(5) are stale, while part (1) is *worse* than filed: the 2026-09-03
correction rested the Art. 30(1)(f) discharge on a mechanism that does not govern this container,
so the cell is not presently a valid discharge. (4) The register assigns the falsified "under
processor-DPA terms" ground to #7786's scope, so "do not caveat" holds for the *conclusion*, not
the *ground*. Also: the CLOSED trigger list makes the fifth trigger and the §(f) edit a same-PR
obligation, and the attestation is the `clo` agent's work, never an operator task.

### Engineering

**Status:** reviewed
**Assessment:** the originally-proposed structural fix does not work — the heading carve is
unreachable for a fenced host-login line, verified by execution. Relocation is ruled out (it
strands the reader at the `## Symptom` discriminator and breaks a numbered 6-step procedure).
Un-grandfathering is file-granular, so "do not edit the false positives" is unachievable as
stated. (c) cannot reach Terraform today (Robot dedicated, no root exists);
`hr-all-infrastructure-provisioning-servers` binds,
`hr-fresh-host-provisioning-reachable-from-terraform-apply` does not. #7787's one-token deletion
is safe (argv passthrough, `ADVISORY` read at exactly one site) and its trigger is discharged.
**The CTO's doc-only ruling was reversed on the narrower evidence** that a heading-scoped carve
fix has measured-zero blast radius and is the only shape in which the rule text, the runbook and
the linter agree; the general precedence refactor the CTO ruled against remains deferred.

### Product/UX Gate

**Tier:** none — no UI surface (no path matches the UI-surface glob superset; the Eleventy legal
mirrors are content, not components). CPO was invoked because
`brand_survival_threshold: single-user incident` requires plan-time sign-off.
**Decision:** reviewed
**Agents invoked:** clo, cto, cpo (plan-time); dhh-rails-reviewer, kieran-rails-reviewer,
code-simplicity-reviewer, architecture-strategist, spec-flow-analyzer, cto (devex lens), and a
scoped strong-model consult (plan-review panel)
**Skipped specialists:** cmo (no marketing, GTM or messaging surface — the replacement clause is
required to be register language, not copy); ux-design-lead (no UI surface)
**Pencil available:** N/A (no UI surface)

#### Findings

CPO **confirmed** the `single-user incident` threshold against the objection that this PR changes
no data flow: a published legal page is itself a user-facing artifact, the harm is per-reader by
construction, "aggregate pattern" is not distinguishable at N=1 beta user, and a botched
correction originates *new* risk. CPO **rejected the minimal framing** on the facts and
**required** the pseudonymisation claim be scoped to the Vector paths, correction brackets stay
out of the published pages, and the PR body state that #7529/#7825 remain open. CPO also
**overrode the CLO split** on #6474-vs-#7786. **Sign-off: approved**, conditional on those four
constraints — all written into Phases 3–4.

**Plan-review panel (7 reviewers + a scoped strong-model consult) changed the plan materially.**
Three reviewers independently found the same P0: `/ship` Phase 5.5's mandated counsel-review
artifact would red the gate Phase 6 promotes — now handled by Phases 4.6 and 5.4. Other adopted
findings: a **third** `30 MB` site in PA8 §(b)(vi); the §2.3(m) dual-enumeration collision that
would make three published pointers false; the DPA template carrying the same false mechanism; the
`AC15 of PR #4293` pointer live at four sites; the closure clause **already breached** by #7772's
two un-mirrored triggers; block-form ignore markers damaging markdown (→ inline same-line);
`REQUIRED` being a single unrelated string so a `FORBIDDEN`-only guard cannot tell correction from
deletion; and two false claims in an earlier draft — that the ship hook is a consumer of this diff
(its `last-resort` grep sits behind two early exits on added lines), and that `CORRECTION_NOTE`
matches the register's bracket form (it does not, and the probe never reads
`knowledge-base/legal/`). Both are retracted in place. The strong-model consult supplied the
heading-scoped lint fix that replaced the original heading-plus-region workaround; DHH's cut of
the PR-split section as a technical fork routed to a non-technical operator was applied in full,
along with a reduction from 38 acceptance criteria to 26 and the deletion of a `## Test Scenarios`
table that duplicated them.

---

## Acceptance Criteria

**Two conventions apply throughout.** (1) Every diff assertion uses
`git diff "$(git merge-base origin/main HEAD)"`, never two-dot `git diff origin/main` — the
moment `main` advances past the branch point, an unrelated upstream edit reads as this PR's.
(2) Every `vitest` invocation is prefixed `env -u GIT_DIR -u GIT_WORK_TREE`:
`apps/web-platform/vitest.config.ts` registers a `globalSetup` tripwire
(`assertNoInheritedGitLocation`, added by #7840) that aborts on an inherited git environment,
which is exactly the shape of an agent shell in a worktree.

### #7874 — the lint fix and the three-way split

- **AC1.** `python3 scripts/lint-infra-no-human-steps.py` over the three runbooks prints
  `OK: no human-run infra steps in 3 scanned file(s)` and exits 0. (Baseline on `main`: `FAIL: 10`.)
  The count is pinned, not just the `OK` — an empty or unresolved path list prints
  `OK … 0 scanned file(s)` and exits 0.
- **AC2.** The gate's own CI invocation, not a reconstruction of its inputs:
  `python3 scripts/lint-infra-no-human-steps.py --changed --base origin/main` exits 0, and its
  scanned count **equals** the number of changed `.md` files under the five `SCAN_DIRS` — the
  changed set *is* that set, so `≥` is weaker than the property.
- **AC3.** Whole-corpus non-regression: run the lint over every file in `SCAN_DIRS` on `main` and
  on `HEAD`, capture both **finding sets** to files, **normalise each entry to `file` + finding text
  (dropping the line number)**, and `diff` them. The difference must be exactly the 10 findings
  named in #7874 — nothing else appears or disappears. The whole-corpus baseline is **529
  findings** and Phase 1 shifts line numbers inside the edited files, so a raw `file:line:` diff is
  noisy by construction; record the expected delta as a committed fixture rather than prose. A count is not
  sufficient; Phase 0 changes suppression semantics corpus-wide. **The `HEAD` set is computed over
  a superset that includes this PR's three new files under `SCAN_DIRS`** (the plan,
  `tasks.md`, `decision-challenges.md`), so a finding in one of them reads as a finding, not as
  "something else appeared".
- **AC4.** `git diff "$(git merge-base origin/main HEAD)" -- <each of the three runbooks> | grep '^-[^-]'`
  returns **exactly five** lines: the two renamed subsection headings, plus the three prose lines
  carrying an inline class-(a) marker pair — each of which must reappear on the `+` side
  **byte-identical modulo the inserted marker**. Enumerated in the PR body.

  A same-line marker splices into the existing prose line, so a correct implementation renders it
  as one `-` plus one `+`; an earlier draft of this AC said "only the two renamed lines" and would
  have failed a correct implementation. (An editor reflow of a neighbouring line would also show
  here — re-wrap by hand rather than weakening the criterion.)
- **AC5.** **Two** runbooks — `admin-ip-drift.md` and `ssh-fail2ban-unban.md` — contain a heading
  matching `^#+[[:space:]]+Last-resort diagnosis\b` (ERE intervals such as `#{1,6}` are silently
  literal on BusyBox awk and older mawk, which would make an awk extraction empty and any
  "no host-login command here" check pass vacuously). `grok-build-hetzner-dogfood.md`
  deliberately has **no** such heading — it is provisioning debt, not a last-resort diagnosis —
  and the PR body records that its section-name contract stays knowingly unsatisfied pending the
  Phase-2 deferral issue.
- **AC6.** Every suppression this PR adds is bounded **per region**, so later growth shows up as a
  diff on an asserted number rather than as invisible absorption. **Per-region, not a total** — a
  total is not derivable (the `## Symptom` fence alone is 4 lines, so three same-line markers plus
  that fence is 7 inclusive or 4 exclusive, and neither is the "6" an earlier draft asserted).

  State the counting rule as the `awk` that computes it (inclusive span from each
  `lint-infra-ignore start` to its matching `end`), and assert **every** region's span is ≤ 6
  lines. Bound the two renamed **carve** sections the same way — the carve is the *larger*
  suppressor, since it hides every future addition to the section, and an earlier draft bounded
  only the regions. This is what stops one suppression from silently covering `## Diagnosis` and
  both Recovery sections.
- **AC6b.** After the edit, `grep -niE 'last.resort'` over each runbook returns only sites whose
  sense is disambiguated **in the line itself or the line immediately below it**. There are three
  senses in play — the SSH probe (the renamed sections), the noVNC recovery *channel*
  (`ssh-fail2ban-unban.md`'s header), and the third IP-echo curl service (`admin-ip-drift.md`
  `## Diagnosis` Step 1) — and a drafting pass that drops the disambiguation would leave the
  heading reading as an entry point. This is the criterion that keeps the heading honest; AC5
  pins only the regex.
- **AC7.** Every ignore marker added by this PR carries a rationale naming its disposition class
  and owning issue — **on the start marker or the following line, either shape accepted**. The
  class-(a) markers cite **#6806** with the same-PR removal instruction; the class-(c) region
  cites the Phase-2 deferral issue. Assert `count(added 'lint-infra-ignore start') == count(those
  carrying a rationale)`, on the rationale sentence rather than a bare `#6806` token, which also
  matches a cross-reference.
- **AC8.** `bash scripts/lint-infra-no-human-steps.test.sh` passes; its case-count floor exists
  and exceeds the pre-PR case count; and Guard 1's mutation rows 1–6 plus both harness rows each
  behave as tabulated, run and recorded in the PR body. Row 4 (zero-dispatch) is the anti-vacuity
  row and must be run.
- **AC9.** #6806 carries a comment naming the three class-(a) markers by file and content anchor
  and recording the same-PR coupling (`gh issue view 6806 --json comments`). This is the removal
  trigger; the runbook comment is only the local explanation. The Phase-2 deferral issue exists
  and is OPEN (`gh issue view <N> --json state`), and its body carries the re-triage note for the
  grok region — any command added inside it later must be re-triaged, not silently absorbed.

### #7786 + #6474 — the corpus and the register

- **AC10.** `bash scripts/probe-legal-corpus-truth.sh` prints `CORPUS-OK` **with a non-zero
  examined count**, exits 0 — *and*, in the same run, a scratch copy of the tree with
  `no off-host copies` reintroduced into the mirror exits 1 with `CORPUS-FALSE:
  mirror/privacy-policy.md`. The positive run is not evidence without the negative control.
- **AC11.** Semantic sweep, not literal: across `docs/legal/`,
  `plugins/soleur/docs/pages/legal/` and `knowledge-base/legal/`,
  `grep -rniE 'no off-host|off-host copies|no external log|no log shipping|never leave the host|on-host only'`
  returns hits **only** where the retired wording is *quoted* rather than *asserted* — a dated
  correction bracket in a register, or the Phase 4.5 attestation, which must quote what was wrong
  to be an attestation. Each surviving hit is listed in the PR body with its classification.
  Baseline today is 6 hits, all assertions on the two published surfaces.
- **AC12.** `grep -rn '30 MB'` over **the same three trees as AC11 plus
  `knowledge-base/engineering/operations/runbooks/`** returns hits only where the figure is
  quoted inside a dated retraction. Scoping this to `article-30-register.md` alone would miss
  `recover-userid-from-pino-stdout.md`'s two descriptions (Phase 4.3),
  `betterstack-log-query.md` (Phase 3.10) and the DPA template (Phase 3.5d) — both plan-internal step numbers. In particular the
  register no longer asserts the mechanism at **any of its three sites** — asserted on three
  content anchors (§(f)'s opening `pino stdout:` clause, §(f)'s
  `The **mechanism is the record**` sentence, and **§(b) limb (vi)**), not on an occurrence count.
- **AC13.** Every factual claim the diff **adds** traces to a named source. The PR body maps
  `--log-driver journald`, `SystemMaxUse=1G`, `SystemKeepFree=2G`, `level >= 40`,
  `CONTAINER_NAME = ["soleur-web-platform"]`, the 90-day Better Stack retention, 2026-06-02/#4786
  and 2026-05-21/#4279 each to a file + content anchor. An AC set built only from absence
  assertions can pass in full while the replacement claim is false.
- **AC14.** PA8 §(f) cites `journald-config.test.sh`'s `assert "SystemMaxUse=1G"` and the
  `infra-validation.yml` step name, and `bash apps/web-platform/infra/journald-config.test.sh`
  passes — the cited evidence holds. **No `cloud-init.yml:<line>` citation survives outside a
  dated bracket.** A bare `grep -c 'cloud-init.yml:[0-9]' … → 0` would contradict Phase 4.1's own
  convention, which requires the retraction to *quote* the withdrawn anchor: "an overwrite with no
  dated marker is invisible to a reader diffing this register against a prior export."
- **AC15.** **List parity, not one trigger.** The runbook's `### Re-verification triggers`
  numbered list and PA8 §(f)'s `**Re-verification triggers:**` clause enumerate the *same set*:
  the four originals, the fifth (`journald-soleur.conf`), and the two #7772 per-source triggers
  that §(f) already carries and the runbook never received. Give both sites a stable token (`RVT-1`…`RVT-7`) and assert
  `comm -3` over the extracted token sets is empty — without an extraction rule, comparing a
  numbered markdown list against an inline `**Re-verification triggers:**` clause degrades to a
  human read. Not `git log -- A B`, a union filter that cannot see an asymmetric commit; and not a
  check for the fifth trigger alone, which passes over the pre-existing breach.
- **AC16.** `sha256sum docs/legal/{data-protection-disclosure,gdpr-policy,privacy-policy}.md`
  matches the three refreshed literals in `apps/web-platform/lib/legal/legal-doc-shas.ts`, and
  `bash apps/web-platform/scripts/check-tc-document-sha.sh` exits 0. That script is deliberately
  **not** registered in `test-all.sh`, so it must be run explicitly.
- **AC17.** `TC_VERSION` in `apps/web-platform/lib/legal/tc-version.ts` is unchanged from
  `origin/main`, and `git diff origin/main -- docs/legal/terms-and-conditions.md` is empty.
- **AC18.** `knowledge-base/legal/compliance-posture.md` `## Active Compliance Items` carries the
  trigger-that-did-not-operate row, matching the row schema committed as an HTML comment in that
  section, naming the Art. 5(2) framing, and anchored on the runbook's trigger numbering rather
  than restating the trigger text.
- **AC18b.** Every published cross-reference the edit touches still resolves to a clause that says
  what the pointer claims. Enumerated in the PR body, each verified by reading the target: the
  outer `(A)`/`(B)` renumbering swept through `privacy-policy.md` §5.14, the register's Better
  Stack vendor row and `gdpr-policy.md` §3.7 (+ all three mirrors); `AC15 of PR #4293` → **#7529**
  at all four sites; `gdpr-policy.md` §3.7's `DPD §4.2` pointer resolves to a table that now names
  Better Stack; PA8 §(b)(vi)'s "in §(f)" pointer no longer promises a figure §(f) has retracted.
  This is the class the absence-greps in AC11/AC12 structurally cannot catch.

### #7787 — the promotion

- **AC19.** Assert the **property**, not a line total — a rewritten comment block renders as N
  removals plus M additions with byte-identical lines kept as context, so no arithmetic on the
  count is stable:

  ```bash
  git diff "$(git merge-base origin/main HEAD)" -- scripts/test-all.sh \
    | grep -E '^[+-][^+-]' | grep -vE '^[+-][[:space:]]*#' | wc -l   # == 3
  ```

  and the three non-comment changed lines are exactly: the old and new
  `lint-legal-registers-live` lines, and the added `probe-legal-corpus-truth-live` line.
  Enumerated in the PR body.
- **AC20.** `grep -cE 'run_suite .*(--advisory|--warn|--soft|\|\| true)' scripts/test-all.sh`
  returns **0**, and `grep -n 'PROMOTION: delete the --advisory flag' scripts/test-all.sh` returns
  nothing.
- **AC21.** `bash scripts/lint-legal-registers.sh` exits 0 and its summary line matches
  `7 assertion(s), 0 failed` with `waiver-parity=ok`, `waived` incremented by the number of
  waivers added, and `produced` incremented by **the number of new `audits/` files that match
  `DETERMINATION_PATTERN`** — derived by running that pattern over the new files, not by counting
  them. (Baseline `produced=14 waived=10`. A counsel-review file that does not quote Art. 4(12) or
  Art. 33 leaves `produced` at 14 while `waived` moves, and an AC that assumed both increment
  together would red a correct tree.) Run over
  the tree as this PR leaves it — **after the Phase 4.5 attestation and any `/ship` Phase 5.5
  counsel-review file are committed** (predicate (b) requires cited paths be git-*tracked*, so an
  unstaged file reds rather than warns), and **before PR-ready**. This is the criterion that stops
  the promotion reddening its own PR.
- **AC22.** Guard 3 mutation rows 1–6 behave as tabulated, run and recorded verbatim in the PR
  body. Rows 2 and 3 together are the asymmetry proof; without them it is asserted, not measured.
  Row 6 (an unwaived determination-shaped `audits/` file) is the one that reproduces this PR's own
  hazard.
- **AC23.** `bash scripts/lint-legal-registers.test.sh` passes and
  `grep -c -- '--advisory' scripts/lint-legal-registers.test.sh` is unchanged from `origin/main`
  (it returns **9** — nine occurrences across the three assertions; the prose count and the grep
  count differ, so a reader running it does not conclude the file was edited).

### Cross-cutting

- **AC24.** `bash scripts/test-all.sh` is green (this covers the mirror-drift ratchet, the
  scope-block gate, `legal-doc-consistency`, the C4 suites, and the newly-wired corpus-truth
  probe; the web-platform vitest suites run under the `webplat` group).
- **AC25.** The PR body carries the (a)/(b)/(c) three-way split as a table, each row naming its
  finding lines, its disposition, its owning issue, and — for (b) — the two sub-classes
  (transcript vs. probe), so a future reader cannot mistake (b) for (c). It also states that
  #7851 keeps two of its three statements, and that #7529/#7825 remain open. **And it states,
  per rename, why a terminal VERIFICATION step legitimately carries a "diagnosis" heading** —
  naming the enumerated no-SSH steps that precede it. Phase 2 applies the gaming-the-gate test to
  reject exactly this move for the grok runbook; without the justification on the record, a
  future author could cite these two renames as precedent for renaming an operative section into
  the carve.
- **AC26.** Every `knowledge-base/` path cited in the plan and PR body resolves:
  `grep -oE 'knowledge-base/[A-Za-z0-9/_.-]+\.md' <file> | sort -u | xargs -I{} bash -c '[[ -f "{}" ]] || echo "BROKEN: {}"'`
  prints nothing.

### Post-merge (operator)

None. Every verification runs locally or in CI. The CLO attestation is auto-routed via the `clo`
agent, not an operator task (`hr-no-dashboard-eyeball-pull-data-yourself`;
`knowledge-base/project/learnings/workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`).

---

## Dependencies & Risks

| Risk | Mitigation |
|---|---|
| **Phase 5.5's mandated counsel-review file trips the newly-promoted gate** | Phases 4.6 + 5.4 pre-author both waivers + `§Excluded records` parity rows; AC21 re-runs the lint after those files are **committed** (predicate (b) needs them git-tracked) and before PR-ready |
| An unrelated `main`-side change reds the promoted gate after the local measurement | Phase 6 is its own terminal commit and the PR body names it as the revert unit — a one-commit revert, not a corpus rollback |
| Block-form ignore markers damage the runbook's markdown (paragraph split, list terminated) | Class (a) uses inline same-line markers; AC4's deletion-grep cannot see this class, so AC6 bounds the suppressed line count instead |
| The published corpus gains a newly-false cross-reference | AC18b enumerates and verifies every pointer the edit touches — the class AC11/AC12's absence-greps structurally cannot catch |
| Phase 0 changes suppression semantics corpus-wide | Heading-scoped; blast radius measured at zero (no such heading exists). AC3 diffs whole-corpus finding *sets*, so any unintended change surfaces |
| Touching `admin-ip-drift.md` un-grandfathers three findings this PR is told not to fix | Class (a) inline markers, explicitly labelled and #6806-owned; prose untouched; the coupling is written into #6806 by Phase 1.4 |
| The class-(a) region rots after #6806 lands | AC8's comment on #6806 is the trigger. A note in the suppressed file is not one — `harvest-debt` cannot see `*.md` (Phase 8.5) |
| A suppression region reads as concealment | Every region opens with a rationale naming class and owner; class (c) names a deferral issue, not "wontfix"; the sanctioned diagnostics use the heading, not a region |
| The corrected corpus makes a live Art. 28(3) gap visible | Intended. #7529/#7825 stay OPEN with a 2026-11-13 re-evaluation; the PR body says so |
| A blanket pseudonymisation claim would be false for the `soleur-registry` shipper | Phase 3.3 scopes the claim to the Vector paths |
| `MIN_CHECKS=7` zero headroom | Recorded; `fail()` also increments `checks`, so a finding does not trip it — the risk is a future code edit. Phase 6.4 adds the remedy to the failure message |
| Predicate (c)'s waiver treadmill (7 of 10 waivers, precision 4/14) | Recorded; authors already commit waivers in-PR. Narrowing is a CLO scoping ruling → Phase 8.3 |

---

## References & Research

### Research Insights

**Premise validation.** All four issues verified OPEN via `gh issue view --json state`. Three of
four had stale premises, corrected in `## Research Reconciliation`. Cited artifacts verified on
disk or via `gh`: PR #7872 (`05e50c525`), PR #7782 (`5d8a12736`), PR #4786 (`223364c14`), PR #4800
(`faf9ea95e`), PR #4279 (`f08ac4c46`), issue #3754 (CLOSED 2026-09-04), issues #6806, #7529, #7825
(OPEN).

**Capability claims verified before assertion** (`hr-verify-repo-capability-claim-before-assert`):
the carve behaviour was measured by executing the lint against fixtures in four configurations,
not inferred from the regex; the `--advisory` asymmetry was read from the single `ADVISORY` call
site and confirmed by running `--advisory --bogus` to rc=2; the absence of a Terraform root for
GEX was established with `git ls-files '*.tf'`; the ship hook's non-engagement was established by
reading its two early exits, which **retracted a false claim in an earlier draft of this plan**.

**Key source anchors.** `scripts/lint-infra-no-human-steps.py` (`_is_carve_heading`; `scan_text`'s
five-step loop; the #7286 in-fence `HOST_LOGIN_RE` exception; `SCAN_DIRS`);
`.claude/hooks/ship-runbook-ssh-gate.sh` (the `added`/`hits` early exits);
`scripts/lint-legal-registers.sh` (`REGISTER_FILES`; the inline-code strip applied before
predicate (a); `MIN_CHECKS=7`; `NOT_TRANSCRIBED`; 11 `die2` sites); `scripts/test-all.sh` (`run_suite` argv
passthrough; `suite_exit_class`; the `#7387` unit+live convention; 194 call sites, one advisory);
`scripts/probe_legal_corpus_truth.py` (`SURFACES × DOCS`, `FORBIDDEN`, `REQUIRED`,
`CORRECTION_NOTE`); `plugins/soleur/skills/ship/SKILL.md` §"Counsel-Review CLO-Attestation Gate";
`apps/web-platform/infra/{journald-soleur.conf,journald-config.test.sh,vector.toml,cloud-init.yml,server.tf}`;
`knowledge-base/legal/tc-version-bump-policy.md` §"Non-T&C legal docs";
`apps/web-platform/scripts/check-tc-document-sha.sh` (`BODY_EQUIVALENCE_DOCS`).

**Applicable institutional learnings.**
`2026-09-06-a-live-positive-validated-the-filter-on-one-row.md` (a live positive validates one
row — applied in AC10's paired control and every Guard's dispatch row);
`2026-03-02-legal-doc-bulk-consistency-fix-pattern.md` (two locations, scope both before editing
either — applied in Phase 3's six-file table);
`2026-05-18-plan-citation-and-ac-grep-brittleness-on-legal-doc-prs.md` (AC greps must inspect the
target's convention first — applied in AC12/AC15);
`2026-05-16-brainstorm-verify-register-citations-and-adjacent-silent-failures.md` (stale-narrative
comments are canaries — the rotted `cloud-init.yml:303-310` anchor and the stale PROMOTION
comment);
`best-practices/2026-07-23-draining-one-severity-tier-unmasks-co-located-lower-tier-hits.md`
(assert on the token diff, never a total — AC3 diffs finding sets);
`workflow-patterns/2026-05-18-clo-attestation-auto-route-instead-of-human-task.md`;
`2026-07-16-a-gate-that-proves-it-cannot-fail-open-shipped-its-own-proof-unwired.md` (the reason
Phase 5.3 wires the probe rather than leaving the list decorative).

**CI evidence for #7787.** 14/14 green `test-scripts` runs on `main` from `33855997136`
(2026-09-04 08:58 UTC) through `34058032717` (2026-09-06 20:27 UTC); zero
`::warning::lint-legal-registers` in any; `rows` pinned at 5 while `produced` grew 10→14 and
`waived` 6→10, with every new determination file waived **in the same PR** that added it — authors
already behave as though the gate blocks.

### Issues and PRs

Closes #7786, #6474, #7874, #7787. References #6806, #7529, #7825, #7717, #7823, #7872, #7782, #7772, #7803, #7838, #7440, #7625, #4786, #4800, #4792, #4773, #4279, #4293, #3754, #6546, #7286, #6016. ADRs: ADR-084 (decision classes), ADR-132 (infra-sentinel suppression), ADR-176, ADR-192, ADR-193, ADR-200.

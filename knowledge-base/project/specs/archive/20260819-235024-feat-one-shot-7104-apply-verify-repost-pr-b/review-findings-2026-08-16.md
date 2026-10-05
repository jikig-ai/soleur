# Review findings — 2026-08-16 panel, against SHA `2fdd9e285`

Six report-only agents: `user-impact-reviewer` (mandated by the `single-user incident`
threshold), `observability-coverage-reviewer`, `test-design-reviewer`, `security-sentinel`,
`silent-failure-hunter`, `architecture-strategist`.

**Disposition: DO NOT SHIP.** Two P0s, and three fixes shipped by the 2026-08-16 review-fix pass
are defeated by executed mutations. Nothing below is speculative — every CRITICAL was either run
by the agent against a sandbox copy or re-verified by hand against the code.

---

## The two P0s

### P0-A — pass 2 lost the absolute freshness pin (false green on the terminal verdict)

`apps/web-platform/infra/infra-config-verify.sh:220-246`.

On `origin/main` the arm was unconditionally `FRAME_START_TS -lt APPLY_START_EPOCH`. PR-B inserted
the `VERIFY_PASS == 2` branch **in front of it**, so pass 2's only surviving assertion is RELATIVE:
`FRAME_START_TS -gt REPUSH_BASELINE_TS`. `APPLY_START_EPOCH` is validated three lines above and
then never read on this path.

With `APPLY_START_EPOCH=2000`, pass 1 observing `1000`, pass 2 observing `1500`: prints
`Re-push VERIFIED: frame advanced 1000 -> 1500`, sets `freshness_evidence=verified`, falls through
to `verdict=verified` — while the frame **still predates this workflow's own apply**. Any unrelated
frame advance satisfies it: a queued handler invocation, a concurrent trigger, a lagging host clock.

That is the #7220 shape this PR exists to close, reintroduced in the terminal verdict.

Nuance from `test-design` (F9), which must not be lost in the fix: the host-clock-to-host-clock
comparison on pass 2 is **deliberate** so runner/host skew cancels, so a re-pushed frame may
legitimately predate `APPLY_START_EPOCH`. The correct fix is therefore not a naive AND — it needs
the skew allowance the runner-clock comparison already carries, and a **distinct** `::error::`
("the frame moved but still predates this apply" is a different diagnosis, with a different lever,
from "the frame did not move"). What is currently unasserted either way is that the advance is
bounded: a +1 s bump reads as VERIFIED.

### P0-B — a re-push that bricks the channel is reported as "the infra-config gate never ran"

Converged on independently by `user-impact` (F1), `observability` (P0), and `architecture` (S3);
verified by hand.

`Verify webhook is alive post-re-push` (`apply-deploy-pipeline-fix.yml:921`) has **no `id:`** and a
bare-expression `if:`, so it and pass 2 (`:946`) both receive the implicit `success() &&`. When the
liveness probe fails — i.e. the re-push destroyed the sole no-SSH remediation channel — pass 2 is
**`skipped`**, not `failure`:

- recovered arm (`:1414`) needs `PASS2_VERDICT == 'verified'` → no
- re-push-failure arm (`:1439`) tests only for `'failure'`, sees `'skipped'` → no
- gate-never-ran arm (`:1461`) tests `GATE_OUTCOME != 'failure'`; pass 1 soft-failed `exit 0`, so
  `GATE_OUTCOME == 'success'` → **fires**

The operator receives *"Server config update failed before it could be checked — the site is up"*,
body *"nothing needs re-provisioning … re-run"*, detail *"The infra-config gate never ran
(outcome=**success**)"*. Every clause false; `infra-config-verify.sh:351` says a plain re-run
cannot fix it. The backstop (`:1045`) and the `**Self-healed:**` summary line (`:1983`) corroborate
the false story on the same run.

The workflow's own comments at `:1405`/`:1427` diagnose exactly this and patch two arms **by
ordering**. The general fix is the guard, not the ordering.

**Fix:** `id:` on the probe; a fourth arm routing its failure to the `unreachable` mode with the
`-replace=terraform_data.infra_config_handler_bootstrap` lever; change the gate-never-ran predicate
to `GATE_OUTCOME == 'skipped' || -z GATE_OUTCOME`; gate the Self-healed line on pass 2 verifying;
branch the backstop on the re-push outcomes. No battery row covers alert-step dispatch.

---

## Three fixes from the 2026-08-16 pass that are DEFEATED (all executed by the agent)

### D1 — the loop-depth scanner is bypassable; #6594 restored at `132 passed, 0 failed`

`infra-config-gate.test.sh:368-417`. The scanner strips comments and quoted spans but **not
`[[ ]]` test spans** — unlike its own sibling sweeper at `:627`, which does — and its tokenizer
matches bare `do`/`done` anywhere. Two balanced phantom lines zero the depth at the assert and
rebalance the file:

```
  for _n in 1; do :; done            # restores done_count == 1
  [[ $PHASE == done ]] || :          # depth 1 -> 0
  adjudicate_infra_config … && break
  [[ $PHASE == do ]] || :            # rebalance
```

Applied with the real terminal adjudication deleted, so the only content assert is an any-of-3 poll
inside the retry loop: **gate 132/0 rc=0, verify 29/0 rc=0**, printing the reassuring
`maxdepth=2 ADJ=0 CI=1 — terminal-ness is structural, so G2-1 and G2-5 cannot cancel`. The
positive control does not protect (maxdepth reads 2, *higher* than baseline); the balance check
does not protect (the phantoms are balanced by construction).

**Fix:** strip `[[ … ]]` before tokenizing (reuse `:627`); require `do`/`done` in command or
terminator position, not bare-word position; add the composite as a row.

### D2 — the tally's "two independent producers" are one function

`infra-config-gate.test.sh:53`. Both producers live in the same one-line `pass()`, so one edit
moves both:

```bash
pass() { echo "  PASS: $1"; printf 'PASS\nPASS\n' >> "$PASSLOG"; pass=$((pass + 2)); }
```

Measured **264 passed, 0 failed, OK, rc=0** — reconciliation clean, source-literal check clean,
floor of 132 cleared with **66 real assertions deletable**. Composite: same mutation plus deleting
Guard 1's entire unit block (`:1537-1742`) → **234 passed, OK, rc=0**.

The test for independence is: *can one edit move both?* A real second producer must be structurally
independent — e.g. count `^  PASS: ` lines from the emitted stdout at teardown.

### D3 — the allow-list sweep has four escape classes; `awk` and `sed` are trampolines *inside* the allow list

`infra-config-gate.test.sh:586-680`, run verbatim against crafted inputs:

```
abs-path            EVADED   /usr/bin/terraform apply -auto-approve
rel-path-dot        EVADED   ./push-infra-config.sh
var-indirect        EVADED   TF=terraform ; $TF apply -auto-approve
awk-system          EVADED   awk 'BEGIN{system("terraform apply -auto-approve")}'
awk-pipe-sh         EVADED   awk 'BEGIN{print "terraform apply" | "sh"}'
sed-e-flag          EVADED   sed -e "s/x/terraform apply/e" …
sed-inplace-write   EVADED   sed -i "s/old/new/" ../../../.github/workflows/apply-deploy-pipeline-fix.yml
redirect-write      EVADED   echo pwned > /etc/default/soleur-doppler-token
control-1           HIT      terraform apply -auto-approve   (the shape all 12 controls use)
```

Root causes: (1) `awk` has `system()` and `| "sh"`, GNU `sed` has the `e` flag and `-i` — and
`strip_noise` blanks quoted spans, so the awk program body is invisible by construction; (2) the
token regex requires a leading `[A-Za-z_]`, so `/usr/bin/terraform` and `./x.sh` capture *no token
at all*; (3) `$VAR` in command position captures nothing; (4) shell redirection is a write.

The comment shipped says `eval`/`source`/`.`/`command` are "DELIBERATELY ABSENT: each is an
arbitrary-command trampoline" — and admits two larger ones on the next line. All 12 positive
controls use one shape (bare binary in command position), which is exactly why they miss all four
classes.

---

## Remaining, by owner

### Ledger integrity (`silent-failure` #2/#3, `observability` P1)
- **Destructive:** `:1204-1209` — under `set +e`, a failed `gh issue view` yields `prev=''` and
  `gh issue edit --body-file` **overwrites the entire ledger**, then prints "appended" and exits 0.
  #7576 is explicitly blocked on this artifact's readings.
- **Vacuous gate, introduced this pass:** `steps.ledger_body.outcome == 'success'` (`:1166`) can
  never be false, because `ledger_body` now runs `set +e` + terminal `exit 0` — including the
  mktemp arm that exits 0 with no `path` output. Gate on `outputs.path != ''`.
- Unguarded `mktemp` at `:1205`; `gh issue edit` has no rc check; a failed `gh issue close` leaves
  the ledger OPEN, breaking the "created closed so it never notifies" invariant.

### Alert honesty
- The `recovered` body (`red-alert.sh:124`) asserts three unmeasured things: "the first attempt
  landed the files" (INVERTED — the race is *no files written*; the predicate only establishes the
  frame describes a PREVIOUS apply), "The website stayed up throughout" (the only probe is the
  webhook endpoint, and the container swap is still AHEAD in the same job), "no customer data is
  affected".
- "Exactly one production write was made, to `terraform_data.deploy_pipeline_fix`" understates: the
  resource's `local-exec` re-delivers the full ~24-file FILE_MAP and reconciles systemd units.
- The re-push-FAILURE class reuses the `reachable` body ("the files themselves reached the server"
  — false on the plan-failure path), mitigated only by a clause asking a non-technical founder to
  "Ignore any suggestion that app health is unaffected". Needs a fifth `repush_failed` mode.
- **Label namespace:** plan `:405` states the name is **not** `ci/infra-config-recovered`, and the
  plan reserves `ci/*` for red alarms. That is exactly the name shipped.
- No `action-required` label → invisible to `operator-digest`, which queries by it.
- "Close it whenever you like" converts a rolling issue into a per-event one.

### `unadjudicated` re-arms the success()-gated steps
The backstop exits 0, so `:1551` swaps the container, `:1917` posts *"infra-config files landed
(files_written == files_total, files_failed == 0)"* onto the founder's #4804 — a **fabricated
measurement**, since the gate's own annotation says nothing was adjudicated — and `:1938` closes
drift issues as "re-aligned with HEAD". Gate those three on the verdict. `freshness_evidence=none`
is also the weakest green the design allows and the only level with no out-of-band report.
`verdict=unadjudicated` has **zero test coverage**.

### Security (0 critical / 0 high)
Cleared: no exfiltration path, blast radius bounded and two-producer, credential separation real
(`repush_apply` carries no `env:` at all), one `${{ }}` in a `run:` and it is `job.status`, `detail`
never reaches a shell, source sanitiser is a byte-wise allow-list.
- **Reclaim asymmetry:** `tfplan.json` survives five `exit 1` paths (one `rm` at `:398`, five exits
  between) while the step's comment claims the window is closed; the binary `tfplan` is **never**
  reclaimed; `tfplan.txt` is neither reclaimed nor gitignored. The new reclaim step covers only the
  files this pass authored.
- **The address-set assert has no producer-side pin** — deleting `:866-882` leaves every guard
  green, and there is no row. Same for `GRADED -ne 1`, the re-push destroy-guard, and the trap.
- The actuation sweep over `infra-config-verify.sh` is still the deny-list this PR *measured* as
  11-of-12 evadable — on the higher-privilege file (runs twice in prod, holds `DOPPLER_TOKEN`, its
  `repush_needed=true` is the sole authoriser).

### Architecture
- **S1 — phantom precedent.** ADR-189 says "ADR-072 bans a verification surface from actuating."
  ADR-072 contains no such principle (verified: zero hits for actuate/verification-surface); its
  Option-2 rejection turns on a flock collision, and ADR-186 frames it as *signal availability*.
  No `AP-NNN` covers it. Restate as **established here** and register as `AP-023`, citing the T5
  sweep + Guard 2(7) — the invariant genuinely exists and is well enforced; the citation is false.
- **S2** — the split separates the write, blast radius, credentials and verdict, but **not the
  authorization**: the verification surface is the sole authorizer. Honest formulation: *"the
  verification surface authorizes but does not perform the write, and what it authorizes is
  independently shape-graded and independently credentialed."*
- **S6 — the sunset is a wish.** No `SOLEUR-DEBT:` marker, no followthrough script, no ledger row;
  and #7576 is gated on an event measured at n=1 in ~13 months — the same unfireability argument
  the ADR uses to *reject* the escalation trigger three lines earlier.
- **S7** — the re-push drops the doppler wrapper apply #1 explicitly RETAINED as an unvalidated
  behaviour change, and run `31714143720` (cited as proof) executed the **wrapped** form.
- **S4** — "R17.4's residual is closed" is overstated: the probe is gated on apply *success*.
- **S8** — the backstop narrates "skipped or MIS-KEYED" on three non-mis-key paths.

### Battery / suite quality (score 6.9/10, grade C)
- **F3** — the omission list is neither honest nor complete. Unrowed: Guard 3 / CARDINALITY PIN
  (the m18 fix itself), Guard 1's *consumer* side (D2 mutates the producer only), Guard 2 (5b),
  AC18, the G2-1+G2-5 composite, all of `red-alert.sh`, and registration. "Demotion — not
  applicable" is contradicted by this PR's own record: a demotion was its top survivor.
- **F5** — S1–S4 are four rows on one axis with one detector; S1 and S3 share a marker, the exact
  anti-pattern the gate suite calls out. Discriminating variants measured: `deploy.attacker.test`
  isolates I6d; swapping to `CF_ACCESS_CLIENT_SECRET` isolates I6c.
- **F6** — the STAY-GREEN control appends a comment to a file whose comments every scanner strips;
  it duplicates the mandatory baseline and cannot detect what it names.
- **F7** — neither sibling suite got the tally protection, and neither has rows.
- **F8** — `GATE_MIN_ASSERTIONS` is a **floor** (`-lt`), not the flush pin the commit message
  claims. `G1_EXPECTED_REFERENCES=12` includes **2 pre-existing references unrelated to the gate
  chain**, so any PR touching this 1985-line shared workflow reds a registered gate — scope the
  extractor to the gate chain instead.
- **F9** — `STUB_HTTP_CODE` is 200 at all three drive sites, so the 404/000/502/503 branches are
  never driven; pass 2 with `DPF_REPLACED=false` never driven; `REPUSH_BASELINE_TS` unset never
  driven.

### Recurring anti-patterns named by the panel
1. *The control samples one shape* — the 12-input allow-list battery, the 12 Guard-1 references,
   and the four stub rows each vary a parameter within one shape rather than crossing shapes.
2. *"Two independent producers" that share a code path* — if one edit moves both, it is one.
3. *Hand-rolled shell parsing* — three mini-parsers now ship with **different** noise-stripping
   policies (one strips `[[ ]]`, one does not). D1 is the cost. Consolidate into one `strip_noise`.

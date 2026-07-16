# Decision Challenges — feat-one-shot-6497-login-gate-unclassified

Recorded headless per plan Step 4.5 / ADR-084 (`decision-principles.md`). The operator's stated
direction is the default; these are surfaced, not silently applied. `/ship` renders these into
the PR body and files them as `action-required`.

---

## UC-1 — "Open a successor issue for *zot serves zero pulls; zot-primary is not achieved end-to-end*"

**Class:** User-Challenge (challenges the operator's stated direction).

**What you asked for:** open a successor issue capturing that the round trip is dead — CI pushes
to zot but web hosts never pull from it — and reference it from this PR, so a green push-soak is
not left standing as proof of an end-to-end claim it never tested.

**Why I think the direction should change:** the issue you want opened **already exists twice**.

- **#6497** (OPEN, P1 — the issue this PR re-scopes) states in its own body, verbatim: *"zot has
  served **zero pulls in 90 days**"* and *"This is not a regression. zot has never worked."* It
  also owns the exact decomposition: three conditions must hold for zot to serve a pull —
  (1) login works ← **#6497**; (2) zot holds the tag ← #6416; (3) the host reaches zot on the
  private net ← #6415/ADR-115.
- **#6122** (OPEN) is the zot migration umbrella and owns end-to-end. Phase 5.3-5.5 (PAT revoke /
  GHCR retirement) remains gated on exactly the pull-side evidence you are describing.

A successor issue would restate #6497's own thesis in a third place while #6497 is open, P1, and
actively being worked in this very PR.

**What I did instead (your intent, non-duplicative):** the genuine defect your instruction
identified is real and I have not dropped it — **#6416's title over-claimed**. It reads
*"ADR-096 zot-primary dead end-to-end"*, but its gate
(`scripts/followthroughs/zot-mirror-connector-6416.sh`) anchors every check on `127.0.0.1:5000`
from inside the GitHub runner and measures **only** whether `crane` copied the image *into* zot.
It never observes a pull, never checks `ZOT_ACTIVE=1`, never confirms zot answered a single
`GET`. Closing it 5/5 retired an end-to-end claim on push-side evidence alone — precisely your
objection. Plan Phase 6.2 posts a comment on #6416 recording that its closure is legitimate for
its **true** scope (condition 2 of 3: zot holds the tag) while its **title** over-claimed, and
points at #6497 + #6122 as the surviving end-to-end trackers. The record is corrected; no
duplicate is created. I did **not** reopen #6416 — its soak genuinely passed what it measured.

**Cost if I'm wrong:** near zero, and reversible — if you want the successor issue anyway, it is
one `gh issue create`. Say the word and I'll file it.

---

## UC-2 — "#6497's ORIGINAL cause is FIXED AND CONVERGED; only its residue remains"

**Class:** User-Challenge (factual reframing of the premise the PR body is meant to carry).

**Your framing:** the htpasswd Terraform edge shipped and provably works; #6497's original cause
is fixed and converged; only residue remains. The PR body must not imply the htpasswd edge is
still broken.

**Where I agree, fully:** the edge works. `htpasswd_pull_matches=true htpasswd_push_matches=true`,
the `registry-host-replace` dispatch (run 29482827061) succeeded at 08:15Z, zot is healthy. The
PR body will not imply otherwise, and this plan does not touch `cloud-init-registry.yml`,
`zot-disk-heartbeat.sh`, or ADR-115.

**Where the wording matters:** the original cause was not *fixed* — it was **falsified**. Those
are different, and the difference is load-bearing for the PR body.

#6497's root cause was **derived** from a discriminator argument: *"crane/cosign push
authenticates against the same `/etc/zot/htpasswd` in the same window that `zot-pull` is
rejected. One entry current, one stale — the shape only a per-entry divergence produces."* The
08:15Z re-bake **was the experiment that argument implied**: re-bake htpasswd → login recovers.
htpasswd now matches on both entries and `login_failed` **continues on every deploy since
08:27Z**. The hypothesis is refuted, not resolved. The discriminator claimed a uniqueness it did
not have — "push works, pull login fails" is *also* the signature of a **local** docker-login
failure hitting both registries, which it never enumerated.

**Why this is worth your attention rather than a wording nit:** "fixed and converged" invites the
next engineer to conclude WEB-PLATFORM-5B is solved and the remainder is noise. It is not: the
issue's own **AC11 is red** (`zero new WEB-PLATFORM-5B events` — we have 6+ since 08:27Z), and
the issue body explicitly predicted this, warning that AC10 (`htpasswd_pull_matches=true`) *"is
**not** sufficient … proves only that the probe is wired."* The issue predicted its own
non-closure and was right.

Two shipped comments now assert the falsified causation — `zot-registry.tf:108-109` (*"which is
exactly what #6497 / Sentry WEB-PLATFORM-5B was"*) and `:332` (*"the WEB-PLATFORM-5B defect"*) —
in the same file whose false comment started this thread, which the 2026-07-15 learning calls the
**fifth consecutive instance** of this class. Plan Phase 5 narrows both to what is true: the edge
closes a real rotation-convergence gap; the claim that this gap **caused** WEB-PLATFORM-5B was
refuted. The edge keeps its full credit; only the causal attribution goes.

**Net effect on your instruction:** unchanged in substance — do not re-implement the edge, do not
imply it is broken. Changed in one word: the PR body says the htpasswd hypothesis was
**falsified by the experiment it motivated**, not that it was fixed.

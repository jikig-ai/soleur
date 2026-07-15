---
title: "fix(ci): infra-validation renders cloud-init templatefiles before schema-checking them"
issue: 6454
pr: 6458
branch: feat-one-shot-6454-infra-validation-templatefile
lane: cross-domain
type: bug
date: 2026-07-15
requires_cpo_signoff: false
---

# fix(ci): infra-validation renders cloud-init templatefiles before schema-checking them

🐛 Closes #6454.

> **Note on `lane:`** — no `spec.md` exists for this branch, so `lane:` defaulted to `cross-domain` (TR2 fail-closed).

## Overview

`.github/workflows/infra-validation.yml`'s `validate` job runs `cloud-init schema -c cloud-init.yml` against a **raw Terraform templatefile**. `apps/web-platform/infra/cloud-init.yml` carries `%{ if web_colocate_inngest ~}` at line 665 **column 1**; YAML reads a leading `%` at column 0 as a *directive indicator* and the scanner hard-fails before schema checking ever begins. The job has therefore been red on **every** PR touching `apps/*/infra/**` since #6344 merged, and is invisible on `main` because the workflow is `pull_request`-only.

The fix is the one `plugins/soleur/skills/work/SKILL.md` §6.1 (line 622) has prescribed all along and that the workflow never adopted: **render the template, then validate the rendered output.**

Two failure classes are in scope, not one:

1. **Loud false-red** — `cloud-init.yml` fails on un-rendered template syntax (the filed bug).
2. **Silent false-green** — the step is guarded by `if [[ -f cloud-init.yml ]]`, so it validates **exactly one** of the repo's **four** cloud-init templatefiles. The other three are never validated at all, and even `cloud-init.yml`'s check, were it to parse, would only ever have validated *placeholder text*. A permanently-red gate and three permanently-unvalidated files are the same root cause wearing two hats.

Both are closed by rendering every templatefile via `terraform console` + `templatefile()` with an **auto-derived** stub var map, then validating the rendered doc — plus a counter that makes a silent skip impossible.

## Design Decision 0: render vs. strip (challenged at plan-review; settled on evidence)

The simplicity panel proposed replacing the whole renderer with a one-line directive strip — `perl -pe 's/(?<!%)%\{[^}]*\}//g'` then `cloud-init schema` — arguing ~15 lines beats ~100 and that rendering-with-`"x"`-stubs is no stronger than validating raw placeholders. It demonstrated the strip closes the filed bug and catches the injected `runcmd`/YAML defects. **It also falsified two of my claims, and I have corrected them below.** But on the core architecture the evidence goes the other way. I ran its proposal:

| Probe | Result |
| --- | --- |
| `web_colocate_inngest` default (`variables.tf`) | **`false`** — so the **false arm is the default production document** |
| Strip output | **796 lines** — matches **neither** arm (true=795, false=731) |
| Inngest-bootstrap lines: strip vs false arm | **49 vs 26** |
| `hooks.json.tmpl` stripped → JSON parse | **INVALID** — `${jsonencode(...)}` survives a `%{`-only strip |

Three findings, each disqualifying on its own:

1. **The strip validates a document that cannot exist.** Deleting `%{ if … ~}` / `%{ endif ~}` keeps the gated body unconditionally, yielding a 796-line Frankenstein matching no real config. Terraform emits **795** (true) or **731** (false).
2. **It never validates the default production config.** `web_colocate_inngest` defaults to `false`, so the document every web host actually boots is the 731-line false arm — the one the strip never produces. A gate that validates a config no host boots, while never validating the one they all do, is a *sophisticated* false-green. That is failure class (2) with extra steps.
3. **It cannot validate JSON templates at all.** A `%{`-only strip leaves `${jsonencode(webhook_deploy_secret)}` in place → `hooks.json.tmpl` fails to parse. Extending the strip to `${…}` would delete the value and *still* produce invalid JSON. So the strip cannot cover `hooks.json.tmpl` today, nor **#6448's `docker-daemon.json`** — the case the coordinator made binding.

The panel's cost accounting also overstates: **terraform is already installed in this job** (`setup-terraform`, line 94, for `terraform fmt` + `terraform validate`). The render adds **no** CI dependency — only a step reorder.

**Verdict: keep the render.** It produces both real documents exactly, validates JSON, auto-covers #6448, and is what `plugins/soleur/skills/work/SKILL.md` §6.1 has prescribed all along. The panel's simplification findings are adopted in full elsewhere (see *Plan-Review Adoptions*) — the architecture is not.

**Where the panel was right, and my text is now corrected:** rendering with `"x"` stubs is **not** categorically stronger than raw for a *simple scalar interpolation in a scalar slot* — both check a placeholder. Rendering's advantage is specific and provable, not general: it resolves **directives** (arm selection — the decisive gap above) and produces **structurally valid JSON** where a placeholder would not. The earlier blanket claim that raw-validation is "precisely the false-green" was too broad and has been narrowed.

### The design must be principled, not a filename allowlist

The fix is discovered **structurally**, not by filename. The next PR in this approved sequence, **#6448**, will very likely convert `apps/web-platform/infra/docker-daemon.json` from `file()` (verified today at `server.tf:571`, `server.tf:589`) into a `templatefile()` so its `insecure-registries` entry derives from `local.registry_private_ip` instead of a hardcoded `10.0.1.30:5000`.

**Precision, per plan-review (my first draft overstated this and the panel was right to call it):** a `cloud-init*.yml` glob does **not** *red* when #6448 lands — it keeps validating the cloud-inits and simply **never expands to cover `docker-daemon.json`**. It does not break; it **fails to auto-cover**. That is not a false-red, but it *is* failure class (2) — the same silent non-coverage that leaves 3 of 4 cloud-inits unvalidated today, extended to a new file. The honest claim is under-coverage, not breakage.

The binding test for every candidate design is therefore: *when #6448 adds a second raw templatefile, is it covered with **no edit to the validation**?* The coordinator made this explicit and preferred either rendering-before-validating or detecting template-ness **structurally** (by the file being referenced by a `templatefile()` call) **rather than by filename**. **This design does, and it was proven by simulation, not asserted** (below).

Discovery is the **union** of two structural sets, never a filename allowlist:

- **(A)** every file referenced by a `templatefile(...)` call in the root's `*.tf` — the authoritative "this is a template" signal, straight from the consumer;
- **(B)** every `cloud-init*.yml` present — catches a cloud-init consumed via `file()` that (A) would miss.

`A ∪ B` is **5 files today**, not 4: (A) already contains **`hooks.json.tmpl`** (`server.tf:5`), a JSON template that **nothing in the repo currently validates**. Broadening from the glob to the structural set closes that gap as a side effect.

> *Correction, per plan-review:* `hooks.json.tmpl` has **13 occurrences of exactly one variable** (`${jsonencode(webhook_deploy_secret)}`), not 13 distinct vars — verified: key extraction yields **1** key. The coverage gain is one interpolation across a previously-unvalidated JSON file, not thirteen. Worth having (the file reaches prod unvalidated today), but it is one var.

### Proof-of-concept: executed, not hypothesised

Prototyped end-to-end this session against Terraform **v1.10.5** (byte-identical to the workflow's pinned `TERRAFORM_VERSION`) and the real corpus. Verified `2026-07-15`:

| File | Discovered via | Render | Stub-var leaks | Validation |
| --- | --- | --- | --- | --- |
| `cloud-init.yml` (bool=true) | A ∪ B | OK — 795 lines | 0 | `Valid schema` |
| `cloud-init.yml` (bool=false) | A ∪ B | OK — 731 lines | 0 | `Valid schema` |
| `cloud-init-registry.yml` | A ∪ B | OK — 631 lines | 0 | `Valid schema` |
| `cloud-init-inngest.yml` | A ∪ B | OK — 418 lines | 0 | `Valid schema` |
| `cloud-init-git-data.yml` | A ∪ B | OK — 182 lines | 0 | `Valid schema` |
| `hooks.json.tmpl` **(new coverage)** | A only | OK | 0 | `JSON parse: VALID` |

**The #6448 forward-compatibility test — actually run, not reasoned about.** A simulated #6448 was constructed in a scratch dir: `docker-daemon.json`'s `10.0.1.30:5000` replaced with `${registry_private_ip}:5000`, plus a `terraform_data` resource consuming it via `templatefile(...)`. Result with the **unmodified** script:

- structural discovery found `docker-daemon.json` from the `templatefile()` call site;
- it rendered and validated as JSON (`"insecure-registries": ["x:5000"]`);
- **zero edits to the validation were required.** The design passes the coordinator's test.

Negative proofs (the gate must **catch**, not merely pass):

- Injected `runcmd: "this-must-be-a-list-not-a-string"` → `Error: Cloud config schema errors: runcmd: '...' is not of type 'array'`, **exit 1**. The load-bearing result: `cloud-init schema` performs **real semantic validation** post-render, and that coverage has been dead since #6344.
- Injected malformed YAML → `Error: ... is not valid YAML`, **exit 1**.
- Appended `,,,BROKEN` to `hooks.json.tmpl` → rendered doc fails JSON parse → gate reds. The JSON leg bites too.

`terraform console` runs in an **empty `-chdir` scratch dir** — `templatefile()` is a builtin, so this needs **no `terraform init`, no providers, and no credentials**, preserving the validate job's credential-free contract (workflow header, line 6).

## Research Reconciliation — Spec vs. Codebase

Every row below was mechanically verified this session. Several correct the task brief **and the issue body** — treat the issue's proposed remediation as a proposal that was verified and partially amended, not as fact.

| Claim | Reality | Plan response |
| --- | --- | --- |
| *(task brief)* The failing file is `cloud-init-registry.yml`, which interpolates `${zot_image}` | **FALSE.** `cloud-init schema -c cloud-init-registry.yml` → **exit 0, "Valid schema"**. `cloud-init.yml` → **exit 1**. The brief's premise was wrong. | Plan targets `cloud-init.yml` as the red file; all four get rendered. |
| *(issue)* "`cloud-init-inngest.yml` … contain[s] no `%{`" | **Misleading.** It contains 3 × `%{` — but all are **escaped** `%%{` (curl `-w` format strings). Real TF directives: `cloud-init.yml`=2, all others=**0**. | Detection must use negative lookbehind, not a naive grep (below). |
| *(issue)* Proposed detector `grep -qE '\$\{|%\{'` | **Insufficient.** Matches escaped `$${` (6/10/5/2 per file) and `%%{` (0/0/3/0), so it misclassifies escapes as template syntax. | Use `(?<!\$)\$\{` and `(?<!%)%\{` (PCRE). |
| *(issue)* The job schema-validates the cloud-inits | **Only one.** `if [[ -f cloud-init.yml ]]` — `cloud-init-registry.yml`, `cloud-init-inngest.yml`, `cloud-init-git-data.yml` are **never validated**. Real `${` counts: 27/17/22/13 — all four are templatefiles. | Loop over `cloud-init*.yml`; assert count validated == count present. |
| *(issue)* Alternative: "skip the schema step for templatefile-consumed cloud-inits" | **Rejected.** All four are templatefile-consumed, so this degrades the gate to a total no-op — the exact failure class in scope. | Render. Never skip. |
| *(agent research)* Add a fast path: raw-validate files with no `%{` | **Rejected.** All four carry real `${…}`; raw-validating them checks *placeholder strings* — that is precisely the false-green. Raw validation is correct **only** for a file with neither `${` nor `%{`. | Raw path retained but reachable only on zero template syntax. |
| *(my own earlier finding)* "Every interpolation across all four files is a bare identifier — so the extractor is safe" | **TRUE for the 4 cloud-inits, FALSE for the real templatefile set.** Broadening discovery to set (A) immediately surfaces `hooks.json.tmpl`'s `${jsonencode(webhook_deploy_secret)}` — a **function call**. My v1 extractor exited 3 on it: a **red gate on a correct file**, i.e. #6454 reproduced by my own fix. Caught only because the coordinator's constraint forced structural discovery. | Extractor rule: an identifier immediately followed by `(` is a **function**, not a var → drop it. Verified: `hooks.json.tmpl` now renders and parses as valid JSON, and all 4 cloud-inits still pass. |
| *(my own earlier design)* Pre-emptive "unsupported interpolation shape" check → exit 3 | **Rejected — it was guessing.** A hand-rolled shape-classifier cannot enumerate Terraform's expression grammar (ternaries, nested calls, `try()`), and every gap becomes a false-red. | **Terraform is the authority.** Render and let `terraform console` judge: a missing key yields `vars map does not contain key "X"`, a bad type yields a condition/type error. Surface its message verbatim and exit non-zero. Strictly more accurate than any guess, and simpler. |
| *(coordinator)* `docker-daemon.json` is consumed via `file()` today and #6448 will likely make it a `templatefile()` | **Confirmed:** `server.tf:571` `sha256(file("${path.module}/docker-daemon.json"))` and `server.tf:589` `source = "${path.module}/docker-daemon.json"`. | Structural discovery (set A) picks it up automatically on the day #6448 converts it. Proven by simulation — see PoC. |
| Is `hooks.json.tmpl` validated today? | **No.** It is referenced by `ci-deploy.test.sh` / `cutover-inngest-workflow.test.sh` / `infra-config-apply.test.sh`, but none render-and-parse it. A malformed `hooks.json.tmpl` reaches prod unvalidated. | Set (A) covers it. Net-new coverage, free. |
| *(prior art)* `private-nic-guard.test.sh:87` blanket assertion `! grep -qE '\$\{[A-Za-z0-9_.]+\}'` | **Would FALSE-FAIL on a full-file render.** TF-escaped `$${DOPPLER_SHA256}` legitimately renders to `${DOPPLER_SHA256}`. That assertion only survives in its own file because those shell seams use `:-` defaults, which break its `\}` anchor (its own comment says so). | Scope the residual assertion to the **derived stub var names**, not a blanket `${…}` pattern. Verified: 0 stub-var leaks; 4 legitimate shell `${…}` survive. |
| *(prior art)* AC7's hardcoded map — "a new map var breaks this render (**the intended tripwire**)" | Acceptable in an advisory test; **fatal in the gate**. A gate that reds when someone adds a var re-creates #6454 verbatim. | Auto-derive the map; replace the accidental tripwire with an **explicit** template↔`.tf` cross-check. |
| *(task brief)* Proof = a PR touching `apps/*/infra/**` goes green | **Trap.** `detect-changes` derives the matrix from the diff. A PR touching **only** the workflow yields `directories == '[]'` → `validate` is **skipped** → reads green. That is the forbidden outcome. | The PR **must** touch a real `apps/*/infra/**` file. Encoded as AC9. |
| *(issue)* "consider promoting to required" | **Not directly feasible.** `validate` is a matrix job; check names (`validate (apps/web-platform/infra)`) are dynamic and cannot be pinned in `infra/github/ruleset-ci-required.tf`. Needs an `if: always()` aggregator (precedent: `tenant-integration-required`) + a TF apply. | **Follow-up issue** (Non-Goals). Mitigated in-scope — see below. |
| Is `validate` a required check? | **No** — absent from `ruleset-ci-required.tf`'s 18 contexts. Precisely why it survived red. | See mitigation. |
| Does `guard-script-fixture-tests` run always? | **Yes — and it is REQUIRED** (ruleset 14145388), on `pull_request` **and** `merge_group`, with no path filter. | **Load-bearing:** the anti-no-op proof lives *here*, not in the advisory job. |

### The required-check story (two layers, and the aggregator ships here)

The issue frames non-required status as the reason the red gate survived — "It is non-required, so it does not block merge — which is precisely why it has survived."

- **Gate correctness** — "does this catch a malformed template?" — is proven by `.github/scripts/test/test-validate-infra-templates.sh`, which runs inside `guard-script-fixture-tests`: **required, path-filter-free, every PR and merge_group.** This needs no ruleset change and lands here.
- **Gate application** to the *real* corpus runs in the `validate` matrix job, which cannot itself be required (matrix check names are dynamic). The static-named **`infra-validate-required` aggregator ships in this PR** (Phase 3) so an admin can flip the ruleset in a one-line follow-up. Deferring the aggregator too would guarantee a *second* structural edit to the same workflow later; deferring only the `ruleset-ci-required.tf` entry + apply is a legitimate, minimal hand-off.

Fixture-tests alone would be insufficient — they only ever see synthetic fixtures, never the repo's real templates. The aggregator is what closes that.

## User-Brand Impact

- **If this lands broken, the user experiences:** a malformed `cloud-init.yml` merges undetected, `terraform apply` provisions a host that fails first boot, and `soleur.ai` serves nothing until a human notices — the gate that should have caught it having been green-because-skipped.
- **If this leaks, the user's data is exposed via:** no new exposure vector. The renderer stubs every var with the literal `"x"` and reads **no** secrets: it runs in an empty scratch dir with no Doppler token, no backend creds, no provider. Real secret values never enter the render.
- **Brand-survival threshold:** `aggregate pattern`

Rationale for `aggregate pattern` over `none`: the diff touches two paths flagged by preflight's canonical `SENSITIVE_PATH_RE` (`apps/[^/]+/infra/` and `\.github/workflows/.*infra-validation.*\.ya?ml$`). The failure mode is delayed detection of a class of infra defects, surfacing as a reliability pattern rather than one user's data being exposed — but it is not `none`, because the gate guards prod host boot.

## Observability

```yaml
liveness_signal:
  what:            "validate (apps/*/infra) job outcome + the script's `validated N/N` summary line"
  cadence:         "per-PR — every PR touching apps/*/infra/** or infra/**"
  alert_target:    "PR checks UI (advisory) + required `Bash fixture tests for guard scripts` (blocking)"
  configured_in:   ".github/workflows/infra-validation.yml (validate job) + .github/workflows/pr-quality-guards.yml:25"

error_reporting:
  destination:     "GitHub Actions job log + PR check status (no Sentry — this is CI-plane, not runtime)"
  fail_loud:       "script exits non-zero; step has NO continue-on-error; no self-SKIP on missing tooling"

failure_modes:
  - mode:          "Rendered cloud-init violates cloud-init schema (e.g. runcmd not an array)"
    detection:     "`cloud-init schema -c <rendered>` exits 1 -> script exit 1. Proven with an injected fixture"
    alert_route:   "validate job red on the PR"
  - mode:          "Rendered JSON template (hooks.json.tmpl, future docker-daemon.json) is malformed"
    detection:     "JSON parse of rendered doc fails -> script exit 1. Proven by appending ',,,BROKEN'"
    alert_route:   "validate job red on the PR"
  - mode:          "Render fails: var missing from the map, wrong type, or an expression shape we mis-derived"
    detection:     "terraform console exits non-zero; its message is surfaced verbatim -> script exit 2"
    alert_route:   "validate job red on the PR"
  - mode:          "Template references a var the .tf templatefile map does not pass (breaks at APPLY, not validate)"
    detection:     "cross-check: derived template identifiers not a subset of .tf map keys -> script exit 4"
    alert_route:   "validate job red on the PR"
  - mode:          "Gate silently validates nothing (the #6454 class recurring)"
    detection:     "script asserts validated_count == |A union B|; mismatch -> script exit 5"
    alert_route:   "validate job red on the PR"
  - mode:          "terraform or cloud-init absent from the runner"
    detection:     "script fail-closed exit 6 (deliberately NOT the AC7 self-SKIP)"
    alert_route:   "validate job red on the PR"
  - mode:          "PR touches only the workflow -> matrix empty -> validate SKIPPED, reads green"
    detection:     "test-validate-infra-templates.sh runs in the REQUIRED, path-filter-free guard-script-fixture-tests job"
    alert_route:   "required check red — blocks merge"
  - mode:          "A new templatefile lands (e.g. #6448's docker-daemon.json) and goes unvalidated"
    detection:     "structural discovery reads templatefile() referents from *.tf — no filename allowlist to update"
    alert_route:   "validate job red on the PR if the new template is broken; covered automatically if sound"

logs:
  where:           "GitHub Actions run logs — `gh run view <id> --log`"
  retention:       "90 days (repo default)"

discoverability_test:
  command:         "bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra"
  expected_output: "exit 0 and a line matching `rendered\\+validated ([0-9]+)/\\1 file\\(s\\)` (N==N; today N=5)"
```

The `validated N/N` line is not decoration: it is the machine-checkable evidence that the gate **ran** rather than skipped, and AC10 greps CI logs for it. `N` is `|A ∪ B|` = **5** today (4 cloud-inits + `hooks.json.tmpl`) and grows on its own as templatefiles are added — so the assertion is the **computed equality N==N**, never the literal `5`. (Plan-review catch: pinning `5/5` anywhere would go stale the moment #6448 lands — the #6454 shape one layer up.)

**Exit-code contract** (every path is loud; none is a skip): `0` pass · `1` validation failed · `2` render failed (terraform's message surfaced) · `3` stub var leaked into rendered output · `4` template↔`.tf` drift · `5` counter mismatch (silent-skip guard) · `6` required tooling absent (fail-closed).

## Design Decision 1: how templates are discovered (principled vs. filename)

| Option | Verdict |
| --- | --- |
| **Filename glob `cloud-init*.yml`** (my own v1) | **Rejected.** Passes CI today, silently fails when #6448 makes `docker-daemon.json` a templatefile. A validator that only knows about files it was told about by name is the same class of defect as the bug being fixed. |
| **Per-file skip-list** (e.g. name `cloud-init-registry.yml` as exempt) | **Rejected outright.** Explicitly the anti-goal: it is a no-op wearing a config file. |
| **Structural: `A ∪ B`** — (A) `templatefile()` referents parsed from `*.tf` ∪ (B) `cloud-init*.yml` present | **CHOSEN.** (A) is the consumer's own declaration of template-ness — the most authoritative signal available, and the one that auto-covers #6448. (B) backstops a cloud-init consumed via `file()` that (A) would miss. The union cannot be gamed by a rename. |

**Template-ness is then confirmed structurally, not by extension:** a file in the set is rendered iff it contains real template syntax under negative lookbehind (`(?<!\$)\$\{`, `(?<!%)%\{`) — so TF-escaped `$${SHELL_VAR}` and `%%{http_code}` are correctly *not* mistaken for template syntax. A set member with zero real template syntax takes the raw path.

**Validation then dispatches by type**, so the set can grow beyond cloud-init:

| Member | Validator |
| --- | --- |
| `cloud-init*.yml` | `cloud-init schema -c <rendered>` (semantic + YAML) |
| `*.json`, `*.json.tmpl` | JSON parse of the rendered doc |
| anything else | render + stub-var-leak assertion (still real: catches TF var/type errors) |

This is what makes the answer to "does #6448 need to touch the validation again?" a proven **no**.

## Design Decision 2: where the stub var map comes from

This is the plan's other real architectural choice, and the brief demanded it be resolved explicitly rather than papered over.

| Option | Verdict |
| --- | --- |
| **(a) Hardcoded stub map** (mirrors the inngest suite's AC7 prior art) | **Rejected.** That suite's own comment calls a new map var breaking the render "the intended tripwire". In an advisory test that is tolerable. Wired into the gate it **re-creates #6454 exactly**: the day someone adds a templatefile var, the gate reds for a non-reason, operators re-learn to ignore it. Fixing a false-red by installing a different false-red is not a fix. |
| **(b) Derive var names by scanning the template body** | **Rejected — this was my v1, and the strong-model consult killed it.** It re-implements Terraform's expression grammar while claiming not to guess. Fatal case: `%{ for x in list ~}` binds `x` **template-locally**; a body-scanner derives `x`, `x` is absent from the `.tf` map, and the gate hard-reds a **perfectly valid template** — #6454 reborn, by my own hand. No current file uses `%{ for }`, so this would have shipped green and detonated later. |
| **(c) KEYS from the `.tf` templatefile map + TYPES from the body** | **CHOSEN.** The `.tf` map is the authoritative statement of what `templatefile()` actually receives — the same parse discovery already performs (D1), so it is free. Loop-locals and function names can never enter the map, because only real map keys do. The body is consulted **only** for typing (`%{ if <id> …}` → bool, else string), which the `.tf` alone cannot supply. |
| **(d) Drive the render from Terraform's real vars** | **Rejected.** Requires resolving ~13 Doppler-backed sensitive variables; the validate job is credential-free by design (workflow header line 6). |

Verified end-to-end under (c) this session — all 5 members render and validate: 4 cloud-inits `Valid schema`, `hooks.json.tmpl` `JSON VALID`. Extraction yields exactly **13** keys for `cloud-init.yml`, **10** for `cloud-init-registry.yml`, **1** for `hooks.json.tmpl`.

**Attribution must be comment-proof — found by running it, not by reasoning.** A loose `grep -l "templatefile(.*cloud-init.yml" *.tf` matches **`ci-ssh-key.tf:92`**, whose *prose comment* reads ``# `templatefile()` interpolation map so `cloud-init.yml`'s ``. Picking that file yields an **empty** key map and a failed render. Both discovery and attribution therefore anchor on the real call syntax — `templatefile\(\s*"\$\{path\.module\}/<name>"` — which a comment does not match. Verified: anchored attribution maps `cloud-init.yml`→`server.tf`, `hooks.json.tmpl`→`server.tf`, `cloud-init-registry.yml`→`zot-registry.tf`, with `ci-ssh-key.tf` correctly ignored.

**Terraform is the backstop authority.** The script does not pre-judge grammar; it renders and lets `terraform console` rule:

- a key the template needs but the `.tf` map omits → `Invalid function argument` / `vars map does not contain key "X"` → exit 2, message surfaced verbatim (**this replaces the v1 exit-4 cross-check — Terraform performs it for free, with a better message**);
- a mistyped key (bool stubbed as string) → Terraform's condition/type error → exit 2;
- a key in the `.tf` map the template ignores → harmless; `templatefile()` permits unused map keys.

Every failure is judged by the tool that defines the grammar and reported in its own words. Simpler *and* strictly more accurate than a hand-rolled classifier — and it is what keeps the gate from ever red-lighting a correct file, which is the #6454 failure class it exists to end.

## Design Decision 3: extracting the rendered doc from `terraform console`

The prior art strips `terraform console`'s `<<EOT … EOT` heredoc wrapper (first/last line). **That method is broken, and I proved it rather than inheriting it:**

```
# single-line template -> console emits a QUOTED STRING, not a heredoc
$ printf 'templatefile("one.txt", { v="hi" })' | terraform -chdir=$(mktemp -d) console
"x=hi"
# the <<EOT strip yields:  "x=hi"   <- quotes intact, NOT the document
```

Two defects: (1) it silently mangles any template Terraform renders as a quoted string rather than a heredoc — **live**, not theoretical, for any short template; (2) it breaks on a rendered doc containing a line that is exactly `EOT` — latent today (verified: no bare `EOT` line in the current corpus), but a bare-line grep is a fragile thing to bet a gate on.

**CHOSEN:** wrap as `jsonencode(templatefile(…))` and decode. Note the subtlety — `terraform console` **re-quotes** the `jsonencode` result, so the output is double-encoded and a single `jq -r` is *not* enough (the consult suggested one pass; testing showed two are required):

```bash
printf 'jsonencode(templatefile("%s", { … }))\n' "$tpl" \
  | terraform -chdir="$(mktemp -d)" console | jq -r . | jq -r .
```

Verified: yields the identical 795-line document for `cloud-init.yml` (`Valid schema`), and correctly yields `x=hi` — unquoted — for the single-line case the `<<EOT` strip mangles. No first/last-line surgery, immune to both defects.

**What option (c)-as-cross-check buys:** it recovers the *real* value AC7's tripwire was groping for. AC7 caught yml/`.tf` drift **by accident** (the render broke). The cross-check catches it **on purpose**, with an error that says what actually went wrong — and it catches the more dangerous direction AC7 never could: a `${new_var}` added to the yml but **not** to the `.tf` map, which `terraform validate` does not catch and which breaks at **apply** time in production.

### Documented coverage narrowing (stated loudly, per scope constraint)

The renderer renders **two** passes per templated file: all-bools-`true` and all-bools-`false`.

- For the current corpus this is **complete**: only `cloud-init.yml` has directives, with exactly **one** bool (`web_colocate_inngest`), so 2 passes = 2 of 2 possible states. Both were proven to render and pass schema this session (795 / 731 lines — the arms genuinely differ, so both are real).
- If a file ever carries **N ≥ 2** bools, all-true/all-false covers 2 of 2^N states — a **real narrowing**. Mixed combinations would be unvalidated.

This is a conscious trade against combinatorial blowup. **Deliverable:** the script emits the bool count, and Phase 4 files a follow-up issue to revisit if any file reaches N ≥ 2. No file does today.

## Files to Create

- **`.github/scripts/validate-infra-templates.sh`** — the generic renderer + validator. Takes an infra-root dir; discovers `A ∪ B` structurally; renders; dispatches validation by type. Repo-level (not under `apps/web-platform/infra/`) because `validate` fans out over `apps/*/infra` **and** `infra/*` and must not assume web-platform's layout. **Named for what it does** — it is not cloud-init-specific (it already covers `hooks.json.tmpl`, and #6448's `docker-daemon.json` next).
- **`.github/scripts/test/test-validate-infra-templates.sh`** — fixture tests on **synthesized** templates (`cq-test-fixtures-synthesized-only`). Auto-discovered by `run-all.sh`'s `test-*.sh` glob → lands in the **required** `guard-script-fixture-tests` job.

## Files to Edit

- **`.github/workflows/infra-validation.yml`** — rewrite the `Validate cloud-init schema` step to call the script; **move it after `setup-terraform`**; add `terraform_wrapper: false`; add the `infra-validate-required` aggregator job.
- **`apps/web-platform/infra/cloud-init.yml`** — **a one-line comment only**, noting that the shared CI gate now renders this file via `templatefile()` and schema-checks the **rendered** doc. Two jobs: it is honest documentation at the point of confusion, and it **touches `apps/*/infra/**` so this PR's own `validate` matrix is non-empty** (AC11 — without such a touch the matrix is `[]`, `validate` is *skipped*, and a skip is a failure of this task). The comment must contain **no `%{`** — per `work/SKILL.md` §6.1, Terraform's directive scanner does not skip prose, so a `%{` in a comment would break the render. (No `${…}` either.)

**Cut at plan-review — the `cloud-init-inngest-bootstrap.test.sh` refactor.** My draft repointed that suite's AC7 `render_ci()` at the shared script to delete its hardcoded map. The simplicity panel was right and I have dropped it:

- Its main justification (killing the tripwire) **contradicts my own text**, which concedes the tripwire is "acceptable in an advisory test". It is a test of the *toggle's behavior* (gated-off omits the bootstrap; `false` vs `"false"` coercion), not a gate on template validity.
- Its other real justification — providing the `apps/*/infra/**` touch — is served by the one-line comment above at a fraction of the cost.
- It would have forced a `--set-var` API onto the script purely for one test's benefit.

The hardcoded map stays. It is pre-existing, advisory, and not this PR's bug. → **follow-up issue** (Non-Goals).

### Open Code-Review Overlap

One hit, on a path I am not editing:

- **#2197** (`refactor(billing): SubscriptionStatus type + hoist single-instance throttle doc…`) — matched only because its body mentions `apps/web-platform/infra/server.tf`. **Disposition: Acknowledge.** Entirely different concern (billing types), and `server.tf` is not in Files to Edit. Remains open.

No open code-review issue touches `.github/workflows/infra-validation.yml`, `.github/scripts/`, `cloud-init.yml`, or `cloud-init-inngest-bootstrap.test.sh`.

## Implementation Phases

Phase order is load-bearing: the contract (the script) ships before its consumers (workflow, AC7).

### Phase 1 — RED: prove the gate is broken and the fixtures bite

1. Write `.github/scripts/test/test-validate-infra-templates.sh` against synthesized fixtures in a `mktemp -d` (`cq-test-fixtures-synthesized-only`; each fixture ships a stub `*.tf` so discovery has a call site). The panel argued 10 → 4; I keep 9, because each survivor below asserts a **distinct exit code**, and a fixture asserting merely "non-zero" passes when the script crashes for an unrelated reason:
   - **F1 (the #6454 regression):** `%{ if flag ~}` / `%{ endif ~}` at **column 1** + a `${var}`. Raw `cloud-init schema` fails; script must **pass** it.
   - **F2 (anti-no-op, load-bearing):** renders to `runcmd: "a-string"` → **exit 1**. *The single most valuable fixture in the suite.*
   - **F3 (anti-no-op):** renders to malformed YAML → exit 1.
   - **F4 (escape fidelity):** `$${SHELL_VAR}` + `%%{http_code}` and **no** real template syntax → **raw** path; escapes must not be misread as template syntax. *The negative lookbehind is the subtlest character sequence in the fix; the live `%%{http_code}` curl strings in `cloud-init-inngest.yml` depend on it.*
   - **F5 (silent-skip guard):** two templates, one unreadable → exit 5, never a partial pass.
   - **F6 (attribution, repurposed):** a template whose `.tf` call site is absent, and one referenced by **two** call sites → exit 4 both times. Guards the `ci-ssh-key.tf` comment-match trap found this session.
   - **F7 (arm selection):** `%{ if b ~}A%{ else ~}B%{ endif ~}` where arm **B alone** is schema-invalid → exit 1. *Proves both arms are really validated — the property justifying the render over a strip (Design Decision 0). A strip would pass this vacuously.*
   - **F8 (fail-closed tooling):** simulate absent `terraform` → exit 6, **not** SKIP.
   - **F9 (JSON leg + #6448 forward-compat, load-bearing):** a `.tf` declaring `templatefile("…/some-config.json", {ip = local.x})` + that JSON template, rendering to malformed JSON → discovered **from the call site alone**, no filename-list entry, → exit 1. Merges the panel-cut F10 into the JSON fixture: one fixture, both properties.
2. Run: every fixture fails (script absent). **Verify RED.**

### Phase 2 — GREEN: the renderer

Implement `.github/scripts/validate-infra-templates.sh`:

1. `set -uo pipefail`; arg = infra-root dir; resolve to an absolute path.
2. **Discover `A ∪ B`:** (A) parse `templatefile(` referents from `*.tf` (`templatefile\(\s*"\$\{path\.module\}/\K[^"]+`); (B) glob `cloud-init*.yml`. **Zero members → print `no infra templates in <dir>` and exit 0** (legitimate: `infra/github/` has none). Presence-based, never metadata/substring-based (per the fail-open-gate learning).
3. Fail closed (exit 6) if `terraform` is absent, or if `cloud-init` is absent while set (B) is non-empty. **Deliberately not AC7's self-SKIP** — an advisory test may skip; a gate may not.
4. Per member:
   - Detect real template syntax with negative lookbehind: `(?<!\$)\$\{[^}]*\}` and `(?<!%)%\{[^}]*\}`. **No `head -N` truncation** (per `2026-07-01-existence-grep-must-not-be-head-truncated`).
   - Zero real template syntax → validate raw by type; `validated++`; continue.
   - **Attribute** the member to its `.tf` call site with the **anchored, comment-proof** pattern `templatefile\(\s*"\$\{path\.module\}/<name>"`. Zero call sites while the member *has* template syntax → **exit 4** (loud: a template nobody renders). More than one call site → **exit 4** (ambiguous; do not silently pick one).
   - **KEYS** = the templatefile map keys, via awk starting **after** the `{` (not at the `templatefile(` line — that captures the enclosing `user_data =` assignment as a phantom key) and stopping at `^\s*\}\)`. **TYPES** from the body: a key matching `%{ if <key>` → bool, else string. Build the map (`key="x"` / `key=true|false`).
   - Render both bool arms: `printf 'jsonencode(templatefile("%s", { … }))\n' | terraform -chdir="$(mktemp -d)" console | jq -r . | jq -r .`. **Non-zero → exit 2, surfacing terraform's message verbatim** (terraform is the grammar authority; the script never guesses). No `<<EOT` surgery — see Design Decision 3.
   - Assert **no map key** survives as `${key}` in the rendered doc → exit 3. *Not* a blanket `${…}` grep, which false-fails on legitimately-rendered `$${SHELL_VAR}`.
   - Validate by type: `cloud-init*.yml` → `cloud-init schema -c`; `*.json`/`*.json.tmpl` → JSON parse; else → render-only.
5. Assert `validated == |A ∪ B|` → else **exit 5**.

   > *Corrected at /work:* the draft read `validated++` **per arm** here while asserting `validated == files_present` in the next step — those contradict, since `cloud-init.yml` is one file with two arms and would count 2 against a discovered 1, hard-failing exit 5 on a correct corpus. The Observability block's `rendered\+validated ([0-9]+)/\1 file\(s\)` settles it: the counter is **per file**, incremented once all of that file's arms validate. Implemented per-file. (The draft also carried two steps numbered `5`; merged.)
6. Print `infra template validation: rendered+validated N/N file(s) in <dir>` and the bool count.
7. Run Phase 1's fixtures. **Verify GREEN.**

### Phase 3 — Wire the consumers

1. `.github/workflows/infra-validation.yml`:
   - Move `Validate cloud-init schema` to **after** `hashicorp/setup-terraform` (the script needs `terraform` on PATH); rename it `Validate infra templates (render-then-validate)`.
   - Add `terraform_wrapper: false` to that `setup-terraform` — the wrapper corrupts `terraform console` stdout and the decode depends on byte-clean output. `deploy-script-tests` already sets it for exactly this reason (workflow lines 158-164).
   - Body → `bash "$GITHUB_WORKSPACE/.github/scripts/validate-infra-templates.sh" "${{ matrix.directory }}"`, retaining the `apt-get install -y -qq cloud-init` bootstrap. **No `continue-on-error`** (per `2026-07-15-silent-fallback-masked-a-dead-primary-for-14-days`: it yields `conclusion=success` over `outcome=failure`).
   - **Add the `infra-validate-required` aggregator job** (~10 static lines) — the static-named gate a matrix job cannot be. Precedent: `tenant-integration-required` in `ruleset-ci-required.tf`.

     ```yaml
     infra-validate-required:
       needs: [detect-changes, validate]
       if: always()
       runs-on: ubuntu-24.04
       steps:
         - name: Fail closed if validate did not succeed when it should have
           env:
             DIRS: ${{ needs.detect-changes.outputs.directories }}
             RESULT: ${{ needs.validate.result }}
           run: |
             if [[ "$DIRS" == "[]" ]]; then
               echo "No infra directories changed; nothing to validate."; exit 0
             fi
             if [[ "$RESULT" != "success" ]]; then
               echo "validate did not succeed (result=$RESULT) while infra changed: $DIRS"; exit 1
             fi
             echo "validate succeeded for: $DIRS"
     ```

     The second clause is the **anti-silent-skip guard at job level**: infra changed but `validate` was `skipped`/`cancelled`/`failure` → red. It always runs, so it always reports a status (no required-check deadlock — see `2026-03-20-github-required-checks-skip-ci-synthetic-status`).
2. `apps/web-platform/infra/cloud-init.yml`: add the **one-line comment** (no `%{`, no `${`) — the `apps/*/infra/**` touch that keeps this PR's matrix non-empty.
3. **Do-no-harm step (demoted from an AC at plan-review):** run the three coordinator-named suites locally and confirm they still pass — `registry-insecure-config.test.sh`, `private-nic-guard.test.sh`, `soleur-host-bootstrap-observability.test.sh`. All three are **verified BASELINE PASS** as of this plan, so any failure is attributable to this PR, not pre-existing. Also run `bash .github/scripts/test/run-all.sh` and `bash apps/web-platform/infra/cloud-init-inngest-bootstrap.test.sh` (untouched, must stay green).

### Phase 4 — Verify against real CI + follow-ups

1. Push. Confirm via **real CI logs** (`gh run list`, `gh run view <id> --log`) that `validate (apps/web-platform/infra)`:
   - **ran** (matrix non-empty — the PR touches `apps/web-platform/infra/cloud-init.yml`), and
   - **passed**, with the log carrying the `validated N/N` line.
   A skipped-but-green job is a **FAIL** of this task, not a pass.
2. Confirm `guard-script-fixture-tests` (required) and `infra-validate-required` are green.
3. File follow-ups (Non-Goals).

## Acceptance Criteria

Trimmed at plan-review from 16 to 10. Every AC below is a **checkable post-condition**, not a paraphrase of a phase instruction. **No AC pins a literal file count** — the panel correctly caught that `5/5` hardcoded into an AC is the #6454 shape one layer up (it goes stale the moment #6448 adds a template). Counts are asserted as *computed equality*, with today's value quoted only as context.

### Pre-merge (PR)

- [x] **AC1** — `bash .github/scripts/validate-infra-templates.sh apps/web-platform/infra` exits **0**, and its `validated N/N` line has **N == the number of discovered members** (today: 5 — 4 cloud-inits + `hooks.json.tmpl`). The script asserts the equality itself; the AC must not restate the literal. — **VERIFIED:** `rendered+validated 5/5 file(s)`, exit 0. All three matrix-selectable roots pass (`apps/cla-evidence/infra` and `infra/github` correctly report `no infra templates`, exit 0).
- [x] **AC2 (anti-no-op, load-bearing)** — F2 (renders to `runcmd: "a-string"`) → script exits **1**. *The single most valuable fixture here: a gate that cannot fail is not a gate.* — **VERIFIED.**
- [x] **AC3 (anti-no-op)** — F3 (malformed rendered YAML) → exit 1; F9 (malformed rendered JSON) → exit 1. — **VERIFIED** (both, plus F9b proves the JSON leg passes a well-formed doc, so F9 cannot pass merely by never discovering the file).
- [x] **AC4 (the filed bug)** — F1 (`%{ if … ~}` at column 1) exits **0** through the script, while `cloud-init schema -c` on the same raw file exits **1**. Encodes the exact before/after. — **VERIFIED** on the fixture *and* on the real `apps/web-platform/infra/cloud-init.yml`: raw exit 1, script exit 0.
- [x] **AC5 (silent-skip guard)** — F5 → exit 5; the script never reports success having validated fewer members than it discovered. — **VERIFIED.**
- [x] **AC6 (fail-closed)** — F8 (terraform absent) → exit 6, and the output contains **no** `SKIP`. — **VERIFIED** (F8 isolates the terraform-absent branch via a PATH carrying cloud-init but not terraform, and asserts the message names `terraform`).
- [x] **AC7 (arm selection — the render's load-bearing justification)** — for `cloud-init.yml` the script validates **both** the `true` arm and the `false` arm (the **default** production doc per `variables.tf`), and both pass. This is the property a directive-strip provably cannot deliver (Design Decision 0); without it the render is not worth its cost. — **VERIFIED: 803 / 739 lines.** *(Plan-time PoC measured 795/731; this PR's own 8-line `cloud-init.yml` comment accounts for the +8 on both arms. The load-bearing property is that the arms **differ** — proving both are really rendered — not the literal counts, per this section's own no-pinned-literals rule.)*
- [x] **AC8 (principled, not filename-bound — load-bearing)** — F9: a `.tf` declaring `templatefile("…/some-config.json", …)` plus that JSON template is discovered from the **call site alone** and validated, with no filename-list entry anywhere. This is what keeps #6448 from re-opening #6454. *(The panel correctly cut my companion `grep`-the-script-for-absent-strings check as a purity ritual — F9 tests the behavior, which is what matters.)* — **VERIFIED.**
- [x] **AC9** — `bash .github/scripts/test/run-all.sh` exits 0; `guard-script-fixture-tests` green. — **VERIFIED locally:** `ALL FIXTURE TESTS PASS` (the new suite auto-discovered by the `test-*.sh` glob, 19/19). CI leg confirmed at AC10.
- [ ] **AC10 (proof-of-fix — the whole point)** — on PR #6458's own run: `gh run view <id> --json jobs` shows job `validate (apps/web-platform/infra)` with `conclusion == "success"` **and** `status == "completed"` (**not** `skipped`), its log contains the `validated N/N` line, and `infra-validate-required` is green. All three: conclusion alone cannot distinguish pass from skip.

### Post-merge

- [ ] **AC11** — follow-up issues filed and linked (Non-Goals).

**Cut at plan-review, with reasons** (recorded so they are not silently re-added): the step-ordering / `terraform_wrapper` / `continue-on-error` AC (ordering is *proven by the step working* in AC1+AC10 — a corrupted stdout reds the decode); "no file except X modified" (scope policing, duplicates Non-Goal 6, and diff review does it); the sibling-suite AC (**demoted to a Phase-3 step** — the three suites are verified BASELINE PASS, and `run-all.sh`/CI is what enforces them); and the two ACs that died with the `render_ci()` refactor.

## Test Scenarios

| # | Scenario | Expect | Status |
| --- | --- | --- | --- |
| T1 | `cloud-init.yml`, bool `true` | render → `Valid schema` (803 lines as shipped; 795 at plan time, +8 = this PR's comment) | **verified** |
| T2 | `cloud-init.yml`, bool `false` (**default** prod doc) | render → `Valid schema` (739 lines as shipped; 731 at plan time, +8) | **verified** |
| T3 | Other three cloud-inits | render → `Valid schema` | **verified** |
| T4 | `hooks.json.tmpl` (`${jsonencode(...)}`) | render → JSON VALID (**new coverage**) | **verified** |
| T5 | Anchored attribution vs. `ci-ssh-key.tf`'s prose comment | maps to `server.tf`, comment ignored | **verified** |
| T6 | Single-line template | double-decode → `x=hi`; `<<EOT` strip → `"x=hi"` (**broken**) | **verified** |
| T7 | F2 semantic violation / F3 YAML / F9 JSON | exit 1 | **verified (F2/F3/JSON)** |
| T8 | F4 `$${VAR}` + `%%{http_code}`, no real syntax | raw path; escapes preserved | fixture |
| T9 | F6 absent / ambiguous `.tf` call site | exit 4 | fixture |
| T10 | F9 simulated #6448 `templatefile("…/some-config.json")` | discovered from call site; rendered; JSON-validated; **zero validation edits** | **verified by simulation** |
| T11 | Dir with no templates (`infra/github`) | exit 0, explicit message | fixture |
| T12 | Residual assertion vs. `$${SHELL_VAR}` | 4 legitimate `${…}` survive, **0** key leaks, no false-fail | **verified** |
| T13 | Sibling suites (Phase 3 step) | all three still pass | **BASELINE PASS captured** |

## Risks & Mitigations

| Risk | Mitigation |
| --- | --- |
| `terraform_wrapper` corrupts console stdout → decode breaks | `terraform_wrapper: false` on the validate job's `setup-terraform`. Precedent: `deploy-script-tests` sets it for this exact reason. A corrupted stdout reds the decode, so AC1/AC10 cover it — no separate AC needed. |
| Blanket residual `${…}` assertion false-fails on rendered shell vars | Proven this session (`${DOPPLER_SHA256}` et al.). Assertion scoped to the **map keys** (T12), not a blanket grep. |
| Mis-derived var/type on an unseen shape | Terraform is the authority: render fails → exit 2 with its verbatim message. The script never guesses, so it cannot silently mis-validate. Keys come from the `.tf` map, so loop-locals and function names cannot leak in. |
| `.tf` map-key parse is fragile | Anchored on the call syntax, starting **after** the `{` (the naive form captures the enclosing `user_data =` as a phantom key — caught and fixed this session). Verified: 13/10/1 keys for the three call sites. A parse that yields an empty map fails the render loudly (exit 2), never silently. |
| The gate becomes a no-op some other way | Counter assertion (exit 5) + F2/F3/F9 negative fixtures in a **required** job. |
| A new templatefile lands uncovered (the #6448 scenario) | Structural discovery from `templatefile()` call sites (AC8/F9). **Proven by simulation.** |
| PR touches only the workflow → matrix empty → skipped-but-green | AC10 asserts `status == completed` and non-skipped; the one-line `cloud-init.yml` comment keeps a real `apps/*/infra/**` touch in the diff; `infra-validate-required` reds if infra changed and `validate` did not succeed. |
| Render cost in CI | ~6 renders × ~1 s. Negligible; empty-dir console needs no `init`, and terraform is **already installed** in this job. |
| Terraform version drift CI vs. local | Prototyped on v1.10.5 = the workflow's pinned `TERRAFORM_VERSION`. |

## Plan-Review Adoptions

Recorded so cut scope is not silently re-added, and so the one rejection is auditable.

**Adopted from the simplicity panel** — it falsified two of my claims and I corrected both:

1. "A glob **silently fails** when #6448 lands" → **false**; a glob under-covers, it does not break. Wording corrected to "fails to auto-cover" (still failure class 2, still the coordinator's binding constraint).
2. "Raw-validating checks placeholder strings — **precisely** the false-green" → **too broad**; for a simple scalar interpolation, `"x"` and `${var}` are equivalent strength. Narrowed to the two places rendering provably wins: **arm selection** and **valid JSON**.
3. Literal `5/5` pinned in ACs → **computed equality**; a pinned count is the #6454 shape one layer up.
4. `hooks.json.tmpl`'s "13 real `${…}`" → **13 occurrences of 1 var**.
5. AC8's `grep`-the-script-for-absent-strings → **cut** (purity ritual; F9 tests the behavior).
6. The `cloud-init-inngest-bootstrap.test.sh` `render_ci()` refactor → **cut** (justification contradicted my own text; replaced by a one-line comment for the matrix touch).
7. ACs 16 → 10; step-ordering / scope-policing / follow-up-ceremony ACs cut or demoted to phase steps.
8. Keep the extracted script + fixture suite in the **required, path-filter-free** job — the panel independently verified this is load-bearing (`run-all.sh:9` globs `test-*.sh`; `pr-quality-guards.yml:19` runs it; `ruleset-ci-required.tf:126` pins it required).

**Adopted from the strong-model consult:**

9. **Keys from the `.tf` map, types from the body** — kills a `%{ for x in list ~}` loop-local false-red my body-scanner would have shipped, and folds the exit-4 cross-check into Terraform's own error.
10. **Ship the `if: always()` aggregator here**, defer only the ruleset flip.
11. **`jsonencode` + decode** instead of `<<EOT` stripping — *corrected*: the consult suggested one `jq -r`; testing showed console re-quotes, so **two** passes are required.

**Rejected, with evidence** — the panel's core proposal to replace the render with a `%{`-strip (Design Decision 0): it emits a 796-line document matching neither arm, never validates the **default** (`false`) production config, and cannot parse JSON templates at all. Its cost accounting also double-counts terraform, which the job already installs.

## Non-Goals (each gets a tracking issue — a deferral without one is invisible)

1. **Flipping the ruleset to make `infra-validate-required` required.** The aggregator job itself **ships here** (Phase 3) — only the `ruleset-ci-required.tf` entry + `terraform apply` defer, because that is an admin/apply action, not a code change. Shipping the aggregator now means the follow-up is a one-line ruleset edit rather than a second structural edit to the same workflow. → **file issue**
2. **N ≥ 2 bool combinatorics.** all-true/all-false covers 2 of 2^N. Complete for today's corpus (N=1, verified); a documented narrowing if that changes. → **file issue**
3. **The hardcoded stub map in `cloud-init-inngest-bootstrap.test.sh`'s AC7 leg.** Pre-existing; it will false-red that *advisory suite* when someone adds a templatefile var to `server.tf`. My draft refactored it; plan-review cut that as scope creep (my own text concedes the tripwire is "acceptable in an advisory test"). The shared script is available to it later. → **file issue**
4. **#6448** (docker-daemon.json insecure-registries drift, "fails SILENT") — explicitly out of scope. This plan is designed to *help* it, not block it: when #6448 converts `docker-daemon.json` to a `templatefile()`, discovery covers it automatically (proven by simulation, T9).
   **Hand-off note for #6448's author** (observed while verifying, not acted on): `registry-insecure-config.test.sh` greps `DJ_ZOT_IP` out of the **raw** `docker-daemon.json`. Once that file becomes a templatefile, the raw grep will read `${registry_private_ip}` rather than an IP, so that probe must move to the **rendered** doc as part of #6448. This plan does not touch that file, that probe, or `docker-daemon.json`, and `.github/scripts/validate-infra-templates.sh` is available to #6448 as the render helper. → **note on the issue**
5. **Fixing the self-referential probe** in `registry-insecure-config.test.sh` (asserts `CI_ZOT_IP == DJ_ZOT_IP` rather than against `local.registry_private_ip`, so real drift passes green). That is #6448's scope. Verified untouched and still passing here (Phase 3 do-no-harm step).
6. **#6415 / #6400** — later PRs in this session's sequence. Out of scope. #6454 is the unblocker that merges first.
7. **Changing the BEHAVIOR of any `cloud-init*.yml`, `docker-daemon.json`, or `*.tf`.** They are correct as written for this bug; the workflow was wrong. *(Clarified at /work: the draft read "Editing any `cloud-init*.yml`…", which contradicted this plan's own **Files to Edit** — that section mandates a one-line `cloud-init.yml` comment, both as documentation at the point of confusion and as the `apps/*/infra/**` touch AC10 needs to keep the matrix non-empty. The comment is inert: it adds no directive, no interpolation, and the rendered arms still pass schema. No file's rendered behavior changes.)*

## Domain Review

**Domains relevant:** none

No cross-domain implications — CI-plane gate correctness. No UI surface (Files to Create/Edit contain no `components/**`, `app/**/page.tsx`, or `app/**/layout.tsx` → the mechanical UI-surface override does not fire; Product = NONE). No regulated-data surface: no schema, migration, auth flow, API route, or `.sql`; and none of the gdpr-gate (a)-(d) expansion triggers fire (no LLM on operator data, threshold ≠ single-user incident, no cron reading learnings/specs, no new artifact-distribution surface) → Phase 2.7 skipped. No new infrastructure surface — no server, service, secret, vendor, DNS record, or persistent process; the renderer reads no credentials → Phase 2.8 skipped.

## Architecture Decision (ADR/C4)

**Not applicable — no architectural decision.** This is a bug fix to a CI gate on an existing surface. No ownership/tenancy boundary moves; no new substrate, integration, or trust boundary; no existing ADR is reversed or extended.

**C4 completeness check** (per the mandate, a "no impact" conclusion must cite what was enumerated): all three of `model.c4`, `views.c4`, `spec.c4` were considered against this change's full surface. (a) **External human actors:** none added or changed — no correspondent, reviewer, or recipient enters the picture. (b) **External systems/vendors:** none — the renderer calls no vendor API; `terraform console` runs offline in an empty dir with no provider and no credentials. (c) **Containers/data stores:** none touched — nothing is deployed, migrated, or persisted; the change lives entirely in the CI plane and alters no runtime container. (d) **Actor↔surface access relationships:** unchanged — no access path is widened, narrowed, or re-owned. A GitHub Actions job's internal validation logic is not a modeled C4 element, and no element description is falsified by this change. Would a competent engineer reading only the ADRs + C4 be *misled* about the system after this ships? **No** — the system's architecture is byte-identical; only a CI gate stops lying.

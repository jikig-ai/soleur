# Session State

## Plan Phase
- Plan file: `knowledge-base/project/plans/2026-08-11-fix-registry-zot-log-shipping-plan.md`
- Status: **recovered from partial-artifact** (planning subagent died on an API connection error
  mid-response after 78 tool uses / ~42 min; the plan body, the deepen-plan sections, and the
  five-reviewer panel dispositions were all already on disk).
- Plan artifact: `recovered` (selector=`branch` — frontmatter `branch:` matched, non-recursive over
  `plans/*.md`, so `plans/archive/` excluded by construction)

### Recovery evidence
The recovery predicate (`## Acceptance Criteria` present) held. Beyond the predicate, the three
corrections the subagent's final partial message said it was "applying" are all verifiably on disk,
so nothing was lost to the crash:

| Late correction | Finding | On disk |
|---|---|---|
| C4 edge exists at `model.c4:562` (the earlier grep was case-broken against `zotRegistry`) | A10 | 3 refs |
| ADR-178 also taken → moved to ADR-179 | A12 | 11 refs |
| Infra suites register via `.github/workflows/infra-validation.yml`, not `scripts/test-all.sh` | A11 | 5 refs |

**`plan-review` was NOT re-run.** The generic recovery arm says "continue from `/soleur:plan-review`",
but plan-review demonstrably already ran: `## Panel Findings That Changed the Architecture` carries 14
findings (A1–A14) each with a disposition, and the Overview records the plan "was revised substantially
after a five-reviewer panel". Re-running it would re-spend the operator's budget to re-derive findings
already incorporated (token-discipline #4: re-run a suite only when its inputs changed). Recorded here
rather than left implicit, since it is a deviation from the literal recovery text.

**Inherited-measurement caveat (token-discipline #4, resume inversion).** Every live measurement in
this plan was self-pulled by the crashed subagent ~40 min before this entry. The plan does not rely on
that: Phase 0.1 mandates re-probing the delivery window (`boot_id`, `zot_uptime_s`, `pcent`) at
implementation time rather than inheriting it, and AC 18 mandates re-deriving the ADR ordinal
immediately before merge. Both re-probes are owed by `/work`, not satisfied by this file.

### Errors
- Planning subagent terminated early: `API Error: Connection lost mid-response` (subagent tokens
  406,552; 78 tool uses; 2,524,643 ms). No Session Summary was emitted — recovered from on-disk
  artifacts per the `plan-artifact-recovery` block. Recovery ran **once**; no re-invocation of
  `soleur:plan` was needed.
- Scope check clean: `git status` showed the plan file as the only change, so the subagent did not
  breach its plan-only mandate.

### Decisions
- **Shape change from the issue's literal framing.** The issue says "follow the existing Vector
  source/allowlist pattern"; the registry host runs **no Vector agent**, so there is no allowlist entry
  to add. The deliverable is a purpose-built journald→ingest shipper (ADR-179), adopting Vector's
  *discipline* (exact-value field match, explicit quota budget, redaction before egress) but not its
  agent.
- **The binding reason against the shared Vector config is payload destruction, not credentials.**
  `vector.toml:298` deletes any top-level `message` key as an Art-9 user-content key, and zerolog's
  log text *is* a top-level `message` — a Vector-shipped zot line would arrive with its message
  deleted. The earlier pepper/isolation-guard argument is explicitly retracted as false.
- **This is a shipping problem, not an instrumentation problem.** The zot container already runs with
  `--log-driver journald` under the container name `zot`, so the lines are already on the host.
- **The verification gate asserts a POSITIVE, host-isolated envelope**, not a negation of the
  heartbeat prefix (which would be fail-open and would auto-PASS on exactly today's production state).
  The issue's suggested tokens (`routes.go`, `blobs/uploads`) are rejected as generic — all hosts
  multiplex into Logs source 2457081.
- **Ships inert-until-provisioned, and says so.** The registry host is cloud-init-only; delivery rides
  the pending step-6 `registry-host-replace` on the open zot-pin ordered path. Liveness is owned by a
  follow-through probe on a **dedicated tracker** (never the issue the PR closes, where the sweeper
  would make it a permanent silent no-op).
- Zero Terraform changes — a deliberate risk reduction that keeps the change clear of the
  untargeted-apply hazard on `hcloud_server.registry`.

### Components Invoked
- `soleur:plan` (inside the crashed planning subagent) — completed
- `soleur:deepen-plan` (same subagent) — completed; research fan-out, premise validation,
  User-Brand Impact (Phase 4.6), Encryption Posture
- `soleur:plan-review` (same subagent) — completed; five-reviewer panel, 14 findings A1–A14
- `scripts/betterstack-query.sh` via `doppler run -p soleur -c prd_terraform` — falsification table
  re-measured independently (`hr-no-dashboard-eyeball-pull-data-yourself`)

## Work Phase
- Status: complete
- Commits: 8 on `feat-one-shot-7440-zot-log-shipping`

### Phase 0 measurements — taken, not inherited
Every one was re-derived at implementation time rather than read off the plan.

| Precondition | Method | Result |
|---|---|---|
| 0.1 delivery window (H0) | live `SOLEUR_ZOT_DISK` query | **CLEARED** — `boot_id=bc135d5b-…` unchanged, `pcent=8`, `zot_uptime_s` 40317→43017, `resize_ok=true` |
| 0.3 zot's RAW log shape | **ran the pinned image locally** (digest matches the live host's `zot_image_digest`) | quoted zerolog JSON, confirming finding A2 |
| Authorization header shape | 3 probes (basic-auth / Bearer / Basic) against that container | `"Authorization":["******"]` — zot masks it ITSELF; literal secret appeared **0 times**. A7 confirmed by measurement |
| Non-Authorization headers | same | `"X-Custom":["plainvalue"]` — logged VERBATIM, so the backstop is anchored on header-object shape, not one header's known masking |
| journald field match | ran a container named `zot` with `--log-driver journald` | `journalctl CONTAINER_NAME=zot` **matches** — the Phase 1.3 load-bearing assertion |
| Feedback loop | `systemd-cat -t zot-log-shipper` | a shipper-tagged entry carries **no** `CONTAINER_NAME`; the match excludes it (0 hits) → structurally impossible |
| Cursor mechanics | `--output=json` / `--no-tail --after-cursor` | `__CURSOR` present; resume parses |
| 0.6 strip precedent | read `zot-liveness-heartbeat.test.sh` | confirmed it does **NOT** apply the rationale strip; mine does |

### Verification
| Gate | Result |
|---|---|
| `zot-log-shipper.test.sh` | **103/103** + 11-mutant battery (all RED, baseline GREEN) |
| `test-zot-log-channel-probe.sh` | **55/55** + 7-mutant battery (all RED) |
| `run-registered-suites.sh` (authoritative infra) | **94/94, 0 RED, 0 unaccounted** — includes my suite by name |
| `scripts/test-all.sh` | `288/290`; epilogue confirms `apps/web-platform/infra/ IS covered above` |
| render + `cloud-init schema` | 8/8 files green |
| `c4-code-syntax` + `c4-render` | 23/23 |
| userdata budget | `stored_bytes=12004 / cap=32768 / headroom=20764` |
| `systemd-analyze verify` on the unit | rc=0 |
| GDPR gate | canonical path regex matches **0** changed paths → skips |

### Session errors
1. **A `%%` that is not a Terraform escape.** Wrote `CPUQuota=20%%` reasoning by analogy from `$${`
   and `%%{`. Terraform's directive escape is `%%{` specifically — a bare `%%` is literal, so it
   would have rendered as `20%%` and systemd would have rejected it, on the host with no in-place
   fix path. My `grep -qE 'CPUQuota='` existence check passed on the broken value. **Fix:** assert
   the VALUE SHAPE (`CPUQuota=[0-9]+%$`), forbid `%%` in the unit block, and run
   `systemd-analyze verify` on the extracted unit.
2. **An assertion stricter than the linter it mirrored.** The `${VAR:?}` check false-FAILED on the
   probe's own header prose documenting the ban. The real linter greps `-n` on the raw file and
   THEN drops full-line-comment hits. **Fix:** mirror the production checker's two-stage predicate
   and also delegate to the linter itself.
3. **A regex that could not match its target.** The leak arm's Doppler pattern used a dot-free
   trailing class, so it stopped at the `<config>` segment of `dp.st.<config>.<random>` and could
   never fire. Caught only by fixture C8c.
4. **Quantified over the wrong ref set.** First ADR-ordinal probe covered `refs/remotes/origin`
   only (65 refs) and reported 178 free. Over all **2,986** refs it is claimed twice, on
   **local-only branches invisible to origin**. The plan was right and my narrower instrument was
   wrong. **Fix:** the ADR records the command and the blind spot.
5. **`pgrep -f 'test-all.sh'` matched my own command line and killed my shell** — the exact trap
   `hr-never-run-commands-with-unbounded-output`'s neighbour documents. **Fix:** bracket class
   (`[t]est-all\.sh`).
6. **Included a stray `git stash list`** in a diagnostic, denied by the guardrail hook
   (`hr-never-git-stash-in-worktrees`). Harmless but avoidable.
7. **Ran a whole-repo linter that is enforced per-staged-file.** `lint-infra-no-human-steps.py`
   reported 534 findings; identical on the merge-base tree, none in my files, and lefthook scopes
   it to `{staged_files}` where it passes. Wrong instrument, not a regression.

### Pre-existing, confirmed, not fixed here
`plugins/soleur/test/preflight-check10-suite-integrity.test.sh` reports `10 passed, 2 failed` on a
green tree. Its summary parser anchors `^[[:space:]]*([0-9]+) pass`, but bun emits
`\e[0m\e[32m 122 pass\e[0m` — the line starts with ESC. Measured: the anchored pattern matches 0 on
a coloured line and 1 on a plain one, while the unanchored `expect() calls` pattern matches, which
is exactly the `expect=514 / pass=0` asymmetry. **Reproduces identically on the merge-base tree.**
Filed as #7466, including that its `n_fail` arm reports `[ok]` on an unmeasured count (fail-open).

### Net issue flow
**Closing 1 / filing 3 / net +2.** #7455 (probe tracker — cannot be consolidated; the sweeper needs
its own open host), #7456 (three deferred items consolidated into one tracker), #7466 (discovered
defect in a different subsystem — the gate requires it stay separate).

The `code-simplicity-reviewer` CONCUR co-sign that normally gates a `deferred-scope-out` filing was
**not run**: this session is configured not to spawn agents. The cost-of-filing test was applied
directly instead, and all three filings are structurally un-inlineable.

## Review Phase — DEGRADED (0 of 12 agents)

**Status: BLOCKED on an operator decision. The PR is deliberately left in DRAFT.**

Change classified **`code`** (14 files, +3337/−5, `.sh` + `.ts` present) → 8 always-on agents plus
`test-design-reviewer`, `user-impact-reviewer`, `observability-coverage-reviewer` and `semgrep-sast`
= **12 expected**. **Zero were spawned** — this session is configured not to use the Agent tool
(review Gate 2a: "spawning unavailable or unauthorized"), so the sanctioned inline degraded path was
run instead.

Evidence trailer emitted with honest coverage: `Reviewed-Coverage: inline-fallback 0/12 agents`,
all twelve named in `--agents-missing`. A full-strength trailer would have been worse than none,
because `/ship` reads that field as a boolean.

### What the degraded pass DID cover
- `shellcheck` on all three authored bash files **and** on the extracted post-strip shipper (the
  bytes the host actually runs) — clean; five `SC2034`s on the tests, three false positives
  (read inside `eval`'d assert strings), two real and fixed.
- Deterministic gates: `check-adr-ordinals`, `lint-orphan-test-suites`,
  `lint-followthrough-varq-ban`, `followthrough-exec-bit`, `lint-infra-no-human-steps` (scoped as
  lefthook invokes it), render + `cloud-init schema`, userdata budget, `systemd-analyze verify`.
- Inline reasoning over security / architecture / resource / simplicity, plus three findings fixed
  (see the `review:` commit).

### What it did NOT cover, and why that matters here
`security-sentinel`, `user-impact-reviewer` and `observability-coverage-reviewer` are exactly the
lenses this diff most needs: it adds the registry host's **first `Restart=always` unit** on the
**sole container-image pull path**, ships log content to a third-party warehouse, and the plan
declares `brand_survival_threshold: single-user incident`. Gate 2a item 4 forbids marking a PR ready
at that threshold with zero agents, so I did not.

**Remaining: re-run `/review` with the panel** (needs agent spawning authorized), then `/compound`
→ `/ship`. Do NOT read this as "review passed" — it is a measured 0/12.

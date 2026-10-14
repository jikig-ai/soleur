# Decision challenges — feat-one-shot-6604-workspaces-plaintext-wipe

Plan: `knowledge-base/project/plans/2026-09-28-feat-workspaces-plaintext-volume-wipe-plan.md`.
Headless plan run: each Taste / User-Challenge finding is recorded here instead of being asked.

## User-Challenge (sequencing): Terraform convergence and the ADR flip land in a second PR, after the dispatch

**Finding.** The brief asks for one merged PR, then the wipe, then closing #6604/#6588, and lists the
`for_each` narrowing and the ADR-119 flip in the same scope. Terraform (reproduced on 1.10.5) will not
accept the narrowing before the volume is deleted and its state forgotten, and the soak sweeper closes
#6604 the moment ADR-119 reads `accepted`.

**Chosen.** PR A (the mode) merges first; the dispatch runs on the operator's go-ahead; PR B (the
narrowing, ledger, ADR flip, legal-register sweep) follows the same day. The brief's own words ("after
the API delete") already point this way; this records the second PR explicitly.

**Re-evaluate when:** never for this volume; a future retirement can pre-plan the same two-PR shape.

## Taste (plan-review, DHH vs code-simplicity/CTO): pause the push-apply workflows instead of a create-guard

**Finding.** Between the delete and PR B, every push apply would plan `+create` of a fresh plaintext
volume. A new destroy-guard surface would reverse #6919/T55 and needs an edit to a file a few hundred
bytes under its size cap.

**Chosen.** `gh workflow disable` both push-apply workflows for the window (named in the go-ahead),
re-enable and `manual-rerun` after PR B. Cost: infra merges in the window stay unapplied until the
rerun, and the dispatched apply arms are unavailable. The `manual-rerun` arm re-applies only
`apply-web-platform-infra.yml`'s targets: a merge to `apply-deploy-pipeline-fix.yml`'s `paths:` in the
window is **not** covered by it and needs its own dispatch after PR B (runbook step h).

**Re-evaluate when:** the window cannot be kept to hours, or a second retirement needs the same window.

## Taste (CTO devex): who clicks the environment approval

**Finding.** The environment's only reviewer is the operator's GitHub user, which the agent's `gh` also
authenticates as; the git-data runbook has agents approve via `pending_deployments`.

**Chosen (default).** The operator clicks it, or explicitly delegates it in the go-ahead; a delegated
agent checks the preflight banner's id, name, server and `api_state` against the pin first.

**Re-evaluate when:** the environment gains a second reviewer or a self-review restriction.

## Taste (CTO devex vs DHH/simplicity): duplicate the SSH delivery block rather than extract it

**Finding.** The `wipe` job copies `cutover`'s bridge/bundle/`.env`/run block, so the rehearsal does not
exercise the copy.

**Chosen.** Duplicate; keep the freeze path byte-stable; state the gap in the ADR addendum.

**Re-evaluate when:** a third job needs the same delivery, or the freeze path is retired.

## Taste (DHH): destruction record as a PR-A template, C4 edge in PR A

**Finding.** Both could be written once, in PR B.

**Chosen.** Keep both in PR A: the CLO's Art. 5(2) precedent makes the template a precondition of the
act, and the C4 edge describes a capability PR A ships.

**Re-evaluate when:** no.

## Taste (CTO devex): the `wipe` job remains after PR B

**Finding.** After PR B the mode has no target on web-1.

**Chosen.** PR B deletes the forget workflow (its addresses no longer exist) but keeps the `wipe` job
and script mode: its refusals protect the rollback path, and #6931 may retire web-2's plaintext volume
the same way.

**Re-evaluate when:** #6931 decides web-2's path.

## Implementation forks decided in /work (2026-09-28, recorded rather than asked)

- **`.env` delivery: one named `printf` per line, not a heredoc.** `workspaces-luks-header.test.sh` H14
  forbids `DOPPLER_TOKEN=` followed by anything but `%` (the argv-leak guard) and H16 pins
  `WORKSPACES_LUKS_DEV=%s`; a heredoc line `DOPPLER_TOKEN=${…}` trips H14. One `printf 'KEY=%s\n'` per
  key gives the plan's property (no multi-`%s` format that repeats when the argument count outgrows it)
  and keeps both security guards unchanged. The duplicate-key refusal runs **runner-side**, over the
  exact body about to be delivered (the step is the only author of that body), rather than inside the
  heavily-quoted remote `bash -c`. Re-evaluate if a second author of the `.env` appears.
- **Step bodies are extracted with PyYAML, not `yq`.** `yq` is not installed on this host, and the
  existing `workspaces-luks-cutover-workflow.test.sh` already parses with PyYAML (installing it when
  absent). Same property: each body is selected by job + step `id`, exactly-one asserted, and executed
  under `bash --noprofile --norc -eo pipefail`.
- **`arm_dead_man` gets no plaintext-wiped refusal.** Measured unreachable on a cut-over host: the main
  body runs `prepare_staging_target` (which dies `staging_already_cutover` when `$MOUNT` is the mapper)
  before `arm_dead_man`, and the wipe requires `$MOUNT` == mapper (W2). The premise is pinned by
  `workspaces-luks-wipe.test.sh` S6 and noted in `assert_rollback_not_post_cutover`.
- **Four reason slugs beyond the plan's table**, each where the plan named a check without a slug or a
  gap the rehearsal should catch: `wipe_blkid_probe_failed` (blkid rc ∉ {0,2,8}, the plan's "blkid rc 4
  with a marker" census row), `wipe_target_serial_mismatch` (W6 `ID_SERIAL`, Guard 1 #9c),
  `wipe_signature_survived` (W12), and `wipe_io_cap_unavailable` — a W8 `systemd-run --scope -p
  IOReadBandwidthMax=… true` probe, so a host whose cgroup cannot take the 150M cap refuses in the
  REHEARSAL instead of failing at W10 after `PLAINTEXT_WIPE_BEGUN` is persisted.
- **W6b also requires `ActiveState=active`.** Measured locally (systemd 258): `systemctl show` of a
  device unit that does not exist reads `LoadState=loaded`, `ActiveState=inactive`. So "loaded" alone
  cannot catch a ghost unit; every matched unit must be loaded AND active, and zero matched units is a
  refusal (nothing proven).
- **W5 downloads with `aws s3api get-object`, not `aws s3 cp`.** Same GET; the `s3 cp <dest>` form added
  a relative-operand site to the fixture-relative ratchet (`fixture-relative-assert.test.sh`), the
  `get-object` form does not, and it matches the escrow's existing `s3api head-object` read-back.
- **The `wipe` job derives `WORKSPACES_LUKS_DEV` from the constant `LUKS_VOLUME_ID` (106443278)**, not
  from a name lookup like the `cutover` job — binding W3 to the physical id the presence proof also
  checks.
- **W6's realpath-inequality check is an equivalent mutant of its major:minor check** (a device reached
  by the same path has the same major:minor), so no row can red on its removal alone. Kept as
  belt-and-braces; the major:minor check and Guard 1 #1/#2/#9 red on every real mutant.
- **The `wipe` API step re-runs the presence proof after EVERY `DELETE`** (not only a `404`), giving a
  fixed three-read shape the suite pins; a `404` is still accepted only with that proof green.
- **`emit_wipe` accepts digits in keys** (`hdr_sha256` rides the rehearsal row). The two rows the job
  parses (`wiped`, `already_wiped_detached`) carry `[a-z_]` keys only, matching the plan's regex.
- **The loopback zero cases stub W6b**; LW6 runs the REAL W6b against the runner's systemd separately,
  so the real-device zero evidence is not coupled to the runner's device-unit graph.
- **The Observability-token census finds the plan by name under `knowledge-base/project/plans/`**
  (including `archive/`), so archiving the plan after ship does not break it; the durable census is the
  runbook verdict table (C2), which must name every slug the script raises.

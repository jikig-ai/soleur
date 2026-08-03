# Phase 0 probe results — measured 2026-08-03

Probes only, no edits. Ephemeral config-scoped service tokens were minted with `--max-age 10m`,
probed, and **revoked by slug in-band**; a sweep across all 13 configs confirms zero leftovers.
No token value was ever printed — values went to `umask 077` scratch files and were shredded.

## P0.1 — `.key` and `access = "read"` — PASS

`doppler_service_token` siblings (`kb-drift.tf:102`, `web-probe-read-token.tf:33`) use
`access = "read"` and expose `.key`. `.api_key` belongs only to `doppler_service_account_token`,
the resource being retired. Plan §D1 is correct.

## P0.2 — `terraform validate` — deferred to Phase 1

Cannot run until `token-drift-read-tokens.tf` exists. Discharged in task 1.7.

## P0.3.1 — self-identification field — PASS, but NOT via `doppler me`

| Probe | Result | Verdict |
|---|---|---|
| `doppler me --json` | `{"type":"service_token","name":"p034-probe-prd","slug":…}` — `name` is the value **the caller supplied at create time** | **DISQUALIFIED.** Plan's hard constraint: the field must be one Doppler DERIVES from the binding, never one echoing the supplied `name`. A probe asserting a string Terraform put there is vacuous. |
| `doppler configs -p soleur --json` | root-bound → `[{"name":"prd","environment":"prd","root":true}]`; branch-bound → `[{"name":"prd_kb_drift_walker","environment":"prd","root":false}]` | **ADMITTED.** Exactly one entry; `name` is derived from the binding, not supplied. |

The admitted call is the one already at `check-cloudflare-token-drift.sh:479-480` — FR6's "retained
with a new meaning" lands on a call that already exists.

## P0.3.2 — wrong-config behaviour — **FALSIFIES AN INHERITED PREMISE**

A config-scoped token **ERRORS** on a wrong `-c`. It does **not** silently serve its bound config.

```
token bound to prd (ROOT)
  -c prd            -> rc=0 OK keys=129
  -c prd_terraform  -> rc=1 ERROR: This token does not have access to requested config 'prd_terraform'
  -c prd_ghcr       -> rc=1 ERROR: …
  -c dev            -> rc=1 ERROR: …
  -c ci             -> rc=1 ERROR: …
  -c cli            -> rc=1 ERROR: …
token bound to prd_kb_drift_walker (BRANCH)
  -c prd_kb_drift_walker -> rc=0 OK keys=130
  -c prd                 -> rc=1 ERROR: …   <- a branch token cannot read its own root
  -c prd_terraform       -> rc=1 ERROR: …
  -c dev                 -> rc=1 ERROR: …
  -c <omitted>           -> serves the bound config
```

This contradicts the R8-cited learning
`2026-03-29-doppler-service-token-config-scope-mismatch.md` ("`-c`/`DOPPLER_CONFIG` are ignored")
for the `secrets` verb in the pinned CLI v3.75.3. The `configs list` verb still behaves as
`kb-drift.tf:94-96` records — a list *silently scoped to the caller* — so the two verbs differ, and
the learning is right about `configs list` and wrong about `secrets`.

**Consequences:**

1. **FR7 resolves: `-p`/`-c` STAY on argv.** The detector's comment that *"the config is named
   EXPLICITLY on every read"* is a TRUE guarantee, not an inverted one. Test P3 stays as-is.
2. **The read path IS the binding assertion.** Under the producible defect (`config = "prd"` for
   all 13 instead of `each.key`), the read loop issues `-c ci`, `-c dev`, … against prd-bound
   tokens and every one **errors**. 12 configs count UNREAD, `configs` drops to 1, and the run
   grades `1/13 degraded` — exactly the outcome control C-c was designed to produce, obtained at
   zero extra network cost.

## P0.3.3 — branch-scoped confirmation — PASS

`prd_kb_drift_walker` self-identifies as itself and is denied `prd`, `prd_terraform`, `dev`.
Confirmation, not discovery, per R5.

## P0.3.4 — non-empty identity on the census-vacuous configs — PASS

`cli`-bound token self-identifies `[{"name":"cli","root":true}]`, `--only-names` → 3 keys.
Non-empty identity; ADR-164's "vacuous" census was about *token-shaped* keys, not identity.

## P0.3.5 — decision gate — C-c ADMITTED, and implemented as the read path

The plan's stated gate is *"if 0.3.1 or 0.3.3 fails, C-c is DROPPED."* **Both passed**, so C-c is
admitted. But P0.3.2 measured something the plan did not anticipate: with `-c` retained, the
`--only-names` read at `:536` **already** fails closed on a mis-binding. A separate
self-identification probe would issue 13 extra API calls per run to re-derive a property the very
next call enforces.

**Adopted:** C-c's *diagnostic* value at C-a's cost — the read path stays the control, and the
detector discriminates the access-denied error shape from a generic read failure, emitting the
three distinct causes FR6c requires:

| Condition | Annotation | Coverage effect |
|---|---|---|
| read fails with `does not have access to requested config` | `::error::token_drift_config_binding_mismatch` | config counted UNREAD |
| read fails any other non-zero way | `::error::token_drift_identify_unreachable` | config counted UNREAD |
| read succeeds but yields no parseable key set | `::error::token_drift_identify_empty` | config counted UNREAD |

This satisfies FR6c's substance — mismatch counts UNREAD (which is what gives it a channel), a
named annotation, and three distinct causes rather than collapsing "the API 5xx'd" into "this
credential is mis-bound" — without the 13-call probe. **Deviation from the plan's literal FR6c is
deliberate and recorded here**; it is a cheaper implementation of the same control, not a dropped
one. C-a (static, pre-merge) and C-d (`sort -u`) are unaffected and both still ship.

## P0.4 — inventory vs live Doppler — PASS

```
doppler configs -p soleur --json | jq -r '.[].name' | sort   -> 13 names
grep -E '^[a-z0-9_]+$' doppler-config-inventory.txt | sort -u -> 13 names
diff -> IDENTICAL
```

The merge-triggered apply cannot fail on a `for_each` key naming a config that does not exist —
the only pre-merge control on the new apply coupling, since `infra-validation.yml`'s plan job is
`continue-on-error: true`.

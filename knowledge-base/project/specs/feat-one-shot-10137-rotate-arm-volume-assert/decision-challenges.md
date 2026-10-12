# Decision challenges - feat-one-shot-10137-rotate-arm-volume-assert

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Extract the whole post-apply block (volume loop + NIC create + both attachment creates) vs only the volume loop | technical | Ruled by CTO agent, 2026-10-12: extract the whole block - extracting only the loop leaves the empty `resource_changes` hole closed only by assertions that stay untestable inline. |
| Function takes the gate mode (`replace`/`rotate`), not `apply_target`; the step derives the mode from `APPLY_TARGET` through a lib helper | technical | Ruled by CTO agent, 2026-10-12: take mode, keep a fail-closed `*)` arm - a second inline target-to-mode map is a second source of truth that can drift from the plan step's GATE_MODE. |
| Rotate mode: skip-only for `hcloud_volume.git_data_luks`, or also assert delete+create post-apply | technical | Ruled by CTO agent, 2026-10-12: skip-only, built structurally as a per-mode preserved-volume set - the pre-apply gate already requires `luks_volume_rotated == 1` on the same saved plan, and a second assert adds a post-apply false-failure surface. |
| Unknown or empty mode | technical | Ruled by CTO agent, 2026-10-12: fail closed with a distinct wiring-fault message - defaulting to replace turns a wiring fault into a false failure, defaulting to rotate into a false pass on the LUKS volume. A fourth test row pins it. |
| Empty `resource_changes` must not pass | technical | Ruled by CTO agent, 2026-10-12: the positive NIC-create and attachment-create assertions carry it (readable/classifiable alone pass `[]`); the test row asserts the message names the missing create, plus a `null`/absent variant. Do not require the preserved volumes to be present: they are absent by omission. |
| ADR / C4 | technical | No architectural decision: a bug fix on an existing assertion; no ADR or C4 edit. ADR-239 amendment already records #10137 and is not edited (docs rule). |

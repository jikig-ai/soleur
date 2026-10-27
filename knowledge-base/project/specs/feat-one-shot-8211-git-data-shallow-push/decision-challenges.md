# Decision Challenges — feat-one-shot-8211-git-data-shallow-push

## Decision Classes

| Item | Class | Ruling |
|------|-------|--------|
| Wrapper exec shape: keep the generic `exec git -c "core.hooksPath=…" "${verb#git-}" "$repo_real"` line verbatim and add a receive-pack-only conditional branch carrying `-c receive.shallowUpdate=true` | technical | Ruled by planner, 2026-10-27: the generic line is exact-match pinned by the production fence probe (`git-data-cutover.sh:689` `pin_ex`, `grep -qxF` on the live host) and by T11/P2 parity — removing it turns every fence probe into `transport_pin_mismatch`. The ruling said "upload-pack exec line stays unchanged"; with one shared exec line the only argv-faithful reading is a conditional branch. |
| Extend the host fence probe (`pin_ex` → also assert the shallow flag) | technical | Ruled by planner, 2026-10-27: declined — out of prescribed scope. The generic line survives so the probe stays green unchanged; R-PUSH-SHALLOW covers the flag end-to-end; widening the probe is a separate posture decision parked with the #8211 security-sentinel note. |
| Brand-survival threshold / CPO sign-off | technical | pending - assumed: `single-user incident` declared (plan frontmatter `requires_cpo_signoff: true` set per the threshold rule); the CPO consult could not be spawned in this harness — the parent's technical-ruling gate converts this row. |
| `lane:` value | technical | pending - assumed: `cross-domain` — no `spec.md` exists for this branch, so the fail-closed default applies (plan Phase "Save Tasks" rule: absent or invalid lane → cross-domain). |

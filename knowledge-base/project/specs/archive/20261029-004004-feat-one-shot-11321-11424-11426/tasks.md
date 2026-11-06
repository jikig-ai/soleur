# Tasks — feat-one-shot-11321-11424-11426

Derived from `knowledge-base/project/plans/2026-10-28-feat-breakglass-mirror-image-tag-fix-plan.md`.
PR #11442 (draft). Issues: #11424 (break-glass mirror skill), #11426 + #9669 (image_tag vv* defect), #11321 (eMudhra census close-out, read-only).

## Phase 1 — Resolver normalization (#11426, #9669)

- [ ] 1.1 Edit `apps/web-platform/infra/scripts/resolve-web1-known-good-tag.sh`: after input acquisition add `RUNNING_VERSION="${RUNNING_VERSION#v}"` (before `TARGET_TAG="v${RUNNING_VERSION}"`); update the contract comment to "strict three-part semver, bare or v-prefixed — normalized to bare before the prepend". Strict regex unchanged.
- [ ] 1.2 Edit `apps/web-platform/infra/resolve-web1-known-good-tag.test.sh`: rewrite fixture (g) to `run_arg "v1.2.3"` → rc=0, OUT=v1.2.3; add (g2) `run_arg "vv1.2.3"` → rc!=0, empty OUT; add (g3) `run_stdin "v4.5.6"` → v4.5.6.
- [ ] 1.3 Wording-only edits in `.github/workflows/apply-web-platform-infra.yml`: drop "bare" from the two `image_tag` validation messages (~:4731, ~:5207); one-line "either spelling; resolver canonicalizes" comment at both resolve steps. NO call-site strip (`IMAGE_TAG_INPUT#v` must not appear).
- [ ] 1.4 Verify: `bash apps/web-platform/infra/resolve-web1-known-good-tag.test.sh` → `0 failed`; `git grep -n 'IMAGE_TAG_INPUT#v' -- .github/workflows/` → empty.

## Phase 2 — registry-breakglass-mirror skill doc (#11424)

- [ ] 2.1 Create `plugins/soleur/skills/registry-breakglass-mirror/SKILL.md` — frontmatter `name: registry-breakglass-mirror`, third-person `description:` ≤25 words (budget 2406/2436). Body: when to invoke (tunnel/bridge down, zot must be re-materialized); connectivity matrix (primary ssh.soleur.ai; fallback direct SSH to host public IP as deploy, gated on `soleur:admin-ip-refresh`); credential sourcing (DEPLOY_SSH_PRIVATE_KEY from soleur/prd_terraform; ZOT_PUSH_USER/ZOT_PUSH_TOKEN from soleur/prd; operator-supplied GHCR_TOKEN read:packages PAT — never GHCR_READ_TOKEN, revoked by design); procedure fetch→assemble→push→verify; the never-upload-through-a-forwarded-connection rule; cosign signature obligation (sha256-<hex>.sig ref); failure vocabulary pointer to scripts/zot-mirror-diagnosis.sh; parameterized MIRROR_HOST (default web-1, any 10.0.1.0/24 member).
- [ ] 2.2 Edit `plugins/soleur/README.md`: Skills count 104→105; add skills-table row.

## Phase 3 — mirror script (#11424)

- [ ] 3.1 Create `plugins/soleur/skills/registry-breakglass-mirror/scripts/mirror-ghcr-to-zot.sh` — runs ON the datacenter host; args repo+refs (`repo@sha256:`/`repo:tag`); env GHCR_TOKEN, ZOT_PUSH_USER, ZOT_PUSH_TOKEN; `--dry-run`; `set -euo pipefail`. GHCR token exchange; `curl --resolve` manifest+blob GETs for ghcr.io AND pkg-containers.githubusercontent.com (307 redirect target); assemble OCI layout; `crane push <layout> 10.0.1.30:5000/...` (--insecure); mirror the signature ref; per-ref `crane validate --remote` read-back (never crane digest alone); secrets via env/stdin never argv; fetch pinned crane release (name+sha256) if absent; no /etc/hosts writes; no -k.
- [ ] 3.2 Verify: `bash -n` clean; `--dry-run` exits 0 and pushes nothing; greps per plan AC5.

## Phase 4 — ADR-096 amendment + C4 descriptions

- [ ] 4.1 Amend `knowledge-base/engineering/architecture/decisions/ADR-096-migrate-container-registry-ghcr-to-self-hosted-zot.md` — dated 2026-10-28 amendment: sanctioned `--resolve` exception to the #9169 hosts-file deny + datacenter-first doctrine (never push blobs through a forwarded registry connection).
- [ ] 4.2 Edit `knowledge-base/engineering/architecture/diagrams/model.c4` — three description updates (ghcr node, #8036 deletion comment :801, hetzner->zotRegistry pull edge :800). Run `apps/web-platform/test/c4-code-syntax.test.ts` + `c4-render.test.ts`.

## Phase 5 — #11321 evidence + close (read-only)

- [ ] 5.1 `doppler secrets get CF_API_TOKEN` / `CF_ACCOUNT_ID` (-p soleur -c prd_terraform) → resolve tunnel `soleur-web-platform` → GET `/cfd_tunnel/<id>/connections` → classify_conn_versions: every live conn ≥ 2026.10.2.
- [ ] 5.2 `gh run list -w scheduled-inngest-health.yml -L 3` → `gh run view --log | grep SOLEUR_ORIGIN_HOST_CHURN` → `version_verdict=versions_ok`.
- [ ] 5.3 versions_ok → evidence comment on #11321 (output + run URL + refs PR #11442) + `gh issue close 11321`. below_floor/version_unreadable → post failing evidence, leave OPEN, escalate (no production mutation authorized).

## Phase 6 — PR body + ship

- [ ] 6.1 PR #11442 body first line = the merge-blast answer (push-triggered auto-apply fires on infra/** but resolves no resource changes from this diff — verified no .tf references the edited files). `Closes #11424`, `Closes #11426`, `Closes #9669`, `Refs #11321`.

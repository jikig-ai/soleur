// Rendered-`user_data` size guard for the Hetzner web + git-data hosts (#5921).
//
// Hetzner caps cloud-init `user_data` at 32,768 bytes. Before this guard the web host's
// rendered `user_data` was ~282 KB (~8.6x over) because server.tf inlined 22 scripts +
// hooks.json as base64 into the templatefile map. The fix bakes those (plus the journald
// drop-in) into the app image and extracts them at boot, and moves the install ceremony into
// a baked `soleur-host-bootstrap.sh`. This test models the rendered size from the SAME inputs
// terraform uses (template text + base64-of-file sources) and fails if the WEB host exceeds
// the sub-cap budget. It also structurally asserts the extraction contract (AC3/AC4/AC5/AC6/
// AC8) across the cloud-init launcher AND the baked bootstrap, and the Dockerfile<->server.tf
// baked-set parity.
//
// NOT byte-exact: base64 of variable-length secrets is modeled with fixed placeholders, so
// AC11's live `terraform plan` remains the byte-exact source of truth. This test catches the
// gross re-inlining regression class (a script/hooks/config blob re-entering user_data),
// which is what balloons the size past the cap.
//
// git-data (#5927, resolved): the git-data host is a NO-DOCKER host, so #5921's bake-and-extract
// mechanism does not apply. After #5918 (LUKS/transport/remove/provision) its RAW user_data is
// ~41.7 KB — OVER the Hetzner cap. The fix wraps the whole render in Terraform's base64gzip()
// (git-data.tf), which cloud-init auto-decompresses; the base64gzip OUTPUT (~21.9 KB) is what
// Hetzner stores against the cap — UNDER it with ~10 KB headroom. This test now models that
// base64gzip'd size and asserts it stays under a sub-cap budget. CRITICAL: the gzip model reads
// the REAL script bytes for the 5 base64encode(file()) args — gzipping the "x".repeat(N)
// placeholder render collapses ~1000:1 and would make the budget non-discriminating (a re-inlined
// script would gzip to near-nothing and never trip it).

import { test, expect, describe } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { gzipSync } from "node:zlib";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const INFRA = join(REPO_ROOT, "apps", "web-platform", "infra");
const DOCKERFILE = join(REPO_ROOT, "apps", "web-platform", "Dockerfile");

// Hetzner hard cap; we enforce a sub-cap budget on WEB so a partial re-inlining still fails
// CI with headroom (measured web ~30,800 B as of #6055 — organic growth from ~29,256 B plus the
// char-device sweep sudoers grant). The budget stays ~1,268 B under the hard cap, so a re-inlining
// regression (KB-scale — the failure mode this guards) still trips it. NOTE: web user_data uses
// the #5921 bake-and-extract approach (not git-data's base64gzip); as it keeps growing toward the
// cap, a future base64gzip wrap (like #5927 did for git-data) will be needed — track before the
// next multi-KB cloud-init addition.
const HETZNER_CAP = 32_768;
// Web host base64gzip'd budget (#6090). server.tf wraps the web render in base64gzip() (the
// git-data #5927 precedent, ADR-080 amended for the web host) because the RAW render reached the
// old 31,500 B sub-cap organically and #6090's fresh-boot observability additions (readiness
// gates + emit call-sites that must live IN cloud-init, post-install) pushed it over. We model the
// base64gzip OUTPUT (what Hetzner stores against the cap). Was ~15,064 B / 18,000 B budget. Two
// legitimate arcs grew it: #6090's fresh-boot observability (readiness gates, per-stage emit
// call-sites, the ghcr_login baked-cred + hardened doppler fallback) and #6122's registry-migration
// inline logic (the seed-block zot login + /run/soleur-image-ref resolution + the inngest IREF — all
// MUST live in cloud-init since the seed pull runs pre-bootstrap, so a baked helper can't cover it).
// Merged render ~19.3 KB. Re-baselined to 21,500 B (#6090 recurrence, §1A): the deploy-path
// auth_denied fix adds a fail-open Doppler re-fetch+retry to the seed-block ghcr_login on a
// baked-login FAILURE (not only EMPTY). Like the original ghcr_login baked-cred fallback, this
// MUST live inline in cloud-init (the seed pull runs pre-bootstrap, so a baked helper can't cover
// it), so baking-instead-of-inline is not available here — the sanctioned path is a modest
// re-baseline. Measured render ~21.06 KB; 21,500 B keeps a KB-scale re-inlining tripwire (a
// re-inlined ~1.5+ KB blob trips it) and ~11 KB below HETZNER_CAP. When this climbs further,
// prefer baking new host logic over inline cloud-init (the #5921 pattern) before raising again.
// FLOOR is non-vacuity: a broken model gzipping near-nothing fails loudly. #5921's bake-and-extract
// is RETAINED underneath — base64gzip is layered on top, not a reversal.
// #6396: +~140 B modest re-baseline (21,500 → 21,800). The Vector-shipper BODIES are baked into
// soleur-host-bootstrap.sh (0 user_data, #5921 pattern); the irreducible inline cost is the
// terminal-block boot-emit trap + the ungated `soleur-vector-install` call site + per-host
// SOLEUR_HOST_NAME injection — necessary call-sites, not a re-inlined blob. Comments trimmed first.
// #6425: +100 B modest re-baseline (21,800 → 21,900). Measured 21,716 → 21,784 (+68 B) for the
// col-0 `%{ if web_tunnel_connector ~}` / `%{ endif ~}` connector gate + its one-line pointer
// comment. This is the one addition the "prefer baking over inline" guidance above CANNOT absorb:
// a templatefile directive is evaluated at RENDER time by terraform, so it is irreducibly inline —
// baking it into soleur-host-bootstrap.sh would move it to boot time, after the token is already
// in user_data, defeating the gate's security half. Full rationale lives in server.tf (not
// byte-budgeted); cloud-init.yml carries only a pointer. Comments trimmed first (an earlier draft
// cost +516 B). At 21,800 the headroom was 16 B — below the noise floor of any future edit, which
// would have made the NEXT infra change fail CI for no defect. 21,900 keeps the guard's actual
// purpose intact: a KB-scale re-inlining (~1.5+ KB, the failure mode this exists to catch) still
// trips it, and it stays ~10.9 KB below HETZNER_CAP.
// #6594: +400 B modest re-baseline (21,900 → 22,300). Measured 21,836 → 22,044 (+208 B) for the
// fail2ban `ignoreip = ... 10.0.1.0/24` grant (+60 B) plus its one-line pointer comment (+148 B).
// The grant is a REQUIRED consequence of pinning the tunnel ingress, not an independent addition:
// once `ssh.` resolves to web-1's private IP, a peer connector proxies in from a real source
// address instead of 127.0.0.1, so fail2ban's default loopback ignore no longer covers the CI
// login path — see server.tf's fail2ban_tuning block for the full rationale (a lockout there is
// noVNC-only recovery). "Prefer baking over inline" CANNOT absorb it: fail2ban is reloaded at the
// package-audit stage, BEFORE Docker, so its drop-in cannot come from the post-Docker image
// extraction (server.tf's keep-inline note) — the #5921 treatment that moved journald out is
// structurally unavailable here. Rationale prose was moved to server.tf (free) and only the
// pointer kept, per #6425's precedent. 21,900 would have left 4 B of headroom — the same
// below-the-noise-floor trap #6425 called out at 16 B. 22,300 keeps the guard's purpose intact:
// a KB-scale re-inlining (~1.5+ KB) still trips it, and it stays ~10.2 KB below HETZNER_CAP.
// #6604: on top of #6594's 22,300 baseline, +~150 B for two irreducibly-inline additions the
// "prefer baking over inline" guidance CANNOT absorb: (a) the /mnt/data mount pinned by-id + fstab
// `nofail` + fstab-dedupe guard (the glob binds the wrong device once the LUKS volume attaches —
// MUST be in the runcmd mount, not a baked helper), and (b) the baked-DSN write to
// /etc/default/luks-monitor (the luks-monitor units source it; MUST be written at cloud-init time so
// a Doppler-down boot still pages — DP-9). Merged render measured ~22,256; 22,450 keeps the KB-scale
// re-inlining tripwire (a ~1.5 KB blob → ~23.7 KB trips it) and stays ~10.3 KB below HETZNER_CAP.
// #6459: on top of #6604's 22,450 baseline, +~250 B for the fresh-boot readiness marker's
// irreducibly-inline CALL-SITE. The helper BODY (soleur-fresh-boot-ready, incl. its Doppler token
// fetch) is baked into soleur-host-bootstrap.sh → 0 user_data (#5921 pattern applied). What CANNOT
// be baked is the invocation itself: the marker must run as the LAST runcmd item (AFTER Vector, so
// vector= is truthful) and receives BETTERSTACK_INGEST_URL='${betterstack_ingest_url}' — a
// templatefile splice evaluated at RENDER time (single source of truth = local.betterstack_logs_ingest_url;
// baking a hardcoded copy would re-duplicate the URL constant). Comments trimmed first (2 lines).
// Measured render ~22,564; 22,700 keeps the KB-scale re-inlining tripwire (a ~1.5 KB blob still
// trips it) and stays ~10 KB below HETZNER_CAP.
const WEB_GZIP_BUDGET = 22_700;
const WEB_GZIP_FLOOR = 10_000;
// git-data base64gzip'd budget (#5927). Measured base64gzip output ~21,929 B; the 28,000 B
// budget leaves ~6 KB headroom over that — loose enough for Go(terraform)-vs-node(zlib) header/
// level differences + CI jitter, tight enough to catch a re-inlined script re-ballooning the raw
// payload. The FLOOR (10,000 B) is non-vacuity: the modeled render must gzip to something real,
// so a broken model that gzips near-nothing (e.g. accidentally x-run placeholders) fails loudly.
const GIT_DATA_BUDGET = 28_000;
const GIT_DATA_FLOOR = 10_000;

const IMAGE_NAME = "ghcr.io/jikig-ai/soleur-web-platform:latest";
// Modeled byte lengths for render-time values that are NOT base64-of-a-file. base64-of-file
// args are computed exactly from disk; only these variable-length values are approximated.
const SECRET_LENGTHS: Record<string, number> = {
  image_name: IMAGE_NAME.length,
  tunnel_token: 220,
  webhook_deploy_secret: 64,
  doppler_token: 48,
  resend_api_key: 40,
  ci_ssh_public_key_openssh: 120,
  git_transport_pubkey: 120,
  git_provision_pubkey: 120,
  git_remove_pubkey: 120,
  git_data_volume_id: 24,
  git_data_luks_volume_id: 24,
};
const DEFAULT_REF_LEN = 80;

function b64len(bytes: number): number {
  return 4 * Math.ceil(bytes / 3); // terraform base64encode: padded, no line breaks — exact.
}

function extractTemplatefileMap(tfSrc: string, cloudInitFile: string): string {
  const anchor = `templatefile("\${path.module}/${cloudInitFile}", {`;
  const start = tfSrc.indexOf(anchor);
  if (start === -1) throw new Error(`templatefile anchor for ${cloudInitFile} not found`);
  let i = start + anchor.length;
  let depth = 1;
  const bodyStart = i;
  for (; i < tfSrc.length && depth > 0; i++) {
    if (tfSrc[i] === "{") depth++;
    else if (tfSrc[i] === "}") depth--;
  }
  return tfSrc.slice(bodyStart, i - 1);
}

function parseVarMap(mapBody: string): Record<string, string> {
  const out: Record<string, string> = {};
  for (const raw of mapBody.split("\n")) {
    const line = raw.trim();
    if (!line || line.startsWith("#")) continue;
    const m = /^([a-zA-Z0-9_]+)\s*=\s*(.+?)\s*$/.exec(line);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

function modeledLen(name: string, expr: string): number {
  const fileMatch = /^base64encode\(file\("\$\{path\.module\}\/([^"]+)"\)\)$/.exec(expr);
  if (fileMatch) return b64len(readFileSync(join(INFRA, fileMatch[1])).byteLength);
  // Guard: any other base64encode(file(...)) shape must be recognized, else the model would
  // silently under-count a large blob and mask a re-inlining regression.
  if (/base64encode\(file\(/.test(expr)) {
    throw new Error(`unrecognized base64encode(file()) for ${name}: ${expr}`);
  }
  if (/^base64encode\(local\.hooks_json\)$/.test(expr)) {
    const tmpl = readFileSync(join(INFRA, "hooks.json.tmpl"), "utf8");
    const rendered = tmpl.replace(
      /\$\{jsonencode\(webhook_deploy_secret\)\}/g,
      JSON.stringify("x".repeat(SECRET_LENGTHS.webhook_deploy_secret)),
    );
    return b64len(Buffer.byteLength(rendered, "utf8"));
  }
  if (/^sha256\(/.test(expr)) return 64;
  if (name in SECRET_LENGTHS) return SECRET_LENGTHS[name];
  return DEFAULT_REF_LEN;
}

// Model rendered `user_data` byte-length: substitute modeled values into the cloud-init
// template, honoring terraform's `$${` -> `${` escape (those are shell vars, not template
// interpolations, and must NOT be modeled).
function renderedSize(cloudInitFile: string, vars: Record<string, number>): number {
  const src = readFileSync(join(INFRA, cloudInitFile), "utf8");
  const ESC = "__SOLEUR_ESC__";
  let s = src.split("$${").join(ESC);
  s = s.replace(/\$\{([a-zA-Z0-9_]+)\}/g, (_whole, name) => {
    if (!(name in vars)) {
      throw new Error(`${cloudInitFile} references un-provided template var \${${name}}`);
    }
    return "x".repeat(vars[name]);
  });
  s = s.split(ESC).join("${");
  return Buffer.byteLength(s, "utf8");
}

function varLengths(tfSrc: string, cloudInitFile: string): Record<string, number> {
  const map = parseVarMap(extractTemplatefileMap(tfSrc, cloudInitFile));
  const out: Record<string, number> = {};
  for (const [name, expr] of Object.entries(map)) out[name] = modeledLen(name, expr);
  return out;
}

// The REAL string value terraform would substitute for a templatefile var — needed for the
// gzip model (git-data / #5927). For base64encode(file()) args this is the ACTUAL base64 of the
// script on disk (its byte content, NOT an "x".repeat placeholder — placeholders compress
// ~1000:1 and would make the gzip budget non-discriminating). Small variable-length secrets/ids
// stay as fixed-length "x".repeat placeholders: at ~600 B total they don't move the budget, and
// their exact byte content is unknown at test time anyway.
function modeledValue(name: string, expr: string): string {
  const fileMatch = /^base64encode\(file\("\$\{path\.module\}\/([^"]+)"\)\)$/.exec(expr);
  if (fileMatch) return readFileSync(join(INFRA, fileMatch[1])).toString("base64");
  if (/base64encode\(file\(/.test(expr)) {
    throw new Error(`unrecognized base64encode(file()) for ${name}: ${expr}`);
  }
  return "x".repeat(modeledLen(name, expr));
}

// Model the base64gzip() OUTPUT length — what Hetzner stores against the 32,768 cap for git-data
// (#5927). Renders the cloud-init template with REAL script content (via modeledValue), gzips at
// level 9 (matching terraform's base64gzip), and base64-encodes. NOT byte-exact vs terraform's Go
// zlib (different header/level), so callers assert a BUDGET, never equality (#5887's terraform
// plan is the byte-exact truth).
function renderedGzipB64Len(cloudInitFile: string, tfSrc: string): number {
  const map = parseVarMap(extractTemplatefileMap(tfSrc, cloudInitFile));
  const src = readFileSync(join(INFRA, cloudInitFile), "utf8");
  const ESC = "__SOLEUR_ESC__";
  let s = src.split("$${").join(ESC);
  s = s.replace(/\$\{([a-zA-Z0-9_]+)\}/g, (_whole, name) => {
    if (!(name in map)) {
      throw new Error(`${cloudInitFile} references un-provided template var \${${name}}`);
    }
    return modeledValue(name, map[name]);
  });
  s = s.split(ESC).join("${");
  return gzipSync(Buffer.from(s, "utf8"), { level: 9 }).toString("base64").length;
}

const serverTf = readFileSync(join(INFRA, "server.tf"), "utf8");
const gitDataTf = readFileSync(join(INFRA, "git-data.tf"), "utf8");
const cloudInit = readFileSync(join(INFRA, "cloud-init.yml"), "utf8");
const bootstrap = readFileSync(join(INFRA, "soleur-host-bootstrap.sh"), "utf8");
const dockerfile = readFileSync(DOCKERFILE, "utf8");
const dockerignore = readFileSync(join(REPO_ROOT, "apps", "web-platform", ".dockerignore"), "utf8");

describe("rendered user_data size (Hetzner 32,768 B cap)", () => {
  test("web host base64gzip'd user_data is under the sub-cap budget (#6090)", () => {
    // server.tf wraps the web render in base64gzip() (#6090, git-data #5927 precedent). Model the
    // base64gzip OUTPUT (the string Hetzner stores against the cap) with REAL keep-inline content.
    const size = renderedGzipB64Len("cloud-init.yml", serverTf);
    expect(size).toBeLessThan(HETZNER_CAP);
    expect(size).toBeLessThan(WEB_GZIP_BUDGET);
    expect(size).toBeGreaterThan(WEB_GZIP_FLOOR); // non-vacuity
  });

  test("git-data host base64gzip'd user_data is under the sub-cap budget (#5927)", () => {
    // git-data is a no-docker host: #5921's bake-and-extract does not apply. Post-#5918 its RAW
    // render is ~41.7 KB (over cap), so git-data.tf wraps it in base64gzip(). We model the
    // base64gzip OUTPUT (the string Hetzner stores against the cap) with REAL script content.
    const size = renderedGzipB64Len("cloud-init-git-data.yml", gitDataTf);
    expect(size).toBeLessThan(HETZNER_CAP);
    expect(size).toBeLessThan(GIT_DATA_BUDGET);
    expect(size).toBeGreaterThan(GIT_DATA_FLOOR); // non-vacuity: model must gzip real content
  });

  test("git-data gzip model reads REAL script content, not x-run placeholders (guards R2)", () => {
    // R2: the base64gzip budget above only discriminates if modeledValue substitutes the ACTUAL
    // base64 of each base64encode(file()) script. If modeledValue regressed to "x".repeat(N), the
    // whole render would gzip ~4x smaller (real ~21.9 KB vs placeholder ~5.2 KB) and drop below
    // GIT_DATA_FLOOR — so the budget test would fail loudly. Guard that property at the source by
    // asserting modeledValue itself: a real file arg must yield the file's true base64, never an
    // x-run stand-in. (Testing modeledValue directly avoids the trap where injecting content
    // through a bypass path proves nothing about modeledValue.)
    const fileArg = 'base64encode(file("${path.module}/git-data-bootstrap.sh"))';
    const real = modeledValue("git_data_bootstrap_b64", fileArg);
    expect(real).toBe(readFileSync(join(INFRA, "git-data-bootstrap.sh")).toString("base64"));
    expect(real).not.toMatch(/^x+$/); // NOT the placeholder the non-file path would produce
    expect(real.length).toBeGreaterThan(1_000); // a real script's base64 is substantial, not ~600 B of noise
  });
});

describe("server.tf keep/remove contract (AC3/AC5/AC6)", () => {
  const webMap = extractTemplatefileMap(serverTf, "cloud-init.yml");

  test("fail2ban keep-inline b64 arg is still present", () => {
    expect(webMap).toContain("fail2ban_sshd_local_b64");
  });
  test("journald b64 arg is removed (now baked, #5921)", () => {
    expect(webMap).not.toContain("journald_soleur_conf_b64");
  });
  test("webhook_deploy_secret is retained (injected into hooks at boot)", () => {
    expect(webMap).toContain("webhook_deploy_secret");
  });
  test("hooks_json_b64 is removed from the web templatefile map (AC6)", () => {
    expect(webMap).not.toContain("hooks_json_b64");
  });
  test("host_scripts_content_hash render var is added (AC5)", () => {
    expect(webMap).toContain("host_scripts_content_hash");
    expect(serverTf).toMatch(/host_scripts_content_hash\s*=\s*sha256\(/);
    expect(serverTf).toMatch(/local\.host_script_files/);
  });
  test("the externalized script args are gone from the web templatefile map", () => {
    for (const gone of [
      "ci_deploy_script_b64",
      "disk_monitor_script_b64",
      "infra_config_apply_script_b64",
      "cron_egress_nftables_script_b64",
      "cron_egress_postapply_assert_b64",
    ]) {
      expect(webMap).not.toContain(gone);
    }
  });
});

describe("cloud-init launcher contract (AC4/AC5/AC8)", () => {
  const BEGIN = "# BEGIN host-script extraction (#5921)";
  const END = "# END host-script extraction (#5921)";
  const block = (() => {
    const a = cloudInit.indexOf(BEGIN);
    const b = cloudInit.indexOf(END);
    return a !== -1 && b !== -1 ? cloudInit.slice(a, b) : "";
  })();

  test("launcher block exists and is delimited", () => {
    expect(cloudInit).toContain(BEGIN);
    expect(cloudInit).toContain(END);
  });
  test("the extraction docker pull has NO `|| true` (AC4d)", () => {
    expect(block).toMatch(/until docker pull/);
    expect(block).not.toMatch(/docker pull[^\n]*\|\|\s*true/);
  });
  test("combined content-hash is verified before the baked installer runs (AC5)", () => {
    // Anchor on the actual hash-COMPARE line and the actual RUN line (both mention the
    // bootstrap/hash in header comments too, so use the load-bearing statements).
    const verifyIdx = block.indexOf('"$HOST_SCRIPTS_HASH"');
    const runIdx = block.lastIndexOf("soleur-host-bootstrap.sh");
    expect(verifyIdx).toBeGreaterThan(-1);
    expect(runIdx).toBeGreaterThan(-1);
    expect(verifyIdx).toBeLessThan(runIdx);
    // The install ceremony lives in the baked script, not inline (keeps user_data small).
    expect(block).not.toMatch(/install -D/);
  });
  test("pre-verify failures emit a discriminating Sentry signal (AC9)", () => {
    expect(block).toMatch(/sentry/i);
    expect(block).toContain("stage");
  });
  test("terminal docker run is gated on the fail-closed sentinel (AC8)", () => {
    expect(cloudInit).toMatch(/test -f \/run\/soleur-hostscripts\.ok \|\|/);
    expect(cloudInit).toMatch(/poweroff -f/);
  });
  // #6462 AC1 — the fresh-boot registry beacon must sit BEFORE `IMAGE_REF="$REF"`.
  //
  // WHY THE ORDER IS THE WHOLE FEATURE: after the pull loop, `REF == IMAGE_REF` iff GHCR
  // served the image and `REF != IMAGE_REF` iff zot did — that comparison IS the
  // discriminator. `IMAGE_REF="$REF"` reassigns IMAGE_REF to the served ref, making the
  // comparison tautologically true from that line on. One line later and the beacon
  // reports "GHCR served" on every boot, forever.
  //
  // THE -1 GUARDS ARE LOAD-BEARING, NOT CEREMONY. indexOf returns -1 on a miss and -1 is
  // less than every real offset, so `servedIdx < refIdx` ALONE passes on a tree with no
  // beacon in it at all — a typo'd stage, a renamed stage, or the line never being written
  // all satisfy it. (Verified: on the pre-beacon tree this assert returned -1 < 31470 =>
  // true.) This mirrors the AC5 idiom above IN FULL — both toBeGreaterThan(-1) legs, then
  // the ordering — not just its last line. Existence is ALSO pinned independently in
  // sentry-zot-mirror-fallback-alert-op-contract.test.ts so neither AC vacuously carries
  // the other.
  //
  // ANCHOR ON THE CALL FORM, NOT THE BARE TOKEN: the rationale comment above the emit names
  // `app_ghcr_served`, so `indexOf("app_ghcr_served")` would return the COMMENT's offset
  // (which sits above the anchor) and pass even with the code line below `IMAGE_REF="$REF"`
  // — the exact failure this test exists to catch. Prose cannot produce the call form.
  //
  // ACCEPTED WART, documented here because cloud-init.yml is byte-budgeted and this file is
  // NOT (the emit carries only a one-line pointer): `_emit` builds its `image_ref` tag from
  // `$IMAGE_REF`, still the GHCR ref at the insertion point (the reassign is the next line).
  // So the `app_zot` beacon reports `image_ref: ghcr.io/…` — the wrong registry on the event
  // asserting zot served it. Deliberately NOT fixed:
  //   - Gate-harmless: `image_ref` appears in zot-soak-6122.sh only inside comments (:26,
  //     :40), never in a query — the soak reads `stage` alone.
  //   - The real pulls are unaffected: :642/:660/:780 read /run/soleur-image-ref, which the
  //     line above the beacon populates with the correct served ref.
  //   - The fix (a temp var) is affordable on bytes now, but lands in the boot path, where a
  //     malformed line means NO HOST BOOTS. Not worth that risk for a cosmetic tag nothing
  //     queries. Do not "fix" this on noticing the headroom.
  // BOTH operands must be comment-proof, not just the left one. An earlier draft anchored
  // the right operand on the bare literal `IMAGE_REF="$REF"` and the beacon's own rationale
  // comment quotes that assignment — so indexOf resolved it to the COMMENT (which sits
  // ABOVE the beacon) and the test failed with servedIdx > refIdx even though the code was
  // correctly ordered. Same defect class as the left operand, mirrored. Anchor on
  // `^\s*…$` via .search(): a comment line begins with `#`, so it can never satisfy it.
  test("the fresh-boot registry beacon precedes the IMAGE_REF reassignment (#6462 AC1)", () => {
    const servedIdx = block.indexOf('"app_ghcr_served" warning');
    const refIdx = block.search(/^\s*IMAGE_REF="\$REF"$/m);
    expect(servedIdx).toBeGreaterThan(-1);
    expect(refIdx).toBeGreaterThan(-1);
    expect(servedIdx).toBeLessThan(refIdx);
  });
  // #6462 AC1b — AC1's anchor is defeated the moment a comment quotes the emit call
  // verbatim (indexOf would silently return the comment's offset). Make that self-enforcing
  // rather than asking four paragraphs of prose not to do it.
  // #6462 AC1c — pin WHICH REGISTRY EACH BRANCH REPORTS, not just where the line sits.
  //
  // AC1/AC1b pin the beacon's POSITION and the uniqueness of its anchors. Neither pins its
  // SEMANTICS, and mutation testing proved the gap is real: inverting the discriminator
  // (`=` → `!=`) passed ALL 39 tests across both files. That mutation is a FALSE-PASS ROUTE
  // on the gate authorizing an irreversible PAT revoke — on an all-GHCR fleet it reports
  // app_zot>0 / app_ghcr_served=0, so the denominator looks satisfied and the FAIL set stays
  // silent, and only the independent MIN_SAMPLE arm still objects.
  //
  // The direction is the whole feature. After the pull loop:
  //   REF == IMAGE_REF  ⟺  GHCR served it (the probe missed, OR the zot→GHCR flip reassigned
  //                        REF="$IMAGE_REF")  → app_ghcr_served, `warning`, a FAIL signal
  //   REF != IMAGE_REF  ⟺  zot served it (the zot branch prefixed "$ZURL/") → app_zot, `info`,
  //                        the DENOMINATOR
  // Pin the literal so `=`↔`!=` and a branch swap both go red.
  test("the beacon maps each branch to the RIGHT registry (#6462 AC1c — direction, not position)", () => {
    expect(block).toContain(
      'if [ "$REF" = "$IMAGE_REF" ]; then _emit "app image served by GHCR" "app_ghcr_served" warning; else _emit "app image served by zot" "app_zot" info; fi',
    );
  });
  test("each beacon call form appears exactly once, so AC1's anchor stays unambiguous (#6462 AC1b)", () => {
    expect(block.match(/"app_ghcr_served" warning/g)).toHaveLength(1);
    expect(block.match(/"app_zot" info/g)).toHaveLength(1);
    // The right operand too: exactly one line-anchored reassignment, so AC1's .search()
    // cannot silently pick a different one if the boot path ever grows a second.
    expect(block.match(/^\s*IMAGE_REF="\$REF"$/gm)).toHaveLength(1);
  });
  test("cloud-init no longer references the externalized write_files vars", () => {
    for (const gone of [
      "ci_deploy_script_b64",
      "hooks_json_b64",
      "cron_egress_firewall_service_b64",
      "infra_config_install_script_b64",
      "journald_soleur_conf_b64",
    ]) {
      expect(cloudInit).not.toContain(`\${${gone}}`);
    }
  });
});

describe("baked bootstrap installer contract (AC4/AC5/AC6/AC8/AC9)", () => {
  test("installs with authoritative modes, never a preserve-mode copy (AC4e)", () => {
    expect(bootstrap).toMatch(/install -D -m 0755/);
    expect(bootstrap).toMatch(/install -D -m 0644/);
    expect(bootstrap).not.toMatch(/cp -a|cp -p|docker cp[^\n]*\/usr\/local\/bin/);
  });
  test("per-file assertions incl. the sudo-NOPASSWD escalation helper mode (AC4f)", () => {
    expect(bootstrap).toMatch(/test -x .*infra-config-install/);
    expect(bootstrap).toMatch(/stat -c %a \/usr\/local\/bin\/infra-config-install/);
    expect(bootstrap).toContain("755");
  });
  test("hooks.json secret is injected via literal jsonencode-equivalent (AC6)", () => {
    expect(bootstrap).toContain("${jsonencode(webhook_deploy_secret)}");
    expect(bootstrap).toMatch(/json\.dumps\(secret\)/);
    expect(bootstrap).toMatch(/grep -q infra-config-status/);
  });
  test("sentinel is written LAST (AC8)", () => {
    const sentIdx = bootstrap.indexOf(": > /run/soleur-hostscripts.ok");
    expect(sentIdx).toBeGreaterThan(-1);
    // nothing but a trailing newline after the sentinel write
    expect(bootstrap.slice(sentIdx).trim()).toBe(": > /run/soleur-hostscripts.ok");
  });
  test("failure trap emits a discriminating Sentry event (AC9)", () => {
    expect(bootstrap).toMatch(/sentry/i);
    expect(bootstrap).toMatch(/"stage":"%s"/);
    expect(bootstrap).toMatch(/trap emit_fail EXIT/);
  });
  test("installs + kernel-loads the container-sandbox profiles on-host (#6629 fresh-host delivery leg)", () => {
    // The delivery-leg the RCA is about: a fresh host must receive BOTH profiles at the
    // exact paths the terminal docker run's --security-opt reads, AND kernel-load apparmor
    // ("applied != loaded" — apparmor=soleur-bwrap fails container-create otherwise). Without
    // these assertions a "clean up the #6629 block" refactor could delete the install+assert
    // lines together and ship a silently-unenforced fresh host (all placement/parity/count
    // tests stay green). Pins install -> path, the load, and the fail-closed presence gate.
    expect(bootstrap).toMatch(
      /install -D -m 0644[^\n]*seccomp-bwrap\.json[^\n]*\/etc\/docker\/seccomp-profiles\/soleur-bwrap\.json/,
    );
    expect(bootstrap).toMatch(
      /install -D -m 0644[^\n]*apparmor-soleur-bwrap\.profile[^\n]*\/etc\/apparmor\.d\/soleur-bwrap/,
    );
    expect(bootstrap).toMatch(/apparmor_parser -r \/etc\/apparmor\.d\/soleur-bwrap/);
    // fail-closed presence + kernel-load asserts (run before the sentinel write)
    expect(bootstrap).toMatch(/test -f \/etc\/docker\/seccomp-profiles\/soleur-bwrap\.json/);
    expect(bootstrap).toMatch(/test -f \/etc\/apparmor\.d\/soleur-bwrap/);
    expect(bootstrap).toMatch(/aa-status[^\n]*grep -qE '\^\[\[:space:\]\]\+soleur-bwrap\$'/);
  });
});

describe("Dockerfile <-> server.tf baked-set parity (AC2)", () => {
  // Parser is parameterized on the source text so the comment-hazard fixture below can
  // exercise the SAME code path the real server.tf goes through (a fixture that tested a
  // reimplementation would prove nothing about this parser).
  function parseHostScriptFiles(src: string): string[] {
    const defMatch = /host_script_files\s*=\s*\[([\s\S]*?)\]/.exec(src);
    // Strip whole-line `#` comments BEFORE the quoted-string match. The real block carries
    // ~10 interleaved comment lines; none contains a double-quoted string TODAY, but one
    // future comment reading `# ... installs "vector.toml" ...` would silently inject a
    // phantom entry into the parsed set — a wrong answer with no diagnostic. Anchored on
    // `^\s*#`, which is HCL comment syntax and cannot appear inside a list element.
    const body = (defMatch?.[1] ?? "")
      .split("\n")
      .filter((line) => !/^\s*#/.test(line))
      .join("\n");
    // NOTE: duplicates are deliberately PRESERVED here (map-then-sort, not a Set) so the
    // duplicate-entry assertion below has something to detect.
    return [...body.matchAll(/"([^"]+)"/g)].map((x) => x[1]).sort();
  }
  function serverTfBakedSet(): string[] {
    return parseHostScriptFiles(serverTf);
  }
  function dockerfileBakedSet(): string[] {
    // Match ONLY the multi-line COPY that ends in /opt/soleur/host-scripts/ (the `\`
    // continuation distinguishes it from the single-line sandbox-canary COPY above it).
    const copyMatch = /COPY --from=builder\s*\\\n([\s\S]*?)\/opt\/soleur\/host-scripts\//.exec(
      dockerfile,
    );
    const body = copyMatch?.[1] ?? "";
    return [...body.matchAll(/\/app\/infra\/([^\s\\]+)/g)].map((x) => x[1]).sort();
  }

  // Everything AFTER the host-scripts COPY, truncated at the next stage boundary. The
  // runner is the last stage today, so this is COPY-to-EOF; the `^FROM` cut keeps the
  // region correct if a stage is ever appended.
  function dockerfileRunnerTailAfterBakedCopy(): string {
    const copy = /COPY --from=builder\s*\\\n[\s\S]*?\/opt\/soleur\/host-scripts\/[^\S\n]*\n/.exec(
      dockerfile,
    );
    if (!copy) throw new Error("host-scripts COPY not found in Dockerfile — parser is stale");
    const tail = dockerfile.slice(copy.index + copy[0].length);
    // NOTE: this truncates at the next stage, so instructions in an APPENDED stage are NOT
    // scanned. That is a known limitation, not a safety property — an earlier comment here
    // claimed the opposite. The appended-stage case is covered by the separate assertion
    // below that no stage after this COPY re-declares FROM on the runner.
    const nextStage = /^FROM\s/m.exec(tail);
    return nextStage ? tail.slice(0, nextStage.index) : tail;
  }

  // Logical mutating instructions (RUN/COPY/ADD) in a Dockerfile region, one per entry.
  //
  // COPY and ADD are included, not just RUN: a later `COPY --from=builder <x> /opt/soleur/
  // host-scripts/<x>` overwrites a baked file just as effectively as a `sed -i`, and is
  // arguably the likelier way an engineer would patch a script. It is also invisible to the
  // list-parity test above, because dockerfileBakedSet() matches ONLY the one multi-line
  // COPY — so the two LISTS still agree perfectly while the CONTENT has diverged. Measured
  // at review: a RUN-only candidate set let three distinct mutation shapes through green.
  function runInstructions(region: string): string[] {
    const src = region
      .split("\n")
      // Drop full-line `#` comments FIRST. A comment can never be an instruction, and
      // prose inside one must not be able to satisfy the instruction anchor below.
      .filter((line) => !/^\s*#/.test(line))
      .join("\n");
    // Fold `\` continuations so a multi-line RUN is ONE logical instruction (otherwise a
    // mutation hidden on a continuation line would never be seen by the anchor).
    return src
      .replace(/\\\n/g, " ")
      .split("\n")
      .map((line) => line.trim())
      // Anchor on the instruction keyword at line start — Dockerfile syntax a
      // comment or a prose mention of the word "RUN" structurally cannot produce.
      .filter((line) => /^(RUN|COPY|ADD)\s/.test(line));
  }

  test("both sides list the same files, incl. hooks.json.tmpl + bootstrap + journald", () => {
    const tf = serverTfBakedSet();
    const df = dockerfileBakedSet();
    expect(tf.length).toBeGreaterThan(0);
    expect(df).toEqual(tf);
    expect(tf).toContain("hooks.json.tmpl");
    expect(tf).toContain("soleur-host-bootstrap.sh");
    expect(tf).toContain("journald-soleur.conf");
  });
  test("the baked set is exactly 23 scripts + hooks.json.tmpl + journald + bootstrap + cosign-trusted-root + vector.toml + 2 sandbox profiles", () => {
    // +1 vs #5921's 25: cron-egress-enforce-probe.sh (fresh-host post-container egress
    // enforcement probe, #5933 item 3).
    // +1 (=27): cosign-trusted-root.json — pinned public trust material baked into the
    // HOST image (not the app image) + installed to /etc/soleur by the bootstrap (#6005,
    // ADR-087). A data file, not a script.
    // +1 (=28): vector.toml — the Vector shipper config baked for the ungated web-host
    // install (soleur-vector-install renders + installs it to /etc/vector/vector.toml, #6396).
    // A data file, not a script.
    // +2 (=30): seccomp-bwrap.json + apparmor-soleur-bwrap.profile — container-sandbox
    // security-control profiles baked for FRESH-host boot-time delivery + enforcement (#6629,
    // ADR-122). Previously SSH-provisioner-only, so a fresh host ran the tenant sandbox
    // unenforced. Data files, not scripts.
    expect(serverTfBakedSet().length).toBe(30);
  });

  // ASSERTION A (build-integrity). server.tf computes local.host_scripts_content_hash over
  // the on-disk repo tree at plan time; cloud-init recomputes it at boot over the files it
  // extracts FROM THE IMAGE. Any Dockerfile RUN that rewrites a baked file's CONTENT after
  // the COPY makes those two constructions disagree permanently — every fresh boot aborts,
  // and no list-parity test above can see it (the two LISTS still match perfectly).
  test("no RUN after the host-scripts COPY mutates the baked directory's content", () => {
    const runs = runInstructions(dockerfileRunnerTailAfterBakedCopy());
    // Non-vacuity floor: this region has RUN instructions today (chown, useradd, git
    // config). If the parser ever yields 0, the filter below is trivially satisfied and
    // this assertion silently stops guarding anything.
    expect(runs.length).toBeGreaterThan(0);

    // Candidates: any instruction naming the baked dir, or /opt/soleur which CONTAINS it
    // (a recursive op on the parent reaches the baked files just as directly).
    //
    // TAINT: selecting on the literal path alone is too narrow — `WORKDIR /opt/soleur/
    // host-scripts` followed by a path-relative `RUN sed -i ... soleur-host-bootstrap.sh`,
    // or `ENV SD=/opt/soleur` followed by `RUN sed -i ... $SD/host-scripts/...`, mutates
    // the same bytes without ever spelling the path on the mutating line. Both survived
    // green when measured at review. So if any WORKDIR/ENV in this region names the baked
    // path, every following instruction becomes a candidate and must justify itself.
    const region = dockerfileRunnerTailAfterBakedCopy();
    const tainted = /^\s*(WORKDIR|ENV)\s+[^\n]*\/opt\/soleur/m.test(region);
    const touching = tainted ? runs : runs.filter((r) => r.includes("/opt/soleur"));

    // ALLOW-LIST — ownership only, and only this exact form. `chown -R 1001:1001
    // /opt/soleur` is safe because it changes the owner uid/gid recorded in the layer's
    // metadata and NOTHING ELSE: file CONTENT is byte-identical before and after, so the
    // sha256-over-contents that both sides compute is unaffected. Anything else reaching
    // this path — `sed -i`, a `>` or `>>` redirect, `install`, `cp`, `truncate`, `chmod`
    // combined with a rewrite — alters content and MUST fail here.
    const OWNERSHIP_ONLY = /^RUN chown -R 1001:1001 \/opt\/soleur$/;
    expect(touching.filter((r) => !OWNERSHIP_ONLY.test(r))).toEqual([]);
    // The allow-list must stay LIVE: if the chown is renamed or removed, this trips so the
    // exemption is re-justified rather than silently covering nothing.
    expect(touching.filter((r) => OWNERSHIP_ONLY.test(r)).length).toBe(1);
  });

  // ASSERTION B (build-integrity). Terraform hashes the ENUMERATED list — sort() preserves
  // duplicates, so a repeated entry contributes its filesha256 twice. The boot side hashes
  // files FOUND ON DISK, where the duplicate collapses to one. The two hashes then disagree
  // permanently and every fresh host aborts at the pre-install verify. List parity above
  // cannot catch it: the Dockerfile COPY tolerates a repeated source path silently.
  test("host_script_files contains no duplicate entries", () => {
    const tf = serverTfBakedSet();
    const duplicates = [...new Set(tf.filter((f, i) => tf.indexOf(f) !== i))];
    expect(duplicates).toEqual([]);
  });

  // Parser hazard (Phase 1.2). Pins the `^\s*#` strip in parseHostScriptFiles: without it,
  // a future comment quoting a filename injects a phantom entry and every downstream
  // assertion in this describe silently reasons about a wrong set.
  test("a quoted filename inside a comment does not enter the parsed set", () => {
    const clean = `locals {
  host_script_files = [
    "alpha.sh",
    "beta.conf",
  ]
}`;
    const commented = `locals {
  host_script_files = [
    "alpha.sh",
    # the bootstrap also installs "phantom.toml" to /etc/soleur — prose, not an entry
    "beta.conf",
  ]
}`;
    expect(parseHostScriptFiles(clean)).toEqual(["alpha.sh", "beta.conf"]);
    expect(parseHostScriptFiles(commented)).toEqual(parseHostScriptFiles(clean));
    expect(parseHostScriptFiles(commented)).not.toContain("phantom.toml");
  });

  // #5922 release break: the Dockerfile bakes the host-scripts via
  // `COPY --from=builder /app/infra/<file>`, but `.dockerignore` excludes the
  // whole `infra/` dir from the builder-stage `COPY . .`. Every baked file must
  // be re-included with `!infra/<file>` or the runner COPY fails
  // ("/app/infra/<file>": not found) and the entire web-platform release build
  // breaks. This asserts the third leg of parity the AC2 test above did not cover.
  //
  // NOTE: this host-scripts-only re-include leg is now SUBSUMED by the generalized guard in
  // plugins/soleur/test/dockerfile-copy-dockerignore-parity.test.ts (which checks EVERY builder
  // COPY --from / RUN .sh src against every .dockerignore exclusion, not just the infra/ host-scripts
  // block). It is retained here as the AC2 parity trio. If you edit either parser, update both.
  function dockerignoreInfraReincludes(): Set<string> {
    const set = new Set<string>();
    for (const raw of dockerignore.split("\n")) {
      const m = /^!infra\/(\S+)\s*$/.exec(raw.trim());
      if (m) set.add(m[1]);
    }
    return set;
  }
  test("every baked host-script is re-included in .dockerignore (survives COPY . .)", () => {
    const reincludes = dockerignoreInfraReincludes();
    const missing = dockerfileBakedSet().filter((f) => !reincludes.has(f));
    expect(missing).toEqual([]);
  });
});

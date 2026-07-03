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
// git-data (AC7): the git-data host is a NO-DOCKER host, so #5921's bake-and-extract mechanism
// does not apply. After #5918 (LUKS/transport/remove/provision) its user_data is ~41.7 KB —
// OVER the Hetzner cap — a distinct-mechanism fix tracked in #5927 (hard blocker on ADR-068
// Phase 2). Until then we pin it at a NO-FURTHER-GROWTH ceiling so CI stays green while still
// catching NEW git-data growth.

import { test, expect, describe } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";

const REPO_ROOT = join(import.meta.dir, "..", "..", "..");
const INFRA = join(REPO_ROOT, "apps", "web-platform", "infra");
const DOCKERFILE = join(REPO_ROOT, "apps", "web-platform", "Dockerfile");

// Hetzner hard cap; we enforce a sub-cap budget on WEB so a partial re-inlining still fails
// CI with headroom (measured web ~29,256 B).
const HETZNER_CAP = 32_768;
const WEB_BUDGET = 30_500;
const WEB_FLOOR = 5_000; // non-vacuity
// git-data known-over-cap ceiling (measured ~41,662 B) — see #5927.
const GIT_DATA_CEILING = 42_000;

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

const serverTf = readFileSync(join(INFRA, "server.tf"), "utf8");
const gitDataTf = readFileSync(join(INFRA, "git-data.tf"), "utf8");
const cloudInit = readFileSync(join(INFRA, "cloud-init.yml"), "utf8");
const bootstrap = readFileSync(join(INFRA, "soleur-host-bootstrap.sh"), "utf8");
const dockerfile = readFileSync(DOCKERFILE, "utf8");
const dockerignore = readFileSync(join(REPO_ROOT, "apps", "web-platform", ".dockerignore"), "utf8");

describe("rendered user_data size (Hetzner 32,768 B cap)", () => {
  test("web host user_data is under the sub-cap budget with headroom", () => {
    const size = renderedSize("cloud-init.yml", varLengths(serverTf, "cloud-init.yml"));
    expect(size).toBeLessThan(WEB_BUDGET);
    expect(size).toBeLessThan(HETZNER_CAP);
    expect(size).toBeGreaterThan(WEB_FLOOR); // non-vacuity
  });

  test("git-data host user_data stays at-or-below its known-over-cap ceiling (#5927)", () => {
    // git-data is a no-docker host: #5921's bake-and-extract does not apply. It is OVER the
    // Hetzner cap post-#5918; a distinct-mechanism fix is tracked in #5927. This ceiling keeps
    // CI green while catching NEW growth — do NOT relax it to hide further regressions.
    const size = renderedSize(
      "cloud-init-git-data.yml",
      varLengths(gitDataTf, "cloud-init-git-data.yml"),
    );
    expect(size).toBeLessThan(GIT_DATA_CEILING);
    expect(size).toBeGreaterThan(0);
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
});

describe("Dockerfile <-> server.tf baked-set parity (AC2)", () => {
  function serverTfBakedSet(): string[] {
    const defMatch = /host_script_files\s*=\s*\[([\s\S]*?)\]/.exec(serverTf);
    const body = defMatch?.[1] ?? "";
    return [...body.matchAll(/"([^"]+)"/g)].map((x) => x[1]).sort();
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

  test("both sides list the same files, incl. hooks.json.tmpl + bootstrap + journald", () => {
    const tf = serverTfBakedSet();
    const df = dockerfileBakedSet();
    expect(tf.length).toBeGreaterThan(0);
    expect(df).toEqual(tf);
    expect(tf).toContain("hooks.json.tmpl");
    expect(tf).toContain("soleur-host-bootstrap.sh");
    expect(tf).toContain("journald-soleur.conf");
  });
  test("the baked set is exactly 23 scripts + hooks.json.tmpl + journald + bootstrap", () => {
    // +1 vs #5921's 25: cron-egress-enforce-probe.sh (fresh-host post-container egress
    // enforcement probe, #5933 item 3).
    expect(serverTfBakedSet().length).toBe(26);
  });

  // #5922 release break: the Dockerfile bakes the host-scripts via
  // `COPY --from=builder /app/infra/<file>`, but `.dockerignore` excludes the
  // whole `infra/` dir from the builder-stage `COPY . .`. Every baked file must
  // be re-included with `!infra/<file>` or the runner COPY fails
  // ("/app/infra/<file>": not found) and the entire web-platform release build
  // breaks. This asserts the third leg of parity the AC2 test above did not cover.
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

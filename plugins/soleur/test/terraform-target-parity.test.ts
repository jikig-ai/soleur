// Terraform `-target=` parity guard (#4844).
//
// Every SSH-provisioned `terraform_data.*` resource in apps/web-platform/infra/*.tf
// MUST be reachable by an auto-apply path, or it silently drifts: the GitHub
// runner egress IP is not in var.admin_ips, so these resources are EXCLUDED from
// the main saved-tfplan apply and only land via an explicit `-target=` over the
// CF Tunnel SSH bridge. This test asserts each such resource appears in the UNION
// of:
//   • apply-web-platform-infra.yml's SSH `-target=` set (the 7 server.tf siblings)
//   • apply-deploy-pipeline-fix.yml's `-target=` set (deploy_pipeline_fix +
//     infra_config_handler_bootstrap)
//   • the exclusion allowlist (root_authorized_keys — stays operator-local per the
//     firewall chicken-and-egg; it is what authorizes the CI key the bridge uses).
//
// SSH-provisioned predicate: a `terraform_data` resource that has BOTH a
//   `connection { … type = "ssh" … }` block AND at least one `provisioner` block.
// `deploy_pipeline_fix` is `local-exec` with NO connection block → correctly
// excluded by this predicate (do NOT count it).
//
// COMMENT-STRIP (SpecFlow 2c, P0): a server.tf comment block (the #3756-
// regression-explanation preceding infra_config_handler_bootstrap) contains the
// literal `connection{type="ssh"}`. `#`/`//` line comments are stripped before
// matching so that comment cannot false-count (and mask a real miss). A
// non-vacuity test below proves the strip is load-bearing.
//
// CONCURRENCY-GROUP PARITY (#4844 P0): the R2 backend has no state lock, so the
// IDENTICAL `concurrency.group` literal in both SSH-applying workflows is the
// sole state serializer. A divergent string silently fails to serialize (GHA
// does not error), so this test also asserts the two literals are byte-equal and
// the shared cloudflared pins match — converting that silent-correctness
// invariant into an enforced one.
//
// DOCUMENTED LIMITATION (SpecFlow 2b): this guard is ONE-DIRECTIONAL — it proves
// every SSH resource is in the union, NOT that every `-target=` line points at a
// live resource. A stale/typo'd `-target=` is NOT caught here (terraform exits 0
// on "no resources matched"). A reverse-direction guard is out of scope.
//
// PARSER ASSUMPTIONS: (1) HCL braces are balanced even inside the remote-exec
// inline strings in these files (`${…}` interpolations and heredoc bodies carry
// no unbalanced `{`/`}`), so brace-matching the resource body is sound. (2) No
// `/* */` block comments are present; only `#`/`//` line comments are stripped.
// (3) `isSshProvisioned` matches `type = "ssh"` BEFORE the first `}` after
// `connection {` — i.e. the connection block carries no nested brace before
// `type`. If a future block reorders `type` after a `${…}`-bearing attribute the
// predicate fails OPEN (resource silently invisible to the guard); the
// `connection`-blocks here put `type` first, so it holds as of #4844.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve, join } from "path";
import {
  readFileSync,
  existsSync,
  readdirSync,
  writeFileSync,
  mkdtempSync,
  rmSync,
} from "fs";
import { tmpdir } from "os";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const INFRA_DIR = resolve(REPO_ROOT, "apps/web-platform/infra");
const WEB_PLATFORM_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);
const DEPLOY_PIPELINE_FIX_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-deploy-pipeline-fix.yml",
);

// Resources that are intentionally NOT auto-applied by either CI workflow.
// root_authorized_keys stays operator-local: it is the resource that appends the
// CI public key to root's authorized_keys, so it cannot be applied via the very
// bridge that key authorizes (firewall chicken-and-egg). See ci-ssh-key.tf and
// apply-web-platform-infra.yml's header.
const EXCLUSION_ALLOWLIST = new Set<string>(["root_authorized_keys"]);

// Sentinel: 8 in server.tf (7 hardening siblings + infra_config_handler_bootstrap)
// + root_authorized_keys in ci-ssh-key.tf. `>=` (not `===`) so adding a new
// SSH-provisioned resource raises the count without a brittle exact-match edit —
// the union-coverage assertion is what enforces correctness; this only guards
// against the predicate silently collapsing to zero (e.g. a parser regression).
const MIN_SSH_PROVISIONED = 9;

/** Strip `#` and `//` line comments, quote-aware, leaving string contents intact. */
function stripLineComment(line: string): string {
  let inStr = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (c === '"' && line[i - 1] !== "\\") {
      inStr = !inStr;
      continue;
    }
    if (!inStr && c === "#") return line.slice(0, i);
    if (!inStr && c === "/" && line[i + 1] === "/") return line.slice(0, i);
  }
  return line;
}

function stripComments(text: string): string {
  return text.split("\n").map(stripLineComment).join("\n");
}

interface TerraformDataResource {
  name: string;
  body: string;
}

/** Extract every `terraform_data` resource (name + brace-matched body) from
 *  already-comment-stripped HCL. */
function extractTerraformDataResources(
  stripped: string,
): TerraformDataResource[] {
  const header = /resource\s+"terraform_data"\s+"([A-Za-z0-9_]+)"\s*\{/g;
  const out: TerraformDataResource[] = [];
  let m: RegExpExecArray | null;
  while ((m = header.exec(stripped)) !== null) {
    const name = m[1];
    const openBrace = header.lastIndex - 1; // index of the `{`
    let depth = 0;
    let end = -1;
    for (let i = openBrace; i < stripped.length; i++) {
      if (stripped[i] === "{") depth++;
      else if (stripped[i] === "}") {
        depth--;
        if (depth === 0) {
          end = i;
          break;
        }
      }
    }
    if (end === -1) {
      throw new Error(`Unbalanced braces for terraform_data.${name}`);
    }
    out.push({ name, body: stripped.slice(openBrace, end + 1) });
  }
  return out;
}

/** SSH-provisioned = has a `connection { … type = "ssh" … }` block AND at least
 *  one `provisioner "<kind>" {` block. */
function isSshProvisioned(body: string): boolean {
  const hasSshConnection = /connection\s*\{[^}]*type\s*=\s*"ssh"/.test(body);
  const hasProvisioner = /provisioner\s+"[a-z-]+"\s*\{/.test(body);
  return hasSshConnection && hasProvisioner;
}

/** Collect `-target=terraform_data.<name>` resource names from a workflow file. */
function extractTargets(workflowText: string): Set<string> {
  const set = new Set<string>();
  for (const m of workflowText.matchAll(
    /-target=terraform_data\.([A-Za-z0-9_]+)/g,
  )) {
    set.add(m[1]);
  }
  return set;
}

function listInfraTfFiles(): string[] {
  return readdirSync(INFRA_DIR)
    .filter((f) => f.endsWith(".tf"))
    .map((f) => resolve(INFRA_DIR, f))
    .sort();
}

/** Names of every SSH-provisioned terraform_data resource across the given infra
 *  *.tf files (defaults to all of them). Parameterized so a test can drive a
 *  synthetic file through the REAL walk → extract → predicate chain end-to-end. */
function collectSshProvisioned(files: string[] = listInfraTfFiles()): string[] {
  const names: string[] = [];
  for (const file of files) {
    const stripped = stripComments(readFileSync(file, "utf8"));
    for (const r of extractTerraformDataResources(stripped)) {
      if (isSshProvisioned(r.body)) names.push(r.name);
    }
  }
  return names.sort();
}

/** Extract `concurrency.group`, `cancel-in-progress`, and the cloudflared pins
 *  from a workflow file (simple line scans — these keys are single-valued). */
function extractWorkflowInvariants(workflowText: string): {
  group: string | null;
  cancelInProgress: string | null;
  cloudflaredVersion: string | null;
  cloudflaredSha256: string | null;
} {
  const grab = (re: RegExp) => {
    const m = workflowText.match(re);
    return m ? m[1] : null;
  };
  return {
    group: grab(/^\s*group:\s*(\S+)\s*$/m),
    cancelInProgress: grab(/^\s*cancel-in-progress:\s*(\S+)\s*$/m),
    cloudflaredVersion: grab(/^\s*CLOUDFLARED_VERSION:\s*"([^"]+)"/m),
    cloudflaredSha256: grab(/^\s*CLOUDFLARED_SHA256:\s*"([^"]+)"/m),
  };
}

let sshProvisioned: string[];
let coveredUnion: Set<string>;

beforeAll(() => {
  expect(existsSync(INFRA_DIR)).toBe(true);
  expect(existsSync(WEB_PLATFORM_WORKFLOW)).toBe(true);
  expect(existsSync(DEPLOY_PIPELINE_FIX_WORKFLOW)).toBe(true);

  sshProvisioned = collectSshProvisioned();

  const webPlatformTargets = extractTargets(
    readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"),
  );
  const deployPipelineFixTargets = extractTargets(
    readFileSync(DEPLOY_PIPELINE_FIX_WORKFLOW, "utf8"),
  );
  coveredUnion = new Set<string>([
    ...webPlatformTargets,
    ...deployPipelineFixTargets,
    ...EXCLUSION_ALLOWLIST,
  ]);
});

describe("terraform -target parity — current state is covered", () => {
  test(`at least ${MIN_SSH_PROVISIONED} SSH-provisioned terraform_data resources are discovered`, () => {
    expect(sshProvisioned.length).toBeGreaterThanOrEqual(MIN_SSH_PROVISIONED);
  });

  test("every SSH-provisioned resource is in the target ∪ allowlist union", () => {
    const uncovered = sshProvisioned.filter((n) => !coveredUnion.has(n));
    expect(uncovered).toEqual([]);
  });

  test("the 7 hardening siblings + bootstrap + root_authorized_keys are all present", () => {
    for (const expected of [
      "disk_monitor_install",
      "resource_monitor_install",
      "fail2ban_tuning",
      "journald_persistent",
      "docker_seccomp_config",
      "apparmor_bwrap_profile",
      "orphan_reaper_install",
      "infra_config_handler_bootstrap",
      "root_authorized_keys",
    ]) {
      expect(sshProvisioned).toContain(expected);
    }
  });

  test("deploy_pipeline_fix (local-exec, no connection block) is NOT counted", () => {
    expect(sshProvisioned).not.toContain("deploy_pipeline_fix");
  });
});

describe("comment-strip is load-bearing (SpecFlow 2c non-vacuity)", () => {
  test("server.tf's `connection{type=\"ssh\"}` comment is stripped before matching", () => {
    const raw = readFileSync(resolve(INFRA_DIR, "server.tf"), "utf8");
    // The comment literal exists in the raw source…
    expect(raw).toContain('connection{type="ssh"}');
    // …and is gone after stripping, so it cannot be mis-parsed.
    expect(stripComments(raw)).not.toContain('connection{type="ssh"}');
  });

  test("a comment-only resource header does NOT create a phantom resource", () => {
    const synthetic = [
      "# resource \"terraform_data\" \"commented_out\" {",
      '#   connection { type = "ssh" }',
      '#   provisioner "remote-exec" { inline = ["true"] }',
      "# }",
    ].join("\n");
    const found = extractTerraformDataResources(stripComments(synthetic));
    expect(found).toEqual([]);
  });
});

describe("guard rejects an un-targeted SSH resource (synthetic fixture)", () => {
  // Verify FAILURE on a new SSH-provisioned resource that no workflow -targets,
  // WITHOUT editing the real .tf — parse a synthetic HCL string through the same
  // extractor + predicate, then run it through the same coverage check.
  const SYNTHETIC = `
resource "terraform_data" "synthetic_untargeted_ssh" {
  triggers_replace = sha256("x")

  connection {
    type        = "ssh"
    host        = hcloud_server.web.ipv4_address
    user        = "root"
    private_key = var.ci_ssh_private_key
    agent       = var.ci_ssh_private_key == null
  }

  provisioner "remote-exec" {
    inline = ["echo synthetic"]
  }
}
`;

  test("the synthetic resource parses as SSH-provisioned", () => {
    const parsed = extractTerraformDataResources(stripComments(SYNTHETIC));
    expect(parsed).toHaveLength(1);
    expect(parsed[0].name).toBe("synthetic_untargeted_ssh");
    expect(isSshProvisioned(parsed[0].body)).toBe(true);
  });

  test("coverage check flags it as uncovered (the guard would FAIL)", () => {
    const augmented = [...sshProvisioned, "synthetic_untargeted_ssh"];
    const uncovered = augmented.filter((n) => !coveredUnion.has(n));
    expect(uncovered).toEqual(["synthetic_untargeted_ssh"]);
  });

  // End-to-end fail-closed proof: drive the synthetic resource through the REAL
  // walk → extract → predicate → coverage chain (not a string injected into the
  // pre-computed array), so a regression in collectSshProvisioned's file
  // discovery is also caught. Write the synthetic .tf to an OS tmpdir (NOT the
  // infra dir — that would pollute the real walk for sibling tests).
  test("a real un-targeted SSH .tf file is discovered AND flagged uncovered", () => {
    const dir = mkdtempSync(join(tmpdir(), "tf-parity-"));
    try {
      const tmpTf = join(dir, "synthetic.tf");
      writeFileSync(tmpTf, SYNTHETIC, "utf8");
      const discovered = collectSshProvisioned([
        ...listInfraTfFiles(),
        tmpTf,
      ]);
      expect(discovered).toContain("synthetic_untargeted_ssh");
      const uncovered = discovered.filter((n) => !coveredUnion.has(n));
      expect(uncovered).toEqual(["synthetic_untargeted_ssh"]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });
});

// ─── Non-SSH resource coverage (#5566) ──────────────────────────────────────
// The original guard above only covers SSH-provisioned `terraform_data` resources.
// But apply-web-platform-infra.yml applies a TARGET-SCOPED plan: EVERY managed
// resource needs a matching `-target=` line or it silently never applies (no CI
// error). #5566: `github_actions_secret.supabase_access_token` was added to
// inngest.tf without a `-target` line → the SUPABASE_ACCESS_TOKEN GH secret was
// never created and only surfaced via the 12h drift cron. This block asserts
// every managed resource is reachable by a `-target=` line OR is in the
// documented operator-applied exclusion set below.

/** Every managed `resource "TYPE" "NAME"` address (excludes `data` sources). */
function extractAllResources(stripped: string): string[] {
  const re = /(?:^|\n)\s*resource\s+"([a-z0-9_]+)"\s+"([A-Za-z0-9_]+)"\s*\{/g;
  const out: string[] = [];
  let m: RegExpExecArray | null;
  while ((m = re.exec(stripped)) !== null) out.push(`${m[1]}.${m[2]}`);
  return out;
}

/** Every `-target=<type>.<name>` address (any resource type) in a workflow.
 *  Comment-strip FIRST so a DISABLED (commented-out) `-target=` line is NOT counted
 *  as covered — otherwise a `# -target=sentry_issue_alert.foo` would mask a real
 *  un-applied resource, the exact inert-target class this guard exists to catch.
 *  Verified no-op against the current workflows (no live target sits in a comment). */
function extractAllTargets(workflowText: string): Set<string> {
  const set = new Set<string>();
  for (const m of stripComments(workflowText).matchAll(
    /-target=([a-z0-9_]+\.[A-Za-z0-9_]+)/g,
  )) {
    set.add(m[1]);
  }
  return set;
}

// Resources intentionally NOT in the per-PR CI `-target=` allow-list.
// Documented in apply-web-platform-infra.yml's header (lines ~25-35):
//   - hcloud_* (server/volume/ssh_key) + root_authorized_keys are managed by the
//     operator's initial full apply + the drift detector, never per-PR.
const OPERATOR_APPLIED_EXCLUSIONS = new Set<string>([
  "hcloud_server.web",
  "hcloud_ssh_key.default",
  "hcloud_volume.workspaces",
  "hcloud_volume_attachment.workspaces",
  "terraform_data.root_authorized_keys",
  // #5274 Phase 2 (ADR-068) — the git-data host + its private network are a
  // one-time operator initial-apply, exactly like `hcloud_server.web` above. The
  // per-PR CI `-target` path bridges over SSH to the EXISTING web host; it cannot
  // provision a brand-new host, a new private network, or that host's transport
  // keypair/firewall. These land via the operator's full apply + the drift
  // detector, never per-PR — so they are operator-applied exclusions, not the
  // #5566 silent-un-applied class. (`doppler_secret.*` here ride the same apply
  // as the host they belong to; they are `doppler_secret`, not the CI-published
  // `doppler_service_token`/`github_actions_secret` types the test forces.)
  "hcloud_network.private",
  "hcloud_network_subnet.private",
  "hcloud_server_network.web",
  "hcloud_server_network.git_data",
  "tls_private_key.git_transport",
  "doppler_secret.git_transport_ssh_private_key",
  // #5817 PR B part 2 — the SECOND (provision) keypair + its prd secret ride the
  // SAME one-time git-data apply as git_transport above (ADR-068 amendment "PR B
  // bare-repo provisioning"). Operator-applied, never per-PR — the same class as
  // the transport keypair, not the #5566 silent-un-applied class.
  "tls_private_key.git_provision",
  "doppler_secret.git_provision_ssh_private_key",
  "hcloud_server.git_data",
  "hcloud_volume.git_data",
  "hcloud_volume_attachment.git_data",
  "hcloud_firewall.git_data",
  "hcloud_firewall_attachment.git_data",
  "betteruptime_heartbeat.git_data_prd",
  "doppler_secret.git_data_heartbeat_url_prd",
  // #5274 Phase 3 (ADR-068) — the multi-host cluster's new resources all ride the
  // operator's MAINTENANCE-WINDOW apply, exactly like hcloud_server.web + the
  // git-data keys above, NOT the #5566 per-PR-CI class:
  //   - the 3rd git-data key (REMOVE / Art.17 erasure) rides the git-data host
  //     apply, same class as git_transport/git_provision;
  //   - the spread placement group attaches to the RUNNING hcloud_server.web and
  //     forces a power-off reboot — a maintenance-window apply, same class as the
  //     host it groups;
  //   - the host↔host proxy TLS keypair/cert + their prd doppler_secrets belong to
  //     the web-host cluster (SANs = web host private IPs) and ride the same
  //     cluster apply (doppler_secret, not the CI-published token types the test
  //     forces).
  "tls_private_key.git_remove",
  "doppler_secret.git_remove_ssh_private_key",
  "hcloud_placement_group.web_spread",
  "tls_private_key.proxy_server",
  "tls_self_signed_cert.proxy_server",
  "doppler_secret.proxy_tls_key",
  "doppler_secret.proxy_tls_cert",
]);
// AUDIT-PENDING (#5577): these are un-targeted today but it is NOT yet confirmed
// whether that is intentional (operator-applied) or a forgotten allow-list entry
// (the #5566 class). Snapshotted here so this guard catches FUTURE misses; #5577
// classifies each into OPERATOR_APPLIED_EXCLUSIONS or the workflow `-target` list.
// Do NOT grow this set — a NEW un-targeted resource must fail the test, not be
// added here.
const AUDIT_PENDING_UNCOVERED = new Set<string>([
  "cloudflare_record.dkim_resend_inbound",
  "cloudflare_record.mx_receiving_inbound",
  "cloudflare_record.mx_send_inbound",
  "cloudflare_record.spf_send_inbound",
  "doppler_secret.live_verify_user_password",
  "random_password.live_verify_user",
]);

describe("terraform -target parity — ALL managed resources are reachable (non-SSH, #5566)", () => {
  let allResources: string[];
  let allTargets: Set<string>;

  beforeAll(() => {
    allResources = listInfraTfFiles().flatMap((f) =>
      extractAllResources(stripComments(readFileSync(f, "utf8"))),
    );
    allTargets = new Set<string>([
      ...extractAllTargets(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8")),
      ...extractAllTargets(readFileSync(DEPLOY_PIPELINE_FIX_WORKFLOW, "utf8")),
    ]);
  });

  test("every managed resource has a -target line, an operator-applied exclusion, or a pending-audit snapshot", () => {
    const uncovered = allResources.filter(
      (a) =>
        !allTargets.has(a) &&
        !OPERATOR_APPLIED_EXCLUSIONS.has(a) &&
        !AUDIT_PENDING_UNCOVERED.has(a),
    );
    // A non-empty list means a NEW resource was added without a -target line
    // (the #5566 silent-un-applied class) — add the -target to
    // apply-web-platform-infra.yml, or classify it into the exclusion set above.
    expect(uncovered).toEqual([]);
  });

  test("the #5566 resource (github_actions_secret.supabase_access_token) is now targeted", () => {
    // Regression anchor: the exact resource whose missing -target line was the
    // #5566 gap must stay covered.
    expect(allTargets.has("github_actions_secret.supabase_access_token")).toBe(
      true,
    );
  });

  test("every github_actions_secret + doppler_service_token is targeted (CI-publish types, no operator-apply ambiguity)", () => {
    const ciPublish = allResources.filter(
      (a) =>
        a.startsWith("github_actions_secret.") ||
        a.startsWith("doppler_service_token."),
    );
    expect(ciPublish.length).toBeGreaterThan(0); // non-vacuity
    const uncovered = ciPublish.filter((a) => !allTargets.has(a));
    expect(uncovered).toEqual([]);
  });

  test("guard FAILS on a synthetic new un-targeted resource (non-vacuity)", () => {
    const synthetic = `
resource "github_actions_secret" "synthetic_forgotten_secret" {
  repository      = "soleur"
  secret_name     = "SYNTHETIC"
  plaintext_value = var.x
}
`;
    const parsed = extractAllResources(stripComments(synthetic));
    expect(parsed).toEqual(["github_actions_secret.synthetic_forgotten_secret"]);
    const uncovered = parsed.filter(
      (a) =>
        !allTargets.has(a) &&
        !OPERATOR_APPLIED_EXCLUSIONS.has(a) &&
        !AUDIT_PENDING_UNCOVERED.has(a),
    );
    expect(uncovered).toEqual([
      "github_actions_secret.synthetic_forgotten_secret",
    ]);
  });
});

describe("concurrency-group + cloudflared-pin parity across the two workflows (#4844 P0)", () => {
  // The shared concurrency group is the SOLE state serializer (R2 has no lock).
  // GHA silently fails to serialize on divergent group strings, so assert the
  // two literals are byte-equal. Also assert both keep cancel-in-progress:false
  // and that the duplicated cloudflared pins (forwarded to the shared composite
  // action via `with:`) stay in sync.
  const EXPECTED_GROUP = "terraform-apply-web-platform-host";
  let wpi: ReturnType<typeof extractWorkflowInvariants>;
  let dpf: ReturnType<typeof extractWorkflowInvariants>;

  beforeAll(() => {
    wpi = extractWorkflowInvariants(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"));
    dpf = extractWorkflowInvariants(
      readFileSync(DEPLOY_PIPELINE_FIX_WORKFLOW, "utf8"),
    );
  });

  test("both workflows declare the IDENTICAL concurrency group literal", () => {
    expect(wpi.group).toBe(EXPECTED_GROUP);
    expect(dpf.group).toBe(EXPECTED_GROUP);
    expect(wpi.group).toBe(dpf.group);
  });

  test("both workflows keep cancel-in-progress: false", () => {
    expect(wpi.cancelInProgress).toBe("false");
    expect(dpf.cancelInProgress).toBe("false");
  });

  test("the cloudflared version + sha256 pins match across both workflows", () => {
    expect(wpi.cloudflaredVersion).not.toBeNull();
    expect(wpi.cloudflaredSha256).not.toBeNull();
    expect(wpi.cloudflaredVersion).toBe(dpf.cloudflaredVersion);
    expect(wpi.cloudflaredSha256).toBe(dpf.cloudflaredSha256);
  });
});

// ─── Sentry infra -target parity (#5884) ────────────────────────────────────
// `apps/web-platform/infra/sentry/*.tf` is applied by apply-sentry-infra.yml via
// an EXPLICIT `-target=` list (not a whole-directory apply), exactly like the
// #5566 web-platform case above. A new sentry_issue_alert / sentry_cron_monitor /
// sentry_uptime_monitor added to a .tf file but forgotten in that `-target` list
// ships in code, passes `terraform validate`, and is NEVER applied to Sentry — an
// inert alert/monitor with zero runtime signal. This bug has bitten twice already
// (learning 2026-06-12-detector-cron-must-route-…; again in #5875's
// sandbox_startup_failure). The #5566 guard above reads only the MAIN
// apps/web-platform/infra/ tree + its two workflows; it never sees infra/sentry/
// or apply-sentry-infra.yml. This block extends the identical mechanism
// (extractAllResources ∪ extractAllTargets + a frozen exclusion Set) to the Sentry
// apply pipeline. Reuses stripComments / extractAllResources / extractAllTargets.

const SENTRY_INFRA_DIR = resolve(REPO_ROOT, "apps/web-platform/infra/sentry");
const SENTRY_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-sentry-infra.yml",
);

// Import-only sentry_issue_alert placeholders (conditions_v2 = []), created in
// Sentry via `terraform import` of the legacy configure-sentry-alerts.sh rules
// (see issue-alerts.tf header + learning 2026-06-12-detector-cron-must-route-…).
// They are DELIBERATELY absent from apply-sentry-infra.yml's -target set — a
// target-scoped apply would try to CREATE a duplicate live rule. FROZEN: do NOT
// grow. A NEW apply-created alert (real conditions_v2) must be TARGETED in the
// workflow, never added here.
const SENTRY_IMPORT_ONLY_EXCLUSIONS = new Set<string>([
  "sentry_issue_alert.auth_callback_no_code_burst",
  "sentry_issue_alert.auth_exchange_code_burst",
  "sentry_issue_alert.auth_per_user_loop",
  "sentry_issue_alert.auth_signout_burst",
]);

// Floor sentinel — 67 managed resources today (44 cron + 4 uptime + 19 alert).
// `>=` (not `===`) so adding a resource raises the count without a brittle edit;
// the parity assertion enforces correctness, this only guards a parser collapse
// (regex/path regression that silently discovers zero resources).
const SENTRY_MIN_RESOURCES = 60;

function listSentryTfFiles(): string[] {
  return readdirSync(SENTRY_INFRA_DIR)
    .filter((f) => f.endsWith(".tf"))
    .map((f) => resolve(SENTRY_INFRA_DIR, f))
    .sort();
}

describe("terraform -target parity — Sentry infra issue-alerts/monitors (#5884)", () => {
  let sentryResources: string[];
  let sentryTargets: Set<string>;

  beforeAll(() => {
    expect(existsSync(SENTRY_INFRA_DIR)).toBe(true);
    expect(existsSync(SENTRY_WORKFLOW)).toBe(true);
    // NOTE: infra/sentry/ is a FLAT directory applied by a SINGLE workflow —
    // listSentryTfFiles is non-recursive and only apply-sentry-infra.yml is scanned.
    // No filter on resource TYPE: EVERY managed resource discovered under
    // infra/sentry/ must be reachable by a -target line (mirrors the #5566 block).
    // A future non-sentry_ resource (random_password, doppler_secret) added here
    // must fail CLOSED — filtering to `sentry_` would silently skip it, re-opening
    // the #5566 un-applied class. (`data "sentry_project"` is already excluded:
    // extractAllResources matches `resource "…"`, not `data "…"`.)
    sentryResources = listSentryTfFiles().flatMap((f) =>
      extractAllResources(stripComments(readFileSync(f, "utf8"))),
    );
    sentryTargets = extractAllTargets(readFileSync(SENTRY_WORKFLOW, "utf8"));
  });

  test(`discovers >= ${SENTRY_MIN_RESOURCES} managed sentry resources (non-vacuity)`, () => {
    expect(sentryResources.length).toBeGreaterThanOrEqual(SENTRY_MIN_RESOURCES);
  });

  test("every apply-created sentry resource is targeted (or a documented import-only exclusion)", () => {
    const uncovered = sentryResources.filter(
      (a) => !sentryTargets.has(a) && !SENTRY_IMPORT_ONLY_EXCLUSIONS.has(a),
    );
    // A non-empty list means a new sentry resource was added without a -target
    // line (the inert-alert class) — add the -target to apply-sentry-infra.yml,
    // or (only for a genuine import-only placeholder) add it to
    // SENTRY_IMPORT_ONLY_EXCLUSIONS.
    expect(uncovered).toEqual([]);
  });

  test("the #5875 regression anchor (sandbox_startup_failure) stays targeted", () => {
    expect(
      sentryTargets.has("sentry_issue_alert.sandbox_startup_failure"),
    ).toBe(true);
  });

  test("the #5884 regression anchor (github_webhook_founder_ambiguous) stays targeted", () => {
    // The apply-created alert whose missing -target line this PR fixed — the exact
    // resource that surfaced the guard's third real inert-alert instance. Pin it so
    // a future workflow edit cannot silently re-drop it back to inert.
    expect(
      sentryTargets.has("sentry_issue_alert.github_webhook_founder_ambiguous"),
    ).toBe(true);
  });

  test("the 4 import-only auth_* placeholders are present in .tf yet NOT targeted", () => {
    for (const a of SENTRY_IMPORT_ONLY_EXCLUSIONS) {
      expect(sentryResources).toContain(a);
      expect(sentryTargets.has(a)).toBe(false);
    }
  });

  test("guard FAILS on a synthetic un-targeted apply-created alert (non-vacuity)", () => {
    const synthetic = `resource "sentry_issue_alert" "synthetic_forgotten_alert" { project = "x" }`;
    const parsed = extractAllResources(stripComments(synthetic));
    expect(parsed).toEqual(["sentry_issue_alert.synthetic_forgotten_alert"]);
    const uncovered = parsed.filter(
      (a) => !sentryTargets.has(a) && !SENTRY_IMPORT_ONLY_EXCLUSIONS.has(a),
    );
    expect(uncovered).toEqual(["sentry_issue_alert.synthetic_forgotten_alert"]);
  });
});

// ─── `moved`-block / -target parity (#5887) ─────────────────────────────────
// Terraform processes EVERY `moved {}` block on any plan/apply. Under a
// target-scoped plan (`terraform plan -target=<addr>`, the shape both
// apply-web-platform-infra.yml and apply-deploy-pipeline-fix.yml use), Terraform
// REJECTS the plan if a pending `moved` source/target base address is excluded
// from the `-target=` set:
//     Error: Moved resource instances excluded by targeting
// #5877 (ADR-068 Phase 3) added four `moved {}` blocks to placement-group.tf,
// re-addressing the singleton web host + its volume/attachment/network to the
// `["web-1"]` for_each key. That wedged the targeted CI plan RED on every run.
//
// The fix is NOT to add these bases to the per-PR `-target=` allow-list:
// `hcloud_server.web` carries `placement_group_id` + `for_each = var.web_hosts`
// (server.tf), so targeting it in the UNATTENDED per-PR path forces a power-off
// reboot of the running prod host (and transitively creates the placement group
// / a second host). They are consumed by the operator's ADR-068 Phase-3
// MAINTENANCE-WINDOW apply, after which no pending moves remain and the targeted
// CI plan self-heals with zero workflow change. This guard therefore asserts
// every `moved` endpoint is EITHER `-target=`ed OR documented as operator-consumed
// — it must NOT encode "moved endpoint ⟹ must be in -target" (that would hard-code
// the rejected, reboot-bearing fix as the required state). See #5887 + the
// ADR-068 §Amendment (#5887).

/**
 * Every `moved { from = <addr> to = <addr> }` endpoint reduced to its BASE
 * resource address (a trailing `["key"]` for_each/index is dropped — the
 * `[a-z0-9_]+\.[A-Za-z0-9_]+` capture stops at the word boundary before `[`).
 * The four #5877 blocks are FLAT (no nested braces), so a flat
 * `moved\s*\{[^}]*\}` match is sufficient — the depth-counting
 * `extractTerraformDataResources` walker is not needed here.
 */
function extractMovedBases(stripped: string): string[] {
  const bases = new Set<string>();
  for (const block of stripped.match(/(?:^|\n)\s*moved\s*\{[^}]*\}/g) ?? []) {
    for (const m of block.matchAll(
      /\b(?:from|to)\s*=\s*([a-z0-9_]+\.[A-Za-z0-9_]+)/g,
    )) {
      bases.add(m[1]);
    }
  }
  return [...bases];
}

// The four #5877 `moved` bases, consumed by the operator's ADR-068 Phase-3
// maintenance-window apply (a routine per-PR `-target` add would reboot/replace
// the running host — see #5887). The 4th (`hcloud_server_network.web`) is not in
// the runtime error only because its Phase-2 resource is not yet in state → its
// move is a no-op with nothing to move; the guard accounts for all four so a
// future state-materialization does not re-wedge CI.
//
// DUAL-MAINTENANCE HAZARD: these four addresses also live in
// OPERATOR_APPLIED_EXCLUSIONS above (they are operator-applied for the #5566
// coverage guard too). The subset test below asserts the two hand-maintained
// sets never diverge on a resource rename.
const MOVED_OPERATOR_CONSUMED = new Set<string>([
  "hcloud_server.web",
  "hcloud_volume.workspaces",
  "hcloud_volume_attachment.workspaces",
  "hcloud_server_network.web",
]);

describe("terraform `moved`/-target parity — pending moves are accounted for (#5887)", () => {
  let movedBases: string[];
  let allTargets: Set<string>;

  beforeAll(() => {
    movedBases = listInfraTfFiles().flatMap((f) =>
      extractMovedBases(stripComments(readFileSync(f, "utf8"))),
    );
    allTargets = new Set<string>([
      ...extractAllTargets(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8")),
      ...extractAllTargets(readFileSync(DEPLOY_PIPELINE_FIX_WORKFLOW, "utf8")),
    ]);
  });

  test("every `moved` endpoint base is `-target=`ed OR documented operator-consumed", () => {
    // non-vacuity: the 4 #5877 bases. NOTE: once the operator ADR-068 Phase-3
    // cutover completes and the `moved {}` blocks are cleaned out of
    // placement-group.tf, this assertion red-lines BY DESIGN — drop it (and
    // MOVED_OPERATOR_CONSUMED) in that cleanup PR.
    expect(movedBases.length).toBeGreaterThan(0);
    const uncovered = movedBases.filter(
      (a) => !allTargets.has(a) && !MOVED_OPERATOR_CONSUMED.has(a),
    );
    // A non-empty list means a `moved {}` block re-addresses a resource that is
    // NEITHER in the workflow `-target=` allow-list NOR classified as
    // operator-consumed — i.e. it WEDGES every target-scoped CI apply with
    // "Moved resource instances excluded by targeting" (the #5887 class). Fix:
    // add a `-target=` line ONLY if the resource is safe to apply UNATTENDED
    // per-PR; otherwise classify it into MOVED_OPERATOR_CONSUMED and ship the
    // operator cutover WITH the migration. This test is also the regression
    // anchor — dropping a #5877 base from MOVED_OPERATOR_CONSUMED turns it red
    // (the base is not in allTargets), so no separate tautology test is added.
    expect(uncovered).toEqual([]);
  });

  test("guard FAILS on a synthetic forgotten `moved` block (non-vacuity)", () => {
    // Prove the guard bites: a moved block whose base is in NEITHER set is flagged.
    const synthetic = `
moved {
  from = hcloud_foo.bar
  to   = hcloud_foo.bar["k"]
}
`;
    const parsed = extractMovedBases(stripComments(synthetic));
    expect(parsed).toEqual(["hcloud_foo.bar"]); // base extracted, index stripped
    const uncovered = parsed.filter(
      (a) => !allTargets.has(a) && !MOVED_OPERATOR_CONSUMED.has(a),
    );
    expect(uncovered).toEqual(["hcloud_foo.bar"]);
  });

  test("MOVED_OPERATOR_CONSUMED is a subset of OPERATOR_APPLIED_EXCLUSIONS (dual-maintenance drift guard)", () => {
    // Closes the sync-drift hazard: the four addresses live in two hand-maintained
    // sets that must move in lockstep on a resource rename. Any moved-consumed base
    // that is NOT also operator-excluded means the sets diverged.
    const drifted = [...MOVED_OPERATOR_CONSUMED].filter(
      (a) => !OPERATOR_APPLIED_EXCLUSIONS.has(a),
    );
    expect(drifted).toEqual([]);
  });
});

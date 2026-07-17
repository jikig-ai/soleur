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
const MIN_SSH_PROVISIONED = 10; // #6122: +terraform_data.registry_insecure_config (zot insecure-registries, running-host SSH delivery)

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
  // `['"]?` tolerates a quoted `-target='addr["key"]'` (the shape the ADR-068
  // warm-standby job uses for its for_each addresses) — the capture still stops at
  // the word boundary before `[`, so a for_each target reduces to its BASE address
  // exactly like an unquoted one. Optional, so every existing UNQUOTED `-target=`
  // line captures identically (no change to prior results). Making quoted targets
  // visible here is what makes the `stripJob` job-aware boundary below LOAD-BEARING
  // rather than an accident of quoting.
  for (const m of stripComments(workflowText).matchAll(
    /-target=['"]?([a-z0-9_]+\.[A-Za-z0-9_]+)/g,
  )) {
    set.add(m[1]);
  }
  return set;
}

/**
 * Return the workflow text with a named top-level job block removed. Top-level
 * job keys are indented EXACTLY two spaces under `jobs:`; a job block runs from
 * its `  <id>:` header to the next `  <id>:` header (or EOF). Keeps the #5566 /
 * #5887 `-target` parity guards JOB-AWARE: the ADR-068 warm-standby DISPATCH job
 * (`warm_standby`) `-target`s the 6 additive resources that are already
 * OPERATOR_APPLIED_EXCLUSIONS, so folding its targets into `allTargets` would
 * WEAKEN the moved-block regression anchor (dropping `hcloud_server_network.web`
 * from MOVED_OPERATOR_CONSUMED must still turn the guard red). The auto-apply
 * (per-PR push) + SSH-bridge apply paths those guards actually cover live in the
 * `apply` job; the dispatch-only warm-standby path is a separate writer surface.
 */
function stripJob(workflowText: string, jobId: string): string {
  const out: string[] = [];
  let dropping = false;
  for (const line of workflowText.split("\n")) {
    if (/^ {2}[A-Za-z0-9_-]+:/.test(line)) {
      dropping = new RegExp(`^ {2}${jobId}:`).test(line);
    }
    if (!dropping) out.push(line);
  }
  return out.join("\n");
}

/**
 * Strip ALL dispatch-only jobs (warm_standby + web_2_recreate) from the workflow
 * before the #5566/#5887 coverage+moved guards build `allTargets`. BOTH are
 * additive/scoped `-target` writers whose targets are OPERATOR_APPLIED_EXCLUSIONS,
 * so folding them into `allTargets` would WEAKEN the moved-block anchor. CTO
 * must-fix 2: web_2_recreate carries `-target='hcloud_server.web["web-2"]'`, whose
 * base `hcloud_server.web` is a MOVED_OPERATOR_CONSUMED endpoint — if it leaked
 * into `allTargets`, dropping `hcloud_server.web` from MOVED_OPERATOR_CONSUMED
 * would no longer turn the moved guard red (masking a dropped moved-base). Strip
 * both dispatch jobs at EVERY site that builds the base-address coverage set.
 */
function stripDispatchJobs(workflowText: string): string {
  // #6178: inngest_host is a dispatch-only job (apply_target=inngest-host) that -targets the
  // net-new singleton host resources — strip it so its -targets do NOT broaden the per-merge
  // coverage set (else a real per-merge miss could be masked).
  // registry_host_replace (ADR-096): a dispatch-only scoped -replace job whose 5 -targets are
  // ALL registry OPERATOR_APPLIED_EXCLUSIONS. The coverage guards stay green whether or not it
  // is stripped (empirically verified — its targets are already exclusions), but strip it too
  // for the SAME reason every dispatch job is stripped: a dispatch writer surface must never
  // broaden the per-merge coverage anchor (belt-and-suspenders; keeps the parity boundary
  // uniform so a FUTURE registry -target that is NOT already an exclusion cannot silently mask
  // a per-merge miss). The inngest_host_replace job carries NO -target that isn't an exclusion
  // either, and is left folded-in historically; registry_host_replace is stripped explicitly
  // here as the current best practice for a new dispatch job.
  // git_data_host_replace (#6242, ADR-103): the same current best practice — its 5 -targets are
  // ALL git-data OPERATOR_APPLIED_EXCLUSIONS (server + network + both volume attachments +
  // firewall attachment), so stripping it does not change the coverage anchor today, but keeps
  // the parity boundary uniform so a FUTURE git-data -target that is NOT already an exclusion
  // cannot silently mask a per-merge miss.
  // registry_region_migrate (#6288): the sibling of registry_host_replace for a REGION move
  // (nbg1→hel1) — a dispatch-only scoped job whose 6 -targets are the SAME registry
  // OPERATOR_APPLIED_EXCLUSIONS. Strip it for the identical reason: a dispatch writer surface must
  // never broaden the per-merge coverage anchor.
  return stripJob(
    stripJob(
      stripJob(
        stripJob(
          stripJob(stripJob(workflowText, "warm_standby"), "web_2_recreate"),
          "inngest_host",
        ),
        "registry_host_replace",
      ),
      "registry_region_migrate",
    ),
    "git_data_host_replace",
  );
}

/** Inverse of stripJob: return ONLY the named job's block (header → next job/EOF). */
function extractJobBlock(workflowText: string, jobId: string): string {
  const out: string[] = [];
  let capturing = false;
  for (const line of workflowText.split("\n")) {
    if (/^ {2}[A-Za-z0-9_-]+:/.test(line)) {
      capturing = new RegExp(`^ {2}${jobId}:`).test(line);
    }
    if (capturing) out.push(line);
  }
  return out.join("\n");
}

/**
 * Full `-target=` values with the for_each `["key"]` PRESERVED (quoted or bare).
 * Distinct from extractAllTargets, which reduces to base addresses for the
 * coverage guards; the warm-standby guard needs the exact keyed addresses.
 */
function extractTargetsWithKeys(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(
    /-target=(?:'([^']+)'|"([^"]+)"|(\S+))/g,
  )) {
    out.push((m[1] ?? m[2] ?? m[3]).replace(/\\$/, ""));
  }
  return out;
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
  // #5274 Sub-PR 3.D (ADR-068) — the fresh LUKS git-data volume + its at-rest key +
  // its scoped read-only token ALL ride the operator's MAINTENANCE-WINDOW cutover apply
  // (the volume attaches to the RUNNING git-data host; guest-side cryptsetup unlocks it
  // at boot), NOT the #5566 per-PR-CI class. Same class as hcloud_volume.git_data + the
  // git-data doppler_secrets above.
  //   `doppler_service_token.git_data` is an OPERATOR-APPLIED token exception (see
  //   OPERATOR_APPLIED_TOKEN_EXCLUSIONS below): unlike doppler_service_token.write /
  //   .kb_drift (whose `.key` is published into a paired github_actions_secret consumed
  //   by CI, so #5566 forces them to be CI-targeted), this token is minted into an
  //   operator-created `prd_git_data` Doppler config and consumed by cloud-init on the
  //   git-data HOST. CI cannot apply it — the config does not exist until the operator
  //   creates it (runbook precondition), and CI cannot provision the host that reads it.
  "random_password.git_data_luks",
  "doppler_secret.git_data_luks_key",
  "hcloud_volume.git_data_luks",
  "hcloud_volume_attachment.git_data_luks",
  "doppler_service_token.git_data",
  // #6588 (ADR-119) — the ADDITIVE LUKS-at-rest /workspaces volume + its at-rest key +
  // its scoped read-only token ALL ride the operator's `workspaces-luks-cutover` dispatch
  // apply, NOT the #5566 per-PR-CI class. Same class as hcloud_volume.workspaces +
  // hcloud_volume_attachment.workspaces above (already excluded), which is the very volume
  // this one is cut over FROM.
  //   This exclusion is load-bearing for MERGEABILITY, not just hygiene: `host_creates`
  //   (#6416, destroy-guard-filter-web-platform.jq) is TYPE-scoped to hcloud_server OR
  //   hcloud_volume and is evaluated BEFORE the destroy_count sum, so `[ack-destroy]`
  //   deliberately cannot reach it. A net-new hcloud_volume that CI could plan would HALT
  //   the per-PR apply path.
  //   `doppler_service_token.workspaces_luks` is an OPERATOR-APPLIED token exception (see
  //   OPERATOR_APPLIED_TOKEN_EXCLUSIONS below), same class as doppler_service_token.git_data:
  //   it is minted into the operator-created `prd_workspaces_luks` Doppler config and read by
  //   the web-1 HOST at unlock time — never published into a paired github_actions_secret. The
  //   config does not exist until the operator creates it (runbook precondition), so CI cannot
  //   apply it. The dedicated config is what keeps the key OUT of the `--config prd` download
  //   that feeds `docker run --env-file` (CWE-522 — see workspaces-luks.tf).
  "random_password.workspaces_luks",
  "doppler_secret.workspaces_luks_key",
  "hcloud_volume.workspaces_luks",
  "hcloud_volume_attachment.workspaces_luks",
  "doppler_service_token.workspaces_luks",
  // #6604 — the daily luks-monitor probe's Better Stack heartbeat + its Doppler URL secret. Same
  // class as betteruptime_heartbeat.git_data_prd + doppler_secret.git_data_heartbeat_url_prd
  // (both excluded, applied together by the operator apply; the heartbeat is paused until the
  // operator unpauses at cutover). NOT part of the five-resource cutover gate allow-set, and never
  // rides the gated cutover -target set — so it does not affect the cutover destroy-guard.
  "betteruptime_heartbeat.workspaces_luks",
  "doppler_secret.workspaces_luks_heartbeat_url",
  // #6122 (ADR-096) — the zot registry host + its volume/network/firewall/creds/heartbeat
  // ALL ride the operator's initial full (untargeted) `terraform apply` + drift detector,
  // exactly like the git-data host above (CTO ruling 2026-07-06,
  // knowledge-base/project/specs/feat-registry-oidc-migration/apply-path-cto-ruling.md).
  // The per-PR CI `-target` path bridges over SSH to the EXISTING web host; it cannot
  // provision a brand-new host, a new private network attach, or that host's firewall.
  // NONE are in the workflow `-target` list. `doppler_secret.*` here (incl the host-token copies
  // in the ISOLATED `soleur-registry` project, #6122) ride the same host apply; they are
  // `doppler_secret`, not the CI-published `doppler_service_token`/`github_actions_secret` types
  // the #5566 test forces. `doppler_project.registry` (the isolated boot-credential project whose
  // own `prd` root holds ONLY the two ZOT tokens — true cross-project isolation from soleur/prd)
  // also rides the operator full apply: CI cannot create it (no host) and it is not a CI-published type.
  "hcloud_server.registry",
  "hcloud_volume.registry",
  "hcloud_volume_attachment.registry",
  "hcloud_server_network.registry",
  "hcloud_firewall.registry",
  "hcloud_firewall_attachment.registry",
  "random_password.zot_pull",
  "random_password.zot_push",
  "doppler_project.registry",
  "doppler_environment.registry_prd",
  "doppler_secret.zot_pull_token_registry",
  "doppler_secret.zot_push_token_registry",
  // #6244 — the isolated Better Stack Logs ingest token in soleur-registry/prd (same class as
  // the two ZOT tokens above: minted into the isolated project, consumed by the registry host's
  // cloud-init, NOT published to a per-PR CI target). Rides the registry-host-replace dispatch.
  "doppler_secret.registry_betterstack_logs_token",
  "doppler_secret.zot_registry_url",
  "doppler_secret.zot_pull_user",
  "doppler_secret.zot_pull_token",
  "doppler_secret.zot_push_user",
  "doppler_secret.zot_push_token",
  "betteruptime_heartbeat.registry_prd",
  "betteruptime_heartbeat.registry_disk_prd",
  "doppler_secret.zot_heartbeat_url_prd",
  "doppler_service_token.registry",
  // #6122 (ADR-096) — the CI-push ingress (CTO ruling 2026-07-06): CI reaches the private-net
  // zot host via the EXISTING `web` Cloudflare Tunnel + a NEW dedicated CF Access service token,
  // bridged with `cloudflared access tcp` (mirrors the SSH bridge). All operator-applied WITH the
  // registry host (an unattended per-PR apply must not mint a push credential + DNS for a host
  // that doesn't exist yet). The `..._config.web` ingress_rule EDIT rides the already-`-target`ed
  // config resource (not a new resource). The two doppler_secrets carry ignore_changes=[value]
  // (CF client_secret is write-once/empty-on-refresh, #4492) — still `doppler_secret`, not the
  // CI-published github_actions_secret/doppler_service_token types the #5566 test forces.
  "cloudflare_zero_trust_access_application.registry",
  "cloudflare_zero_trust_access_service_token.registry_push",
  "cloudflare_zero_trust_access_policy.registry_push_service_token",
  "cloudflare_record.registry",
  "doppler_secret.registry_push_access_token_id",
  "doppler_secret.registry_push_access_token_secret",
  // #6178 (ADR-100) — the dedicated Inngest singleton host. Same class as the registry/git-data
  // hosts: net-new host resources the per-PR CI `-target` path CANNOT provision (it bridges over
  // SSH to the EXISTING web host). All applied by the operator's full apply + the
  // `apply_target=inngest-host` dispatch job (which stripDispatchJobs excludes from the coverage
  // set, below). The doppler_project.inngest + its secrets are the ISOLATED soleur-inngest project
  // (its `prd` root holds ONLY inngest secrets — cross-project isolation from soleur/prd, #6122
  // precedent); they are `doppler_secret`/`doppler_project`, not the CI-published token types the
  // #5566 test forces. Fresh signing/event keys (AC-KEYROTATE — not reused from the co-located inngest.tf).
  "hcloud_server.inngest",
  "hcloud_volume.inngest_redis",
  "hcloud_volume_attachment.inngest_redis",
  "hcloud_server_network.inngest",
  "hcloud_firewall.inngest",
  "hcloud_firewall_attachment.inngest",
  "random_id.inngest_signing_key_dedicated",
  "random_id.inngest_event_key_dedicated",
  "random_password.inngest_redis_password_dedicated",
  "doppler_project.inngest",
  "doppler_environment.inngest_prd",
  "doppler_secret.inngest_signing_key_dedicated",
  "doppler_secret.inngest_event_key_dedicated",
  "doppler_secret.inngest_redis_password_dedicated",
  // #6197: arm64 Vector journal->Better Stack Logs shipper token, minted into the
  // ISOLATED soleur-inngest project's prd root (inngest-betterstack-token.tf). Applied by
  // the additive inngest_host dispatch job (stripDispatchJobs excludes that job from the
  // coverage set, so this exclusions entry — not the -target line — is the load-bearing coverage).
  "doppler_secret.inngest_betterstack_logs_token",
  "doppler_service_token.inngest",
  // #6545 — Grok Build dogfood host (headless Grok 4.5 trial). Gated by
  // `enable_grok_dogfood` (default false). Per-PR CI cannot birth this host
  // (#6416 host_creates tripwire). Provision is operator-local after free-slot
  // check: `TF_VAR_enable_grok_dogfood=true` + targeted apply. Same class as
  // registry/inngest/git-data: net-new host resources, never per-PR -target.
  // Public IP only (no private-net join — review P1).
  "hcloud_server.grok_dogfood",
  "hcloud_firewall.grok_dogfood",
  "hcloud_firewall_attachment.grok_dogfood",
]);
// Operator-applied doppler_service_token exceptions to the "every token is CI-targeted"
// assertion (#5566). A token belongs here ONLY when it is minted into an operator-created
// config for host consumption (NOT published into a CI-consumed github_actions_secret),
// so CI genuinely cannot and must not apply it. Do NOT grow this for a token that feeds
// a github_actions_secret — that is the #5566 silent-un-applied class and MUST be targeted.
const OPERATOR_APPLIED_TOKEN_EXCLUSIONS = new Set<string>([
  "doppler_service_token.git_data",
  // #6588 (ADR-119) — minted into the operator-created `prd_workspaces_luks` config and read by
  // the web-1 host at LUKS-unlock time (NOT published to a CI github_actions_secret). CI cannot
  // apply it — the config does not exist until the operator creates it. Same class as
  // doppler_service_token.git_data. The dedicated config is a SECURITY boundary, not hygiene:
  // web-1's cloud-init runs `doppler secrets download --config prd` into the TMPENV that feeds
  // `docker run --env-file`, so a key in shared `prd` would be readable via /proc/self/environ
  // by the agent container whose own data it encrypts (CWE-522). The mechanism is inheritance
  // DIRECTIONALITY (root → branch), NOT scope reduction: this token still resolves the full prd
  // set, exactly like the "leaky prd_registry branch config" named below — see #6167 and
  // learnings/security-issues/2026-07-07-doppler-branch-config-does-not-isolate-secrets.md.
  // It is free here because web-1 already carries a full-prd DOPPLER_TOKEN.
  "doppler_service_token.workspaces_luks",
  // #6122 (ADR-096) — minted into the ISOLATED `soleur-registry` project's `prd` root config
  // (TF-created via doppler_project.registry in the operator full apply; its own root holds ONLY
  // the two ZOT tokens — true cross-project isolation, NOT the leaky `prd_registry` branch config
  // it replaced), consumed by the registry host's cloud-init (NOT published to a CI
  // github_actions_secret). CI cannot apply it — no host to read it. Same class as
  // doppler_service_token.git_data.
  "doppler_service_token.registry",
  // #6178 (ADR-100) — minted into the ISOLATED soleur-inngest project's `prd` root config
  // (TF-created via doppler_project.inngest in the operator full apply), consumed by the inngest
  // host's cloud-init (NOT published to a CI github_actions_secret). CI cannot apply it — no host
  // to read it. Same class as doppler_service_token.git_data / .registry.
  "doppler_service_token.inngest",
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
      // JOB-AWARE: exclude the dispatch-only jobs (warm_standby + web_2_recreate)
      // — their additive/scoped for_each targets are OPERATOR_APPLIED_EXCLUSIONS
      // and must not broaden this coverage set (see stripDispatchJobs).
      ...extractAllTargets(
        stripDispatchJobs(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8")),
      ),
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

  test("every github_actions_secret + doppler_service_token is targeted (CI-publish types), except operator-applied host tokens", () => {
    const ciPublish = allResources.filter(
      (a) =>
        a.startsWith("github_actions_secret.") ||
        a.startsWith("doppler_service_token."),
    );
    expect(ciPublish.length).toBeGreaterThan(0); // non-vacuity
    // Operator-applied host tokens (minted into an operator-created config, consumed by
    // cloud-init — NOT published to a CI github_actions_secret) are exempt: CI cannot
    // apply them. Every OTHER token MUST be CI-targeted (the #5566 silent-un-applied class).
    const uncovered = ciPublish.filter(
      (a) => !allTargets.has(a) && !OPERATOR_APPLIED_TOKEN_EXCLUSIONS.has(a),
    );
    expect(uncovered).toEqual([]);
    // Non-vacuity for the carve-out: every excluded token must actually exist as a
    // managed resource (a stale exclusion would silently permit a real miss).
    for (const t of OPERATOR_APPLIED_TOKEN_EXCLUSIONS) {
      expect(allResources).toContain(t);
    }
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

  // #6604: the pin is now replicated into the git-data + workspaces-luks cutover/verify workflows
  // (all feed the same cf-tunnel-ssh-bridge composite). A pin bump that updated only the two apply
  // workflows would leave these on a stale version/SHA — the bridge download fails CLOSED (aborts),
  // not a silent hole, hence this is a drift tripwire. Assert EVERY workflow carrying the pin matches
  // the canonical (apply-web-platform-infra) value.
  test("the cloudflared pin matches across ALL workflows that declare it (#6604)", () => {
    const grabPin = (rel: string) => {
      const src = readFileSync(resolve(REPO_ROOT, rel), "utf8");
      return {
        version: /^\s*CLOUDFLARED_VERSION:\s*"([^"]+)"/m.exec(src)?.[1] ?? null,
        sha256: /^\s*CLOUDFLARED_SHA256:\s*"([^"]+)"/m.exec(src)?.[1] ?? null,
      };
    };
    const PIN_WORKFLOWS = [
      ".github/workflows/git-data-cutover.yml",
      ".github/workflows/workspaces-luks-cutover.yml",
      ".github/workflows/workspaces-luks-verify.yml",
    ];
    for (const wf of PIN_WORKFLOWS) {
      const pin = grabPin(wf);
      expect(pin.version, `${wf} CLOUDFLARED_VERSION`).toBe(wpi.cloudflaredVersion);
      expect(pin.sha256, `${wf} CLOUDFLARED_SHA256`).toBe(wpi.cloudflaredSha256);
    }
  });
});

// ─── Sentry infra -target parity (#5884) — REMOVED ──────────────────────────
// This block asserted that every resource under apps/web-platform/infra/sentry/
// appeared in apply-sentry-infra.yml's `-target=` list, with a frozen exclusion Set
// for the import-only auth_* placeholders (a target-scoped apply would try to CREATE
// a duplicate of an imported rule).
//
// apply-sentry-infra.yml now plans that root FULL: the `-target=` list is gone, so
// the plan universe is `state UNION config` and `declared ≡ applied` by construction.
// Every assertion here depended on a target set that no longer exists and could only
// be restated as a tautology. The inert-alert class it guarded is now structurally
// impossible, and the import-only placeholders need no exclusion — a full plan
// reconciles them from state rather than trying to re-create them.
//
// This retirement is SCOPED TO THE SENTRY ROOT ONLY. The #5566 web-platform block
// above and the #5887 `moved`-block parity below cover DIFFERENT infra roots that
// still apply via `-target=`; their guards remain load-bearing. Reintroduce a Sentry
// block here only if apply-sentry-infra.yml ever regains a `-target=` flag.

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
      // JOB-AWARE (P0.4 + CTO must-fix 2): the warm_standby job `-target`s
      // hcloud_server_network.web["web-1"/"web-2"]; the web_2_recreate job
      // `-target`s hcloud_server.web["web-2"] (base hcloud_server.web — itself a
      // MOVED_OPERATOR_CONSUMED endpoint). Folding EITHER into allTargets would let
      // a moved base be dropped from MOVED_OPERATOR_CONSUMED without turning this
      // guard red — weakening the #5877 anchor. Strip BOTH dispatch jobs.
      ...extractAllTargets(
        stripDispatchJobs(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8")),
      ),
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

// ─── ADR-068 warm-standby dispatch -target guard (this PR) ───────────────────
// The `apply_target=warm-standby` dispatch job (`warm_standby` in
// apply-web-platform-infra.yml) runs an ADDITIVE 6-target plan+apply through the
// shared R2 concurrency serializer, then triggers the host-side deploy fan-out to
// web-2. This guard pins the target set to EXACTLY the 6 additive resources and
// proves it can never carry web-1's placement-group reboot into the dispatch plan
// (no hcloud_server.* target ⇒ the destroy-guard-filter-web-platform.jq
// `reboot_updates` counter is 0 by construction). It also asserts the parity
// guards above stay JOB-AWARE (the warm-standby targets are NOT folded into
// `allTargets`), without weakening the moved-block boundary.
const WARM_STANDBY_TARGETS = [
  "hcloud_network.private",
  "hcloud_network_subnet.private",
  'hcloud_server_network.web["web-1"]',
  'hcloud_server_network.web["web-2"]',
  'hcloud_volume.workspaces["web-2"]',
  'hcloud_volume_attachment.workspaces["web-2"]',
];

describe("ADR-068 warm-standby dispatch -target set (additive; reboot_updates=0)", () => {
  let warmTargets: string[];
  let warmJobBlock: string;
  let fullBaseTargets: Set<string>;
  let strippedBaseTargets: Set<string>;

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    warmJobBlock = extractJobBlock(wf, "warm_standby");
    warmTargets = extractTargetsWithKeys(warmJobBlock);
    fullBaseTargets = extractAllTargets(wf);
    // Strip BOTH dispatch jobs: web_2_recreate ALSO -targets
    // hcloud_server_network.web["web-2"], so stripping only warm_standby would
    // leave the base in strippedBaseTargets and break the boundary assertion below.
    strippedBaseTargets = extractAllTargets(stripDispatchJobs(wf));
  });

  test("the warm_standby job -targets EXACTLY the 6 additive resources", () => {
    expect([...warmTargets].sort()).toEqual([...WARM_STANDBY_TARGETS].sort());
  });

  test("warm_standby REUSES the shared extracted poll, not an inline copy (AC8, #6040 migration lock)", () => {
    // #6040: warm_standby was migrated off its ~94-line inline baseline/trigger/
    // verify copy onto the shared deploy-status-fanout-verify.sh (the SAME poll the
    // web_2_recreate job runs). Lock the migration in so a future revert fails CI.
    expect(warmJobBlock).toContain("deploy-status-fanout-verify.sh");
    // Proof the inline verify-poll copy is GONE: its terminal-timeout sentinel now
    // lives ONLY in the shared script (+ that string never appeared elsewhere in the
    // warm_standby block). A revert that reinstates the inline poll turns this red.
    expect(warmJobBlock).not.toContain("did not report a fresh completion");
    // The former cross-step outputs the inline copy published are gone: the summary
    // step must read the shared verify step's deployed_tag, and no dangling
    // steps.trigger.outputs.* / steps.baseline.outputs.* reference may remain.
    expect(warmJobBlock).toContain("steps.verify.outputs.deployed_tag");
    expect(warmJobBlock).not.toContain("steps.trigger.outputs");
    expect(warmJobBlock).not.toContain("steps.baseline.outputs");
  });

  test("warm-standby targets NO hcloud_server.* — reboot_updates=0 by construction", () => {
    // reboot_updates only counts placement_group_id/server_type in-place updates
    // on hcloud_server.* (destroy-guard-filter-web-platform.jq:135). The warm-standby
    // set attaches the private network (hcloud_server_network — a DIFFERENT type) +
    // the web-2 volume; it never targets hcloud_server.web, so web-1's placement
    // reboot cannot enter the dispatch plan and the plan-scoped guard's
    // reboot_updates is 0. `\.` after hcloud_server is load-bearing: it must NOT
    // match hcloud_server_network.
    const serverTargets = warmTargets.filter((t) => /^hcloud_server\./.test(t));
    expect(serverTargets).toEqual([]);
    // non-vacuity: the network attach IS present (the filter above is not empty
    // merely because the whole set is empty).
    expect(
      warmTargets.some((t) => t.startsWith("hcloud_server_network.web")),
    ).toBe(true);
  });

  test("every warm-standby target's base address is an OPERATOR_APPLIED_EXCLUSION", () => {
    // The 6 additive resources are excluded from BOTH auto-apply target sets
    // (P0.4) — the dispatch is the ONLY path that applies them. If a future edit
    // pointed the warm-standby job at a non-excluded resource this turns red.
    for (const t of warmTargets) {
      const base = t.replace(/\[.*$/, "");
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(base)).toBe(true);
    }
  });

  test("the warm_standby job still RUNS the reboot_updates destroy-guard before apply (runtime-guard anchor)", () => {
    // Defense-in-depth (optional, this PR): the static "no hcloud_server.* target"
    // reasoning above wouldn't notice if the RUNTIME destroy-guard check were
    // deleted from the plan step. `-target` still pulls hcloud_server.web into the
    // plan graph transitively, so the runtime reboot_updates=0 gate is the real
    // backstop. Anchor its presence so a future edit that drops it turns this red.
    expect(warmJobBlock).toContain("destroy-guard-filter-web-platform.jq");
    expect(warmJobBlock).toContain("reboot_updates");
    // The gate must ABORT on a reboot (rc-bearing check), not merely compute the
    // counter — pin the `reboot_updates -gt 0` guard expression itself.
    expect(warmJobBlock).toMatch(/reboot_updates"?\s*-gt\s*0/);
  });

  test("the parity guards stay JOB-AWARE: warm-standby targets are NOT in the stripped allTargets", () => {
    // Load-bearing boundary (P0.4): with extractAllTargets now quote-tolerant, a
    // WHOLE-file scan DOES see the warm-standby base hcloud_server_network.web;
    // once stripJob removes the dispatch job it is GONE. The #5566/#5887 guards use
    // the stripped form, so the moved-block regression anchor keeps its teeth.
    expect(fullBaseTargets.has("hcloud_server_network.web")).toBe(true);
    expect(strippedBaseTargets.has("hcloud_server_network.web")).toBe(false);
  });
});

describe("hcloud_server.web reboot deferral — placement_group_id stays in ignore_changes (#5887 zero-downtime CI unwedge)", () => {
  // Removing `placement_group_id` from hcloud_server.web's lifecycle.ignore_changes
  // re-introduces the pending web-1 placement-group attach (0 -> web_spread) into
  // every targeted plan. That attach is a reboot-forcing in-place `update` on the
  // RUNNING prod host, which the destroy-guard `reboot_updates` counter (#5911,
  // tests/scripts/lib/destroy-guard-filter-web-platform.jq) HALTS with rc=2 —
  // re-wedging BOTH apply pipelines (the #5887 wedge). The GA maintenance-window PR
  // removes this entry ON PURPOSE to take the reboot on a drained host (blue-green);
  // until then it must stay. This static guard fails if a future edit drops it.
  function hcloudServerWebBody(): string {
    const stripped = stripComments(
      readFileSync(resolve(INFRA_DIR, "server.tf"), "utf8"),
    );
    const header = /resource\s+"hcloud_server"\s+"web"\s*\{/g;
    const m = header.exec(stripped);
    if (!m) throw new Error("hcloud_server.web block not found in server.tf");
    // Brace-match the body (terraform ${...} interpolations are balanced, so
    // string-embedded braces net to zero — same approach as extractTerraformDataResources).
    let depth = 1;
    let i = m.index + m[0].length;
    const start = i;
    for (; i < stripped.length && depth > 0; i++) {
      if (stripped[i] === "{") depth++;
      else if (stripped[i] === "}") depth--;
    }
    if (depth !== 0) throw new Error("Unbalanced braces for hcloud_server.web");
    return stripped.slice(start, i - 1);
  }

  test("lifecycle.ignore_changes includes placement_group_id", () => {
    const body = hcloudServerWebBody();
    const ic = /ignore_changes\s*=\s*\[([^\]]*)\]/.exec(body);
    expect(ic).not.toBeNull();
    const entries = (ic as RegExpExecArray)[1]
      .split(",")
      .map((s) => s.trim())
      .filter(Boolean);
    expect(entries).toContain("placement_group_id");
    // Non-vacuity: the pre-existing import-artifact entries (#967) are still present,
    // proving we parsed the real ignore_changes list, not an empty/wrong block.
    expect(entries).toContain("user_data");
  });
});

// ─── web-2-recreate dispatch -target/-replace guard (this PR, AC7/AC10c) ─────
// The `apply_target=web-2-recreate` dispatch job (`web_2_recreate`) runs a SCOPED,
// GUARDED `terraform apply -replace='hcloud_server.web["web-2"]'` + the 3 web-2
// `-target`s to re-run web-2's first-boot cloud-init and bind :9000. This guard
// pins the target/replace set to EXACTLY the web-2 addresses and proves it can
// never carry a web-1 address (the sole live origin) into the plan. The DATA
// volume (hcloud_volume.workspaces["web-2"]) must NOT be in the set (0-destroy).
const WEB2_RECREATE_TARGETS = [
  'hcloud_server.web["web-2"]',
  'hcloud_server_network.web["web-2"]',
  'hcloud_volume_attachment.workspaces["web-2"]',
];
const WEB2_RECREATE_REPLACE = 'hcloud_server.web["web-2"]';

/** Every `-replace=<addr>` value (quoted or bare) in a workflow-job block. */
function extractReplaceAddrs(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(
    /-replace=(?:'([^']+)'|"([^"]+)"|(\S+))/g,
  )) {
    out.push((m[1] ?? m[2] ?? m[3]).replace(/\\$/, ""));
  }
  return out;
}

describe("web-2-recreate dispatch -target/-replace set (scoped; web-1 never targeted)", () => {
  let recreateTargets: string[];
  let recreateJobBlock: string;
  let replaceAddrs: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    recreateJobBlock = extractJobBlock(wf, "web_2_recreate");
    recreateTargets = extractTargetsWithKeys(recreateJobBlock);
    replaceAddrs = extractReplaceAddrs(recreateJobBlock);
  });

  test("the web_2_recreate job -targets EXACTLY the 3 web-2 resources", () => {
    expect([...recreateTargets].sort()).toEqual([...WEB2_RECREATE_TARGETS].sort());
  });

  test("every web-2-recreate target's base address is an OPERATOR_APPLIED_EXCLUSION", () => {
    for (const t of recreateTargets) {
      const base = t.replace(/\[.*$/, "");
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(base)).toBe(true);
    }
  });

  test('hcloud_volume.workspaces["web-2"] (the DATA volume) is NOT in the recreate set', () => {
    expect(recreateTargets).not.toContain('hcloud_volume.workspaces["web-2"]');
    // base form absent too — the volume must be 0-destroy (AC3 / AC15).
    expect(recreateTargets.map((t) => t.replace(/\[.*$/, ""))).not.toContain(
      "hcloud_volume.workspaces",
    );
  });

  test("the -replace address is EXACTLY the web-2 server (never web-1)", () => {
    expect(replaceAddrs).toEqual([WEB2_RECREATE_REPLACE]);
  });

  test("NO web-1 address appears in the recreate job's -target/-replace set (blast-radius guard)", () => {
    const all = [...recreateTargets, ...replaceAddrs];
    const web1 = all.filter((a) => a.includes('"web-1"'));
    expect(web1).toEqual([]);
    // non-vacuity: the set is non-empty and DOES carry web-2 addresses.
    expect(all.some((a) => a.includes('"web-2"'))).toBe(true);
  });

  test("guard would FAIL if a web-1 address were added to the recreate set (non-vacuity)", () => {
    // Prove the "no web-1" filter above bites: a poisoned set with a web-1 target
    // is flagged. Guards against the filter silently matching nothing.
    const poisoned = [...WEB2_RECREATE_TARGETS, 'hcloud_server.web["web-1"]'];
    const web1 = poisoned.filter((a) => a.includes('"web-1"'));
    expect(web1).toEqual(['hcloud_server.web["web-1"]']);
  });

  test("the recreate job runs the sourced web2_recreate_gate + coherence preflight before apply", () => {
    expect(recreateJobBlock).toContain("web2-recreate-gate.sh");
    expect(recreateJobBlock).toContain("web2_recreate_gate");
    // The LOAD-BEARING coherence preflight runs BEFORE any -replace.
    expect(recreateJobBlock).toContain("web2-recreate-preflight.sh");
  });

  test("verify REUSES the shared extracted poll, not a re-derived copy (AC10c)", () => {
    // The new job invokes the shared script rather than inlining the poll body.
    expect(recreateJobBlock).toContain("deploy-status-fanout-verify.sh");
    // Proof it did NOT copy-paste the warm_standby poll: the poll-loop timeout
    // sentinel ("did not report a fresh completion") lives only in the shared
    // script + warm_standby's inline copy, never in this job block.
    expect(recreateJobBlock).not.toContain(
      "did not report a fresh completion",
    );
    // The shared script carries the load-bearing invariants (single-peer guard +
    // terminal exit 1 on timeout — no green-on-timeout).
    const shared = readFileSync(
      resolve(INFRA_DIR, "scripts/deploy-status-fanout-verify.sh"),
      "utf8",
    );
    expect(shared).toContain("ROSTER_COUNT");
    expect(shared).toMatch(/ROSTER_COUNT"?\s*-ne\s*2/);
    expect(shared).toMatch(
      /did not report a fresh completion[\s\S]*?exit 1/,
    );
  });
});

// ─── registry-host-replace dispatch -target/-replace guard (ADR-096) ─────────
// The `apply_target=registry-host-replace` dispatch job (`registry_host_replace`) runs a
// SCOPED, GUARDED `terraform apply -replace='hcloud_server.registry'` + the 6 registry
// `-target`s (5 host resources + the #6244 isolated Better Stack Logs token secret) to re-run
// the registry host's cloud-init (disk-heartbeat cron + storage.retention)
// and apply any pending storage-volume resize WITHOUT destroying the zot OCI store. This guard
// pins the target/replace set to EXACTLY the registry addresses, proves the store volume is
// IN the set (so its size update can ride in) yet PRESERVED by the sourced gate, and asserts
// the dispatch job is stripped from the per-merge coverage anchor (stripDispatchJobs).
const REGISTRY_REPLACE_TARGETS = [
  "hcloud_server.registry",
  "hcloud_server_network.registry",
  "hcloud_volume_attachment.registry",
  "hcloud_firewall_attachment.registry",
  "hcloud_volume.registry",
  // #6244 — the isolated Better Stack Logs token secret MUST ride the SAME dispatch: the amended
  // 3-secret boot guard FATALs (zot never launches) if the token is absent from the isolated
  // config when the replaced host boots. Pure-create on first apply, no-op thereafter.
  "doppler_secret.registry_betterstack_logs_token",
];
const REGISTRY_REPLACE_REPLACE = "hcloud_server.registry";

describe("registry-host-replace dispatch -target/-replace set (scoped; store preserved)", () => {
  let registryTargets: string[];
  let registryJobBlock: string;
  let replaceAddrs: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    registryJobBlock = extractJobBlock(wf, "registry_host_replace");
    registryTargets = extractTargetsWithKeys(registryJobBlock);
    replaceAddrs = extractReplaceAddrs(registryJobBlock);
  });

  test("the registry_host_replace job -targets EXACTLY the 6 registry-replace resources", () => {
    expect([...registryTargets].sort()).toEqual(
      [...REGISTRY_REPLACE_TARGETS].sort(),
    );
  });

  test("the -replace address is EXACTLY the registry server", () => {
    expect(replaceAddrs).toEqual([REGISTRY_REPLACE_REPLACE]);
  });

  test("every registry-replace target's base address is an OPERATOR_APPLIED_EXCLUSION", () => {
    for (const t of registryTargets) {
      const base = t.replace(/\[.*$/, "");
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(base)).toBe(true);
    }
  });

  test("the zot store volume (hcloud_volume.registry) IS in the set (so its size update rides in)", () => {
    // Unlike web-2-recreate (data volume EXCLUDED), the registry store volume MUST be in the
    // -target set — the server user_data interpolates its id, and the gate PRESERVES it
    // (size-update-only). Its presence is what lets the pending resize apply in one dispatch.
    expect(registryTargets).toContain("hcloud_volume.registry");
  });

  test("the registry job runs the sourced registry_host_replace_gate before apply", () => {
    expect(registryJobBlock).toContain("registry-host-replace-gate.sh");
    expect(registryJobBlock).toContain("registry_host_replace_gate");
    // The ONLY `ack-destroy` mentions are the prose disclaimers that there is NO bypass —
    // there is no conditional that skips the gate on an [ack-destroy] marker.
    expect(registryJobBlock).toContain("NO [ack-destroy] bypass");
  });

  test("stripDispatchJobs removes the registry_host_replace job's -targets from the coverage set", () => {
    // Belt-and-suspenders (Phase 3.3): a dispatch writer surface must not broaden the
    // per-merge coverage anchor. After stripping, none of the 6 registry -targets appear.
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const strippedTargets = extractAllTargets(stripDispatchJobs(wf));
    for (const addr of REGISTRY_REPLACE_TARGETS) {
      // hcloud_volume.registry etc. are exclusions, so absence from the stripped set is the
      // load-bearing proof the strip took effect (non-vacuity: they ARE present unstripped).
      expect(strippedTargets.has(addr)).toBe(false);
    }
    // non-vacuity: the whole-file (unstripped) scan DOES see the registry server target.
    const fullTargets = extractAllTargets(wf);
    expect(fullTargets.has("hcloud_server.registry")).toBe(true);
  });

  test("no registry address leaked into MOVED_OPERATOR_CONSUMED", () => {
    for (const addr of REGISTRY_REPLACE_TARGETS) {
      expect(MOVED_OPERATOR_CONSUMED.has(addr)).toBe(false);
    }
  });
});

// The `apply_target=git-data-host-replace` dispatch job (`git_data_host_replace`, #6242, ADR-103)
// runs a SCOPED, GUARDED `terraform apply -replace='hcloud_server.git_data'` + 5 `-target`s
// (server + private NIC + BOTH volume attachments + firewall attachment) to re-run the git-data
// host's cloud-init WITHOUT SSH. UNLIKE registry, BOTH data volumes (hcloud_volume.git_data* ) and
// the LUKS passphrase are PRESERVED BY OMISSION — deliberately NOT in the -target set. This guard
// pins the target/replace set to EXACTLY the 5 git-data addresses, proves NEITHER data volume is in
// the set (the omission that preserves them), and asserts the dispatch job is stripped from the
// per-merge coverage anchor. It locks the load-bearing invariant that the workflow's 5 `-target`
// lines correspond 1:1 to the gate's 5-member allow-set (a drift on either side would otherwise
// only surface at live-dispatch time).
const GIT_DATA_REPLACE_TARGETS = [
  "hcloud_server.git_data",
  "hcloud_server_network.git_data",
  "hcloud_volume_attachment.git_data",
  "hcloud_volume_attachment.git_data_luks",
  "hcloud_firewall_attachment.git_data",
];
const GIT_DATA_REPLACE_REPLACE = "hcloud_server.git_data";
// The two data volumes preserved by OMISSION — asserted ABSENT from the -target set.
const GIT_DATA_PRESERVED_VOLUMES = [
  "hcloud_volume.git_data",
  "hcloud_volume.git_data_luks",
];

describe("git-data-host-replace dispatch -target/-replace set (scoped; BOTH volumes preserved by omission)", () => {
  let gitDataTargets: string[];
  let gitDataJobBlock: string;
  let replaceAddrs: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    gitDataJobBlock = extractJobBlock(wf, "git_data_host_replace");
    gitDataTargets = extractTargetsWithKeys(gitDataJobBlock);
    replaceAddrs = extractReplaceAddrs(gitDataJobBlock);
  });

  test("the git_data_host_replace job -targets EXACTLY the 5 git-data-replace resources", () => {
    expect([...gitDataTargets].sort()).toEqual(
      [...GIT_DATA_REPLACE_TARGETS].sort(),
    );
  });

  test("the -replace address is EXACTLY the git-data server", () => {
    expect(replaceAddrs).toEqual([GIT_DATA_REPLACE_REPLACE]);
  });

  test("the target set EXACTLY equals the gate's 5-member allow-set (job↔gate parity)", () => {
    // The load-bearing invariant: the workflow's -target lines must correspond 1:1 to the sourced
    // gate's allow-set. Extract the allow[] array from the gate lib and compare.
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/git-data-host-replace-gate.sh"),
      "utf8",
    );
    const allowBlock = gateSrc.match(/def allow:\s*\[([^\]]+)\]/);
    expect(allowBlock).not.toBeNull();
    const allowMembers = [...allowBlock![1].matchAll(/"([^"]+)"/g)].map(
      (m) => m[1],
    );
    expect([...allowMembers].sort()).toEqual([...gitDataTargets].sort());
  });

  test("NEITHER data volume is in the -target set (preserved by omission)", () => {
    // The deliberate divergence from registry (whose store volume IS in-scope for a resize). An
    // untargeted resource cannot be planned for destroy, so omission is what preserves the stores.
    for (const vol of GIT_DATA_PRESERVED_VOLUMES) {
      expect(gitDataTargets).not.toContain(vol);
    }
  });

  test("every git-data-replace target's base address is an OPERATOR_APPLIED_EXCLUSION", () => {
    for (const t of gitDataTargets) {
      const base = t.replace(/\[.*$/, "");
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(base)).toBe(true);
    }
  });

  test("the git-data job runs the sourced git_data_host_replace_gate before apply", () => {
    expect(gitDataJobBlock).toContain("git-data-host-replace-gate.sh");
    expect(gitDataJobBlock).toContain("git_data_host_replace_gate");
    // The ONLY `ack-destroy` mentions are the prose disclaimers that there is NO bypass.
    expect(gitDataJobBlock).toContain("NO [ack-destroy] bypass");
  });

  test("stripDispatchJobs removes the git_data_host_replace job's -targets from the coverage set", () => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const strippedTargets = extractAllTargets(stripDispatchJobs(wf));
    for (const addr of GIT_DATA_REPLACE_TARGETS) {
      expect(strippedTargets.has(addr)).toBe(false);
    }
    // non-vacuity: the whole-file (unstripped) scan DOES see the git-data server target.
    const fullTargets = extractAllTargets(wf);
    expect(fullTargets.has("hcloud_server.git_data")).toBe(true);
  });

  test("no git-data address leaked into MOVED_OPERATOR_CONSUMED", () => {
    for (const addr of GIT_DATA_REPLACE_TARGETS) {
      expect(MOVED_OPERATOR_CONSUMED.has(addr)).toBe(false);
    }
  });
});

// ─── FIX B: betteruptime_team_member.ops per-merge coverage anchor ────────────
describe("betteruptime_team_member.ops is a per-merge -targeted managed resource (FIX B)", () => {
  test("the resource exists in uptime-alerts.tf and is covered by a per-merge -target", () => {
    const resources = listInfraTfFiles().flatMap((f) =>
      extractAllResources(stripComments(readFileSync(f, "utf8"))),
    );
    expect(resources).toContain("betteruptime_team_member.ops");
    // It auto-applies on merge, so its -target lives in the NON-stripped apply job — the
    // stripped coverage set (what the #5566 guard uses) must still see it.
    const strippedTargets = extractAllTargets(
      stripDispatchJobs(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8")),
    );
    expect(strippedTargets.has("betteruptime_team_member.ops")).toBe(true);
    // It is NOT an operator-applied exclusion (it is auto-appliable).
    expect(OPERATOR_APPLIED_EXCLUSIONS.has("betteruptime_team_member.ops")).toBe(
      false,
    );
  });
});

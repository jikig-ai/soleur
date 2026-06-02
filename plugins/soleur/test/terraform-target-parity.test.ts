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
// COMMENT-STRIP (SpecFlow 2c, P0): server.tf's leading comment for
// infra_config_handler_bootstrap contains the literal `connection{type="ssh"}`.
// `#`/`//` line comments are stripped before matching so that comment cannot
// false-count (and mask a real miss). A non-vacuity test below proves the strip
// is load-bearing.
//
// DOCUMENTED LIMITATION (SpecFlow 2b): this guard is ONE-DIRECTIONAL — it proves
// every SSH resource is in the union, NOT that every `-target=` line points at a
// live resource. A stale/typo'd `-target=` is NOT caught here (terraform exits 0
// on "no resources matched"). A reverse-direction guard is out of scope.
//
// PARSER ASSUMPTIONS: HCL braces are balanced even inside the remote-exec inline
// strings in these files (`${…}` interpolations and heredoc bodies carry no
// unbalanced `{`/`}`), so brace-matching the resource body is sound. No `/* */`
// block comments are present in these files; only `#`/`//` line comments are
// stripped. Both hold for apps/web-platform/infra/*.tf as of #4844.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync, readdirSync } from "fs";

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

/** Names of every SSH-provisioned terraform_data resource across all infra *.tf. */
function collectSshProvisioned(): string[] {
  const names: string[] = [];
  for (const file of listInfraTfFiles()) {
    const stripped = stripComments(readFileSync(file, "utf8"));
    for (const r of extractTerraformDataResources(stripped)) {
      if (isSshProvisioned(r.body)) names.push(r.name);
    }
  }
  return names.sort();
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
});

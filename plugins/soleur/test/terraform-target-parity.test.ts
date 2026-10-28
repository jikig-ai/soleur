// Terraform `-target=` parity guard (#4844).
//
// Every SSH-provisioned `terraform_data.*` resource in apps/web-platform/infra/*.tf
// MUST be reachable by an auto-apply path, or it silently drifts: the GitHub
// runner egress IP is not in var.admin_ips, so these resources are EXCLUDED from
// the main saved-tfplan apply and only land via an explicit `-target=` over the
// CF Tunnel SSH bridge. This test asserts each such resource appears in the UNION
// of:
//   • apply-web-platform-infra.yml's SSH `-target=` set (the server.tf siblings,
//     applied over the CF Tunnel SSH bridge; count derived, never restated)
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
//
// THIS SUITE'S NAME UNDERSTATES ITS CONTENTS, deliberately and with the cost recorded. Beyond
// `-target=` parity it also owns two invariants of `apply-web-platform-infra.yml` that have
// nowhere better to live: the workflow's NOTIFICATION CHANNEL (`the ssh_token_gate green-skip has
// a channel (#7539)`, and since #7586 `apply-web-platform-infra has a failure channel`) and its
// ARM-gate BUDGET (`the ARM gate's deadlines fit its job`, #7587). They are here rather than in a
// new file because the channel guards share `extractJobBlock` / `extractStep` with the parity
// guards and must not drift from them — a second file would re-implement both helpers and the two
// copies would diverge. The workflow points back at this file from the ARM gate's own comment.

import { describe, test, expect, beforeAll } from "bun:test";
import { parse as parseYaml } from "yaml";
import { resolve, join, posix, relative } from "path";
import {
  readFileSync,
  existsSync,
  readdirSync,
  lstatSync,
  writeFileSync,
  mkdtempSync,
  mkdirSync,
  rmSync,
  symlinkSync,
} from "fs";
import { tmpdir } from "os";
import { spawnSync } from "child_process";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
/** Suite-level cardinality floor — see the final describe in this file (#7656 C8). */
// Exactly `grep -cE '^\s*test\(' plugins/soleur/test/terraform-target-parity.test.ts` (the final describe counts the
// same pattern). Re-derive with that command and edit this constant in the same change as any added or removed test.
// 278 -> 266 (#8285 PR B, -12): the "inngest-backstop-retire dispatch" describe (17 tests: registration, id-pin ordering,
// confirm literal, environment, phase gating, destroy preconditions, literal state-only -targets, mutex, timeout, strip,
// ...) was replaced by a 5-test describe (G1 "stays retired" across every workflow, G1b deleted files/variables, B9 mutex
// over the three surviving surfaces, B6, B5): the job those rows graded no longer exists. The floor is exact
// (grep -cE '^\s*test\(' = 266). Each deleted row's mutation, and what kills it now, is in the PR B plan
// (knowledge-base/project/plans/archive/20261009-235733-2026-10-09-chore-pr-b-retire-inngest-backstop-wipe-apparatus-plan.md).
// 266 -> 271 (#9879, +5): G2 reachability (sole-copy census) rows G2 live/mutation/spelling/scripts/harness in the B5/B6 describe.
// 271 -> 277 (#9879 review fixes, +6): G2 destroy spellings + sub-root normalisation, G2 scanner linearity, and the G2e attribute pin
// (live, mutation matrix, comment-stripper robustness, per-merge edge to the volume).
// 277 -> 278 (#9879 review round 2, +1): G2e lexer/scanner linearity.
// 278 -> 276 (#9372 retirement): the declared count was 279 (floor 278, one row loose); the single-use rebirth workflow's five-target describe (three tests) retired with the workflow and the G2 test was rewritten in place, so 279 - 3 = 276.
// Exact again: grep -cE '^\s*test\(' = 276.
// 276 -> 279 (#10166, +3): the d6 rotate marker / flip gate wiring describe (real-tree pins, twelve-mutant battery, the executed gate block). The 2 rows of slack were already there (declared 278 vs floor 276 on main).
// 279 -> 286 (#10175, +7): the rotate's store-never-written gate describe (real-tree pins, the wiring mutation battery, the no-other-flag-writer scan, the flag-seam credential enumeration, the census pin, and the two executed-step tests). The 2 rows of slack above are unchanged (declared 288).
// 296 -> 297 (#10697 fix round, +1): the web_bash_synthetic beat's period/grace/alerting-attribute pins and the URL-secret name tie.
// 297 -> 299 (2026-10-27 eMudhra cloudflared plan, +2; the 311 on main counted the +12 of #11179, whose destroy-workflow pins left with the workflow at #11195): the hardcoded 3-file PIN_WORKFLOWS test was replaced by the
// .github/-wide pin census describe (census+parity, canonical source) plus its mutation-battery describe — 3 tests in, 1 out.
// 299 -> 303 (#11194, +4): the plaintext-id interlock wire pins (replace job incl. rotate; create job), the wiring-predicate
// mutation battery and the executed-step test. The retired-address assertion REPLACED the GIT_DATA_PRESERVED_VOLUMES test
// one-for-one (declared count unchanged by it). Exact again: grep -cE '^\s*test\(' = 303.
const TEST_FLOOR = 303;
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
// #7539: raised 10 -> 17, the MEASURED size of the set. The old floor left a
// headroom of 7 -- eight of the seventeen are unpinned by the name list below,
// so a resource could silently drop out of the SSH set with the whole suite
// green. That matters beyond this sentinel: Guard 1 intersects against
// collectSshProvisioned(), so a narrowed set silently narrows the guard too.
// Still `>=`, so adding an SSH-provisioned resource does not need an edit here.
// #8706: raised 17 -> 18 for terraform_data.luks_monitor_install (workspaces-luks.tf).
// #9151: raised 18 -> 19 for terraform_data.deploy_pipeline_fix_web2 (server.tf).
// #9534-review: raised 19 -> 20 for terraform_data.journald_persistent_web2 (server.tf).
// #10455 b: raised 20 -> 22 for terraform_data.web_bash_synthetic_install and terraform_data.web_bash_synthetic_install_web2 (server.tf).
const MIN_SSH_PROVISIONED = 22;

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
let webPlatformTargets: Set<string>;
let deployPipelineFixTargets: Set<string>;

beforeAll(() => {
  expect(existsSync(INFRA_DIR)).toBe(true);
  expect(existsSync(WEB_PLATFORM_WORKFLOW)).toBe(true);
  expect(existsSync(DEPLOY_PIPELINE_FIX_WORKFLOW)).toBe(true);

  sshProvisioned = collectSshProvisioned();

  webPlatformTargets = extractTargets(
    readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"),
  );
  deployPipelineFixTargets = extractTargets(
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

  // #9151 — apply-deploy-pipeline-fix.yml is the web-2 sibling's SOLE carrier: it
  // alone opens the bastion `ssh -L` forward + second OUTPUT REDIRECT that makes
  // hcloud_server.web["web-2"].ipv4_address routable for Terraform's Go SSH
  // client. A -target line in apply-web-platform-infra.yml (whose bridge carries
  // no web-2 route) would hang that run to the SSH timeout — the same class as
  // for_each over var.web_hosts (#7000), one hop further out.
  test("deploy_pipeline_fix_web2 is targeted ONLY by apply-deploy-pipeline-fix.yml (#9151)", () => {
    expect(sshProvisioned).toContain("deploy_pipeline_fix_web2");
    expect(deployPipelineFixTargets.has("deploy_pipeline_fix_web2")).toBe(true);
    expect(webPlatformTargets.has("deploy_pipeline_fix_web2")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Guard 1 (#7539): the bridge-less stage may not target an SSH-provisioned
// resource.
//
// The `apply` job runs TWO terraform stages separated by a CREDENTIAL boundary.
// Stage 1 ("Terraform plan (allow-list, non-SSH resources only)" → "Terraform
// apply" of the saved tfplan) runs BEFORE `./.github/actions/cf-tunnel-ssh-bridge`
// exports TF_VAR_ci_ssh_private_key. Stage 2 ("Terraform apply (SSH-provisioned
// resources, over the bridge)") runs after it and owns every SSH-provisioned
// resource. server.tf resolves `agent = var.ci_ssh_private_key == null`, so an
// SSH-provisioned resource targeted in stage 1 bakes `agent = true` and dies:
// `SSH agent requested but SSH_AUTH_SOCK not-specified`. It fails DIRECTLY (its
// own provisioner) and can also drag a dependency in via `-target` transitivity,
// which is a REQUEST and not a bound.
//
// The property is a BRIGHT LINE over `terraform_data` rather than over the SSH
// predicate. Measured: 17 of 18 `terraform_data` resources in the infra root are
// SSH-provisioned, and NOTHING else in the root carries a `provisioner` block at
// all — so the line is strictly stronger here, needs no dependency graph, and
// cannot be narrowed by a resource silently dropping out of
// collectSshProvisioned(). A future genuinely-local terraform_data on the push
// path costs one PUSH_PATH_TERRAFORM_DATA_ALLOWLIST entry with a stated reason.
//
// PARSER ASSUMPTIONS (this extractor fails OPEN, like its siblings above):
//   • The end anchor is the bridge step's `uses:` VALUE, never a step title — a
//     legitimate rename must not hard-fail the guard
//     (cq-cite-content-anchor-not-line-number).
//   • Targets match on COMMENT-STRIPPED text and only on flag-shaped lines
//     (`^\s*-target=`). Both are load-bearing: the range contains prose mentions
//     of `-target=` (an ALLOW-LIST MAINTENANCE comment and a `::warning::`
//     string) that a naive substring match counts. H1 pins this.
//   • An unresolvable range is a FAILURE, never an empty pass (M4).
//
// See ADR-154 (§ bridge-less stage amendment).

/** Deliberately empty: no local `terraform_data` legitimately sits on a
 *  bridge-less path today. An addition needs a one-line reason, like
 *  EXCLUSION_ALLOWLIST. Kept non-vacuous by an M-row that allowlists a
 *  synthetic offender and asserts it is admitted — a zero-cardinality set with
 *  no test is an escape hatch nobody has ever proven is wired. */
const BRIDGELESS_TERRAFORM_DATA_ALLOWLIST = new Set<string>([]);

/** Bridge step anchor — the composite's `uses:` VALUE, not any step title. */
const BRIDGE_USES_RE =
  /^\s*uses:\s*\.\/\.github\/actions\/cf-tunnel-ssh-bridge\s*$/;

/** Every top-level job id (a 2-space `<id>:` key that owns `runs-on`/`steps`). */
function listJobIds(workflowText: string): string[] {
  const ids: string[] = [];
  let inJobs = false;
  for (const line of workflowText.split("\n")) {
    if (/^jobs:\s*$/.test(line)) {
      inJobs = true;
      continue;
    }
    if (!inJobs) continue;
    if (/^[A-Za-z]/.test(line)) break; // left the `jobs:` mapping
    const m = line.match(/^ {2}([A-Za-z0-9_-]+):\s*$/);
    if (m) ids.push(m[1]);
  }
  return ids;
}

/**
 * For ONE job: the text that runs WITHOUT `TF_VAR_ci_ssh_private_key` — i.e.
 * everything before its first `cf-tunnel-ssh-bridge` step, or the WHOLE job
 * when it never opens a bridge. Returns null only when the job block itself
 * does not resolve; callers MUST treat null as a failure, never as empty.
 *
 * Scoping to the whole job set rather than the literal id "apply" is
 * load-bearing: `vector_redeliver` has the identical two-stage shape and is
 * compliant only by step ORDER (its own header calls that "LOAD-BEARING"), and
 * the file has grown to 18 jobs by accretion.
 */
function bridgelessRangeForJob(
  workflowText: string,
  jobId: string,
): string | null {
  const job = extractJobBlock(workflowText, jobId);
  if (!job.trim()) return null;
  const lines = job.split("\n");
  const bridge = lines.findIndex((l) => BRIDGE_USES_RE.test(l));
  if (bridge === 0) return null; // a job that opens with the bridge is malformed
  return bridge === -1 ? job : lines.slice(0, bridge).join("\n");
}

/**
 * `terraform_data` addresses reachable from a `-target=`/`-replace=` flag.
 *
 * Quoting tolerance is NOT optional — the sibling `extractAllTargets` says so
 * in its own comment, and this file's workflow uses 69 single-quoted and 14
 * double-quoted `-target=` flags against 139 bare ones. A bare-only,
 * line-leading matcher lets the #7539 regression re-land verbatim in the
 * house style. `-replace=` is included because it drives the same provisioner
 * run and the workflow already carries 13 of them.
 */
function terraformDataTargets(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(
    /-(?:target|replace)=['"]?(?:module\.[A-Za-z0-9_]+\.)*terraform_data\.([A-Za-z0-9_]+)/g,
  )) {
    out.push(m[1]);
  }
  return out;
}

/** Every `-target=`/`-replace=` of any type — the dispatch floor's input. */
function countTargets(text: string): number {
  return [...stripComments(text).matchAll(/-(?:target|replace)=/g)].length;
}

/**
 * Offenders across EVERY job: `{job, addr}` for each `terraform_data` reachable
 * from a bridge-less range. Throws when a job block fails to resolve, so an
 * unparseable workflow fails closed rather than reporting "no offenders".
 */
function bridgelessOffenders(
  workflowText: string,
): Array<{ job: string; addr: string }> {
  const jobs = listJobIds(workflowText);
  if (jobs.length === 0) throw new Error("no jobs resolved from the workflow");
  const out: Array<{ job: string; addr: string }> = [];
  for (const job of jobs) {
    const range = bridgelessRangeForJob(workflowText, job);
    if (range === null) throw new Error(`job block did not resolve: ${job}`);
    for (const addr of terraformDataTargets(range)) {
      if (!BRIDGELESS_TERRAFORM_DATA_ALLOWLIST.has(addr)) out.push({ job, addr });
    }
  }
  return out;
}

/**
 * Every resource TYPE in the infra root that carries a `provisioner` block.
 *
 * Guard 1 is stated as a bright line over `terraform_data` rather than over the
 * SSH predicate, and that is only STRICTLY STRONGER while this set is exactly
 * {terraform_data}. The premise was true and unpinned until #7539's review: an
 * SSH-provisioned `null_resource`, or a `provisioner` added to
 * `hcloud_server.web`, would sit outside the line with the whole suite green.
 * Pinning the premise is strictly better than widening the predicate for it —
 * it fails in the PR that introduces the violation, naming the resource, and it
 * needs no edit to the fail-open HCL parser four other assertions depend on.
 */
function resourceTypesWithProvisioners(
  files: string[] = listInfraTfFiles(),
): string[] {
  const types = new Set<string>();
  for (const f of files) {
    let current: string | null = null;
    for (const line of stripComments(readFileSync(f, "utf8")).split("\n")) {
      const h = line.match(/^resource\s+"([A-Za-z0-9_]+)"\s+"[A-Za-z0-9_]+"\s*\{/);
      if (h) {
        current = h[1];
        continue;
      }
      if (current && /^\s*provisioner\s+"[a-z-]+"\s*\{/.test(line)) {
        types.add(current);
      }
    }
  }
  return [...types].sort();
}

/**
 * Every workflow that opens a CF Tunnel SSH bridge — DERIVED, never restated.
 *
 * Guard 1 originally read one workflow while five use the bridge. A hardcoded
 * list would reproduce the defect this file exists to catch: the deferral filed
 * during review proposed a trigger reading "when a THIRD workflow adopts the
 * shape", and three already had. Deriving means a sixth is guarded on arrival.
 */
function bridgeWorkflowPaths(): string[] {
  const dir = resolve(REPO_ROOT, ".github/workflows");
  return readdirSync(dir)
    .filter((f) => f.endsWith(".yml") || f.endsWith(".yaml"))
    .map((f) => resolve(dir, f))
    .filter((abs) =>
      /^\s*uses:\s*\.\/\.github\/actions\/cf-tunnel-ssh-bridge\s*$/m.test(
        readFileSync(abs, "utf8"),
      ),
    )
    .sort();
}

describe("bridge-less stage may not target an SSH-provisioned resource (#7539)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");

  test("every job block resolves (an unparseable workflow fails CLOSED)", () => {
    const jobs = listJobIds(wf);
    // Floor derived from the measured value (18 jobs), not a round number: a
    // job-enumeration that silently narrows takes the whole guard with it.
    expect(jobs.length).toBeGreaterThanOrEqual(15);
    for (const j of jobs) {
      expect(bridgelessRangeForJob(wf, j)).not.toBeNull();
    }
  });

  test("dispatch floor: the ranges hold targets (a guard that scans nothing must FAIL)", () => {
    const scanned = listJobIds(wf)
      .map((j) => countTargets(bridgelessRangeForJob(wf, j)!))
      .reduce((a, b) => a + b, 0);
    // Measured 219 across all bridge-less ranges at authoring time. Bounded
    // NEAR the measurement, not at a fraction of it: a floor that tolerates
    // losing half the range does not floor the tail, which is where #7539 lived.
    expect(scanned).toBeGreaterThanOrEqual(180);
  });

  test("the bridge anchor resolves in the apply job (content anchor, not a title)", () => {
    // The apply job MUST have a bridge; a range equal to the whole job would
    // mean the anchor stopped resolving and every post-bridge target became an
    // offender — loud, but for the wrong reason. Pin it positively.
    const applyJob = extractJobBlock(wf, "apply");
    expect(BRIDGE_USES_RE.test(applyJob.split("\n").find((l) => BRIDGE_USES_RE.test(l)) ?? "")).toBe(true);
    expect(bridgelessRangeForJob(wf, "apply")!.length).toBeLessThan(applyJob.length);
  });

  test("no terraform_data is targeted before a CF Tunnel SSH bridge, in ANY job", () => {
    expect(bridgelessOffenders(wf)).toEqual([]);
  });

  test("the bright line's PREMISE is pinned: only terraform_data carries provisioners", () => {
    // If this ever fails, Guard 1 stopped being strictly stronger than the SSH
    // predicate and the named type must be admitted to the walk.
    expect(resourceTypesWithProvisioners()).toEqual(["terraform_data"]);
  });

  test("EVERY bridge-using workflow is guarded, not just this one", () => {
    const paths = bridgeWorkflowPaths();
    // Floor derived from the measured five; a derivation that silently narrows
    // takes the coverage with it.
    expect(paths.length).toBeGreaterThanOrEqual(5);
    for (const abs of paths) {
      expect(bridgelessOffenders(readFileSync(abs, "utf8"))).toEqual([]);
    }
  });
});

// The green-skip channel (#7539). When CI_SSH_ACCESS_TOKEN_ID is absent,
// ssh_token_gate sets ssh_apply_skip=true and the bridge, the post-bridge apply
// AND the heartbeat ARM gate all skip — the run goes GREEN having delivered
// nothing. These assert the notification arm is actually wired, so it cannot be
// silently un-wired: an arm that exists but references a dead output, or whose
// body omits the recovery command, reproduces the ::warning:: problem in email.
/**
 * One `- name: <title>` step within a job block, bounded at the next same-indent
 * step header (or the end of the job). Returns null when absent.
 *
 * Bounded by the NEXT HEADER rather than by a length comparison: the first draft
 * asserted `slice.length < remainder.length` as its non-vacuity guard, which
 * false-REDs when the step is legitimately the LAST one in the job — coupling the
 * guard to step ORDER, which is not the property.
 */
function extractStep(jobText: string, titleMatch: RegExp): string | null {
  const lines = jobText.split("\n");
  const start = lines.findIndex(
    (l) => /^ {6}- name:/.test(l) && titleMatch.test(l),
  );
  if (start === -1) return null;
  let end = lines.length;
  for (let i = start + 1; i < lines.length; i++) {
    if (/^ {6}- name:/.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

// The green-skip channel (#7539). When CI_SSH_ACCESS_TOKEN_ID cannot be read,
// ssh_token_gate sets ssh_apply_skip=true and the bridge, the post-bridge apply
// AND the heartbeat ARM gate all skip — the run goes GREEN having delivered
// nothing.
//
// Every assertion here is scoped to the NOTIFY STEP and anchored on syntax a
// comment cannot produce. The first draft used job-wide `toContain` on bare
// tokens, under which the `if:` could be moved to a decoy step and the whole
// SSH_STAGE branch deleted, both at full green.
describe("the ssh_token_gate green-skip has a channel (#7539)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const applyJob = extractJobBlock(wf, "apply");
  const notify = extractStep(applyJob, /Notify ops/);
  const summary = extractStep(applyJob, /Post-apply summary/);
  const gate = extractStep(applyJob, /Check CI-SSH token presence/);

  test("the notify step exists and USES the ops-email action (anchored, not a substring)", () => {
    expect(notify).not.toBeNull();
    expect(notify!).toMatch(/^\s*uses:\s*\.\/\.github\/actions\/notify-ops-email\s*$/m);
  });

  test("the skip gate is ON that step — not on a decoy elsewhere in the job", () => {
    // Anchored on the `if:` LINE, not the step body. The body carries a comment
    // explaining why this is `!cancelled()` and not `always()` — a body-wide
    // `not.toContain("always()")` is satisfied by that comment, which is the exact
    // collision this file documents (cq-assert-anchor-not-bare-token). Measured:
    // the first draft of this assertion failed on its own explanatory comment.
    const ifLine = notify!
      .split("\n")
      .find((l) => /^\s*if:/.test(stripLineComment(l)));
    expect(ifLine).toBeDefined();
    expect(ifLine!).toMatch(
      /steps\.ssh_token_gate\.outputs\.ssh_apply_skip\s*==\s*'true'/,
    );
    // `!cancelled()`, never `always()`: always() also fires on a CANCELLED run,
    // where the body's "completed green" headline is false.
    expect(ifLine!).toContain("!cancelled()");
    expect(ifLine!).not.toContain("always()");
  });

  test("it references a real step id, and that gate emits BOTH outputs it is read for", () => {
    expect(gate).not.toBeNull();
    expect(applyJob).toMatch(/^\s*id:\s*ssh_token_gate\s*$/m);
    expect(gate!).toContain('echo "ssh_apply_skip=true" >> "$GITHUB_OUTPUT"');
    expect(gate!).toContain('echo "ssh_skip_cause=${SKIP_CAUSE}" >> "$GITHUB_OUTPUT"');
  });

  test("the gate MEASURES the cause instead of assuming it (no bare `|| true` collapse)", () => {
    // A `|| true` here folds an expired DOPPLER_TOKEN into "the secret is absent",
    // and the email then states that as fact.
    expect(gate!).not.toMatch(/TOKEN_ID=\$\(doppler secrets get [^)]*\|\| true\)/);
    expect(gate!).toContain("SKIP_CAUSE=unreadable");
    expect(gate!).toContain("SKIP_CAUSE=absent");
  });

  test("the email carries a RUNNABLE recovery command, not a pointer to one", () => {
    expect(notify!).toContain("gh workflow run apply-web-platform-infra.yml");
    expect(notify!).toContain("apply_target=manual-rerun");
    // and it reports the measured cause rather than a hardcoded one
    expect(notify!).toContain("ssh_skip_cause");
  });

  test("the run summary BRANCHES on the skip (job.status alone reads success)", () => {
    expect(summary).not.toBeNull();
    // Assert the branch itself, not just the echo literal: deleting the whole
    // if/elif/else leaves `**SSH stage:**` matching while SSH_STAGE renders empty.
    expect(summary!).toMatch(/if\s+\[\s*"\$\{SSH_SKIP\}"\s*=\s*"true"\s*\]/);
    expect(summary!).toContain("SSH_STAGE=");
    expect(summary!).toContain("**SSH stage:**");
  });
});

describe("git_data_host_create: the boot-signal poll is gated on the apply outcome (#8010)", () => {
  // The poll used to be `if: always()`: on run 34822248580 a plan the birth gate REFUSED
  // (apply skipped) still spent the full 10-minute budget and told the operator to re-dispatch.
  // These arms pin the predicate and drive the Dispatch summary's verdict `case` under real
  // bash across the outcome cross-product, so the fail-closed branches are exercised rather
  // than string-matched.
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const job = extractJobBlock(wf, "git_data_host_create");
  const apply = extractStep(job, /Terraform apply \(git-data birth\)/);
  const poll = extractStep(job, /Poll for the git-data boot-completion signal/);
  const summary = extractStep(job, /Dispatch summary/);

  test("the apply and poll steps carry the ids the predicate and the summary read", () => {
    expect(apply).not.toBeNull();
    expect(poll).not.toBeNull();
    expect(apply!).toMatch(/^\s*id:\s*apply\s*$/m);
    expect(poll!).toMatch(/^\s*id:\s*poll\s*$/m);
  });

  test("the poll's if: line is the enumerated, cancellation-aware predicate — never always()", () => {
    const ifLine = poll!
      .split("\n")
      .find((l) => /^\s*if:/.test(stripLineComment(l)));
    expect(ifLine).toBeDefined();
    expect(ifLine!).toContain("!cancelled()");
    expect(ifLine!).toMatch(
      /steps\.apply\.outcome == 'success' \|\| steps\.apply\.outcome == 'failure'/,
    );
    expect(ifLine!).not.toContain("always()");
    expect(ifLine!).not.toContain("!= 'skipped'");
  });

  test("the summary verdict case fails closed on every unverified pair (executed under bash)", () => {
    expect(summary).not.toBeNull();
    const m = /if \[\[ -z "\$APPLY_OUTCOME"[\s\S]*?esac/.exec(summary!);
    expect(m).not.toBeNull();
    // Dedent the YAML block scalar so bash sees the script as the runner would.
    const block = m![0].split("\n").map((l) => l.replace(/^ {10}/, "")).join("\n");
    // [apply, poll, rc, annotation stdout must contain ("" = must print nothing)]. The
    // annotation column is what tells the cancelled arm from the `*` default, which share rc 0.
    const table: Array<[string, string, number, string]> = [
      ["success", "success", 0, ""],
      ["success", "failure", 0, ""],
      ["success", "skipped", 1, "::error::apply succeeded but the boot-signal poll did not run"],
      ["success", "cancelled", 1, "::error::apply succeeded but the boot-signal poll did not run"],
      ["skipped", "skipped", 0, "::notice::boot-signal poll SKIPPED"],
      ["failure", "failure", 0, ""],
      ["failure", "skipped", 0, ""],
      ["cancelled", "skipped", 0, "::warning::apply was cancelled mid-flight"],
      ["neutral", "skipped", 0, "::warning::unrecognised outcome pair"],
      ["", "", 1, "::error::apply/poll outcome is EMPTY"],
      ["success", "", 1, "::error::apply/poll outcome is EMPTY"],
      ["", "skipped", 1, "::error::apply/poll outcome is EMPTY"],
    ];
    for (const [a, p, rc, note] of table) {
      const r = spawnSync("bash", ["-eo", "pipefail", "-c", block], {
        env: { PATH: process.env.PATH ?? "/usr/bin:/bin", APPLY_OUTCOME: a, POLL_OUTCOME: p },
        encoding: "utf8",
      });
      expect(`${a}/${p} -> rc=${r.status}`).toBe(`${a}/${p} -> rc=${rc}`);
      if (note === "") expect(`${a}/${p} -> [${r.stdout}]`).toBe(`${a}/${p} -> []`);
      else expect(`${a}/${p} -> ${r.stdout}`).toContain(note);
    }
  });
});

// Mutation + harness battery. Each M-row asserts the guard reports RED for a
// mutated fixture; each H-row asserts it PASSES a legitimate non-canonical one.
// These run in CI forever rather than being hand-applied once at authoring time.
describe("Guard 1 mutation battery (#7539)", () => {
  const BRIDGE = "        uses: ./.github/actions/cf-tunnel-ssh-bridge";

  /** Minimal synthetic workflow with the same two-stage shape as the real one. */
  function synth(opts: {
    preBridge?: string[];
    postBridge?: string[];
    bridgeLine?: string;
  }): string {
    return [
      "jobs:",
      "  preflight:",
      "    runs-on: ubuntu-latest",
      "  apply:",
      "    runs-on: ubuntu-latest",
      "    steps:",
      "      - name: Terraform plan (allow-list, non-SSH resources only)",
      "        run: |",
      "          terraform plan \\",
      ...(opts.preBridge ?? []).map((t) => `            ${t}`),
      "      - name: CF Tunnel SSH bridge (gated)",
      opts.bridgeLine ?? BRIDGE,
      "      - name: Terraform apply (SSH-provisioned resources, over the bridge)",
      "        run: |",
      "          terraform apply \\",
      ...(opts.postBridge ?? []).map((t) => `            ${t}`),
      "  inngest_host:",
      "    runs-on: ubuntu-latest",
    ].join("\n");
  }

  /** A compliant baseline: SSH addresses only after the bridge. */
  const COMPLIANT = synth({
    preBridge: [
      "-target=doppler_secret.alpha \\",
      "-target=betteruptime_heartbeat.beta \\",
      "-target=cloudflare_ruleset.gamma \\",
    ],
    postBridge: [
      "-target=terraform_data.journald_persistent \\",
      "-target=terraform_data.fail2ban_tuning \\",
    ],
  });

  const addrs = (wf: string) => bridgelessOffenders(wf).map((o) => o.addr);

  test("control: the compliant baseline is GREEN (a red baseline voids every row)", () => {
    expect(bridgelessOffenders(COMPLIANT)).toEqual([]);
  });

  test("M1: the #7539 regression itself — the misplaced address before the bridge", () => {
    const mutant = synth({
      preBridge: [
        "-target=doppler_secret.alpha \\",
        "-target=terraform_data.inngest_consumer_probe_install \\",
      ],
      postBridge: ["-target=terraform_data.journald_persistent \\"],
    });
    expect(addrs(mutant)).toEqual(["inngest_consumer_probe_install"]);
  });

  test("M2: a SECOND offender after a compliant first (catches a check that stops at hit one)", () => {
    const mutant = synth({
      preBridge: [
        "-target=doppler_secret.alpha \\",
        "-target=terraform_data.inngest_consumer_probe_install \\",
        "-target=terraform_data.fail2ban_tuning \\",
      ],
    });
    expect(addrs(mutant)).toEqual([
      "inngest_consumer_probe_install",
      "fail2ban_tuning",
    ]);
  });

  // M3a-c: TOKEN SHAPE. The real workflow writes 69 single-quoted and 14
  // double-quoted `-target=` flags against 139 bare ones, and 13 `-replace=`.
  // A bare-only, line-leading matcher lets the regression re-land in the
  // file's own majority style — measured, it did: the first draft of this
  // guard passed all three of these green.
  test("M3a: SINGLE-QUOTED — the style 69 of the file's own -target flags use", () => {
    const mutant = synth({
      preBridge: ["-target='terraform_data.inngest_consumer_probe_install' \\"],
    });
    expect(addrs(mutant)).toEqual(["inngest_consumer_probe_install"]);
  });

  test("M3b: DOUBLE-QUOTED", () => {
    const mutant = synth({
      preBridge: ['-target="terraform_data.journald_persistent" \\'],
    });
    expect(addrs(mutant)).toEqual(["journald_persistent"]);
  });

  test("M3c: -replace= drives the same provisioner run as -target=", () => {
    const mutant = synth({
      preBridge: ["-replace=terraform_data.cosign_trusted_root \\"],
    });
    expect(addrs(mutant)).toEqual(["cosign_trusted_root"]);
  });

  test("M3d: a SECOND flag on one line, and a module-prefixed address", () => {
    const mutant = synth({
      preBridge: [
        "-target=doppler_secret.alpha -target=terraform_data.fail2ban_tuning \\",
        "-target=module.web.terraform_data.orphan_reaper_install \\",
      ],
    });
    expect(addrs(mutant)).toEqual([
      "fail2ban_tuning",
      "orphan_reaper_install",
    ]);
  });

  test("M4: an address in the bridge-less APPLY step, not the plan step (the range hole)", () => {
    const mutant = [
      "jobs:",
      "  apply:",
      "    steps:",
      "      - name: Terraform plan (allow-list, non-SSH resources only)",
      "        run: terraform plan -target=doppler_secret.alpha",
      "      - name: Terraform apply",
      "        run: |",
      "          terraform apply \\",
      "            -target=terraform_data.cosign_trusted_root \\",
      "      - name: CF Tunnel SSH bridge (gated)",
      BRIDGE,
      "  inngest_host:",
      "    runs-on: ubuntu-latest",
    ].join("\n");
    expect(addrs(mutant)).toEqual(["cosign_trusted_root"]);
  });

  test("M5: a SECOND job with its own bridge, reordered so the target precedes it", () => {
    // `vector_redeliver` in the real file has exactly this shape and is
    // compliant only by step ORDER. An apply-job-only guard is blind to it.
    const mutant = [
      "jobs:",
      "  apply:",
      "    steps:",
      "      - name: CF Tunnel SSH bridge (gated)",
      BRIDGE,
      "      - name: Terraform apply",
      "        run: terraform apply -target=terraform_data.journald_persistent",
      "  vector_redeliver:",
      "    steps:",
      "      - name: Terraform plan (scoped)",
      "        run: terraform plan -target=terraform_data.journald_persistent",
      "      - name: CF Tunnel SSH bridge",
      BRIDGE,
      "  entrypoint_audit:",
      "    runs-on: ubuntu-latest",
    ].join("\n");
    expect(bridgelessOffenders(mutant)).toEqual([
      { job: "vector_redeliver", addr: "journald_persistent" },
    ]);
  });

  test("M6: a NEW job with no bridge at all — the whole job is bridge-less", () => {
    const mutant = [
      "jobs:",
      "  apply:",
      "    steps:",
      "      - name: CF Tunnel SSH bridge (gated)",
      BRIDGE,
      "  hotfix_seccomp:",
      "    steps:",
      "      - name: Terraform apply",
      "        run: terraform apply -target=terraform_data.docker_seccomp_config",
      "  entrypoint_audit:",
      "    runs-on: ubuntu-latest",
    ].join("\n");
    expect(bridgelessOffenders(mutant)).toEqual([
      { job: "hotfix_seccomp", addr: "docker_seccomp_config" },
    ]);
  });

  test("M7: an unresolvable JOB SET fails CLOSED, never empty-passes", () => {
    expect(() => bridgelessOffenders("name: no jobs here\non: push\n")).toThrow(
      /no jobs resolved/,
    );
  });

  test("M8: the allowlist escape hatch is WIRED (a zero-cardinality set is unproven)", () => {
    const mutant = synth({
      preBridge: ["-target=terraform_data.local_only_thing \\"],
    });
    expect(addrs(mutant)).toEqual(["local_only_thing"]);
    BRIDGELESS_TERRAFORM_DATA_ALLOWLIST.add("local_only_thing");
    try {
      expect(bridgelessOffenders(mutant)).toEqual([]);
    } finally {
      BRIDGELESS_TERRAFORM_DATA_ALLOWLIST.delete("local_only_thing");
    }
    expect(addrs(mutant)).toEqual(["local_only_thing"]);
  });

  test("H1: comment-stripping is live (now load-bearing — the matcher is unanchored)", () => {
    // With an unanchored matcher, stripComments is what keeps a DOCUMENTED
    // target from reading as an applied one. The first draft anchored on
    // `^\s*-target=`, which made this strip a measured no-op.
    const mutant = synth({
      preBridge: [
        "-target=doppler_secret.alpha \\",
        "# -target=terraform_data.journald_persistent (documented, not applied)",
      ],
    });
    expect(bridgelessOffenders(mutant)).toEqual([]);
  });

  test("H2: a legitimate non-canonical workflow PASSES (the guard is not diffing the real file)", () => {
    const mutant = synth({
      preBridge: [
        "-target=github_actions_secret.zeta \\",
        "-target='random_id.eta' \\",
      ],
      postBridge: [
        "-target=terraform_data.synthetic_probe_install \\",
        "-target=terraform_data.synthetic_monitor_install \\",
      ],
    });
    expect(bridgelessOffenders(mutant)).toEqual([]);
  });

  test("H3: a job with no terraform at all stays GREEN", () => {
    const mutant = [
      "jobs:",
      "  apply:",
      "    steps:",
      "      - name: CF Tunnel SSH bridge (gated)",
      BRIDGE,
      "  entrypoint_audit:",
      "    steps:",
      "      - name: Audit",
      "        run: echo ok",
    ].join("\n");
    expect(bridgelessOffenders(mutant)).toEqual([]);
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
 * Strip ALL dispatch-only jobs from the workflow before the #5566/#5887
 * coverage+moved guards build `allTargets`. Each is an additive/scoped `-target`
 * writer whose targets are OPERATOR_APPLIED_EXCLUSIONS, so folding them into
 * `allTargets` would WEAKEN the moved-block anchor.
 *
 * The original CTO must-fix 2 concerned web_2_recreate, which carried
 * `-target='hcloud_server.web["web-2"]'` — a MOVED_OPERATOR_CONSUMED base that,
 * if leaked into `allTargets`, would stop the moved guard going red on a dropped
 * moved-base. That job (and warm_standby) were deleted with the web-2 dispatch
 * sweep (#6575, 2026-07-20), so their strips are gone. The rule they established
 * still binds: strip EVERY dispatch job at EVERY site that builds the base-address
 * coverage set, and re-check this list whenever a dispatch job is added.
 */
/**
 * Every job name stripDispatchJobs() strips MUST exist in the workflow.
 *
 * `stripJob` silently no-ops on a job that is not present, so the strip list is unverified
 * in both directions: a deleted job's strip lingers forever (measured at review — re-adding
 * the deleted warm_standby/web_2_recreate strips left the suite fully green), and a typo
 * disables a strip that matters. This pins the list to reality so it cannot accrete dead
 * entries, which is exactly the drift #6575 had to clean up by hand.
 */
describe("stripDispatchJobs list is pinned to real jobs", () => {
  test("every stripped job name exists as a top-level job in the workflow", () => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    // ANCHORED AT COLUMN 0 (`^...` + `m`). Without the anchor this SELF-MATCHES: the first
    // occurrence of the function name in this file's own source is inside this very regex
    // literal (indented), so the extraction captured this test's own strings ("utf8", "y",
    // "m") instead of the job names. The real declaration is the only one at column 0.
    const fnSrc = /^function stripDispatchJobs[\s\S]*?\n}/m.exec(
      readFileSync(__filename, "utf8"),
    );
    expect(fnSrc).not.toBeNull();
    // Every quoted job name in the function body. Deliberately NOT a `stripJob(x, "y")`
    // shape match: the calls nest across lines and the first argument is itself a call
    // containing commas, so an argument-position regex silently extracts nothing — which
    // the non-vacuity floor below caught when this test was written.
    const stripped = [...fnSrc![0].matchAll(/"([a-z0-9_]+)"/g)].map((m) => m[1]);
    // Non-vacuity floor: the extraction must actually find the names.
    expect(stripped.length).toBeGreaterThan(0);
    const missing = stripped.filter(
      (job) => !new RegExp(`^  ${job}:`, "m").test(wf),
    );
    expect(missing).toEqual([]);
  });
});

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
  // ALL git-data OPERATOR_APPLIED_EXCLUSIONS (server + network + the LUKS volume attachment +
  // firewall attachment), so stripping it does not change the coverage anchor today, but keeps
  // the parity boundary uniform so a FUTURE git-data -target that is NOT already an exclusion
  // cannot silently mask a per-merge miss.
  // registry_region_migrate (#6288): the sibling of registry_host_replace for a REGION move
  // (nbg1→hel1) — a dispatch-only scoped job whose 6 -targets are the SAME registry
  // OPERATOR_APPLIED_EXCLUSIONS. Strip it for the identical reason: a dispatch writer surface must
  // never broaden the per-merge coverage anchor.
  // workspaces_luks_recut (#6855, #6812): a dispatch-only scoped -replace job whose 2 -targets
  // (hcloud_volume.workspaces_luks + its attachment) are BOTH already OPERATOR_APPLIED_EXCLUSIONS,
  // so stripping is coverage-neutral today — but strip it per the current best practice for a new
  // dispatch job (uniform parity boundary; a FUTURE recut -target that is NOT an exclusion cannot
  // silently mask a per-merge miss). Its sibling workspaces_luks_cutover is left folded-in
  // historically; new dispatch jobs are stripped explicitly.
  // registry_luks_recut (#6929): the sanctioned guest-side-LUKS recut. A dispatch-only job whose
  // 6 -targets are the SAME registry OPERATOR_APPLIED_EXCLUSIONS as its two registry siblings, so
  // stripping is coverage-neutral today — but strip it for the identical reason: a dispatch writer
  // surface must never broaden the per-merge coverage anchor. NOT cosmetic: without the strip, a
  // FUTURE registry -target that is not already an exclusion would fold into the per-merge
  // coverage set and could silently mask a real per-merge miss.
  // web_host_create (#6730, ADR-145): the dispatch-only BIRTH path — the one route
  // granted the capability every other route HALTs on. Strip it for the same reason as
  // every sibling, but note the stakes differ: four of its nine -targets
  // (hcloud_server.web, hcloud_server_network.web, hcloud_volume.workspaces,
  // hcloud_volume_attachment.workspaces) are MOVED_OPERATOR_CONSUMED / exclusion bases,
  // so folding them into `allTargets` would blunt the moved-block anchor — exactly the
  // CTO must-fix that the deleted web_2_recreate strip originally existed to satisfy.
  // The other five are per-merge-covered, so the strip is coverage-neutral for them
  // (asserted below, non-vacuously).
  // web_host_replace (#6969, ADR-148): the dispatch-only REPLACE path, sibling of the birth
  // above. Three of its four -targets (hcloud_server.web, hcloud_server_network.web,
  // hcloud_volume_attachment.workspaces) are the SAME MOVED_OPERATOR_CONSUMED / exclusion
  // bases the birth strip exists for, so the same blunting argument applies verbatim; the
  // fourth (hcloud_firewall_attachment.web) is per-merge-covered and the strip is
  // coverage-neutral for it. Stripped for the uniform reason too: a dispatch writer surface
  // must never broaden the per-merge coverage anchor.
  // git_data_host_create (#6977, ADR-149): the dispatch-only git-data BIRTH path. Stripped
  // for the uniform reason every dispatch job is — a dispatch writer surface must never
  // broaden the per-merge coverage anchor — and here the strip is genuinely load-bearing
  // rather than merely uniform: ALL EIGHTEEN of its -targets are
  // OPERATOR_APPLIED_EXCLUSIONS (ADR-103), so folding them into `allTargets` would assert
  // per-merge coverage for a fan-out the per-merge apply deliberately never touches.
  // inngest_link_flag (#10136, CTO G1): the Tier-B flag actuator. Its ONE -target is
  // doppler_secret.inngest_link_tls, an OPERATOR_APPLIED_EXCLUSION on purpose: a merge must never flip the
  // production Inngest URL. Stripped so the dispatch job's target cannot masquerade as per-merge coverage
  // (the per-merge list is asserted below NOT to contain it).
  //
  // NOTE for whoever edits this function next: the guard above extracts EVERY
  // "[a-z0-9_]+" string literal in this body and requires each to name a real top-level
  // job. Adding any other lowercase quoted literal here — even in a helper call — makes
  // that guard treat it as a job name and go red. Comments are fine; literals are not.
  return stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(workflowText, "inngest_host"), "registry_host_replace"), "registry_region_migrate"), "registry_luks_recut"), "git_data_host_replace"), "workspaces_luks_recut"), "web_host_create"), "web_host_replace"), "git_data_host_create"), "inngest_link_flag");
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
  "hcloud_firewall.git_data",
  "hcloud_firewall_attachment.git_data",
  // (#11194) hcloud_volume.git_data and hcloud_volume_attachment.git_data left this set: both were
  // destroyed at the provider on 2026-10-27 and are in no .tf file. GIT_DATA_RETIRED_ADDRESSES
  // (below) pins them ABSENT from every git-data dispatch job's -target/-replace lines.
  // betteruptime_heartbeat.git_data_prd + doppler_secret.git_data_heartbeat_url_prd left this set
  // (#8754): the "operator full apply" route they were excluded for no longer exists, so they ride
  // the per-merge -target list, where the same apply's arm step measures a beat before arming. The
  // birth route still refuses them (GIT_DATA_BIRTH_REFUSED).
  // betteruptime_heartbeat.git_data_host_prd + doppler_secret.git_data_host_heartbeat_url_prd (#9438)
  // are in the same position from birth: per-merge targeted, refused by the birth route.
  // #5274 Phase 3 (ADR-068) — the multi-host cluster's new resources all ride the
  // operator's MAINTENANCE-WINDOW apply, exactly like hcloud_server.web + the
  // git-data keys above, NOT the #5566 per-PR-CI class:
  //   - the 3rd git-data key (REMOVE / Art.17 erasure) rides the git-data host
  //     apply, same class as git_transport/git_provision;
  //   - the spread placement group attaches to the RUNNING hcloud_server.web and
  //     forces a power-off reboot — a maintenance-window apply, same class as the
  //     host it groups;
  //   - the host↔host proxy TLS keypair/cert + their prd doppler_secrets are
  //     count-gated on var.host_proxy_tls_enabled (default false, #8754 / ADR-118
  //     amendment) and exist only after the multi-host flip, which must move all
  //     four to a -target list in the same change (doppler_secret, not the
  //     CI-published token types the test forces).
  "tls_private_key.git_remove",
  "doppler_secret.git_remove_ssh_private_key",
  "hcloud_placement_group.web_spread",
  "tls_private_key.proxy_server",
  "tls_self_signed_cert.proxy_server",
  "doppler_secret.proxy_tls_key",
  "doppler_secret.proxy_tls_cert",
  // #11181 / #11182 (ADR-068 §(b)) — Cloudflare Load Balancer overlay-add trio
  // (monitor, web-1 pool, LB on app.soleur.ai). Provisioning requires both the
  // Load Balancing add-on subscription and `Account: Load Balancers: Edit` +
  // `Zone: Load Balancers: Edit` scopes on CF_API_TOKEN (measured 2026-10-27:
  // the per-PR CI token returns Cloudflare code 10000 Authentication error on
  // /load_balancers, so per-PR auto-targeting would 403 and wedge every merge
  // apply — the #5566-inverse footgun). Rides the GA maintenance-window apply.
  "cloudflare_load_balancer_monitor.web",
  "cloudflare_load_balancer_pool.web_1",
  "cloudflare_load_balancer.app",
  // #6657 (ADR-125 / AP-019) — the DNS-edit-only Cloudflare token for the GitHub
  // Pages cert-reissue routine + its prd doppler_secret. Minting a
  // cloudflare_api_token requires "User API Tokens: Edit", which the per-PR CI
  // runner's cf_api_token lacks; auto-targeting the mint on every infra/*.tf push
  // would 403 and wedge the whole apply (the #5566-inverse footgun). So both ride
  // an operator JIT / maintenance-window apply (documented in
  // infra/cf-cert-reissue-token.tf), NOT the #5566 per-PR-CI silent-un-applied
  // class — same class as the git-data doppler_secrets above (doppler_secret, not
  // the CI-published doppler_service_token/github_actions_secret types this test
  // forces).
  "cloudflare_api_token.gh_pages_cert_reissue_dns_edit",
  "doppler_secret.cf_api_token_dns_edit",
  // #5274 Sub-PR 3.D (ADR-068) — the fresh LUKS git-data volume + its at-rest key +
  // its scoped read-only token ALL ride the operator's MAINTENANCE-WINDOW cutover apply
  // (the volume attaches to the RUNNING git-data host; guest-side cryptsetup unlocks it
  // at boot), NOT the #5566 per-PR-CI class. Same class as the git-data doppler_secrets above.
  //   `doppler_service_token.git_data` is an OPERATOR-APPLIED token exception (see
  //   OPERATOR_APPLIED_TOKEN_EXCLUSIONS below): unlike doppler_service_token.write /
  //   .kb_drift (whose `.key` is published into a paired github_actions_secret consumed
  //   by CI, so #5566 forces them to be CI-targeted), this token is minted into an
  //   `prd_git_data` Doppler config and consumed by cloud-init on the git-data HOST. CI
  //   cannot apply it: it is minted into a config that only the gated birth dispatch
  //   creates, and CI cannot provision the host that reads it.
  //
  //   (#6977) That config is now `doppler_config.git_data_prd` below rather than an
  //   operator's dashboard click. The prose here used to read "the config does not exist
  //   until the operator creates it (runbook precondition)" — true when written, and the
  //   precondition it referenced has been deleted, not merely automated.
  "random_password.git_data_luks",
  "doppler_secret.git_data_luks_key",
  "hcloud_volume.git_data_luks",
  "hcloud_volume_attachment.git_data_luks",
  "doppler_service_token.git_data",
  // (#6977) The prd_git_data BRANCH CONFIG itself. An exclusion for the same reason as
  // every git-data sibling — and it must NEVER be given a per-PR `-target` line. Both
  // Doppler writes above reference it, so a per-PR target would drag
  // hcloud_server.git_data into the per-merge plan through upstream closure, trip
  // `host_creates > 0`, and wedge every merge to main.
  //
  // (#6982) DC-3 is now RESOLVED, not merely inherited. That mechanism was read as killing
  // the `doppler_secret.git_data_ssh_host` proposal outright; it does not. It bites only
  // under the remedy "give the new secret a per-PR -target line", which is not the remedy
  // any of its five sibling secrets use — they sit in THIS set with no per-PR target at
  // all. So the secret ships in #6982 as an exclusion + a birth -target, with no wedge.
  //
  // (#7772) THE SENTENCE THAT STOOD HERE described the rejected design. It said the value is
  // sourced "from a static local (local.git_data_private_ip) instead of the computed NIC
  // attribute", which "removes the last edge that could reach the server". DC-3 mandated the
  // opposite and DC-5 was reversed before merge: git-data.tf reads
  // `hcloud_server_network.git_data.ip`. The no-wedge conclusion is unaffected and stands on
  // the reason above it — this exclusion means no per-PR -target, so the computed edge is
  // never in a per-merge plan closure. `local.git_data_private_ip` still exists and is still
  // load-bearing, but for network.tf's own `ip =` assignment, not for this secret.
  "doppler_config.git_data_prd",
  // (#6982) Both ride the git-data-host-create dispatch, never the per-PR apply — same
  // class as every git-data sibling above.
  "doppler_secret.git_data_ssh_host",
  "doppler_secret.git_data_betterstack_logs_token",
  // (#7226, ADR-237) The git-data SSH HOST key and its published pin (GIT_DATA_SSH_HOST_KEY).
  // They rotate WITH the host: the replace job -replace's the key and -targets the pin, the
  // birth job -targets both. A per-PR -target on either would publish a pin the live host does
  // not carry (plan R1), so both are exclusions and Guard 4 below asserts neither is on the
  // per-PR list.
  "tls_private_key.git_data_host_ssh",
  "doppler_secret.git_data_ssh_host_key",
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
  //   NOTE (#6649): `doppler_service_token.workspaces_luks` is DELIBERATELY NOT excluded here.
  //   #6649 publishes its `.key` into `github_actions_secret.workspaces_luks_boot_token`
  //   (workspaces-luks.tf) and adds an explicit `-target` for BOTH to the DEFAULT allow-list, so it
  //   is now a CI-PUBLISHED token (the #5566 rule: a token feeding a github_actions_secret MUST be
  //   targeted, never excluded — mirroring inngest_arm_write, which is in neither exclusion set).
  //   Excluding it would desensitize the default-apply coverage assertion for its `-target` line. The
  //   web-1 host ALSO reads it directly from `prd_workspaces_luks` at unlock time; publishing does not
  //   change the CWE-522 container-boundary rationale (see workspaces-luks.tf + OPERATOR_APPLIED_TOKEN_EXCLUSIONS).
  //   The four resources below ride ONLY the scoped operator cutover apply, so they stay excluded.
  "random_password.workspaces_luks",
  "doppler_secret.workspaces_luks_key",
  "hcloud_volume.workspaces_luks",
  "hcloud_volume_attachment.workspaces_luks",
  // #6604 — the daily luks-monitor probe's Better Stack heartbeat + its Doppler URL secret (the
  // same class the git-data heartbeat pair was until #8754 moved it to the per-merge -target list;
  // this heartbeat is paused until the operator unpauses at cutover). NOT part of the five-resource cutover gate allow-set, and never
  // rides the gated cutover -target set — so it does not affect the cutover destroy-guard.
  "betteruptime_heartbeat.workspaces_luks",
  "doppler_secret.workspaces_luks_heartbeat_url",
  // #6122 (ADR-096) — the zot registry host + its volume/network/firewall/creds/heartbeat
  // ALL ride the operator's initial full (untargeted) `terraform apply` + drift detector,
  // exactly like the git-data host above (CTO ruling 2026-07-06,
  // knowledge-base/project/specs/archive/20261013-041741-feat-registry-oidc-migration/apply-path-cto-ruling.md).
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
  // #6895 (ADR-096 amendment / ADR-119 / ADR-140) — the guest-side LUKS-at-rest apparatus for the
  // registry (zot) store volume: the at-rest passphrase (random_password) + its masked secret in the
  // ISOLATED soleur-registry/prd project. Same class as random_password.git_data_luks +
  // doppler_secret.git_data_luks_key above: they ride the operator's gated registry recut apply (a
  // scoped -replace of the volume+attachment+host together), NOT the #5566 per-PR-CI class. The
  // isolated project's existing doppler_service_token.registry (above) already reads the key at boot;
  // no new CI-published token type this test forces.
  "random_password.registry_luks",
  "doppler_secret.registry_luks_key",
  "betteruptime_heartbeat.registry_prd",
  "betteruptime_heartbeat.registry_disk_prd",
  // doppler_secret.zot_heartbeat_url_prd removed (#6438 B3): it was a reserved-but-inert secret for
  // a never-built off-host probe; the web-host consumer probe now mints its own per-host heartbeat +
  // URL secret (betteruptime_heartbeat.web_zot_consumer / doppler_secret.web_zot_consumer_url, which
  // DO ride the per-PR -target list). The orphaned secret itself is destroyed by a bare per-merge
  // -target (#8754, pinned by the PR-B describe below), so it needs no exclusion.
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
  // #8285 — the throwaway wipe host and the plaintext pair `hcloud_volume.inngest_redis` /
  // `hcloud_volume_attachment.inngest_redis` are gone: the apparatus is deleted and the volume was destroyed
  // 2026-10-09. A managed address that no longer exists needs no exclusion (Guard 1 below pins that the
  // retired addresses are not targeted by any job).
  // #6894 / ADR-142. The ADDITIVE target volume and its attachment. They are listed here the moment the
  // resources exist — check_resource_partition reds on any managed address that is neither reachable nor
  // excluded, so the coverage test would go red on the commit that declares the volume if these two lines lagged it.
  //  - The ATTACHMENT is operator-applied via `apply_target=inngest-host` / `inngest-host-replace`; it is not in
  //    the per-merge allowlist.
  //  - The VOLUME is not a `-target` of any per-merge step either (this entry is what `-target` coverage reads), but
  //    it is NOT unreachable from a merge: it rides the per-merge plan as a DEPENDENCY of the per-merge target
  //    `logtail_exploration.inngest_luks_wrong_volume`, through the alias local that interpolates
  //    `hcloud_volume.inngest_redis_luks.id` (betterstack-logs-alerts.tf). That edge is how an in-place update
  //    (delete_protection, #9879) reaches the live volume, and the same edge would carry a create or a replace,
  //    which prevent_destroy refuses and the G2e attribute pin holds in place. The edge is pinned by the
  //    "G2e: the per-merge edge to the volume" test (ADR-282); this exclusion does not make the volume operator-only.
  "hcloud_volume.inngest_redis_luks",
  "hcloud_volume_attachment.inngest_redis_luks",
  "hcloud_server_network.inngest",
  "hcloud_firewall.inngest",
  // hcloud_firewall_attachment.inngest left this set (#8754): it is a removed{} forget now.
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
  // #6780 (ADR-135) — the promoted config-refresh digest pointer, minted into the ISOLATED
  // soleur-inngest/prd project (inngest-config-digest.tf). No per-PR -target: it is count-gated on a
  // non-empty TF_VAR (#8754), and promotion is a separate-principal apply (HARD-6) whose route is not
  // built yet (#9060). The cloud-init regex already admits the name; the remaining coupling is the
  // isolation floor 5->6 bump, which rides the first promotion. `doppler_secret`, not a
  // CI-published token type. (`github_repository_environment.inngest_config_signing`, by contrast, IS host-
  // independent and carries a normal -target — see apply-web-platform-infra.yml.)
  "doppler_secret.inngest_config_digest",
  // #10136 (CTO G1) - the Inngest link flag: count-gated on var.inngest_link_tls, written and applied ONLY by
  // the Tier-B `inngest_link_flag` dispatch job (stripped from the per-merge view in stripDispatchJobs).
  // A merge must never change the URL the web tier dials. Its five siblings in inngest-tls.tf (the key, the
  // cert and the three Doppler copies) ARE per-merge targeted.
  "doppler_secret.inngest_link_tls",
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
  // #6649 (ADR-119) — doppler_service_token.workspaces_luks is DELIBERATELY NOT excluded here.
  // It was an operator-applied-host-token (same class as git_data), but #6649 publishes its `.key`
  // into github_actions_secret.workspaces_luks_boot_token (workspaces-luks.tf) so the cutover/verify
  // workflows can deliver it host-side over the SSH bridge. Per the #5566 rule below, a token that
  // feeds a github_actions_secret MUST be CI-targeted, never excluded — so it is now explicitly
  // `-target`ed in apply-web-platform-infra.yml's DEFAULT allow-list (mirroring the inngest_arm_write
  // precedent). web-1 still ALSO reads prd_workspaces_luks directly via the same token at unlock
  // time; publishing it does not change the CWE-522 container-boundary rationale in workspaces-luks.tf.
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
      // JOB-AWARE: exclude the dispatch-only jobs
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

  test("#6931: the fresh-boot LUKS credentials are CI-targeted in the DEFAULT apply, never an operator-applied exclusion", () => {
    // They MUST exist in state before any web-2 birth: a resource created INSIDE a birth plan is an
    // out-of-scope create to web-host-birth-gate.sh and aborts the birth. `allTargets` is built from
    // the workflow with every dispatch job stripped, so membership here means the per-merge push
    // apply creates them, which is what makes the birth plan a no-op for them. The marker write
    // token feeds a github_actions_secret, so the #5566 rule forbids excluding it as well.
    const freshBoot = [
      "doppler_service_token.workspaces_luks_fresh_boot",
      // #9377 — the web-class escrow split: config, token, bucket and the three secrets must exist in state
      // before any web-2 birth (a create inside a birth plan is out of scope for web-host-birth-gate.sh).
      "doppler_config.workspaces_luks_web",
      "doppler_service_token.workspaces_luks_fresh_boot_web",
      "cloudflare_r2_bucket.workspaces_luks_header_web",
      // The web-class passphrase generator (#9377 decision A1): the key secret's value is its `.result`, so it
      // must ride the same default apply (a `-target` pulls dependencies, but the explicit target keeps the
      // push-apply's plan stable and the declared/targeted parity honest).
      "random_password.workspaces_luks_web",
      "doppler_secret.workspaces_luks_web_key",
      "doppler_secret.workspaces_luks_web_header_bucket",
      "doppler_secret.workspaces_luks_web_header_r2_endpoint",
      "doppler_config.workspaces_luks_marker",
      "doppler_service_token.workspaces_luks_marker_write",
      "github_actions_secret.doppler_token_workspaces_luks_marker",
    ];
    for (const a of freshBoot) {
      expect(allResources, `${a} must be a declared resource`).toContain(a);
      expect(allTargets.has(a), `${a} must be in the default push-apply -target list`).toBe(true);
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(a), `${a} must not be an operator-applied exclusion`).toBe(false);
      expect(OPERATOR_APPLIED_TOKEN_EXCLUSIONS.has(a), `${a} must not be an operator-applied token exclusion`).toBe(false);
    }
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

});

// ─── cloudflared pin parity census — every pin site under .github/ ──────────
// Guard 1 of the 2026-10-27 eMudhra plan (supersedes the #6604 hardcoded
// PIN_WORKFLOWS list). The pin is replicated to 10 sites across 9 workflows —
// 5 env-form `CLOUDFLARED_VERSION:`/`CLOUDFLARED_SHA256:` pairs AND 5
// call-site literal `cloudflared-version:`/`cloudflared-sha256:` pairs inside
// `with:` blocks. The old list only saw the env form in 3 named files: a
// literal-site bump (e.g. apply-web-platform-infra.yml's own second pin in the
// SAME file that owns the canonical env pair) was invisible, so a partial bump
// stayed green. The census DISCOVERS sites by scanning
// `.github/workflows/*.yml` + `.github/actions/*/action.yml`; no file list is
// restated here, so an 11th pin site added anywhere under .github/ is caught
// the day it lands. Canonical = apply-web-platform-infra.yml's env pin.
//
// A `cloudflared-version: ${{ env.CLOUDFLARED_VERSION }}` site RESOLVES through
// its own workflow's env pin — it is conformant iff that workflow declares a
// CONCRETE env pin of the same kind (itself censused). A resolved site in a
// file with no matching env declaration is flagged: at runtime it expands to
// an empty string, which is the dangling-reference class. Other `${{ }}`
// expressions (inputs.*, secrets.*) FORWARD a value supplied elsewhere — the
// composite actions' `CLOUDFLARED_VERSION: ${{ inputs.cloudflared-version }}`
// lines are exactly that — and are conformant by construction: the producer
// site (a caller's literal, or the caller's own env pin) is itself censused.

/** The canonical source of truth — the env pair in this workflow. */
const CANONICAL_PIN_WORKFLOW = ".github/workflows/apply-web-platform-infra.yml";

/** Anti-vacuity floor: the MEASURED site count on main (5 env pairs + 5
 *  literal pairs). `>=`, not `===`, so an added site never needs an edit here;
 *  a census that finds ~nothing proves nothing. */
const MIN_CLOUDFLARED_PIN_SITES = 10;

interface CloudflaredPinSite {
  file: string;
  form: "env" | "literal";
  kind: "version" | "sha256";
  value: string;
  /** true for ANY `${{ ... }}` expression — the value is supplied elsewhere. */
  resolved: boolean;
  /** true specifically for `${{ env.CLOUDFLARED_* }}` — needs a concrete env
   *  pin of the same kind in the same file or it expands to "" at runtime. */
  envRef: boolean;
}

/** Every file the census scans: `.github/workflows/*.yml` +
 *  `.github/actions/<dir>/action.yml`, discovered (never listed). */
function listGithubPinFiles(githubDir = resolve(REPO_ROOT, ".github")): string[] {
  const files: string[] = [];
  const wfDir = join(githubDir, "workflows");
  for (const f of readdirSync(wfDir)
    .filter((f) => /\.ya?ml$/.test(f))
    .sort()) {
    files.push(join(wfDir, f));
  }
  const actionsDir = join(githubDir, "actions");
  if (existsSync(actionsDir)) {
    for (const d of readdirSync(actionsDir).sort()) {
      const a = join(actionsDir, d, "action.yml");
      if (existsSync(a) && lstatSync(a).isFile()) files.push(a);
    }
  }
  return files;
}

/** The live census input as a relpath→text map (the shape mutations perturb). */
function readCloudflaredPinFileMap(): Record<string, string> {
  const map: Record<string, string> = {};
  for (const abs of listGithubPinFiles()) {
    map[relative(REPO_ROOT, abs).split("/").join("/")] = readFileSync(
      abs,
      "utf8",
    );
  }
  return map;
}

// A pin declaration is a YAML mapping key at line start — a `#`-commented or
// mid-line prose mention can never satisfy it. Values: quoted scalars,
// `${{ ... }}` expressions, or bare scalars.
const CLOUDFLARED_PIN_LINE_RE =
  /^\s*(CLOUDFLARED_VERSION|CLOUDFLARED_SHA256|cloudflared-version|cloudflared-sha256)\s*:\s*(?:"([^"]*)"|'([^']*)'|(\$\{\{[^}]*\}\})|([^\s#]+))/;

const CLOUDFLARED_ENV_REF_RE =
  /^\$\{\{\s*env\.(CLOUDFLARED_VERSION|CLOUDFLARED_SHA256)\s*\}\}$/;

/** Discover every pin site in the given file map (pure — mutations inject or
 *  perturb entries to prove the verdict discriminates). */
function cloudflaredPinCensus(
  files: Record<string, string>,
): CloudflaredPinSite[] {
  const sites: CloudflaredPinSite[] = [];
  for (const [file, text] of Object.entries(files)) {
    for (const line of text.split("\n")) {
      const m = CLOUDFLARED_PIN_LINE_RE.exec(line);
      if (!m) continue;
      const key = m[1];
      const value = m[2] ?? m[3] ?? m[4] ?? m[5] ?? "";
      sites.push({
        file,
        form: key === key.toUpperCase() ? "env" : "literal",
        kind: /VERSION$/i.test(key) ? "version" : "sha256",
        value,
        resolved: value.startsWith("${{"),
        envRef: CLOUDFLARED_ENV_REF_RE.test(value),
      });
    }
  }
  return sites;
}

/** Canonical pin = the env pair in CANONICAL_PIN_WORKFLOW *of the map under
 *  test* — mutating that file's env pin must red the whole census. */
function canonicalCloudflaredPin(files: Record<string, string>): {
  version: string | null;
  sha256: string | null;
} {
  const text = files[CANONICAL_PIN_WORKFLOW];
  const inv = text
    ? extractWorkflowInvariants(text)
    : { cloudflaredVersion: null, cloudflaredSha256: null };
  return { version: inv.cloudflaredVersion, sha256: inv.cloudflaredSha256 };
}

/** Every way the census is RED, as named problems (empty = GREEN). */
function cloudflaredPinVerdict(files: Record<string, string>): string[] {
  const canonical = canonicalCloudflaredPin(files);
  if (!canonical.version || !canonical.sha256) {
    return [
      `canonical-unreadable: ${CANONICAL_PIN_WORKFLOW} env pin did not parse`,
    ];
  }
  const problems: string[] = [];
  const sites = cloudflaredPinCensus(files);
  const locations = new Set(sites.map((s) => `${s.file}#${s.form}`));
  if (locations.size < MIN_CLOUDFLARED_PIN_SITES) {
    problems.push(
      `vacuous-census: only ${locations.size} pin sites discovered (< ${MIN_CLOUDFLARED_PIN_SITES})`,
    );
  }
  for (const s of sites) {
    if (s.envRef) {
      // The ref resolves through this file's OWN env pin — conformant iff a
      // CONCRETE (non-${{}}) env token of the same kind exists in that file
      // (it is itself censused for parity). Absent, the ref expands to "" at
      // runtime: the dangling-reference class.
      const backed = sites.some(
        (t) =>
          t.file === s.file &&
          t.form === "env" &&
          t.kind === s.kind &&
          !t.value.startsWith("${{"),
      );
      if (!backed) {
        problems.push(
          `${s.file}: ${s.form} ${s.kind} forwards to env.${s.value.match(/env\.(\w+)/)?.[1] ?? "?"} but the file declares no env pin`,
        );
      }
      continue;
    }
    if (s.resolved) continue; // inputs.*/secrets.*/vars.* — forwards a value supplied elsewhere
    const want = s.kind === "version" ? canonical.version : canonical.sha256;
    if (s.value !== want) {
      problems.push(
        `${s.file}: ${s.form} ${s.kind} pin ${JSON.stringify(s.value)} != canonical ${JSON.stringify(want)}`,
      );
    }
  }
  for (const loc of locations) {
    const kinds = new Set(
      sites
        .filter((s) => `${s.file}#${s.form}` === loc)
        .map((s) => s.kind),
    );
    if (!kinds.has("version")) {
      problems.push(`${loc}: sha256 declared with no version pin`);
    }
    if (!kinds.has("sha256")) {
      problems.push(`${loc}: version declared with no sha256 pin`);
    }
  }
  return problems;
}

describe("cloudflared pin parity census — every pin site under .github/ (#6604 superseded)", () => {
  let files: Record<string, string>;
  beforeAll(() => {
    files = readCloudflaredPinFileMap();
  });

  test(`the census discovers >= ${MIN_CLOUDFLARED_PIN_SITES} pin sites (anti-vacuity)`, () => {
    const locations = new Set(
      cloudflaredPinCensus(files).map((s) => `${s.file}#${s.form}`),
    );
    // The canonical env pin must resolve from the live map — a verdict that
    // cannot read its own reference point is detector-broken, not green.
    const canonical = canonicalCloudflaredPin(files);
    expect(canonical.version).not.toBeNull();
    expect(canonical.sha256).not.toBeNull();
    expect(locations.size).toBeGreaterThanOrEqual(MIN_CLOUDFLARED_PIN_SITES);
    // Every discovered site is a COMPLETE pair — version and sha256 together.
    for (const loc of locations) {
      const kinds = new Set(
        cloudflaredPinCensus(files)
          .filter((s) => `${s.file}#${s.form}` === loc)
          .map((s) => s.kind),
      );
      expect(kinds, `${loc} carries a half-pair`).toEqual(
        new Set(["version", "sha256"]),
      );
    }
  });

  test("every pin site (env + literal forms) equals the canonical env pin", () => {
    expect(cloudflaredPinVerdict(files)).toEqual([]);
  });
});

describe("cloudflared pin census mutation battery", () => {
  const mutate = (
    live: Record<string, string>,
    file: string,
    fn: (text: string) => string,
  ): Record<string, string> => ({ ...live, [file]: fn(live[file] ?? "") });

  test("a divergent pin at ANY site turns the verdict RED; the resolved-ref row stays GREEN", () => {
    const live = readCloudflaredPinFileMap();
    const V = (files: Record<string, string>) => cloudflaredPinVerdict(files);

    expect(V(live)).toEqual([]); // control: a RED below is the mutation's doing

    // Row 1 — bump ONLY reusable-release.yml's literal pin (env pins untouched).
    const row1 = mutate(
      live,
      ".github/workflows/reusable-release.yml",
      (t) => t.replace(/cloudflared-version:\s*"[^"]+"/, 'cloudflared-version: "0.0.0-stale"'),
    );
    expect(V(row1).join("\n")).toMatch(/reusable-release\.yml/);

    // Row 2 — bump ONLY the canonical ENV pin: every other site diverges.
    const row2 = mutate(live, CANONICAL_PIN_WORKFLOW, (t) =>
      t.replace(/CLOUDFLARED_VERSION:\s*"[^"]+"/, 'CLOUDFLARED_VERSION: "0.0.0-stale"'),
    );
    const v2 = V(row2);
    expect(v2.length).toBeGreaterThan(0);
    expect(v2.join("\n")).toMatch(/git-data-cutover\.yml/);

    // Row 3 — an 11th workflow the old hardcoded list never named carries a
    // stale literal pin: the census (not a file list) is what catches it.
    const row3 = {
      ...live,
      ".github/workflows/zz-new-bridge-consumer.yml":
        'name: x\njobs:\n  j:\n    steps:\n      - uses: ./.github/actions/cf-tunnel-ssh-bridge\n        with:\n          cloudflared-version: "0.0.0-stale"\n          cloudflared-sha256: "deadbeef"\n',
    };
    expect(V(row3).join("\n")).toMatch(/zz-new-bridge-consumer\.yml/);

    // Row 4 — a scan that finds nothing is RED, never vacuous-green.
    const renamed: Record<string, string> = {};
    for (const [k, t] of Object.entries(live)) {
      renamed[k] = t
        .replaceAll("CLOUDFLARED_VERSION", "TUNNEL_VERSION")
        .replaceAll("CLOUDFLARED_SHA256", "TUNNEL_SHA256")
        .replaceAll("cloudflared-version", "tunnel-version")
        .replaceAll("cloudflared-sha256", "tunnel-sha256");
    }
    const v4 = V(renamed);
    expect(v4.length).toBeGreaterThan(0);
    expect(v4.join("\n")).toMatch(/vacuous-census|canonical-unreadable/);

    // Row 5 — a literal site MOVED to `${{ env.* }}` refs inside a workflow
    // that declares the env pin stays GREEN (it resolves through canonical).
    const row5 = mutate(live, CANONICAL_PIN_WORKFLOW, (t) =>
      t
        .replace(
          /cloudflared-version:\s*"[^"]+"/,
          "cloudflared-version: ${{ env.CLOUDFLARED_VERSION }}",
        )
        .replace(
          /cloudflared-sha256:\s*"[^"]+"/,
          "cloudflared-sha256: ${{ env.CLOUDFLARED_SHA256 }}",
        ),
    );
    expect(V(row5)).toEqual([]);

    // Row 5b — the same ref in a file WITHOUT an env pin dangles: RED.
    const row5b = mutate(
      live,
      ".github/workflows/reusable-release.yml",
      (t) =>
        t.replace(
          /cloudflared-version:\s*"[^"]+"/,
          "cloudflared-version: ${{ env.CLOUDFLARED_VERSION }}",
        ),
    );
    expect(V(row5b).join("\n")).toMatch(/no env pin/);

    // Row 6 — a half-pair (version with no sha256) is RED wherever it sits.
    const row6 = {
      ...live,
      ".github/workflows/zz-half-pair.yml":
        'env:\n  CLOUDFLARED_VERSION: "0.0.0-stale"\n',
    };
    expect(V(row6).join("\n")).toMatch(/no sha256 pin/);
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
// `hcloud_server.web` carries `for_each = var.web_hosts` (server.tf): a
// reboot-class non-ignored delta (`server_type`) on it in the UNATTENDED per-PR
// path forces a reboot of the running prod host, and targeting it would
// transitively have created the placement group / a second host. (The placement_group_id attach
// itself is suppressed while the attribute sits in lifecycle.ignore_changes —
// the deferral this file's later describe pins.) They are consumed by the operator's ADR-068 Phase-3
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

/**
 * Every `-replace=<addr>` value (quoted or bare) in a workflow-job block.
 *
 * Defined at module scope. It previously lived inside the web-2-recreate block
 * that #6575 deleted, but it is SHARED by the registry-host-replace and
 * git-data-host-replace describes below — deleting its home block took the
 * binding with it and broke both (caught by the suite, not by tsc).
 */
function extractReplaceAddrs(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(
    /-replace=(?:'([^']+)'|"([^"]+)"|(\S+))/g,
  )) {
    out.push((m[1] ?? m[2] ?? m[3]).replace(/\\$/, ""));
  }
  return out;
}

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
// runs a SCOPED, GUARDED `terraform apply -replace='hcloud_server.git_data'` + its `-target`s
// (server + private NIC + the LUKS volume attachment + firewall attachment + the host-key pin) to
// re-run the git-data host's cloud-init WITHOUT SSH. UNLIKE registry, the LUKS data volume
// (hcloud_volume.git_data_luks) and the LUKS passphrase are PRESERVED BY OMISSION — deliberately
// NOT in the base -target set. This guard pins the target/replace set to EXACTLY the git-data
// addresses below, proves the retired plaintext pair is in NO -target/-replace line of either
// git-data dispatch job, and asserts the dispatch job is stripped from the per-merge coverage
// anchor. It locks the load-bearing invariant that the workflow's `-target` lines correspond 1:1
// to the gate's allow-set (a drift on either side would otherwise only surface at live-dispatch
// time).
const GIT_DATA_REPLACE_TARGETS = [
  "hcloud_server.git_data",
  "hcloud_server_network.git_data",
  "hcloud_volume_attachment.git_data_luks",
  "hcloud_firewall_attachment.git_data",
  // (#7226, ADR-237) The pin is re-published by the replace that rotates the key.
  "doppler_secret.git_data_ssh_host_key",
];
// (#7226, ADR-237) The replace rotates the SSH host key in LOCKSTEP with the host: dropping the
// key's -replace re-uses a key a rooted host could have exfiltrated (ADR-220 D6).
const GIT_DATA_REPLACE_REPLACES = ["hcloud_server.git_data", "tls_private_key.git_data_host_ssh"];
// (#8211 PR2 / ADR-220 D6) The ROTATE arm's conditional additions — the LUKS store trio
// move together, only under apply_target=git-data-host-rotate (EXTRA_REPLACE/EXTRA_TARGET
// in the plan step). A partial set here is a stranding, not a rotate.
const GIT_DATA_ROTATE_REPLACES = ["hcloud_volume.git_data_luks", "random_password.git_data_luks"];
const GIT_DATA_ROTATE_TARGETS = [
  "hcloud_volume.git_data_luks",
  "random_password.git_data_luks",
  "doppler_secret.git_data_luks_key",
];
// (#11194) The plaintext pair destroyed at the provider on 2026-10-27 and removed from the HCL. It
// must appear in NO `-target`/`-replace` line of either git-data dispatch job: a `-target` that
// matches nothing exits 0 silently (terraform), so only this assertion — not the plan — notices a
// re-added line. (The LUKS volume is preserved by omission from the BASE set and joins only inside
// the rotate arm's EXTRA_ conditional; that half is pinned by the rotate-trio test below.)
const GIT_DATA_RETIRED_ADDRESSES = ["hcloud_volume.git_data", "hcloud_volume_attachment.git_data"];
// Every `-target=`/`-replace=` flag in a job block that names a retired address (exact address, so
// the `_luks` siblings never match). Comment lines are excluded.
function retiredFlagLines(block: string): string[] {
  const alt = GIT_DATA_RETIRED_ADDRESSES.map((a) => a.replace(/\./g, "[.]")).join("|");
  const re = new RegExp(`-(?:target|replace)=['"]?(?:${alt})(?![A-Za-z0-9_])`);
  return block.split("\n").filter((l) => !/^\s*#/.test(l) && re.test(l));
}
// The same scan, counting every git-data flag line it COULD have matched (non-vacuity).
function gitDataFlagLines(block: string): string[] {
  return block.split("\n").filter((l) => !/^\s*#/.test(l) && /-(?:target|replace)=['"]?[a-z_]+[.]git_data/.test(l));
}

describe("git-data-host-replace dispatch -target/-replace set (scoped; LUKS volume preserved by omission; plaintext pair retired)", () => {
  let gitDataTargets: string[];
  let gitDataJobBlock: string;
  let replaceAddrs: string[];
  let gitDataRotateTargets: string[];
  let rotateReplaces: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    gitDataJobBlock = extractJobBlock(wf, "git_data_host_replace");
    // (#8211 PR2) The rotate arm's -target/-replace additions live in EXTRA_TARGET /
    // EXTRA_REPLACE arrays, applied only when apply_target == 'git-data-host-rotate'.
    // Base = the unconditional lines; rotate = the EXTRA_ lines.
    const baseBlock = gitDataJobBlock
      .split("\n")
      .filter((l) => !l.includes("EXTRA_"))
      .join("\n");
    const rotateBlock = gitDataJobBlock
      .split("\n")
      .filter((l) => l.includes("EXTRA_"))
      .join("\n");
    gitDataTargets = extractTargetsWithKeys(baseBlock);
    replaceAddrs = extractReplaceAddrs(baseBlock);
    gitDataRotateTargets = extractTargetsWithKeys(rotateBlock);
    rotateReplaces = extractReplaceAddrs(rotateBlock);
  });

  test("the git_data_host_replace job -targets EXACTLY the git-data-replace resources", () => {
    expect([...gitDataTargets].sort()).toEqual(
      [...GIT_DATA_REPLACE_TARGETS].sort(),
    );
  });

  test("the -replace addresses are EXACTLY the git-data server and its SSH host key (lockstep, #7226)", () => {
    expect([...replaceAddrs].sort()).toEqual([...GIT_DATA_REPLACE_REPLACES].sort());
  });

  test("the -target ∪ -replace set EXACTLY equals the gate's allow-set (job↔gate parity)", () => {
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
    expect([...allowMembers].sort()).toEqual(
      [...new Set([...gitDataTargets, ...replaceAddrs])].sort(),
    );
  });

  // (#8211 PR2) Rotate arm: the EXTRA_TARGET/EXTRA_REPLACE lines hold EXACTLY the LUKS
  // trio, and the gate's rotate-extension allow list equals the same set.
  test("the rotate arm carries EXACTLY the LUKS store trio (volume + passphrase + key)", () => {
    expect([...gitDataRotateTargets].sort()).toEqual([...GIT_DATA_ROTATE_TARGETS].sort());
    expect([...rotateReplaces].sort()).toEqual([...GIT_DATA_ROTATE_REPLACES].sort());
  });

  test("the rotate set equals the gate's rotate-extension allow list (job↔gate parity)", () => {
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/git-data-host-replace-gate.sh"),
      "utf8",
    );
    const rotBlock = gateSrc.match(/\$mode == "rotate" then\s*\[([^\]]+)\]/);
    expect(rotBlock).not.toBeNull();
    const rotMembers = [...rotBlock![1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);
    expect([...rotMembers].sort()).toEqual(
      [...new Set([...gitDataRotateTargets, ...rotateReplaces])].sort(),
    );
  });

  test("the rotate precondition reads the GIT-DATA Better Stack table, not the shared default", () => {
    // git-data emits to its own source 2734275 (t520508_soleur_git_data_prd_logs); the
    // betterstack-query.sh default is the shared inngest source, which answers zero rows
    // for host_name=soleur-git-data forever — the precondition would fail closed every
    // dispatch. The env pin (BS_TABLE="$BS_GIT_DATA_TABLE") is the anchored contract.
    // The read itself lives in scripts/lib/git-data-boot-signal-poll.sh —
    // git_data_served_empty_read pins the table/env there; the step must call it.
    expect(gitDataJobBlock).toContain("git_data_served_empty_read");
    const libSrc = readFileSync(
      resolve(REPO_ROOT, "scripts/lib/git-data-boot-signal-poll.sh"),
      "utf8",
    );
    expect(libSrc).toContain('BS_TABLE="$BS_GIT_DATA_TABLE"');
    expect(libSrc).toContain('BS_TABLE_S3="$BS_GIT_DATA_TABLE_S3"');
    expect(libSrc).toContain("JSONExtractString(raw,'stage') = 'boot_complete'");
    expect(libSrc).toContain("JSONExtractString(raw,'host_name') = 'soleur-git-data'");
    expect(libSrc).toContain("--only-secrets");
  });

  test("the rotate arm is conditional on apply_target=git-data-host-rotate", () => {
    // The EXTRA_* additions apply only when the dispatch selected the rotate target —
    // the bash check inside the plan step is what gates them.
    expect(gitDataJobBlock).toContain('inputs.apply_target }}" == "git-data-host-rotate"');
  });

  test("the gate is invoked with the mode argument (rotate passes through)", () => {
    expect(gitDataJobBlock).toMatch(/git_data_host_replace_gate\s+tfplan\.json\s+"?\$?GATE_MODE/);
  });

  test("the apply step grades the saved plan through the mode-aware post-apply backstop (#10137)", () => {
    // The apply step used to carry an inline loop asserting BOTH data volumes preserved, which failed
    // the rotate dispatch on its own intended LUKS replace. Every pin below runs on the step with
    // comments stripped, anchored on a non-comment line: a comment that quotes the construct (the
    // step documents all of them) must not satisfy a pin.
    const raw = extractStep(gitDataJobBlock, /Terraform apply \(git-data-host -replace\)/);
    expect(raw, "apply step not found in git_data_host_replace").not.toBeNull();
    const step = stripComments(raw!);
    // Step shape the flip gate / poll / summary key on, and nothing that tolerates a refusal.
    expect(step).toMatch(/^\s*id: apply$/m);
    expect(step).toMatch(/^\s*if: inputs\.plan_only != true$/m);
    expect(step, "a continue-on-error (any quoting) would turn a refusal into a tolerated failure").not.toMatch(/continue-on-error/);
    // The mode is the one the plan step's gate accepted, read through env (no second mapping).
    expect(step).toMatch(/^\s*GATE_MODE: \$\{\{ steps\.plan\.outputs\.gate_mode \}\}$/m);
    expect(step).not.toContain("APPLY_TARGET");
    // The lib is actually sourced, at the step's top level, and the guarded call follows it
    // IMMEDIATELY: nothing between them can wrap the call in a condition or reassign the mode.
    const src = step.match(/^ {10}source "\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/git-data-host-replace-gate\.sh"$/m);
    expect(src, "the lib must be sourced by a real top-level line").not.toBeNull();
    const callRe = /^ {10}if ! git_data_host_post_apply_assert tfplan\.json "\$\{GATE_MODE:-\}"; then\n([\s\S]*?)\n {10}fi\n/m;
    const call = step.match(callRe);
    expect(call, "the post-apply call must be a top-level `if ! … ; then … fi`").not.toBeNull();
    expect(step.slice(src!.index! + src![0].length, call!.index!).trim()).toBe("");
    // The refusal body must actually exit 1 (an annotation alone lets the job go green).
    expect(call![1]).toMatch(/^\s*exit 1$/m);
    // The call comes after the terraform apply, and nothing between them reassigns the mode or
    // exits successfully early.
    const applyAt = step.indexOf("terraform apply -no-color -input=false tfplan");
    expect(applyAt).toBeGreaterThan(-1);
    expect(applyAt).toBeLessThan(call!.index!);
    // (scanned from the START of the step: a reassignment before the apply line is the same failure)
    expect(step.slice(0, call!.index!)).not.toMatch(/\bGATE_MODE\+?=|-v GATE_MODE|\bread\b[^\n]*\bGATE_MODE\b|GATE_MODE:=|\bexit 0\b/);
    // The inline loop is gone, and the old display name (false under rotate) with it.
    expect(step).not.toMatch(/for VOL in hcloud_volume\.git_data/);
    expect(gitDataJobBlock).not.toContain("both-volumes-preserved assert");
    expect(gitDataJobBlock).toContain("Validate dispatch inputs (rotate confirm token)");
    // The rotate failure annotation is its own arm, and an unknown mode takes a neutral arm rather
    // than the plain-replace claim that both volumes are preserved.
    expect(step).toMatch(/^\s*rotate\)\n\s*echo "::error::terraform apply \(git-data-host-rotate\) failed mid-replace/m);
    expect(step).toMatch(/^\s*\*\)\n\s*echo "::error::terraform apply \(git-data host\) failed mid-replace and the dispatch mode is unknown/m);
    // Exactly one call site in the job (the Observability probe counts it).
    expect(gitDataJobBlock.match(/git_data_host_post_apply_assert tfplan\.json/g)?.length).toBe(1);
  });

  test("the plan step publishes the mode its gate accepted, once, directly after the gate block (#10137)", () => {
    const raw = extractStep(gitDataJobBlock, /Terraform plan \(scoped git-data-host -replace\)/);
    expect(raw, "plan step not found in git_data_host_replace").not.toBeNull();
    const step = stripComments(raw!);
    const publish = "printf 'gate_mode=%s\\n' \"$GATE_MODE\" >> \"$GITHUB_OUTPUT\"";
    expect(step.split(publish).length - 1, "the plan step must publish gate_mode exactly once").toBe(1);
    const gateCall = step.indexOf('if ! git_data_host_replace_gate tfplan.json "$GATE_MODE"; then');
    expect(gateCall).toBeGreaterThan(-1);
    // The gate block closes at the step's top-level `fi` (a nested `fi` is indented deeper).
    const closeAt = step.indexOf("\n          fi\n", gateCall);
    expect(closeAt).toBeGreaterThan(gateCall);
    const publishAt = step.indexOf(publish);
    expect(publishAt).toBeGreaterThan(closeAt);
    // Directly after the gate block, at the top level: nothing between the gate's closing `fi` and
    // the publish, so it is unconditional and cannot follow a reassignment of the mode (the #10137
    // failure shape: rotate graded as replace again, with the gate having accepted rotate).
    expect(step.slice(closeAt + "\n          fi\n".length, publishAt).trim()).toBe("");
    expect(step.slice(step.lastIndexOf("\n", publishAt) + 1, publishAt)).toBe("          ");
    // One reader of the output in the whole job.
    expect(gitDataJobBlock.split("steps.plan.outputs.gate_mode").length - 1).toBe(1);
  });

  test("neither retired plaintext address is in ANY -target/-replace line of the replace job or the create job (#11194)", () => {
    // The retired pair is in no .tf file, so a re-added line would match nothing and terraform
    // would exit 0 silently; the gates' allow-sets would then also have to be widened to PASS it,
    // which the retired-address rows in their suites refuse. This is the workflow half.
    const createBlock = extractJobBlock(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"), "git_data_host_create");
    // Non-vacuity: the scan sees real git-data flag lines in BOTH jobs, so "none retired" is a
    // property of those lines rather than of an empty extraction.
    expect(gitDataFlagLines(gitDataJobBlock).length).toBeGreaterThan(3);
    expect(gitDataFlagLines(createBlock).length).toBeGreaterThan(10);
    expect(retiredFlagLines(gitDataJobBlock)).toEqual([]);
    expect(retiredFlagLines(createBlock)).toEqual([]);
    // Detector control: the scan DOES flag a retired flag line, and spares the LUKS siblings.
    expect(retiredFlagLines("  -target='hcloud_volume_attachment.git_data' \\")).toHaveLength(1);
    expect(retiredFlagLines("  -replace='hcloud_volume.git_data' \\")).toHaveLength(1);
    expect(retiredFlagLines("  -target='hcloud_volume.git_data_luks' \\")).toHaveLength(0);
    expect(retiredFlagLines("  -target='hcloud_volume_attachment.git_data_luks' \\")).toHaveLength(0);
    expect(retiredFlagLines("  # -target='hcloud_volume.git_data' (a comment)")).toHaveLength(0);
  });

  test("every git-data-replace target's base address is an OPERATOR_APPLIED_EXCLUSION", () => {
    for (const t of [...gitDataTargets, ...replaceAddrs, ...gitDataRotateTargets, ...rotateReplaces]) {
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

// ─── (#11194, ADR-239 Amendment 2026-10-28) the plaintext-id interlock on both git-data dispatch jobs ──
//
// Between the PR that retires the plaintext arms from the gates and the PR that blanks
// `git_data_volume_id` in git-data.tf, the gates PASS a plaintext-free plan while the module call
// still renders a destroyed device id into `user_data`: a dispatch in that window would replace the
// live host into the bootstrap's `plaintext_unverified` FATAL. `git_data_plaintext_id_interlock`
// (tests/scripts/lib/git-data-birth-readiness-gate.sh) refuses it. These pins hold the WIRING: a
// function nobody calls protects nothing, and the function's own verdicts live in
// tests/scripts/test-git-data-birth-readiness-gate.sh. Each pin runs on the step with comments
// stripped, anchored on a real top-level line a comment cannot produce.
//
// The step carries NO `if:` in either job (the census suite's G5c row, ADR-241 D-Guard-5, forbids
// one on a gate step). In the replace job (which also serves rotate) a refusal is downgraded to a
// warning only when PLAN_ONLY is the exact string `true`; everything else blocks.
const IL_SOURCE_LINE =
  /^ {10}source "\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/git-data-birth-readiness-gate\.sh"$/m;
const IL_CALL =
  /^ {10}if ! git_data_plaintext_id_interlock "\$\{GITHUB_WORKSPACE\}\/apps\/web-platform\/infra\/git-data\.tf"; then\n([\s\S]*?)\n {10}fi$/m;
// The replace job's refusal body: the strict `true` downgrade (warning, no exit) beside a blocking
// else (error, exit 1). Both halves in one expression so neither can be dropped alone.
const IL_REPLACE_BODY =
  /^ {12}if \[\[ "\$\{PLAN_ONLY:-\}" == "true" \]\]; then\n {14}echo "::warning::[^\n]*"\n {12}else\n {14}echo "::error::[^\n]*"\n {14}exit 1\n {12}fi$/m;

/** The wiring predicate shared by the real-tree pin and its mutants. Returns the failed clauses. */
function interlockStepProblems(stepRaw: string, opts: { replaceJob: boolean }): string[] {
  const step = stripComments(stepRaw);
  const bad: string[] = [];
  if (!IL_SOURCE_LINE.test(step)) bad.push("source line");
  const call = step.match(IL_CALL);
  if (!call) bad.push("call");
  if (!/^\s*set -euo pipefail$/m.test(step)) bad.push("set -euo pipefail");
  if (/continue-on-error/.test(step)) bad.push("continue-on-error");
  // No `if:` on the step in either job (a condition is a way to skip a gate).
  if (/^ {8}if:/m.test(step)) bad.push("step-level if");
  if (opts.replaceJob) {
    if (!/^ {8}env:\n {10}PLAN_ONLY: \$\{\{ inputs\.plan_only \}\}$/m.test(step)) bad.push("PLAN_ONLY env");
    if (!call || !IL_REPLACE_BODY.test(call[0])) bad.push("strict downgrade + blocking default");
  } else {
    // The create route has no verification mode: a plain blocking refusal, no downgrade.
    if (!call || !/^\s*exit 1$/m.test(call[1])) bad.push("exit 1");
    if (/PLAN_ONLY|plan_only/.test(step)) bad.push("create job must not read plan_only");
  }
  return bad;
}

describe("git-data dispatch jobs run the plaintext-id interlock before planning (#11194)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");

  function stepOf(jobId: string, planTitle: RegExp): { raw: string; job: string } {
    const job = extractJobBlock(wf, jobId);
    const raw = extractStep(job, /Plaintext-id interlock/);
    expect(raw, `${jobId}: the interlock step must exist`).not.toBeNull();
    // It runs BEFORE the plan step: nothing has been planned or created when it refuses.
    const planRaw = extractStep(job, planTitle);
    expect(planRaw, `${jobId}: the plan step must exist`).not.toBeNull();
    expect(job.indexOf(raw!)).toBeGreaterThan(-1);
    expect(job.indexOf(raw!)).toBeLessThan(job.indexOf(planRaw!));
    return { raw: raw!, job };
  }

  test("git_data_host_replace (replace and rotate): the interlock precedes the plan, is unconditional, and downgrades only on plan_only == true", () => {
    const { raw } = stepOf("git_data_host_replace", /Terraform plan \(scoped git-data-host -replace\)/);
    expect(interlockStepProblems(raw, { replaceJob: true })).toEqual([]);
  });

  test("git_data_host_create: the interlock precedes the plan and is plainly blocking", () => {
    const { raw } = stepOf("git_data_host_create", /Terraform plan \(scoped git-data birth\)/);
    expect(interlockStepProblems(raw, { replaceJob: false })).toEqual([]);
  });

  test("the wiring predicate reds on each way to disarm the replace-job step (mutation battery, control first)", () => {
    const { raw } = stepOf("git_data_host_replace", /Terraform plan \(scoped git-data-host -replace\)/);
    // CONTROL: the unmutated step is clean, so every red below is the mutation's.
    expect(interlockStepProblems(raw, { replaceJob: true })).toEqual([]);
    const mutants: Array<[string, (t: string) => string, string]> = [
      ["a step-level if: skipping the gate", (t) => t.replace("        env:\n", "        if: inputs.plan_only != true\n        env:\n"), "step-level if"],
      ["a non-strict downgrade (!= \"false\")", (t) => t.replace('== "true" ]]; then', '!= "false" ]]; then'), "strict downgrade"],
      ["a downgrade that is always taken", (t) => t.replace('if [[ "${PLAN_ONLY:-}" == "true" ]]; then', "if true; then"), "strict downgrade"],
      ["the blocking exit dropped from the else arm", (t) => t.replace("              exit 1\n            fi\n          fi", "            fi\n          fi"), "strict downgrade"],
      ["the call removed", (t) => t.replace(/git_data_plaintext_id_interlock "/, 'true "'), "call"],
      ["continue-on-error added", (t) => t.replace("        env:\n", "        continue-on-error: true\n        env:\n"), "continue-on-error"],
    ];
    for (const [label, mutate, clause] of mutants) {
      const m = mutate(raw);
      expect(m, `mutation did not land: ${label}`).not.toBe(raw);
      expect(interlockStepProblems(m, { replaceJob: true }).join("|"), label).toContain(clause);
    }
    // The create job must NOT grow a downgrade: its pin reds when one appears.
    const createRaw = stepOf("git_data_host_create", /Terraform plan \(scoped git-data birth\)/).raw;
    const withDowngrade = createRaw.replace("        run: |", "        env:\n          PLAN_ONLY: ${{ inputs.plan_only }}\n        run: |");
    expect(withDowngrade).not.toBe(createRaw);
    expect(interlockStepProblems(withDowngrade, { replaceJob: false }).join("|")).toContain("create job must not read plan_only");
  });

  test("EXECUTED: the replace-job step blocks (rc 1) on a non-empty literal unless PLAN_ONLY is exactly `true` (then a warning, rc 0), and passes on an empty one", () => {
    const { raw } = stepOf("git_data_host_replace", /Terraform plan \(scoped git-data-host -replace\)/);
    const runBody = raw.split("\n").slice(raw.split("\n").findIndex((l) => /^ {8}run: \|$/.test(l)) + 1);
    const script = runBody.map((l) => l.replace(/^ {10}/, "")).join("\n");
    expect(script).toContain("git_data_plaintext_id_interlock");
    const ws = mkdtempSync(resolve(tmpdir(), "il-wf-"));
    try {
      mkdirSync(resolve(ws, "tests/scripts"), { recursive: true });
      mkdirSync(resolve(ws, "apps/web-platform/infra"), { recursive: true });
      symlinkSync(resolve(REPO_ROOT, "tests/scripts/lib"), resolve(ws, "tests/scripts/lib"));
      const tf = resolve(ws, "apps/web-platform/infra/git-data.tf");
      const run = (literal: string, planOnly: string | undefined) => {
        writeFileSync(tf, `module "git_data_userdata" {\n  git_data_volume_id = ${literal}\n}\n`);
        const env: Record<string, string> = { PATH: process.env.PATH ?? "", GITHUB_WORKSPACE: ws };
        if (planOnly !== undefined) env.PLAN_ONLY = planOnly;
        const r = spawnSync("bash", ["-c", script], { env, encoding: "utf8" });
        return { rc: r.status, out: `${r.stdout}${r.stderr}` };
      };
      // CONTROL: an empty literal passes in every mode, so the refusals below are the literal's.
      for (const po of [undefined, "false", "true"]) expect(run('""', po).rc, `empty literal, PLAN_ONLY=${po}`).toBe(0);
      for (const po of [undefined, "", "false", "TRUE", "1", "yes"]) {
        const r = run('"106867358"', po);
        expect([po, r.rc]).toEqual([po, 1]);
        expect(r.out).toContain("::error::");
        expect(r.out, "the value must never reach the log").not.toContain("106867358");
      }
      const dg = run('"106867358"', "true");
      expect(dg.rc).toBe(0);
      expect(dg.out).toContain("::warning::plan_only");
      expect(dg.out).not.toContain("::error::");
      expect(dg.out, "the value must never reach the log").not.toContain("106867358");
    } finally {
      rmSync(ws, { recursive: true, force: true });
    }
  });
});

// ─── (#7226, ADR-237) host-key pinning: the per-PR list, the probe, the redeploy jobs ────
//
// Guard 4 row 6: neither git-data pin address may ride the per-PR apply — a routine merge
// would publish a pin the live host does not carry (plan R1). The merge-time web-1 probe
// (terraform_data.web_1_host_key_probe) MUST ride it, with the pinned Terraform version fed in,
// because a Terraform bump can change x/crypto's host-key algorithm order (plan R4) and the
// probe's trigger folds the version in. And each git-data birth/replace is followed by a
// secret-free job that forces a web release so the app loads the rotated pin (plan D6).
const GIT_DATA_PIN_ADDRS = ["tls_private_key.git_data_host_ssh", "doppler_secret.git_data_ssh_host_key"];
const PIN_REDEPLOY_WORKFLOW = resolve(REPO_ROOT, ".github/workflows/git-data-pin-redeploy.yml");
// Every workflow that plans/applies the MAIN root (apps/web-platform/infra). Each must feed
// TF_VAR_terraform_version equal to its own TERRAFORM_VERSION, or web_1_host_key_probe's trigger
// differs per workflow and the drift job reports a phantom probe replacement.
const MAIN_ROOT_TF_WORKFLOWS = [
  "apply-web-platform-infra.yml",
  "apply-deploy-pipeline-fix.yml",
  "scheduled-terraform-drift.yml",
  "infra-validation.yml",
];

describe("host-key pinning: per-PR list, merge-time probe, pin redeploy (#7226)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const applyJob = extractJobBlock(wf, "apply");
  const sshApply = extractStep(applyJob, /Terraform apply \(SSH-provisioned resources, over the bridge\)/) ?? "";

  test("the per-PR SSH apply step resolves and targets the web-1 host-key probe", () => {
    expect(sshApply.length).toBeGreaterThan(0);
    expect(extractAllTargets(sshApply).has("terraform_data.web_1_host_key_probe")).toBe(true);
  });

  test("Guard 4 row 6: neither pin address is on ANY per-merge -target list", () => {
    const perMerge = extractAllTargets(stripDispatchJobs(wf));
    for (const a of GIT_DATA_PIN_ADDRS) expect(perMerge.has(a)).toBe(false);
    expect(perMerge.has("terraform_data.web_1_host_key_probe")).toBe(true);
    // Every OTHER main-root planner too (apply-deploy-pipeline-fix applies per merge; the
    // drift / validation plans must never grow a -target on a pin address either).
    for (const f of MAIN_ROOT_TF_WORKFLOWS) {
      const t = extractAllTargets(stripDispatchJobs(readFileSync(resolve(REPO_ROOT, ".github/workflows", f), "utf8")));
      for (const a of GIT_DATA_PIN_ADDRS) expect([f, a, t.has(a)]).toEqual([f, a, false]);
    }
  });

  test("the birth job -targets both pin addresses; the replace job -replace's the key and -targets the pin", () => {
    const birth = extractAllTargets(extractJobBlock(wf, "git_data_host_create"));
    for (const a of GIT_DATA_PIN_ADDRS) expect(birth.has(a)).toBe(true);
    const replaceJob = extractJobBlock(wf, "git_data_host_replace");
    expect(extractReplaceAddrs(replaceJob)).toContain("tls_private_key.git_data_host_ssh");
    expect(extractAllTargets(replaceJob).has("doppler_secret.git_data_ssh_host_key")).toBe(true);
  });

  for (const job of ["git_data_host_create", "git_data_host_replace"]) {
    test(`${job}: prints ONLY a regex-validated SHA256 fingerprint to the summary after apply`, () => {
      const block = stripComments(extractJobBlock(wf, job));
      expect(block).toContain("terraform output -raw git_data_ssh_host_key_fingerprint");
      expect(block).toMatch(/\[\[ "\$fp" =~ \^SHA256:\[A-Za-z0-9\+\/\]\{43\}\$ \]\]; then echo "git-data host key fingerprint: \$fp" >> "\$GITHUB_STEP_SUMMARY"; echo "::notice title=git-data-pin::git-data host key fingerprint: \$fp"; else/);
    });
  }

  test("the apply workflow carries NO release-poll redeploy JOB (a job, not a step, would hold the fleet-wide apply lock)", () => {
    const jobs = Object.keys((parseYaml(wf) as { jobs: Record<string, unknown> }).jobs);
    // (#8211 PR2) The inline pin_load STEPS run track.sh — a minutes-long webhook poll
    // inside the (short) apply job, which is exactly what the lock can afford. What stays
    // barred is a redeploy JOB or the release-dispatch machinery (gh workflow run /
    // workflow_run polling), which is the 70-minute shape that forced the follower split.
    expect(jobs.filter((j) => /redeploy/.test(j))).toEqual([]);
    const stripped = stripComments(wf);
    expect(stripped).not.toContain("source-run-gate.sh");
    expect(stripped).not.toContain("gh workflow run web-platform-release");
  });

  test("every main-root Terraform workflow feeds TF_VAR_terraform_version == its TERRAFORM_VERSION", () => {
    for (const f of MAIN_ROOT_TF_WORKFLOWS) {
      const doc = parseYaml(readFileSync(resolve(REPO_ROOT, ".github/workflows", f), "utf8")) as {
        env?: Record<string, unknown>;
        jobs?: Record<string, { env?: Record<string, unknown>; steps?: Array<{ name?: string; env?: Record<string, unknown> }> }>;
      };
      const env = doc.env ?? {};
      expect(typeof env.TERRAFORM_VERSION).toBe("string");
      expect([f, env.TF_VAR_terraform_version]).toEqual([f, env.TERRAFORM_VERSION]);
      // A job- or step-level env: override of either key to another value would split the
      // probe trigger per job. Undefined (inherit) is the only other accepted value.
      for (const [jn, job] of Object.entries(doc.jobs ?? {})) {
        const scopes: Array<[string, Record<string, unknown> | undefined]> = [[`${f}:${jn}`, job?.env]];
        for (const [i, st] of (job?.steps ?? []).entries()) scopes.push([`${f}:${jn}:step${i}(${st?.name ?? ""})`, st?.env]);
        for (const [where, e] of scopes) {
          for (const k of ["TF_VAR_terraform_version", "TERRAFORM_VERSION"]) {
            if (e && k in e) expect([where, k, e[k]]).toEqual([where, k, env.TERRAFORM_VERSION]);
          }
        }
      }
    }
  });

  // #6604 step 7 — a workflow that WRITES the main root's state outside plan/apply (a dispatched
  // `terraform state rm|mv|push`). The last one, the single-use workspaces-plaintext-forget.yml, was
  // retired in #6604 PR B, so this row's old per-writer TERRAFORM_VERSION loop iterated over ZERO
  // files and asserted nothing. It is now an EXACT-EMPTY assertion instead: a state write can forget
  // hcloud_volume.workspaces_luks (prevent_destroy is config-scoped and does not see a `state rm`) and
  // reopen the bare-create recut shape, and a Terraform version other than the apply workflows' could
  // upgrade the state format under them. A new writer must edit this row deliberately, and pin
  // TERRAFORM_VERSION to apply-web-platform-infra's when it does.
  test("no workflow writes main-root state outside plan/apply (terraform state rm|mv|push)", () => {
    const dir = resolve(REPO_ROOT, ".github/workflows");
    const STATE_WRITE = /terraform\s+(?:-chdir=\S+\s+)?state\s+(rm|mv|push|replace-provider)\b/;
    // The four main-root spellings the planner census below uses, not just INFRA_DIR.
    const MAIN_ROOT_FORMS = [
      /INFRA_DIR:\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /^\s*-\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /working-directory:\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /-chdir=["']?apps\/web-platform\/infra(?![\w\/-])/,
    ];
    const isWriter = (t: string) => STATE_WRITE.test(t) && MAIN_ROOT_FORMS.some((re) => re.test(t));
    // Non-vacuity: the discovery predicate must match the shapes it exists for (the retired forget
    // workflow's, and a -chdir spelling), and must not match a planner.
    expect(isWriter("env:\n  INFRA_DIR: apps/web-platform/infra\n        run: terraform state rm \"${addrs[@]}\"")).toBe(true);
    expect(isWriter("        run: terraform -chdir=apps/web-platform/infra state rm 'hcloud_volume_attachment.workspaces_luks'")).toBe(true);
    expect(isWriter("env:\n  INFRA_DIR: apps/web-platform/infra\n        run: terraform plan -out=tfplan")).toBe(false);
    const writers = readdirSync(dir)
      .filter((f) => f.endsWith(".yml"))
      .filter((f) => isWriter(stripComments(readFileSync(join(dir, f), "utf8"))));
    expect(writers).toEqual([]);
  });

  test("the main-root workflow census is complete (a new planner cannot skip the variable)", () => {
    const dir = resolve(REPO_ROOT, ".github/workflows");
    // Every spelling of "this workflow runs Terraform in the main root": an INFRA_DIR env, a
    // static matrix entry, a literal working-directory, or `terraform -chdir=`. Sub-roots
    // (apps/web-platform/infra/<sub>) do not match: each pattern ends at the root.
    const MAIN_ROOT_FORMS = [
      /INFRA_DIR:\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /^\s*-\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /working-directory:\s*["']?apps\/web-platform\/infra["']?\s*$/m,
      /-chdir=["']?apps\/web-platform\/infra(?![\w\/-])/,
    ];
    const found = readdirSync(dir)
      .filter((f) => f.endsWith(".yml"))
      .filter((f) => {
        const t = stripComments(readFileSync(join(dir, f), "utf8"));
        const plans = /terraform\s+(-chdir=\S+\s+)?(plan|apply)\b/.test(t);
        return plans && MAIN_ROOT_FORMS.some((re) => re.test(t));
      })
      .sort();
    // Exact: infra-validation.yml is the one planner the census cannot see (its matrix is
    // computed at runtime from a changed-files job), so it is listed by hand; every other
    // entry must be found, and nothing else may be.
    expect(found).toEqual(MAIN_ROOT_TF_WORKFLOWS.filter((f) => f !== "infra-validation.yml").sort());
    expect(found.length).toBe(3);
  });

  // ─── Inline pin-load arm (follower retired, #8211 PR2 / ADR-237 D6 amendment) ───────
  // git-data-pin-redeploy.yml + dispatch-web-redeploy/source-run-gate.sh are DELETED: the
  // follower's only reason for a separate workflow was a 70-minute release-run poll that
  // could not sit inside the apply lock. The webhook mechanism (track.sh: POST
  // /hooks/deploy + deploy-status frame poll) is minutes, so the pin-load is a STEP inside
  // each git-data job, after the verified boot poll. These pins hold the arm's shape:
  describe("inline git-data pin-load (the retired follower, inlined)", () => {
    const wfd = parseYaml(wf) as Record<string, any>;
    const gitDataJobs = ["git_data_host_create", "git_data_host_replace"];
    const pinLoad = (doc: Record<string, any>, job: string) =>
      ((doc.jobs?.[job]?.steps ?? []) as any[]).filter((s) => s.id === "pin_load");
    const trackUsers = (doc: Record<string, any>) =>
      Object.keys(doc.jobs ?? {}).filter((j) =>
        ((doc.jobs[j].steps ?? []) as any[]).some((s) => String(s.run ?? "").includes("dispatch-web-redeploy/track.sh")),
      );
    const freshLockDoc = () => parseYaml(wf) as Record<string, any>;
    function pinLoadParity(doc: Record<string, any>): string[] {
      const v: string[] = [];
      for (const job of gitDataJobs) {
        const hits = pinLoad(doc, job);
        if (hits.length !== 1) {
          v.push(`PL1 ${job}: ${hits.length} pin_load steps`);
          continue;
        }
        const s = hits[0];
        if (!String(s.run ?? "").includes("dispatch-web-redeploy/track.sh")) v.push(`PL1 ${job}: the pin_load step does not run track.sh`);
        if (!String(s.if ?? "").includes("steps.poll.outcome == 'success'")) v.push(`PL1 ${job}: the pin_load step's if: dropped the poll-success gate`);
        if (!String(s.if ?? "").includes("plan_only")) v.push(`PL1 ${job}: the pin_load step's if: dropped the plan_only guard`);
      }
      return v;
    }

    test("PL1: both git-data jobs run track.sh as id: pin_load, only on a verified boot", () => {
      for (const job of gitDataJobs) {
        const hits = pinLoad(wfd, job);
        expect(hits.length, `${job}: exactly one pin_load step`).toBe(1);
        const s = hits[0];
        expect(String(s.run ?? "")).toContain("dispatch-web-redeploy/track.sh");
        // A pin-load before boot-complete would redeploy the fleet to trust a key whose
        // host never came up — the poll verdict is the gate.
        expect(String(s.if ?? "")).toContain("steps.poll.outcome == 'success'");
        expect(String(s.if ?? "")).toContain("plan_only");
      }
    });

    test("PL1 RED: a pin_load missing its poll gate, or a pin-load step not running track.sh, is a violation", () => {
      const doc = freshLockDoc();
      const s = pinLoad(doc, "git_data_host_replace")[0];
      s.if = "";
      expect(pinLoadParity(doc)).toEqual([
        "PL1 git_data_host_replace: the pin_load step's if: dropped the poll-success gate",
        "PL1 git_data_host_replace: the pin_load step's if: dropped the plan_only guard",
      ]);
      const doc2 = freshLockDoc();
      pinLoad(doc2, "git_data_host_replace")[0].run = "echo hello";
      expect(pinLoadParity(doc2)).toEqual([
        "PL1 git_data_host_replace: the pin_load step does not run track.sh",
      ]);
    });

    test("PL2: the pin-load reads webhook creds from prd_terraform only, and fans out to every web host", () => {
      for (const job of gitDataJobs) {
        const s = pinLoad(wfd, job)[0];
        const run = String(s.run ?? "");
        expect(run).toContain("-p soleur -c prd_terraform");
        expect(run).toContain("WEBHOOK_DEPLOY_SECRET");
        // The peers CSV must be present — a single-host swap leaves the fleet MIXED.
        expect(String((s.env as any)?.WEB_HOST_PRIVATE_IPS ?? "")).toBe("10.0.1.10,10.0.1.11");
      }
    });

    test("PL3: track.sh runs ONLY from the two git-data pin-load steps, in the whole apply workflow", () => {
      expect(trackUsers(wfd).sort()).toEqual(gitDataJobs.slice().sort());
    });

    test("PL4: the retired follower is really gone — no git-data-pin-redeploy workflow, no source-run-gate.sh", () => {
      expect(existsSync(PIN_REDEPLOY_WORKFLOW)).toBe(false);
      expect(existsSync(resolve(REPO_ROOT, ".github/actions/dispatch-web-redeploy/source-run-gate.sh"))).toBe(false);
    });
  });
});

// ─── web-host-create dispatch: the birth path's -target set + gate pairing ────
// `apply_target=web-host-create` (#6730, ADR-145) is the ONLY automated route allowed
// to BIRTH an hcloud_server.web. (Since #6969, `web-host-replace` also creates one as the
// create half of a delete+create — a different contract, graded by a different gate; see the
// web-host-replace block below.) Every other route HALTs on host_creates > 0, and that
// HALT is not inherited — it is a separate inline copy in the `apply` job whose `if:` is
// mutually exclusive with every dispatch job. So this job's own sourced gate is not
// defense-in-depth behind an existing check; for this path it is the ONLY check, and
// this guard is what stops a future refactor from silently unhooking it.
//
// The -target set is the whole per-host fan-out. Getting it WRONG is not a cosmetic
// scoping error: a server born without hcloud_server_network has no private IP, and
// hcloud_firewall_attachment is documented (hcloud provider 1.63.0) NOT to attach before
// first boot — that combination IS #6416. The four monitoring addresses matter for a
// quieter reason: web-probe-envwrite.sh resolves WEB_NIC_GUARD_URL_<KEY> from Doppler on
// the fresh host, so a birth that omits them produces a host whose heartbeats never fire
// while every other signal looks green.
const WEB_HOST_BIRTH_TARGET_BASES = [
  "hcloud_server.web",
  "hcloud_server_network.web",
  "hcloud_volume.workspaces",
  "hcloud_volume_attachment.workspaces",
  // Singleton over `[for h in hcloud_server.web : h.id]` — unkeyed by construction.
  "hcloud_firewall_attachment.web",
  // The apex A record, pinned to web-1's ipv4_address. A DEPENDENT of hcloud_server.web,
  // so `-target`'s upstream-only transitivity never pulls it in implicitly.
  "cloudflare_record.app",
  "betteruptime_heartbeat.web_zot_consumer",
  "betteruptime_heartbeat.web_nic_guard",
  "betteruptime_heartbeat.web_bash_synthetic",
  "doppler_secret.web_zot_consumer_url",
  "doppler_secret.web_nic_guard_url",
  "doppler_secret.web_bash_synthetic_url",
];
// The FLEET-SCOPED members: singletons with no per-host instance, so they carry no
// `["<key>"]` and are exempt from the same-key assertion below.
const WEB_HOST_BIRTH_UNKEYED = [
  "hcloud_firewall_attachment.web",
  "cloudflare_record.app",
];
// The bases that are per-merge covered, so stripping the job cannot lose coverage.
const WEB_HOST_BIRTH_PER_MERGE_COVERED = [
  "hcloud_firewall_attachment.web",
  "betteruptime_heartbeat.web_zot_consumer",
  "betteruptime_heartbeat.web_nic_guard",
  "betteruptime_heartbeat.web_bash_synthetic",
  "doppler_secret.web_zot_consumer_url",
  "doppler_secret.web_nic_guard_url",
  "doppler_secret.web_bash_synthetic_url",
];

/**
 * `-target` values for a job whose keys are SHELL-INTERPOLATED rather than literal.
 *
 * extractTargetsWithKeys assumes the sibling dispatch shape
 * `-target='hcloud_server.web["web-2"]'` — single quotes around a hardcoded key. This
 * job cannot use it: single quotes suppress the `${WEB_HOST_KEY}` expansion that makes
 * the job generic over var.web_hosts, so its targets are double-quoted with escaped
 * inner quotes (`-target="hcloud_server.web[\"${WEB_HOST_KEY}\"]"`). Fed to the shared
 * extractor, the outer-quote match stops at the first `\"` and yields a truncated
 * `hcloud_server.web[\` — which is why this exists rather than a widened shared regex:
 * the other callers genuinely want the literal-key shape, and loosening the shared one
 * to tolerate escapes would make THEIR assertions accept an interpolated target too.
 */
function extractEscapedQuotedTargets(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(/-target="((?:[^"\\]|\\.)*)"/g)) {
    // Unescape so the result reads like the address terraform receives.
    out.push(m[1].replace(/\\"/g, '"'));
  }
  return out;
}

describe("web-host-create dispatch -target set + birth-gate pairing (#6730)", () => {
  let jobBlock: string;
  let keyedTargets: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    jobBlock = extractJobBlock(wf, "web_host_create");
    keyedTargets = extractEscapedQuotedTargets(jobBlock);
  });

  test("the job exists and its -target extraction is non-vacuous", () => {
    // Every assertion below reads jobBlock; an absent job yields "" and turns the
    // structural greps into silent passes. Fail here instead.
    expect(jobBlock).not.toEqual("");
    expect(keyedTargets.length).toBe(WEB_HOST_BIRTH_TARGET_BASES.length);
  });

  test("the -targets are EXACTLY the twelve per-host birth fan-out addresses", () => {
    const bases = [...new Set(keyedTargets.map((t) => t.replace(/\[.*$/, "")))];
    expect(bases.sort()).toEqual([...WEB_HOST_BIRTH_TARGET_BASES].sort());
  });

  test("every keyed -target interpolates the SAME dispatch key, never a literal host", () => {
    // One authorization births one host. A hardcoded `["web-1"]` slipped into the set —
    // or a second variable name — would let a dispatch for web-3 quietly touch another
    // host's volume or NIC, and the sourced gate grades against the key it was PASSED,
    // so a mismatched literal here is invisible to it.
    const keys = keyedTargets
      .map((t) => /\["([^"]*)"\]/.exec(t)?.[1])
      .filter((k): k is string => k !== undefined);
    // Named explicitly rather than as an off-by-N against the total: the first version
    // said "8 keyed + 1 unkeyed singleton (the firewall attachment)" and broke the moment a
    // SECOND unkeyed member (cloudflare_record.app) joined the set. An arithmetic
    // relationship to a list that grows is a constant pretending to be a derivation.
    expect(keys.length).toBe(
      WEB_HOST_BIRTH_TARGET_BASES.length - WEB_HOST_BIRTH_UNKEYED.length,
    );
    expect([...new Set(keys)]).toEqual(["${WEB_HOST_KEY}"]);
  });

  test("the job runs the sourced web_host_birth_gate and borrows no sibling gate", () => {
    // Same bare-token defect as the replace block below, and pre-existing — but ADR-145 §73-76
    // asserts "terraform-target-parity.test.ts pins the job<->gate pairing so a future refactor
    // cannot silently unhook it", which was measured FALSE for this job too. Fixed here rather
    // than filed: this PR already edits this file, and the claim is load-bearing for the one
    // route granted the host_creates capability.
    expect(jobBlock).toMatch(/^\s*source\s+\S*web-host-birth-gate\.sh/m);
    expect(jobBlock).toMatch(
      /\bweb_host_birth_gate\s+tfplan\.json\s+"\$\{WEB_HOST_KEY\}"/,
    );
    // A birth graded against a RETIRE or REPLACE allow-set is graded against the wrong
    // contract — the retire gate requires host_creates == 0, the exact inverse. Naming
    // each sibling explicitly (rather than a generic "one gate only" count) keeps the
    // failure message actionable.
    for (const sibling of [
      "web2-retire-gate.sh",
      "workspaces-luks-cutover-gate.sh",
      "workspaces-luks-recut-gate.sh",
      "registry-host-replace-gate.sh",
      "git-data-host-replace-gate.sh",
    ]) {
      expect(jobBlock).not.toContain(sibling);
    }
  });

  test("the job carries a required-reviewer environment gate", () => {
    // The sole human authorization on this path (the plan's own framing: an
    // authorization gate, not a task). The environment's reviewer set is pinned
    // non-empty by the DP-11 F8 guard below, which only reaches it because the
    // environment is declared in terraform.
    expect(jobBlock).toMatch(/^\s{4}environment:\s*web-platform-infra-apply\s*$/m);
  });

  test("the job passes a pinned @sha256 image_name, never a bare tag", () => {
    // ADR-128: a host booted on an image whose baked host-scripts do not match the
    // applied hash aborts cloud-init at stage=verify, and runcmd is once-per-instance —
    // no reboot repairs it. The pin is what makes the coherence preflight meaningful.
    expect(jobBlock).toMatch(/-var="image_name=\$\{PINNED\}"/);
    expect(jobBlock).not.toMatch(/-var="image_name=[^"]*:latest"/);
  });

  test("stripDispatchJobs removes the job's -targets without losing per-merge coverage", () => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const stripped = extractAllTargets(stripDispatchJobs(wf));
    // The five per-merge-covered bases must SURVIVE the strip — they are targeted by the
    // `apply` job too, so their presence proves the strip did not blow a hole in the
    // #5566 coverage anchor.
    for (const addr of WEB_HOST_BIRTH_PER_MERGE_COVERED) {
      expect(stripped.has(addr)).toBe(true);
    }
    // Non-vacuity for the strip itself: the job block genuinely carries these targets,
    // so the assertions above are not passing merely because the job is empty.
    expect(extractAllTargets(jobBlock).has("hcloud_server.web")).toBe(true);
  });

  test("stripDispatchJobs REMOVES the four moved/exclusion bases from the coverage set", () => {
    // The assertion the strip actually exists for, and the one the first draft omitted.
    // "The per-merge-covered bases survive" is true whether or not the strip runs — the
    // `apply` job targets them either way — so that test alone pins nothing. What the strip
    // is FOR is keeping these four out of `allTargets`, because they are
    // MOVED_OPERATOR_CONSUMED / exclusion bases and folding them in blunts the #5877
    // moved-block anchor. That is the CTO must-fix the deleted web_2_recreate strip existed
    // to satisfy; without this assertion, removing "web_host_create" from stripDispatchJobs
    // left the suite fully green.
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const stripped = extractAllTargets(stripDispatchJobs(wf));
    for (const base of [
      "hcloud_server.web",
      "hcloud_server_network.web",
      "hcloud_volume.workspaces",
      "hcloud_volume_attachment.workspaces",
    ]) {
      expect(stripped.has(base)).toBe(false);
    }
  });

  test("the gate's allow-set matches the job's -target set exactly", () => {
    // The fan-out lived in FOUR places — the workflow -target list, two copies inside the
    // gate, and WEB_HOST_BIRTH_TARGET_BASES here — and only workflow<->constant was bound.
    // Widening the gate's allow-set therefore silently permitted out-of-scope changes while
    // this file still certified the exact set; narrowing it made the gate refuse every real
    // birth plan, an outage dressed as a safety feature, with nothing red. The gate now
    // carries ONE `def allow($k)`; this binds it to the workflow. Mirrors the git-data
    // gate's parity assertion above.
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/web-host-birth-gate.sh"),
      "utf8",
    );
    // Terminate on the closing `];` at line start, NOT a bare `]`. A non-greedy `[\s\S]*?\]`
    // stops at the FIRST `]`, which is the one inside `hcloud_server.web[\"...\"]` — it
    // extracted exactly one member and the comparison failed. The non-vacuity length check
    // below is what surfaced that rather than letting a 1-member "allow-set" quietly pass
    // some other assertion.
    const defAllow = /def allow\(\$k\):\s*\[([\s\S]*?)\n\];/.exec(gateSrc);
    expect(defAllow).not.toBeNull();
    // Filter to terraform-address shape. The members are jq string literals containing
    // ESCAPED quotes (`"hcloud_server.web[\"\($k)\"]"`), so a bare /"([^"]+)"/ also
    // matches the `"]"` fragment between two escapes and yields a phantom member. Requiring
    // `<type>.<name>` drops it without hiding a real one — every legitimate member has it.
    const gateBases = [
      ...new Set(
        [...defAllow![1].matchAll(/"([^"]+)"/g)]
          .map((m) => m[1].replace(/\[.*$/, ""))
          .filter((a) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(a)),
      ),
    ].sort();
    // Non-vacuity: the extraction must actually find the nine members.
    expect(gateBases.length).toBe(WEB_HOST_BIRTH_TARGET_BASES.length);
    expect(gateBases).toEqual([...WEB_HOST_BIRTH_TARGET_BASES].sort());
  });

  // ── The gate's allow-set, judged by PURE functions so each rule has a mutation row (below). ──
  const birthGateSrc = (): string =>
    readFileSync(resolve(REPO_ROOT, "tests/scripts/lib/web-host-birth-gate.sh"), "utf8");
  const allowBody = (src: string): string => {
    const m = /def allow\(\$k\):\s*\[([\s\S]*?)\n\];/.exec(src);
    if (!m) throw new Error("def allow($k) not found in the birth gate");
    return m[1];
  };
  // Address-shaped members only (the escaped-quote fragments between members are not addresses).
  const allowMembers = (src: string): string[] =>
    [...allowBody(src).matchAll(/"((?:[^"\\]|\\.)*)"/g)]
      .map((m) => m[1])
      .filter((a) => /^[a-z0-9_]+\.[a-z0-9_]+/.test(a));
  const allowBases = (src: string): string[] => [...new Set(allowMembers(src).map((a) => a.replace(/\[.*$/, "")))].sort();
  // Keyed members interpolate the REQUEST'S key (`[\"\($k)\"]`); the fleet singletons carry no key at all. A
  // hardcoded key (`[\"web-3\"]`) would let a sibling host's address ride every birth, and base-only parity
  // cannot see it.
  const keyFormOk = (src: string): boolean =>
    allowMembers(src).every((a) => {
      const base = a.replace(/\[.*$/, "");
      const unkeyed = WEB_HOST_BIRTH_UNKEYED.includes(base);
      return unkeyed ? a === base : a === `${base}[\\"\\($k)\\"]`;
    });
  const allowOk = (src: string): boolean =>
    JSON.stringify(allowBases(src)) === JSON.stringify([...WEB_HOST_BIRTH_TARGET_BASES].sort()) && keyFormOk(src);

  test("the allow-set equals the target bases AND every keyed member interpolates the request's key", () => {
    expect(allowMembers(birthGateSrc()).length).toBe(WEB_HOST_BIRTH_TARGET_BASES.length);
    expect(allowOk(birthGateSrc())).toBe(true);
  });

  test("MUTATION: widening the allow-set with the LUKS attachment or the LUKS volume is seen", () => {
    const src = birthGateSrc();
    expect(allowOk(src)).toBe(true); // control
    for (const extra of ["hcloud_volume_attachment.workspaces_luks", "hcloud_volume.workspaces_luks", "hcloud_volume.workspaces_sibling"]) {
      const mutated = src.replace('"doppler_secret.web_bash_synthetic_url[\\"\\($k)\\"]"\n];', `"doppler_secret.web_bash_synthetic_url[\\"\\($k)\\"]",\n      "${extra}"\n];`);
      expect(mutated).not.toBe(src);
      expect(allowOk(mutated)).toBe(false);
    }
  });

  test("MUTATION: narrowing the allow-set, or hardcoding a key in a keyed member, is seen", () => {
    const src = birthGateSrc();
    const dropped = src.replace('      "hcloud_firewall_attachment.web",\n', "");
    expect(dropped).not.toBe(src);
    expect(allowOk(dropped)).toBe(false);
    const hardcoded = src.replace('"hcloud_volume.workspaces[\\"\\($k)\\"]"', '"hcloud_volume.workspaces[\\"web-3\\"]"');
    expect(hardcoded).not.toBe(src);
    expect(allowOk(hardcoded)).toBe(false);
    const keyedSingleton = src.replace('"cloudflare_record.app"', '"cloudflare_record.app[\\"\\($k)\\"]"');
    expect(keyedSingleton).not.toBe(src);
    expect(allowOk(keyedSingleton)).toBe(false);
  });

  // The web-1 refusal literal is the Terraform literal of the singleton LUKS attachment. The replace gate's
  // twin is bound to its workflow copy; this one had no binding at all, so renaming web-1 in var.web_hosts /
  // the attachment would leave the refusal pointing at a stale string and reopen the #6964 stranding.
  const luksAttachmentKey = (tf: string): string => {
    const code = stripComments(tf);
    const start = code.indexOf('resource "hcloud_volume_attachment" "workspaces_luks"');
    if (start === -1) throw new Error("hcloud_volume_attachment.workspaces_luks not found");
    const body = code.slice(start, code.indexOf("\n}\n", start));
    const m = /server_id\s*=\s*hcloud_server\.web\["([^"]+)"\]\.id/.exec(body);
    if (!m) throw new Error("the attachment's server_id is not hcloud_server.web[<literal key>].id");
    return m[1];
  };
  const birthPinnedKey = (src: string): string => {
    const m = /_WEB_HOST_BIRTH_LUKS_PINNED_KEY="([^"]+)"/.exec(src);
    if (!m) throw new Error("_WEB_HOST_BIRTH_LUKS_PINNED_KEY not found in the birth gate");
    return m[1];
  };
  const luksTf = (): string => readFileSync(resolve(INFRA_DIR, "workspaces-luks.tf"), "utf8");

  test("the birth gate's LUKS-pinned refusal key equals the key the singleton LUKS attachment is hard-bound to", () => {
    expect(luksAttachmentKey(luksTf())).toBe("web-1");
    expect(birthPinnedKey(birthGateSrc())).toBe(luksAttachmentKey(luksTf()));
    // ...and equals the replace gate's twin (two gates, one literal).
    const replaceSrc = readFileSync(resolve(REPO_ROOT, "tests/scripts/lib/web-host-replace-gate.sh"), "utf8");
    expect(birthPinnedKey(birthGateSrc())).toBe(/_WEB_HOST_REPLACE_LUKS_PINNED_KEY="([^"]+)"/.exec(replaceSrc)![1]);
  });

  test("MUTATION: a drifted gate literal, or a renamed attachment key, is seen", () => {
    const src = birthGateSrc();
    const tf = luksTf();
    const driftedGate = src.replace('_WEB_HOST_BIRTH_LUKS_PINNED_KEY="web-1"', '_WEB_HOST_BIRTH_LUKS_PINNED_KEY="web-9"');
    expect(driftedGate).not.toBe(src);
    expect(birthPinnedKey(driftedGate)).not.toBe(luksAttachmentKey(tf));
    const renamedTf = tf.replace('server_id = hcloud_server.web["web-1"].id', 'server_id = hcloud_server.web["web-9"].id');
    expect(renamedTf).not.toBe(tf);
    expect(birthPinnedKey(src)).not.toBe(luksAttachmentKey(renamedTf));
    // A comment that quotes the old literal must not satisfy the extractor.
    const commentOnly = tf.replace('server_id = hcloud_server.web["web-1"].id', '# server_id = hcloud_server.web["web-1"].id\n  server_id = var.x');
    expect(() => luksAttachmentKey(commentOnly)).toThrow();
  });
});

// ─── web-host-replace dispatch: the replace path's -target set + gate pairing ──
// `apply_target=web-host-replace` (#6969, ADR-148) is the sibling web-host-birth-gate.sh
// named but nobody had built. It is NOT a widened birth: a birth is additive and its gate
// permits zero destroys, while this one requires exactly one delete+create of the requested
// host. Both gates gain their meaning from that distinction, so the two -target sets must
// stay separately pinned — a replace graded against the birth allow-set would abort on the
// destroy arm, and a birth graded against this one would abort on replace cardinality.
//
// The SAFETY PROPERTY OF THIS SET IS ITS OMISSIONS, which is why they are asserted
// explicitly below rather than left implicit in a four-member equality check. An untargeted
// resource cannot be planned for destroy, so leaving the workspace store, the LUKS volume
// and the LUKS passphrase out of the -target set is what preserves them.
const WEB_HOST_REPLACE_TARGET_BASES = [
  "hcloud_server.web",
  "hcloud_server_network.web",
  "hcloud_volume_attachment.workspaces",
  // Singleton over `[for h in hcloud_server.web : h.id]` — unkeyed by construction. It MUST
  // ride the replace: a fresh Hetzner host has a public IPv4/IPv6 and boots NAKED without it.
  "hcloud_firewall_attachment.web",
];
const WEB_HOST_REPLACE_UNKEYED = ["hcloud_firewall_attachment.web"];
// PRESERVED BY OMISSION — asserted ABSENT from the -target set. Each is a store or a key
// whose loss is unrecoverable, and omission (not a gate arm) is the primary mechanism.
const WEB_HOST_REPLACE_PRESERVED = [
  "hcloud_volume.workspaces",
  "hcloud_volume.workspaces_luks",
  "random_password.workspaces_luks",
  "doppler_secret.workspaces_luks_key",
  // The web-class key copy (#9377), which now carries its OWN generator's value (random_password.workspaces_luks_web),
  // not web-1's: it must stay out of the -target set, and the gate's luks_passphrase_touched names it too.
  "doppler_secret.workspaces_luks_web_key",
  // The web-class passphrase generator (#9377 decision A1): a replace of it rotates a passphrase whose old value
  // survives nowhere, so no replace job may name it.
  "random_password.workspaces_luks_web",
  // The apex A record is pinned to web-1's ipv4_address. This job REFUSES web-1, so the
  // record must never move; its presence in the -target set would be the difference between
  // "replace a standby" and "re-point production DNS".
  "cloudflare_record.app",
];

/**
 * `-replace` values for a job whose key is SHELL-INTERPOLATED rather than literal.
 *
 * The shared extractReplaceAddrs assumes the sibling dispatch shape
 * `-replace='hcloud_server.git_data'`. This job cannot use it: single quotes would suppress
 * the `${WEB_HOST_KEY}` expansion that makes the job generic over var.web_hosts, so its
 * -replace is double-quoted with escaped inner quotes. Fed to the shared extractor, the
 * outer-quote match stops at the first `\"` and yields a truncated `hcloud_server.web[`.
 * Sibling of extractEscapedQuotedTargets, and separate for the same reason: loosening the
 * shared extractor would make the OTHER callers' assertions accept an interpolated address.
 */
function extractEscapedQuotedReplaceAddrs(text: string): string[] {
  const out: string[] = [];
  for (const m of stripComments(text).matchAll(/-replace="((?:[^"\\]|\\.)*)"/g)) {
    out.push(m[1].replace(/\\"/g, '"'));
  }
  return out;
}

describe("web-host-replace dispatch -target set + replace-gate pairing (#6969)", () => {
  let jobBlock: string;
  let keyedTargets: string[];
  let replaceAddrs: string[];

  beforeAll(() => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    jobBlock = extractJobBlock(wf, "web_host_replace");
    // The escaped-quote extractor, not the literal-key one: this job's targets interpolate
    // ${WEB_HOST_KEY} so they are double-quoted with escaped inner quotes.
    keyedTargets = extractEscapedQuotedTargets(jobBlock);
    replaceAddrs = extractEscapedQuotedReplaceAddrs(jobBlock);
  });

  test("the job exists and its -target extraction is non-vacuous", () => {
    // Every assertion below reads jobBlock; an absent job yields "" and turns the structural
    // greps into silent passes. Fail here instead.
    expect(jobBlock).not.toEqual("");
    expect(keyedTargets.length).toBe(WEB_HOST_REPLACE_TARGET_BASES.length);
  });

  test("the -targets are EXACTLY the four replace fan-out addresses", () => {
    const bases = [...new Set(keyedTargets.map((t) => t.replace(/\[.*$/, "")))];
    expect(bases.sort()).toEqual([...WEB_HOST_REPLACE_TARGET_BASES].sort());
  });

  test("every keyed -target interpolates the SAME dispatch key, never a literal host", () => {
    // One authorization replaces one host. A hardcoded `["web-1"]` slipped into the set would
    // let a dispatch for web-3 destroy the live origin, and the sourced gate grades against
    // the key it was PASSED — so a mismatched literal here is invisible to it.
    const keys = keyedTargets
      .map((t) => /\["([^"]*)"\]/.exec(t)?.[1])
      .filter((k): k is string => k !== undefined);
    expect(keys.length).toBe(
      WEB_HOST_REPLACE_TARGET_BASES.length - WEB_HOST_REPLACE_UNKEYED.length,
    );
    expect([...new Set(keys)]).toEqual(["${WEB_HOST_KEY}"]);
  });

  test("the -replace address is EXACTLY the keyed web server", () => {
    expect(replaceAddrs).toEqual(['hcloud_server.web["${WEB_HOST_KEY}"]']);
  });

  test("exactly ONE address is -replaced (one authorization, one destroy)", () => {
    // The cardinality the gate enforces on the PLAN, asserted here on the INVOCATION. A
    // second -replace would put a destroy in the plan that the gate's replace-count arm
    // would then have to catch after the fact; keeping the invocation single-address means
    // the two agree by construction.
    expect(replaceAddrs.length).toBe(1);
  });

  test("neither data volume, the LUKS passphrase, nor the apex A record is targeted", () => {
    // The omissions ARE the preservation. An untargeted resource cannot be planned for
    // destroy, so this assertion guards the primary mechanism, not a backstop.
    const bases = new Set(keyedTargets.map((t) => t.replace(/\[.*$/, "")));
    for (const addr of WEB_HOST_REPLACE_PRESERVED) {
      expect(bases.has(addr)).toBe(false);
    }
  });

  test("the job runs the sourced web_host_replace_gate and borrows no sibling gate", () => {
    // ANCHORED ON THE SOURCE COMMAND AND THE CALL-WITH-ARGUMENT, not bare tokens.
    // `extractJobBlock` does NOT strip comments, and both tokens appear in comments inside
    // this job (the prose above the step and the `# shellcheck source=` directive). MEASURED:
    // with the bare `toContain` form, replacing the real invocation with `if false; then`
    // left this suite 82/0 green — and this gate is the ONLY check on a path that destroys a
    // production host. Mirrors stock-preflight-coverage.test.ts, whose own comment records
    // that deleting all five real `source` lines left IT green (cq-assert-anchor-not-bare-token).
    expect(jobBlock).toMatch(/^\s*source\s+\S*web-host-replace-gate\.sh/m);
    expect(jobBlock).toMatch(
      /\bweb_host_replace_gate\s+tfplan\.json\s+"\$\{WEB_HOST_KEY\}"/,
    );
    // A replace graded against the BIRTH allow-set is graded against the inverse contract
    // (the birth gate requires zero destroys). Naming each sibling explicitly rather than a
    // generic "one gate only" count keeps the failure message actionable.
    for (const sibling of [
      "web-host-birth-gate.sh",
      "web2-retire-gate.sh",
      "workspaces-luks-cutover-gate.sh",
      "workspaces-luks-recut-gate.sh",
      "registry-host-replace-gate.sh",
      "git-data-host-replace-gate.sh",
    ]) {
      expect(jobBlock).not.toContain(sibling);
    }
  });

  test("the job sources the stock preflight (a replace destroys before it creates)", () => {
    // MANDATORY on this path rather than advisory: the destroy frees the slot but cannot
    // conjure DC stock, so an out-of-stock create leaves the host gone and unrecreatable
    // (#6393/#6400). The entire cx line was orderable in 0 of 3 EU DCs on 2026-07-26.
    expect(jobBlock).toContain("stock-preflight-gate.sh");
    expect(jobBlock).toContain("stock_preflight_gate");
  });

  test("the job carries a required-reviewer environment gate and the shared swap mutex", () => {
    expect(jobBlock).toMatch(/^\s{4}environment:\s*web-platform-infra-apply\s*$/m);
    // The group string is a SHARED literal across the release deploy and the pipeline-fix
    // apply. GitHub does not error on divergent group strings — they simply fail to
    // serialize — so a rename here is a silent loss of the mutex on a lockless backend.
    expect(jobBlock).toMatch(/^\s{6}group:\s*web-1-swap\s*$/m);
    expect(jobBlock).toMatch(/^\s{6}cancel-in-progress:\s*false\s*$/m);
  });

  test("the confirm token is REPLACE-<key>, never the birth path's BIRTH-<key>", () => {
    // Distinct by design: a token typed for a birth must not authorize a destroy.
    expect(jobBlock).toContain('"REPLACE-${WEB_HOST_KEY_RAW}"');
    expect(jobBlock).not.toContain('"BIRTH-${WEB_HOST_KEY_RAW}"');
  });

  test("the job passes a pinned @sha256 image_name, never a bare tag", () => {
    expect(jobBlock).toMatch(/-var="image_name=\$\{PINNED\}"/);
    expect(jobBlock).not.toMatch(/-var="image_name=[^"]*:latest"/);
  });

  test("stripDispatchJobs REMOVES the replace job's exclusion bases from the coverage set", () => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const stripped = extractAllTargets(stripDispatchJobs(wf));
    for (const base of [
      "hcloud_server.web",
      "hcloud_server_network.web",
      "hcloud_volume_attachment.workspaces",
    ]) {
      expect(stripped.has(base)).toBe(false);
    }
    // The fleet firewall singleton is per-merge covered, so it must SURVIVE the strip —
    // proving the strip did not blow a hole in the #5566 coverage anchor.
    expect(stripped.has("hcloud_firewall_attachment.web")).toBe(true);
    // Non-vacuity for the strip itself: the job block genuinely carries the server target.
    expect(extractAllTargets(jobBlock).has("hcloud_server.web")).toBe(true);
  });

  test("the gate's allow-set matches the job's -target set exactly", () => {
    // The load-bearing invariant. Widening the gate's allow-set would silently permit
    // out-of-scope changes while this file still certified the exact set; narrowing it would
    // make the gate refuse every real replace — an outage dressed as a safety feature, with
    // nothing red. Mirrors the birth and git-data parity assertions.
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/web-host-replace-gate.sh"),
      "utf8",
    );
    // Terminate on the closing `];` at line start, NOT a bare `]` — a non-greedy match would
    // stop at the `]` inside `hcloud_server.web[\"...\"]` and extract one member. The
    // non-vacuity length check below is what surfaces that rather than letting a 1-member
    // "allow-set" quietly pass.
    const defAllow = /def allow\(\$k\):\s*\[([\s\S]*?)\n\];/.exec(gateSrc);
    expect(defAllow).not.toBeNull();
    // The members are jq string literals containing ESCAPED quotes, so a bare /"([^"]+)"/
    // also matches the `"]"` fragment between two escapes and yields a phantom member.
    // Requiring `<type>.<name>` drops it without hiding a real one.
    const gateBases = [
      ...new Set(
        [...defAllow![1].matchAll(/"([^"]+)"/g)]
          .map((m) => m[1].replace(/\[.*$/, ""))
          .filter((a) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(a)),
      ),
    ].sort();
    expect(gateBases.length).toBe(WEB_HOST_REPLACE_TARGET_BASES.length);
    expect(gateBases).toEqual([...WEB_HOST_REPLACE_TARGET_BASES].sort());
  });

  test("the gate's keyed arms extension is exactly the LUKS attachment and the apex record (#9356)", () => {
    // The arms-key extension widens the allow-set for ONE key beyond the workflow's -target
    // list, on purpose: the arms are dead code while the refusal holds, and the workflow's
    // -target list is NOT edited by the arms PR (byte budget + the refusal). So this is NOT a
    // -target parity check; it pins the extension's exact membership, so a third address
    // cannot ride in under "arms" without turning this red. hcloud_volume.workspaces_luks and the
    // passphrase resources must never appear in it (they remain prohibitions).
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/web-host-replace-gate.sh"),
      "utf8",
    );
    const defArms = /def allow_arms:\s*\[([\s\S]*?)\n\];/.exec(gateSrc);
    expect(defArms).not.toBeNull();
    const armsAddrs = [...defArms![1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
    expect(armsAddrs).toEqual(["cloudflare_record.app", "hcloud_volume_attachment.workspaces_luks"]);
    // Neither extension member is a -target of the replace job (non-vacuity of the "NOT edited" claim).
    const jobTargets = extractAllTargets(jobBlock);
    expect(jobTargets.size).toBeGreaterThan(0);
    for (const addr of armsAddrs) {
      expect(jobTargets.has(addr)).toBe(false);
    }
    // The extension applies to the same key the refusal names: a different arms key would
    // silently arm a host the refusal does not protect.
    const armsKey = /_WEB_HOST_REPLACE_LUKS_ARMS_KEY="([^"]+)"/.exec(gateSrc);
    const pinnedKey = /_WEB_HOST_REPLACE_LUKS_PINNED_KEY="([^"]+)"/.exec(gateSrc);
    expect(armsKey).not.toBeNull();
    expect(armsKey![1]).toBe(pinnedKey![1]);
  });

  test("the gate's LUKS-pinned refusal key matches the job's fail-fast key", () => {
    // The gate is the load-bearing refusal; the job's input validation repeats it only so
    // the operator reads the reason at the top of the run instead of after a digest resolve
    // and a terraform plan. Two copies of a safety-relevant literal is exactly the drift
    // shape this file exists to pin, so bind them.
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/web-host-replace-gate.sh"),
      "utf8",
    );
    const pinned = /_WEB_HOST_REPLACE_LUKS_PINNED_KEY="([^"]+)"/.exec(gateSrc);
    expect(pinned).not.toBeNull();
    expect(pinned![1]).toBe("web-1");
    expect(jobBlock).toContain(`"$WEB_HOST_KEY_RAW" == "${pinned![1]}"`);
  });

  test("the three keyed bases ARE moved-consumed, which is why the strip is load-bearing", () => {
    // Written first as "no replace-path address leaked into MOVED_OPERATOR_CONSUMED",
    // copied from the git-data block where that IS true — and measured false here. It is
    // the inverse that matters: these three bases are exactly the MOVED_OPERATOR_CONSUMED
    // endpoints, so folding this job's -targets into `allTargets` would let a moved base be
    // dropped from that set without turning the #5877 anchor red. Recorded rather than
    // quietly deleted, because a copied assertion that happens to be false about the new
    // subject is the failure this block's own strip test exists to catch.
    for (const addr of [
      "hcloud_server.web",
      "hcloud_server_network.web",
      "hcloud_volume_attachment.workspaces",
    ]) {
      expect(MOVED_OPERATOR_CONSUMED.has(addr)).toBe(true);
    }
    // The fleet firewall singleton is NOT a moved endpoint — it is per-merge covered, and
    // the strip test above asserts it survives.
    expect(MOVED_OPERATOR_CONSUMED.has("hcloud_firewall_attachment.web")).toBe(false);
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

// ─── DP-11 F8 guard: every github_repository_environment must gate on a NON-EMPTY
//     required-reviewer set. A zero-reviewer environment auto-approves, silently
//     defeating the human ack these environments exist to enforce on irreversible
//     cutover dispatches (inngest arm/rollback, the /workspaces LUKS freeze #6604).
//     Terraform pins reviewers.users, but nothing else fails RED pre-merge if a
//     future edit empties it — this test is that guard. ────────────────────────
describe("github_repository_environment declares a non-empty reviewers.users (DP-11 F8)", () => {
  // (#8209, ADR-241 D2) THE PROPERTY WIDENED, not weakened.
  //
  // This guard was written when every environment in this root was a cutover GATE whose
  // protection WAS the reviewer, so "reviewers.users is non-empty" and "this environment
  // is protected" were the same sentence. ADR-241 introduces a second, deliberately
  // reviewer-less class: `infra-privileged` serves the UNATTENDED Tier-B jobs
  // (apply-on-merge, the scheduled drift check), which a reviewer gate would block by
  // design. Adding a reviewer to satisfy the old spelling would have broken the thing
  // the environment exists to do.
  //
  // The real hazard was never "zero reviewers" on its own — it is an environment that
  // auto-approves AND admits any branch. A main-only deployment-branch policy makes
  // "auto-approve" mean "auto-approve a run that is already on main", which is a
  // protection, just a different one. So the invariant is now: EVERY environment
  // carries at least one of the two, and an environment with NEITHER is RED.
  //
  // That widening is a DISJUNCTION, and a disjunction is strictly WEAKER than either
  // side — so on its own it would have silently retired the old property for every
  // environment that already satisfied it. `REVIEWERS_RATCHET` below is what keeps the
  // old property where it applied: the two-of-two limb is available only to
  // environments that never gated on a human. (An earlier draft of this comment claimed
  // the widening was "strictly STRONGER". It was not, and emptying
  // `web_platform_infra_apply`'s reviewer list passed under it.)
  // Returns, per environment, the SET of branch_patterns its deployment policies declare.
  //
  // A set rather than a boolean, because the property is "`main` is the ONLY pattern",
  // not "`main` is AMONG the patterns". Those differ by one appended resource:
  //
  //   resource "github_repository_environment_deployment_policy" "infra_privileged_any" {
  //     environment    = github_repository_environment.infra_privileged.environment
  //     branch_pattern = "*"
  //   }
  //
  // GitHub UNIONs deployment policies, so that one block re-opens the environment to
  // every branch while a `main` policy is still present and still correct. An extractor
  // that `continue`s past a non-`main` pattern cannot see it: the appended resource is
  // invisible rather than disqualifying, and the guard stays green while the boundary
  // #8209 buys is gone. Collect every pattern and let the caller demand exactly {"main"}.
  //
  // `files` is a parameter — the same seam `collectSshProvisioned` carries — so the
  // direction test below can drive a SYNTHETIC tree through the REAL walk. Without it
  // nothing can exercise the must-trip side: every policy on the live tree says "main",
  // so deleting the pattern test entirely leaves this suite green.
  const policyPatternsFor = (
    files: string[] = listInfraTfFiles(),
  ): Map<string, Set<string>> => {
    const found = new Map<string, Set<string>>();
    const re =
      /resource\s+"github_repository_environment_deployment_policy"\s+"[A-Za-z0-9_]+"\s*\{([\s\S]*?)\n\}/g;
    for (const file of files) {
      const stripped = stripComments(readFileSync(file, "utf8"));
      let m: RegExpExecArray | null;
      re.lastIndex = 0;
      while ((m = re.exec(stripped)) !== null) {
        const body = m[1];
        const ref = body.match(
          /environment\s*=\s*github_repository_environment\.([A-Za-z0-9_]+)\.environment/,
        );
        if (!ref) continue;
        const pat = body.match(/branch_pattern\s*=\s*"([^"]*)"/);
        // A policy with no readable pattern is counted as an UNKNOWN pattern, not
        // skipped: "I could not parse it" must not render as "it is main-only".
        const set = found.get(ref[1]) ?? new Set<string>();
        set.add(pat ? pat[1] : "__UNPARSED__");
        found.set(ref[1], set);
      }
    }
    return found;
  };
  const policyPatterns = policyPatternsFor();
  const isMainOnly = (env: string): boolean => {
    const pats = policyPatterns.get(env);
    return pats !== undefined && pats.size === 1 && pats.has("main");
  };
  const mainOnlyPolicyEnvs = new Set(
    [...policyPatterns.keys()].filter((e) => isMainOnly(e)),
  );

  // Environments that carried a non-empty `reviewers.users` before #8209 widened the
  // property below. They keep it.
  //
  // WHY A RATCHET AND NOT A RE-DERIVATION: the widened limb is `reviewers OR main-only
  // policy`, and a disjunction is strictly WEAKER than either side. Before #8209 the
  // property was `reviewers`, full stop — so emptying `web_platform_infra_apply`'s
  // reviewer list (a UI click, or deleting four lines of HCL) would now PASS on the
  // branch-policy limb, converting the sole human authorization for a host birth into
  // an auto-approve with no test going red. That is the exact harm the `#6730` comment
  // above says declaring the environment in terraform exists to prevent, and the
  // widening would have re-opened it.
  //
  // So the disjunction is available only to environments that never had reviewers. For
  // everything in this set the property is unchanged: reviewers, and a branch policy on
  // top of them is additive.
  //
  // MEASURED off the tree, not guessed: these are every environment that carries a
  // non-empty `reviewers.users` today. The loop below asserts each one is still IN the
  // population, so renaming or deleting an environment cannot quietly drop it out of the
  // ratchet — a ratchet nobody can fail is the same as no ratchet.
  const REVIEWERS_RATCHET = new Set([
    "workspaces_luks_cutover",
    "inngest_cutover",
    "inngest_config_signing",
    "web_platform_infra_apply",
  ]);

  test("every cutover-gate environment in the infra root gates on ≥1 reviewer", () => {
    const header =
      /resource\s+"github_repository_environment"\s+"([A-Za-z0-9_]+)"\s*\{/g;
    const envs: { name: string; users: string; body: string }[] = [];
    for (const file of listInfraTfFiles()) {
      const stripped = stripComments(readFileSync(file, "utf8"));
      let m: RegExpExecArray | null;
      while ((m = header.exec(stripped)) !== null) {
        const name = m[1];
        const openBrace = header.lastIndex - 1; // index of the resource `{`
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
          throw new Error(
            `Unbalanced braces for github_repository_environment.${name}`,
          );
        }
        const body = stripped.slice(openBrace, end + 1);
        const rev = body.match(/reviewers\s*\{[^}]*users\s*=\s*\[([^\]]*)\]/);
        envs.push({ name, users: (rev?.[1] ?? "").trim(), body });
      }
    }

    // Fail-closed: the guard is vacuous if the extractor matches nothing. Assert it
    // actually saw the known cutover-gate environments before trusting the loop.
    const names = envs.map((e) => e.name);
    expect(names).toContain("workspaces_luks_cutover");
    expect(names).toContain("inngest_cutover");
    // #6730 — the birth path's environment. It pre-existed this change as a live,
    // untracked GitHub environment, which meant its reviewer set was governed by
    // nothing: emptying it in the UI would have silently converted the sole human
    // authorization for a host birth into an auto-approve, with no test going red.
    // Declaring it in terraform is what brings it under the loop below.
    expect(names).toContain("web_platform_infra_apply");
    // (#8209) The reviewer-less Tier-B environment must be IN the population, or the
    // widened property below is vacuous for exactly the class it was widened for.
    expect(names).toContain("infra_privileged");
    // And the policy extractor must have found something, or every environment would
    // trivially satisfy the branch-policy limb and the check would pass for the wrong
    // reason. A zero-match extractor is the worst outcome: it still prints a verdict.
    expect(
      mainOnlyPolicyEnvs.size,
      "the deployment-policy extractor matched NOTHING — the branch-policy limb below would be vacuous",
    ).toBeGreaterThan(0);

    const seenRatchet = new Set<string>();
    for (const env of envs) {
      const ids = env.users
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);

      if (REVIEWERS_RATCHET.has(env.name)) {
        seenRatchet.add(env.name);
        expect(
          ids.length,
          `github_repository_environment.${env.name} is in REVIEWERS_RATCHET and its reviewers.users is EMPTY. ` +
            `This environment gated on a human before #8209; the branch-policy limb is not available to it. ` +
            `Removing its reviewers converts a human authorization into an auto-approve (DP-11 F8; #6730).`,
        ).toBeGreaterThan(0);
        continue;
      }

      // A reviewer-less environment relies entirely on the branch policy, so the policy
      // must be main-ONLY (see policyPatternsFor) AND the environment must actually be
      // configured to consult custom policies. `custom_branch_policies = false` makes
      // every named pattern inert; `protected_branches = true` admits every protected
      // branch regardless of pattern. Both are one-word edits that GitHub accepts and
      // that leave the `main` policy resource sitting there looking correct.
      const dbp = env.body.match(/deployment_branch_policy\s*\{([^}]*)\}/);
      const custom =
        dbp !== null && /custom_branch_policies\s*=\s*true/.test(dbp[1]);
      const notProtected =
        dbp !== null && /protected_branches\s*=\s*false/.test(dbp[1]);
      const policyIntact = isMainOnly(env.name) && custom && notProtected;
      expect(
        ids.length > 0 || policyIntact,
        `github_repository_environment.${env.name} has no reviewers, so it is gated only by its branch policy — ` +
          `and that gate is not intact. Needs all three: exactly one deployment policy whose branch_pattern is ` +
          `"main" (saw ${JSON.stringify([...(policyPatterns.get(env.name) ?? [])])}), ` +
          `custom_branch_policies = true (saw ${custom}), protected_branches = false (saw ${notProtected}). ` +
          `Otherwise any branch can deploy to it and read its secrets (DP-11 F8; #8209 ADR-241 D2).`,
      ).toBe(true);
    }

    // A ratchet entry that is not in the population enforces nothing. This is the
    // difference between "this environment still requires a human" and "an environment
    // by that name was renamed away and nobody noticed".
    for (const name of REVIEWERS_RATCHET) {
      expect(
        seenRatchet.has(name),
        `REVIEWERS_RATCHET names ${name}, but no github_repository_environment by that name was found in the ` +
          `infra root. Either it was renamed (update the ratchet and confirm the new name still has reviewers) ` +
          `or it was deleted. An unmatched ratchet entry is an unenforced one.`,
      ).toBe(true);
    }
  });

  // The must-trip side of the branch-policy limb. Every deployment policy on the live
  // tree says `branch_pattern = "main"`, so on the real tree the limb is green whether
  // the pattern test works or is deleted outright — the guard above can only ever
  // demonstrate its pass branch. `policyPatternsFor(files)` takes the file list for
  // exactly this reason: a synthetic tree goes through the REAL walk, not a re-derived
  // copy of it that could drift from the thing shipping.
  test("a second, wider deployment policy DISQUALIFIES an environment (branch-policy limb)", () => {
    const dir = mkdtempSync(join(tmpdir(), "tf-policy-direction-"));
    try {
      const f = join(dir, "synthetic.tf");
      const mainPolicy = `
resource "github_repository_environment_deployment_policy" "synthetic_main" {
  repository     = "soleur"
  environment    = github_repository_environment.synthetic.environment
  branch_pattern = "main"
}
`;
      writeFileSync(f, mainPolicy);
      expect(
        [...(policyPatternsFor([f]).get("synthetic") ?? [])],
        "a lone main policy must read as exactly {main} — otherwise the negative below proves nothing",
      ).toEqual(["main"]);

      // GitHub UNIONs deployment policies. Appending this re-opens the environment to
      // every branch while the `main` policy is still present and still correct.
      writeFileSync(
        f,
        mainPolicy +
          `
resource "github_repository_environment_deployment_policy" "synthetic_any" {
  repository     = "soleur"
  environment    = github_repository_environment.synthetic.environment
  branch_pattern = "*"
}
`,
      );
      const pats = policyPatternsFor([f]).get("synthetic");
      expect(pats, "the second policy was not seen at all").toBeDefined();
      expect(
        pats!.size === 1 && pats!.has("main"),
        `appending a branch_pattern = "*" policy left the environment reading as main-only ` +
          `(patterns: ${JSON.stringify([...pats!])}). Any branch could deploy to it and read its secrets.`,
      ).toBe(false);

      // And a commented-out wider policy must NOT disqualify — the walk strips comments,
      // so this pins the extractor against the opposite error (reporting a phantom).
      writeFileSync(f, mainPolicy + `\n# branch_pattern = "*"\n`);
      expect([...(policyPatternsFor([f]).get("synthetic") ?? [])]).toEqual([
        "main",
      ]);
    } finally {
      rmSync(dir, { recursive: true, force: true });
    }
  });

  // (#7025) The rung-2 rehearsal dispatch is the THIRD consumer of web-platform-infra-apply,
  // and it inherits its reviewer set from the loop above rather than declaring its own.
  //
  // The assertion lives HERE, beside the guard that makes the environment meaningful, rather
  // than only in the infra suite: F8 proves the environment HAS reviewers, and this proves
  // the rehearsal actually ROUTES THROUGH it. Either fact alone is satisfiable while the
  // rehearsal dispatches unreviewed — a job with no `environment:` never meets a reviewer no
  // matter how well-populated that reviewer set is.
  test("the rung-2 rehearsal dispatch routes through the reviewed environment", () => {
    const wf = readFileSync(
      resolve(REPO_ROOT, ".github/workflows/git-data-rung2-rehearsal.yml"),
      "utf8",
    );
    expect(wf).toMatch(/^\s{4}environment:\s*web-platform-infra-apply\s*$/m);

    // It must NOT be able to commit its own evidence. That file releases the birth
    // interlock, so a workflow with `contents: write` would be approving the birth as a side
    // effect of a dispatch whose prompt said "rehearsal" — the environment reviewer would be
    // authorizing one thing and getting another.
    expect(wf).toMatch(/^permissions:\n\s{2}contents:\s*read\s*$/m);
    expect(wf).not.toMatch(/contents:\s*write/);
  });
});

/**
 * registry-luks-recut dispatch (#6929) — the sanctioned guest-side-LUKS recut.
 *
 * The load-bearing property is the ATOMIC 3-WAY `-replace`. Replacing the host alone preserves
 * the store volume (a host replace, not a recut); replacing the volume alone leaves the old host mounting a device that no longer
 * exists. They move together or not at all.
 */
describe("registry-luks-recut dispatch -target/-replace set (#6929)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const jobBlock = extractJobBlock(wf, "registry_luks_recut");

  test("the job exists and is dispatch-gated on its own apply_target", () => {
    expect(jobBlock.length).toBeGreaterThan(0);
    expect(jobBlock).toContain("inputs.apply_target == 'registry-luks-recut'");
  });

  test("-targets are exactly the registry's own 6 addresses", () => {
    const targets = extractAllTargets(jobBlock);
    for (const addr of REGISTRY_REPLACE_TARGETS) {
      expect(targets.has(addr)).toBe(true);
    }
    expect(targets.size).toBe(REGISTRY_REPLACE_TARGETS.length);
  });

  test("every -target is an OPERATOR_APPLIED_EXCLUSION (merging applies nothing)", () => {
    for (const addr of extractAllTargets(jobBlock)) {
      expect(OPERATOR_APPLIED_EXCLUSIONS.has(addr)).toBe(true);
    }
  });

  test("carries all THREE -replace flags — the volume, its attachment, and the host", () => {
    // Anchored on the flag syntax, not a bare address: every one of these addresses also
    // appears as a `-target=` on the very next lines and in the job's prose, so a bare-token
    // grep would pass against a job that lost its -replace flags entirely.
    const replaced = [
      ...jobBlock.matchAll(/-replace='([^']+)'/g),
    ].map((m) => m[1]);
    expect(replaced.sort()).toEqual(
      [
        "hcloud_server.registry",
        "hcloud_volume.registry",
        "hcloud_volume_attachment.registry",
      ].sort(),
    );
  });

  test("sources the recut gate lib and states there is no ack-destroy bypass", () => {
    expect(jobBlock).toContain("registry-luks-recut-gate.sh");
    expect(jobBlock).toContain("registry_luks_recut_gate");
    expect(jobBlock).toContain("NO [ack-destroy] bypass");
  });

  test("does NOT re-derive an inline copy of the gate's counter logic", () => {
    // The gate must be the SAME BYTES the test suite exercises. An inline jq over
    // resource_changes inside the plan step would be a second, untested implementation.
    const planStep = jobBlock.slice(
      jobBlock.indexOf("Terraform plan (atomic 3-way recut)"),
      jobBlock.indexOf("Pre-apply zero-touch assert"),
    );
    expect(planStep.length).toBeGreaterThan(0);
    expect(planStep).not.toContain("resource_changes");
  });

  test("requires the typed confirm and the id-pin before planning", () => {
    expect(jobBlock).toContain("RECUT-REGISTRY-LUKS");
    expect(jobBlock).toContain("expected_registry_store_volume_id");
  });

  test("declares no environment that auto-approves from any branch (DP-11 F8)", () => {
    // (#8209, ADR-241 D2) THE PROPERTY, RESTATED — this test used to assert `environment:`
    // was ABSENT, and its own title gave the reason: "a zero-reviewer environment
    // auto-approves". That reason is the real property, and absence was only one way to
    // satisfy it. This job now declares `infra-privileged`, which has no reviewer but IS
    // pinned to `main`, so it cannot auto-approve a branch dispatch — the hazard the
    // original assertion was written against.
    //
    // The teeth are preserved by composition, not by trust: the DP-11 F8 suite above reds
    // on ANY environment carrying neither reviewers nor a main-only policy, so the
    // allowlist here cannot be widened into a fake gate without that suite failing.
    const m = /^\s+environment:\s*(\S+)\s*$/m.exec(jobBlock);
    if (m) {
      expect(
        m[1],
        `registry_luks_recut declares environment: ${m[1]}. Only a reviewer-gated environment ` +
          `or the main-pinned infra-privileged is admissible here; anything else can auto-approve ` +
          `a dispatch from an arbitrary branch onto a destructive recut (DP-11 F8).`,
      ).toBe("infra-privileged");
    }
  });

  test("pins timeout-minutes below GitHub's 360-minute default", () => {
    // It holds the fleet-wide apply mutex with cancel-in-progress: false, so no declaration
    // would let a hung poll block every merge-apply for six hours.
    const m = /timeout-minutes:\s*(\d+)/.exec(jobBlock);
    expect(m).not.toBeNull();
    expect(Number(m![1])).toBeLessThanOrEqual(30);
  });

  test("stripDispatchJobs removes this job's -targets from the coverage set", () => {
    const strippedTargets = extractAllTargets(stripDispatchJobs(wf));
    for (const addr of REGISTRY_REPLACE_TARGETS) {
      expect(strippedTargets.has(addr)).toBe(false);
    }
    // Non-vacuity: unstripped, the whole-file scan DOES see them.
    expect(extractAllTargets(wf).has("hcloud_server.registry")).toBe(true);
  });
});

// --- G2 reachability (#9879): reachability of the inngest sole-copy addresses -------------------------------------------
// Extends B5/B6 (below) with one census over EVERY workflow and tracked script. Built on the existing chokepoints:
// extractJobBlock (per-job text), extractAllTargets (the job-found non-vacuity check), stripDispatchJobs (the
// per-merge view), stripShellLineComments and joinContinuations (comment strip, continuation fold).
//
// Comment policy: ONLY whole-line `#` comments are removed. A trailing `# ...` is KEPT: shell has `$#`, `${#a[@]}`
// and `"a #b"`, so a quote-unaware trailing-comment strip (stripComments) would let `echo "$#"; terraform ... -replace=X`
// hide its own flag. The cost is a conservative false RED on a trailing comment that spells a flag, which is fixable
// in review; the alternative is a fail-open scan.
const SOLE_COPY_ADDRS = [
  "hcloud_volume.inngest_redis_luks",
  "hcloud_volume_attachment.inngest_redis_luks",
  "random_password.inngest_redis_luks",
  "doppler_secret.inngest_redis_luks_key",
  "doppler_project.inngest",
  "doppler_environment.inngest_prd",
];
// Full regexp-metacharacter escape (backslash included) for address literals interpolated into a RegExp.
const g2Esc = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
const G2_ADDR_ALT = SOLE_COPY_ADDRS.map((a) => g2Esc(a)).join("|");
const G2_WORKFLOW = "apply-web-platform-infra.yml";
// MEASURED 2026-10-10 on the live tree with
//   grep -nE "^[^#]*-(target|replace)[= ]+['\"]?(<the six addresses>)\b" .github/workflows/*.yml
// = seven lines, all in apply-web-platform-infra.yml (657-658 per-merge `apply`; 1673/1674/1680/1681 `inngest_host`;
// 1975 `inngest_host_replace`), zero -replace, zero -destroy. Entry shape: workflow|job|verb|address.
// Edited only with a reviewer reading it: the workflow is the other side of the comparison.
const SOLE_COPY_EXPECTED: readonly string[] = [
  `${G2_WORKFLOW}|apply|target|random_password.inngest_redis_luks`,
  `${G2_WORKFLOW}|apply|target|doppler_secret.inngest_redis_luks_key`,
  `${G2_WORKFLOW}|inngest_host|target|hcloud_volume.inngest_redis_luks`,
  `${G2_WORKFLOW}|inngest_host|target|hcloud_volume_attachment.inngest_redis_luks`,
  `${G2_WORKFLOW}|inngest_host|target|doppler_project.inngest`,
  `${G2_WORKFLOW}|inngest_host|target|doppler_environment.inngest_prd`,
  `${G2_WORKFLOW}|inngest_host_replace|target|hcloud_volume_attachment.inngest_redis_luks`,
];
const G2_TOP = "<top-level>";

/** Comment-stripped (whole-line), continuation-folded, LF-normalised code. */
const g2Code = (text: string): string => joinContinuations(stripShellLineComments(text.replace(/\r\n/g, "\n")));

/** job id -> block (via extractJobBlock); the text outside `jobs:` is keyed G2_TOP. Throws on a header it cannot parse. */
function g2Jobs(text: string): Map<string, string> {
  const lf = text.replace(/\r\n/g, "\n");
  const out = new Map<string, string>();
  const m = /^jobs:[ \t]*(?:#.*)?$/m.exec(lf);
  if (!m) {
    out.set(G2_TOP, lf);
    return out;
  }
  let body = lf.slice(m.index + m[0].length);
  const tail = /\n(?=[A-Za-z_][^\n]*:)/.exec(body); // a column-0 key after `jobs:` ends the section
  let rest = "";
  if (tail) {
    rest = body.slice(tail.index);
    body = body.slice(0, tail.index);
  }
  out.set(G2_TOP, lf.slice(0, m.index) + rest);
  const ids = new Set<string>();
  for (const line of body.split("\n")) {
    if (/^ {2}\S/.test(line) && !/^ {2}#/.test(line)) {
      const h = /^ {2}([A-Za-z0-9_-]+):/.exec(line);
      if (!h) throw new Error(`g2Jobs: unparseable job header ${JSON.stringify(line)}`);
      ids.add(h[1]);
    }
  }
  if (ids.size === 0) throw new Error("g2Jobs: no jobs found under jobs:");
  for (const id of ids) out.set(id, extractJobBlock(body, id));
  return out;
}

const g2Named = (code: string): string[] =>
  SOLE_COPY_ADDRS.filter((a) => new RegExp(`(?<![A-Za-z0-9_])${g2Esc(a)}(?![A-Za-z0-9_])`).test(code));

const G2_STATE_VERBS: Array<[string, RegExp]> = [
  ["state-rm", /(?<![\w-])state\s+rm(?![\w-])/],
  ["state-mv", /(?<![\w-])state\s+mv(?![\w-])/],
  ["state-push", /(?<![\w-])state\s+push(?![\w-])/],
  ["import", /\bterraform(?:\s+-chdir=\S+)?\s+import(?![\w-])/],
  ["taint", /\bterraform(?:\s+-chdir=\S+)?\s+taint(?![\w-])/],
];

/** A state-write verb in `code` x every sole-copy address `code` names (co-occurrence: a loop or variable cannot hide it). */
function g2StateWriteHits(code: string): Array<[string, string]> {
  const named = g2Named(code);
  const out: Array<[string, string]> = [];
  for (const [verb, re] of G2_STATE_VERBS) if (re.test(code)) for (const a of named) out.push([verb, a]);
  return out;
}

// Command position for `terraform [-chdir=X] destroy`: line start, a separator, a shell keyword, a YAML `run:`, an env
// assignment run, a privilege/exec wrapper (`sudo`, `env`, `time`, `timeout N`, `nice`, `flock x`, ...) with its options,
// `--` (doppler run), or the opening quote of `bash -c "..."`. The binary may be path-qualified (`/usr/bin/terraform`,
// `./terraform`), `$VAR` or `$(... terraform ...)`. Prose has a backtick, a quote or ordinary words in front, so it is not
// the command. STATED NON-GOALS (defence in depth only; prevent_destroy and the Hetzner lock are the real controls): `flock x
// -c '...'`, a binary renamed through a symlink, a destroy assembled at run time (`terraform "$verb"`), and a test-named
// driver script (skipped by G2_TEST_OR_FIXTURE: nothing in CI runs it as an apply; making it one is an edit to that script
// that a reviewer sees, and the destroy still meets prevent_destroy). This is a spelling list, not "every spelling".
// LINEARITY: a bare `{`, `!` or `--` is a prefix only when followed by whitespace (a long `{a={a=` token has no start per
// character), a keyword is a start only at a word boundary, and every repeated group is BOUNDED, so one start costs a
// constant number of tokens and the match is linear (two perf rows in the spelling suite pin it).
const G2_OPTS = String.raw`(?:[ \t]+-\S+(?!\S)(?:[ \t]+[\w./@:=+][^\s;&|()]*(?![^\s;&|()]))?){0,16}`;
const G2_CMD_PREFIX =
  String.raw`(?:^|[;&|(]|\{(?=[ \t])|!(?=[ \t])|--(?=[ \t])|\b(?:then|do|else|elif|if|while|until)\b|\brun:|\b(?:sudo|exec|time|command|env|nohup|xargs|eval|nice|ionice|setsid)\b${G2_OPTS}|\btimeout\b${G2_OPTS}[ \t]+\d[\w.]*|\bflock\b${G2_OPTS}[ \t]+\S+|\b(?:ba|z|da|k)?sh[ \t]+(?:-\w+[ \t]+)*-\w*c[ \t]+["'])`;
const G2_TERRAFORM_BIN = String.raw`(?:\$(?:\{\w+\}|\w+)|\$\([^()]*\bterraform\b[^()]*\)|(?:[\w.-]*/){0,8}terraform)`;
const G2_DESTROY_CMD = new RegExp(
  String.raw`${G2_CMD_PREFIX}[ \t]*(?:[A-Za-z_]\w*=[^\s;&|()]*[ \t]+){0,64}${G2_TERRAFORM_BIN}(?:[ \t]+-chdir[= ]\S+)?[ \t]+destroy(?![\w-])`,
  "m",
);
const G2_DESTROY_FLAG = /(?<![\w-])-destroy(?![\w-])/;

/**
 * Is this step's `working-directory` a rehearsal SUB-ROOT (its own state)? The path is NORMALISED first: `apps/web-platform/infra/.`
 * and `.../infra/./` are the main root itself, and `.../infra/sub/..` is too, so none of them is an exemption. `[ \t]*` (never `\s*`)
 * keeps the scan linear: `\s*` with /m crosses newlines and goes quadratic on a whitespace-only input.
 */
function g2IsSubRoot(step: string): boolean {
  const m = /^[ \t]*(?:-[ \t]+)?working-directory:[ \t]*(.*)$/m.exec(step); // greedy then trim: a lazy `(.*?)[ \t]*$` is quadratic on a long whitespace run
  if (!m) return false;
  const v = m[1].replace(/^(["'])(.*)\1$/, "$2").trim();
  if (/^\$\{\{\s*env\.REHEARSAL_DIR\s*\}\}$/.test(v)) return true;
  const root = "apps/web-platform/infra/";
  const i = v.indexOf(root);
  if (i < 0) return false;
  const rest = posix.normalize(v.slice(i));
  if (!rest.startsWith(root)) return false;
  const seg = rest.slice(root.length).split("/")[0];
  return seg !== ""; // `.`/`..` cannot survive posix.normalize behind the root prefix (fuzzed: 0 of 200k), so no further check
}

/** Every (verb, address) a job's code reaches: -target/-replace in `=`/space/quoted/escaped-quote spellings, destroy, state writes. */
function g2JobVerbs(code: string): Array<[string, string]> {
  const out: Array<[string, string]> = [];
  const flag = new RegExp(`-(target|replace)(?:=|\\s+)[\\\\'"]*(?:module\\.[A-Za-z0-9_-]+\\.)*(${G2_ADDR_ALT})(?![A-Za-z0-9_])`, "g");
  for (const m of code.matchAll(flag)) out.push([m[1], m[2]]);
  // Destroy, judged per STEP: a step whose `working-directory` is a rehearsal SUB-ROOT (its own state; the two rehearsal
  // workflows and their teardown steps) is out of scope unless it also names a sole-copy address (the flag scan above and
  // the state-write scan below already see that). Every other destroy is a hit. `[ack-destroy]` has a word char before the
  // dash, and prose `terraform destroy` sits behind a backtick/quote, so neither is the command.
  for (const step of code.split(/\n(?= {6}- )/)) {
    const isDestroy = G2_DESTROY_FLAG.test(step) || G2_DESTROY_CMD.test(step);
    if (isDestroy && !g2IsSubRoot(step)) out.push(["destroy", "*"]);
  }
  out.push(...g2StateWriteHits(code));
  return out;
}

/** Sorted unique `workflow|job|verb|address` over a {workflow filename: text} map. */
function g2Census(files: Record<string, string>): string[] {
  const set = new Set<string>();
  for (const [name, text] of Object.entries(files)) {
    for (const [job, block] of g2Jobs(text)) {
      for (const [verb, addr] of g2JobVerbs(g2Code(block))) set.add(`${name}|${job}|${verb}|${addr}`);
    }
  }
  return [...set].sort();
}

/** Non-vacuity: every (workflow, job) the expected set names must exist and still carry a -target flag. */
function g2MissingJobs(files: Record<string, string>, expected: readonly string[]): string[] {
  const missing: string[] = [];
  for (const key of new Set(expected.map((e) => e.split("|").slice(0, 2).join("|")))) {
    const [file, job] = key.split("|");
    const block = files[file] === undefined ? "" : (g2Jobs(files[file]).get(job) ?? "");
    if (!/-target(?:=|\s)/.test(g2Code(block))) missing.push(key);
  }
  return missing;
}

/** Empty array = GREEN. Anything else names the defect. */
function g2Verdict(files: Record<string, string>, expected: readonly string[] = SOLE_COPY_EXPECTED): string[] {
  const got = g2Census(files);
  const want = new Set(expected);
  return [
    ...g2MissingJobs(files, expected).map((k) => `job-not-found: ${k}`),
    ...got.filter((t) => !want.has(t)).map((t) => `unexpected: ${t}`),
    ...[...want].filter((t) => !got.includes(t)).map((t) => `absent: ${t}`),
  ];
}

function g2LiveWorkflows(): Record<string, string> {
  const dir = resolve(REPO_ROOT, ".github/workflows");
  const out: Record<string, string> = {};
  for (const f of readdirSync(dir).filter((n) => /\.ya?ml$/.test(n)).sort()) out[f] = readFileSync(resolve(dir, f), "utf8");
  return out;
}

/**
 * Tracked files the script scan covers: composite actions, CI helper scripts, repo scripts, every app's infra tree and the
 * web-platform scripts, in the extensions that can drive terraform. A symlink (lstat) is skipped, so a link into the tree
 * is not scanned twice or followed out of it. Test files and fixtures are skipped by name: they spell the forbidden verbs
 * on purpose, and nothing in CI runs them as an apply.
 */
const G2_SCRIPT_DIRS = /^(?:\.github\/actions\/|\.github\/scripts\/|scripts\/|apps\/[^/]+\/infra\/|apps\/web-platform\/scripts\/)/;
const G2_SCRIPT_EXT = /\.(?:sh|bash|py|ts|mjs|yml|yaml)$/;
const G2_TEST_OR_FIXTURE = /(?:^|\/)(?:tests?|fixtures?|__tests__|__fixtures__)\/|(?:^|\/)test[-_][^/]*$|[.-]tests?\.[a-z]+$|[-_]test\.[a-z]+$/;
/** The scan population among `paths` (repo-relative): in the directories and extensions above, not a test/fixture, a real file (not a symlink) under `root`. */
function g2ScanPopulation(paths: string[], root: string): string[] {
  return paths
    .filter((p) => G2_SCRIPT_DIRS.test(p) && G2_SCRIPT_EXT.test(p) && !G2_TEST_OR_FIXTURE.test(p))
    .filter((p) => {
      try {
        return lstatSync(resolve(root, p)).isFile(); // false for a symlink, a directory or a path deleted in the worktree
      } catch {
        return false;
      }
    });
}

function g2TrackedScripts(): string[] {
  const r = spawnSync("git", ["ls-files", "-z"], { cwd: REPO_ROOT, encoding: "utf8", maxBuffer: 1 << 27 });
  if (r.status !== 0) throw new Error(`git ls-files failed: ${r.stderr}`);
  return g2ScanPopulation(r.stdout.split("\0"), REPO_ROOT);
}

/** Whole-line comments out: `#` for every extension, `//` as well for ts/mjs. Trailing comments are kept (see the policy note above). */
const g2ScriptCode = (rel: string, text: string): string => {
  const code = g2Code(text);
  return /\.(?:ts|mjs)$/.test(rel) ? code.split("\n").filter((l) => !/^\s*\/\//.test(l)).join("\n") : code;
};

// Flag spellings and destroy, as FILE-level verbs: in a script there is no job or step to scope them to, so the rule is the
// same co-occurrence the state verbs use (verb anywhere x sole-copy address anywhere in the same file).
const G2_FILE_FLAG_VERBS: Array<[string, RegExp]> = [
  ["target", /(?<![\w-])-target(?![\w-])/],
  ["replace", /(?<![\w-])-replace(?![\w-])/],
  ["destroy", new RegExp(`${G2_DESTROY_FLAG.source}|${G2_DESTROY_CMD.source}`, "m")],
];

/** `script|verb|address` for any state-write or flag verb in a file that names a sole-copy address anywhere. */
function g2ScriptHits(rel: string, text: string): string[] {
  const code = g2ScriptCode(rel, text);
  const named = g2Named(code);
  if (named.length === 0) return [];
  const verbs = [...G2_STATE_VERBS, ...G2_FILE_FLAG_VERBS];
  return verbs.flatMap(([v, re]) => (re.test(code) ? named.map((a) => `${rel}|${v}|${a}`) : []));
}

/** Insert `newLines` (indented like the anchor) BEFORE the first line matching `anchor` inside `jobId` (any job if omitted). */
function g2InsertBefore(text: string, anchor: RegExp, newLines: string[], jobId?: string): string {
  const out: string[] = [];
  let inJob = jobId === undefined;
  let done = false;
  for (const line of text.split("\n")) {
    if (jobId !== undefined && /^ {2}[A-Za-z0-9_-]+:/.test(line)) inJob = new RegExp(`^ {2}${jobId}:`).test(line);
    if (inJob && !done && anchor.test(line)) {
      const indent = /^\s*/.exec(line)![0];
      for (const n of newLines) out.push(indent + n);
      done = true;
    }
    out.push(line);
  }
  if (!done) throw new Error(`g2InsertBefore: anchor ${anchor} not found${jobId ? ` in job ${jobId}` : ""}`);
  return out.join("\n");
}

/**
 * The inngest dispatch surfaces after the plaintext-backstop retirement (#8285 PR B).
 *
 * `apply_target=inngest-backstop-retire` and its `inngest_backstop_retire` job were deleted once the
 * volume was destroyed. What stays pinned: the retired surface stays RETIRED (Guard 1: a conflict
 * resolution or a revert-of-a-revert cannot silently bring the destroy dispatch back), and the properties
 * of the surfaces that remain (the shared inngest mutex, the replace job's targets, the LUKS passphrase
 * pair's place in the per-merge list).
 *
 * THE MUTEX IS TWO GROUPS, and a job can carry only one. The job-level group is the inngest one
 * (`deploy-inngest-restart`, shared with cutover-inngest.yml and the host jobs); the root's
 * serializer (`terraform-apply-web-platform-host`, the state backend has use_lockfile = false) is the
 * WORKFLOW-level group, which already governs every job in this file. Both are asserted as properties.
 */
describe("inngest dispatch surfaces after the backstop retirement (#8285 PR B)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const RETIRED_ADDRS = [
    "hcloud_volume.inngest_redis",
    "hcloud_volume_attachment.inngest_redis",
    "hcloud_server.inngest_backstop_wipe",
    "hcloud_volume_attachment.inngest_backstop_wipe",
  ];

  test("G1: the retired dispatch stays retired (no job, enum option, confirm literal, input or -target) in ANY workflow", () => {
    // Quotes and a trailing comment are tolerated on every form: YAML accepts all of them, so a guard that
    // matches only the bare spelling is defeated by re-quoting the revert.
    const JOB = /^ {2}["']?inngest_backstop_retire["']?:[ \t]*(?:#.*)?$/m;
    const OPTION = /^ +- ["']?inngest-backstop-retire["']?[ \t]*(?:#.*)?$/m;
    const INPUT = /^ +["']?(expected_inngest_volume_id|phase|wipe_run_id|erasure|clo_attestation_ref)["']?:[ \t]*(?:#.*)?$/m;
    // A retired address reaching terraform as -target / -replace, in either `=` or space form, in any job.
    const ADDR_FLAG = new RegExp(
      `-(?:target|replace)(?:=|\\s+)["']?(?:${RETIRED_ADDRS.map((a) => g2Esc(a)).join("|")})\\b`,
    );
    // Non-vacuity: each pattern recognises the form it forbids, so an empty result is not a blind scan.
    expect(JOB.test("  inngest_backstop_retire:\n")).toBe(true);
    expect(JOB.test("  'inngest_backstop_retire': # x\n")).toBe(true);
    expect(OPTION.test("          - inngest-backstop-retire\n")).toBe(true);
    expect(OPTION.test("      - inngest-backstop-retire\n")).toBe(true); // any indent
    expect(OPTION.test('          - "inngest-backstop-retire"\n')).toBe(true);
    expect(INPUT.test("      wipe_run_id:\n")).toBe(true);
    expect(INPUT.test("      phase:\n")).toBe(true);
    expect(ADDR_FLAG.test("-target=hcloud_server.inngest_backstop_wipe")).toBe(true);
    // A line continuation between the flag and its operand is folded (as the census does) before the scan.
    expect(ADDR_FLAG.test("-target \\\n  hcloud_server.inngest_backstop_wipe".replace(/\\\r?\n\s*/g, " "))).toBe(true);
    expect(ADDR_FLAG.test('-replace "hcloud_volume.inngest_redis"')).toBe(true);
    // The LIVE sibling must not match (the \b / name boundary is what keeps `inngest_redis_luks` legal).
    expect(ADDR_FLAG.test("-target=hcloud_volume.inngest_redis_luks")).toBe(false);
    expect(extractAllTargets(wf).size).toBeGreaterThan(50);

    const dir = resolve(REPO_ROOT, ".github/workflows");
    const workflows = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f));
    expect(workflows.length).toBeGreaterThan(10); // non-vacuity: the directory scan reached the workflows
    for (const f of workflows) {
      const text = readFileSync(resolve(dir, f), "utf8");
      const code = stripComments(text);
      expect(JOB.test(text), `${f}: retired job key`).toBe(false);
      expect(OPTION.test(text), `${f}: retired apply_target option`).toBe(false);
      // `phase` is a generic word: only the retired job's workflow could have carried it, so it is scoped to the
      // file the dispatch lived in; the other four inputs are unique to the retired job and scanned everywhere.
      const inputRe = f === "apply-web-platform-infra.yml" ? INPUT : /^ +["']?(expected_inngest_volume_id|wipe_run_id|erasure|clo_attestation_ref)["']?:/m;
      expect(inputRe.test(text), `${f}: retired workflow_dispatch input`).toBe(false);
      expect(code, `${f}: confirm literal`).not.toContain("RETIRE-INNGEST-BACKSTOP");
      expect(text, `${f}: gate library`).not.toContain("inngest-backstop-retire-gate.sh");
      expect(ADDR_FLAG.test(code.replace(/\\\r?\n\s*/g, " ")), `${f}: retired address as -target/-replace`).toBe(false);
    }
    const all = extractAllTargets(wf);
    for (const addr of RETIRED_ADDRS) {
      expect(all.has(addr), `${addr} must not be a -target of any job`).toBe(false);
    }
  });

  test("G1b: the deleted apparatus files and the four wipe variables stay deleted", () => {
    const GONE = [
      "apps/web-platform/infra/inngest-backstop-wipe.tf",
      "apps/web-platform/infra/cloud-init-inngest-backstop-wipe.yml",
      "apps/web-platform/infra/inngest-backstop-wipe.test.sh",
      "tests/scripts/lib/inngest-backstop-retire-gate.sh",
      "tests/scripts/test-inngest-backstop-retire-gate.sh",
    ];
    // Non-vacuity: the check resolves a path that DOES exist, so an always-false existsSync would not pass it.
    expect(existsSync(resolve(REPO_ROOT, "apps/web-platform/infra/inngest-redis-luks.tf"))).toBe(true);
    for (const rel of GONE) expect(existsSync(resolve(REPO_ROOT, rel)), `${rel} was deleted by #8285 PR B`).toBe(false);
    const vars = stripComments(readFileSync(resolve(INFRA_DIR, "variables.tf"), "utf8"));
    expect(vars).toMatch(/variable "inngest_redis_volume_size"/); // non-vacuity: a live sibling variable is found
    expect(vars).not.toMatch(/variable\s+"inngest_backstop_/);
  });

  test("B9: inngest_host, inngest_host_replace and cutover-inngest share ONE job-level mutex; the workflow-level root group governs all", () => {
    const CUTOVER_WORKFLOW = resolve(REPO_ROOT, ".github/workflows/cutover-inngest.yml");
    const groupOf = (block: string): string | null => {
      const m = /^ {4}concurrency:\n {6}group: (\S+)\n {6}cancel-in-progress: (\S+)$/m.exec(block);
      return m ? `${m[1]}|${m[2]}` : null;
    };
    const surfaces: Array<[string, string | null]> = [
      ["inngest_host", groupOf(extractJobBlock(wf, "inngest_host"))],
      ["inngest_host_replace", groupOf(extractJobBlock(wf, "inngest_host_replace"))],
      ["cutover-inngest.yml:cutover", groupOf(extractJobBlock(readFileSync(CUTOVER_WORKFLOW, "utf8"), "cutover"))],
    ];
    for (const [name, g] of surfaces) {
      expect(g, `${name} declares no job-level concurrency group`).not.toBeNull();
    }
    expect([...new Set(surfaces.map(([, g]) => g))]).toEqual(["deploy-inngest-restart|false"]);
    // The root's serializer (no state lock): a workflow-level group, identical to apply-deploy-pipeline-fix.yml's.
    expect(wf).toMatch(/^concurrency:\n(?:  #[^\n]*\n)*  group: terraform-apply-web-platform-host\n  cancel-in-progress: false$/m);
  });

  test("B6: inngest_host_replace does not target the plaintext pair, still carries the LUKS attachment, and no volume (#6894, #8285)", () => {
    const replaceJob = extractJobBlock(wf, "inngest_host_replace");
    const targets = extractAllTargets(replaceJob);
    expect(targets.has("hcloud_server.inngest")).toBe(true); // non-vacuity: the extraction reached the job
    expect(targets.has("hcloud_volume_attachment.inngest_redis_luks")).toBe(true);
    expect(targets.has("hcloud_volume_attachment.inngest_redis")).toBe(false);
    // The durable volume is preserved by OMISSION - targeting it would put the sole copy one replace from a destroy.
    expect(targets.has("hcloud_volume.inngest_redis")).toBe(false);
    expect(targets.has("hcloud_volume.inngest_redis_luks")).toBe(false);
    expect(extractAllTargets(extractJobBlock(wf, "inngest_host")).has("hcloud_volume.inngest_redis")).toBe(false);
    expect(extractAllTargets(extractJobBlock(wf, "inngest_host")).has("hcloud_volume_attachment.inngest_redis")).toBe(false);
  });

  test("B5: the LUKS passphrase pair is in the PER-MERGE -target list, not the inngest_host job's", () => {
    expect(extractAllTargets(extractJobBlock(wf, "inngest_host")).has("random_password.inngest_redis_luks")).toBe(false);
    const perMerge = extractAllTargets(stripDispatchJobs(wf));
    expect(perMerge.has("random_password.inngest_redis_luks")).toBe(true);
    expect(perMerge.has("doppler_secret.inngest_redis_luks_key")).toBe(true);
  });

  // ---- G2 reachability (#9879): the sole-copy addresses are reachable ONLY through the expected (workflow, job, verb) set ----
  test("G2: live tree - the (workflow, job, verb, address) census over every workflow equals the expected set", () => {
    const files = g2LiveWorkflows();
    expect(Object.keys(files).length).toBeGreaterThan(10); // non-vacuity: the directory scan reached the workflows
    expect(Object.keys(files)).toContain(G2_WORKFLOW);
    expect(SOLE_COPY_EXPECTED.length).toBe(7);
    expect(g2Verdict(files)).toEqual([]);
    expect(g2Census(files)).toEqual([...SOLE_COPY_EXPECTED].sort());
    // Zero -replace and zero destroy of any of them, anywhere.
    expect(g2Census(files).filter((t) => /\|(replace|destroy)\|/.test(t))).toEqual([]);
    // Non-vacuity through the EXISTING chokepoints: the three expected jobs are found and carry -targets.
    for (const job of ["apply", "inngest_host", "inngest_host_replace"]) {
      expect(extractAllTargets(extractJobBlock(wf, job)).size, `${job} extracted empty`).toBeGreaterThan(0);
      expect(g2Jobs(wf).get(job)).toBe(extractJobBlock(wf.slice(wf.indexOf("\njobs:\n") + 6), job));
    }
    // The per-merge view after stripDispatchJobs: the inngest_host job is gone from it, the other two expected jobs remain.
    const perMerge = g2Census({ [G2_WORKFLOW]: stripDispatchJobs(wf) });
    expect(perMerge).toEqual(SOLE_COPY_EXPECTED.filter((t) => !t.includes("|inngest_host|")).sort());
    // The two Doppler parents are targeted (never replaced or destroyed) and only by inngest_host.
    for (const parent of ["doppler_project.inngest", "doppler_environment.inngest_prd"]) {
      expect(g2Census(files).filter((t) => t.endsWith(`|${parent}`))).toEqual([`${G2_WORKFLOW}|inngest_host|target|${parent}`]);
    }
  }, 60_000);

  test("G2: mutation matrix rows 1-7 each turn the verdict RED (scratch copies only)", () => {
    const live = g2LiveWorkflows();
    const VOL = "hcloud_volume.inngest_redis_luks";
    const ATT = "hcloud_volume_attachment.inngest_redis_luks";
    const att = /-target='hcloud_volume_attachment\.inngest_redis_luks' \\$/;
    const withWf = (text: string, extra: Record<string, string> = {}) => ({ ...live, [G2_WORKFLOW]: text, ...extra });
    const rows: Array<[string, Record<string, string>, RegExp]> = [
      ["1 -replace of the volume in inngest_host_replace",
        withWf(g2InsertBefore(wf, att, [`-replace='${VOL}' \\`], "inngest_host_replace")), /unexpected: .*\|inngest_host_replace\|replace\|hcloud_volume\.inngest_redis_luks/],
      ["2 -target of the volume in inngest_host_replace",
        withWf(g2InsertBefore(wf, att, [`-target='${VOL}' \\`], "inngest_host_replace")), /unexpected: .*\|inngest_host_replace\|target\|hcloud_volume\.inngest_redis_luks/],
      ["3 the attachment target in a third job (both legal ones intact)",
        withWf(g2InsertBefore(wf, /^\s*-target=/, [`-target='${ATT}' \\`], "registry_host_replace")), /unexpected: .*\|registry_host_replace\|target\|hcloud_volume_attachment\.inngest_redis_luks/],
      ["4 a terraform destroy step in a main-root workflow",
        withWf(wf, { "apply-deploy-pipeline-fix.yml": g2InsertBefore(live["apply-deploy-pipeline-fix.yml"], /^\s+terraform plan -target=/, ["terraform destroy -auto-approve"]) }), /unexpected: apply-deploy-pipeline-fix\.yml\|.*\|destroy\|\*/],
      ["5 -target X spelled with a space and a line continuation",
        withWf(g2InsertBefore(wf, att, ["-target \\", `  ${VOL} \\`], "inngest_host_replace")), /unexpected: .*\|inngest_host_replace\|target\|hcloud_volume\.inngest_redis_luks/],
      ["6 renamed job (expected job not found)",
        withWf(wf.replace(/^ {2}inngest_host_replace:/m, "  inngest_host_replace_renamed:")), /job-not-found: .*\|inngest_host_replace/],
      ["7 a new workflow file naming the pair in -target",
        withWf(wf, { "zz-new.yml": `name: x\njobs:\n  j:\n    steps:\n      - run: |\n          terraform apply \\\n            -target=random_password.inngest_redis_luks \\\n            -target=doppler_secret.inngest_redis_luks_key\n` }), /unexpected: zz-new\.yml\|j\|target\|random_password\.inngest_redis_luks/],
    ];
    expect(g2Verdict(live)).toEqual([]); // control: the unmutated tree is GREEN, so a RED below is the mutation's doing
    for (const [name, files, want] of rows) {
      if (name.startsWith("6")) expect(files[G2_WORKFLOW]).not.toBe(wf);
      const verdict = g2Verdict(files);
      expect(verdict.length, `row ${name} stayed GREEN`).toBeGreaterThan(0);
      expect(verdict.join("\n"), `row ${name} was RED for the wrong reason`).toMatch(want);
    }
  }, 60_000);

  test("G2: every spelling is seen - flags, destroy, taint, state write, import (in a non-expected job)", () => {
    const live = { [G2_WORKFLOW]: wf }; // one file is enough for a per-spelling verdict and keeps the loop fast
    const VOL = "hcloud_volume.inngest_redis_luks";
    const PW = "random_password.inngest_redis_luks";
    const anchor = /-target='hcloud_volume_attachment\.inngest_redis_luks' \\$/;
    const spellings: Array<[string, string[], string, RegExp?]> = [
      ["-target=X", [`-target=${VOL} \\`], "target"],
      ["-target X", [`-target ${VOL} \\`], "target"],
      ["-target 'X'", [`-target '${VOL}' \\`], "target"],
      ['-target="X"', [`-target="${VOL}" \\`], "target"],
      ['-target=\\"X\\"', [`-target=\\"${VOL}\\" \\`], "target"],
      ["-replace=X", [`-replace=${VOL} \\`], "replace"],
      ["-replace X", [`-replace ${VOL} \\`], "replace"],
      ["-replace 'X'", [`-replace '${VOL}' \\`], "replace"],
      ["-destroy", ["-destroy \\"], "destroy"],
      ["terraform destroy (own line)", ["terraform destroy -auto-approve"], "destroy", /^\s*set \+e$/],
      ["doppler run -- terraform destroy", ["doppler run -p soleur -c prd_terraform -- terraform destroy -auto-approve"], "destroy", /^\s*set \+e$/],
      ["cd x && terraform destroy", ["cd x && terraform destroy -auto-approve"], "destroy", /^\s*set \+e$/],
      ["terraform taint", [`terraform taint ${PW}`], "taint"],
      ["state rm", [`terraform state rm ${PW}`], "state-rm"],
      ["state mv", [`terraform state mv ${PW} random_password.elsewhere`], "state-mv"],
      ["state push (job also names an address)", ["terraform state push errored.tfstate"], "state-push"],
      ["import", [`terraform import ${PW} id`], "import"],
    ];
    for (const [name, lines, verb, own] of spellings) {
      const text = g2InsertBefore(wf, own ?? anchor, lines, "inngest_host_replace");
      const census = g2Census({ ...live, [G2_WORKFLOW]: text });
      expect(census.filter((t) => t.includes(`|inngest_host_replace|${verb}|`)), `spelling "${name}" was not seen`).not.toEqual([]);
      expect(g2Verdict({ ...live, [G2_WORKFLOW]: text }).length, `spelling "${name}" stayed GREEN`).toBeGreaterThan(0);
    }
    // The scanner's own non-vacuity: `[ack-destroy]` prose is not the -destroy flag, and a sibling address is not a sole-copy one.
    expect(g2JobVerbs(g2Code("echo 'add [ack-destroy] to the commit'"))).toEqual([]);
    expect(g2JobVerbs(g2Code("terraform plan -target=hcloud_volume.inngest_redis_luks_other -target=doppler_project.inngest_x"))).toEqual([]);
    // Comments are stripped: a whole-line comment naming a flag is not a hit.
    expect(g2JobVerbs(g2Code(`# -replace=${VOL}\n  # terraform destroy`))).toEqual([]);
    // A `#` inside a string or `$#` cannot hide a flag behind it (trailing comments are deliberately NOT stripped).
    expect(g2JobVerbs(g2Code(`echo "$#"; terraform apply -replace=${VOL}`))).toEqual([["replace", VOL]]);
  }, 60_000);

  test("G2: destroy spellings in a main-root workflow are RED; prose, sub-root steps and non-destroy words stay GREEN", () => {
    const jobOf = (stepBody: string): string => `name: x\njobs:\n  j:\n    runs-on: ubuntu-latest\n    steps:\n${stepBody}\n`;
    const verdictOf = (stepBody: string): string[] => g2Census({ "zz.yml": jobOf(stepBody) });
    const RUN = (cmd: string) => `      - run: |\n          ${cmd}`;
    const wd = (dir: string, cmd = "terraform destroy -auto-approve") => `      - name: t\n        working-directory: ${dir}\n        run: ${cmd}`;
    const red: Array<[string, string]> = [
      ["- run: terraform destroy (single-line step)", "      - run: terraform destroy"],
      ["if terraform destroy ...; then", RUN("if terraform destroy -auto-approve; then echo done; fi")],
      ["sudo terraform destroy", RUN("sudo terraform destroy -auto-approve")],
      ["sudo -E terraform destroy", RUN("sudo -E terraform destroy")],
      ["VAR=x terraform destroy", RUN("TF_VAR_x=1 terraform destroy -auto-approve")],
      ["two assignments then destroy", RUN("A=1 B=2 terraform destroy")],
      ['bash -c "terraform destroy"', RUN('bash -c "terraform destroy -auto-approve"')],
      ["sh -ec 'terraform destroy'", RUN("sh -ec 'terraform destroy'")],
      ["env X=1 terraform destroy", RUN("env X=1 terraform destroy")],
      ["terraform -chdir=x destroy", RUN("terraform -chdir=apps/web-platform/infra destroy")],
      ["a && terraform destroy", RUN("cd x && terraform destroy")],
      ["wd apps/web-platform/infra/. is the main root", wd("apps/web-platform/infra/.")],
      ["wd apps/web-platform/infra/ ./ form", wd("apps/web-platform/infra/./")],
      ["wd ./apps/web-platform/infra/.", wd("./apps/web-platform/infra/.")],
      ["wd apps/web-platform/infra/sub/.. is the main root", wd("apps/web-platform/infra/sub/..")],
      ["wd no working-directory", "      - name: t\n        run: terraform destroy"],
      ["wd quoted main root", wd(`"apps/web-platform/infra/."`)],
    ];
    const green: Array<[string, string]> = [
      ["prose in an echo", RUN('echo "this job never runs terraform destroy"')],
      ["prose in backticks", RUN("echo 'see `terraform destroy` in the runbook'")],
      ["::error:: annotation", RUN('echo "::error::terraform destroy refused"')],
      ["whole-line comment", RUN("# terraform destroy -auto-approve\n          echo ok")],
      ["a terraform plan", RUN("terraform plan -out tfplan")],
      ["the [ack-destroy] marker", RUN("echo 'add [ack-destroy] to the commit'")],
      ["REHEARSAL_DIR sub-root", wd("${{ env.REHEARSAL_DIR }}")],
      ["a named sub-dir sub-root", wd("apps/web-platform/infra/rehearsal")],
      ["a ./-prefixed sub-dir sub-root", wd("./apps/web-platform/infra/rehearsal/inner")],
      ["a workspace-prefixed sub-dir sub-root", wd("${{ github.workspace }}/apps/web-platform/infra/rehearsal")],
      ["a binary that merely ends in terraform", RUN("my-terraform destroy")],
      ["a path segment that merely ends in terraform", RUN("./xterraform destroy")],
      ["a variable that is an argument, not the command", RUN("echo $TF destroy")],
      ["prose behind sudo and an option value", RUN("sudo -u root echo terraform destroy")],
      ["terraform destroys (a longer word)", RUN("terraform destroys")],
      ["a quoted $TF in prose", RUN('echo "run $TF destroy later"')],
    ];
    // TABLE: one row per alternative of G2_CMD_PREFIX (and per binary spelling). Each line reaches `terraform` ONLY through the
    // named alternative (line start + whitespace cannot skip the leading word), so dropping any one alternative reds its row.
    const table: Array<[string, string]> = [
      [";", "echo a; terraform destroy"],
      ["&", "echo a & terraform destroy"],
      ["|", "echo a | terraform destroy"],
      ["(", "(terraform destroy)"],
      ["{ ", "{ terraform destroy; }"],
      ["! ", "! terraform destroy"],
      ["-- ", "doppler run -- terraform destroy"],
      ["then", "then terraform destroy"],
      ["do", "do terraform destroy"],
      ["else", "else terraform destroy"],
      ["elif", "elif terraform destroy; then"],
      ["if", "if terraform destroy; then"],
      ["while", "while terraform destroy; do"],
      ["until", "until terraform destroy; do"],
      ["sudo", "sudo terraform destroy"],
      ["exec", "exec terraform destroy"],
      ["time", "time terraform destroy"],
      ["command", "command terraform destroy"],
      ["env", "env terraform destroy"],
      ["nohup", "nohup terraform destroy"],
      ["xargs", "xargs terraform destroy"],
      ["eval", "eval terraform destroy"],
      ["nice", "nice terraform destroy"],
      ["ionice", "ionice -c3 terraform destroy"],
      ["setsid", "setsid terraform destroy"],
      ["timeout N", "timeout 60 terraform destroy"],
      ["timeout -k N D", "timeout -k 5 60s terraform destroy"],
      ["flock FILE", "flock /tmp/l terraform destroy"],
      ["flock -w N FILE", "flock -w 5 /tmp/l terraform destroy"],
      ["bash -c", 'bash -c "terraform destroy"'],
      ["sh -c", "sh -c 'terraform destroy'"],
      ["zsh -c", 'zsh -c "terraform destroy"'],
      ["dash -ec", "dash -ec 'terraform destroy'"],
      ["ksh -c", "ksh -c 'terraform destroy'"],
      ["run:", "      - run: terraform destroy"],
      ["assignment run", "TF_LOG=1 TF_IN_AUTOMATION=1 terraform destroy"],
      ["sudo -u root", "sudo -u root terraform destroy"],
      ["sudo -n -E -u root", "sudo -n -E -u root terraform destroy"],
      ["nice -n 10", "nice -n 10 terraform destroy"],
      ["env -u A B=1", "env -u A B=1 terraform destroy"],
      ["path /usr/bin/terraform", "/usr/bin/terraform destroy"],
      ["path ./terraform", "./terraform destroy"],
      ["path + -chdir", "sudo /usr/local/bin/terraform -chdir=x destroy"],
      ["$TF", "$TF destroy"],
      ["${TF}", "${TERRAFORM} destroy"],
      ["$(which terraform)", "$(which terraform) destroy"],
    ];
    for (const [name, step] of red) {
      expect(verdictOf(step).filter((t) => t.endsWith("|destroy|*")), `destroy spelling "${name}" stayed GREEN`).not.toEqual([]);
    }
    for (const [name, cmd] of table) {
      const step = cmd.startsWith("      - run:") ? cmd : RUN(cmd);
      expect(verdictOf(step).filter((t) => t.endsWith("|destroy|*")), `prefix alternative "${name}" stayed GREEN: ${cmd}`).not.toEqual([]);
    }
    for (const [name, step] of green) {
      expect(verdictOf(step), `"${name}" must stay GREEN`).toEqual([]);
    }
    // g2IsSubRoot directly: the normalisation, not a regex shape, decides.
    for (const [dir, want] of [
      ["apps/web-platform/infra/.", false],
      ["apps/web-platform/infra/./", false],
      ["apps/web-platform/infra", false],
      ["apps/web-platform/infra/sub/..", false],
      ["apps/web-platform/infra/../infra/.", false],
      ["apps/web-platform/infra/sub", true],
      ["apps/web-platform/infra/./sub", true],
      ["${{ env.REHEARSAL_DIR }}", true],
      ["apps/other/infra/sub", false],
    ] as const) {
      expect(g2IsSubRoot(`        working-directory: ${dir}`), `working-directory: ${dir}`).toBe(want);
    }
    // The existing per-job path agrees: the same insertion into a live non-expected job is RED for the new spellings.
    const live = { [G2_WORKFLOW]: wf };
    for (const line of ["sudo terraform destroy", "if terraform destroy; then", "TF_VAR_x=1 terraform destroy", 'bash -c "terraform destroy"']) {
      const text = g2InsertBefore(wf, /^\s*set \+e$/, [line], "inngest_host_replace");
      expect(g2Verdict({ ...live, [G2_WORKFLOW]: text }).join("\n"), line).toMatch(/unexpected: .*\|inngest_host_replace\|destroy\|\*/);
    }
  }, 60_000);

  test("G2: scanners are linear - whitespace-only, assignment-run, and separator-run inputs finish in under 2s", () => {
    const hostile: Array<[string, string]> = [
      ["300 KB of newline-space-tab", "\n \t".repeat(100_000)],
      ["300 KB of newline-space-tab after a working-directory key", "      - run: x\n        working-directory:" + "\n \t".repeat(100_000)],
      ["a run of `;a=` separators", ";a=".repeat(100_000)],
      ["a run of `;a= ` assignment tokens", ";a= ".repeat(75_000)],
      ["a long `a=a=a=` token", "a=".repeat(150_000)],
      ["repeated `terraform ` words", "terraform ".repeat(30_000)],
      ["repeated `sudo -x ` wrappers", "sudo -x ".repeat(40_000)],
      ["a run of `-target` and whitespace", "-target \n".repeat(40_000)],
      // the prefix alternatives that start a scan at every occurrence: a bare `{`, `!`, `--` and keywords inside assignment values
      ["a run of `{a=` tokens", "{a=".repeat(100_000)],
      ["a run of `!a=` tokens", "!a=".repeat(100_000)],
      ["a run of `--a=` tokens", "--a=".repeat(100_000)],
      ["a run of `a=sudo ` assignment values", "a=sudo ".repeat(40_000)],
      ["a run of `a=then ` assignment values", "a=then ".repeat(40_000)],
      ["a run of `sudo -sudo ` wrappers", "sudo -sudo ".repeat(30_000)],
      ["`sudo -` and one 300 KB option word", "sudo -" + "a".repeat(300_000)],
      ["repeated `timeout 5 ` and `flock x ` wrappers", "timeout 5 flock x ".repeat(20_000)],
      ["a run of `;$(a` command substitutions", ";$(a".repeat(60_000)],
      ["one 300 KB path-shaped word", "; " + "a/".repeat(150_000)],
      ["a long whitespace run inside a working-directory value", "      - run: x\n        working-directory: a" + " ".repeat(100_000) + "y"],
    ];
    for (const [name, text] of hostile) {
      const t0 = performance.now();
      const verbs = g2JobVerbs(g2Code(text));
      const hits = g2ScriptHits("h.sh", text);
      g2IsSubRoot(text);
      const ms = performance.now() - t0;
      expect(ms, `${name}: ${ms.toFixed(0)} ms`).toBeLessThan(2000);
      expect([name, verbs, hits]).toEqual([name, [], []]); // nothing real in the text: the fast path is also the correct path
    }
  }, 60_000);

  test("G2: tracked scripts - no state-write or flag verb co-occurs with a sole-copy address", () => {
    const scripts = g2TrackedScripts();
    // MEASURED 2026-10-10: 537 files after the test/fixture skip (1063 before it), zero hits. The floor is a non-vacuity bound, not the count.
    expect(scripts.length).toBeGreaterThan(400); // the listing reached every directory class below, not just scripts/
    for (const dir of [/^\.github\/actions\//, /^\.github\/scripts\//, /^scripts\//, /^apps\/[^/]+\/infra\//]) {
      expect(scripts.filter((p) => dir.test(p)).length, `no scanned file under ${dir}`).toBeGreaterThan(0);
    }
    for (const ext of [".sh", ".py", ".yml"]) expect(scripts.some((p) => p.endsWith(ext)), `no scanned ${ext} file`).toBe(true);
    // Non-vacuity: the scan can SEE a sole-copy address in this population (three files name one without a verb) - an empty hit list is not a blind scan.
    const naming = scripts.filter((rel) => g2Named(g2ScriptCode(rel, readFileSync(resolve(REPO_ROOT, rel), "utf8"))).length > 0);
    expect(naming.length).toBeGreaterThan(0);
    const hits = scripts.flatMap((rel) => g2ScriptHits(rel, readFileSync(resolve(REPO_ROOT, rel), "utf8")));
    expect(hits).toEqual([]);
    // Scratch control (the real-content control, a script retired with the rebirth workflow): a verb IS present
    // and no sole-copy address is named, so the line is legal by content, not by exemption. It flows through the same two
    // functions the population scan uses (g2Code/G2_STATE_VERBS and g2Named), embedded in a longer line with a leading `cd x &&`
    // and a trailing comment, so a verb-less scanner (empty G2_STATE_VERBS) or a blind matcher cannot pass it.
    const control = g2Code(`cd x && terraform state rm 'hcloud_volume.workspaces["web-2"]' # web-2 pinned form`);
    expect(G2_STATE_VERBS.some(([v, re]) => v === "state-rm" && re.test(control))).toBe(true);
    expect(g2Named(control)).toEqual([]);
    expect(g2ScriptHits("c.sh", `cd x && terraform state rm 'hcloud_volume.workspaces["web-2"]' # web-2 pinned form`)).toEqual([]);
    // The same line plus a second line naming a sole-copy address must report exactly that one hit, not "at least one" and not none.
    expect(g2ScriptHits("c.sh", `cd x && terraform state rm 'hcloud_volume.workspaces["web-2"]'\nterraform state rm hcloud_volume.inngest_redis_luks`)).toEqual(["c.sh|state-rm|hcloud_volume.inngest_redis_luks"]);
    // Mutations on scratch strings: each spelling in a script is RED; the web-2 pinned form is not.
    const VOL = "hcloud_volume.inngest_redis_luks";
    expect(g2ScriptHits("s.sh", `terraform state rm 'hcloud_volume.inngest_redis_luks'`)).toEqual(["s.sh|state-rm|hcloud_volume.inngest_redis_luks"]);
    expect(g2ScriptHits("s.sh", `addrs=(doppler_project.inngest)\n(cd x && terraform state rm "\${addrs[@]}")`)).toEqual(["s.sh|state-rm|doppler_project.inngest"]);
    expect(g2ScriptHits("s.sh", `terraform \\\n  import doppler_environment.inngest_prd p/e`)).toEqual(["s.sh|import|doppler_environment.inngest_prd"]);
    expect(g2ScriptHits("s.sh", `# terraform state rm hcloud_volume.inngest_redis_luks`)).toEqual([]);
    expect(g2ScriptHits("s.sh", `terraform state rm 'hcloud_volume.workspaces["web-2"]'`)).toEqual([]);
    // The flag verbs co-occur the same way, in every extension of the population.
    for (const [rel, line, verb] of [
      ["a.sh", `terraform apply -replace=${VOL}`, "replace"],
      ["a.bash", `terraform apply -target=${VOL}`, "target"],
      ["a.sh", `terraform plan -destroy -out p # ${VOL}`, "destroy"],
      ["a.py", `subprocess.run(["terraform", "-replace", "${VOL}"])`, "replace"],
      ["a.yml", `      - run: terraform destroy\n      - run: echo ${VOL}`, "destroy"],
      ["a.ts", `await $\`terraform apply -target=\${"${VOL}"}\``, "target"],
    ] as const) {
      expect(g2ScriptHits(rel, line), `${rel}: ${line}`).toEqual([`${rel}|${verb}|${VOL}`]);
    }
    // Legal by content: a flag or destroy with NO sole-copy address in the file (the rehearsal sub-root teardown, a web-2 replace);
    // the address with NO verb; a comment-only mention (`#`, and `//` for ts/mjs).
    expect(g2ScriptHits("r.sh", `cd apps/web-platform/infra/rehearsal && terraform destroy -auto-approve -target=hcloud_server.web2`)).toEqual([]);
    expect(g2ScriptHits("r.sh", `echo ${VOL}`)).toEqual([]);
    expect(g2ScriptHits("r.ts", `// terraform apply -replace=${VOL}\nconsole.log(1)`)).toEqual([]);
    expect(g2ScriptHits("r.sh", `# terraform destroy ${VOL}`)).toEqual([]);
    // Population filter: a symlink, a test file and a fixture are out; a real file is in; a path outside the directory classes is out.
    const root = mkdtempSync(join(tmpdir(), "g2-pop-"));
    try {
      const mk = (rel: string, body = "x") => {
        const abs = join(root, rel);
        spawnSync("mkdir", ["-p", join(abs, "..")]);
        writeFileSync(abs, body);
      };
      mk("scripts/real.sh");
      mk("scripts/real.test.sh");
      mk("scripts/test/helper.sh");
      mk("scripts/fixtures/f.sh");
      mk("scripts/target.sh");
      mk("docs/other.sh");
      spawnSync("ln", ["-s", join(root, "scripts/real.sh"), join(root, "scripts/link.sh")]);
      const all = ["scripts/real.sh", "scripts/real.test.sh", "scripts/test/helper.sh", "scripts/fixtures/f.sh", "scripts/link.sh", "scripts/gone.sh", "docs/other.sh", "scripts/data.json"];
      expect(g2ScanPopulation(all, root)).toEqual(["scripts/real.sh"]);
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  }, 60_000);

  test("G2: harness - superset/subset constants are RED; a comment/continuation/quote-rewritten copy still equals the set", () => {
    const live = g2LiveWorkflows();
    // SUITE edit: a superset constant (one extra triple) and a subset constant (one triple dropped) both turn the live tree RED.
    expect(g2Verdict(live, [...SOLE_COPY_EXPECTED, `${G2_WORKFLOW}|inngest_host_replace|target|hcloud_volume.inngest_redis_luks`]).length).toBeGreaterThan(0);
    expect(g2Verdict(live, SOLE_COPY_EXPECTED.slice(1)).join("\n")).toMatch(/unexpected: /);
    // Superset constant naming a job that does not exist: the non-vacuity check, not the diff, catches it.
    expect(g2Verdict(live, [...SOLE_COPY_EXPECTED, `${G2_WORKFLOW}|no_such_job|target|doppler_project.inngest`]).join("\n")).toMatch(/job-not-found: .*no_such_job/);
    // Must-PASS: rewrite every sole-copy -target (`=` -> space, re-quoted, folded onto a continuation) and add whole-line
    // comments that would be hits if they were code. The census must still equal the expected set.
    let n = 0;
    const flagRe = new RegExp(`^(\\s*)-target=(['"]?)(${G2_ADDR_ALT})\\2 \\\\$`, "gm");
    let rewritten = wf.replace(flagRe, (_m, ind: string, _q: string, addr: string) => {
      const quote = ["", "'", '"'][n++ % 3];
      return `${ind}# -replace=${addr} \\\n${ind}-target \\\n${ind}  ${quote}${addr}${quote} \\`;
    });
    expect(n).toBe(7);
    expect(rewritten).not.toBe(wf);
    expect(g2Verdict({ ...live, [G2_WORKFLOW]: rewritten })).toEqual([]);
    // The rewrite is real: the original spelling no longer appears for any sole-copy address.
    expect(new RegExp(`-target=['"]?(${G2_ADDR_ALT})\\b`).test(rewritten)).toBe(false);
    // Control for the same rewrite: add a real flag to it and it goes RED, so GREEN above is not a blind scan.
    expect(g2Verdict({ ...live, [G2_WORKFLOW]: rewritten + `\n      - run: terraform apply -replace=hcloud_volume.inngest_redis_luks\n` }).length).toBeGreaterThan(0);
  }, 60_000);
});

// --- G2e attribute pin (#9879): the INDEPENDENT anchor for the Guard 1 suite, in a REQUIRED check ---------------------------
// Guard 1 (apps/web-platform/infra/inngest-luks-sole-copy.test.sh) runs in infra-validation.yml, which is NOT a required check,
// so one diff could weaken the pins and the guard that pins them together and merge green. This file runs in the required `test`
// check (ADR-282), so the same attributes are asserted here on EFFECTIVE text (comments removed), with a lexer of its own: a
// defect shared by both lexers would have to be written twice, in two languages, in one reviewed diff.
// Fail closed: a block that cannot be found, is found twice, or reads as zero attributes is RED, never "zero checks, green".
// SUNSET: fold G2e into Guard 1 when Guard 1 becomes a required check (#9927). Until then G2e must not become a superset of it:
// it holds what one diff must not weaken (delete_protection, prevent_destroy, no ignore_changes, no depth-0 count/for_each/provider/
// provisioner, the attachment unpinned), over exactly the six addresses G2 and census G4h name (tied below).

/**
 * HCL with comments removed: whole-line and trailing `#` and `//`, and `/* ... *\/` (newlines kept). Strings are copied whole (a
 * string never spans a line, so a stray quote cannot blind the rest of the file). A heredoc opener is recognised ONLY in code, so a
 * trailing comment such as `# see <<EOF` is consumed as a comment first and starts nothing; a real heredoc body is blanked
 * (`blank`) or kept verbatim (`keep`, for a reader that needs the SQL).
 */
function g2eStrip(text: string, heredoc: "blank" | "keep" = "blank"): string {
  const t = text.replace(/\r\n/g, "\n");
  const n = t.length;
  let out = "";
  let i = 0;
  while (i < n) {
    const c = t[i];
    const c2 = t[i + 1];
    if (c === '"') {
      let j = i + 1;
      while (j < n && t[j] !== '"' && t[j] !== "\n") j += t[j] === "\\" ? 2 : 1;
      const end = j < n && t[j] === '"' ? j + 1 : Math.min(j, n);
      out += t.slice(i, end);
      i = end;
      continue;
    }
    if (c === "#" || (c === "/" && c2 === "/")) {
      while (i < n && t[i] !== "\n") i++;
      continue;
    }
    if (c === "/" && c2 === "*") {
      const e = t.indexOf("*/", i + 2);
      const end = e < 0 ? n : e + 2;
      out += t.slice(i, end).replace(/[^\n]/g, "");
      i = end;
      continue;
    }
    if (c === "<" && c2 === "<") {
      const m = /^<<-?([A-Za-z_][A-Za-z0-9_]*)[ \t]*(?=\n)/.exec(t.slice(i, i + 80));
      if (m) {
        const term = new RegExp(`\\n[ \\t]*${m[1]}[ \\t]*(?=\\n|$)`, "g");
        term.lastIndex = i + m[0].length;
        const tm = term.exec(t);
        const end = tm ? tm.index + tm[0].length : n;
        out += heredoc === "keep" ? t.slice(i, end) : `""${"\n".repeat((t.slice(i, end).match(/\n/g) ?? []).length)}`;
        i = end;
        continue;
      }
    }
    out += c;
    i++;
  }
  return out;
}

/** Index just past the `}` that closes the block whose `{` is at `open`, skipping strings; -1 if it never closes. */
function g2eClose(s: string, open: number): number {
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    const c = s[i];
    if (c === '"') {
      let j = i + 1;
      while (j < s.length && s[j] !== '"' && s[j] !== "\n") j += s[j] === "\\" ? 2 : 1;
      i = j;
      continue;
    }
    if (c === "{") depth++;
    else if (c === "}" && --depth === 0) return i + 1;
  }
  return -1;
}

/** The body of the single `resource "type" "name" { ... }` in comment-stripped HCL, or a defect string. */
function g2eResource(stripped: string, type: string, name: string): { body: string } | { defect: string } {
  const re = new RegExp(`(?:^|\\n)[ \\t]*resource[ \\t]+"${type}"[ \\t]+"${name}"[ \\t]*\\{`, "g");
  const ms = [...stripped.matchAll(re)];
  if (ms.length === 0) return { defect: "missing" };
  if (ms.length > 1) return { defect: "duplicate" };
  const open = ms[0].index! + ms[0][0].length - 1;
  const close = g2eClose(stripped, open);
  return close < 0 ? { defect: "unterminated" } : { body: stripped.slice(open + 1, close - 1) };
}

/** A block body split into its depth-0 text (nested braces emptied, so a nested attribute cannot pass for a top-level one) and its nested blocks. */
function g2eSplit(body: string): { top: string; nested: Array<{ name: string; body: string }> } | null {
  let top = "";
  const nested: Array<{ name: string; body: string }> = [];
  let depth = 0;
  let from = 0;
  let nm = "";
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === '"') {
      let j = i + 1;
      while (j < body.length && body[j] !== '"' && body[j] !== "\n") j += body[j] === "\\" ? 2 : 1;
      if (depth === 0) top += body.slice(i, j + 1);
      i = j;
      continue;
    }
    if (c === "{") {
      if (depth === 0) {
        nm = /([A-Za-z_][\w-]*)[ \t]*$/.exec(body.slice(Math.max(0, i - 128), i))?.[1] ?? ""; // `labels = {` ends in `=`, so a map literal has no block name; a 128-char tail of the FLAT body (not of the growing `top` rope) keeps the scan linear
        from = i + 1;
      }
      depth++;
    } else if (c === "}") {
      if (--depth < 0) return null;
      if (depth === 0) {
        nested.push({ name: nm, body: body.slice(from, i) });
        top += "{}";
      }
    } else if (depth === 0) top += c;
  }
  return depth === 0 ? { top, nested } : null;
}

/** Values of every depth-0 `key = value` line in `top`. */
const g2eAttr = (top: string, key: string): string[] =>
  [...top.matchAll(new RegExp(`^[ \\t]*${key}[ \\t]*=[ \\t]*(.*)$`, "gm"))].map((m) => m[1].trim()); // greedy then trim: a lazy `(.*?)[ \t]*$` is quadratic on a long whitespace run

const G2E_META = ["count", "for_each", "provider"] as const;
interface G2ePin {
  file: "luks" | "host";
  type: string;
  name: string;
  /** "lifecycle": exactly one lifecycle block carrying `prevent_destroy = true`. "none": no lifecycle block and no prevent_destroy at all. */
  protect: "lifecycle" | "none";
  deleteProtection?: true;
}
const G2E_PINS: readonly G2ePin[] = [
  { file: "luks", type: "hcloud_volume", name: "inngest_redis_luks", protect: "lifecycle", deleteProtection: true },
  { file: "luks", type: "random_password", name: "inngest_redis_luks", protect: "lifecycle" },
  { file: "luks", type: "doppler_secret", name: "inngest_redis_luks_key", protect: "lifecycle" },
  { file: "host", type: "doppler_project", name: "inngest", protect: "lifecycle" },
  { file: "host", type: "doppler_environment", name: "inngest_prd", protect: "lifecycle" },
  { file: "luks", type: "hcloud_volume_attachment", name: "inngest_redis_luks", protect: "none" },
];

/** Defects (empty = GREEN) and the number of positive checks evaluated (a pass with zero checks is not a pass). */
function g2eVerdict(src: { luks: string; host: string }, pins: readonly G2ePin[] = G2E_PINS): { defects: string[]; checks: number } {
  const defects: string[] = [];
  let checks = 0;
  const stripped = { luks: g2eStrip(src.luks), host: g2eStrip(src.host) };
  for (const pin of pins) {
    const addr = `${pin.type}.${pin.name}`;
    const r = g2eResource(stripped[pin.file], pin.type, pin.name);
    if ("defect" in r) {
      defects.push(`${addr}: ${r.defect} in ${pin.file === "luks" ? "inngest-redis-luks.tf" : "inngest-host.tf"}`);
      continue;
    }
    checks++;
    const split = g2eSplit(r.body);
    if (!split) {
      defects.push(`${addr}: unbalanced braces`);
      continue;
    }
    if (!/^[ \t]*[A-Za-z_]\w*[ \t]*=/m.test(split.top)) {
      defects.push(`${addr}: extractor read zero attributes`);
      continue;
    }
    checks++;
    // Depth-0 meta-arguments rewrite WHAT the block is (count = 0 removes it from state without a destroy plan, for_each/provider
    // move it to another instance or provider, a provisioner runs code on it). A nested `count` word (a labels map) is not depth 0.
    const meta = [...G2E_META.filter((k) => g2eAttr(split.top, k).length > 0), ...(/^[ \t]*provisioner\b/m.test(split.top) ? ["provisioner"] : [])];
    if (meta.length > 0) defects.push(`${addr}: depth-0 meta-argument ${meta.join(", ")} (the sole-copy block must be one plain instance)`);
    else checks++;
    if (pin.deleteProtection) {
      const dp = g2eAttr(split.top, "delete_protection");
      if (dp.length !== 1 || dp[0] !== "true") defects.push(`${addr}: delete_protection is not exactly one code line \`= true\` (found ${JSON.stringify(dp)})`);
      else checks++;
    }
    const lifecycles = split.nested.filter((b) => b.name === "lifecycle");
    if (pin.protect === "lifecycle") {
      const inner = lifecycles.length === 1 ? g2eSplit(lifecycles[0].body) : null;
      const pd = inner ? g2eAttr(inner.top, "prevent_destroy") : [];
      if (pd.length !== 1 || pd[0] !== "true") defects.push(`${addr}: no lifecycle block with exactly one \`prevent_destroy = true\` code line (lifecycle blocks: ${lifecycles.length}, prevent_destroy: ${JSON.stringify(pd)})`);
      else checks++;
      // ignore_changes stops Terraform delivering or re-asserting an attribute (delete_protection) and hides an out-of-band lift from the plan.
      if (/\bignore_changes\b/.test(lifecycles.map((b) => b.body.replace(/"[^"\n]*"/g, '""')).join("\n"))) defects.push(`${addr}: lifecycle carries ignore_changes (the pinned attributes must stay managed)`);
      else checks++;
    } else if (lifecycles.length > 0 || /\bprevent_destroy\b/.test(r.body)) {
      defects.push(`${addr}: carries a lifecycle block / prevent_destroy (a sanctioned host replace would become a plan error)`);
    } else checks++;
  }
  return { defects, checks };
}

/** Rewrite the single column-0 `resource "type" "name" { ... }` block of RAW text (closing brace at column 0, as terraform fmt writes it). */
function g2eMutate(text: string, type: string, name: string, fn: (block: string) => string): string {
  const m = new RegExp(`^resource "${type}" "${name}" \\{\\n[\\s\\S]*?\\n\\}$`, "m").exec(text);
  if (!m) throw new Error(`g2eMutate: ${type}.${name} not found`);
  const out = text.slice(0, m.index) + fn(m[0]) + text.slice(m.index + m[0].length);
  if (out === text) throw new Error(`g2eMutate: no-op on ${type}.${name}`);
  return out;
}

// The alert edge (ADR-282, F1): the volume is NOT a per-merge `-target`. An in-place update of it (delete_protection) reaches the
// per-merge plan only as a DEPENDENCY of `logtail_exploration.inngest_luks_wrong_volume`, through the alias local that interpolates
// `hcloud_volume.inngest_redis_luks.id`. Remove the exploration from the list, or stop the alias reading the volume, and the
// in-place update stops being applied by any merge; the chain below is what keeps that edge from being cut silently.
const G2E_EDGE_TARGETS = ["logtail_exploration.inngest_luks_wrong_volume", "logtail_exploration_alert.inngest_luks_wrong_volume"];
function g2eEdgeVerdict(wfText: string, alertsTf: string): string[] {
  const defects: string[] = [];
  const applyTargets = extractAllTargets(extractJobBlock(wfText, "apply"));
  if (applyTargets.size < 50) defects.push(`apply job extracted ${applyTargets.size} targets (job not found?)`);
  for (const a of G2E_EDGE_TARGETS) if (!applyTargets.has(a)) defects.push(`${a} is not in the per-merge apply job's -target list`);
  const code = g2eStrip(alertsTf, "keep");
  if (!/^[ \t]*inngest_luks_wrong_volume_alias[ \t]*=[ \t]*"[^"\n]*\$\{[ \t]*hcloud_volume\.inngest_redis_luks\.id[ \t]*\}[^"\n]*"[ \t]*$/m.test(code)) {
    defects.push("local.inngest_luks_wrong_volume_alias does not interpolate hcloud_volume.inngest_redis_luks.id");
  }
  if (!/^[ \t]*inngest_luks_wrong_volume_sql[ \t]*=[ \t]*<<-?SQL[ \t]*\n[\s\S]*?\$\{[ \t]*local\.inngest_luks_wrong_volume_alias[ \t]*\}[\s\S]*?\n[ \t]*SQL[ \t]*$/m.test(code)) {
    defects.push("local.inngest_luks_wrong_volume_sql does not interpolate local.inngest_luks_wrong_volume_alias");
  }
  const ex = g2eResource(g2eStrip(alertsTf), "logtail_exploration", "inngest_luks_wrong_volume");
  if ("defect" in ex) defects.push(`logtail_exploration.inngest_luks_wrong_volume: ${ex.defect}`);
  else if (!/^[ \t]*sql_query[ \t]*=.*\blocal\.inngest_luks_wrong_volume_sql\b/m.test(ex.body)) {
    defects.push("logtail_exploration.inngest_luks_wrong_volume.sql_query does not read local.inngest_luks_wrong_volume_sql");
  }
  return defects;
}

describe("G2e attribute pin (#9879): the sole-copy attributes on EFFECTIVE text, in a required check (ADR-282)", () => {
  const read = (f: string): string => readFileSync(resolve(INFRA_DIR, f), "utf8");
  const live = { luks: read("inngest-redis-luks.tf"), host: read("inngest-host.tf") };
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const alertsTf = read("betterstack-logs-alerts.tf");
  // volume 6 (found, attributes read, meta-arguments, delete_protection, prevent_destroy, no ignore_changes) + four protected blocks x 5
  // + attachment 4 (found, attributes read, meta-arguments, no lifecycle)
  const LIVE_CHECKS = 30;

  /** Insert `line` as a depth-0 attribute right after the opening line of a block. */
  const addTop = (b: string, line: string): string => b.replace("{\n", `{\n  ${line}\n`);
  /** Insert `line` inside the block's lifecycle, right after its opening line. */
  const addToLifecycle = (b: string, line: string): string => b.replace(/^([ \t]*)lifecycle \{\n/m, `$&$1  ${line}\n`);
  const rmPD = (b: string): string => b.replace(/^[ \t]*prevent_destroy[ \t]*=[ \t]*true[ \t]*\n/m, "");
  const withLuks = (t: string) => ({ ...live, luks: t });
  const withHost = (t: string) => ({ ...live, host: t });
  const VOL: [string, string] = ["hcloud_volume", "inngest_redis_luks"];
  const PW: [string, string] = ["random_password", "inngest_redis_luks"];
  const KEY: [string, string] = ["doppler_secret", "inngest_redis_luks_key"];
  const ATT: [string, string] = ["hcloud_volume_attachment", "inngest_redis_luks"];
  const PROJ: [string, string] = ["doppler_project", "inngest"];
  const ENV: [string, string] = ["doppler_environment", "inngest_prd"];

  test("G2e: live tree - all six blocks are found, read as non-empty, and carry exactly the pinned attributes", () => {
    expect(G2E_PINS.length).toBe(6);
    // Tie: the pinned set IS the G2 sole-copy address set and the inngest half of census G4H_EXPECTED, so a seventh address added to
    // either side without a pin here is RED (it would otherwise get no attribute pin in the required check).
    expect(G2E_PINS.map((p) => `${p.type}.${p.name}`).sort()).toEqual([...SOLE_COPY_ADDRS].sort());
    const census = readFileSync(resolve(REPO_ROOT, "tests/scripts/test-infra-privileged-tier-census.sh"), "utf8");
    const g4h = [...(/G4H_EXPECTED = frozenset\(\{([^}]*)\}\)/.exec(census)?.[1] ?? "").matchAll(/"([a-z_]+\.[a-z_]+)"/g)].map((m) => m[1]);
    expect(g4h.length, "G4H_EXPECTED is not found, not parsed or not the eight addresses (six inngest + two workspaces_luks) in the census suite").toBe(8); // six inngest + the two workspaces_luks entries
    expect(g4h.filter((a) => !a.endsWith(".workspaces_luks")).sort()).toEqual([...SOLE_COPY_ADDRS].sort());
    const v = g2eVerdict(live);
    expect(v.defects).toEqual([]);
    expect(v.checks).toBe(LIVE_CHECKS); // a verdict that evaluated nothing is not GREEN
    // Non-vacuity of the extractor itself: it reads the volume's real attributes, not an empty body.
    const vol = g2eResource(g2eStrip(live.luks), "hcloud_volume", "inngest_redis_luks");
    expect("body" in vol && g2eAttr(g2eSplit(vol.body)!.top, "location")).toEqual(["var.location"]);
    // Comment prose that spells the attributes is not code: the file's own header says `prevent_destroy` many times.
    expect(live.luks.match(/prevent_destroy/g)!.length).toBeGreaterThan(4);
    expect(g2eStrip(live.luks).match(/^[ \t]*prevent_destroy[ \t]*=[ \t]*true[ \t]*$/gm)!.length).toBe(3); // volume, password, secret (the project and environment live in inngest-host.tf)
    expect(g2eStrip(live.luks).match(/^[ \t]*delete_protection[ \t]*=/gm)!.length).toBe(1);
  });

  test("G2e: mutation matrix - each weakening turns the verdict RED for the right reason (in-memory copies only)", () => {
    const sub = (type: string, name: string, fn: (b: string) => string, file: "luks" | "host" = "luks") =>
      file === "luks" ? withLuks(g2eMutate(live.luks, type, name, fn)) : withHost(g2eMutate(live.host, type, name, fn));
    const rows: Array<[string, { luks: string; host: string }, RegExp]> = [
      ["flip delete_protection to false", sub(...VOL, (b) => b.replace(/delete_protection = true/, "delete_protection = false")), /hcloud_volume\.inngest_redis_luks: delete_protection/],
      ["delete the delete_protection line", sub(...VOL, (b) => b.replace(/^[ \t]*delete_protection[ \t]*=.*\n/m, "")), /hcloud_volume\.inngest_redis_luks: delete_protection/],
      ["comment the delete_protection line out", sub(...VOL, (b) => b.replace(/^([ \t]*)delete_protection/m, "$1# delete_protection")), /hcloud_volume\.inngest_redis_luks: delete_protection/],
      ["delete_protection moved into a nested map", sub(...VOL, (b) => b.replace(/^[ \t]*delete_protection[ \t]*=.*\n/m, "").replace(/app = /, "delete_protection = true\n    app = ")), /hcloud_volume\.inngest_redis_luks: delete_protection/],
      ["delete prevent_destroy: volume", sub(...VOL, rmPD), /hcloud_volume\.inngest_redis_luks: no lifecycle block/],
      ["delete prevent_destroy: random_password", sub(...PW, rmPD), /random_password\.inngest_redis_luks: no lifecycle block/],
      ["delete prevent_destroy: doppler_secret", sub(...KEY, rmPD), /doppler_secret\.inngest_redis_luks_key: no lifecycle block/],
      ["delete prevent_destroy: doppler_project", sub(...PROJ, rmPD, "host"), /doppler_project\.inngest: no lifecycle block/],
      ["delete prevent_destroy: doppler_environment", sub(...ENV, rmPD, "host"), /doppler_environment\.inngest_prd: no lifecycle block/],
      ["prevent_destroy = false", sub(...VOL, (b) => b.replace(/prevent_destroy = true/, "prevent_destroy = false")), /hcloud_volume\.inngest_redis_luks: no lifecycle block/],
      ["prevent_destroy only in a comment", sub(...PW, (b) => b.replace(/^([ \t]*)prevent_destroy/m, "$1# prevent_destroy")), /random_password\.inngest_redis_luks: no lifecycle block/],
      ["prevent_destroy only behind //", sub(...PW, (b) => b.replace(/^([ \t]*)prevent_destroy/m, "$1// prevent_destroy")), /random_password\.inngest_redis_luks: no lifecycle block/],
      ["prevent_destroy inside a /* */ comment", sub(...KEY, (b) => b.replace(/^([ \t]*)prevent_destroy = true/m, "$1/* prevent_destroy = true */")), /doppler_secret\.inngest_redis_luks_key: no lifecycle block/],
      ["the whole lifecycle wrapped in /* */", sub(...VOL, (b) => b.replace(/lifecycle \{\n[ \t]*prevent_destroy = true\n[ \t]*\}/, (m) => `/* ${m} */`)), /hcloud_volume\.inngest_redis_luks: no lifecycle block/],
      ["prevent_destroy moved into a nested map (not a lifecycle)", sub(...PW, (b) => b.replace(/lifecycle \{/, "tags = {")), /random_password\.inngest_redis_luks: no lifecycle block/],
      ["add a lifecycle with prevent_destroy to the ATTACHMENT", sub(...ATT, (b) => b.replace(/\n\}$/, "\n\n  lifecycle {\n    prevent_destroy = true\n  }\n}")), /hcloud_volume_attachment\.inngest_redis_luks: carries a lifecycle/],
      ["add any lifecycle block to the ATTACHMENT", sub(...ATT, (b) => b.replace(/\n\}$/, "\n\n  lifecycle {\n    ignore_changes = []\n  }\n}")), /hcloud_volume_attachment\.inngest_redis_luks: carries a lifecycle/],
      ["rename the volume (extractor must not read zero attributes and pass)", sub(...VOL, (b) => b.replace(/^resource "hcloud_volume" "inngest_redis_luks"/, 'resource "hcloud_volume" "inngest_redis_luks_renamed"')), /hcloud_volume\.inngest_redis_luks: missing/],
      ["rename the project", sub(...PROJ, (b) => b.replace('"inngest" {', '"inngest_renamed" {'), "host"), /doppler_project\.inngest: missing/],
      ["rename the attachment", sub(...ATT, (b) => b.replace('"inngest_redis_luks" {', '"inngest_redis_luks_x" {')), /hcloud_volume_attachment\.inngest_redis_luks: missing/],
      ["a second copy of the volume block", withLuks(live.luks + "\n" + /^resource "hcloud_volume" "inngest_redis_luks" \{\n[\s\S]*?\n\}$/m.exec(live.luks)![0] + "\n"), /hcloud_volume\.inngest_redis_luks: duplicate/],
      ["an unterminated /* before everything blinds the file: RED, not zero checks", withLuks("/* oops\n" + live.luks), /missing/],
      ["an empty body (attributes read as zero)", sub(...PW, () => 'resource "random_password" "inngest_redis_luks" {\n}'), /random_password\.inngest_redis_luks: extractor read zero attributes/],
      ["`# see <<EOF` before the lifecycle, prevent_destroy removed", sub(...VOL, (b) => rmPD(b.replace(/\n[ \t]*lifecycle \{/, "\n  # see <<EOF\n  lifecycle {"))), /hcloud_volume\.inngest_redis_luks: no lifecycle block/],
      ["`// see <<-EOT` trailing, the lifecycle commented out", sub(...KEY, (b) => b.replace(/\n([ \t]*)lifecycle \{\n[ \t]*prevent_destroy = true\n[ \t]*\}/, "\n  # x // see <<-EOT\n/*\n$1lifecycle {\n    prevent_destroy = true\n  }\n*/")), /doppler_secret\.inngest_redis_luks_key: no lifecycle block/],
      ["trailing `# see <<EOF` on an attribute, then prevent_destroy removed", sub(...PW, (b) => rmPD(b.replace(/^(  length .*)$/m, "$1 # see <<EOF"))), /random_password\.inngest_redis_luks: no lifecycle block/],
      // ignore_changes beside prevent_destroy: Terraform stops delivering / re-asserting the attribute (and hides an out-of-band lift)
      ["ignore_changes = [delete_protection] in the volume lifecycle", sub(...VOL, (b) => addToLifecycle(b, "ignore_changes = [delete_protection]")), /hcloud_volume\.inngest_redis_luks: lifecycle carries ignore_changes/],
      ["ignore_changes = all in the passphrase lifecycle", sub(...PW, (b) => addToLifecycle(b, "ignore_changes = all")), /random_password\.inngest_redis_luks: lifecycle carries ignore_changes/],
      ["ignore_changes in the secret lifecycle", sub(...KEY, (b) => addToLifecycle(b, "ignore_changes = [value]")), /doppler_secret\.inngest_redis_luks_key: lifecycle carries ignore_changes/],
      ["ignore_changes in the project lifecycle", sub(...PROJ, (b) => addToLifecycle(b, "ignore_changes = [description]"), "host"), /doppler_project\.inngest: lifecycle carries ignore_changes/],
      ["ignore_changes in the environment lifecycle", sub(...ENV, (b) => addToLifecycle(b, "ignore_changes = [name]"), "host"), /doppler_environment\.inngest_prd: lifecycle carries ignore_changes/],
      // depth-0 meta-arguments, one row per argument and per block family (volume, passphrase pair, the host pair, the attachment)
      ["count = 0 on the volume", sub(...VOL, (b) => addTop(b, "count = 0")), /hcloud_volume\.inngest_redis_luks: depth-0 meta-argument count/],
      ["count = 0 on the passphrase", sub(...PW, (b) => addTop(b, "count = 0")), /random_password\.inngest_redis_luks: depth-0 meta-argument count/],
      ["count = 0 on the secret", sub(...KEY, (b) => addTop(b, "count = var.on ? 1 : 0")), /doppler_secret\.inngest_redis_luks_key: depth-0 meta-argument count/],
      ["count = 0 on the project", sub(...PROJ, (b) => addTop(b, "count = 0"), "host"), /doppler_project\.inngest: depth-0 meta-argument count/],
      ["count = 0 on the environment", sub(...ENV, (b) => addTop(b, "count = 0"), "host"), /doppler_environment\.inngest_prd: depth-0 meta-argument count/],
      ["count = 0 on the attachment", sub(...ATT, (b) => addTop(b, "count = 0")), /hcloud_volume_attachment\.inngest_redis_luks: depth-0 meta-argument count/],
      ["for_each on the volume", sub(...VOL, (b) => addTop(b, 'for_each = toset(["a"])')), /hcloud_volume\.inngest_redis_luks: depth-0 meta-argument for_each/],
      ["for_each on the passphrase", sub(...PW, (b) => addTop(b, 'for_each = toset(["a"])')), /random_password\.inngest_redis_luks: depth-0 meta-argument for_each/],
      ["provider alias on the volume", sub(...VOL, (b) => addTop(b, "provider = hcloud.other")), /hcloud_volume\.inngest_redis_luks: depth-0 meta-argument provider/],
      ["provider alias on the secret", sub(...KEY, (b) => addTop(b, "provider = doppler.other")), /doppler_secret\.inngest_redis_luks_key: depth-0 meta-argument provider/],
      ["provisioner on the volume", sub(...VOL, (b) => addTop(b, 'provisioner "local-exec" {\n    command = "true"\n  }')), /hcloud_volume\.inngest_redis_luks: depth-0 meta-argument provisioner/],
      ["provisioner on the passphrase", sub(...PW, (b) => addTop(b, 'provisioner "local-exec" {\n    command = "true"\n  }')), /random_password\.inngest_redis_luks: depth-0 meta-argument provisioner/],
      // lexer: a brace the lexer must NOT count. The passphrase block's `# {` would run it into the secret block in a lexer that
      // counts trailing-comment braces, and the secret's `prevent_destroy = true` would then stand in for the passphrase's own.
      ["brace in a trailing comment runs the passphrase block into the secret block", withLuks(g2eMutate(g2eMutate(live.luks, ...PW, (b) => b.replace(/^(  length .*)$/m, "$1 # {").replace(/prevent_destroy = true/, "create_before_destroy = false")), ...KEY, (b) => b.replace(/\n\}$/, "\n} # }"))), /random_password\.inngest_redis_luks: no lifecycle block/],
      // lexer: a heredoc body is data. A fake `lifecycle { prevent_destroy = true }` in `format = <<-EOT` must not satisfy the pin.
      ["a fake lifecycle inside a heredoc stands in for the real one", sub(...VOL, (b) => b.replace(/\n[ \t]*lifecycle \{\n[ \t]*prevent_destroy = true\n[ \t]*\}/, '\n  format = <<-EOT\n  lifecycle {\n    prevent_destroy = true\n  }\n  EOT')), /hcloud_volume\.inngest_redis_luks: no lifecycle block with exactly one `prevent_destroy = true` code line \(lifecycle blocks: 0/],
    ];
    expect(g2eVerdict(live).defects).toEqual([]); // control: the live tree is GREEN, so a RED below is the mutation's doing
    for (const [name, files, want] of rows) {
      const v = g2eVerdict(files);
      expect(v.defects.length, `row "${name}" stayed GREEN`).toBeGreaterThan(0);
      expect(v.defects.join("\n"), `row "${name}" was RED for the wrong reason`).toMatch(want);
    }
  });

  test("G2e: the comment stripper is not blinded - benign comments, heredoc-shaped comments and real heredocs stay GREEN with every check evaluated", () => {
    const sub = (type: string, name: string, fn: (b: string) => string) => withLuks(g2eMutate(live.luks, type, name, fn));
    const rows: Array<[string, { luks: string; host: string }]> = [
      ["`# see <<EOF` on its own line before the lifecycle", sub(...VOL, (b) => b.replace(/\n[ \t]*lifecycle \{/, "\n  # see <<EOF\n  lifecycle {"))],
      ["`# see <<EOF` trailing on the lifecycle opener", sub(...VOL, (b) => b.replace(/lifecycle \{/, "lifecycle { # see <<EOF"))],
      ["`// see <<-EOT` trailing on an attribute", sub(...VOL, (b) => b.replace(/^(  size .*)$/m, "$1 // see <<-EOT"))],
      ["`/* <<EOF */` inline", sub(...VOL, (b) => b.replace(/lifecycle \{/, "/* <<EOF */ lifecycle {"))],
      ["trailing comments on the two pinned attributes", sub(...VOL, (b) => b.replace(/delete_protection = true/, "delete_protection = true # x").replace(/prevent_destroy = true/, "prevent_destroy = true // y"))],
      ["a real heredoc holding a lone quote, braces and a comment opener, ahead of the blocks", withLuks("locals {\n  x = <<-EOT\n    it's a \" quote } { /* #\n  EOT\n}\n" + live.luks)],
      ["a /* */ comment spanning lines that spells the protected blocks", withLuks("/*\nresource \"hcloud_volume\" \"inngest_redis_luks\" {\n  delete_protection = false\n}\n*/\n" + live.luks)],
      // meta-argument words that are NOT depth-0 attributes: a nested map, a comment, a heredoc body, a string (must not trip the new check)
      ["count/for_each/provider words inside the labels map", sub(...VOL, (b) => b.replace(/app = /, "count = 1\n    for_each = 2\n    provider = x\n    provisioner = y\n    app = "))],
      ["count/provider spelled in comments", sub(...VOL, (b) => b.replace(/^(  size .*)$/m, "  # count = 0\n  // provider = x\n  /* for_each = {} */\n$1 # provisioner \"x\" {"))],
      ["count/provider/ignore_changes inside a heredoc body", sub(...VOL, (b) => addTop(b, "x_note = <<-EOT\n  count = 0\n  provider = x\n  lifecycle {\n    ignore_changes = all\n  }\n  EOT"))],
      ["a brace in a trailing comment", sub(...PW, (b) => b.replace(/^(  length .*)$/m, "$1 # {{").replace(/special = false/, "special = false # }"))],
      ["a lone `}` inside a string (each lexer must skip strings on its own)", sub(...PW, (b) => addTop(b, 'keepers = { a = "}" }'))],
      ["a lone `{` inside a string", sub(...PW, (b) => addTop(b, 'keepers = { a = "{" }'))],
      ["ignore_changes spelled only in a comment of the lifecycle", sub(...VOL, (b) => addToLifecycle(b, "# ignore_changes = [delete_protection]"))],
    ];
    for (const [name, files] of rows) {
      const v = g2eVerdict(files);
      expect(v.defects, `row "${name}" must stay GREEN`).toEqual([]);
      expect(v.checks, `row "${name}" evaluated fewer checks`).toBe(LIVE_CHECKS);
    }
    // The heredoc opener in a comment starts nothing; in code it does, and its body is blanked/kept as asked.
    expect(g2eStrip("a = 1 # see <<EOF\nb = 2\n")).toBe("a = 1 \nb = 2\n");
    expect(g2eStrip('x = <<-SQL\n  y # z\nSQL\nb = 2\n')).toContain("b = 2");
    expect(g2eStrip('x = <<-SQL\n  y # z\nSQL\nb = 2\n')).not.toContain("y # z");
    expect(g2eStrip('x = <<-SQL\n  y # z\nSQL\nb = 2\n', "keep")).toContain("y # z");
  });

  test("G2e: the lexer and attribute scanners are linear - long word, whitespace and sibling-block runs finish in under 2s", () => {
    const hostile: Array<[string, () => unknown, unknown]> = [
      ["g2eSplit: a 100 KB word run then `={`", () => g2eSplit("a".repeat(100_000) + "={\n  x = 1\n}\n")?.nested.length, 1],
      ["g2eSplit: 20000 sibling blocks", () => g2eSplit("blk {\n  x = 1\n}\n".repeat(20_000))?.nested.length, 20_000],
      ["g2eSplit: 100 KB of `a-` words then a block", () => g2eSplit("a-".repeat(50_000) + " {\n}\n")?.nested.length, 1],
      ["g2eAttr: a 100 KB whitespace run inside a value", () => g2eAttr("key = x" + " ".repeat(100_000) + "y\n", "key"), ["x" + " ".repeat(100_000) + "y"]],
      ["g2eAttr: a 100 KB whitespace run after a value", () => g2eAttr("key = x" + " ".repeat(100_000) + "\n", "key"), ["x"]],
      ["g2eAttr: 20000 near-miss lines", () => g2eAttr("  keyx = 1\n".repeat(20_000), "key"), []],
      ["g2eStrip: 30000 unterminated heredoc openers", () => g2eStrip("<<-A\n".repeat(30_000)).length > 0, true],
      ["g2eStrip: 100000 quotes", () => g2eStrip('"'.repeat(100_000)).length, 100_000],
      ["g2eResource: a 100 KB run of braces", () => "defect" in g2eResource('resource "a" "b" {' + "{".repeat(100_000), "a", "b"), true],
    ];
    for (const [name, run, want] of hostile) {
      const t0 = performance.now();
      const got = run();
      const ms = performance.now() - t0;
      expect(ms, `${name}: ${ms.toFixed(0)} ms`).toBeLessThan(2000);
      expect(got, `${name}: wrong result`).toEqual(want);
    }
  });

  test("G2e: the per-merge edge to the volume - alert in the apply job's -target list AND the alias local interpolates the volume id", () => {
    expect(g2eEdgeVerdict(wf, alertsTf)).toEqual([]);
    // Non-vacuity: the volume itself is NOT a per-merge -target (the edge is the only route), and the alias is the sole reader of its id here.
    expect(extractAllTargets(extractJobBlock(wf, "apply")).has("hcloud_volume.inngest_redis_luks")).toBe(false);
    expect(extractAllTargets(extractJobBlock(wf, "apply")).has("logtail_exploration.inngest_luks_wrong_volume")).toBe(true);
    expect(alertsTf).toContain("hcloud_volume.inngest_redis_luks.id");
    const dropTarget = (addr: string): string => {
      const out = wf.replace(new RegExp(`^[ \\t]*-target=${g2Esc(addr)} \\\\\\n`, "m"), "");
      expect(out).not.toBe(wf);
      return out;
    };
    const rows: Array<[string, string, string, RegExp]> = [
      ["the exploration removed from the per-merge list", dropTarget("logtail_exploration.inngest_luks_wrong_volume"), alertsTf, /logtail_exploration\.inngest_luks_wrong_volume is not in the per-merge apply job/],
      ["the alert removed from the per-merge list", dropTarget("logtail_exploration_alert.inngest_luks_wrong_volume"), alertsTf, /logtail_exploration_alert\.inngest_luks_wrong_volume is not in the per-merge apply job/],
      ["the alias no longer reads the volume", wf, alertsTf.replace(/^(  inngest_luks_wrong_volume_alias = .*)\$\{hcloud_volume\.inngest_redis_luks\.id\}/m, "$110626194"), /alias does not interpolate hcloud_volume\.inngest_redis_luks\.id/],
      ["the alias reads the volume only in a comment", wf, alertsTf.replace(/^(  inngest_luks_wrong_volume_alias = .*)$/m, "  # $1\n  inngest_luks_wrong_volume_alias = \"scsi-0HC_Volume_1\""), /alias does not interpolate/],
      ["the alias reads a sibling volume", wf, alertsTf.replace(/^(  inngest_luks_wrong_volume_alias = .*)hcloud_volume\.inngest_redis_luks\.id/m, "$1hcloud_volume.workspaces_luks.id"), /alias does not interpolate/],
      ["the sql local stops using the alias", wf, alertsTf.replace("${local.inngest_luks_wrong_volume_alias}", "x"), /sql does not interpolate local\.inngest_luks_wrong_volume_alias/],
      ["the exploration stops reading the sql local", wf, alertsTf.replace("trimspace(local.inngest_luks_wrong_volume_sql)", "trimspace(\"select 1\")"), /sql_query does not read local\.inngest_luks_wrong_volume_sql/],
      ["the exploration resource renamed", wf, alertsTf.replace('resource "logtail_exploration" "inngest_luks_wrong_volume"', 'resource "logtail_exploration" "inngest_luks_wrong_volume_x"'), /logtail_exploration\.inngest_luks_wrong_volume: missing/],
      ["the apply job not found (renamed)", wf.replace(/^ {2}apply:/m, "  apply_renamed:"), alertsTf, /apply job extracted 0 targets/],
    ];
    for (const [name, w, tf, want] of rows) {
      const defects = g2eEdgeVerdict(w, tf);
      expect(defects.length, `edge row "${name}" stayed GREEN`).toBeGreaterThan(0);
      expect(defects.join("\n"), `edge row "${name}" was RED for the wrong reason`).toMatch(want);
    }
  });
});

/**
 * ALLOW-SET <=> -target PARITY across all three registry dispatch jobs.
 *
 * The identical 6-address set now lives in SIX places (three gate libs + three job -target
 * lists) with nothing asserting they agree. A seventh registry resource would have to move in
 * lockstep across all six, and missing one surfaces only as a mysterious `out_of_scope > 0`
 * at dispatch time — against a prod apply the operator is waiting on.
 */
describe("registry gate allow-sets match their jobs' -target sets", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const PAIRS: Array<[string, string]> = [
    ["registry_host_replace", "registry-host-replace-gate.sh"],
    ["registry_region_migrate", "registry-region-migrate-gate.sh"],
    ["registry_luks_recut", "registry-luks-recut-gate.sh"],
  ];

  for (const [jobId, libFile] of PAIRS) {
    test(`${jobId} allow-set === its -target set`, () => {
      const lib = readFileSync(
        join(REPO_ROOT, "tests/scripts/lib", libFile),
        "utf8",
      );
      const defAllow = /def allow:\s*\[([\s\S]*?)\]/.exec(lib);
      expect(defAllow).not.toBeNull();
      const allow = [...defAllow![1].matchAll(/"([^"]+)"/g)]
        .map((m) => m[1])
        .sort();
      // Non-vacuity floor: the extraction must actually find addresses.
      expect(allow.length).toBeGreaterThan(0);
      const targets = [...extractAllTargets(extractJobBlock(wf, jobId))].sort();
      expect(targets).toEqual(allow);
    });
  }
});

/**
 * inngest_host SHAPE GATE (#6894, ADR-142 Guard 3): wired into the job, and its allow-set IS the
 * job's -target set.
 *
 * The gate's allow-set is a literal in the same repo as the workflow it grades, so one diff could
 * widen both — this is the outside anchor the plan's Guard Contract names, and it mirrors the
 * registry parity block above. The call assertion follows the "sources and CALLS" shape the
 * retired inngest-backstop-retire dispatch used: anchored on the `if !` call form over COMMENT-STRIPPED text, so a
 * `# shellcheck source=` directive or prose cannot satisfy it.
 */
describe("inngest_host dispatch: shape gate wired and allow-set === -target set (#6894)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const jobBlock = stripComments(extractJobBlock(wf, "inngest_host"));
  const CALL = /^\s*if ! inngest_host_shape_gate tfplan\.json; then$/m;

  test("sources and CALLS inngest_host_shape_gate, with no ack-destroy bypass", () => {
    expect(jobBlock).toContain("inputs.apply_target == 'inngest-host'"); // non-vacuity: the right job
    expect(jobBlock).toMatch(
      /^\s*source "\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/inngest-host-shape-gate\.sh"$/m,
    );
    expect(jobBlock).toMatch(CALL);
    expect([...jobBlock.matchAll(new RegExp(CALL.source, "gm"))].length).toBe(1);
    expect(jobBlock).toContain("NO [ack-destroy] bypass on this path.");
  });

  test("non-vacuity: the call check can tell a wired job from an unwired one", () => {
    const unwired = jobBlock.replace(CALL, "          if false; then");
    expect(CALL.test(unwired)).toBe(false);
  });

  test("the gate runs on the saved plan BEFORE the apply consumes it", () => {
    const callAt = jobBlock.search(CALL);
    const applyAt = jobBlock.indexOf("terraform apply -no-color -input=false tfplan");
    expect(callAt).toBeGreaterThan(-1);
    expect(applyAt).toBeGreaterThan(callAt);
  });

  test("the gate's def allow === the job's -target set", () => {
    const lib = readFileSync(
      join(REPO_ROOT, "tests/scripts/lib/inngest-host-shape-gate.sh"),
      "utf8",
    );
    const defAllow = /def allow:\s*\[([\s\S]*?)\]/.exec(lib);
    expect(defAllow).not.toBeNull();
    const allow = [...defAllow![1].matchAll(/"([^"]+)"/g)].map((m) => m[1]).sort();
    const targets = [...extractAllTargets(extractJobBlock(wf, "inngest_host"))].sort();
    expect(targets.length).toBe(15); // non-vacuity floor (#8754 dropped the inngest attachment; #8285 dropped the plaintext pair)
    expect(allow).toEqual(targets);
    // The passphrase pair is per-merge -targeted and must never join this allow-set.
    expect(allow).not.toContain("random_password.inngest_redis_luks");
    expect(allow).not.toContain("doppler_secret.inngest_redis_luks_key");
  });
});

/**
 * One shell command out of a job block: its first line (the first line matching `start`) through
 * the first line with no trailing backslash. `\\$`, not `\\\s*$`: bash does not continue a line
 * whose backslash is followed by a space, so neither does this. Throws unless exactly one line
 * matches, so a second matching command can never silently become the one under test.
 */
function commandIn(jobBlock: string, start: RegExp): string {
  const lines = jobBlock.split("\n");
  const hits = lines.filter((l) => start.test(l)).length;
  if (hits !== 1) throw new Error(`commandIn: ${hits} lines match ${start}, expected exactly 1`);
  const i = lines.findIndex((l) => start.test(l));
  const end = lines.findIndex((l, j) => j >= i && !/\\$/.test(l));
  return lines.slice(i, end < 0 ? lines.length : end + 1).join("\n");
}

/**
 * #8754: under -target, `removed { from = hcloud_firewall_attachment.inngest … }` is planned only
 * if its address is targeted, so the forget must ride the `apply` job's SAVED plan (`terraform plan
 * … -out=tfplan`, the one the destroy guard grades), not the post-bridge `terraform apply`. The
 * block's shape is Guard 1's (inngest-host.test.sh); the inngest_host job's side is the
 * allow === targets check above.
 */
describe("#8754 inngest firewall attachment forget rides the per-merge saved plan", () => {
  const ADDR = "hcloud_firewall_attachment.inngest";
  const applyJob = stripComments(extractJobBlock(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"), "apply"));
  const savedPlan = commandIn(applyJob, /^\s*terraform plan\b.*-out=tfplan/);
  const postBridge = commandIn(applyJob, /^\s*terraform apply -auto-approve -input=false \\$/);

  test("the address is -targeted inside the saved-plan command", () => {
    expect(extractAllTargets(savedPlan).has("hcloud_firewall_attachment.web")).toBe(true); // non-vacuity
    expect(extractAllTargets(savedPlan).has(ADDR)).toBe(true);
  });

  test("and not in the post-bridge terraform apply, nor in inngest_host_replace", () => {
    expect(extractAllTargets(postBridge).has("terraform_data.disk_monitor_install")).toBe(true); // non-vacuity
    expect(extractAllTargets(postBridge).has(ADDR)).toBe(false);
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    expect(extractAllTargets(extractJobBlock(wf, "inngest_host_replace")).has(ADDR)).toBe(false);
  });
});

/**
 * #8754 PR-B: the standing drift tail. Every address below sat in every drift report since #7316
 * because no workflow could apply it (classification: the #8754 plan's per-resource table). The
 * per-merge SAVED plan is the route that now converges the ones that should exist, so the positive
 * rows read that command. The negative rows ("never targeted", "never overridden") read the whole
 * write surface: every workflow that plans this root, in either `-target` spelling.
 */
describe("#8754 PR-B standing tail converges on the per-merge saved plan", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const savedPlan = commandIn(stripComments(extractJobBlock(wf, "apply")), /^\s*terraform plan\b.*-out=tfplan/);
  const planTargets = extractAllTargets(savedPlan);
  // Every workflow that runs terraform against this root, comment-stripped.
  const writeSurface = [WEB_PLATFORM_WORKFLOW, DEPLOY_PIPELINE_FIX_WORKFLOW]
    .map((p) => stripComments(readFileSync(p, "utf8")))
    .join("\n");
  // Terraform accepts `-target=ADDR` and `-target ADDR`; extractAllTargets sees only the first.
  // The leading `[a-z]` skips `--target 127.0.0.1:5000`-style flags of other tools.
  const anyFormTargets = new Set(
    [...writeSurface.matchAll(/(?<![\w-])--?target(?:=|\s+)['"]?([a-z][a-z0-9_]*\.[A-Za-z0-9_]+)/g)].map((m) => m[1]),
  );
  const tf = (name: string): string => stripComments(readFileSync(join(INFRA_DIR, name), "utf8"));
  // The body of the first top-level block whose header matches, brace-matched. "" when absent, so
  // a renamed or deleted block reds the row that reads it instead of passing on nothing.
  const block = (text: string, header: RegExp): string => {
    const m = header.exec(text);
    if (!m) return "";
    let depth = 0;
    for (let i = text.indexOf("{", m.index); i < text.length; i++) {
      if (text[i] === "{") depth++;
      else if (text[i] === "}" && --depth === 0) return text.slice(m.index, i + 1);
    }
    return "";
  };
  const allTf = listInfraTfFiles().map((f) => stripComments(readFileSync(f, "utf8"))).join("\n");
  const missingFrom = (addrs: string[], set: Set<string>): string[] => addrs.filter((a) => !set.has(a));
  const presentIn = (addrs: string[], set: Set<string>): string[] => addrs.filter((a) => set.has(a));

  test("the saved plan and the write surface are found (non-vacuity), and no config hides in *.tf.json", () => {
    expect(planTargets.has("cloudflare_bot_management.soleur_ai")).toBe(true);
    expect(planTargets.size).toBeGreaterThan(100);
    expect(anyFormTargets.has("cloudflare_bot_management.soleur_ai")).toBe(true);
    // listInfraTfFiles reads *.tf only; Terraform also loads *.tf.json, where a resource or a
    // removed block would escape every row below.
    expect(readdirSync(INFRA_DIR).filter((f) => f.endsWith(".tf.json"))).toEqual([]);
  });

  test("the git-data heartbeat pairs are per-merge targeted, no longer an exclusion, and still refused by the birth", () => {
    // The web-fed pair (#8754) and the host-originated pair (#9438): the second monitor is born
    // paused and is NOT in the per-merge arm list, because its feeder reaches the host only
    // through the owner-authorized replace.
    const pair = [
      "betteruptime_heartbeat.git_data_prd",
      "doppler_secret.git_data_heartbeat_url_prd",
      "betteruptime_heartbeat.git_data_host_prd",
      "doppler_secret.git_data_host_heartbeat_url_prd",
    ];
    const birth = extractAllTargets(extractJobBlock(wf, "git_data_host_create"));
    expect(birth.has("hcloud_server.git_data")).toBe(true); // non-vacuity
    expect(missingFrom(pair, planTargets)).toEqual([]);
    expect(pair.filter((a) => OPERATOR_APPLIED_EXCLUSIONS.has(a))).toEqual([]);
    expect(presentIn(pair, birth)).toEqual([]);
  });

  test("the host heartbeat secret reaches ONLY its heartbeat: project and config are literals, so the per-merge closure cannot pull in doppler_config.git_data_prd or hcloud_server.git_data (#9438)", () => {
    const src = tf("git-data.tf");
    const res = block(src, /^resource\s+"doppler_secret"\s+"git_data_host_heartbeat_url_prd"\s*\{/m);
    expect(res).toMatch(/^\s*project\s*=\s*"soleur"\s*$/m);
    expect(res).toMatch(/^\s*config\s*=\s*local\.git_data_liveness_doppler_cfg\s*$/m);
    // The local is a plain string, never a resource address (the closure stays resource-free).
    expect(src).toMatch(/^\s*git_data_liveness_doppler_cfg\s*=\s*"prd_git_data"\s*$/m);
    expect(res).toMatch(/^\s*value\s*=\s*betteruptime_heartbeat\.git_data_host_prd\.url\s*$/m);
    // Every address-shaped token in the block, minus the one heartbeat it must reference.
    const refs = [...res.matchAll(/\b(?:hcloud|doppler|betteruptime|random|tls|terraform)_[a-z_]+\.[a-z_0-9]+/g)].map((m) => m[0]);
    expect([...new Set(refs)]).toEqual(["betteruptime_heartbeat.git_data_host_prd"]);
    // The heartbeat is born paused and its arm is not a per-merge concern.
    const hb = block(src, /^resource\s+"betteruptime_heartbeat"\s+"git_data_host_prd"\s*\{/m);
    expect(hb).toMatch(/^\s*paused\s*=\s*true\s*$/m);
    expect(hb).toMatch(/^\s*push\s*=\s*false\s*$/m);
    expect(hb).toMatch(/ignore_changes\s*=\s*\[paused\]/);
  });

  test("the deployment policy is adopted by import into a NEW, destroy-proof address and the phantom address is forgotten", () => {
    const OLD = "github_repository_environment_deployment_policy.web_platform_infra_apply_main";
    const NEW = `${OLD}_adopted`;
    const src = tf("web-host-birth-environment.tf");
    // Both addresses ride the saved plan: an import or a removed block is planned only when its
    // address is targeted, and the old address must be targeted for its forget to be planned.
    expect(missingFrom([OLD, NEW], planTargets)).toEqual([]);
    const res = block(src, /^resource\s+"github_repository_environment_deployment_policy"\s+"web_platform_infra_apply_main_adopted"\s*\{/m);
    expect(res).toMatch(/^\s*branch_pattern\s*=\s*"main"\s*$/m);
    // The adopting merge carries a count-based [ack-destroy]; this keeps it off the pin.
    expect(res).toMatch(/^\s*prevent_destroy\s*=\s*true\s*$/m);
    expect(allTf).not.toMatch(/^resource\s+"github_repository_environment_deployment_policy"\s+"web_platform_infra_apply_main"\s*\{/m);
    const imp = block(src, /^import\s*\{/m);
    expect(imp).toMatch(new RegExp(`^\\s*to\\s*=\\s*${escapeRe(NEW)}\\s*$`, "m"));
    expect(imp).toMatch(/^\s*id\s*=\s*"soleur:web-platform-infra-apply:49861552"\s*$/m);
    const rem = block(src, /^removed\s*\{/m);
    expect(rem).toMatch(new RegExp(`^\\s*from\\s*=\\s*${escapeRe(OLD)}\\s*$`, "m"));
    expect(rem).toMatch(/^\s*destroy\s*=\s*false\s*$/m);
  });

  test("the orphaned ZOT_HEARTBEAT_URL secret is destroyed by a bare -target, never kept or forgotten", () => {
    const ADDR = "doppler_secret.zot_heartbeat_url_prd";
    expect(planTargets.has(ADDR)).toBe(true);
    // A bare target on an address with no configuration plans its DESTROY. A resource block (under
    // this address or any other that names the secret) would keep the value in Doppler prd; a
    // removed block would forget it and leave the value there too.
    expect(allTf).toContain('resource "doppler_secret" "zot_pull_token"'); // non-vacuity
    expect(allTf).not.toMatch(/resource\s+"doppler_secret"\s+"zot_heartbeat_url_prd"/);
    expect(allTf).not.toMatch(/^\s*name\s*=\s*"ZOT_HEARTBEAT_URL"\s*$/m);
    expect(allTf).not.toMatch(/from\s*=\s*doppler_secret\.zot_heartbeat_url_prd\b/);
  });

  test("bot management declares the live SBFM values and does not ignore them", () => {
    const res = block(tf("bot-management.tf"), /^resource\s+"cloudflare_bot_management"\s+"soleur_ai"\s*\{/m);
    expect(res).toMatch(/^\s*fight_mode\s*=\s*false\s*$/m); // non-vacuity
    expect(res).toMatch(/^\s*sbfm_definitely_automated\s*=\s*"allow"\s*$/m);
    expect(res).toMatch(/^\s*sbfm_verified_bots\s*=\s*"allow"\s*$/m);
    // Declared, not ignored: a dashboard flip to "block" must stay visible as drift.
    expect(res).not.toMatch(/ignore_changes/);
  });

  test("the proxy-TLS quartet is count-gated on host_proxy_tls_enabled, default false", () => {
    const src = tf("proxy-tls.tf");
    const quartet: Array<[string, string]> = [
      ["tls_private_key", "proxy_server"],
      ["tls_self_signed_cert", "proxy_server"],
      ["doppler_secret", "proxy_tls_key"],
      ["doppler_secret", "proxy_tls_cert"],
    ];
    const ungated = quartet
      .filter(([type, name]) => !/^\s*count\s*=\s*var\.host_proxy_tls_enabled\s*\?\s*1\s*:\s*0\s*$/m.test(
        block(src, new RegExp(`^resource\\s+"${type}"\\s+"${name}"\\s*\\{`, "m")),
      ))
      .map(([type, name]) => `${type}.${name}`);
    expect(ungated).toEqual([]);
    const v = block(tf("variables.tf"), /^variable\s+"host_proxy_tls_enabled"\s*\{/m);
    expect(v).toMatch(/^\s*type\s*=\s*bool\s*$/m);
    expect(v).toMatch(/^\s*default\s*=\s*false\s*$/m);
  });

  test("the inngest config-digest pointer exists only once a digest is promoted, default empty", () => {
    const res = block(tf("inngest-config-digest.tf"), /^resource\s+"doppler_secret"\s+"inngest_config_digest"\s*\{/m);
    expect(res).toMatch(/^\s*count\s*=\s*var\.inngest_config_digest\s*!=\s*""\s*\?\s*1\s*:\s*0\s*$/m);
    const v = block(tf("variables.tf"), /^variable\s+"inngest_config_digest"\s*\{/m);
    expect(v).toMatch(/^\s*default\s*=\s*""\s*$/m);
  });

  test("no workflow targets the gated resources or overrides their gate variables", () => {
    const gated = [
      "tls_private_key.proxy_server",
      "tls_self_signed_cert.proxy_server",
      "doppler_secret.proxy_tls_key",
      "doppler_secret.proxy_tls_cert",
      "doppler_secret.inngest_config_digest",
    ];
    expect(presentIn(gated, anyFormTargets)).toEqual([]);
    expect(gated.filter((a) => !OPERATOR_APPLIED_EXCLUSIONS.has(a))).toEqual([]);
    // A `-var`/TF_VAR_ override in a workflow would flip the gate without touching variables.tf.
    expect(writeSurface).not.toMatch(/\bhost_proxy_tls_enabled\b/);
    expect(writeSurface).not.toMatch(/-var[= ]+['"]?inngest_config_digest=|TF_VAR_inngest_config_digest/);
  });

  test("the infra-validation plan job can read deployment policies, and gains no write scope", () => {
    const iv = parseYaml(readFileSync(resolve(REPO_ROOT, ".github/workflows/infra-validation.yml"), "utf8")) as {
      jobs: Record<string, { permissions?: Record<string, string> }>;
    };
    const perms = iv.jobs.plan?.permissions ?? {};
    expect(perms.actions).toBe("read");
    expect(perms.contents).toBe("read");
    const writes = Object.entries(perms).filter(([, v]) => v === "write").map(([k]) => k);
    expect(writes).toEqual(["pull-requests"]);
  });
});

/**
 * #8714 task 5.4 (ADR-096): retire the GHCR token minter and the host-side GHCR credential
 * plumbing. The four Doppler objects are destroyed by the per-merge apply through BARE -targets:
 * the address stays in the saved plan while no configuration declares it, which plans its delete
 * (precedent: doppler_secret.zot_heartbeat_url_prd, #9062). A resource block would keep the value
 * in Doppler prd; a `removed { destroy = false }` block would forget it and leave the value there,
 * and even `destroy = true` needs the -target to be planned. Removing the -target lines (and this
 * describe) is a follow-up AFTER the destroy has applied (the lines then plan nothing).
 */
describe("#8714 5.4 GHCR minter retirement: bare -targets destroy the four Doppler objects", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const savedPlan = commandIn(stripComments(extractJobBlock(wf, "apply")), /^\s*terraform plan\b.*-out=tfplan/);
  const planTargets = extractAllTargets(savedPlan);
  const allTf = listInfraTfFiles().map((f) => stripComments(readFileSync(f, "utf8"))).join("\n");
  const RETIRED: Array<[string, string]> = [
    ["doppler_secret", "ghcr_read_user"],
    ["doppler_secret", "ghcr_read_token"],
    ["doppler_service_token", "ghcr_minter"],
    ["doppler_secret", "ghcr_minter_doppler_token"],
  ];
  const addrs = RETIRED.map(([t, n]) => `${t}.${n}`);

  test("all four addresses stay in the per-merge saved plan, so their deletes are planned", () => {
    expect(planTargets.has("doppler_secret.github_app_id")).toBe(true); // non-vacuity
    expect(addrs.filter((a) => !planTargets.has(a))).toEqual([]);
  });

  test("no .tf declares, forgets, or re-names any of them", () => {
    expect(allTf).toContain('resource "doppler_secret" "zot_pull_token"'); // non-vacuity
    const declared = RETIRED.filter(([t, n]) => new RegExp(`resource\\s+"${t}"\\s+"${n}"`).test(allTf)).map(
      ([t, n]) => `${t}.${n}`,
    );
    expect(declared).toEqual([]);
    const forgotten = addrs.filter((a) => new RegExp(`from\\s*=\\s*${escapeRe(a)}\\b`).test(allTf));
    expect(forgotten).toEqual([]);
    // Any address, not just the four: a second resource publishing one of these names would keep it.
    const names = ["GHCR_READ_USER", "GHCR_READ_TOKEN", "GHCR_MINTER_DOPPLER_TOKEN"].filter((n) =>
      new RegExp(`^\\s*name\\s*=\\s*"${n}"\\s*$`, "m").test(allTf),
    );
    expect(names).toEqual([]);
  });

  test("each retired address is targeted BARE (an instance key would target nothing in state)", () => {
    const keyed = extractTargetsWithKeys(savedPlan);
    expect(keyed).toContain("doppler_secret.github_app_id"); // non-vacuity
    expect(addrs.filter((a) => !keyed.includes(a))).toEqual([]);
  });

  test("no config file anywhere under infra/ names a retired object, in any spelling", () => {
    const walk = (d: string): string[] =>
      readdirSync(d, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory()
          ? e.name === ".terraform" ? [] : walk(resolve(d, e.name))
          : /\.tf(\.json)?$/.test(e.name) ? [resolve(d, e.name)] : [],
      );
    const TOKEN = /\bghcr_(read|minter)/i;
    const files = walk(INFRA_DIR);
    expect(files.some((f) => f.endsWith("/sentry/cron-monitors.tf"))).toBe(true); // the walk recursed
    // The regex matches the retirement note in inngest-host.tf before comment-stripping (non-vacuity).
    expect(TOKEN.test(readFileSync(resolve(INFRA_DIR, "inngest-host.tf"), "utf8"))).toBe(true);
    const hits = files.filter((f) => TOKEN.test(stripComments(readFileSync(f, "utf8"))));
    expect(hits.map((f) => f.slice(INFRA_DIR.length + 1))).toEqual([]);
  });

  test("the ghcr_read_* root variables are gone", () => {
    expect(allTf).toMatch(/^variable\s+"image_name"\s*\{/m); // non-vacuity
    expect(allTf).not.toMatch(/^variable\s+"ghcr_read_(user|token)"\s*\{/m);
  });
});

/**
 * JOB <=> GATE-LIB PAIRING.
 *
 * Two INVERSE, near-identically-named registry gates now exist (host-replace PRESERVES the
 * store; luks-recut REPLACES it). A copy-pasted `source` line would silently invert a destroy
 * authorization while every other assertion in this file stays green.
 */
/**
 * Escape EVERY regex metacharacter, not just `.`.
 *
 * The previous form escaped only the dot, which CodeQL correctly flags as
 * incomplete escaping (js/incomplete-sanitization, high): a `\` in the input
 * would survive into the pattern and change its meaning rather than match
 * itself. Today's inputs are hardcoded filenames from ALL_REGISTRY_LIBS below,
 * so nothing is exploitable — but a partial escaper in a gate-parity assertion
 * is a wrong-by-construction helper that the next filename (or the next reader
 * who copies it) inherits. Escape the whole class instead of the one character
 * that happened to appear.
 */
const escapeRe = (s: string): string => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");

describe("each registry dispatch job sources exactly its own gate lib", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const ALL_REGISTRY_LIBS = [
    "registry-host-replace-gate.sh",
    "registry-region-migrate-gate.sh",
    "registry-luks-recut-gate.sh",
  ];
  const PAIRS: Array<[string, string]> = [
    ["registry_host_replace", "registry-host-replace-gate.sh"],
    ["registry_region_migrate", "registry-region-migrate-gate.sh"],
    ["registry_luks_recut", "registry-luks-recut-gate.sh"],
  ];

  for (const [jobId, ownLib] of PAIRS) {
    test(`${jobId} sources ${ownLib} and no sibling registry gate`, () => {
      const block = extractJobBlock(wf, jobId);
      expect(block.length).toBeGreaterThan(0);
      for (const lib of ALL_REGISTRY_LIBS) {
        const sourced = new RegExp(
          `source\\s+"\\$\\{GITHUB_WORKSPACE\\}/tests/scripts/lib/${escapeRe(lib)}"`,
        ).test(block);
        expect(sourced).toBe(lib === ownLib);
      }
    });
  }
});

/**
 * STEP ORDER for registry_luks_recut (#6929).
 *
 * Order is a safety property here, not cosmetics:
 *   - the pull-path health gate and the destroy-guard must precede the APPLY (afterwards there
 *     is nothing left to protect — the store is already destroyed);
 *   - the web-1/workspaces zero-touch assert must precede the apply too. In the plan's v1 it ran
 *     AFTER, reading the same tfplan.json the gate had already read — it therefore added no
 *     information and could prevent nothing;
 *   - the liveness poll must follow the apply, since it asserts the NEW host beats.
 */
describe("registry recut step order is a safety property", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");

  // Step names in declaration order for a job. Anchored on the `- name:` step key at its exact
  // indent so prose inside a `run:` body cannot be mistaken for a step.
  const stepsOf = (job: string) =>
    [...extractJobBlock(wf, job).matchAll(/^ {6}- name: (.+)$/gm)].map((m) =>
      m[1].trim(),
    );

  // The authorization half moved into its own job (#7277 B2), so this property now SPANS TWO
  // JOBS. It is expressed per-job plus an explicit `needs:` edge rather than collapsed into one
  // list, because the ordering that matters after the split is a job dependency, not a step
  // index — a step-index assertion inside one job cannot see it at all.
  //
  // This suite went RED and unnoticed for the whole life of the branch: the D10 step was renamed
  // from "Pre-destroy pull-path health gate" to "Pre-destroy authorization gate (D10 VERDICT)"
  // and the needle was not. The non-vacuity floor caught it (findIndex returned -1), which is
  // the only reason it failed loudly instead of passing on an all -1 array. Needles below are
  // deliberately the SHORTEST stable substring of each step name, so a future retitling that
  // keeps the step's meaning does not red the suite for a cosmetic reason.
  const gateSteps = stepsOf("registry_pull_path_gate");
  const recutSteps = stepsOf("registry_luks_recut");
  const gIdx = (needle: string) => gateSteps.findIndex((n) => n.includes(needle));
  const rIdx = (needle: string) => recutSteps.findIndex((n) => n.includes(needle));

  test("the recut job depends on the authorization gate job", () => {
    // The load-bearing edge. Without it the destroy can run with no verdict at all, and every
    // step-order assertion below would still pass.
    expect(extractJobBlock(wf, "registry_luks_recut")).toMatch(
      /^ {4}needs: registry_pull_path_gate$/m,
    );
  });

  test("all ordered steps are present in both jobs", () => {
    // Non-vacuity floor: if either extraction found nothing, every findIndex returns -1 and the
    // ordering assertions would pass on an all -1 array.
    expect(gateSteps.length).toBeGreaterThanOrEqual(6);
    expect(recutSteps.length).toBeGreaterThanOrEqual(5);
    for (const needle of [
      "Validate typed confirm",
      "Resolve recovery posture",
      "D10 PREPARE",
      "Start throwaway registry",
      "D10 VERDICT",
      "Upload pinned restore manifest",
    ]) {
      expect(gIdx(needle)).toBeGreaterThanOrEqual(0);
    }
    for (const needle of [
      "Validate typed confirm",
      "destroy-guard",
      "Pre-apply zero-touch assert",
      "Terraform apply",
      "Post-apply liveness assert",
    ]) {
      expect(rIdx(needle)).toBeGreaterThanOrEqual(0);
    }
  });

  test("gate job: confirm < posture < PREPARE < throwaway < VERDICT", () => {
    const order = [
      gIdx("Validate typed confirm"),
      gIdx("Resolve recovery posture"),
      gIdx("D10 PREPARE"),
      gIdx("Start throwaway registry"),
      gIdx("D10 VERDICT"),
    ];
    expect(order).toEqual([...order].sort((a, b) => a - b));
  });

  test("gate job: the manifest is uploaded AFTER the verdict, not between PREPARE and VERDICT", () => {
    // #7277 B5. PREPARE writes the manifest, the VERDICT step re-derives over the SAME path and
    // rehearses against what it derived, and the restore job downloads this artifact. Uploading
    // between them captured PREPARE's inventory while the rehearsal proved VERDICT's — a
    // divergence with NO other observable, since both runs are green and nothing compares the
    // two sets. Ordering is the fix, so ordering is what must be pinned.
    expect(gIdx("Upload pinned restore manifest")).toBeGreaterThan(gIdx("D10 VERDICT"));
  });

  test("recut job: confirm < destroy-guard < zero-touch < apply < liveness", () => {
    const order = [
      rIdx("Validate typed confirm"),
      rIdx("destroy-guard"),
      rIdx("Pre-apply zero-touch assert"),
      rIdx("Terraform apply"),
      rIdx("Post-apply liveness assert"),
    ];
    expect(order).toEqual([...order].sort((a, b) => a - b));
  });

  test("the zero-touch assert runs BEFORE the apply, not after", () => {
    // Pinned separately from the chain above because this is the one ordering the plan's v1 got
    // wrong, and a chain assertion would not name it if it regressed.
    expect(rIdx("Pre-apply zero-touch assert")).toBeLessThan(rIdx("Terraform apply"));
  });

  test("the gate job performs no terraform action", () => {
    // The split is only worth anything if the gate job cannot destroy. Asserted as negative
    // space: a gate job that acquired an apply/destroy step would silently re-create the exact
    // coupling the split removed, and no ordering assertion would notice.
    //
    // MEASURED ON A COMMENTS-STRIPPED COPY. The first version of this assertion matched the
    // PROSE `push a timeout into \`terraform apply\` or D11` in the next job's explanatory header
    // — a false RED on a correct workflow, and the same bare-token trap
    // (cq-assert-anchor-not-bare-token) this PR fixed twice elsewhere. A guard that forbids a
    // literal the surrounding file must also DOCUMENT has to anchor on something a comment
    // cannot produce.
    const gate = extractJobBlock(wf, "registry_pull_path_gate")
      .split("\n")
      .filter((l) => !/^\s*#/.test(l))
      .join("\n");
    expect(gate).not.toMatch(/terraform\s+(apply|destroy)/);
    expect(gate).not.toMatch(/^\s+-target=/m);
  });
});

// ─── git-data-host-create dispatch: the birth -target set + gate pairing (#6977) ──
//
// `apply_target=git-data-host-create` (ADR-149) is the ONLY automated route that can
// create the git-data store. It is NOT a widened git-data-host-replace: that gate
// requires actions ⊇ {delete,create}, fires its luks_passphrase_touched arm on a CREATE,
// and rests its allow-set on "preserved by OMISSION" — an argument that INVERTS
// on a birth, where an omitted address is a MISSING resource rather than a protected one.
// So the two -target sets stay separately pinned, and the job is asserted below to borrow
// neither the sibling gate nor its allow-set.
//
// THE SAFETY PROPERTY OF THIS SET IS ITS COMPLETENESS, which is the mirror image of the
// replace set (whose property is its omissions). Four members are DOWNSTREAM of the
// server and so are not auto-pulled by -target's upstream closure; three more are
// siblings terraform would never pull at all. Each omission is a distinct catastrophe —
// enumerated in the gate's requirement arm — so the set is asserted three ways: workflow
// -target list == gate `def allow:` == this constant.
const GIT_DATA_BIRTH_TARGET_BASES = [
  "hcloud_server.git_data",
  // DOWNSTREAM of the server (references its .id) — omit and the host comes up with no
  // private-net IP (#6416). runcmd is once-per-instance and ADR-115 bars git-data from
  // the reboot primitive, so that host must be REPLACED, not repaired.
  "hcloud_server_network.git_data",
  "hcloud_volume.git_data_luks",
  // DOWNSTREAM — omit it and the store boots with its volume unmounted: at-rest encryption is
  // absent while every artifact claims it present.
  "hcloud_volume_attachment.git_data_luks",
  // UPSTREAM of its own attachment (the attachment references .id), which is why it is in
  // the set at all — and why the gate needs a separate firewall-CONTENT arm: being in the
  // allow-set makes `update` a permitted verb on the one resource carrying the entire
  // public-exposure defense.
  "hcloud_firewall.git_data",
  // DOWNSTREAM, and the only thing binding the zero-rule deny-all firewall to the host.
  // Omit and the store boots NAKED on its public IPv4/IPv6.
  "hcloud_firewall_attachment.git_data",
  // (#6977 P7) The prd_git_data branch config. VERIFIED ABSENT in Doppler prd; both
  // writes below target it, so without it the apply fails "Could not find requested
  // config". Provisioned rather than hand-created — and NEVER given a per-PR -target.
  "doppler_config.git_data_prd",
  "doppler_service_token.git_data",
  "tls_private_key.git_transport",
  "tls_private_key.git_provision",
  "tls_private_key.git_remove",
  // SIBLINGS, not in the server's graph (issue AC4). Omit one and the host's
  // authorized_keys holds a public half whose private half exists only in tfstate.
  "doppler_secret.git_transport_ssh_private_key",
  "doppler_secret.git_provision_ssh_private_key",
  "doppler_secret.git_remove_ssh_private_key",
  // SIBLINGS (P12). The service token authorizes READING the config; it says nothing
  // about the config CONTAINING the key. Omit these and luksOpen fails — silently.
  "random_password.git_data_luks",
  "doppler_secret.git_data_luks_key",
  // (#6982) SIBLING. Publishes GIT_DATA_SSH_HOST from `hcloud_server_network.git_data.ip` —
  // the COMPUTED NIC attribute, which is what ADR-149's DC-3 mandates and what git-data.tf
  // actually does (`value = hcloud_server_network.git_data.ip`).
  //
  // (#7772) THIS COMMENT SAID THE OPPOSITE and was corrected here. It claimed the value came
  // from a STATIC local "never from hcloud_server_network.git_data.ip", and closed by saying
  // ADR-149 "cut it from #6977 believing the opposite" — describing the position DC-3
  // REVERSED before merge, in a birth-route artifact, about a birth-route resource. The
  // reversal is safe precisely because this secret's only -target line IS the birth job,
  // which already targets both hcloud_server.git_data and hcloud_server_network.git_data:
  // the edge drags nothing new into any plan that exists, and there is no pre-birth window to
  // protect because the secret is created BY the dispatch. The mandated form is also strictly
  // stronger — a birth that landed the server but not the NIC can no longer publish an
  // address nothing answers on.
  //
  // Omit it and every account deletion files a FALSE Art. 17 erasure-failed event from birth
  // onward. That part was always true and is unchanged.
  "doppler_secret.git_data_ssh_host",
  // (#6982) SIBLING. The Better Stack ingest token in prd_git_data, read by the
  // post-Doppler emits (boot-completion, gc faults). Omit it and the queryable copy of the
  // boot signal never ships, which is what the follow-through probe reads.
  "doppler_secret.git_data_betterstack_logs_token",
  // (#7226, ADR-237) The Terraform-minted SSH host key cloud-init installs, and its pin in prd.
  // PRESENCE members (create-or-no-op), not entailed: neither references the server's id.
  "tls_private_key.git_data_host_ssh",
  "doppler_secret.git_data_ssh_host_key",
];

// Asserted ABSENT from the -target set. Both are refused by the gate's out-of-scope arm
// too, but absence here is the primary mechanism — an untargeted resource cannot be
// planned at all.
const GIT_DATA_BIRTH_REFUSED = [
  // The feeder already shipped and is web-host-resident (#6548), so creating a monitor
  // this route cannot arm reproduces the #6537 fed-but-paused shape: a green dashboard
  // measuring nothing.
  "betteruptime_heartbeat.git_data_prd",
  "doppler_secret.git_data_heartbeat_url_prd",
  // (#9438) The host-originated pair: its feeder rides the host's own cloud-init, and the URL is
  // read at runtime from the scoped config, so the birth's exact -target set has no use for it and
  // must not take a Doppler write into prd_git_data.
  "betteruptime_heartbeat.git_data_host_prd",
  "doppler_secret.git_data_host_heartbeat_url_prd",
  // SSH-provisions web-1, the LIVE serving host, and remote-exec runs at APPLY not plan.
  "terraform_data.git_data_probe_install",
];

describe("git-data-host-create dispatch -target set + birth-gate pairing (#6977)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const jobBlock = extractJobBlock(wf, "git_data_host_create");

  test("the job exists and is reachable only via its own apply_target", () => {
    // AC1 is verified by PARSED ENUM MEMBERSHIP + the job `if:` needle, deliberately not
    // by a `grep -c … >= 3` — three comment lines satisfy that, and
    // stock-preflight-coverage.test.ts documents it as a real false-green in this repo.
    expect(jobBlock.length).toBeGreaterThan(0);
    expect(jobBlock).toMatch(
      /if:\s*github\.event_name == 'workflow_dispatch' && inputs\.apply_target == 'git-data-host-create'/,
    );
    // LINE-ANCHORED, not `.toContain`. The extracted `options:` block includes its YAML
    // COMMENT lines, and this job's enum entry carries a comment block naming itself — so
    // `.toContain("- git-data-host-create")` is satisfied by the comment. MEASURED:
    // commenting out the real enum line kept the whole suite green while making the job
    // permanently undispatchable, i.e. killing the feature this PR ships. That is the same
    // false-green class the assertion's own comment claims to avoid.
    const opts = /apply_target:[\s\S]*?options:([\s\S]*?)\n\nconcurrency:/.exec(wf);
    expect(opts).not.toBeNull();
    expect(opts![1]).toMatch(/^\s*-\s+git-data-host-create\s*$/m);
  });

  test("the -target set equals the constant, exactly", () => {
    const targets = [...extractAllTargets(jobBlock)].sort();
    // Non-vacuity: the extraction must actually find the members (the count follows the constant;
    // a hard-coded number here is what went stale when the plaintext pair left).
    expect(targets.length).toBeGreaterThan(10);
    expect(targets.length).toBe(GIT_DATA_BIRTH_TARGET_BASES.length);
    expect(targets).toEqual([...GIT_DATA_BIRTH_TARGET_BASES].sort());
  });

  test("the refused addresses are ABSENT from the -target set", () => {
    const targets = extractAllTargets(jobBlock);
    for (const addr of GIT_DATA_BIRTH_REFUSED) {
      expect(targets.has(addr)).toBe(false);
    }
    // Non-vacuity for the assertion above: the set is genuinely non-empty, so "absent"
    // is a real property rather than a consequence of extracting nothing.
    expect(targets.has("hcloud_server.git_data")).toBe(true);
  });

  test("every -target is an OPERATOR_APPLIED_EXCLUSION (ADR-103)", () => {
    // The property that keeps merging this PR from applying anything to git-data. If a
    // future -target is added here without a matching exclusion, the per-merge apply
    // would start reaching it.
    const missing = GIT_DATA_BIRTH_TARGET_BASES.filter(
      (a) => !OPERATOR_APPLIED_EXCLUSIONS.has(a),
    );
    expect(missing).toEqual([]);
  });

  // ── (#6982, AC8a) THE FOURTH REGISTRATION SITE ────────────────────────────────────
  //
  // The gate carries `def allow:` (a PERMISSION set) *and* a separate hardcoded PRESENCE
  // loop (a COMPLETENESS set) that nothing extracted until now. Those are different
  // properties, and the three-way check above only ever pinned the first, so a
  // THREE-OF-FOUR edit was fully green: a new address would be PERMITTED to change but
  // not REQUIRED to appear, and a birth whose Doppler write is silently absent would
  // PASS. That is the exact shape ADR-149 Residual 2 warns about, hiding behind a PASS.
  //
  // The partition is asserted as an equation rather than a count so it cannot rot:
  //   presence ∪ entailed ∪ {server} ∪ {firewall_attachment} == the -target set
  // Entailed and firewall_attachment are enumerated here because they are structural
  // (they are the members the gate demands CREATE rather than merely appear).
  test("the gate's PRESENCE loop + entailed + server + fw-attachment == the -target set", () => {
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/git-data-host-birth-gate.sh"),
      "utf8",
    );

    // The presence loop is `for present_addr in \ "a" \ "b" …; do`. Anchor on the loop
    // variable, NOT on a bare quoted-address run — the file is full of quoted addresses
    // in prose, and a looser pattern would silently capture the wrong block.
    const presenceBlock = /for present_addr in\s*\\\s*([\s\S]*?);\s*do/.exec(gateSrc);
    expect(presenceBlock).not.toBeNull();
    const presence = [...presenceBlock![1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);

    const entailedBlock = /for required_addr in\s*\\\s*([\s\S]*?);\s*do/.exec(gateSrc);
    expect(entailedBlock).not.toBeNull();
    const entailed = [...entailedBlock![1].matchAll(/"([^"]+)"/g)].map((m) => m[1]);

    // Non-vacuity floors: an extraction that found nothing would make the union assertion
    // below pass only by accident of the other terms.
    expect(presence.length).toBeGreaterThan(10);
    expect(entailed.length).toBeGreaterThan(0);

    // The two members the gate handles by their own dedicated arms rather than by a loop:
    // the server (the `creates == 1` identity arm) and the firewall attachment (an
    // OUTCOME arm asserting server_ids ends at length 1 — deliberately NOT entailed).
    const union = [
      ...new Set([
        ...presence,
        ...entailed,
        "hcloud_server.git_data",
        "hcloud_firewall_attachment.git_data",
      ]),
    ].sort();

    expect(union).toEqual([...GIT_DATA_BIRTH_TARGET_BASES].sort());
    // The partition is DISJOINT: the loops' sizes plus the two dedicated-arm members add up to the
    // target set exactly, so the entailed count follows the lists rather than a hard-coded number.
    expect(presence.length + entailed.length + 2).toBe(GIT_DATA_BIRTH_TARGET_BASES.length);

    // (AC8b) The two #6982 additions must join the PRESENCE half specifically. In the
    // entailed loop they would demand `creates == 1`, which a resumed dispatch cannot
    // satisfy (they legitimately re-plan as no-ops) — ADR-149's "too strict → a permanent
    // wedge". This is the half of the placement that a union check alone cannot see.
    for (const addr of [
      "doppler_secret.git_data_ssh_host",
      "doppler_secret.git_data_betterstack_logs_token",
    ]) {
      expect(presence).toContain(addr);
      expect(entailed).not.toContain(addr);
    }
  });

  // ── (#6982, AC8c) THE ZERO-OF-N CASE ──────────────────────────────────────────────
  //
  // Every arm above compares the registration sites TO EACH OTHER, so declaring a new
  // resource in git-data.tf and touching NONE of them is completely silent: the parity
  // census does not cover general resources, and an untargeted resource is never planned,
  // so `terraform validate`, `tsc` and a green PR branch all agree it is fine. It would
  // surface for the first time at a birth, as an absence.
  //
  // Scoped to the address classes whose omission is actually harmful and which git-data.tf
  // owns: Doppler writes (a secret that never lands) and Better Stack objects (a monitor
  // that never exists). Both must be either in the birth set or explicitly excluded.
  test("every doppler_secret/betteruptime address in git-data*.tf is registered or excluded", () => {
    const declared = new Set<string>();
    for (const f of [
      "apps/web-platform/infra/git-data.tf",
      "apps/web-platform/infra/git-data-luks.tf",
    ]) {
      const src = readFileSync(resolve(REPO_ROOT, f), "utf8");
      for (const m of src.matchAll(
        /^resource\s+"(doppler_secret|doppler_config|doppler_service_token|betteruptime_\w+)"\s+"([^"]+)"/gm,
      )) {
        declared.add(`${m[1]}.${m[2]}`);
      }
    }

    // Non-vacuity: the scan must actually find the declarations it is grading.
    expect(declared.size).toBeGreaterThan(5);
    expect(declared.has("doppler_secret.git_data_ssh_host")).toBe(true);

    const birthSet = new Set(GIT_DATA_BIRTH_TARGET_BASES);
    const refused = new Set(GIT_DATA_BIRTH_REFUSED);
    const unregistered = [...declared].filter(
      (a) =>
        !birthSet.has(a) && !OPERATOR_APPLIED_EXCLUSIONS.has(a) && !refused.has(a),
    );
    expect(unregistered).toEqual([]);
  });

  test("stripDispatchJobs removes the job's targets from the coverage set", () => {
    const stripped = extractAllTargets(stripDispatchJobs(wf));
    // All are exclusions, so folding them in would assert per-merge coverage for
    // a fan-out the per-merge apply deliberately never touches.
    expect(stripped.has("doppler_config.git_data_prd")).toBe(false);
    // Non-vacuity for the strip: the job block genuinely carries the target.
    expect(extractAllTargets(jobBlock).has("doppler_config.git_data_prd")).toBe(true);
  });

  test("the job INVOKES each gate, and the invocations cannot be skipped", () => {
    // SOURCING A BASH LIBRARY ONLY DEFINES FUNCTIONS — it runs no check. Asserting the
    // `source` lines therefore pins nothing about whether the gate ever executes, and
    // three separate mutations were MEASURED green against the source-only assertions:
    //   • `if ! git_data_host_birth_gate tfplan.json; then` -> `if false; then`
    //   • deleting the only git_data_birth_readiness_gate invocation
    //   • adding `if: ${{ false }}` to the Birth-readiness interlock step
    // Each disarms the only check on a path that creates the store holding every user's
    // source code. The sibling web_host_replace suite already asserts its invocation; that
    // precedent was dropped here.
    expect(jobBlock).toMatch(/^\s*if ! git_data_host_birth_gate tfplan\.json; then/m);
    expect(jobBlock).toMatch(/^\s*if ! stock_preflight_gate tfplan\.json; then/m);
    expect(jobBlock).toMatch(
      /^\s*if ! git_data_birth_readiness_gate "\$\{GITHUB_WORKSPACE\}\/[^"]+"; then/m,
    );
    // #6982 A3 added a SECOND interlock and did not inherit this pin. Measured: deleting its
    // invocation, or putting `if: ${{ false }}` on its step, left this suite 98/0 GREEN —
    // the same three mutations the comment above says were measured against gate 1, on the
    // gate that is the only thing holding the birth today.
    expect(jobBlock).toMatch(
      /^\s*if ! git_data_rung2_rehearsal_gate "\$\{GITHUB_WORKSPACE\}\/[^"]+"; then/m,
    );
    // #8009 adds a THIRD interlock (CPO condition C1). It inherits every pin above rather
    // than repeating their history: the rung-2 gate is structurally incapable of catching a
    // collapsed authorization map, because rehearsal.tf sets all three pubkeys to one
    // tls_private_key by design -- so a production collapse is a NO-OP in the rehearsal and
    // the evidence still records PASS. This gate is the only mechanical check on that class.
    expect(jobBlock).toMatch(
      /^\s*git_data_authorization_map_gate "\$\{GITHUB_WORKSPACE\}\/[^"]+" \|\| rc=\$\?$/m,
    );
    // `rc=0` BEFORE THE CALL, AND `|| rc=$?` ON IT. Actions runs the block under -eo
    // pipefail, so the bare `cmd; rc=$?` form aborts AT the call and every reporting line
    // below it never runs. Pinning the capture shape is pinning that the step can report.
    expect(jobBlock).toMatch(/^\s*rc=0$/m);
    // ABORT (2) MUST NOT BE REPORTED AS A VERDICT ABOUT THE KEY MAP. The gate is tri-state
    // and its suite pins that; a single branch here asserted the HOLD claim on all ten
    // could-not-measure paths, which is the defect class this gate exists to close, one
    // layer up. Both branches must exist and the rc=2 one must name it as an INSTRUMENT
    // failure.
    expect(jobBlock).toMatch(/^\s*if \[\[ "\$rc" -eq 2 \]\]; then$/m);
    expect(jobBlock).toMatch(/COULD NOT MEASURE/);
    expect(jobBlock).toMatch(/^\s*if \[\[ "\$rc" -ne 0 \]\]; then$/m);

    // The interlocks are separate STEPS, so each can be disarmed without touching its body
    // at all. Pin the three ways for BOTH: a conditional, continue-on-error, or a missing
    // non-zero exit.
    for (const stepName of [
      "Birth-readiness interlock",
      "Rung-2 rehearsal interlock",
      "Authorization-map interlock",
    ]) {
      const step = new RegExp(`- name: ${stepName}[\\s\\S]*?(?=\\n      - name: )`).exec(jobBlock);
      expect(step, `step not found: ${stepName}`).not.toBeNull();
      expect(step![0]).not.toMatch(/^\s*if:/m);
      expect(step![0]).not.toMatch(/continue-on-error/);
      expect(step![0]).toMatch(/^\s*exit 1$/m);
    }

  });

  test("the interlock inspects the SAME template git-data.tf renders", () => {
    // MEASURED: repointing the job's path argument to apps/web-platform/infra/cloud-init.yml
    // — the WEB host's template — left every suite green AND made the gate RELEASE, because
    // that file legitimately carries four ${sentry_dsn} interpolations. A one-token edit
    // silently disengages the entire interlock, and the gate's fail-closed arms cannot help:
    // the wrong file exists and satisfies the sentinel.
    //
    // The gate's whole argument is "wiring the sentinel IS the work, because templatefile
    // fails on an unsupplied variable" — which holds only if the template it inspects is
    // the one being rendered. Bind them.
    // (#7025, R7) The render moved to modules/git-data-userdata/main.tf, which BOTH the
    // production root and the rung-2 rehearsal root call. Read the map from there — and
    // strip the `../../` that a module two levels down must write, so the comparison is
    // still between two names of the SAME file rather than between two spellings of a path.
    const tfSrc = readFileSync(
      resolve(REPO_ROOT, "apps/web-platform/infra/modules/git-data-userdata/main.tf"),
      "utf8",
    );
    const rendered = /templatefile\("\$\{path\.module\}\/((?:\.\.\/)*)([^"]+)"/.exec(tfSrc);
    expect(rendered).not.toBeNull();
    // The prefix must be exactly the two levels that reach apps/web-platform/infra/. A
    // deeper or shallower run means the module moved and the payload paths silently now
    // resolve somewhere else — which the rung-2 gate would report as a floor ABORT, but
    // only at dispatch time.
    expect(rendered![1]).toBe("../../");
    const inspected = /git_data_birth_readiness_gate "\$\{GITHUB_WORKSPACE\}\/apps\/web-platform\/infra\/([^"]+)"/.exec(jobBlock);
    expect(inspected).not.toBeNull();
    expect(inspected![1]).toBe(rendered![2]);
  });

  test("the replicated literals are bound, not merely commented", () => {
    // Each of these lives in >= 2 places with a COMMENT asserting they must agree, and
    // each was MEASURED to drift silently: renaming the new job's concurrency group,
    // changing the confirm token, or renaming the Doppler config all left the suite green
    // while breaking the mutex, the runbook's dispatch command, and the documented
    // terraform-import recovery respectively.

    // The shared mutex. GitHub does not error on divergent group strings — they silently
    // fail to serialize — so a one-sided literal is a mutex of one.
    for (const job of ["git_data_host_create", "git_data_host_replace"]) {
      expect(extractJobBlock(wf, job)).toMatch(/^\s{6}group:\s*git-data-state\s*$/m);
    }
    expect((wf.match(/^\s{6}group: git-data-state\s*$/gm) ?? []).length).toBe(2);

    // The confirm token, bound to the runbook that tells the operator to type it.
    expect(jobBlock).toMatch(/\[\[\s*"\$CONFIRM_RAW"\s*!=\s*"BIRTH-GIT-DATA"\s*\]\]/);
    const runbook = readFileSync(
      resolve(REPO_ROOT, "knowledge-base/engineering/operations/runbooks/git-data-birth.md"),
      "utf8",
    );
    expect(runbook).toContain("confirm=BIRTH-GIT-DATA");

    // The Doppler config name, bound to the ONLY documented recovery from the
    // already-exists dead end (a 400 that a re-dispatch cannot clear).
    const luksSrc = readFileSync(resolve(REPO_ROOT, "apps/web-platform/infra/git-data-luks.tf"), "utf8");
    const cfg = /resource "doppler_config" "git_data_prd"[\s\S]*?name\s*=\s*"([^"]+)"/.exec(luksSrc);
    expect(cfg).not.toBeNull();
    expect(jobBlock).toContain(`terraform import doppler_config.git_data_prd soleur.${cfg![1]}`);
    expect(runbook).toContain(`terraform import doppler_config.git_data_prd soleur.${cfg![1]}`);
  });

  test("the job SOURCES both gates by command, and borrows no sibling gate", () => {
    // Anchored on `source` as a COMMAND at line start, not a bare filename `.includes`.
    // A filename substring is satisfied by a comment mentioning the gate — a recorded
    // false-green in this repo — and the whole point of this assertion is that the job
    // executes the same bytes the gate's own suite exercises.
    expect(jobBlock).toMatch(
      /^\s*source\s+"\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/git-data-host-birth-gate\.sh"/m,
    );
    expect(jobBlock).toMatch(
      /^\s*source\s+"\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/git-data-birth-readiness-gate\.sh"/m,
    );
    expect(jobBlock).toMatch(
      /^\s*source\s+"\$\{GITHUB_WORKSPACE\}\/tests\/scripts\/lib\/stock-preflight-gate\.sh"/m,
    );
    // It must NOT source the replace gate. Grading a birth against that contract aborts
    // three ways, and the two files are siblings by shape and opposites by contract.
    // Anchored on `source` as a COMMAND: `[^\n]*` would let any line containing the
    // substring "source" qualify — and "re-source" / "resource" contain it.
    expect(jobBlock).not.toMatch(/^\s*source\s+\S*git-data-host-replace-gate\.sh/m);
  });

  // ORDERING ASSERTIONS. Every index below is taken from a SYNTACTIC CONSTRUCT — an
  // INVOCATION at line start (`if ! <gate_fn>`), or `terraform plan` with its flags —
  // never a bare filename or phrase.
  //
  // That is not stylistic caution. The first draft used `indexOf("terraform plan")` and
  // FAILED, because the job's own header comment says "...not after a two-minute
  // terraform plan": a bare-token index matched the COMMENT and reported the interlock
  // as running after the plan when it runs before it.
  //
  // A `source`-position index was then tried and MEASURED INERT — see the note in the
  // first test below. Its helper has been DELETED rather than left unused: a `source`
  // line only DEFINES a bash function, so indexing on it pins definition order while
  // the invocations it claims to order can be freely swapped. Keeping a dead helper
  // that reconstructs that mistake is an invitation to re-adopt it, and it was also the
  // source of a CodeQL `js/incomplete-sanitization` alert (it escaped `.` but not `\`).
  // Index on invocations; do not reintroduce a source-position helper.

  test("the birth gate is sourced BEFORE the stock preflight", () => {
    // Order is load-bearing: the birth gate proves the plan IS the scoped birth, the
    // preflight proves it is FEASIBLE. Reversed, an out-of-scope plan would be stock-
    // checked before anyone asked whether it was the right plan.
    // Compares INVOCATIONS. MEASURED: leaving both `source` lines in place and swapping
    // only the two `if ! …_gate tfplan.json` blocks so the preflight runs first left the
    // suite green — the source-position form pinned definition order, which is inert.
    const birthAt = jobBlock.search(/^\s*if ! git_data_host_birth_gate\b/m);
    const stockAt = jobBlock.search(/^\s*if ! stock_preflight_gate\b/m);
    expect(birthAt).toBeGreaterThan(-1);
    expect(stockAt).toBeGreaterThan(-1);
    expect(birthAt).toBeLessThan(stockAt);
  });

  test("BOTH interlocks run BEFORE the terraform plan", () => {
    const interlockAt = jobBlock.search(/^\s*if ! git_data_birth_readiness_gate\b/m);
    // #6982 A3's rung-2 gate is the second hold and had no ordering pin. A gate that runs
    // after the plan still lets a held route pay for a plan and read a secret before it
    // refuses, which is the cost the first gate's placement comment exists to avoid.
    const rung2At = jobBlock.search(/^\s*if ! git_data_rung2_rehearsal_gate\b/m);
    // `terraform plan` WITH its flags — the invocation, not the words. The job header
    // comment contains the bare phrase. (I hit exactly this writing the rung-2 pin: an
    // unanchored /terraform plan/ matched the header comment and the assertion inverted.)
    const planAt = jobBlock.search(/^\s*terraform plan -no-color/m);
    expect(interlockAt).toBeGreaterThan(-1);
    expect(rung2At).toBeGreaterThan(-1);
    expect(planAt).toBeGreaterThan(-1);
    // The third interlock (#8009) is static -- it reads Terraform SOURCE, never a plan -- so
    // it can and must refuse before any provider is contacted, exactly like its two siblings.
    const authmapAt = jobBlock.search(/^\s*git_data_authorization_map_gate\b/m);
    expect(authmapAt).toBeGreaterThan(-1);
    expect(interlockAt).toBeLessThan(planAt);
    expect(rung2At).toBeLessThan(planAt);
    expect(authmapAt).toBeLessThan(planAt);
    // A job-level continue-on-error would make all three interlocks non-blocking at once,
    // outside every step body the per-step loop inspects.
    expect(jobBlock).not.toMatch(/^\s{4}continue-on-error:/m);
  });

  test("git_data_host_replace ALSO carries the authorization-map interlock (#8009 D9)", () => {
    // D9. user_data is ForceNew and ADR-115 bars git-data from the reboot primitive, so
    // after the birth a REPLACE is the ONLY route by which a re-rendered authorized_keys
    // block reaches the host. The realistic incident is therefore not a collapsed BIRTH --
    // that fires once, ever -- but a collapsed REPLACE, on the path with no human approver.
    //
    // The limitation ships stated rather than implied, here and in the step's own ::error::
    // and the runbook.
    //
    // (#8209, ADR-241 D2) UPDATED. This job used to carry no `environment:` and therefore no
    // deployment_branch_policy, so a workflow_dispatch ran the SELECTED REF's scripts and the
    // gate was supplied by the branch it polices. The "fleet-wide policy call" this comment
    // deferred has now been made: the five replace-class targets carry
    // `environment: infra-privileged`, pinned to `main`, so a non-main dispatch is refused
    // before the job starts. The limitation is NARROWED, not removed — a deliberate actor who
    // can land a commit on `main` still reaches it — which is why the assertion below still
    // pins that the message says so.
    const replaceBlock = extractJobBlock(wf, "git_data_host_replace");
    expect(replaceBlock).toMatch(
      /^\s*git_data_authorization_map_gate "\$\{GITHUB_WORKSPACE\}\/[^"]+" \|\| rc=\$\?$/m,
    );
    expect(replaceBlock).toMatch(/^\s*if \[\[ "\$rc" -eq 2 \]\]; then$/m);
    expect(replaceBlock).toMatch(/COULD NOT MEASURE/);
    const step = /- name: Authorization-map interlock[\s\S]*?(?=\n      - name: )/.exec(
      replaceBlock,
    );
    expect(step, "Authorization-map interlock step not found in git_data_host_replace").not.toBeNull();
    expect(step![0]).not.toMatch(/^\s*if:/m);
    expect(step![0]).not.toMatch(/continue-on-error/);
    expect(step![0]).toMatch(/^\s*exit 1$/m);
    // The stated limitation is part of the contract, not decoration: a future edit that
    // silently drops it would leave the gate implying protection it does not have.
    expect(step![0]).toMatch(/does NOT hold against a deliberate actor/);

    // ORDERING, NOT JUST PRESENCE. The birth job pins authmapAt < planAt; this job pinned
    // only that the step EXISTS. Measured: moving the interlock below `Terraform apply
    // (git-data-host -replace)` left this suite 194/0 green — so on the one path with no
    // human approver, the gate could run after the host had already been replaced with the
    // collapsed map. A gate that refuses after the fact is not a gate.
    const rAuthmap = replaceBlock.search(/^\s*git_data_authorization_map_gate\b/m);
    const rPlan = replaceBlock.search(/^\s*terraform plan -no-color/m);
    const rApply = replaceBlock.search(/^\s*terraform apply -no-color/m);
    expect(rAuthmap).toBeGreaterThan(-1);
    expect(rPlan).toBeGreaterThan(-1);
    expect(rApply).toBeGreaterThan(-1);
    expect(rAuthmap).toBeLessThan(rPlan);
    expect(rAuthmap).toBeLessThan(rApply);

    // H2 — A JOB-LEVEL `continue-on-error` DISARMS ALL THREE INTERLOCKS AT ONCE, and it
    // sits outside every step body the assertions above read. The step-level loop claims to
    // pin "the three ways" a step can be disarmed; this is a fourth, one level up.
    expect(replaceBlock).not.toMatch(/^\s{4}continue-on-error:/m);

    // H3 — `exit 1` PRESENCE IS NOT REACHABILITY. A real `exit 1` parked in an unrelated
    // later branch of the same step satisfies /^\s*exit 1$/m while the gate's own failure
    // branch merely echoes. Pin that the non-zero exit is INSIDE the refusal branch.
    expect(step![0]).toMatch(
      /if \[\[ "\$rc" -ne 0 \]\]; then\n\s*echo "::error::[\s\S]*?\n\s*exit 1\n/,
    );
  });

  test("git_data_host_replace ALSO carries the rung-2 rehearsal interlock (#8210)", () => {
    // Until #8210 only git_data_host_create called this gate, so an un-rehearsed cloud-init
    // payload could reach the LIVE host by replace from any ref — the route that creates the
    // store was held while the route that REPLACES it was not. That asymmetry is load-bearing
    // now for the same reason D9 above is: user_data is ForceNew and ADR-115 bars git-data from
    // the reboot primitive, so a replace is the ONLY route by which a payload change (including
    // a boot-time control like the LUKS reopen) reaches the host, and it re-runs first boot
    // there. An un-rehearsed template's first real boot would be on the production host.
    const replaceBlock = extractJobBlock(wf, "git_data_host_replace");
    expect(replaceBlock).toMatch(
      /^\s*if ! git_data_rung2_rehearsal_gate "\$\{GITHUB_WORKSPACE\}\/[^"]+"; then/m,
    );

    // The same three disarm shapes the sibling interlocks are pinned against: an `if:` on the
    // step, a continue-on-error, or a refusal branch that echoes without exiting.
    const step = /- name: Rung-2 rehearsal interlock[\s\S]*?(?=\n      - name: )/.exec(
      replaceBlock,
    );
    expect(step, "Rung-2 rehearsal interlock step not found in git_data_host_replace").not.toBeNull();
    expect(step![0]).not.toMatch(/^\s*if:/m);
    expect(step![0]).not.toMatch(/continue-on-error/);
    expect(step![0]).toMatch(
      /if ! git_data_rung2_rehearsal_gate[\s\S]*?\n\s*echo "::error::[\s\S]*?\n\s*exit 1\n/,
    );

    // THE CHECKOUT DEPTH IS PART OF THE INTERLOCK. Guard 4 reads the evidence file's commit
    // provenance and HOLDs on a shallow clone; actions/checkout is depth-1 unless the step
    // sets fetch-depth: 0. The create job has carried it since #8043; the review of #8210 found
    // the interlock copied onto this job WITHOUT it, which held the replace route permanently
    // — "until PM2" in every document, forever in fact. Pinned as the FIRST checkout step of
    // the job carrying `fetch-depth: 0` under `with:`.
    const replaceCheckout = /- uses: actions\/checkout@[0-9a-f]+[^\n]*\n((?:\s{8,}[^\n]*\n)*)/.exec(
      replaceBlock,
    );
    expect(replaceCheckout, "checkout step not found in git_data_host_replace").not.toBeNull();
    expect(replaceCheckout![1]).toMatch(/^\s*fetch-depth:\s*0\s*$/m);

    // ORDERING. A gate that runs after the plan lets a held route pay for a plan and read a
    // secret before refusing; after the apply it is not a gate at all.
    const rRung2 = replaceBlock.search(/^\s*if ! git_data_rung2_rehearsal_gate\b/m);
    const rPlan = replaceBlock.search(/^\s*terraform plan -no-color/m);
    const rApply = replaceBlock.search(/^\s*terraform apply -no-color/m);
    expect(rRung2).toBeGreaterThan(-1);
    expect(rRung2).toBeLessThan(rPlan);
    expect(rRung2).toBeLessThan(rApply);
  });

  test("the job carries the environment gate and reads HCLOUD_TOKEN for the preflight", () => {
    // `\s{4}` pins JOB-level indentation, matching both web precedents. `\s*` would
    // accept a step-level `environment:` at six spaces, which GitHub ignores — so the
    // assertion on the sole human authorization would no longer prove it is job-scoped.
    expect(jobBlock).toMatch(/^\s{4}environment:\s*web-platform-infra-apply\s*$/m);
    // The sourced stock gate runs OUTSIDE the `doppler run` wrapper, and this step's env:
    // is DOPPLER_TOKEN only. Without this read the gate fails closed on EVERY dispatch —
    // an outage, not a tripwire.
    expect(jobBlock).toMatch(/^\s*export HCLOUD_TOKEN\s*$/m);
  });

  test("the gate's allow-set matches the job's -target set exactly", () => {
    const gateSrc = readFileSync(
      resolve(REPO_ROOT, "tests/scripts/lib/git-data-host-birth-gate.sh"),
      "utf8",
    );
    // The UNPARAMETERIZED extractor. This gate is a SINGLETON, so it carries `def allow:`
    // with no key argument and its members contain no `[`/`]` — unlike
    // web-host-birth-gate.sh, whose `def allow($k):` members embed `[\"\($k)\"]` and
    // therefore need the `\n];`-terminated form. Using the web extractor here would match
    // nothing; using this one there would stop at the first `]` inside a member.
    const defAllow = /def allow:\s*\[([^\]]+)\]/.exec(gateSrc);
    expect(defAllow).not.toBeNull();
    const gateBases = [
      ...new Set(
        [...defAllow![1].matchAll(/"([^"]+)"/g)]
          .map((m) => m[1])
          .filter((a) => /^[a-z0-9_]+\.[a-z0-9_]+$/.test(a)),
      ),
    ].sort();
    // Non-vacuity: the extraction must actually find the members.
    expect(gateBases.length).toBeGreaterThan(10);
    expect(gateBases.length).toBe(GIT_DATA_BIRTH_TARGET_BASES.length);
    expect(gateBases).toEqual([...GIT_DATA_BIRTH_TARGET_BASES].sort());
  });
});

// ─── apply_target enum <-> field-label parity (#6977, cto F2) ──────────────────
//
// The `description:` is the FIELD LABEL a non-technical operator reads above the
// dropdown. It enumerated the selectable targets by hand, and drifted: it advertised
// `registry-ruleset-entrypoint-audit`, which is NOT selectable — the option is
// `entrypoint-audit`. An operator following the label would look for an option that does
// not exist. That is the second time this class of rot has been paid for here, so it is
// pinned rather than fixed again.
describe("apply_target enum <-> description parity (#6977)", () => {
  test("every target-shaped token in the description is a real enum option", () => {
    const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    const block = /apply_target:[\s\S]*?options:([\s\S]*?)\n\nconcurrency:/.exec(wf);
    expect(block).not.toBeNull();
    const options = [...block![1].matchAll(/^\s*-\s+([a-z0-9-]+)\s*$/gm)].map(
      (m) => m[1],
    );
    expect(options.length).toBeGreaterThan(10);

    const desc = /apply_target:[\s\S]*?description:\s*>-\n([\s\S]*?)\n\s{8}required:/.exec(wf);
    expect(desc).not.toBeNull();
    // Split on `|`, the separator the label itself uses, then take the FIRST token in each
    // segment that LOOKS like a target (kebab-case with at least one hyphen). Prose words
    // are single tokens without hyphens and drop out.
    //
    // Taking the first KEBAB-MATCHING token, not simply the first token: the opening
    // segment is `Which apply path? manual-rerun (default)`, so a first-token rule yields
    // the prose word "Which", fails the kebab filter, and drops the segment entirely.
    // That silently exempted `manual-rerun` — the DEFAULT option, and so the single member
    // likeliest to matter — from the phantom check, while a comment here claimed it
    // "keeps its leading token". A member that is never examined is indistinguishable
    // from one that passes.
    const kebab = /^[a-z0-9]+(-[a-z0-9]+)+$/;
    const cited = [
      ...new Set(
        desc![1]
          .split("|")
          .map((seg) => seg.trim().split(/[\s.,]/).find((t) => kebab.test(t)))
          .filter((t): t is string => t !== undefined),
      ),
    ];
    // Non-vacuity: the label must genuinely cite targets, else this asserts nothing.
    expect(cited.length).toBeGreaterThan(5);
    // Pin the fix above: the default option must actually be among the cited set.
    expect(cited).toContain("manual-rerun");
    const phantom = cited.filter((t) => !options.includes(t));
    expect(phantom).toEqual([]);

    // The converse direction. Phantom-checking alone is one-way: it catches a label that
    // cites a target the enum lacks, but not an option ADDED to the enum and never
    // documented — the likelier drift, since the enum is what the dispatch UI reads.
    // Word-boundary match, because `inngest-host` is a prefix of `inngest-host-replace`
    // and a substring test would let the shorter one ride on the longer one's mention.
    const undocumented = options.filter(
      (opt) => !new RegExp(`(?<![\\w-])${opt}(?![\\w-])`).test(desc![1]),
    );
    expect(undocumented).toEqual([]);
  });
});

// ============================================================================================
// #7586 / #7587 — the apply workflow's FAILURE CHANNEL and its ARM-gate BUDGET.
//
// These two describes are co-located here rather than in a new suite because this file already
// owns this workflow's channel invariant (the `#7539` green-skip describe above) and its
// `extractJobBlock` / `extractStep` helpers. See the header note at the top of the file.
//
// Both guards share one anti-vacuity helper so "the guard must not pass on an empty scan" is
// asserted once per guard rather than restated as four separate rows.
// ============================================================================================

/**
 * Anti-vacuity floor. A guard that scanned zero subjects and exited clean is indistinguishable
 * from a guard over a healthy repo — this is the difference. Every scan below routes through it.
 */
function expectNonEmptyDispatch(count: number, min = 1): void {
  expect(count).toBeGreaterThanOrEqual(min);
}

// --- A small GitHub-expression evaluator ------------------------------------------------------
//
// The guard EVALUATES the predicate; it does not string-match it. A canonical-string match makes
// harness row H2 (operand reordering, semantics identical) fail BY CONSTRUCTION, while a
// token-presence check passes mutation rows 1/3/4 over a semantically broken predicate. So the
// `if:` expression is parsed and run over the full cross product of conclusions and triggers, and
// the truth table is what is asserted.
//
// `==` is deliberately GitHub's LOOSE equality, not `===`: when the operand types differ Actions
// casts both to Number, which is how an unset output (`null`) compares EQUAL to `'0'`. Nothing in
// this predicate depends on that, but an evaluator that quietly used strict equality would be
// modelling a different language than the one the runner executes.

type GhVal = string | number | boolean | null;

function ghToNumber(v: GhVal): number {
  if (v === null) return 0;
  if (typeof v === "boolean") return v ? 1 : 0;
  if (typeof v === "number") return v;
  if (v.trim() === "") return 0;
  return Number(v);
}

function ghEquals(a: GhVal, b: GhVal): boolean {
  if (typeof a === typeof b && a !== null && b !== null) {
    if (typeof a === "string") return a.toLowerCase() === (b as string).toLowerCase();
    return a === b;
  }
  const x = ghToNumber(a);
  const y = ghToNumber(b);
  if (Number.isNaN(x) || Number.isNaN(y)) return false;
  return x === y;
}

type Tok = { t: "op" | "str" | "path" | "fn"; v: string };

function tokenizeGh(src: string): Tok[] {
  const out: Tok[] = [];
  let i = 0;
  while (i < src.length) {
    const c = src[i];
    if (/\s/.test(c)) {
      i++;
      continue;
    }
    const two = src.slice(i, i + 2);
    if (two === "&&" || two === "||" || two === "==" || two === "!=") {
      out.push({ t: "op", v: two });
      i += 2;
      continue;
    }
    if (c === "(" || c === ")" || c === "!") {
      out.push({ t: "op", v: c });
      i++;
      continue;
    }
    if (c === "'") {
      let j = i + 1;
      let s = "";
      while (j < src.length) {
        if (src[j] === "'" && src[j + 1] === "'") {
          s += "'";
          j += 2;
          continue;
        }
        if (src[j] === "'") break;
        s += src[j];
        j++;
      }
      if (j >= src.length) throw new Error(`unterminated string literal in: ${src}`);
      out.push({ t: "str", v: s });
      i = j + 1;
      continue;
    }
    const m = /^[A-Za-z_][A-Za-z0-9_.-]*/.exec(src.slice(i));
    if (!m) throw new Error(`unexpected character '${c}' in: ${src}`);
    i += m[0].length;
    if (src[i] === "(") {
      const close = src.indexOf(")", i);
      if (close === -1) throw new Error(`unterminated call ${m[0]}( in: ${src}`);
      // Only zero-argument status functions appear in this repo's job-level predicates. A call
      // with arguments would be silently mis-parsed, so refuse it rather than guess.
      if (src.slice(i + 1, close).trim() !== "") {
        throw new Error(`unsupported call with arguments: ${m[0]}(...)`);
      }
      out.push({ t: "fn", v: m[0] });
      i = close + 1;
      continue;
    }
    out.push({ t: "path", v: m[0] });
  }
  return out;
}

/**
 * Evaluate a GitHub job-level `if:` expression.
 *
 * `ctx` maps context paths (`github.event_name`, `needs.apply.result`, …) to values; an
 * unknown path resolves to `null`, exactly as a missing context does on the runner.
 *
 * Status functions are resolved from `jobStatus`. Any function this evaluator does not model
 * THROWS rather than defaulting — a guard that silently treats an unmodelled function as `true`
 * would report a truth table for an expression nobody wrote.
 */
function evalGhIf(src: string, ctx: Record<string, GhVal>): boolean {
  const toks = tokenizeGh(src);
  let p = 0;
  const peek = (): Tok | undefined => toks[p];
  const eat = (v: string): boolean => {
    if (toks[p] && toks[p].t === "op" && toks[p].v === v) {
      p++;
      return true;
    }
    return false;
  };

  const primary = (): GhVal => {
    const t = peek();
    if (!t) throw new Error(`unexpected end of expression in: ${src}`);
    if (t.t === "op" && t.v === "(") {
      p++;
      const v = orExpr();
      if (!eat(")")) throw new Error(`missing ')' in: ${src}`);
      return v;
    }
    if (t.t === "op" && t.v === "!") {
      p++;
      return !truthy(primary());
    }
    if (t.t === "str") {
      p++;
      return t.v;
    }
    if (t.t === "fn") {
      p++;
      // `always()` is the only status function these predicates use. Everything else — including
      // `success()`, `failure()` and `cancelled()` — is refused rather than guessed at, because a
      // job-level predicate carrying one would need the whole workflow's status to evaluate.
      if (t.v === "always") return true;
      throw new Error(`unmodelled status function ${t.v}() in: ${src}`);
    }
    p++;
    return Object.prototype.hasOwnProperty.call(ctx, t.v) ? ctx[t.v] : null;
  };

  const truthy = (v: GhVal): boolean => {
    if (typeof v === "boolean") return v;
    if (v === null) return false;
    if (typeof v === "number") return v !== 0;
    return v !== "";
  };

  const cmpExpr = (): GhVal => {
    const left = primary();
    const t = peek();
    if (t && t.t === "op" && (t.v === "==" || t.v === "!=")) {
      p++;
      const right = primary();
      const eq = ghEquals(left, right);
      return t.v === "==" ? eq : !eq;
    }
    return left;
  };

  const andExpr = (): GhVal => {
    let v = cmpExpr();
    while (eat("&&")) {
      const r = cmpExpr();
      v = truthy(v) ? r : v;
    }
    return v;
  };

  const orExpr = (): GhVal => {
    let v = andExpr();
    while (eat("||")) {
      const r = andExpr();
      v = truthy(v) ? v : r;
    }
    return v;
  };

  const result = orExpr();
  if (p !== toks.length) throw new Error(`trailing tokens in: ${src}`);
  return truthy(result);
}

// --- Guard 1: a non-green apply run has a channel (#7586) ---------------------------------------

const NOTIFY_JOB_ID = "notify-apply-failure";
const CONCLUSIONS = ["success", "failure", "cancelled", "skipped"] as const;

/** The three trigger shapes the workflow can present to this job. */
const TRIGGERS: Array<{ name: string; event: string; target: GhVal }> = [
  { name: "push", event: "push", target: null },
  { name: "manual-rerun", event: "workflow_dispatch", target: "manual-rerun" },
  { name: "other-dispatch", event: "workflow_dispatch", target: "inngest-host" },
];

/**
 * The PROPERTY, written independently of the implementation: every run in which the `apply` job
 * does not reach `success`, and every run in which `apply` is skipped because `preflight` did not
 * succeed, must reach the notification — on the merge path AND on the manual-rerun recovery path
 * the email itself prescribes.
 */
function channelShouldFire(preflight: string, apply: string, event: string, target: GhVal): boolean {
  const onACoveredTrigger = event === "push" || target === "manual-rerun";
  const everythingIsFine = preflight === "success" && (apply === "success" || apply === "skipped");
  return onACoveredTrigger && !everythingIsFine;
}

/** Evaluate a candidate predicate over the whole cross product; return the rows it gets wrong. */
function channelTruthTableViolations(ifExpr: string): string[] {
  const bad: string[] = [];
  let rows = 0;
  for (const trigger of TRIGGERS) {
    for (const preflight of CONCLUSIONS) {
      for (const apply of CONCLUSIONS) {
        rows++;
        const actual = evalGhIf(ifExpr, {
          "github.event_name": trigger.event,
          "inputs.apply_target": trigger.target,
          "needs.preflight.result": preflight,
          "needs.apply.result": apply,
        });
        const want = channelShouldFire(preflight, apply, trigger.event, trigger.target);
        if (actual !== want) {
          bad.push(`${trigger.name}/preflight=${preflight}/apply=${apply}: got ${actual}, want ${want}`);
        }
      }
    }
  }
  expectNonEmptyDispatch(rows, CONCLUSIONS.length * CONCLUSIONS.length * TRIGGERS.length);
  return bad;
}

/**
 * The full verdict over a workflow's TEXT, so the mutation rows can feed it a fixture with the
 * job deleted (row 2 / H1) rather than only a mutated predicate.
 *
 * `needs` is pinned INSIDE the same verdict that quantifies over it. Quantifying over `needs:`
 * alone is not enough: shrinking the array would shrink the obligation, so an edit that drops
 * `preflight` from BOTH `needs:` and the predicate would satisfy a `needs:`-relative guard while
 * restoring the exact defect row 3 exists to catch (mutation row 5).
 */
function channelGuardViolations(wfText: string): string[] {
  const doc = parseYaml(wfText) as {
    jobs?: Record<string, { needs?: string[] | string; if?: string }>;
  };
  const job = doc.jobs?.[NOTIFY_JOB_ID];
  if (!job) return [`no \`${NOTIFY_JOB_ID}\` job — the workflow has no failure channel at all`];
  if (typeof job.if !== "string" || job.if.trim() === "") {
    return [`\`${NOTIFY_JOB_ID}\` declares no \`if:\``];
  }
  const needs = Array.isArray(job.needs) ? job.needs : job.needs ? [job.needs] : [];
  const out: string[] = [];
  if (JSON.stringify(needs) !== JSON.stringify(["preflight", "apply"])) {
    out.push(`needs is ${JSON.stringify(needs)}, expected ["preflight","apply"]`);
  }
  out.push(...channelTruthTableViolations(job.if));
  return out;
}

describe("apply-web-platform-infra has a failure channel", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const doc = parseYaml(wf) as {
    jobs?: Record<
      string,
      {
        needs?: string[];
        if?: string;
        "timeout-minutes"?: number;
        permissions?: Record<string, string>;
        steps?: Array<Record<string, unknown>>;
      }
    >;
  };
  const job = doc.jobs?.[NOTIFY_JOB_ID];

  test("the job exists, and its predicate is CORRECT over the whole conclusion x trigger space", () => {
    expect(job).toBeDefined();
    expect(channelGuardViolations(wf)).toEqual([]);
  });

  test("AC1: budget, permissions and the `needs:` pin", () => {
    // EXACTLY 5, not "<= 10" (#7661 G7). The run-level mutex sum appears in three comments in this
    // file; raising this job to 10 kept a `toBeLessThanOrEqual` guard green while falsifying all
    // three at once. The sum itself is re-derived in the ladder describe.
    expect(job!["timeout-minutes"]).toBe(5);
    // A job-level `permissions:` block REPLACES the workflow-level one, so `contents: read` must
    // be re-declared alongside the grant this job adds. EXHAUSTIVE, not `toMatchObject` (#7661 G9):
    // a subset matcher passes on `{contents:"read",actions:"read","id-token":"write"}`, so a later
    // edit widening the grant would not red. The sibling AC2/AC9 test already uses this shape.
    expect(job!.permissions).toEqual({ contents: "read", actions: "read" });
    expect(job!.needs).toEqual(["preflight", "apply"]);
  });

  test("AC2: every step is NAMED, and EVERY step runs on every path the job fires on", () => {
    const steps = job!.steps ?? [];
    expectNonEmptyDispatch(steps.length, 2);
    // `extractStep` matches `^ {6}- name:`, so an unnamed step is invisible to this suite and
    // nothing about it could be asserted. `uses:`-only checkout is the one exception.
    const named = steps.filter((s) => typeof s.name === "string");
    expectNonEmptyDispatch(named.length, 2);
    const email = steps.find((s) => s.uses === "./.github/actions/notify-ops-email");
    expect(email).toBeDefined();
    const cause = steps.find((s) => s.id === "cause");
    expect(cause).toBeDefined();

    // #7654 A1. A step with no `if:` carries an implicit `success()`. `continue-on-error` changes
    // the OUTCOME of the step it sits on; it does not gate the step. So without `always()` here, a
    // failed checkout or a failed `cause` step SKIPS the email and the red run notifies nobody —
    // the Cut List C1 lesson this job's own header cites, repeated one level down.
    for (const s of [cause!, email!]) {
      expect(typeof s.if === "string" && /\balways\(\)/.test(s.if as string)).toBe(true);
    }

    // #7654 A2. NOT `continue-on-error`. `notify-ops-email` already collapses every non-2xx from
    // Resend into a `::warning::` and exits 0, so the stated rationale ("a Resend outage must not
    // red an already-red run") was protecting against nothing. What it DID suppress is the
    // composite's only hard failure — a missing `RESEND_API_KEY` — which is the one case where
    // this job's conclusion can distinguish "the alarm fired" from "the alarm silently did not".
    expect(email!["continue-on-error"]).toBeUndefined();
  });

  test("AC2d: the composite's only hard-fail branch is a MISSING KEY, so suppressing it is the loss", () => {
    // The A2 assertion above is only meaningful if the composite really does exit 0 on a non-2xx
    // and non-zero on an unset key. Read it rather than assume it.
    const composite = readFileSync(
      resolve(REPO_ROOT, ".github/actions/notify-ops-email/action.yml"),
      "utf8",
    );
    expectNonEmptyDispatch(composite.length, 1);
    expect(composite).toMatch(/RESEND_API_KEY[\s\S]{0,200}?exit 1/);
    expect(composite).toMatch(/HTTP_CODE[\s\S]{0,400}?::warning::/);
  });

  test("AC2b: no `run:` body in this job contains `terraform apply` or `-target=`", () => {
    // LOAD-BEARING, not stylistic. The predicate names `manual-rerun`, so
    // stock-preflight-coverage.test.ts's `jobFor("manual-rerun")` now returns TWO hits and
    // disambiguates them with `appliesTerraform`, which greps exactly these two tokens over
    // `run:` bodies. A `run:`-built email body mentioning either makes that suite red — and the
    // "what did NOT land" prose is precisely the text most likely to contain them.
    const runs = (job!.steps ?? []).map((s) => (typeof s.run === "string" ? s.run : "")).join("\n");
    expectNonEmptyDispatch(runs.length, 1);
    expect(runs).not.toMatch(/\bterraform\s+apply\b/);
    expect(runs).not.toContain("-target=");
  });

  test("AC2c: the cause token is shape-validated with a STATED shape, and written under a random delimiter", () => {
    const cause = (job!.steps ?? []).find((s) => s.id === "cause");
    expect(cause).toBeDefined();
    const body = String(cause!.run ?? "");
    expectNonEmptyDispatch(body.length, 1);
    // Errexit is inherited from `/usr/bin/bash -e {0}`; this body reads exit statuses as DATA.
    expect(body).toMatch(/^\s*set \+e\s*$/m);
    expect(body).toMatch(/tr -d '\\r\\n'/); // 1. CR/LF stripped outright
    // 2. the ONE non-ASCII character this workflow's step names use is transliterated before a
    // byte-wise `tr -cd` can shred it (#7655 B8: `unpause→verify-status→rollback` became
    // `unpauseverify-statusrollback`, a non-word, on exactly the step this job most expects to
    // print). `,` and `#` are in the keep-set for the same reason and are inert after the escape.
    expect(body).toMatch(/sed 's\/→\/->\/g'/);
    expect(body).toMatch(/tr -cd 'A-Za-z0-9 \._:\(\)\/,#-'/); // 3. charset clamped
    expect(body).toMatch(/cut -c1-80/); // 4. length clamped
    // 4. HTML-escaped before it reaches Resend's `html` field.
    expect(body).toContain("&amp;");
    expect(body).toContain("&lt;");
    expect(body).toContain("&gt;");
    // 5. A RANDOM heredoc delimiter — a fixed one is forgeable by a value containing it.
    expect(body).toMatch(/delim=.*(openssl rand|RANDOM)/);
    expect(body).toMatch(/failing_step<<%s/);
    // It must NOT try to read `apply` step outputs: that job declares no `outputs:`.
    expect(body).not.toContain("needs.apply.outputs");
  });

  /** The `case "$swept"` table that resolves the sweep prose, as {value: sentence}. */
  function sweepArms(causeBody: string): Record<string, string> {
    const out: Record<string, string> = {};
    for (const m of causeBody.matchAll(/^\s*([a-z|*]+)\)\s*\n\s*sweep_msg='([\s\S]*?)' ;;/gm)) {
      for (const v of m[1].split("|")) out[v] = m[2];
    }
    return out;
  }

  test("AC2: the email body carries the four elements a non-technical reader needs", () => {
    const email = (job!.steps ?? []).find((s) => s.uses === "./.github/actions/notify-ops-email");
    const withBlock = email!.with as Record<string, string>;
    const body = withBlock.body;
    expectNonEmptyDispatch(body.length, 1);

    // (1) The what-to-do prose is resolved in the `cause` step, so what the BODY must carry is the
    // interpolation — and the branch itself is asserted below, on the table.
    expect(body).toContain("steps.cause.outputs.action_msg");
    // (2) The failing step's name.
    expect(body).toContain("steps.cause.outputs.failing_step");
    // (3) Whether uptime alerting may be paused — both the machine value and the prose.
    expect(body).toContain("steps.cause.outputs.sweep_conclusion");
    expect(body).toContain("steps.cause.outputs.sweep_msg");
    expect(body).toMatch(/uptime (monitors?|alerting)/i);
    // (4) That the previously-applied infrastructure is still serving.
    expect(body).toMatch(/still serving/i);
    // …plus a runnable recovery command, not a pointer to one.
    expect(body).toContain("gh workflow run apply-web-platform-infra.yml");
    expect(body).toContain("apply_target=manual-rerun");
    // …and a lever the TARGET OPERATOR can actually pull (#7655 B7). `gh workflow run` needs the
    // GitHub CLI installed and authenticated with `workflow` scope; the audience for this email
    // is non-technical, and one click from the run URL the email already prints does the job.
    expect(body).toMatch(/Re-run failed jobs/i);
    expect(body).toMatch(/Actions/);
  });

  test("AC7: EVERY value `sweep_conclusion` can take has its own sentence (#7655 B1)", () => {
    // The producer enumerates four values plus a floor; the body branched on TWO, so `cancelled`,
    // `skipped` and `unknown` all landed in "the sweep did not run, so nothing was left
    // half-armed". `cancelled` is precisely the state where the sweep was cut mid-loop and
    // monitors ARE live-and-unfed, and `unknown` is reached when the jobs API read FAILED — the
    // same step that emits `::warning::Could not read the jobs API` then asserted, two elements
    // later, a fact it had just said it could not read. AP-021.
    const cause = (job!.steps ?? []).find((s) => s.id === "cause");
    const causeBody = String(cause!.run ?? "");
    const arms = sweepArms(causeBody);

    // The producer's own enumeration, read from the validating `case` rather than restated.
    const validated = /case "\$swept" in\s*\n\s*([a-z|]+)\)/.exec(causeBody);
    expect(validated).not.toBeNull();
    const values = [...validated![1].split("|"), "*"];
    expect(values.sort()).toEqual(["*", "cancelled", "failure", "skipped", "success"]);
    expectNonEmptyDispatch(Object.keys(arms).length, 5);
    for (const v of values) expect(Object.keys(arms)).toContain(v);

    // No sentence may assert a fact the job did not MEASURE. The retired branch read "The
    // heartbeat re-pause sweep did not run, so nothing was left half-armed by it."
    for (const v of ["cancelled", "*"]) {
      expect(arms[v]).not.toMatch(/nothing was left half-armed/i);
    }
    expect(arms.cancelled).not.toMatch(/did not run/i);
    // The `unknown` arm may only mention "did not run" to DENY that it means that.
    expect(arms["*"]).toMatch(/not the same as saying it did not run/i);
    // `cancelled` must name the live-and-unfed risk, not reassure.
    expect(arms.cancelled).toMatch(/CUT OFF|cut off/);
    expect(arms.cancelled).toMatch(/switched ON|live/i);
    // `unknown` must say it could not find out — which is a different fact from "it did not run".
    expect(arms["*"]).toMatch(/could not find out|cannot tell you/i);
  });

  test("AC7b: the branch that calls an item URGENT prescribes a lever that can clear it (#7655 B4)", () => {
    // The only action the email offered was `gh workflow run … manual-rerun`, and on the next run
    // `arm_one`'s op/state gate no-ops any monitor that is not `paused`. A live-and-unfed monitor
    // is not `paused`, so the prescribed lever provably cannot re-pause the thing the email calls
    // the one urgent item.
    const cause = (job!.steps ?? []).find((s) => s.id === "cause");
    const arms = sweepArms(String(cause!.run ?? ""));
    for (const v of ["failure", "cancelled"]) {
      expect(arms[v]).toMatch(/Better Stack/);
      expect(arms[v]).toMatch(/Pause/);
      expect(arms[v]).not.toMatch(/manual-rerun/);
    }
    // …and the `failure` arm says outright that the re-run will not fix it.
    expect(arms.failure).toMatch(/will NOT clear it|not fix it/i);

    // The premise: the gate really does skip a non-paused monitor.
    const script = readFileSync(resolve(INFRA_DIR, "arm-heartbeats.sh"), "utf8");
    expect(script).toMatch(/if \[\[ "\$HB_STATUS" != "paused" \]\]; then[\s\S]{0,200}?already armed/);
  });

  test("AC7c: the `success` arm describes work that the sweep actually does on its dominant path", () => {
    // The sweep's first line of work is an early exit, and it also concludes `success`. The old
    // prose told the operator that monitors "were switched back off" (none were switched on) and
    // that "the counts are in the run summary" (the summary heredoc was unreachable past the early
    // exit). The script now reports `outcome=noop` and WRITES the summary on that path, and the
    // sentence no longer claims work that did not happen (#7655 B2).
    const cause = (job!.steps ?? []).find((s) => s.id === "cause");
    const arms = sweepArms(String(cause!.run ?? ""));
    expect(arms.success).toMatch(/nothing to switch off in the first place/i);
    const script = readFileSync(resolve(INFRA_DIR, "arm-heartbeats.sh"), "utf8");
    expect(script).toMatch(/sweep_report 0 0 0 noop/);
  });

  test("AC7d: the what-to-do prose has a PREFLIGHT arm, not a two-way ternary (#7655 B5)", () => {
    // On a preflight failure `apply` is SKIPPED, the jobs API finds no `apply` steps, and
    // `failing_step` renders `unresolved` — while the two-armed ternary told the operator to read
    // "the step named above". One of the three modes this job exists to cover produced an
    // incoherent email.
    const cause = (job!.steps ?? []).find((s) => s.id === "cause");
    const causeBody = String(cause!.run ?? "");
    expect(causeBody).toMatch(/if \[\[ "\$\{PREFLIGHT_RESULT\}" != "success" \]\]; then/);
    expect(causeBody).toMatch(/elif \[\[ "\$\{APPLY_RESULT\}" == "cancelled" \]\]; then/);
    const arms = [...causeBody.matchAll(/action_msg='([\s\S]*?)'\n/g)].map((m) => m[1]);
    expect(arms.length).toBe(3);
    expect(arms[0]).toMatch(/BEFORE it applied anything/);
    expect(arms[0]).toMatch(/unresolved/);
    expect(arms[0]).not.toMatch(/step named above/);
    // …and the two context values it branches on reach it as env, never as shell interpolation.
    const env = (cause!.env ?? {}) as Record<string, string>;
    expect(env.PREFLIGHT_RESULT).toContain("needs.preflight.result");
    expect(env.APPLY_RESULT).toContain("needs.apply.result");
  });

  test("AC7e: the blast-radius sentence cannot be false on a partial apply (#7655 B6)", () => {
    // "soleur.ai and app.soleur.ai are unaffected by this" was unconditional. `terraform apply`
    // leaves already-applied resources applied, the per-merge allow-list includes
    // `cloudflare_record.app` and the zone/DNSSEC/firewall resources, and the backend has no state
    // lock — so a run cancelled mid-apply can also lose the state write-back. A false "nothing is
    // down" is worse than no email.
    const email = (job!.steps ?? []).find((s) => s.uses === "./.github/actions/notify-ops-email");
    const body = (email!.with as Record<string, string>).body;
    expect(body).not.toMatch(/are unaffected by this/);
    expect(body).toMatch(/leaves behind whatever\s*\n?\s*it had already created/);
    expect(body).toMatch(/before assuming\s*\n?\s*nothing moved/);
    // The premise: those resources really are in the per-merge target set.
    const applyBlock = extractJobBlock(readFileSync(WEB_PLATFORM_WORKFLOW, "utf8"), "apply");
    expect(applyBlock).toContain("cloudflare_record.app");
    // …and the backend really is unlocked, which is what makes the cancelled case sharper.
    expect(readFileSync(resolve(INFRA_DIR, "main.tf"), "utf8")).toMatch(/use_lockfile\s*=\s*false/);
  });

  test("AC2/AC9: the body's interpolations are an ALLOW-LIST, not whatever was to hand", () => {
    const email = (job!.steps ?? []).find((s) => s.uses === "./.github/actions/notify-ops-email");
    const body = (email!.with as Record<string, string>).body;
    const allowed = new Set([
      "github.sha",
      "github.run_id",
      "github.repository",
      "github.server_url",
      "needs.apply.result",
      "needs.preflight.result",
      "steps.cause.outputs.failing_step",
      "steps.cause.outputs.sweep_conclusion",
      "steps.cause.outputs.sweep_msg",
      "steps.cause.outputs.action_msg",
    ]);
    const refs = new Set<string>();
    for (const m of body.matchAll(/\$\{\{([\s\S]*?)\}\}/g)) {
      for (const r of m[1].matchAll(/\b(github|inputs|needs|steps|secrets|env|runner|job)\.[A-Za-z0-9_.]+/g)) {
        refs.add(r[0]);
      }
    }
    expectNonEmptyDispatch(refs.size, 4);
    // Never a raw step log, `curl` output or a shell trace: the ARM gate reads
    // BETTERSTACK_API_TOKEN and handles monitor ids, and terraform error strings carry resource
    // identifiers and Doppler variable names. The destination is a plaintext, no-expiry mailbox.
    expect([...refs].filter((r) => !allowed.has(r))).toEqual([]);
  });
});

describe("Guard 1 mutation battery (#7586)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const REAL = (parseYaml(wf) as { jobs: Record<string, { if: string }> }).jobs[NOTIFY_JOB_ID].if;

  /** A minimal workflow carrying only the job this guard is about. */
  function synthNotify(opts: { ifExpr?: string; needs?: string[]; omitJob?: boolean }): string {
    if (opts.omitJob) return "name: x\njobs:\n  apply:\n    runs-on: ubuntu-24.04\n";
    const needs = JSON.stringify(opts.needs ?? ["preflight", "apply"]);
    const expr = (opts.ifExpr ?? REAL).replace(/\n/g, " ");
    return [
      "name: x",
      "jobs:",
      "  apply:",
      "    runs-on: ubuntu-24.04",
      `  ${NOTIFY_JOB_ID}:`,
      `    needs: ${needs}`,
      `    if: ${JSON.stringify(expr)}`,
      "    runs-on: ubuntu-24.04",
      "",
    ].join("\n");
  }

  test("control: the REAL predicate, re-parsed through the synthetic shape, is clean", () => {
    // A red baseline would make every row below indistinguishable from a caught mutation.
    expect(channelGuardViolations(synthNotify({}))).toEqual([]);
  });

  test("M1 RED: `needs.apply.result == 'failure'` — the infra-validation precedent — is silent on cancelled", () => {
    const v = channelGuardViolations(synthNotify({ ifExpr: "always() && needs.apply.result == 'failure'" }));
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((s) => s.includes("apply=cancelled"))).toBe(true);
  });

  test("M2 RED: deleting the job leaves the guard with ZERO subjects, and it must say so", () => {
    const v = channelGuardViolations(synthNotify({ omitJob: true }));
    expect(v.length).toBeGreaterThan(0);
    expect(v[0]).toContain("no failure channel at all");
  });

  test("M3 RED: dropping the `needs.preflight.result` clause misses the red run that leaves apply SKIPPED", () => {
    const v = channelGuardViolations(
      synthNotify({
        ifExpr:
          "always() && (github.event_name == 'push' || inputs.apply_target == 'manual-rerun') && " +
          "!(needs.apply.result == 'success' || needs.apply.result == 'skipped')",
      }),
    );
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((s) => s.includes("preflight=failure") && s.includes("apply=skipped"))).toBe(true);
  });

  test("M4 RED: narrowing the trigger to `push` only leaves the manual-rerun recovery with no channel", () => {
    const v = channelGuardViolations(
      synthNotify({
        ifExpr:
          "always() && github.event_name == 'push' && " +
          "!(needs.preflight.result == 'success' && (needs.apply.result == 'success' || needs.apply.result == 'skipped'))",
      }),
    );
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((s) => s.startsWith("manual-rerun/"))).toBe(true);
  });

  test("M5 RED: dropping `preflight` from `needs:` AND its clause, in one edit, still reds", () => {
    // Without the `needs` pin this mutation reds NEITHER guard: the predicate would be
    // self-consistent with a shrunken `needs:` array, which is how the plan's own first draft
    // shipped the defect M3 exists to catch.
    const v = channelGuardViolations(
      synthNotify({
        needs: ["apply"],
        ifExpr:
          "always() && (github.event_name == 'push' || inputs.apply_target == 'manual-rerun') && " +
          "!(needs.apply.result == 'success' || needs.apply.result == 'skipped')",
      }),
    );
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((s) => s.includes("expected [\"preflight\",\"apply\"]"))).toBe(true);
  });

  test("H1 RED: a fixture with no notify job cannot go vacuously green", () => {
    expect(channelGuardViolations(synthNotify({ omitJob: true }))).not.toEqual([]);
  });

  test("H2 PASS: reordering the operands is semantics-preserving and MUST NOT red", () => {
    // The contract is the truth table, not a canonical byte string. A guard that only accepts the
    // shipped spelling rejects a correct implementation — which is why this guard evaluates.
    const reordered =
      "always() && " +
      "!((needs.apply.result == 'skipped' || needs.apply.result == 'success') && needs.preflight.result == 'success') && " +
      "(inputs.apply_target == 'manual-rerun' || github.event_name == 'push')";
    expect(channelGuardViolations(synthNotify({ ifExpr: reordered }))).toEqual([]);
  });
});

// --- Guard 2: the ARM gate's deadlines fit its job (#7587, re-derived #7657) --------------------

const ARM_SCRIPT = resolve(INFRA_DIR, "arm-heartbeats.sh");
const ARM_STATE_FILE_LITERAL = "$RUNNER_TEMP/armed-unconfirmed";
const SPEC_DIR_NAME = "feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline";

/**
 * Resolve the measurement log WITHOUT pinning it to its pre-archive path.
 *
 * `archive-kb` `git mv`s a finished spec directory to `specs/archive/<timestamp>-<name>/` as
 * routine housekeeping. A guard that hard-codes the live path therefore reds `main` the first time
 * anyone tidies up -- the guard breaks on a legitimate edit, which is the definition of a false
 * RED. Measured before this fix: archiving the directory took this suite from 177/0 to
 * 158 pass / 4 fail / 1 error, with 15 tests never reaching an assertion.
 *
 * Search the live path first, then the archive (suffix match, because the archive prefixes a
 * timestamp). Throw naming BOTH candidates if neither exists -- a missing pin must fail LOUD, never
 * fall back to a literal, because the whole point of the pin is that the ladder and the measurement
 * cannot drift apart.
 */
function resolveSpecMeasurements(): string {
  const live = resolve(REPO_ROOT, "knowledge-base/project/specs", SPEC_DIR_NAME, "measurements.md");
  if (existsSync(live)) return live;

  const archiveRoot = resolve(REPO_ROOT, "knowledge-base/project/specs/archive");
  if (existsSync(archiveRoot)) {
    const hit = readdirSync(archiveRoot)
      .filter((d) => d.endsWith(SPEC_DIR_NAME))
      .sort()
      .pop();
    if (hit) {
      const archived = resolve(archiveRoot, hit, "measurements.md");
      if (existsSync(archived)) return archived;
    }
  }

  throw new Error(
    `measurements.md not found for ${SPEC_DIR_NAME}: looked at ${live} and under ${archiveRoot}/*${SPEC_DIR_NAME}/. ` +
      `The LADDER-PIN values live there; the ladder guard cannot run without them.`,
  );
}

const SPEC_MEASUREMENTS = resolveSpecMeasurements();

/**
 * Identify the re-pause sweep WITHOUT keying on its step name — a rename is a legitimate edit and
 * would false-RED a name-keyed guard. (The step's name IS separately coupled to the `cause` step's
 * name-keyed jq filter, below; that is a different obligation and it fails CLOSED.)
 *
 * Both the ARM step and the sweep now invoke the same script, so "does not mention
 * arm-heartbeats.sh" no longer separates them. The discriminator is the MODE: `--sweep` vs `--arm`.
 */
function isSweepStep(s: Record<string, unknown>): boolean {
  return (
    typeof s.if === "string" &&
    /\balways\(\)/.test(s.if) &&
    typeof s.run === "string" &&
    s.run.includes(ARM_STATE_FILE_LITERAL) &&
    /arm-heartbeats\.sh"?\s+--sweep\b/.test(s.run)
  );
}

/**
 * A constant read OUT of the shipped script, never restated here.
 *
 * Two spellings are accepted, both of which appear in `arm-heartbeats.sh`: a bare `NAME=15`, and
 * the defaulted `NAME="${NAME:-10}"` form the optional contract vars use. FAILS CLOSED — a term
 * the ladder cannot resolve is a term the ladder would otherwise silently drop, which is how a
 * budget guard starts certifying a number smaller than the code will spend.
 */
function scriptConst(scriptText: string, name: string): number {
  const bare = new RegExp(`^${name}=(\\d+)\\s*$`, "m").exec(scriptText);
  if (bare) return Number(bare[1]);
  const dflt = new RegExp(`^${name}="\\$\\{${name}:-(\\d+)\\}"\\s*$`, "m").exec(scriptText);
  if (dflt) return Number(dflt[1]);
  throw new Error(`arm-heartbeats.sh declares no resolvable ${name}`);
}

/**
 * The pre-gate ceiling, PINNED to the measurement rather than carried as a bare literal.
 *
 * It used to be `const P95_PRE_GATE_S = 111` with nothing cross-checking it, and it failed OPEN: a
 * larger true value makes the guard more permissive. It also was not a p95 — it was the maximum of
 * six samples, mislabelled. Re-measured over the 42 most recent merge applies that reached the ARM
 * step (8–111 s; nearest-rank p95 at n = 42 is 81 s), and the ladder deliberately uses the MAX.
 * The value is read from the measurement log's machine-readable pin, so the two cannot drift.
 */
function pinnedFromMeasurements(name: string): number {
  const md = readFileSync(SPEC_MEASUREMENTS, "utf8");
  const m = new RegExp(`LADDER-PIN:\\s*${name}=(\\d+)\\b`).exec(md);
  if (!m) throw new Error(`measurements.md carries no LADDER-PIN for ${name}`);
  return Number(m[1]);
}

/**
 * Everything in the `apply` job that runs AFTER the ARM step and must still fit inside the job.
 *
 * The old inequality budgeted only the pre-gate window, leaving whatever was left for the re-pause
 * sweep, the bridge teardown and the post-apply summary combined — and the correlation is
 * adversarial, because the sweep only has work to do when the ARM step was cut, i.e. exactly when
 * the least budget remains (#7657 D3).
 *
 * Derived, not restated: `sites × curl_max_time` is the sweep's own re-PATCH ceiling (one PATCH per
 * arm call site, each `--max-time`d by the shared `hb_patch_paused`), plus the `timeout N` on the
 * sweep step's Doppler mint read out of the workflow, plus a flat allowance for the two remaining
 * `always()` steps.
 */
const TEARDOWN_AND_SUMMARY_BUDGET_S = 60;

function mintTimeoutSeconds(sweepBody: string): number {
  const m = /\btimeout\s+(\d+)\s+doppler\b/.exec(sweepBody);
  if (!m) throw new Error("the sweep step's Doppler mint carries no `timeout N` — an unbounded term the job budget cannot price");
  return Number(m[1]);
}

/**
 * Every `arm_one` deadline, resolved to an integer.
 *
 * The call list does NOT fan out with `for_each` — each monitor is a hand-written line, by design
 * — so this scan is textual, and that is precisely the property mutation row 3 defends. Comments
 * are stripped first: the block comments above these calls quote deadlines in prose, and a
 * comment-blind scan would sum the documentation.
 */
function armOneDeadlines(scriptText: string): number[] {
  const stripped = scriptText
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");
  const out: number[] = [];
  for (const m of stripped.matchAll(/^arm_one\s+'[^']+'\s+'[^']+'\s+("?\$?\{?[A-Za-z0-9_]+\}?"?)\s*(?:\|\||$)/gm)) {
    const raw = m[1].replace(/["${}]/g, "");
    if (/^\d+$/.test(raw)) {
      out.push(Number(raw));
      continue;
    }
    // A deadline passed as a variable is resolved from its assignment, and FAILS CLOSED if the
    // assignment cannot be found — an unresolvable term silently dropped from the sum is how a
    // budget guard starts certifying a smaller number than the code will spend.
    const assign = new RegExp(`^${raw}=(\\d+)\\s*$`, "m").exec(stripped);
    if (!assign) throw new Error(`arm_one deadline '${raw}' could not be resolved to an integer`);
    out.push(Number(assign[1]));
  }
  return out;
}

/** `arm_one <address> <label> <deadline>` as a triple, so a deadline can be checked against its monitor. */
function armOneCalls(scriptText: string): Array<{ addr: string; deadline: number }> {
  const stripped = scriptText.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");
  const out: Array<{ addr: string; deadline: number }> = [];
  for (const m of stripped.matchAll(/^arm_one\s+'([^']+)'\s+'[^']+'\s+("?\$?\{?[A-Za-z0-9_]+\}?"?)\s*(?:\|\||$)/gm)) {
    const raw = m[2].replace(/["${}]/g, "");
    const n = /^\d+$/.test(raw)
      ? Number(raw)
      : Number((new RegExp(`^${raw}=(\\d+)\\s*$`, "m").exec(stripped) ?? [])[1]);
    if (!Number.isFinite(n)) throw new Error(`unresolvable deadline for ${m[1]}`);
    out.push({ addr: m[1], deadline: n });
  }
  return out;
}

/** `period` + `grace` per `betteruptime_heartbeat` resource NAME, read from the .tf source. */
function heartbeatWindows(): Record<string, number> {
  const out: Record<string, number> = {};
  for (const f of listInfraTfFiles()) {
    const text = stripComments(readFileSync(f, "utf8"));
    for (const m of text.matchAll(/resource\s+"betteruptime_heartbeat"\s+"([a-z0-9_]+)"\s*\{([\s\S]*?)\n\}/g)) {
      const period = /^\s*period\s*=\s*(\d+)/m.exec(m[2]);
      const grace = /^\s*grace\s*=\s*(\d+)/m.exec(m[2]);
      if (period && grace) out[m[1]] = Number(period[1]) + Number(grace[1]);
    }
  }
  return out;
}

/** Minutes from a `timeout-minutes:` value, failing closed on a missing budget. */
function timeoutSeconds(v: unknown, what: string): number {
  if (typeof v !== "number" || !Number.isFinite(v) || v <= 0) {
    throw new Error(`${what} declares no usable timeout-minutes (got ${JSON.stringify(v)})`);
  }
  return v * 60;
}

interface LadderTerms {
  pollIntervalS: number;
  curlMaxTimeS: number;
  rollbackAttempts: number;
  maxPreGateS: number;
  mintTimeoutS: number;
}

/**
 * The per-call-site wall clock the `elapsed` accounting does NOT see. See arm-heartbeats.sh.
 *
 * Three round-trips are unconditional (the pre-loop GET, the unpause PATCH, and the final
 * iteration's own GET — the part that overshoots the deadline), plus one poll interval, plus the
 * rollback, which retries `ARM_ROLLBACK_ATTEMPTS` times. The retry count is READ FROM THE SCRIPT:
 * adding an attempt has to move the budget, or the budget is fiction.
 */
function perSiteOverheadS(t: LadderTerms): number {
  return t.pollIntervalS + (3 + t.rollbackAttempts) * t.curlMaxTimeS;
}

function postGateBudgetS(sites: number, t: LadderTerms): number {
  return sites * t.curlMaxTimeS + t.mintTimeoutS + TEARDOWN_AND_SUMMARY_BUDGET_S;
}

/** The ladder verdict, pure so the mutation rows can drive it directly. */
function ladderViolations(jobS: number, stepS: number, deadlines: number[], t: LadderTerms): string[] {
  expectNonEmptyDispatch(deadlines.length, 1);
  // (1) the step ceiling must cover the work the script can actually do — ADDITIVELY. The
  // overhead is per CALL SITE, so `Σ × 1.1` was the wrong shape: it happened to be generous for
  // six large deadlines and would under-budget a seventh small one. Measured: under the old form
  // the step ceiling broke at ≥ 9 s of vendor round-trip.
  const work = deadlines.reduce((a, b) => a + b, 0) + deadlines.length * perSiteOverheadS(t);
  const out: string[] = [];
  if (stepS < work) {
    out.push(`arm_step_timeout ${stepS}s < worst-case script wall clock ${work}s (Σdeadlines ${deadlines.reduce((a, b) => a + b, 0)} + ${deadlines.length} × ${perSiteOverheadS(t)})`);
  }
  // (2) the job must have room for what runs BEFORE the gate AND for what runs after it. The
  // sweep is the last-chance rollback and it runs precisely when the ARM step was cut.
  const post = postGateBudgetS(deadlines.length, t);
  if (jobS - stepS < t.maxPreGateS + post) {
    out.push(`job_timeout - arm_step_timeout = ${jobS - stepS}s < pre-gate ${t.maxPreGateS}s + post-gate ${post}s`);
  }
  // …and the step ceiling must be STRICTLY below the job's, or the gate is cancelled WITH the job
  // rather than failing inside it, which is #7587's shape.
  if (!(stepS < jobS)) out.push(`arm_step_timeout ${stepS}s is not strictly below job_timeout ${jobS}s`);
  return out;
}

/**
 * The ARM step together with the comment block directly above it.
 *
 * `extractJobBlock(wf, "apply")` is NOT a usable scope for "the workflow points a reader at what
 * asserts this gate": it resets only on `/^ {2}[A-Za-z0-9_-]+:/`, so every 2-space-indented
 * comment in the file — including the `notify-apply-failure` header — is inside it, and the
 * assertion was satisfied by pointers that have nothing to do with the ARM step (#7656 C7).
 */
function armStepWithHeader(wfText: string): string {
  const lines = wfText.split("\n");
  let start = lines.findIndex((l) => /^ {6}- name: Arm web-host probe heartbeats/.test(l));
  if (start < 0) throw new Error("the ARM step could not be located in the workflow");
  const stepLine = start;
  while (start > 0 && /^ {6}#/.test(lines[start - 1])) start--;
  let end = stepLine + 1;
  while (end < lines.length && !/^ {6}- name:/.test(lines[end]) && !/^ {6}#/.test(lines[end])) end++;
  return lines.slice(start, end).join("\n");
}

describe("the ARM gate's deadlines fit its job", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const script = readFileSync(ARM_SCRIPT, "utf8");
  const doc = parseYaml(wf) as {
    jobs: Record<string, { "timeout-minutes"?: number; steps?: Array<Record<string, unknown>> }>;
  };
  const applyJob = doc.jobs.apply;
  const armStep = (applyJob.steps ?? []).find(
    (s) => typeof s.name === "string" && /Arm web-host probe heartbeats/.test(s.name as string),
  );
  const sweepStep = (applyJob.steps ?? []).filter(isSweepStep)[0];

  function terms(): LadderTerms {
    return {
      pollIntervalS: scriptConst(script, "ARM_POLL_INTERVAL_S"),
      curlMaxTimeS: scriptConst(script, "ARM_CURL_MAX_TIME_S"),
      rollbackAttempts: scriptConst(script, "ARM_ROLLBACK_ATTEMPTS"),
      maxPreGateS: pinnedFromMeasurements("MAX_PRE_GATE_S"),
      mintTimeoutS: mintTimeoutSeconds(String(sweepStep?.run ?? "")),
    };
  }

  test("the two-part inequality holds, with every term measured or read from the script", () => {
    expect(armStep).toBeDefined();
    expect(sweepStep).toBeDefined();
    const jobS = timeoutSeconds(applyJob["timeout-minutes"], "the apply job");
    const stepS = timeoutSeconds(armStep!["timeout-minutes"], "the ARM step");
    const deadlines = armOneDeadlines(script);
    // Every hand-written call site, not just the ones reachable on today's merge path: a call site
    // absent from tfstate today is still a call site, and the ceiling has to hold when it is not.
    expect(deadlines.length).toBe(8);
    expect(ladderViolations(jobS, stepS, deadlines, terms())).toEqual([]);
  });

  test("the LAST-CHANCE ROLLBACK carries its own ceiling, and it fits the post-gate budget", () => {
    // The ARM step got a ceiling and the sweep did not, on the one step whose work correlates with
    // the ARM step having been cut (#7657 D3).
    const sweepS = timeoutSeconds(sweepStep!["timeout-minutes"], "the re-pause sweep step");
    const t = terms();
    expect(sweepS).toBeGreaterThanOrEqual(
      armOneDeadlines(script).length * t.curlMaxTimeS + t.mintTimeoutS,
    );
    // …and it must not eat the whole post-gate reservation.
    expect(sweepS).toBeLessThanOrEqual(postGateBudgetS(armOneDeadlines(script).length, t));
  });

  test("every deadline is period + grace − reserve, derived from the .tf source", () => {
    // The reserve was 10 and the real gap between the unpause landing and the re-pause landing is
    // `poll_interval + 2 × curl_max_time`, so at ≥ 2 s of vendor round-trip the old formula
    // re-paused AFTER the first absence alert had already fired (#7657 D5).
    const t = terms();
    const reserve = t.pollIntervalS + 2 * t.curlMaxTimeS;
    const windows = heartbeatWindows();
    expectNonEmptyDispatch(Object.keys(windows).length, 4);
    const calls = armOneCalls(script);
    expectNonEmptyDispatch(calls.length, 8);
    for (const { addr, deadline } of calls) {
      const name = /^betteruptime_heartbeat\.([a-z0-9_]+)/.exec(addr)?.[1];
      expect(name).toBeDefined();
      const window = windows[name!];
      expect(window).toBeDefined();
      // Every arm must roll back BEFORE the first absence alert. The inngest arm sits far below
      // the formula on purpose (#7228), which is still inside the bound.
      expect(deadline).toBeLessThanOrEqual(window - reserve);
      // The two arms that depart from the formula on purpose, each pinned EXACTLY in the next test: inngest_consumer (#7228) and
      // web_bash_synthetic (#10455 b: 2660 s per host would put ~90 minutes of worst-case wall clock into every merge's ARM step).
      if (name !== "inngest_consumer" && name !== "web_bash_synthetic") expect(deadline).toBe(window - reserve);
    }
  });

  test("the `inngest_consumer` deadline is EXACTLY 30, `web_bash_synthetic` EXACTLY 300 on each host, and every other deadline is unchanged", () => {
    // Not "<= 60": the reclaimed ~200 s and the 1-in-6 arming probability both plug in 30, so a
    // looser bound would pass while falsifying the arithmetic.
    const stripped = script.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");
    expect(stripped).toMatch(/^ARM_INNGEST_DEADLINE=30$/m);
    expect(stripped).toMatch(/^ARM_WBS_DEADLINE=300$/m);
    expect(armOneDeadlines(script)).toEqual([200, 440, 200, 440, 200, 300, 300, 30]);
    // …and the departure stays strictly inside the monitor's own window, so a failed attempt cannot false-page.
    const wbs = armOneCalls(script).filter((c) => c.addr.includes("web_bash_synthetic"));
    expect(wbs.map((c) => c.addr)).toEqual([
      'betteruptime_heartbeat.web_bash_synthetic["web-1"]',
      'betteruptime_heartbeat.web_bash_synthetic["web-2"]',
    ]);
  });

  test("the `web_bash_synthetic` beat pins period 900 / grace 1800 and mirrors the nic-guard sibling's alerting attributes, and its URL secret is the name both env writers emit", () => {
    // testdesign 8 / 7: the ARM test only asserts `deadline <= window - reserve`, which holds for ANY grace >= 0 and any email flag, so
    // `email = false` (with `policy_id = null` on the free tier nobody is told the detector died), `grace = 60` or `period = 3600`
    // all stayed green. And a renamed `doppler_secret` leaves the env files naming a key that no secret carries.
    const tf = stripComments(readFileSync(join(INFRA_DIR, "web-probe.tf"), "utf8"));
    const block = (type: string, name: string): string => {
      const m = new RegExp(`resource\\s+"${type}"\\s+"${name}"\\s*\\{([\\s\\S]*?)\\n\\}`).exec(tf);
      if (!m) throw new Error(`web-probe.tf has no resource ${type}.${name}`);
      return m[1];
    };
    const attrs = (b: string): Record<string, string> =>
      Object.fromEntries([...b.matchAll(/^\s{2}([a-z_]+)\s*=\s*(.+?)\s*$/gm)].map((m) => [m[1], m[2]]));
    const wbs = attrs(block("betteruptime_heartbeat", "web_bash_synthetic"));
    const nic = attrs(block("betteruptime_heartbeat", "web_nic_guard"));
    expect(wbs.period).toBe("900");
    expect(wbs.grace).toBe("1800");
    // Non-vacuity: the sibling really carries the alerting attributes being compared (an empty parse would equal an empty parse).
    expect(nic.email).toBe("true");
    expect(Object.keys(nic).length).toBeGreaterThanOrEqual(10);
    for (const k of ["for_each", "call", "sms", "email", "push", "team_wait", "team_name", "policy_id", "paused"]) {
      expect(`${k}=${wbs[k]}`).toBe(`${k}=${nic[k]}`);
    }
    const secret = attrs(block("doppler_secret", "web_bash_synthetic_url"));
    expect(secret.name).toBe('"WEB_BASH_SYNTHETIC_URL_${upper(replace(each.key, "-", "_"))}"');
    expect(secret.visibility).toBe('"masked"');
    expect(secret.value).toBe("betteruptime_heartbeat.web_bash_synthetic[each.key].url");
    // …and both env writers emit that same name for a host: the baked one from the upper-cased host key, the SSH one from `upper(replace(...))`.
    const envwrite = readFileSync(join(INFRA_DIR, "web-probe-envwrite.sh"), "utf8");
    expect(envwrite).toContain('"WEB_BASH_SYNTHETIC_URL_${HOST_UPPER}"');
    expect(envwrite).toMatch(/^HOST_UPPER="\$\(printf '%s' "\$SOLEUR_HOST_KEY" \| tr 'a-z-' 'A-Z_'\)"$/m);
    const server = stripComments(readFileSync(join(INFRA_DIR, "server.tf"), "utf8"));
    for (const host of ["web-1", "web-2"]) {
      expect(server).toContain(`'WEB_BASH_SYNTHETIC_URL_\${upper(replace("${host}", "-", "_"))}'`);
    }
  });

  test("the workflow's own ladder arithmetic matches the derived numbers", () => {
    // #7661 G7: 1660/1860/2100 appeared in three comments and were pinned by nothing, so the
    // inequality guard stayed green on the exact edit that made the prose wrong. Every literal the
    // comment states is now re-derived here and compared.
    const jobS = timeoutSeconds(applyJob["timeout-minutes"], "the apply job");
    const stepS = timeoutSeconds(armStep!["timeout-minutes"], "the ARM step");
    const t = terms();
    const deadlines = armOneDeadlines(script);
    const sum = deadlines.reduce((a, b) => a + b, 0);
    const work = sum + deadlines.length * perSiteOverheadS(t);
    const header = armStepWithHeader(wf);
    const budget = extractJobBlock(wf, "apply").split("\n").slice(0, 80).join("\n");
    for (const n of [String(sum), String(work), String(stepS), String(jobS), String(perSiteOverheadS(t))]) {
      expect(`${budget}\n${header}`).toContain(n);
    }
    // …and the mutex sum the file states in three places is the sum of the three jobs that can
    // execute on a push, `preflight` included (#7657 D6).
    const preflightS = timeoutSeconds(
      (doc.jobs.preflight as { "timeout-minutes"?: number })["timeout-minutes"],
      "the preflight job",
    );
    const notifyS = timeoutSeconds(
      (doc.jobs["notify-apply-failure"] as { "timeout-minutes"?: number })["timeout-minutes"],
      "the notify job",
    );
    const mutexMin = (preflightS + jobS + notifyS) / 60;
    expect(mutexMin).toBe(59);
    // Every comment line in the file that states an ADDITIVE minute sum. There are three copies —
    // the apply header, the notify-apply-failure header, and the registry_luks_recut accounting
    // paragraph 1,300 lines away — and they used to be able to drift apart silently.
    const claims = wf.split("\n").filter((l) => /^\s*#.*\+.*=\s*\d+ min\b/.test(l));
    expectNonEmptyDispatch(claims.length, 3);
    for (const c of claims) expect(c).toContain(`= ${mutexMin} min`);
  });

  test("the sweep DELEGATES to the script rather than re-implementing it, and is coupled to the ARM step", () => {
    const sweeps = (applyJob.steps ?? []).filter(isSweepStep);
    expectNonEmptyDispatch(sweeps.length, 1);
    expect(sweeps.length).toBe(1);
    const body = sweeps[0].run as string;
    const armBody = String(armStep!.run ?? "");

    // #7659 F1: the body is not here. No second PATCH implementation, no second API-base literal.
    expect(body).not.toContain("uptime.betterstack.com");
    expect(body).not.toMatch(/curl\b/);
    expect(body).toMatch(/arm-heartbeats\.sh"?\s+--sweep\b/);

    // #7656 C2: writer and reader are one mechanism split across a process boundary, and NOTHING
    // pinned the ARM step's env to the literal the sweep reads. Changing the writer to
    // `…-v2` left both suites green while the sweep short-circuited on every run.
    const writer = /ARMED_UNCONFIRMED="([^"]+)"/.exec(armBody);
    const reader = new RegExp(`ARMED_UNCONFIRMED="([^"]+)"`).exec(body);
    expect(writer).not.toBeNull();
    expect(reader).not.toBeNull();
    expect(writer![1]).toBe(ARM_STATE_FILE_LITERAL);
    expect(reader![1]).toBe(writer![1]);
    // …and the early exit reads the same path.
    expect(body).toContain(`[[ -s "${ARM_STATE_FILE_LITERAL}" ]] || exit 0`);

    // AC4: it exits early BEFORE reading Doppler, so an apply with no work does not re-mint a
    // credential it does not need and raise a mint-failure alarm on a run with nothing to sweep.
    const firstWork = body
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l !== "" && !l.startsWith("#") && !/^set [+-]/.test(l))[0];
    expect(firstWork).toContain(ARM_STATE_FILE_LITERAL);
    expect(firstWork).toContain("exit 0");
    expect(body.indexOf(ARM_STATE_FILE_LITERAL)).toBeLessThan(body.indexOf("doppler secrets get"));

    // AC4: its own credential, re-minted, bounded and masked.
    expect((sweeps[0].env as Record<string, string>)?.DOPPLER_TOKEN).toBeDefined();
    expect(body).toContain("doppler secrets get BETTERSTACK_API_TOKEN");
    expect(body).toMatch(/printf '::add-mask::%s\\n'/);
    expect(body).not.toMatch(/^\s*set -x\s*$/m);
    // #7661 G11: the token reaches the CLI through its own env var, never on argv.
    expect(body).not.toMatch(/--token\s/);
    expect(armBody).not.toMatch(/--token\s/);

    // AC5: errexit is inherited from `bash -e {0}`, and the sweep reads its own mint failure as
    // DATA — an empty token is an `outcome=mint-unreadable` report, not an abort with no diagnosis.
    expect(body).toMatch(/^\s*set \+e\s*$/m);
  });

  test("the sweep's NAME still satisfies the name-keyed filter the email's cause step greps with", () => {
    // #7656 C3. The guard above deliberately does not key on the step name — but PRODUCTION does:
    // `select(.name | ascii_downcase | test("re-pause"))`. Tolerating a rename here while the
    // producer cannot tolerate it converts a false-RED into a silent false-GREEN: `sweep_conclusion`
    // degrades permanently to `unknown`, and the email branches on it.
    const notify = doc.jobs["notify-apply-failure"] as { steps?: Array<Record<string, unknown>> };
    const cause = (notify.steps ?? []).find((s) => s.id === "cause");
    expect(cause).toBeDefined();
    const filter = /ascii_downcase\s*\|\s*test\("([^"]+)"\)/.exec(String(cause!.run ?? ""));
    expect(filter).not.toBeNull();
    expect(String(sweepStep!.name ?? "").toLowerCase()).toMatch(new RegExp(filter![1]));
  });

  test("AC5: the script clears errexit explicitly and uses no bare arithmetic command", () => {
    expect(script).toMatch(/^set \+e\b/m);
    // A bare `(( … ))` exits non-zero whenever the expression evaluates to 0, which under an
    // inherited errexit kills the rollback path mid-sweep.
    const stripped = script.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");
    expect(stripped).not.toMatch(/^\s*\(\(/m);
    // The counter advances from the CLOCK, not from the sleep. Asserted behaviourally in
    // apps/web-platform/infra/arm-heartbeats.test.sh (mutation row M1); this is the cheap
    // structural companion, not the proof.
    expect(stripped).toContain("elapsed=$(( $(now_s) - started ))");
    // No `trap` (Cut List C6): bash keeps only the last EXIT handler, an INT/TERM handler returns
    // and then fires EXIT too, and bash defers the handler until the foreground `sleep` returns.
    expect(stripped).not.toMatch(/^\s*trap\b/m);
    // ONE PATCH implementation, with real status-code semantics rather than `-f` (#7658 E6).
    // Since #7797 the bearer rides curl's stdin config channel, so the transport flags, the token
    // guard and the header live in ONE wrapper (`bs_api`) holding the file's only `curl`; the two
    // call sites (the GET and the PATCH) go through it, so what is pinned is one curl + two calls.
    // #9980 added a THIRD credentialed call site: the named-monitor resolver's paginated list read
    // (`--status` / `--arm-one`). The count is the honest number of call sites, and the intent of the
    // pin survives: every credentialed call goes through `bs_api`, and `curl` stays at exactly one.
    expect(stripped.match(/curl\b/g)?.length).toBe(1);
    expect(stripped.match(/\$\(bs_api /g)?.length).toBe(3);
    expect(stripped).toMatch(/-w '%\{http_code\}'/);
    expect(stripped).toMatch(/\[\[ "\$HB_PATCH_CODE" =~ \^2 \]\]/);
    // The sweep's outcome vocabulary is closed and documented in the same file.
    for (const word of ["noop", "repaused", "partial", "mint-unreadable"]) {
      expect(script).toContain(word);
    }
  });

  test("the workflow points a reader at what asserts this gate — from the STEP, not the whole job", () => {
    const armBody = String(armStep!.run ?? "");
    expect(armBody).toContain("apps/web-platform/infra/arm-heartbeats.sh");
    // Scoped to the ARM step plus its own comment header. Against `extractJobBlock(wf, "apply")`
    // this assertion was satisfied by two unrelated pre-existing comments and survived deleting
    // both real pointers (#7656 C7).
    const header = armStepWithHeader(wf);
    expectNonEmptyDispatch(header.length, 1);
    expect(header).toContain("arm-heartbeats.test.sh");
    expect(header).toContain("terraform-target-parity.test.ts");
  });
});

describe("Guard 2 mutation battery (#7587)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const script = readFileSync(ARM_SCRIPT, "utf8");
  const doc = parseYaml(wf) as {
    jobs: Record<string, { "timeout-minutes"?: number; steps?: Array<Record<string, unknown>> }>;
  };
  const applyJob = doc.jobs.apply;
  const armStep = (applyJob.steps ?? []).find(
    (s) => typeof s.name === "string" && /Arm web-host probe heartbeats/.test(s.name as string),
  )!;
  const sweepStep = (applyJob.steps ?? []).filter(isSweepStep)[0];
  const REAL_DEADLINES = armOneDeadlines(script);
  // LIVE, not restated (#7656 C6). The battery's control used to re-assert `35 * 60` and
  // `31 * 60`, so `control: the shipped ladder is clean` was a statement about the pure function
  // and not about what ships — lowering the real `timeout-minutes` reddened exactly one test
  // elsewhere while every row here, control included, stayed green.
  const JOB_S = timeoutSeconds(applyJob["timeout-minutes"], "the apply job");
  const STEP_S = timeoutSeconds(armStep["timeout-minutes"], "the ARM step");
  const T: LadderTerms = {
    pollIntervalS: scriptConst(script, "ARM_POLL_INTERVAL_S"),
    curlMaxTimeS: scriptConst(script, "ARM_CURL_MAX_TIME_S"),
    rollbackAttempts: scriptConst(script, "ARM_ROLLBACK_ATTEMPTS"),
    maxPreGateS: pinnedFromMeasurements("MAX_PRE_GATE_S"),
    mintTimeoutS: mintTimeoutSeconds(String(sweepStep?.run ?? "")),
  };

  test("control: the SHIPPED ladder is clean, read live from the workflow", () => {
    expect(JOB_S).toBe(53 * 60);
    expect(STEP_S).toBe(47 * 60);
    expect(ladderViolations(JOB_S, STEP_S, REAL_DEADLINES, T)).toEqual([]);
  });

  test("M1 RED: lowering the job back to 15 min while leaving the deadlines alone — #7587 restored", () => {
    const v = ladderViolations(15 * 60, STEP_S, REAL_DEADLINES, T);
    expect(v.length).toBeGreaterThan(0);
    expect(v.some((s) => s.includes("pre-gate") || s.includes("not strictly below"))).toBe(true);
  });

  test("M2 RED: deleting every `arm_one` call leaves the scan with NOTHING to check", () => {
    const gutted = script.replace(/^arm_one .*$/gm, ": removed");
    expect(armOneDeadlines(gutted)).toEqual([]);
    // expectNonEmptyDispatch is what converts "0 checked, exit 0" into a failure.
    expect(() => ladderViolations(JOB_S, STEP_S, armOneDeadlines(gutted), T)).toThrow();
  });

  test("M3 RED: a SECOND call whose own deadline is fine but pushes the SUM past the ceiling", () => {
    // A check that validates only the first call site is the defect class this row names.
    const v = ladderViolations(JOB_S, STEP_S, [...REAL_DEADLINES, 440], T);
    expect(v.length).toBeGreaterThan(0);
    expect(v[0]).toContain("worst-case script wall clock");
  });

  test("M3b RED: one call site more than ships (a NINTH) with a TINY deadline still reds — the overhead is per site", () => {
    // This is the row `Σ × 1.1` could not carry: a multiplier on the deadline sum grows with the
    // deadlines, while the real overhead grows with the number of call sites. Five 15 s round-trips
    // (three unconditional plus two rollback attempts) and a poll interval cost 85 s whether the
    // deadline is 440 or 1.
    const clean = ladderViolations(JOB_S, STEP_S, REAL_DEADLINES, T);
    expect(clean).toEqual([]);
    const headroom = STEP_S - (REAL_DEADLINES.reduce((a, b) => a + b, 0) + REAL_DEADLINES.length * perSiteOverheadS(T));
    expect(headroom).toBeLessThan(perSiteOverheadS(T));
    const v = ladderViolations(JOB_S, STEP_S, [...REAL_DEADLINES, 1], T);
    expect(v.some((s) => s.includes("worst-case script wall clock"))).toBe(true);
  });

  test("M4 RED: removing the ARM step's own ceiling — the gate reverts to being cancelled WITH the job", () => {
    // A REAL mutation of the shipped YAML, not a bare call to the helper (#7656 C6): the previous
    // row asserted `timeoutSeconds(undefined, …)` throws, which never touched the workflow and was
    // the identical assertion H3 makes one test later.
    const mutated = parseYaml(wf) as { jobs: Record<string, { steps?: Array<Record<string, unknown>> }> };
    const step = (mutated.jobs.apply.steps ?? []).find(
      (s) => typeof s.name === "string" && /Arm web-host probe heartbeats/.test(s.name as string),
    )!;
    delete step["timeout-minutes"];
    expect(() => timeoutSeconds(step["timeout-minutes"], "the ARM step")).toThrow(/no usable timeout-minutes/);
    // …and the guard that reads it is the one above, so prove the same helper accepts the REAL one.
    expect(timeoutSeconds(armStep["timeout-minutes"], "the ARM step")).toBe(STEP_S);
  });

  test("M4b RED: removing the SWEEP's ceiling — the last-chance rollback becomes unbounded again", () => {
    const mutated = parseYaml(wf) as { jobs: Record<string, { steps?: Array<Record<string, unknown>> }> };
    const step = (mutated.jobs.apply.steps ?? []).filter(isSweepStep)[0];
    expect(step).toBeDefined();
    delete step["timeout-minutes"];
    expect(() => timeoutSeconds(step["timeout-minutes"], "the re-pause sweep step")).toThrow();
  });

  test("M5 RED: DELETING the sweep step is visible — it is found by always() + the state file, not by name", () => {
    // A real deletion, fed back through `isSweepStep` (#7656 C6: the previous row sliced an array
    // of length 1 from index 1 and asserted the result was empty, which is true of any array).
    const mutated = parseYaml(wf) as { jobs: Record<string, { steps?: Array<Record<string, unknown>> }> };
    const before = (mutated.jobs.apply.steps ?? []).filter(isSweepStep);
    expect(before.length).toBe(1);
    mutated.jobs.apply.steps = (mutated.jobs.apply.steps ?? []).filter((s) => !isSweepStep(s));
    expect((mutated.jobs.apply.steps ?? []).filter(isSweepStep).length).toBe(0);
  });

  test("M5b RED: a sweep that re-implements the PATCH inline is not a delegating sweep", () => {
    const decoy = { if: "always()", run: `[[ -s "${ARM_STATE_FILE_LITERAL}" ]] || exit 0\ncurl -X PATCH https://uptime.betterstack.com/api/v2/heartbeats/1\n` };
    expect(isSweepStep(decoy)).toBe(false);
  });

  test("M6 RED: shrinking the per-round-trip ceiling in the SCRIPT changes the ladder's verdict", () => {
    // The terms are parsed out of the script, so a script edit has to move the arithmetic. If it
    // does not, the ladder is restating literals again.
    const widened: LadderTerms = { ...T, curlMaxTimeS: T.curlMaxTimeS * 3 };
    expect(ladderViolations(JOB_S, STEP_S, REAL_DEADLINES, widened).length).toBeGreaterThan(0);
    expect(() => scriptConst(script.replace(/^ARM_CURL_MAX_TIME_S=\d+$/m, "# removed"), "ARM_CURL_MAX_TIME_S")).toThrow();
    // …and adding a rollback attempt has to cost the budget, or the retry term is decorative.
    const retried: LadderTerms = { ...T, rollbackAttempts: T.rollbackAttempts + 3 };
    expect(ladderViolations(JOB_S, STEP_S, REAL_DEADLINES, retried).length).toBeGreaterThan(0);
  });

  test("M7 RED: a post-gate budget of zero — the shape the old inequality shipped — is caught", () => {
    // Term (2) used to read `jobS - stepS >= p95(pre-gate)` and nothing else, so 129 s were left
    // for the sweep, the bridge teardown and the post-apply summary combined (#7657 D3).
    const noPost = JOB_S - STEP_S - T.maxPreGateS;
    expect(noPost).toBeGreaterThanOrEqual(postGateBudgetS(REAL_DEADLINES.length, T));
    // A job sized on the OLD inequality: room for the pre-gate window and nothing else.
    const tight = STEP_S + T.maxPreGateS + 10;
    const v = ladderViolations(tight, STEP_S, REAL_DEADLINES, T);
    expect(v.some((x) => x.includes("post-gate"))).toBe(true);
  });

  test("H3 RED: a job with NO timeout-minutes must fail CLOSED, never read as unbounded-and-fine", () => {
    expect(() => timeoutSeconds(undefined, "the apply job")).toThrow(/no usable timeout-minutes/);
    expect(() => timeoutSeconds(0, "the apply job")).toThrow();
    expect(() => timeoutSeconds("31", "the apply job")).toThrow();
  });

  test("H4 PASS: a non-canonical step ceiling that still satisfies the inequality MUST NOT red", () => {
    // The contract is the inequality, not a literal. 2800 s (46 min 40 s) is not what ships and is fine: it covers the
    // 2790 s of work and leaves the job its 321 s of pre- and post-gate room.
    expect(ladderViolations(JOB_S, 2800, REAL_DEADLINES, T)).toEqual([]);
  });

  test("H5 RED: an unresolvable deadline variable fails closed rather than dropping the term", () => {
    const broken = script.replace(/^ARM_INNGEST_DEADLINE=30$/m, "# assignment removed");
    expect(() => armOneDeadlines(broken)).toThrow(/could not be resolved/);
  });

  test("H6 RED: an unpinned pre-gate measurement fails closed rather than defaulting", () => {
    // The old `const P95_PRE_GATE_S = 111` failed OPEN: a larger true value made the guard more
    // permissive and nothing cross-checked it against the measurement log.
    expect(pinnedFromMeasurements("MAX_PRE_GATE_S")).toBe(111);
    expect(() => pinnedFromMeasurements("NO_SUCH_PIN")).toThrow(/no LADDER-PIN/);
  });
});

// ─── #9377 decision A2: job reach of the web-class passphrase pair ─────────────────────────────────
//
// The non-ackable rotation HALT (luks_passphrase_rotations) lives in ONE job: `apply`. If a second job could
// reach the web-class passphrase or its Doppler copy, a rotation could be applied there without the HALT (the
// 2026-09-24 learning: a rotation resource reachable by more than one workflow without its gate). So the pair
// must be `-target`ed by `apply` and by NO other job in this workflow, nor by ANY other workflow file, and `apply`
// must carry the HALT, evaluated before the destroy_count sum. The transitive reach (`-target` pulls dependencies)
// was traced by reading the closures at plan time; these rows pin the direct reach.
//
// apply-deploy-pipeline-fix.yml SHARES the destroy-guard filter (destroy-guard-filter-web-platform.jq) but reads only
// host_creates, non_terraform_data_deletes and reboot_updates from it: it has NO luks_passphrase_rotations HALT, so a
// -target/-replace of the pair there would rotate it unguarded. That is why the scan below covers EVERY workflow
// file and not just apply-web-platform-infra.yml.
//
// The HALT itself is pinned structurally (luksHaltViolations), not by text: inserting
// `[[ -n "${ALLOW_LUKS:-}" ]] && exit 0` before its `exit 1` kept the earlier text pins green.
const LUKS_FILTER = resolve(REPO_ROOT, "tests/scripts/lib/destroy-guard-filter-web-platform.jq");
const WEB_PASSPHRASE_PAIR = ["random_password.workspaces_luks_web", "doppler_secret.workspaces_luks_web_key"];
const escRe = (a: string) => a.replace(/[\\^$.*+?()[\]{}|]/g, "\\$&");
/** Whole-line `#` comments out. (stripComments is HCL-flavoured and also eats `//`, which shell lines may contain.) */
const stripShellLineComments = (t: string) =>
  t.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");

/** The six counted addresses, read from the filter's own `luks_passphrase_addrs` so the list has ONE source. */
function luksPassphraseAddrs(jqSource: string): string[] {
  const m = /def luks_passphrase_addrs: \[([^\]]*)\];/.exec(jqSource);
  return m ? [...m[1].matchAll(/"([^"]+)"/g)].map((x) => x[1]) : [];
}

/** Addresses from `addrs` that `text` does not name as a whole token (so `...workspaces_luks` is not satisfied by `..._web`). */
function missingAddrs(text: string, addrs: string[]): string[] {
  return addrs.filter((a) => !new RegExp(`(?<![A-Za-z0-9_])${escRe(a)}(?![A-Za-z0-9_])`).test(text));
}

/** Join `\`-continued physical lines into logical lines (whitespace collapsed), as the shell reads them. */
const joinContinuations = (t: string): string => t.replace(/\\\r?\n[ \t]*/g, " ");

/**
 * ALLOW-LIST of the statements permitted from the START of the apply step's `run:` block through the end of the luks
 * HALT. A deny-list ("no line with exit/return") cannot see `[[ "$HEAD_MSG" == *"[ack-luks]"* ]] && luks_rotations=0`
 * or `echo x; [[ -n "${SKIP_LUKS:-}" ]] && exit 0`, nor anything BEFORE the `counts=$(jq …)` line, so every logical
 * line in that span must match one of the shapes below, and the required statements must appear once each, in order.
 * `lines` are comment-stripped job lines; `readIdx`/`start`/`end` locate the counter read, the HALT `if` and its `fi`.
 */
function destroyGuardPrefixViolations(lines: string[], readIdx: number, start: number, end: number): string[] {
  const v: string[] = [];
  let runIdx = -1;
  for (let i = (readIdx >= 0 ? readIdx : start) - 1; i >= 0; i--) {
    if (/^\s*run:\s*[|>][-+]?\s*$/.test(lines[i])) {
      runIdx = i;
      break;
    }
  }
  if (runIdx < 0) return ["the apply step's `run: |` header was not found above the counter read"];
  const logical = joinContinuations(lines.slice(runIdx + 1, end + 1).join("\n"))
    .split("\n")
    .map((l) => l.trim().replace(/\s+/g, " "))
    .filter((l) => l !== "");
  const PLAN_RE = /^doppler run --preserve-env -p soleur -c prd_terraform --name-transformer tf-var -- terraform plan -no-color -input=false -out=tfplan( -var="[^"$`;&|]*(?:\$\{CI_SSH_PUB\}[^"$`;&|]*)?"| -target=[A-Za-z0-9_.\[\]-]+)+$/;
  const COUNTS = 'counts=$(jq -f "${GITHUB_WORKSPACE}/tests/scripts/lib/destroy-guard-filter-web-platform.jq" < tfplan.json)';
  const READ_RE = /^([a-z_]+)=\$\(echo "\$counts" \| jq -r '\.([a-z_]+)'\)$/;
  const GREP_RE = /^grep -F( -e (?:random_password|doppler_secret)\.[a-z_]+){6} -e 'Plan:' tfplan\.txt >&2 \|\| true$/;
  const COUNTERS = ["resource_deletes", "nested_deletes", "reboot_updates", "host_creates", "apex_move_orphans", "luks_rotations", "undecidable_entries"];
  const READS = [...COUNTERS, "plan_ok"];
  const KNOWN_VARS = new Set([...READS, "rc", "luks_passphrase_rotations"]);
  /** A complete `echo "::error::..."` whose body cannot run code: no unescaped quote/backtick, no `$(`, and every `$` is a plain known variable. */
  const echoOk = (t: string): boolean => {
    if (!(t.startsWith('echo "::error::') && t.endsWith('"'))) return false;
    const inner = t.slice('echo "'.length, -1).replace(/\\./g, "");
    if (/["`]/.test(inner)) return false;
    const rest = inner.replace(/\$\{([A-Za-z_]+)\}|\$([A-Za-z_]+)/g, (_m, x, y) => (KNOWN_VARS.has(x ?? y) ? "" : "\u0000"));
    return !/[$\u0000]/.test(rest);
  };
  const numericOk = (t: string): boolean => {
    const m = /^if ((?:\[\[ ! "\$[a-z_]+" =~ \^\[0-9\]\+\$ \]\](?: \|\| )?)+); then$/.exec(t);
    if (!m) return false;
    const names = [...m[1].matchAll(/"\$([a-z_]+)"/g)].map((x) => x[1]);
    return COUNTERS.every((c) => names.includes(c)) && names.every((n) => COUNTERS.includes(n));
  };
  type Step =
    | { kind: "stmt"; name: string; test: (t: string) => boolean }
    | { kind: "reads" }
    | { kind: "block"; name: string; header: (t: string) => boolean; grep: boolean; exit: string };
  const eq = (x: string) => (t: string) => t === x;
  // A CLOSED SEQUENCE: every line from the step start through the luks HALT's `fi` is consumed by exactly one step below,
  // in this order, and nothing else may appear. `exit`, `fi` and the `rc` block exist only at their one expected place,
  // so an inserted `exit $rc`, a second `if [[ $rc -ne 0 ]]` with an extra `fi`, or an echo/grep carrying a
  // `${a[x=0]}` expansion has no slot to occupy (an allow-list of line SHAPES passed all four).
  const steps: Step[] = [
    { kind: "stmt", name: "set -euo pipefail", test: eq("set -euo pipefail") },
    { kind: "stmt", name: "set +e", test: eq("set +e") },
    { kind: "stmt", name: "the doppler-wrapped terraform plan", test: (t) => PLAN_RE.test(t) },
    { kind: "stmt", name: "rc=$?", test: eq("rc=$?") },
    { kind: "block", name: "the plan-failure block", header: eq("if [[ $rc -ne 0 ]]; then"), grep: false, exit: "exit $rc" },
    { kind: "stmt", name: "set -e", test: eq("set -e") },
    { kind: "stmt", name: "terraform show -no-color", test: eq("terraform show -no-color tfplan > tfplan.txt") },
    { kind: "stmt", name: "terraform show -json", test: eq("terraform show -json tfplan > tfplan.json") },
    { kind: "stmt", name: "the counts= jq read", test: eq(COUNTS) },
    { kind: "reads" },
    { kind: "block", name: "the plan_ok check", header: eq('if [[ "$plan_ok" != "true" ]]; then'), grep: false, exit: "exit 1" },
    { kind: "block", name: "the numeric validation (every counter)", header: numericOk, grep: false, exit: "exit 1" },
    { kind: "block", name: "the undecidable HALT", header: eq('if [[ "$undecidable_entries" -gt 0 ]]; then'), grep: false, exit: "exit 1" },
    { kind: "block", name: "the luks HALT", header: eq('if [[ "$luks_rotations" -gt 0 ]]; then'), grep: true, exit: "exit 1" },
  ];
  const WHY = "a statement outside the destroy-guard allow-list between the step start and the luks HALT";
  let at = 0;
  const peek = () => logical[at] ?? "<end of the span>";
  walk: for (const st of steps) {
    if (st.kind === "stmt") {
      if (!st.test(peek())) {
        v.push(`${WHY} (expected ${st.name}): ${peek().slice(0, 90)}`);
        break walk;
      }
      at++;
    } else if (st.kind === "reads") {
      const seen: string[] = [];
      for (let k = 0; k < READS.length; k++) {
        const m = READ_RE.exec(peek());
        const ok = m && (m[1] === m[2] || (m[1] === "luks_rotations" && m[2] === "luks_passphrase_rotations")) && !seen.includes(m[1]) && READS.includes(m[1]);
        if (!ok) {
          v.push(`${WHY} (expected one of the ${READS.length} counter reads, each once): ${peek().slice(0, 90)}`);
          break walk;
        }
        seen.push(m![1]);
        at++;
      }
    } else {
      if (!st.header(peek())) {
        v.push(`${WHY} (expected ${st.name}): ${peek().slice(0, 90)}`);
        break walk;
      }
      at++;
      let echoes = 0;
      while (logical[at]?.startsWith("echo ")) {
        if (!echoOk(logical[at])) {
          v.push(`${WHY} (an echo that can run code or expands an unknown variable in ${st.name}): ${logical[at].slice(0, 90)}`);
          break walk;
        }
        echoes++;
        at++;
      }
      if (echoes === 0) {
        v.push(`${WHY} (${st.name} has no ::error:: echo): ${peek().slice(0, 90)}`);
        break walk;
      }
      if (st.grep) {
        if (!GREP_RE.test(peek())) {
          v.push(`${WHY} (expected the literal six-address grep -F in ${st.name}): ${peek().slice(0, 90)}`);
          break walk;
        }
        at++;
      }
      if (peek() !== st.exit) {
        v.push(`${WHY} (expected '${st.exit}' closing ${st.name}): ${peek().slice(0, 90)}`);
        break walk;
      }
      at++;
      if (peek() !== "fi") {
        v.push(`${WHY} (expected 'fi' closing ${st.name}): ${peek().slice(0, 90)}`);
        break walk;
      }
      at++;
    }
  }
  if (v.length === 0 && at !== logical.length) v.push(`${WHY} (trailing lines after the luks HALT's fi): ${peek().slice(0, 90)}`);
  const fiCount = logical.filter((t) => t === "fi").length;
  const ifCount = logical.filter((t) => t.startsWith("if ")).length;
  if (fiCount !== ifCount) v.push(`${WHY} (if/fi imbalance: ${ifCount} if vs ${fiCount} fi)`);
  return v;
}

/**
 * Structural violations of the apply job's luks_rotations HALT, on the job's comment-stripped code. The shape the
 * host_creates HALT checker (web-host-escrow-preflight-census.test.ts) enforces, with a stricter body: EVERY
 * executable line in the body must be an `echo "::error::..."`, the plan-line grep to stderr, or the final `exit 1`,
 * all at one indent, so a conditional or short-circuit exit cannot hide in it.
 */
function luksHaltViolations(code: string): string[] {
  const lines = code.split("\n");
  const ifRe = /^(\s*)if \[\[ "\$luks_rotations" -gt 0 \]\]; then\s*$/;
  const start = lines.findIndex((l) => ifRe.test(l));
  if (start < 0) return ['no `if [[ "$luks_rotations" -gt 0 ]]; then` HALT (exact, unconditioned) found'];
  const indent = ifRe.exec(lines[start])![1];
  const v: string[] = [];
  const indentOf = (l: string) => /^(\s*)/.exec(l)![1];
  const readIdx = lines.findIndex((l) => /^\s*luks_rotations=\$\(echo "\$counts" \| jq -r '\.luks_passphrase_rotations'\)\s*$/.test(l));
  const sumIdx = lines.findIndex((l) => /^\s*destroy_count=\$\(\(resource_deletes\b/.test(l));
  if (readIdx < 0) v.push("the luks_rotations counter is not read from the destroy-guard filter output");
  else if (indentOf(lines[readIdx]) !== indent) v.push("the HALT is nested at a different level than the counter read (inside a conditional?)");
  if (sumIdx < 0) v.push("the destroy_count sum was not found");
  else if (indentOf(lines[sumIdx]) !== indent) v.push("the destroy_count sum is at a different level than the HALT");
  if (readIdx >= 0 && start < readIdx) v.push("the HALT precedes the counter read");
  if (sumIdx >= 0 && start > sumIdx) v.push("the HALT is positioned AFTER the destroy_count sum ([ack-destroy] could then reach it)");
  let end = -1;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i] === `${indent}fi`) {
      end = i;
      break;
    }
  }
  if (end < 0) return [...v, "the HALT block has no closing fi at its own indent"];
  const body = lines.slice(start + 1, end).filter((l) => l.trim() !== "");
  const bodyIndent = `${indent}  `;
  const last = body[body.length - 1];
  if (last !== `${bodyIndent}exit 1`) v.push("the HALT body does not END in an unconditional `exit 1`");
  for (const l of body) {
    if (indentOf(l) !== bodyIndent) {
      v.push(`HALT body line nested or mis-indented (a conditional around the exit?): ${l.trim().slice(0, 60)}`);
      continue;
    }
    const t = l.trim();
    if (t === "exit 1") continue;
    if (t.startsWith('echo "::error::') && t.endsWith('"')) {
      const inner = t.slice('echo "'.length, -1).replace(/\\./g, "");
      if (/["`]|\$\(/.test(inner)) v.push(`an echo in the HALT body can run code (unescaped quote, backtick or $( ): ${t.slice(0, 60)}`);
      continue;
    }
    if (/^grep -F\b[^;&|]* tfplan\.txt >&2( \|\| true)?$/.test(t)) continue;
    v.push(`executable line in the HALT body that is not an echo, the plan-line grep or the final exit 1: ${t.slice(0, 80)}`);
  }
  if (body.some((l) => /\bexit 0\b/.test(l) && !/^\s*echo\b/.test(l))) v.push("the HALT body can `exit 0`");
  if (body.some((l) => /ack|skip|override|bypass/i.test(l) && !/^\s*echo\b/.test(l))) v.push("the HALT body carries an acknowledgement/skip path");
  // Everything from the START of the apply step's run block through the HALT: an allow-list, not a heuristic.
  v.push(...destroyGuardPrefixViolations(lines, readIdx, start, end));
  return v;
}

describe("the web-class passphrase pair is reachable only from the apply job, which carries the rotation HALT (#9377)", () => {
  let wf: string;
  let jobIds: string[];
  let applyCode: string;

  function jobIdsOf(text: string): string[] {
    const idx = text.indexOf("\njobs:\n");
    if (idx < 0) return [];
    const ids: string[] = [];
    for (const line of text.slice(idx).split("\n")) {
      const m = /^ {2}([A-Za-z0-9_-]+):\s*$/.exec(line);
      if (m) ids.push(m[1]);
    }
    return ids;
  }
  const baseOf = (a: string) => a.replace(/\[.*$/, "");
  const reachesByFlag = (code: string, a: string) =>
    new RegExp(`-(?:replace|target)(?:=\\s*|\\s+)\\\\?['"]?${escRe(a)}(?![A-Za-z0-9_])`).test(code);

  beforeAll(() => {
    wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
    jobIds = jobIdsOf(wf);
    applyCode = stripShellLineComments(extractJobBlock(wf, "apply"));
  });

  test("the job census is non-vacuous (apply plus the dispatch jobs were all extracted)", () => {
    expect(jobIds).toContain("apply");
    for (const dispatch of ["web_host_create", "web_host_replace", "workspaces_luks_cutover", "workspaces_luks_recut", "inngest_host_replace"]) {
      expect(jobIds, `${dispatch} must be among the extracted jobs`).toContain(dispatch);
    }
    expect(jobIds.length).toBeGreaterThanOrEqual(15);
    const applyTargets = extractTargetsWithKeys(extractJobBlock(wf, "apply")).map(baseOf);
    expect(applyTargets.length).toBeGreaterThanOrEqual(50);
  });

  test("the apply job -targets both members of the pair", () => {
    const applyTargets = new Set(extractTargetsWithKeys(extractJobBlock(wf, "apply")).map(baseOf));
    for (const a of WEB_PASSPHRASE_PAIR) {
      expect(applyTargets.has(a), `${a} must be in the apply job's -target list`).toBe(true);
    }
  });

  test("NO other job in the workflow -targets or -replaces either member of the pair", () => {
    for (const id of jobIds.filter((j) => j !== "apply")) {
      const text = extractJobBlock(wf, id);
      expect(text, `job ${id} must extract non-empty`).not.toEqual("");
      // Scan the JOINED logical lines: a `\`-continuation between the flag and its value must not evade the scan.
      const code = joinContinuations(stripComments(text));
      const targets = new Set(extractTargetsWithKeys(code).map(baseOf));
      for (const a of WEB_PASSPHRASE_PAIR) {
        expect(targets.has(a), `job ${id} must not -target ${a}`).toBe(false);
      }
      // -replace, and a bare mention in a command line, are the other ways to reach it.
      for (const a of WEB_PASSPHRASE_PAIR) {
        expect(reachesByFlag(code, a), `job ${id} must not -replace or -target ${a}`).toBe(false);
      }
    }
  });

  test("NO other workflow FILE -targets or -replaces either member of the pair (apply-deploy-pipeline-fix shares the filter but has no luks HALT)", () => {
    const dir = resolve(REPO_ROOT, ".github/workflows");
    const files = readdirSync(dir).filter((f) => /\.ya?ml$/.test(f) && f !== "apply-web-platform-infra.yml");
    expect(files, "the scan must cover the sibling main-root planners").toContain("apply-deploy-pipeline-fix.yml");
    expect(files.length).toBeGreaterThan(10);
    for (const f of files) {
      const text = readFileSync(join(dir, f), "utf8");
      const code = joinContinuations(stripComments(text));
      const targets = new Set(extractTargetsWithKeys(code).map(baseOf));
      for (const a of WEB_PASSPHRASE_PAIR) {
        expect(targets.has(a), `${f} must not -target ${a}`).toBe(false);
        expect(reachesByFlag(code, a), `${f} must not -replace or -target ${a}`).toBe(false);
      }
    }
  });

  test("the reach scan sees a flag and its value split by a line continuation (instrument rows)", () => {
    const a = "random_password.workspaces_luks_web";
    const scan = (t: string) => {
      const code = joinContinuations(stripComments(t));
      return reachesByFlag(code, a) || extractTargetsWithKeys(code).map(baseOf).includes(a);
    };
    expect(scan("terraform apply \\\n  -replace=random_password.workspaces_luks_web tfplan")).toBe(true);
    expect(scan("terraform apply \\\n  -target \\\n  random_password.workspaces_luks_web tfplan")).toBe(true);
    expect(scan("terraform apply \\\n  -target=\\\n  random_password.workspaces_luks_web tfplan")).toBe(true);
    expect(scan("terraform apply \\\n  -target=random_password.workspaces_luks_web_x tfplan")).toBe(false);
    expect(scan("terraform apply \\\n  -target=hcloud_server.web tfplan")).toBe(false);
    // Without the join the continuation forms evade (the defect this row closes).
    expect(reachesByFlag(stripComments("terraform apply \\\n  -target \\\n  random_password.workspaces_luks_web tfplan"), a)).toBe(false);
  });

  test("the apply job carries the rotation HALT, parsed, validated and BEFORE the destroy_count sum", () => {
    expect(applyCode).toContain("luks_rotations=$(echo \"$counts\" | jq -r '.luks_passphrase_rotations')");
    expect(applyCode.search(/if \[\[ "\$luks_rotations" -gt 0 \]\]; then/), "the HALT must exist").toBeGreaterThan(-1);
    expect(applyCode.indexOf("destroy_count=$((resource_deletes"), "the destroy_count sum must exist").toBeGreaterThan(-1);
    // Structural: unconditional, ack-free, ends in `exit 1`, positioned before the sum (see luksHaltViolations).
    expect(luksHaltViolations(applyCode)).toEqual([]);
  });

  // MUTANTS of the checker itself: each is an implementation that satisfies the old text pins while defeating the
  // HALT. A checker row that stays green on any of these proves nothing.
  describe("luksHaltViolations rejects each way of defeating the HALT", () => {
    const mutate = (code: string, edit: (lines: string[], start: number, end: number, read: number, sum: number) => string[]): string => {
      const lines = code.split("\n");
      const start = lines.findIndex((l) => /^\s*if \[\[ "\$luks_rotations" -gt 0 \]\]; then\s*$/.test(l));
      const ind = /^(\s*)/.exec(lines[start])![1];
      const end = lines.findIndex((l, i) => i > start && l === `${ind}fi`);
      const read = lines.findIndex((l) => l.includes("luks_rotations=$(echo"));
      const sum = lines.findIndex((l) => l.includes("destroy_count=$((resource_deletes"));
      expect(start, "the HALT must be locatable for the mutant").toBeGreaterThan(-1);
      return edit(lines, start, end, read, sum).join("\n");
    };
    const exitIdx = (lines: string[], end: number) => end - 1;

    test("control: the unmutated code is clean (an always-red checker would pass every row below)", () => {
      expect(luksHaltViolations(applyCode)).toEqual([]);
    });
    test("an ALLOW_LUKS short-circuit before the exit 1 is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(exitIdx(l, e), 0, '            [[ -n "${ALLOW_LUKS:-}" ]] && exit 0'), l));
      expect(luksHaltViolations(m).join("\n")).toContain("executable line in the HALT body");
    });
    test("an exit 0 in place of the exit 1 is refused", () => {
      const m = mutate(applyCode, (l, s, e) => ((l[exitIdx(l, e)] = l[exitIdx(l, e)].replace("exit 1", "exit 0")), l));
      expect(luksHaltViolations(m).join("\n")).toContain("END in an unconditional");
    });
    test("a conditional exit 1 is refused", () => {
      const m = mutate(applyCode, (l, s, e) => ((l[exitIdx(l, e)] = '            [[ -z "${ALLOW_LUKS:-}" ]] && exit 1'), l));
      expect(luksHaltViolations(m).join("\n")).toContain("END in an unconditional");
    });
    test("an exit 1 nested under a condition is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(exitIdx(l, e), 1, '            if [[ -z "${ALLOW_LUKS:-}" ]]; then', "              exit 1", "            fi", "            exit 1"), l));
      expect(luksHaltViolations(m).join("\n")).toMatch(/nested or mis-indented|executable line in the HALT body/);
    });
    test("an acknowledgement token in an executable body line is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(exitIdx(l, e), 0, '            ack_ok=${ack_destroy:-false}'), l));
      expect(luksHaltViolations(m).join("\n")).toContain("acknowledgement/skip path");
    });
    test("a body without an exit is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(exitIdx(l, e), 1), l));
      expect(luksHaltViolations(m).join("\n")).toContain("END in an unconditional");
    });
    const ALLOW = "outside the destroy-guard allow-list";
    test("an early short-circuit exit between the counter read and the HALT is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => (l.splice(r + 1, 0, '          [[ -n "${ALLOW_LUKS:-}" ]] && exit 0'), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("a counter rewrite keyed on the commit message (no exit, no return) is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => (l.splice(r + 1, 0, '          [[ "$HEAD_MSG" == *"[ack-luks]"* ]] && luks_rotations=0'), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("an echo-prefixed short-circuit (echo x; [[ ... ]] && exit 0) is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => (l.splice(r + 1, 0, '          echo x; [[ -n "${SKIP_LUKS:-}" ]] && exit 0'), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("a short-circuit on the line BEFORE the counts=$(jq …) read skips the whole guard and is refused", () => {
      const m = mutate(applyCode, (l) => {
        const c = l.findIndex((x) => x.includes("counts=$(jq -f"));
        l.splice(c, 0, '          [[ -n "${SKIP_GUARD:-}" ]] && exit 0');
        return l;
      });
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("a short-circuit at the very start of the step (before the plan runs) is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => {
        let run = r;
        while (run > 0 && !/^\s*run:\s*[|>]/.test(l[run])) run--;
        l.splice(run + 1, 0, '          [[ "$HEAD_MSG" == *"[skip-web-platform-apply]"* ]] && exit 0');
        return l;
      });
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("an exit 0 inside the undecidable HALT body is refused", () => {
      const m = mutate(applyCode, (l) => {
        const u = l.findIndex((x) => x.includes('"$undecidable_entries" -gt 0'));
        const x = l.findIndex((y, i) => i > u && /^\s*exit 1\s*$/.test(y));
        l[x] = l[x].replace("exit 1", "exit 0");
        return l;
      });
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("a counter read swapped to a different key (luks_rotations from resource_deletes) is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => ((l[r] = l[r].replace(".luks_passphrase_rotations", ".resource_deletes")), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    // The four one-line edits that an allow-list of line SHAPES accepted AND that run past the HALT (each is also run,
    // unchecked, by T64m in the counter suite, which shows rc 0: the checker rows below are what stops them).
    test("(a) an `exit $rc` inserted just before the HALT if (rc is 0 after a good plan) is refused", () => {
      const m = mutate(applyCode, (l, s) => (l.splice(s, 0, "          exit $rc"), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("(b) a second `if [[ $rc -ne 0 ]]` wrapped around the HALT with an extra fi is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(e + 1, 0, "          fi"), l.splice(s, 0, "          if [[ $rc -ne 0 ]]; then"), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("(c) an echo that assigns through an array subscript inside a parameter expansion is refused", () => {
      const m = mutate(applyCode, (l, s) => (l.splice(s, 0, '          echo "::error::${a[luks_rotations=0]:-}"'), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("(d) a plan-line grep that assigns through an array subscript is refused", () => {
      const m = mutate(applyCode, (l, s) => (l.splice(s, 0, "          grep -F x${a[luks_rotations=0]:-} tfplan.txt >&2 || true"), l));
      expect(luksHaltViolations(m).join("\n")).toContain(ALLOW);
    });
    test("(e) an arithmetic or command-substitution expansion inside an echo is refused", () => {
      for (const bad of ['echo "::error::$((luks_rotations=0))"', 'echo "::error::$(true)"', 'echo "::error::`true`"', 'echo "::error::${HOME}"']) {
        const m = mutate(applyCode, (l, s) => (l.splice(s, 0, `          ${bad}`), l));
        expect(luksHaltViolations(m).join("\n"), bad).toContain(ALLOW);
      }
    });
    test("(f) a stray fi or a grep that is not the literal six-address -F form is refused", () => {
      const stray = mutate(applyCode, (l, s) => (l.splice(s, 0, "          fi"), l));
      expect(luksHaltViolations(stray).join("\n")).toContain(ALLOW);
      const grep = mutate(applyCode, (l) => {
        const g = l.findIndex((x) => /^\s*grep -F -e random_password\.inngest_redis_luks/.test(x));
        l[g] = "          grep -F -e random_password.inngest_redis_luks -e 'Plan:' tfplan.txt >&2 || true";
        return l;
      });
      expect(luksHaltViolations(grep).join("\n")).toContain(ALLOW);
    });
    test("removing the luks_rotations numeric validation from the validation line is refused (every counter is required)", () => {
      const m = mutate(applyCode, (l) => {
        const n = l.findIndex((x) => x.includes('! "$luks_rotations" =~ ^[0-9]+$'));
        expect(n, "the numeric validation line must be locatable").toBeGreaterThan(-1);
        l[n] = l[n].replace(' || [[ ! "$luks_rotations" =~ ^[0-9]+$ ]]', "");
        return l;
      });
      expect(luksHaltViolations(m).join("\n")).toContain("numeric validation");
    });
    test("removing ANY single counter from the numeric validation is refused", () => {
      for (const c of ["resource_deletes", "nested_deletes", "reboot_updates", "host_creates", "apex_move_orphans", "luks_rotations", "undecidable_entries"]) {
        const m = mutate(applyCode, (l) => {
          const n = l.findIndex((x) => x.includes(`! "$${c}" =~ ^[0-9]+$`));
          const before = l[n];
          l[n] = l[n].replace(new RegExp(` \\|\\| \\[\\[ ! "\\$${c}" =~ \\^\\[0-9\\]\\+\\$ \\]\\]|\\[\\[ ! "\\$${c}" =~ \\^\\[0-9\\]\\+\\$ \\]\\] \\|\\| `), "");
          expect(l[n], `the ${c} removal must land`).not.toBe(before);
          return l;
        });
        expect(luksHaltViolations(m).join("\n"), c).toContain("numeric validation");
      }
    });
    test("a removed counter read is refused", () => {
      const m = mutate(applyCode, (l, s, e, r) => (l.splice(r, 1), l));
      expect(luksHaltViolations(m).join("\n")).toMatch(/counter read for luks_rotations is missing|is not read from the destroy-guard/);
    });
    test("a HALT moved after the destroy_count sum is refused", () => {
      const m = mutate(applyCode, (l, s, e) => {
        const block = l.splice(s, e - s + 1);
        const newSum = l.findIndex((x) => x.includes("destroy_count=$((resource_deletes"));
        l.splice(newSum + 1, 0, ...block);
        return l;
      });
      expect(luksHaltViolations(m).join("\n")).toContain("AFTER the destroy_count sum");
    });
    test("a HALT nested one level deeper than the counter read is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(s, e - s + 1, ...l.slice(s, e + 1).map((x) => `  ${x}`)), l));
      expect(luksHaltViolations(m).join("\n")).toContain("different level");
    });
    test("an echo that can run code (an unescaped quote closing the string) is refused", () => {
      const m = mutate(applyCode, (l, s, e) => (l.splice(exitIdx(l, e), 0, '            echo "::error::x"; [[ -n "${ALLOW_LUKS:-}" ]] && exit 0; echo "y"'), l));
      expect(luksHaltViolations(m).join("\n")).toContain("can run code");
    });
  });

  test("the HALT names every counted address and its plan-line grep reaches all of them (derived from the filter, not retyped)", () => {
    const addrs = luksPassphraseAddrs(readFileSync(LUKS_FILTER, "utf8"));
    expect(addrs.length, "luks_passphrase_addrs must parse (six members)").toBeGreaterThanOrEqual(6);
    for (const a of ["random_password.workspaces_luks", "random_password.workspaces_luks_web", "doppler_secret.workspaces_luks_key", "doppler_secret.workspaces_luks_web_key"]) {
      expect(addrs, `${a} must be a counted address`).toContain(a);
    }
    const halt = applyCode.split("\n");
    const start = halt.findIndex((l) => /^\s*if \[\[ "\$luks_rotations" -gt 0 \]\]; then\s*$/.test(l));
    const end = halt.findIndex((l, i) => i > start && /^ {10}fi\s*$/.test(l));
    const body = halt.slice(start, end);
    const message = body.find((l) => l.includes("terraform plan would CREATE, UPDATE, DELETE or FORGET")) ?? "";
    const grepLine = body.find((l) => /^\s*grep -F\b/.test(l)) ?? "";
    expect(message, "the HALT headline must exist").not.toBe("");
    expect(grepLine, "the plan-line grep must exist").not.toBe("");
    expect(missingAddrs(message, addrs), "the HALT headline must name every counted address").toEqual([]);
    expect(missingAddrs(grepLine, addrs), "the plan-line grep must name every counted address").toEqual([]);
    expect(grepLine, "the plan-line grep must not truncate the lines it exists to show").not.toMatch(/\|\s*head\b/);
    // Instrument rows: dropping ONE address from the text must red, including the one that is a prefix of another.
    const dropped = message.replace("random_password.workspaces_luks, ", "");
    expect(dropped).not.toBe(message);
    expect(missingAddrs(dropped, addrs)).toEqual(["random_password.workspaces_luks"]);
    const droppedWeb = message.replace(", random_password.workspaces_luks_web", "");
    expect(droppedWeb).not.toBe(message);
    expect(missingAddrs(droppedWeb, addrs)).toEqual(["random_password.workspaces_luks_web"]);
  });
});

// --- the d6 rotate marker and the flip gate that reads it (#10166) ------------------------------
// The flip's d6_replace_stale precondition matched a step NAME (`rotate confirm token`) that is
// unconditional and concludes success on EVERY target, so a plain replace or a plan-only rotate
// discharged it. The fix is a last-step marker plus a gate that reads it through
// scripts/lib/git-data-rotate-stamp.sh. Both endpoints are unit-tested elsewhere (the lib suite and
// the census); what pins the WIRE between them is here: the marker's position and `if:`, the gate
// sourcing and calling the lib in order, the name constants shared by lib and workflow, and the
// confirm-token step staying unconditional and unread. Every text pin runs on comment-stripped,
// line-anchored text (a comment can quote the forbidden spelling), and the structural pins read
// the PARSED job steps so a quoting variant of `always()` or `continue-on-error` cannot hide.
const MARKER_IF = "inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true";
const CONFIRM_STEP = "Validate dispatch inputs (rotate confirm token)";

/** The step block holding `id: <id>` (header to the next step or job header), or null. */
function extractStepById(workflowText: string, id: string): string | null {
  const lines = workflowText.split("\n");
  const idAt = lines.findIndex((l) => new RegExp(`^ {8}id: ${id}\\s*$`).test(l));
  if (idAt === -1) return null;
  let start = idAt;
  while (start >= 0 && !/^ {6}- name:/.test(lines[start])) start--;
  if (start < 0) return null;
  let end = lines.length;
  for (let i = idAt + 1; i < lines.length; i++) {
    if (/^ {6}- name:/.test(lines[i]) || /^ {2}[A-Za-z0-9_-]+:/.test(lines[i])) {
      end = i;
      break;
    }
  }
  return lines.slice(start, end).join("\n");
}

/** Violations of the marker/gate/constants wiring; empty on a healthy tree. */
function checkRotateMarkerWiring(applyText: string, cutoverText: string, libText: string): string[] {
  const v: string[] = [];
  const constant = (name: string): string | null =>
    libText.match(new RegExp(`^readonly ${name}="([^"]*)"$`, "m"))?.[1] ?? null;
  const jobId = constant("GDRS_JOB_NAME");
  const preName = constant("GDRS_PRECONDITION_STEP");
  const applyName = constant("GDRS_APPLY_STEP");
  const markerName = constant("GDRS_MARKER_STEP");
  for (const [k, val] of [["GDRS_JOB_NAME", jobId], ["GDRS_PRECONDITION_STEP", preName], ["GDRS_APPLY_STEP", applyName], ["GDRS_MARKER_STEP", markerName]] as const) {
    if (val === null || val === "") v.push(`lib constant ${k} is missing or empty`);
  }
  if (!jobId || !preName || !applyName || !markerName) return v;
  // P-h: the em dash is U+2014 in both lib constants that carry one.
  if (!preName.includes("\u2014") || !applyName.includes("\u2014")) v.push("the lib's precondition/apply constants lost the U+2014 em dash");

  let steps: Array<Record<string, unknown>>;
  try {
    const doc = parseYaml(applyText) as { jobs: Record<string, { name?: unknown; steps?: Array<Record<string, unknown>> }> };
    steps = doc.jobs[jobId]?.steps ?? [];
    // The lib matches the job by its DISPLAY name, which is the job id only while the job has no `name:`.
    if ("name" in (doc.jobs[jobId] ?? {})) v.push(`job ${jobId} gained a name: key, so the lib's exact job-name match no longer sees it`);
    if ("continue-on-error" in (doc.jobs[jobId] ?? {})) v.push(`job ${jobId} carries continue-on-error, so a failed job could still read green`);
    // The marker only means "the whole job succeeded" if no step can fail while the job stays green.
    for (const st of steps) if ("continue-on-error" in st) v.push(`step '${String(st.name)}' of ${jobId} carries continue-on-error, so a failed step could still reach the marker`);
    // No other job may carry the job's display name or a marker-named step (the lib reads `.jobs[]` by name).
    for (const [id, job] of Object.entries(doc.jobs)) {
      if (id === jobId) continue;
      if (job.name === jobId) v.push(`job ${id} is named '${jobId}', so the lib could read it as the replace job`);
      if ((job.steps ?? []).some((st) => st.name === markerName)) v.push(`job ${id} carries a step named '${markerName}'`);
    }
  } catch (e) {
    return [...v, `the apply workflow does not parse: ${(e as Error).message.split("\n")[0]}`];
  }
  if (steps.length === 0) return [...v, `job ${jobId} has no steps (the lib's GDRS_JOB_NAME no longer names a job)`];
  const named = (n: string) => steps.filter((s) => s.name === n);
  // P-a: position. The marker is the literal last step, directly after Dispatch summary.
  if (steps[steps.length - 1].name !== markerName) v.push(`the last step of ${jobId} is '${String(steps[steps.length - 1].name)}', not the marker '${markerName}'`);
  if (steps.length < 2 || steps[steps.length - 2].name !== "Dispatch summary") v.push("the step before the marker is not 'Dispatch summary'");
  // P-g: constants parity. Each name exists exactly once in the job.
  for (const [what, n] of [["marker", markerName], ["precondition", preName], ["apply", applyName]] as const) {
    if (named(n).length !== 1) v.push(`the ${what} step '${n}' appears ${named(n).length} times in ${jobId} (expected exactly 1)`);
  }
  // P-b: the marker's `if:` is exactly the ruled string, and it carries no other gating key.
  const marker = named(markerName)[0];
  if (marker) {
    if (marker.if !== MARKER_IF) v.push(`the marker's if: is '${String(marker.if)}', not '${MARKER_IF}'`);
    for (const key of ["continue-on-error", "timeout-minutes"]) if (key in marker) v.push(`the marker carries ${key}`);
  }
  // P-c: the name matches none of the census G5 gate-name patterns
  // (tests/scripts/test-infra-privileged-tier-census.sh GATE_NAME) and, per the #10166 ruling, carries
  // neither 'Validate' nor 'confirm'.
  if (/interlock|validate|confirm|verify\s+required|preflight/i.test(markerName)) v.push("the marker's name matches a census gate-name pattern or contains 'Validate'/'confirm'");
  // P-d: the confirm-token step still exists once and stays unconditional (census G5c).
  const confirm = named(CONFIRM_STEP);
  if (confirm.length !== 1) v.push(`the confirm-token step appears ${confirm.length} times (expected 1)`);
  else if ("if" in confirm[0]) v.push("the confirm-token step gained an if: (it must stay unconditional, census G5c)");

  // P-e/P-f: the gate. Pins run on the comment-stripped flip_preconditions step.
  const rawGate = extractStepById(cutoverText, "flip_preconditions");
  if (rawGate === null) return [...v, "the flip_preconditions step was not found in git-data-cutover.yml"];
  const gate = stripComments(rawGate);
  if (!/^ {10}source "\$\{GITHUB_WORKSPACE:\?\}\/scripts\/lib\/git-data-rotate-stamp\.sh" \|\| fail d6_run_unreadable /m.test(gate)) v.push("the gate does not source the stamp lib with a fail-closed || fail");
  if ((gate.match(/git_data_d6_scan/g) ?? []).length !== 1) v.push("the gate must call git_data_d6_scan exactly once");
  if (!/^ {12}\*\) fail d6_run_unreadable /m.test(gate)) v.push("the gate's case has no fail-closed *) arm");
  // P-f: the gate no longer reads the confirm-token step or inlines a step-selection jq.
  const cutoverStripped = stripComments(cutoverText);
  if (/rotate confirm token/i.test(cutoverStripped)) v.push("git-data-cutover.yml still reads the 'rotate confirm token' step");
  if (/select\(\.name \| test\(/.test(cutoverStripped)) v.push("git-data-cutover.yml still has an inline step-selection jq");
  if (/\bjobs_json=/.test(cutoverStripped)) v.push("git-data-cutover.yml still captures jobs_json inline");
  return v;
}

describe("the d6 rotate marker and the flip gate that reads it (#10166)", () => {
  const applyText = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const cutoverText = readFileSync(resolve(REPO_ROOT, ".github/workflows/git-data-cutover.yml"), "utf8");
  const libText = readFileSync(resolve(REPO_ROOT, "scripts/lib/git-data-rotate-stamp.sh"), "utf8");

  test("the real tree satisfies every wiring pin (marker last + exact if:, gate sources/scans/cases, constants, confirm step unconditional)", () => {
    expect(checkRotateMarkerWiring(applyText, cutoverText, libText)).toEqual([]);
  });

  test("twelve mutants of the wiring each make the check non-empty, for the right reason, and each mutation actually landed", () => {
    const markerRun = 'run: echo "git-data-host-rotate completed - apply, boot poll, pin load and summary succeeded (the d6 marker)"';
    const mutants: Array<{ label: string; want: RegExp; apply?: (s: string) => string; cutover?: (s: string) => string; lib?: (s: string) => string }> = [
      { label: "drop the plan_only conjunct", want: /the marker's if: is/, apply: (s) => s.replace(` && inputs.plan_only != true\n        ${markerRun}`, `\n        ${markerRun}`) },
      { label: "drop the apply_target conjunct", want: /the marker's if: is/, apply: (s) => s.replace(`if: inputs.apply_target == 'git-data-host-rotate' && inputs.plan_only != true\n        ${markerRun}`, `if: inputs.plan_only != true\n        ${markerRun}`) },
      { label: "add always() to the marker", want: /the marker's if: is/, apply: (s) => s.replace(`if: ${MARKER_IF}\n        ${markerRun}`, `if: always() && ${MARKER_IF}\n        ${markerRun}`) },
      { label: "append a step after the marker", want: /the last step of git_data_host_replace is/, apply: (s) => s.replace(`        ${markerRun}\n`, `        ${markerRun}\n\n      - name: Trailing step\n        run: echo trailing\n`) },
      {
        label: "restore the old confirm-token read in the gate",
        want: /still reads the 'rotate confirm token' step/,
        cutover: (s) => s.replace('          d6="$(git_data_d6_scan <<<"$ids")" || true\n', '          d6="$(git_data_d6_scan <<<"$ids")" || true\n          rotate_ok="$(jq -r \'.steps[] | select(.name | test("rotate confirm token"; "i")) | .conclusion\' <<<"$jobs_json")"\n'),
      },
      {
        label: "add continue-on-error to the apply step",
        want: /carries continue-on-error/,
        apply: (s) => s.replace("      - name: Terraform apply (git-data-host -replace) \u2014 post-apply backstop\n", "      - name: Terraform apply (git-data-host -replace) \u2014 post-apply backstop\n        continue-on-error: true\n"),
      },
      { label: "give the job a name: key", want: /gained a name: key/, apply: (s) => s.replace("\n  git_data_host_replace:\n", "\n  git_data_host_replace:\n    name: git-data host replace\n") },
      {
        label: "carry the marker step name in another job",
        want: /carries a step named/,
        apply: (s) => {
          const at = s.indexOf("      - name: Dispatch summary", s.indexOf("      - name: Rotate completed (d6 marker)"));
          return at < 0 ? s : s.slice(0, at) + "      - name: Rotate completed (d6 marker)" + s.slice(at + "      - name: Dispatch summary".length);
        },
      },
      { label: "add continue-on-error to the job", want: /job git_data_host_replace carries continue-on-error/, apply: (s) => s.replace("\n  git_data_host_replace:\n", "\n  git_data_host_replace:\n    continue-on-error: true\n") },
      {
        label: "name another job like the replace job",
        want: /is named 'git_data_host_replace'/,
        apply: (s) => s.replace("\n  workspaces_luks_cutover:\n", "\n  workspaces_luks_cutover:\n    name: git_data_host_replace\n"),
      },
      {
        label: "rename the marker to a census gate-name pattern (workflow and lib together)",
        want: /matches a census gate-name pattern/,
        apply: (s) => s.replace("      - name: Rotate completed (d6 marker)\n", "      - name: Rotate preflight done\n"),
        lib: (s) => s.replace('readonly GDRS_MARKER_STEP="Rotate completed (d6 marker)"', 'readonly GDRS_MARKER_STEP="Rotate preflight done"'),
      },
      { label: "change one character of the marker constant", want: /the last step of git_data_host_replace is|appears 0 times/, lib: (s) => s.replace('readonly GDRS_MARKER_STEP="Rotate completed (d6 marker)"', 'readonly GDRS_MARKER_STEP="Rotate completed (d6 markes)"') },
    ];
    expect(mutants.length).toBe(12);
    for (const m of mutants) {
      const a = m.apply ? m.apply(applyText) : applyText;
      const c = m.cutover ? m.cutover(cutoverText) : cutoverText;
      const l = m.lib ? m.lib(libText) : libText;
      expect(a !== applyText || c !== cutoverText || l !== libText, `the mutation '${m.label}' did not change any text`).toBe(true);
      const violations = checkRotateMarkerWiring(a, c, l);
      expect(violations, `the mutant '${m.label}' was not caught`).not.toEqual([]);
      // Caught for the RIGHT reason: a mutant that merely breaks the parse would also be non-empty.
      expect(violations.join("\n"), `the mutant '${m.label}' was caught for the wrong reason`).toMatch(m.want);
    }
  });

  test("the gate's d6 block, EXECUTED against a modelled gh, reaches the right verdict for each scan outcome", () => {
    const doc = parseYaml(cutoverText) as { jobs: Record<string, { steps?: Array<{ id?: string; run?: string }> }> };
    const run = Object.values(doc.jobs).flatMap((j) => j.steps ?? []).find((st) => st.id === "flip_preconditions")?.run;
    expect(run, "the flip_preconditions run block must exist").toBeTruthy();
    const failFn = run!.match(/^ *fail\(\) \{.*\}$/m)?.[0];
    expect(failFn, "the step's own fail() must be extractable").toBeTruthy();
    const from = run!.indexOf('source "${GITHUB_WORKSPACE:?}/scripts/lib/git-data-rotate-stamp.sh"');
    const to = run!.indexOf("# deploy_in_flight");
    expect(from, "the d6 block must start at the lib source line").toBeGreaterThan(-1);
    expect(to).toBeGreaterThan(from);
    const blockText = run!.slice(from, to);
    const harnessFor = (block: string) => `set -euo pipefail\n${failFn}\nlast_ok=""\n${block}\necho "LAST_OK=$last_ok"\n`;

    const c = (n: string) => libText.match(new RegExp(`^readonly ${n}="([^"]*)"$`, "m"))![1];
    const [pre, apply, marker] = [c("GDRS_PRECONDITION_STEP"), c("GDRS_APPLY_STEP"), c("GDRS_MARKER_STEP")];
    const job = (conclusion: string | null, steps: Array<[string, string | null]>) =>
      JSON.stringify({ jobs: [{ name: c("GDRS_JOB_NAME"), conclusion, steps: steps.map(([name, conclusion]) => ({ name, conclusion })) }] });
    const stamped = job("success", [[pre, "success"], [apply, "success"], [marker, "success"]]);
    const plain = job("success", [[pre, "skipped"], [apply, "success"], [marker, "skipped"]]);
    const failedRotate = job("failure", [[pre, "success"], [apply, "failure"], [marker, "skipped"]]);
    const inFlight = job(null, [[pre, "success"], [apply, null]]);

    // gh models exactly the two calls the block may make and REFUSES any other argv (exit 64: the full
    // `run list` argv is compared word for word, so an added, removed, reordered or changed selector turns the
    // capture into a failure instead of quietly reading the right fixture). The list goes through the REAL --jq filter.
    const ghStub = `#!/usr/bin/env bash
if [[ "\${1-} \${2-}" == "run list" ]]; then
  [[ $# -eq 14 && "\${*:1:13}" == "run list --workflow apply-web-platform-infra.yml --branch main --event workflow_dispatch --limit 100 --json databaseId,status --jq" ]] \
    || { echo "gh stub refused: $*" >&2; exit 64; }
  jqf="\${14}"
  [[ -f "$FX/list.json" ]] || exit 1
  exec jq -r "$jqf" "$FX/list.json"
fi
if [[ "\${1-} \${2-}" == "run view" && "\${4-}" == "--json" && "\${5-}" == "jobs" && $# -eq 5 ]]; then
  [[ -f "$FX/$3.json" ]] || exit 1
  cat "$FX/$3.json"; exit 0
fi
echo "gh stub refused: $*" >&2
exit 64
`;
    type Case = { name: string; list: Array<[number | string, string]> | null; bodies: Record<number, string>; rc: number; verdict?: string; has?: string[]; hasNot?: string[]; mutate?: [string, string] };
    const cases: Case[] = [
      { name: "an older stamped run behind a newer plain replace discharges D6", list: [[2, "completed"], [1, "completed"]], bodies: { 2: plain, 1: stamped }, rc: 0, has: ["d6 rotate stamp: run 1", "LAST_OK=1"] },
      { name: "only plain replaces leaves D6 open", list: [[2, "completed"]], bodies: { 2: plain }, rc: 1, verdict: "d6_replace_stale", has: ["apply_target=git-data-host-rotate", "NEVER been flipped", "do NOT dispatch it", "#10175", "#8571", "no bypass input"], hasNot: ["re-dispatch it from main"] },
      { name: "an empty run list leaves D6 open", list: [], bodies: {}, rc: 1, verdict: "d6_replace_stale" },
      { name: "a failed newest rotate blocks over an older stamp", list: [[3, "completed"], [1, "completed"]], bodies: { 3: failedRotate, 1: stamped }, rc: 1, verdict: "d6_last_rotate_failed", has: ["run 3", "gh run view 3 --log-failed", "dispatch a FRESH rotate", "Do not re-run the failed run"] },
      { name: "an in-flight newest run blocks over an older stamp", list: [[3, "in_progress"], [1, "completed"]], bodies: { 3: inFlight, 1: stamped }, rc: 1, verdict: "d6_rotate_in_flight", has: ["(run 3)", "Cancel it only if", "never cancel an in_progress run"] },
      { name: "an unreadable newest run blocks over an older stamp", list: [[4, "completed"], [1, "completed"]], bodies: { 1: stamped }, rc: 1, verdict: "d6_run_unreadable", has: ["(run 4)", "gh run view 4 --json jobs"] },
      { name: "a non-numeric id stops the scan and the gate names no run", list: [["abc", "completed"], [1, "completed"]], bodies: { 1: stamped }, rc: 1, verdict: "d6_run_unreadable", has: ["(run n/a)"], hasNot: ["gh run view"] },
      // The bare-stamp guard is unreachable through the real lib (it always prints an id), so drive it by replacing the scan.
      { name: "a stamp reported without a run id fails closed", list: [[1, "completed"]], bodies: { 1: stamped }, rc: 1, verdict: "d6_run_unreadable", has: ["without a run id"], mutate: ['"$(git_data_d6_scan <<<"$ids")"', '"$(echo d6_stamped)"'] },
      { name: "a failed run list blocks", list: null, bodies: {}, rc: 1, verdict: "d6_run_unreadable" },
      // Control: the stub is SELECTIVE. The same block with its --event selector changed is refused by the stub,
      // and the refusal flips the verdict (an accepting stub would have let the stamped fixture discharge D6).
      { name: "CONTROL: a changed selector is refused by the modelled gh", list: [[1, "completed"]], bodies: { 1: stamped }, rc: 1, verdict: "d6_run_unreadable", has: ["gh stub refused"], mutate: ["--event workflow_dispatch", "--event push"] },
    ];
    const root = mkdtempSync(join(tmpdir(), "d6-gate-exec-"));
    try {
      mkdirSync(join(root, "bin"));
      writeFileSync(join(root, "bin", "gh"), ghStub, { mode: 0o755 });
      for (const [i, cs] of cases.entries()) {
        const fx = join(root, `fx${i}`);
        mkdirSync(fx);
        if (cs.list) writeFileSync(join(fx, "list.json"), JSON.stringify(cs.list.map(([databaseId, status]) => ({ databaseId, status }))));
        for (const [id, body] of Object.entries(cs.bodies)) writeFileSync(join(fx, `${id}.json`), body);
        let block = blockText;
        if (cs.mutate) {
          block = blockText.replace(cs.mutate[0], cs.mutate[1]);
          expect(block, `${cs.name}: the mutation must change the block`).not.toBe(blockText);
        }
        const r = spawnSync("bash", ["--noprofile", "--norc", "-c", harnessFor(block)], {
          encoding: "utf8",
          env: { PATH: `${join(root, "bin")}:${process.env.PATH ?? ""}`, HOME: root, LC_ALL: "C", FX: fx, GITHUB_WORKSPACE: REPO_ROOT },
        });
        const out = `${r.stdout}${r.stderr}`;
        expect(r.status, `${cs.name}: exit status (output: ${out.slice(0, 400)})`).toBe(cs.rc);
        if (cs.verdict) expect(out, `${cs.name}: verdict`).toContain(`verdict=${cs.verdict}`);
        for (const h of cs.has ?? []) expect(out, `${cs.name}: output`).toContain(h);
        for (const h of cs.hasNot ?? []) expect(out, `${cs.name}: output must not contain`).not.toContain(h);
      }
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  });
});


// --- suite-level anti-vacuity (#7656 C8) --------------------------------------------------------
// The bash side has had a minimum-cardinality floor since it was written; this file had none. A
// `test.skip` typo, a stray `.only`, or a narrowed filter reports "0 fail" and reads as success —
// the outermost gap, and the one `expectNonEmptyDispatch` cannot see, because it only fires from
// inside a test that RAN.

// --- the rotate's "store never written" gate (#10175) -------------------------------------------
// After the first real flip the LUKS volume may hold the only copy of replicated repositories. The rotate's
// emptiness step reads one boot-time row, so a new step reads git-data-cutover.yml's run records instead
// (scripts/lib/git-data-store-dirty-scan.sh). The lib suite pins the decisions; what pins the WIRE is here:
// the step's position (before the emptiness step, the rung-2 interlock and the plan), its exact `if:`, a
// GITHUB_TOKEN-only environment, no continue-on-error and no input-driven bypass, the job's exact permissions,
// the lib's three name constants against git-data-cutover.yml, and that no other file writes the flag.
const STORE_STEP = "Rotate precondition \u2014 store never written (cutover run records)";
const EMPTY_STEP = "Rotate precondition \u2014 served store measured empty";
const STORE_STEP_IF = "inputs.apply_target == 'git-data-host-rotate'";
const FLAG_WRITERS_ALLOWED = [
  ".github/workflows/git-data-cutover.yml",
  "apps/web-platform/infra/git-data-flag-precheck.sh",
];

/** Violations of the store-never-written wiring; empty on a healthy tree. */
function checkStoreNeverWrittenWiring(applyText: string, cutoverText: string, libText: string): string[] {
  const v: string[] = [];
  const constant = (name: string): string | null =>
    libText.match(new RegExp(`^readonly ${name}="([^"]*)"$`, "m"))?.[1] ?? null;
  const wfFile = constant("GDSD_WORKFLOW_FILE");
  const jobName = constant("GDSD_JOB_NAME");
  const writeStep = constant("GDSD_WRITE_STEP");
  if (wfFile !== "git-data-cutover.yml") v.push(`GDSD_WORKFLOW_FILE is '${String(wfFile)}', not git-data-cutover.yml`);
  if (!jobName || !writeStep) return [...v, "lib constants GDSD_JOB_NAME / GDSD_WRITE_STEP are missing"];
  try {
    const cdoc = parseYaml(cutoverText) as { jobs: Record<string, { name?: unknown; steps?: Array<Record<string, unknown>> }> };
    const cj = cdoc.jobs[jobName];
    if (!cj) v.push(`git-data-cutover.yml has no job '${jobName}'`);
    else {
      if ("name" in cj) v.push(`job ${jobName} gained a name: key, so the scan's exact display-name match no longer sees it`);
      const w = (cj.steps ?? []).filter((st) => st.name === writeStep);
      if (w.length !== 1) v.push(`the flag-write step '${writeStep}' appears ${w.length} times in ${jobName} (expected exactly 1)`);
    }
    const adoc = parseYaml(applyText) as { jobs: Record<string, { permissions?: Record<string, string>; steps?: Array<Record<string, unknown>> }> };
    const job = adoc.jobs["git_data_host_replace"];
    if (!job) return [...v, "git_data_host_replace job not found"];
    const perms = job.permissions ?? {};
    if (JSON.stringify(Object.entries(perms).sort()) !== JSON.stringify([["actions", "read"], ["contents", "read"]])) {
      v.push(`git_data_host_replace permissions are ${JSON.stringify(perms)}, not exactly contents: read + actions: read`);
    }
    const steps = job.steps ?? [];
    const idx = (n: string) => steps.findIndex((st) => st.name === n);
    const at = idx(STORE_STEP);
    if (steps.filter((st) => st.name === STORE_STEP).length !== 1) v.push(`the step '${STORE_STEP}' appears ${steps.filter((st) => st.name === STORE_STEP).length} times (expected exactly 1)`);
    if (at < 0) return [...v, "the store-never-written step is missing"];
    const st = steps[at];
    for (const [what, name] of [["the emptiness step", EMPTY_STEP], ["the rung-2 interlock", "Rung-2 rehearsal interlock (refuses an un-rehearsed payload on the live host)"], ["the terraform plan", "Terraform plan (scoped git-data-host -replace) + destroy-guard"]] as const) {
      const j = idx(name);
      if (j < 0) v.push(`${what} '${name}' was not found`);
      else if (j < at) v.push(`the store-never-written step is AFTER ${what}`);
    }
    if (st.if !== STORE_STEP_IF) v.push(`its if: is '${String(st.if)}', not '${STORE_STEP_IF}'`);
    if ("continue-on-error" in st) v.push("the step carries continue-on-error");
    if (st["timeout-minutes"] !== 10) v.push(`the step's timeout-minutes is ${String(st["timeout-minutes"])}, not 10`);
    const env = (st.env ?? {}) as Record<string, string>;
    if (JSON.stringify(Object.keys(env).sort()) !== JSON.stringify(["GITHUB_REPOSITORY", "GH_TOKEN"].sort())) v.push(`its env is ${JSON.stringify(Object.keys(env))}, not exactly GH_TOKEN + GITHUB_REPOSITORY`);
    if (env.GH_TOKEN !== "${{ secrets.GITHUB_TOKEN }}") v.push("GH_TOKEN is not bound to secrets.GITHUB_TOKEN alone");
    const run = String(st.run ?? "");
    const runStripped = stripComments(run);
    if (/\binputs\./.test(runStripped) || /\$\{\{\s*inputs\./.test(runStripped)) v.push("the step's script reads a dispatch input (a bypass)");
    if (/secrets\.(?!GITHUB_TOKEN)/.test(JSON.stringify(st))) v.push("the step binds a secret other than GITHUB_TOKEN");
    if ((runStripped.match(/git_data_store_dirty_scan/g) ?? []).length !== 1) v.push("the step must call git_data_store_dirty_scan exactly once");
    if (!/\|\s*git_data_store_dirty_scan\)"/.test(runStripped)) v.push("the scan must be called with NO argument (an argument would override the pinned runs)");
    if (!/store_clean\)[\s\S]{0,80}"\$rc" -eq 0/.test(runStripped)) v.push("the store_clean arm must also require the scan's own status to be 0");
    for (const token of ["store_clean", "store_dirty", "cutover_in_flight"]) if (!runStripped.includes(token)) v.push(`the step's case has no ${token} arm`);
    if (!/^\s+\*\) echo "::error::[^\n]*exit 1 ;;/m.test(runStripped)) v.push("the step's case has no fail-closed *) arm");
    if (/\|\|\s*true/.test(runStripped)) v.push("the step swallows a failure with || true");
  } catch (e) {
    return [...v, `a workflow does not parse: ${(e as Error).message.split("\n")[0]}`];
  }
  return v;
}

/** Files (repo-relative) that set GIT_DATA_STORE_ENABLED through doppler, other than the allowed writers. */
function otherFlagWriters(files: Array<[string, string]>): string[] {
  return files
    .filter(([path, text]) => !FLAG_WRITERS_ALLOWED.includes(path) && /doppler\s+secrets\s+set[^\n]*GIT_DATA_STORE_ENABLED|GIT_DATA_STORE_ENABLED[^\n]*doppler\s+secrets\s+set/.test(stripComments(text)))
    .map(([path]) => path);
}

describe("the rotate's store-never-written gate (#10175)", () => {
  const applyText = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const cutoverText = readFileSync(resolve(REPO_ROOT, ".github/workflows/git-data-cutover.yml"), "utf8");
  const libText = readFileSync(resolve(REPO_ROOT, "scripts/lib/git-data-store-dirty-scan.sh"), "utf8");

  test("the real tree satisfies every wiring pin (order, if:, env, permissions, constants, fail-closed arms)", () => {
    expect(checkStoreNeverWrittenWiring(applyText, cutoverText, libText)).toEqual([]);
  });

  test("a mutation battery: each edit to the wiring is caught", () => {
    const sw = (a: string, b: string) => (t: string) => { if (!t.includes(a)) throw new Error(`mutation anchor missing: ${a.slice(0, 50)}`); return t.replace(a, b); };
    const mutants: Array<{ label: string; apply?: (t: string) => string; cutover?: (t: string) => string; lib?: (t: string) => string; want: RegExp }> = [
      { label: "continue-on-error added to the new step", apply: sw(`      - name: ${STORE_STEP}\n        if: ${STORE_STEP_IF}\n`, `      - name: ${STORE_STEP}\n        if: ${STORE_STEP_IF}\n        continue-on-error: true\n`), want: /continue-on-error/ },
      { label: "an input-driven bypass in the step", apply: sw(`          echo "store-never-written verdict: \${verdict}"`, `          [[ "\${{ inputs.reason }}" == force ]] && exit 0\n          echo "store-never-written verdict: \${verdict}"`), want: /dispatch input|bypass/ },
      { label: "if: widened to every replace target", apply: sw(`        if: ${STORE_STEP_IF}\n        timeout-minutes: 10\n        env:\n          GH_TOKEN`, `        if: inputs.apply_target == 'git-data-host-replace'\n        timeout-minutes: 10\n        env:\n          GH_TOKEN`), want: /its if: is/ },
      { label: "a prd Doppler token bound to the step", apply: sw(`          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}\n          GITHUB_REPOSITORY`, `          GH_TOKEN: \${{ secrets.GITHUB_TOKEN }}\n          DOPPLER_TOKEN: \${{ secrets.DOPPLER_TOKEN }}\n          GITHUB_REPOSITORY`), want: /not exactly GH_TOKEN|secret other than/ },
      { label: "actions: read dropped from the job permissions", apply: sw(`    permissions:\n      contents: read\n      actions: read\n    # (#6977)`, `    permissions:\n      contents: read\n    # (#6977)`), want: /permissions/ },
      { label: "an extra scope added to the job permissions", apply: sw(`      actions: read\n    # (#6977)`, `      actions: read\n      packages: read\n    # (#6977)`), want: /permissions/ },
      { label: "step renamed in the workflow", apply: sw(`- name: ${STORE_STEP}`, `- name: Rotate precondition \u2014 store never written`), want: /missing|appears 0 times/ },
      { label: "step moved after the emptiness step", apply: (t) => { const a = t.indexOf(`      - name: ${STORE_STEP}`); const b = t.indexOf(`      # (#8211 PR2 / ADR-220 D6) ROTATE PRECONDITION`); const c = t.indexOf(`      # (#8210) THE RUNG-2 INTERLOCK`); if (a < 0 || b < 0 || c < 0 || !(a < b && b < c)) throw new Error("mutation anchors missing"); return t.slice(0, a) + t.slice(b, c) + t.slice(a, b) + t.slice(c); }, want: /AFTER the emptiness step/ },
      { label: "the *) fail-closed arm removed", apply: sw(`            *) echo "::error::rotate precondition REFUSED (scan_unreadable)`, `            ignored) echo "::error::rotate precondition REFUSED (scan_unreadable)`), want: /fail-closed \*\) arm/ },
      { label: "the lib's write-step constant drifts from the cutover workflow", lib: sw(`GDSD_WRITE_STEP="Write GIT_DATA_STORE_ENABLED (via the"`, `GDSD_WRITE_STEP="Write GIT_DATA_STORE_ENABLED (via the seam"`), want: /appears 0 times/ },
      { label: "the lib's job constant drifts", lib: sw(`readonly GDSD_JOB_NAME="cutover"`, `readonly GDSD_JOB_NAME="cutover2"`), want: /no job 'cutover2'/ },
      { label: "the lib's workflow-file constant drifts", lib: sw(`readonly GDSD_WORKFLOW_FILE="git-data-cutover.yml"`, `readonly GDSD_WORKFLOW_FILE="git-data-cutover2.yml"`), want: /GDSD_WORKFLOW_FILE/ },
      { label: "the cutover job gains a display name", cutover: sw(`  cutover:\n    if: inputs.mode != 'wipe'`, `  cutover:\n    name: Cutover\n    if: inputs.mode != 'wipe'`), want: /gained a name/ },
    ];
    for (const m of mutants) {
      let a = applyText, c = cutoverText, l = libText;
      try { if (m.apply) a = m.apply(a); if (m.cutover) c = m.cutover(c); if (m.lib) l = m.lib(l); } catch (e) { throw new Error(`mutant '${m.label}': ${(e as Error).message}`); }
      const found = checkStoreNeverWrittenWiring(a, c, l);
      expect(found.length, `mutant '${m.label}' was not caught`).toBeGreaterThan(0);
      expect(found.join(" | "), `mutant '${m.label}' was caught for the wrong reason`).toMatch(m.want);
    }
  });

  test("no file other than the cutover workflow and the flag precheck writes GIT_DATA_STORE_ENABLED (a second writer is invisible to the run-record scan)", () => {
    const files = spawnSync("git", ["ls-files", ".github", "scripts", "apps/web-platform/infra", "plugins"], { cwd: REPO_ROOT, encoding: "utf8" }).stdout
      .split("\n").filter((f) => /\.(ya?ml|sh|ts|mjs|py|tf|tmpl)$/.test(f) && !/\.test\./.test(f));
    expect(files.length).toBeGreaterThan(100);
    const read: Array<[string, string]> = files.map((f) => [f, readFileSync(resolve(REPO_ROOT, f), "utf8")] as [string, string]);
    expect(otherFlagWriters(read)).toEqual([]);
    // Control: the detector fires on a synthetic second writer and ignores a comment naming the spelling.
    expect(otherFlagWriters([["x/new.sh", "printf true | doppler secrets set GIT_DATA_STORE_ENABLED -p soleur -c prd"]])).toEqual(["x/new.sh"]);
    expect(otherFlagWriters([["x/new.sh", "# doppler secrets set GIT_DATA_STORE_ENABLED is the only writer"]])).toEqual([]);
  });

  test("the flag-seam credential reaches exactly four steps of the cutover job and no other file in the workflows (a second writer step would be invisible to the scan)", () => {
    const doc = parseYaml(cutoverText) as { jobs: Record<string, { steps?: Array<{ name?: string; env?: Record<string, unknown> }> }> };
    const holders = Object.entries(doc.jobs).flatMap(([id, j]) => (j.steps ?? []).filter((st) => JSON.stringify(st).includes("DOPPLER_TOKEN_GIT_DATA_FLAG")).map((st) => `${id}:${st.name}`)).sort();
    expect(holders).toEqual([
      "cutover:Finalizer \u2014 total unwind on an incomplete flip",
      "cutover:Verify required secrets present",
      "cutover:Write GIT_DATA_LUKS_CUTOVER_AT (last \u2014 proven cutover only)",
      "cutover:Write GIT_DATA_STORE_ENABLED (via the",
    ]);
    const others = spawnSync("git", ["grep", "-l", "DOPPLER_TOKEN_GIT_DATA_FLAG", "--", ".github"], { cwd: REPO_ROOT, encoding: "utf8" }).stdout.split("\n").filter(Boolean);
    expect(others).toEqual([".github/workflows/git-data-cutover.yml"]);
  });

  // --- the REAL run: blocks of both new steps, executed under the Actions default shell with stubbed gh / reader / curl.
  // The wiring pins above are text; these are the only tests that run what the step DECIDES (exit code + annotation).
  const stepRun = (name: string): string => {
    const doc = parseYaml(applyText) as { jobs: Record<string, { steps?: Array<{ name?: string; run?: string }> }> };
    const run = (doc.jobs["git_data_host_replace"].steps ?? []).find((st) => st.name === name)?.run;
    if (!run) throw new Error(`step not found: ${name}`);
    return run;
  };
  const PINS = libText.match(/^readonly GDSD_PINNED_RUNS="(\d+) (\d+)"$/m);
  if (!PINS) throw new Error("GDSD_PINNED_RUNS is not two run ids in the library");
  const PIN_A = PINS[1];
  const PIN_B = PINS[2];
  const WRITE_STEP = "Write GIT_DATA_STORE_ENABLED (via the";
  const jobsBody = (writeConclusion: string) =>
    JSON.stringify({ jobs: [{ name: "cutover", conclusion: "success", steps: [{ name: "x", conclusion: "success" }, { name: WRITE_STEP, conclusion: writeConclusion }] }] });
  const runStep = (run: string, env: Record<string, string>, files: Record<string, string>, bins: Record<string, string>) => {
    const root = mkdtempSync(join(tmpdir(), "step-exec-"));
    try {
      mkdirSync(join(root, "bin"));
      mkdirSync(join(root, "fx"));
      for (const [n, body] of Object.entries(bins)) { writeFileSync(join(root, "bin", n), `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 }); }
      for (const [n, body] of Object.entries(files)) writeFileSync(join(root, "fx", n), body);
      writeFileSync(join(root, "step.sh"), run);
      const r = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", join(root, "step.sh")], {
        encoding: "utf8",
        env: { PATH: `${join(root, "bin")}:/usr/bin:/bin`, HOME: root, RUNNER_TEMP: root, FX: join(root, "fx"), GITHUB_WORKSPACE: REPO_ROOT, ...env },
      });
      return { rc: r.status, out: `${r.stdout}${r.stderr}` };
    } finally {
      rmSync(root, { recursive: true, force: true });
    }
  };
  // gh models exactly the three api shapes of the library and refuses anything else (exit 64).
  const GH_STUB = `
repo="example-org/example-repo"
base="repos/$repo/actions/workflows/git-data-cutover.yml/runs"
if [[ "\${1-}" == api && "\${2-}" == "$base?per_page=1" && "\${3-}" == --jq && -n "\${4-}" ]]; then
  [[ -f "$FX/total" ]] || exit 1; jq -n --argjson n "$(cat "$FX/total")" '{total_count: $n}' | jq -r "$4"; exit $?; fi
if [[ "\${1-}" == api && "\${2-}" == --paginate && "\${3-}" == "$base?per_page=100" && "\${4-}" == --jq && -n "\${5-}" ]]; then
  [[ -f "$FX/list.tsv" ]] || exit 1
  jq -R -s 'split("\\n") | map(select(length > 0) | split("\\t")) | {workflow_runs: map({id: (.[0] | tonumber? // .[0]), status: .[1], run_attempt: (.[2] | tonumber? // .[2]), created_at: .[3]})}' "$FX/list.tsv" | jq -r "$5"; exit $?; fi
if [[ "\${1-}" == api && "\${2-}" =~ ^repos/$repo/actions/runs/([0-9]+)/attempts/([0-9]+)/jobs\\?per_page=100$ && $# -eq 2 ]]; then
  f="$FX/\${BASH_REMATCH[1]}.\${BASH_REMATCH[2]}.json"; [[ -f "$f" ]] || exit 1; cat "$f"; exit 0; fi
echo "gh stub refused: $*" >&2; exit 64`;
  const scenario = (rows: Array<[string, string]>, jobs: Record<string, string>) => {
    const files: Record<string, string> = { total: `${rows.length}\n`, "list.tsv": rows.map(([id, st]) => `${id}\t${st}\t1\t2026-10-01T00:00:00Z\n`).join("") };
    for (const [id, body] of Object.entries(jobs)) files[`${id}.1.json`] = body;
    return files;
  };
  const clean = jobsBody("skipped");
  const storeEnv = { GITHUB_REPOSITORY: "example-org/example-repo", GH_TOKEN: "synthetic-token" };

  test("EXECUTED store-never-written step: each verdict maps to its exit code and annotation (and a mutant of any arm changes an outcome)", () => {
    const run = stepRun(STORE_STEP);
    // A workspace whose library prints store_clean but returns status 1: the verdict word and the scan's own status
    // must agree, and a disagreement refuses (the guard the real library cannot reach, so it is driven by a stub).
    const stubWs = mkdtempSync(join(tmpdir(), "stub-ws-"));
    mkdirSync(join(stubWs, "scripts", "lib"), { recursive: true });
    writeFileSync(join(stubWs, "scripts", "lib", "git-data-store-dirty-scan.sh"), "git_data_store_dirty_list() { :; }\ngit_data_store_dirty_scan() { echo store_clean; return 1; }\n");
    const cases: Array<{ name: string; files: Record<string, string>; env?: Record<string, string>; rc: number; has: string[] }> = [
      { name: "clean, both pins listed", files: scenario([[PIN_B, "completed"], [PIN_A, "completed"]], { [PIN_A]: clean, [PIN_B]: clean }), rc: 0, has: ["store_clean", "rotate precondition ok"] },
      { name: "a pinned run wrote the flag", files: scenario([[PIN_B, "completed"], [PIN_A, "completed"]], { [PIN_A]: clean, [PIN_B]: jobsBody("success") }), rc: 1, has: ["store_dirty", `run ${PIN_B}`, "no bypass input"] },
      { name: "a cutover run is in flight", files: scenario([["9", "in_progress"], [PIN_B, "completed"], [PIN_A, "completed"]], { [PIN_A]: clean, [PIN_B]: clean }), rc: 1, has: ["cutover_in_flight"] },
      { name: "a pinned run expired (retention)", files: scenario([[PIN_B, "completed"]], { [PIN_B]: clean }), rc: 1, has: ["scan_unreadable", "pinned_run_missing"] },
      { name: "gh cannot read the listing", files: {}, rc: 1, has: ["scan_unreadable"] },
      { name: "the scan prints store_clean but returns status 1 (verdict and status disagree)", files: {}, env: { GITHUB_WORKSPACE: stubWs }, rc: 1, has: ["scan_unreadable", "status 1"] },
      { name: "the library cannot be loaded", files: scenario([[PIN_B, "completed"], [PIN_A, "completed"]], { [PIN_A]: clean, [PIN_B]: clean }), env: { GITHUB_WORKSPACE: "/nonexistent-workspace" }, rc: 1, has: ["UNREADABLE", "could not be loaded"] },
    ];
    const outcome = (r: string) => cases.map((c) => { const x = runStep(r, { ...storeEnv, ...c.env }, c.files, { gh: GH_STUB }); return `${x.rc}:${c.has.every((h) => x.out.includes(h))}`; }).join(",");
    for (const c of cases) {
      const x = runStep(run, { ...storeEnv, ...c.env }, c.files, { gh: GH_STUB });
      expect(x.rc, `${c.name}: ${x.out.slice(0, 300)}`).toBe(c.rc);
      for (const h of c.has) expect(x.out, `${c.name}: missing '${h}'`).toContain(h);
    }
    const base = outcome(run);
    const mutants: Array<[string, (t: string) => string]> = [
      ["store_dirty arm exits 0", (t) => t.replace(/(store_dirty\) echo "[^\n]*?)exit 1 ;;/, "$1exit 0 ;;")],
      ["cutover_in_flight arm exits 0", (t) => t.replace(/(cutover_in_flight\) echo "[^\n]*?)exit 1 ;;/, "$1exit 0 ;;")],
      ["the unreadable *) arm exits 0", (t) => t.replace(/(\*\) echo "::error::rotate precondition REFUSED \(scan_unreadable\)[^\n]*?)exit 1 ;;/, "$1exit 0 ;;")],
      ["scan fed an empty history", (t) => t.replace("git_data_store_dirty_list | git_data_store_dirty_scan", "true | git_data_store_dirty_scan")],
      ["scan reads nothing from the list", (t) => t.replace("git_data_store_dirty_list | git_data_store_dirty_scan", "git_data_store_dirty_scan </dev/null")],
      ["case on a constant", (t) => t.replace('case "${verdict%% *}" in', 'case "store_clean" in')],
      ["the status guard on the store_clean arm is removed", (t) => t.replace('[[ "$rc" -eq 0 ]] ||', "true ||")],
      ["the library path is wrong", (t) => t.replace('source "${GITHUB_WORKSPACE}/scripts/lib/git-data-store-dirty-scan.sh"', 'source "${GITHUB_WORKSPACE}/scripts/lib/git-data-store-dirty-scan.sh.x"')],
    ];
    for (const [label, mut] of mutants) {
      const mutated = mut(run);
      expect(mutated, `mutation did not land: ${label}`).not.toBe(run);
      expect(outcome(mutated), `mutant survived: ${label}`).not.toBe(base);
    }
    rmSync(stubWs, { recursive: true, force: true });
  }, 60000);

  test("EXECUTED emptiness step freshness block: fresh passes; stale, missing server, missing token and a populated store refuse (and arm mutants change an outcome)", () => {
    const run = stepRun(EMPTY_STEP);
    const created = "2026-10-13T10:00:00+00:00"; // epoch 1791885600
    const readerBin = `if [[ "$1" == *toUnixTimestamp* ]]; then cat "$FX/epoch"; else cat "$FX/served"; fi`;
    const doppler = `while [[ $# -gt 0 && "$1" != "--" ]]; do shift; done; shift || true; exec "$@"`;
    // curl is argv-selective: the exact Hetzner name filter and the --max-time bound must be on the request.
    const curlBin = `cat >/dev/null 2>&1 || true; case "$*" in *"https://api.hetzner.cloud/v1/servers?name=soleur-git-data"*) :;; *) echo "curl stub refused: $*" >&2; exit 22;; esac; case "$*" in *"--max-time 15"*) :;; *) echo "curl stub: no --max-time 15" >&2; exit 22;; esac; [[ -f "$FX/servers" ]] || exit 22; cat "$FX/servers"`;
    const server = (n: number) => JSON.stringify({ servers: Array.from({ length: n }, () => ({ name: "soleur-git-data", created })) });
    const env = (extra: Record<string, string> = {}) => ({ DOPPLER_TOKEN: "synthetic", HCLOUD_TOKEN: "synthetic-hcloud-token", BETTERSTACK_QUERY_SCRIPT: "", ...extra });
    const files = (epoch: number | null, served: string, servers: string | null) => ({
      served: served === "" ? "" : `{"served_repos":"${served}"}\n`,
      epoch: epoch === null ? "" : `{"epoch":${epoch}}\n`,
      ...(servers === null ? {} : { servers }),
    });
    const go = (r: string, epoch: number | null, served: string, servers: string | null, extra: Record<string, string> = {}) => {
      const root = mkdtempSync(join(tmpdir(), "emptiness-exec-"));
      try {
        mkdirSync(join(root, "bin")); mkdirSync(join(root, "fx"));
        for (const [n, body] of Object.entries({ doppler, curl: curlBin })) writeFileSync(join(root, "bin", n), `#!/usr/bin/env bash\n${body}\n`, { mode: 0o755 });
        writeFileSync(join(root, "reader.sh"), `#!/usr/bin/env bash\n${readerBin}\n`, { mode: 0o755 });
        for (const [n, body] of Object.entries(files(epoch, served, servers))) writeFileSync(join(root, "fx", n), body);
        writeFileSync(join(root, "step.sh"), r);
        const x = spawnSync("bash", ["--noprofile", "--norc", "-eo", "pipefail", join(root, "step.sh")], {
          encoding: "utf8",
          env: { PATH: `${join(root, "bin")}:/usr/bin:/bin`, HOME: root, RUNNER_TEMP: root, FX: join(root, "fx"), GITHUB_WORKSPACE: REPO_ROOT, ...env(extra), BETTERSTACK_QUERY_SCRIPT: join(root, "reader.sh") },
        });
        return { rc: x.status, out: `${x.stdout}${x.stderr}` };
      } finally { rmSync(root, { recursive: true, force: true }); }
    };
    const cases: Array<{ name: string; args: [number | null, string, string | null, Record<string, string>?]; rc: number; has: string[] }> = [
      { name: "fresh row", args: [1791885601, "0", server(1)], rc: 0, has: ["is newer than the current server's creation", "::add-mask::synthetic-hcloud-token"] },
      { name: "row EQUAL to created is stale", args: [1791885600, "0", server(1)], rc: 1, has: ["stale_boot_complete"] },
      { name: "row before created is stale", args: [1791885599, "0", server(1)], rc: 1, has: ["stale_boot_complete"] },
      { name: "two servers refuse", args: [1791885700, "0", server(2)], rc: 1, has: ["boot_complete_unreadable"] },
      { name: "no servers refuse", args: [1791885700, "0", server(0)], rc: 1, has: ["boot_complete_unreadable"] },
      { name: "hetzner unreachable refuses", args: [1791885700, "0", null], rc: 1, has: ["boot_complete_unreadable"] },
      { name: "no epoch row refuses", args: [null, "0", server(1)], rc: 1, has: ["boot_complete_unreadable"] },
      { name: "HCLOUD_TOKEN missing refuses", args: [1791885700, "0", server(1), { HCLOUD_TOKEN: "" }], rc: 1, has: ["HCLOUD_TOKEN is not loaded"] },
      { name: "a populated store refuses", args: [1791885700, "3", server(1)], rc: 1, has: ["REFUSED"] },
      { name: "an unreadable store refuses", args: [1791885700, "", server(1)], rc: 1, has: ["UNREADABLE"] },
    ];
    const outcome = (r: string) => cases.map((c) => { const x = go(r, ...c.args); return `${x.rc}:${c.has.every((h) => x.out.includes(h))}`; }).join(",");
    for (const c of cases) {
      const x = go(run, ...c.args);
      expect(x.rc, `${c.name}: ${x.out.slice(0, 400)}`).toBe(c.rc);
      for (const h of c.has) expect(x.out, `${c.name}: missing '${h}'`).toContain(h);
    }
    const base = outcome(run);
    const mutants: Array<[string, (t: string) => string]> = [
      ["stale arm exits 0", (t) => t.replace(/(stale_boot_complete\) echo "[^\n]*?)exit 1 ;;/, "$1exit 0 ;;")],
      ["unreadable arm exits 0", (t) => t.replace(/(\*\) echo "::error::rotate precondition UNREADABLE \(boot_complete_unreadable\)[^\n]*?)exit 1 ;;/, "$1exit 0 ;;")],
      ["the whole freshness verdict is a constant", (t) => t.replace('case "$fresh" in', 'case "fresh" in')],
      ["created epoch is ignored", (t) => t.replace('git_data_boot_complete_freshness "$drows" "$created_epoch"', 'git_data_boot_complete_freshness "$drows" "0"')],
      ["the HCLOUD_TOKEN guard is removed", (t) => t.replace('if [[ -z "${HCLOUD_TOKEN:-}" ]]; then', "if false; then")],
      ["the Hetzner name filter is dropped", (t) => t.replace("servers?name=soleur-git-data", "servers")],
      ["the Hetzner call loses its --max-time bound", (t) => t.replace("-sS --max-time 15 'https://api.hetzner.cloud", "-sS 'https://api.hetzner.cloud")],
      ["the token mask is removed", (t) => t.replace("printf '::add-mask::%s\\n' \"$HCLOUD_TOKEN\"", ":")],
    ];
    for (const [label, mut] of mutants) {
      const mutated = mut(run);
      expect(mutated, `mutation did not land: ${label}`).not.toBe(run);
      expect(outcome(mutated), `mutant survived: ${label}`).not.toBe(base);
    }
  }, 60000);

  test("the census is unchanged except job-level actions: read (no new secret bound to the job)", () => {
    const doc = parseYaml(applyText) as { jobs: Record<string, { steps?: Array<{ env?: Record<string, string>; with?: Record<string, string> }> }> };
    const secrets = new Set<string>();
    for (const st of doc.jobs["git_data_host_replace"].steps ?? []) {
      for (const val of [...Object.values(st.env ?? {}), ...Object.values(st.with ?? {})]) for (const m of String(val).matchAll(/secrets\.([A-Z0-9_]+)/g)) secrets.add(m[1]);
    }
    expect([...secrets].sort()).toEqual(["DOPPLER_TOKEN", "DOPPLER_TOKEN_INFRA_PRIVILEGED", "GITHUB_TOKEN"]);
  });
});

// ─── #10136: Inngest link TLS (inngest-tls.tf), the merge -target additions and the Tier-B flag actuator ───
//
// WHAT THIS PINS, in the order a reviewer would ask:
//   1. the five key-material addresses exist with the attributes the trust model depends on (non-CA leaf,
//      private-IP SAN only, no early renewal, prevent_destroy on key and cert);
//   2. the merge apply creates exactly those five, in the saved-plan command, and NOT the flag;
//   3. the dependency closure of those five contains no hcloud_server (the merge apply cannot replace the
//      scheduler), and nothing else in the root references them (a templatefile variable that did would put
//      the cert into hcloud_server.inngest's user_data and into the inngest-host-replace closure);
//   4. the flag resource is count-gated, outside the per-merge view, and reachable from exactly ONE job;
//   5. that job plans and gates with an explicit TF_VAR, writes the source key AFTER the gate and just before the apply
//      (prd_terraform does not carry the Terraform-written prd key, measured 2026-10-19; a failed apply is reconciled to
//      the PRIOR key state), applies only the saved flag plan, and its plan gate rejects every other shape (the gate's jq
//      is executed here, not just grepped).
const TLS_FIVE = [
  "tls_private_key.inngest_link",
  "tls_self_signed_cert.inngest_link",
  "doppler_secret.inngest_tls_key",
  "doppler_secret.inngest_tls_cert",
  "doppler_secret.inngest_tls_ca",
];
const TLS_FLAG = "doppler_secret.inngest_link_tls";

/** Body of the first top-level block whose header matches, brace-matched; "" when absent (so a rename reds the row). */
function tlsBlock(text: string, header: RegExp): string {
  const m = header.exec(text);
  if (!m) return "";
  let depth = 0;
  for (let i = text.indexOf("{", m.index); i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(m.index, i + 1);
  }
  return "";
}

/**
 * Transitive DEPENDENCY closure of `roots` over a {file: comment-stripped HCL} map. `-target` pulls in what an
 * address depends on (never its dependents), so this is the set the merge plan can touch on account of the roots.
 * Edges: any `<type>.<name>` token naming a declared resource, and `local.X` (followed into the locals blocks).
 * `var.`/`data.` edges end the walk (a variable has no resource behind it). Deliberately simple; the mutation in
 * the test proves it sees a server reference.
 */
function tlsDependencyClosure(files: Record<string, string>, roots: string[]): Set<string> {
  const resources = new Map<string, string>();
  const locals = new Map<string, string>();
  for (const text of Object.values(files)) {
    for (const m of text.matchAll(/(?:^|\n)\s*resource\s+"([a-z0-9_]+)"\s+"([A-Za-z0-9_]+)"\s*\{/g)) {
      resources.set(`${m[1]}.${m[2]}`, tlsBlock(text.slice(m.index!), /^\s*resource\s+"[a-z0-9_]+"\s+"[A-Za-z0-9_]+"\s*\{/));
    }
    for (const lb of text.matchAll(/(?:^|\n)\s*locals\s*\{/g)) {
      const body = tlsBlock(text.slice(lb.index!), /^\s*locals\s*\{/);
      for (const part of body.split(/\n(?=\s{2}[a-z0-9_]+\s*=)/)) {
        const nm = /^\s*([a-z0-9_]+)\s*=/.exec(part);
        if (nm) locals.set(nm[1], part);
      }
    }
  }
  const refsOf = (body: string): string[] =>
    [...body.matchAll(/\b([a-z][a-z0-9_]*\.[A-Za-z0-9_]+)\b/g)].map((m) => m[1]).filter((a) => resources.has(a));
  const seen = new Set<string>();
  const queue = [...roots];
  while (queue.length > 0) {
    const addr = queue.pop()!;
    if (seen.has(addr)) continue;
    seen.add(addr);
    const body = resources.get(addr) ?? "";
    queue.push(...refsOf(body).filter((a) => !seen.has(a)));
    const localQueue = [...body.matchAll(/\blocal\.([a-z0-9_]+)/g)].map((m) => m[1]);
    const seenLocals = new Set<string>();
    while (localQueue.length > 0) {
      const ln = localQueue.pop()!;
      if (seenLocals.has(ln)) continue;
      seenLocals.add(ln);
      const lbody = locals.get(ln) ?? "";
      queue.push(...refsOf(lbody).filter((a) => !seen.has(a)));
      localQueue.push(...[...lbody.matchAll(/\blocal\.([a-z0-9_]+)/g)].map((m) => m[1]));
    }
  }
  return seen;
}

describe("#10136 inngest link TLS: key material, merge targets, flag actuator", () => {
  const infraFile = (n: string): string => stripComments(readFileSync(join(INFRA_DIR, n), "utf8"));
  const tlsTf = infraFile("inngest-tls.tf");
  const allInfra = (): Record<string, string> =>
    Object.fromEntries(listInfraTfFiles().map((f) => [f, stripComments(readFileSync(f, "utf8"))]));
  const wfText = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const res = (type: string, name: string): string =>
    tlsBlock(tlsTf, new RegExp(`^\\s*resource\\s+"${type}"\\s+"${name}"\\s*\\{`, "m"));
  const flagJob = extractJobBlock(wfText, "inngest_link_flag");

  test("the key and the cert: ECDSA P256, 10 y, private-IP SAN only, non-CA, no early renewal, prevent_destroy on both", () => {
    const key = res("tls_private_key", "inngest_link");
    expect(key).toMatch(/^\s*algorithm\s*=\s*"ECDSA"\s*$/m);
    expect(key).toMatch(/^\s*ecdsa_curve\s*=\s*"P256"\s*$/m);
    expect(key).toMatch(/prevent_destroy\s*=\s*true/);
    const cert = res("tls_self_signed_cert", "inngest_link");
    expect(cert).toMatch(/^\s*private_key_pem\s*=\s*tls_private_key\.inngest_link\.private_key_pem\s*$/m);
    expect(cert).toMatch(/^\s*validity_period_hours\s*=\s*87600\s*$/m);
    expect(cert).toMatch(/^\s*ip_addresses\s*=\s*\[local\.inngest_private_ip\]\s*$/m);
    expect(cert).toMatch(/^\s*is_ca_certificate\s*=\s*false\s*$/m);
    expect(cert).toMatch(/^\s*"server_auth",?\s*$/m);
    expect(cert).toMatch(/prevent_destroy\s*=\s*true/);
    // The trust model: the cert must not be able to issue, must name no DNS identity, and must not renew into a
    // replace that prevent_destroy then blocks on every later merge apply.
    expect(cert).not.toMatch(/early_renewal_hours/);
    expect(cert).not.toMatch(/dns_names/);
    expect(cert).not.toMatch(/is_ca_certificate\s*=\s*true/);
    expect(cert).not.toMatch(/"cert_signing"|"crl_signing"/);
  });

  test("the three Doppler copies: key and cert in the host's isolated project, the base64 CA in soleur/prd; all masked", () => {
    for (const [name, secret] of [["inngest_tls_key", "INNGEST_TLS_KEY"], ["inngest_tls_cert", "INNGEST_TLS_CERT"]]) {
      const b = res("doppler_secret", name);
      expect(b, `${name} missing`).not.toBe("");
      expect(b).toMatch(/^\s*project\s*=\s*doppler_project\.inngest\.name\s*$/m);
      expect(b).toMatch(/^\s*config\s*=\s*doppler_environment\.inngest_prd\.slug\s*$/m);
      expect(b).toMatch(new RegExp(`^\\s*name\\s*=\\s*"${secret}"\\s*$`, "m"));
      expect(b).toMatch(/^\s*visibility\s*=\s*"masked"\s*$/m);
      expect(b).not.toMatch(/ignore_changes|count\s*=/);
    }
    expect(res("doppler_secret", "inngest_tls_key")).toMatch(/^\s*value\s*=\s*tls_private_key\.inngest_link\.private_key_pem\s*$/m);
    expect(res("doppler_secret", "inngest_tls_cert")).toMatch(/^\s*value\s*=\s*tls_self_signed_cert\.inngest_link\.cert_pem\s*$/m);
    const ca = res("doppler_secret", "inngest_tls_ca");
    expect(ca).toMatch(/^\s*project\s*=\s*"soleur"\s*$/m);
    expect(ca).toMatch(/^\s*config\s*=\s*"prd"\s*$/m);
    expect(ca).toMatch(/^\s*name\s*=\s*"INNGEST_TLS_CA"\s*$/m);
    expect(ca).toMatch(/^\s*value\s*=\s*base64encode\(tls_self_signed_cert\.inngest_link\.cert_pem\)\s*$/m);
    expect(ca).toMatch(/^\s*visibility\s*=\s*"masked"\s*$/m);
  });

  test("the merge apply creates the five key-material addresses, between the last inngest target and supabase_project.prd, and NOT the flag", () => {
    const saved = commandIn(stripComments(extractJobBlock(wfText, "apply")), /^\s*terraform plan\b.*-out=tfplan/);
    const order = [...saved.matchAll(/-target=(\S+)/g)].map((m) => m[1].replace(/\\$/, ""));
    for (const a of TLS_FIVE) expect(order, `${a} not in the saved-plan command`).toContain(a);
    const iLast = order.indexOf("doppler_secret.inngest_redis_luks_key");
    expect(iLast).toBeGreaterThan(-1);
    expect(order.slice(iLast + 1, iLast + 6)).toEqual(TLS_FIVE);
    expect(order[iLast + 6]).toBe("supabase_project.prd");
    expect(order).not.toContain(TLS_FLAG);
    const perMerge = extractAllTargets(stripDispatchJobs(wfText));
    expect(TLS_FIVE.filter((a) => !perMerge.has(a))).toEqual([]);
    expect(perMerge.has(TLS_FLAG)).toBe(false);
    // Non-vacuity: the unstripped file DOES see the flag (the flip job targets it), so the strip is load-bearing.
    expect(extractAllTargets(wfText).has(TLS_FLAG)).toBe(true);
  });

  test("no hcloud_server is in the dependency closure of the five merge targets (the merge apply cannot replace the scheduler)", () => {
    const closure = tlsDependencyClosure(allInfra(), TLS_FIVE);
    expect([...closure].filter((a) => a.startsWith("hcloud_"))).toEqual([]);
    // Non-vacuity: the walk reached the Doppler parents the secrets reference ...
    expect(closure.has("doppler_project.inngest")).toBe(true);
    expect(closure.has("doppler_environment.inngest_prd")).toBe(true);
    // ... and it sees a server when one is there: the host's own closure contains it, and a mutated copy of the
    // cert that reads the host through its address reaches it.
    expect(tlsDependencyClosure(allInfra(), ["hcloud_server_network.inngest"]).has("hcloud_server.inngest")).toBe(true);
    const mutated = allInfra();
    const f = Object.keys(mutated).find((k) => k.endsWith("inngest-tls.tf"))!;
    const before = mutated[f];
    mutated[f] = before.replace(/ip_addresses\s*=\s*\[local\.inngest_private_ip\]/, "ip_addresses = [hcloud_server.inngest.ipv4_address]");
    expect(mutated[f]).not.toBe(before);
    expect(tlsDependencyClosure(mutated, TLS_FIVE).has("hcloud_server.inngest")).toBe(true);
  });

  test("nothing outside inngest-tls.tf references the key material, so no templatefile variable can pull it into the host's user_data", () => {
    const REF = /tls_private_key\.inngest_link|tls_self_signed_cert\.inngest_link|doppler_secret\.inngest_tls_(?:key|cert|ca)|doppler_secret\.inngest_link_tls|var\.inngest_link_tls/;
    const offenders = Object.entries(allInfra())
      .filter(([f]) => !f.endsWith("inngest-tls.tf") && !f.endsWith("variables.tf"))
      .filter(([, text]) => REF.test(text))
      .map(([f]) => f);
    expect(offenders).toEqual([]);
    const host = infraFile("inngest-host.tf");
    expect(host).toContain("templatefile("); // non-vacuity: the file under test is the host's
    const call = host.slice(host.indexOf("templatefile("), host.indexOf("local.inngest_rationale_strip"));
    expect(call.length).toBeGreaterThan(500);
    expect(call).not.toMatch(/\btls_|inngest_tls|inngest_link/);
    // The tripwire itself fires on a synthetic reference.
    expect(REF.test("x = tls_self_signed_cert.inngest_link.cert_pem")).toBe(true);
  });

  test("the flag is count-gated on an empty default, validated to the resolver's allowlist, and unreachable from the per-merge list", () => {
    const flag = res("doppler_secret", "inngest_link_tls");
    expect(flag).toMatch(/^\s*count\s*=\s*var\.inngest_link_tls\s*==\s*""\s*\?\s*0\s*:\s*1\s*$/m);
    expect(flag).toMatch(/^\s*project\s*=\s*"soleur"\s*$/m);
    expect(flag).toMatch(/^\s*config\s*=\s*"prd"\s*$/m);
    expect(flag).toMatch(/^\s*name\s*=\s*"INNGEST_LINK_TLS"\s*$/m);
    expect(flag).toMatch(/^\s*value\s*=\s*var\.inngest_link_tls\s*$/m);
    const v = tlsBlock(infraFile("variables.tf"), /^variable\s+"inngest_link_tls"\s*\{/m);
    expect(v).toMatch(/^\s*type\s*=\s*string\s*$/m);
    expect(v).toMatch(/^\s*default\s*=\s*""\s*$/m);
    expect(v).not.toMatch(/sensitive\s*=\s*true/);
    expect(v).toContain('"^(1|pending:[0-9]{1,10})?$"');
    expect(OPERATOR_APPLIED_EXCLUSIONS.has(TLS_FLAG)).toBe(true);
    // Every workflow: exactly one job targets the flag, and it is the Tier-B actuator.
    const sites: string[] = [];
    for (const f of readdirSync(resolve(REPO_ROOT, ".github/workflows")).filter((n) => /\.ya?ml$/.test(n))) {
      const text = readFileSync(resolve(REPO_ROOT, ".github/workflows", f), "utf8");
      for (const [job, body] of g2Jobs(text)) {
        if (new RegExp(`-target[= ]['"]?${g2Esc(TLS_FLAG)}\\b`).test(stripShellLineComments(body))) sites.push(`${f}|${job}`);
      }
    }
    expect(sites).toEqual(["apply-web-platform-infra.yml|inngest_link_flag"]);
  });

  test("the flag job: Tier-B environment, dispatch-gated on its own option, plans with an explicit variable, writes the source key AFTER the gate and BEFORE the apply, reconciles it on failure, applies only the saved flag plan", () => {
    expect(flagJob).not.toBe("");
    expect(flagJob).toMatch(/^\s+environment:\s*infra-privileged\s*$/m);
    expect(flagJob).toContain("if: github.event_name == 'workflow_dispatch' && inputs.apply_target == 'inngest-link-flag'");
    expect(Number(/timeout-minutes:\s*(\d+)/.exec(flagJob)?.[1])).toBeLessThanOrEqual(15);
    expect(flagJob).toContain("uses: ./.github/actions/infra-credentials");
    const code = stripShellLineComments(flagJob);
    // MEASURED 2026-10-19: prd_terraform does NOT inherit a Terraform-written prd key created after the branch, so the
    // source key must exist for every untargeted plan, but it is written only AFTER init, plan and the gate passed and just
    // BEFORE the apply (every earlier failure leaves key and prd consistent), and a failed/cancelled apply restores it.
    const iSet = code.indexOf("doppler secrets set INNGEST_LINK_TLS");
    const iDel = code.indexOf("doppler secrets delete INNGEST_LINK_TLS");
    const iPlan = code.indexOf("terraform plan");
    const iApply = code.indexOf("terraform apply");
    expect(iSet).toBeGreaterThan(-1);
    expect(iDel).toBeGreaterThan(-1);
    expect(iPlan).toBeLessThan(Math.min(iSet, iDel));
    expect(Math.max(iSet, iDel)).toBeLessThan(iApply);
    const doc0 = parseYaml(wfText) as { jobs: Record<string, { steps: Array<Record<string, unknown>> }> };
    const steps0 = doc0.jobs.inngest_link_flag.steps;
    const iRec = steps0.findIndex((st) => String(st.name ?? "").startsWith("Reconcile the source key"));
    const iAp = steps0.findIndex((st) => st.id === "apply");
    expect(iRec).toBeGreaterThan(iAp);
    expect(steps0[iRec].if).toBe("failure() || cancelled()");
    expect((steps0[iRec].env as Record<string, string>).APPLY_OUTCOME).toBe("${{ steps.apply.outcome }}");
    // The delete is never swallowed (no `|| true` on it) and the absence is verified from a names listing.
    expect(code.replace(/\\\n\s*/g, " ")).not.toMatch(/INNGEST_LINK_TLS --yes[^\n]*\|\| true/);
    expect(code).toContain("secrets --only-names -p soleur -c prd_terraform");
    expect(code).toContain("secrets.DOPPLER_TOKEN_WRITE");
    expect(code).toMatch(/--name-transformer tf-var -- \\\n\s+env "TF_VAR_inngest_link_tls=\$\{TF_LINK\}" \\\n\s+terraform plan/);
    // The apply consumes ONLY the saved, gated plan: no -target/-replace/-var, ends in tfplan.
    expect(/^\s*terraform apply (.*)$/m.exec(code)![1]).toBe("-no-color -input=false -auto-approve tfplan");
    expect([...extractAllTargets(flagJob)]).toEqual([TLS_FLAG]);
    // Every `doppler run` in the job keeps the Tier-B precedence (ADR-241 D6).
    const runs = code.split("\n").filter((l) => /doppler run\b/.test(l));
    expect(runs.length).toBe(2);
    expect(runs.filter((l) => !l.includes("--preserve-env"))).toEqual([]);
    expect(flagJob).toMatch(/uses: actions\/checkout@[0-9a-f]{40}[^\n]*\n\s+with:\n\s+persist-credentials: false/);
    // The option and the input exist; the new job is stripped from the per-merge view.
    const opts = /apply_target:[\s\S]*?options:([\s\S]*?)\n\nconcurrency:/.exec(wfText)![1];
    expect(opts).toMatch(/^\s*-\s+inngest-link-flag\s*$/m);
    const doc = parseYaml(wfText) as { on: { workflow_dispatch: { inputs: Record<string, unknown> } } };
    const inputs = Object.keys(doc.on.workflow_dispatch.inputs);
    expect(inputs).toContain("inngest_link_value");
    expect(inputs.length).toBeLessThanOrEqual(25);
    expect(extractJobBlock(stripDispatchJobs(wfText), "inngest_link_flag")).toBe("");
  });

  test("the flag job's blast-radius gate (jq, executed): the flag address only, the right action per value", () => {
    const m = /jq -e --arg v "\$LINK_VALUE" '([\s\S]*?)' >\/dev\/null/.exec(flagJob);
    expect(m, "the gate's jq program was not found in the job").not.toBeNull();
    const run = (value: string, changes: Array<[string, string[]]>): number => {
      const plan = JSON.stringify({ resource_changes: changes.map(([address, actions]) => ({ address, change: { actions } })) });
      return spawnSync("jq", ["-e", "--arg", "v", value, m![1]], { input: plan }).status ?? -1;
    };
    const F = "doppler_secret.inngest_link_tls[0]";
    expect(run("1", [[F, ["create"]]])).toBe(0);
    expect(run("pending:1700000000", [[F, ["update"]]])).toBe(0);
    expect(run("off", [[F, ["delete"]]])).toBe(0);
    expect(run("1", [[F, ["no-op"]]])).not.toBe(0); // a value that planned no change did not land: the job fails
    expect(run("pending:1700000000", [])).not.toBe(0); // a zero-change plan for a value fails
    expect(run("1", [])).not.toBe(0);
    expect(run("off", [])).toBe(0); // already absent: idempotent, the caller still redeploys
    expect(run("off", [[F, ["no-op"]]])).toBe(0);
    expect(run("off", [[F, ["delete"]], ["doppler_secret.inngest_tls_ca", ["delete"]]])).not.toBe(0);
    expect(run("off", [[F, ["create"]]])).not.toBe(0); // `off` must never create
    expect(run("1", [[F, ["delete"]]])).not.toBe(0); // a value must never delete
    expect(run("1", [[F, ["create"]], ["hcloud_server.inngest", ["update"]]])).not.toBe(0);
    expect(run("1", [[F, ["create"]], ["doppler_secret.inngest_tls_ca", ["update"]]])).not.toBe(0);
    expect(run("1", [["doppler_secret.inngest_link_tls_other[0]", ["create"]]])).not.toBe(0);
    expect(run("1", [[F, ["create", "delete"]]])).not.toBe(0); // a replace is not a create
  });
});

describe("this suite itself cannot be silently narrowed", () => {
  const selfText = readFileSync(resolve(import.meta.dir, "terraform-target-parity.test.ts"), "utf8");

  test("no test or describe is skipped, focused, or stubbed out", () => {
    expectNonEmptyDispatch(selfText.length, 1);
    for (const bad of [".skip(", ".only(", ".todo(", ".failing("]) {
      const hits = selfText.split("\n").filter((l) => l.includes(`test${bad}`) || l.includes(`describe${bad}`));
      expect(hits).toEqual([]);
    }
  });

  test("the declared test count is at or above the shipped floor", () => {
    // Hand-ratcheted to the exact shipped count, like the bash suite's ASSERT_FLOOR. Exact rather
    // than "shipped minus a margin": a margin is the room a silent narrowing hides in, and
    // deleting a test on purpose should cost one deliberate edit here.
    const declared = selfText.match(/^\s*test\(/gm)?.length ?? 0;
    expect(declared).toBeGreaterThanOrEqual(TEST_FLOOR);
  });
});

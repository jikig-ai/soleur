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
/** Suite-level cardinality floor — see the final describe in this file (#7656 C8). */
const TEST_FLOOR = 173;
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
const MIN_SSH_PROVISIONED = 17;

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
  // ALL git-data OPERATOR_APPLIED_EXCLUSIONS (server + network + both volume attachments +
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
  //
  // NOTE for whoever edits this function next: the guard above extracts EVERY
  // "[a-z0-9_]+" string literal in this body and requires each to name a real top-level
  // job. Adding any other lowercase quoted literal here — even in a helper call — makes
  // that guard treat it as a job name and go red. Comments are fine; literals are not.
  return stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(stripJob(workflowText, "inngest_host"), "registry_host_replace"), "registry_region_migrate"), "registry_luks_recut"), "git_data_host_replace"), "workspaces_luks_recut"), "web_host_create"), "web_host_replace"), "git_data_host_create");
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
  // at boot), NOT the #5566 per-PR-CI class. Same class as hcloud_volume.git_data + the
  // git-data doppler_secrets above.
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
  // all. Sourcing the value from a static local (local.git_data_private_ip) instead of the
  // computed NIC attribute removes the last edge that could reach the server. So the
  // secret ships in #6982 as an exclusion + a birth -target, with no wedge.
  "doppler_config.git_data_prd",
  // (#6982) Both ride the git-data-host-create dispatch, never the per-PR apply — same
  // class as every git-data sibling above.
  "doppler_secret.git_data_ssh_host",
  "doppler_secret.git_data_betterstack_logs_token",
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
  // DO ride the per-PR -target list), so this exclusion is obsolete.
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
  // #6780 (ADR-134) — the promoted config-refresh digest pointer, minted into the ISOLATED
  // soleur-inngest/prd project (inngest-config-digest.tf). DELIBERATELY has NO per-PR CI -target:
  // the boot isolation self-check on soleur-inngest/prd is EXACT-SET, so this secret can be applied
  // ONLY atomically with the cloud-init regex+floor admission that rides the #6178 cutover — a
  // per-PR apply would brick the sole scheduler at its next boot. Rides the operator/cutover apply,
  // exactly like the sibling isolated-inngest secrets above; `doppler_secret`, not a CI-published
  // token type. (`github_repository_environment.inngest_config_signing`, by contrast, IS host-
  // independent and carries a normal -target — see apply-web-platform-infra.yml.)
  "doppler_secret.inngest_config_digest",
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
  "doppler_secret.web_zot_consumer_url",
  "doppler_secret.web_nic_guard_url",
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
  "doppler_secret.web_zot_consumer_url",
  "doppler_secret.web_nic_guard_url",
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

  test("the -targets are EXACTLY the nine per-host birth fan-out addresses", () => {
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
  test("every cutover-gate environment in the infra root gates on ≥1 reviewer", () => {
    const header =
      /resource\s+"github_repository_environment"\s+"([A-Za-z0-9_]+)"\s*\{/g;
    const envs: { name: string; users: string }[] = [];
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
        envs.push({ name, users: (rev?.[1] ?? "").trim() });
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

    for (const env of envs) {
      const ids = env.users
        .split(",")
        .map((s) => s.trim())
        .filter(Boolean);
      expect(
        ids.length,
        `github_repository_environment.${env.name} has an EMPTY reviewers.users — a zero-reviewer environment auto-approves (DP-11 F8)`,
      ).toBeGreaterThan(0);
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
 * the still-plaintext store volume, so cloud-init hits the `blkid` else->FATAL arm and DARKS the
 * registry; replacing the volume alone leaves the old host mounting a device that no longer
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

  test("declares NO environment: (a zero-reviewer environment auto-approves — DP-11 F8)", () => {
    expect(/^\s+environment:/m.test(jobBlock)).toBe(false);
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
// and rests its 5-member allow-set on "preserved by OMISSION" — an argument that INVERTS
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
  "hcloud_volume.git_data",
  "hcloud_volume.git_data_luks",
  // DOWNSTREAM — omit either and the store boots with its volume unmounted. For the LUKS
  // one that means at-rest encryption is absent while every artifact claims it present.
  "hcloud_volume_attachment.git_data",
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
  // (#6982) SIBLING, dependency-free by design. Publishes GIT_DATA_SSH_HOST from a STATIC
  // local, never from hcloud_server_network.git_data.ip — that is what makes it plannable
  // with the host absent and keeps it clear of any upstream closure onto the server.
  // ADR-149 cut it from #6977 believing the opposite; see its resource comment. Omit it and
  // every account deletion files a FALSE Art. 17 erasure-failed event from birth onward.
  "doppler_secret.git_data_ssh_host",
  // (#6982) SIBLING. The Better Stack ingest token in prd_git_data, read by the
  // post-Doppler emits (boot-completion, gc faults). Omit it and the queryable copy of the
  // boot signal never ships, which is what the follow-through probe reads.
  "doppler_secret.git_data_betterstack_logs_token",
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
    // Non-vacuity: the extraction must actually find the twenty members.
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
    expect(entailed.length).toBe(3);

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
    // All twenty are exclusions, so folding them in would assert per-merge coverage for
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

    // The interlocks are separate STEPS, so each can be disarmed without touching its body
    // at all. Pin the three ways for BOTH: a conditional, continue-on-error, or a missing
    // non-zero exit.
    for (const stepName of ["Birth-readiness interlock", "Rung-2 rehearsal interlock"]) {
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
    expect(interlockAt).toBeLessThan(planAt);
    expect(rung2At).toBeLessThan(planAt);
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
    // Non-vacuity: the extraction must actually find the twenty members.
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
const SPEC_MEASUREMENTS = resolve(
  REPO_ROOT,
  "knowledge-base/project/specs/feat-one-shot-7586-7587-red-apply-no-channel-arm-deadline/measurements.md",
);

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
    expect(deadlines.length).toBe(6);
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
    expectNonEmptyDispatch(calls.length, 6);
    for (const { addr, deadline } of calls) {
      const name = /^betteruptime_heartbeat\.([a-z0-9_]+)/.exec(addr)?.[1];
      expect(name).toBeDefined();
      const window = windows[name!];
      expect(window).toBeDefined();
      // Every arm must roll back BEFORE the first absence alert. The inngest arm sits far below
      // the formula on purpose (#7228), which is still inside the bound.
      expect(deadline).toBeLessThanOrEqual(window - reserve);
      if (name !== "inngest_consumer") expect(deadline).toBe(window - reserve);
    }
  });

  test("the `inngest_consumer` deadline is EXACTLY 30, and every other deadline is unchanged", () => {
    // Not "<= 60": the reclaimed ~200 s and the 1-in-6 arming probability both plug in 30, so a
    // looser bound would pass while falsifying the arithmetic.
    const stripped = script.split("\n").filter((l) => !/^\s*#/.test(l)).join("\n");
    expect(stripped).toMatch(/^ARM_INNGEST_DEADLINE=30$/m);
    expect(armOneDeadlines(script)).toEqual([200, 440, 200, 440, 200, 30]);
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
    expect(mutexMin).toBe(47);
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
    expect(stripped.match(/curl\b/g)?.length).toBe(2);
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
    expect(JOB_S).toBe(41 * 60);
    expect(STEP_S).toBe(35 * 60);
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

  test("M3b RED: a SEVENTH call site with a TINY deadline still reds — the overhead is per site", () => {
    // This is the row `Σ × 1.1` could not carry: a multiplier on the deadline sum grows with the
    // deadlines, while the real overhead grows with the number of call sites. Six 15 s round-trips
    // and a poll interval cost 70 s whether the deadline is 440 or 1.
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
    // The contract is the inequality, not a literal. 36 min is not what ships and is fine.
    expect(ladderViolations(JOB_S, 36 * 60, REAL_DEADLINES, T)).toEqual([]);
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

// --- suite-level anti-vacuity (#7656 C8) --------------------------------------------------------
// The bash side has had a minimum-cardinality floor since it was written; this file had none. A
// `test.skip` typo, a stray `.only`, or a narrowed filter reports "0 fail" and reads as success —
// the outermost gap, and the one `expectNonEmptyDispatch` cannot see, because it only fires from
// inside a test that RAN.
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

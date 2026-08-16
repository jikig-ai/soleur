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
});

// The green-skip channel (#7539). When CI_SSH_ACCESS_TOKEN_ID is absent,
// ssh_token_gate sets ssh_apply_skip=true and the bridge, the post-bridge apply
// AND the heartbeat ARM gate all skip — the run goes GREEN having delivered
// nothing. These assert the notification arm is actually wired, so it cannot be
// silently un-wired: an arm that exists but references a dead output, or whose
// body omits the recovery command, reproduces the ::warning:: problem in email.
describe("the ssh_token_gate green-skip has a channel (#7539)", () => {
  const wf = readFileSync(WEB_PLATFORM_WORKFLOW, "utf8");
  const applyJob = extractJobBlock(wf, "apply");

  test("a notify-ops-email step is gated on the skip output, inside the apply job", () => {
    expect(applyJob).toContain("uses: ./.github/actions/notify-ops-email");
    expect(applyJob).toMatch(
      /if:\s*always\(\)\s*&&\s*steps\.ssh_token_gate\.outputs\.ssh_apply_skip\s*==\s*'true'/,
    );
  });

  test("the gate it references is a real step id (not a dead output)", () => {
    expect(applyJob).toMatch(/^\s*id:\s*ssh_token_gate\s*$/m);
  });

  test("the notification names the recovery lever, not merely the fact of skipping", () => {
    // A body that says only "skipped" is the ::warning:: problem in email form.
    //
    // Scoped to the notify STEP, not the job: `apply_target=manual-rerun` also
    // appears in the job's recovery COMMENT, so a job-wide toContain would pass
    // with the lever absent from the email — vacuous exactly the way a bare-token
    // grep is (cq-assert-anchor-not-bare-token).
    const notifyIdx = applyJob.indexOf(
      "uses: ./.github/actions/notify-ops-email",
    );
    expect(notifyIdx).toBeGreaterThan(-1);
    const afterNotify = applyJob.slice(notifyIdx);
    // Bound the slice at the next step header so it cannot swallow later steps.
    const nextStep = afterNotify.slice(1).search(/\n {6}- name:/);
    const notifyStep =
      nextStep === -1 ? afterNotify : afterNotify.slice(0, nextStep + 1);
    expect(notifyStep).toContain("apply_target=manual-rerun");
    // Non-vacuity: the bounded slice must be a step, not the rest of the file.
    expect(notifyStep.length).toBeLessThan(afterNotify.length);
  });

  test("the run summary surfaces the SSH stage state (job.status alone reads success)", () => {
    expect(applyJob).toMatch(/SSH_SKIP:\s*\$\{\{\s*steps\.ssh_token_gate\.outputs\.ssh_apply_skip/);
    expect(applyJob).toContain("**SSH stage:**");
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

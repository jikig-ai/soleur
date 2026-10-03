// Guard 3 census (#9377, decision B1): every workflow job that can create or replace hcloud_server.web[...] runs
// scripts/web-host-escrow-preflight.sh, fail-closed, before any Terraform command.
//
// PREDICATE. A job is host-creating when its whole non-comment text (every step's `run`, and the `run` text of any
// local composite action a step `uses`) contains BOTH a `terraform apply` AND a `-target`/`-replace` ARGUMENT whose
// address is `hcloud_server.web[`. A bare mention is NOT enough: three jobs (`inngest_volume_recut`,
// `workspaces_luks_cutover`, `workspaces_luks_recut`) loop over that address in `jq` state-presence checks and create
// nothing, so a bare-mention predicate would be red on day one. A job that builds the address dynamically (a variable
// holding the whole `-target=` argument) would evade the predicate; the floor below and review of any new workflow are
// the backstop, recorded in the plan's Risks.
//
// EVERY MATCHING JOB IS UNEXEMPT. There is no exempt list: the two routes that refuse host creation outright
// (`apply-web-platform-infra.yml:apply`, `apply-deploy-pipeline-fix.yml:apply`) never match the predicate (they have
// no such -target), so "every route" holds only while their `host_creates` HALTs survive. A separate assertion pins
// those two HALTs by name and does not depend on the predicate.
//
// The census is not a proof that the check PASSES (the checker reads names only); it proves the check cannot be
// skipped. The mutation rows run the same functions over mutated copies of the parsed real workflows and over
// synthetic rebirth-shaped workflows, so a RED row is a verdict of the code under test, not of the fixture.
//
// Harness: bun:test, like its siblings in plugins/soleur/test/*.ts.

import { describe, test, expect } from "bun:test";
import { parse as parseYaml } from "yaml";
import { resolve, join } from "path";
import { readFileSync, readdirSync, existsSync } from "fs";

const REPO_ROOT = resolve(import.meta.dir, "../../..");
const WORKFLOW_DIR = resolve(REPO_ROOT, ".github/workflows");
const PREFLIGHT_RUN = "bash scripts/web-host-escrow-preflight.sh";
/** Hand-ratcheted to the exact shipped test count (see the last describe). */
const TEST_FLOOR = 28;
/** The census must see at least this many host-creating jobs on the real tree (today web_host_create + web_host_replace). */
const HOST_CREATING_FLOOR = 2;

type Doc = { jobs?: Record<string, any> };
type ReadAction = (localPath: string) => string;

const stripShellComments = (s: string): string =>
  s
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

const realReadAction: ReadAction = (p) => {
  for (const name of ["action.yml", "action.yaml"]) {
    const f = resolve(REPO_ROOT, p.replace(/^\.\//, ""), name);
    if (existsSync(f)) return readFileSync(f, "utf8");
  }
  return "";
};

/** The `run` text of a local composite action, comment-stripped; empty when the action is not a local composite. */
function actionRunText(step: any, readAction: ReadAction): string {
  if (typeof step?.uses !== "string" || !step.uses.startsWith("./")) return "";
  let doc: any;
  try {
    doc = parseYaml(readAction(step.uses));
  } catch {
    return "";
  }
  const parts: string[] = [];
  for (const s of doc?.runs?.steps ?? []) if (typeof s?.run === "string") parts.push(stripShellComments(s.run));
  return parts.join("\n");
}

/** Everything a job can execute as shell text: step runs plus local composite action runs, comment-stripped. */
function jobText(job: any, readAction: ReadAction): string {
  const parts: string[] = [];
  for (const s of job?.steps ?? []) {
    if (typeof s?.run === "string") parts.push(stripShellComments(s.run));
    parts.push(actionRunText(s, readAction));
  }
  return parts.join("\n");
}

const TF_APPLY_RE = /\bterraform\s+(?:-[^\s]+\s+)*apply\b/;
// A -target / -replace argument naming the web server, however the quotes are spelled (`-target="hcloud_server.web[\"k\"]"`,
// `-replace='hcloud_server.web["k"]'`, `-target hcloud_server.web[...]`).
const HOST_ARG_RE = /-(?:target|replace)(?:=|\s+)\\?["']?hcloud_server\.web\[/;
const TF_CMD_RE = /(?:^|[\s;&|(])terraform\s+(?:init|plan|apply|validate|state|import|output|show|fmt|workspace|providers|force-unlock|destroy|taint|untaint)\b/m;

function isHostCreating(job: any, readAction: ReadAction): boolean {
  const t = jobText(job, readAction);
  return TF_APPLY_RE.test(t) && HOST_ARG_RE.test(t);
}

function hostCreatingJobIds(doc: Doc, readAction: ReadAction): string[] {
  return Object.entries(doc.jobs ?? {})
    .filter(([, job]) => isHostCreating(job, readAction))
    .map(([id]) => id);
}

const isPreflightStep = (s: any): boolean => typeof s?.run === "string" && stripShellComments(s.run).trim() === PREFLIGHT_RUN;
const isTerraformStep = (s: any, readAction: ReadAction): boolean =>
  (typeof s?.run === "string" && TF_CMD_RE.test(stripShellComments(s.run))) || TF_CMD_RE.test(actionRunText(s, readAction));

/** Violations of one host-creating job: the preflight step must exist, be unconditional, and precede every Terraform command. */
function preflightViolations(job: any, readAction: ReadAction): string[] {
  const v: string[] = [];
  const steps: any[] = job?.steps ?? [];
  const idx = steps.findIndex(isPreflightStep);
  if (idx < 0) return [`no step runs exactly '${PREFLIGHT_RUN}'`];
  const s = steps[idx];
  for (const k of ["if", "continue-on-error", "working-directory", "shell"]) {
    if (k in s) v.push(`the preflight step carries '${k}:' (it must be unconditional, fail-closed, repo-root relative)`);
  }
  if (s["timeout-minutes"] !== 2) v.push(`the preflight step must carry 'timeout-minutes: 2' (got ${JSON.stringify(s["timeout-minutes"])})`);
  const envKeys = Object.keys(s.env ?? {});
  if (envKeys.length !== 1 || envKeys[0] !== "DOPPLER_TOKEN") v.push(`the preflight step env must be exactly DOPPLER_TOKEN (got ${JSON.stringify(envKeys)})`);
  if (job?.["continue-on-error"] === true) v.push("the job carries continue-on-error: true");
  const firstTf = steps.findIndex((st) => isTerraformStep(st, readAction));
  if (firstTf >= 0 && firstTf < idx) v.push(`the preflight step (#${idx}) comes AFTER the first Terraform command (#${firstTf})`);
  return v;
}

function censusViolations(doc: Doc, readAction: ReadAction): string[] {
  const out: string[] = [];
  for (const id of hostCreatingJobIds(doc, readAction)) {
    for (const why of preflightViolations(doc.jobs![id], readAction)) out.push(`${id}: ${why}`);
  }
  return out;
}

function floorViolation(count: number): string | null {
  return count >= HOST_CREATING_FLOOR ? null : `the census found ${count} host-creating job(s), below the floor of ${HOST_CREATING_FLOOR} (an empty or narrowed match set must not read as clean)`;
}

/**
 * The refusing routes: a `host_creates` HALT that exits non-zero and has no acknowledgement path. Pinned by name so it
 * does not depend on the predicate (these jobs never match it). Operates on the job's comment-stripped run text.
 */
function haltViolations(job: any): string[] {
  const text = stripShellComments(
    (job?.steps ?? []).map((s: any) => (typeof s?.run === "string" ? s.run : "")).join("\n"),
  );
  const lines = text.split("\n");
  const ifRe = /^(\s*)if \[\[ "\$host_creates" -gt 0 \]\]; then\s*$/;
  const start = lines.findIndex((l) => ifRe.test(l));
  if (start < 0) return ["no `if [[ \"$host_creates\" -gt 0 ]]; then` HALT (exact, unconditioned) found"];
  const v: string[] = [];
  const indent = ifRe.exec(lines[start])![1];
  // The HALT must sit at the same nesting level as the counter read, i.e. not inside an ack/skip branch.
  const readIdx = lines.findIndex((l) => /^\s*host_creates=\$\(echo "\$counts" \| jq -r '\.host_creates'\)\s*$/.test(l));
  if (readIdx < 0) v.push("the host_creates counter is not read from the destroy-guard filter output");
  else if (/^(\s*)/.exec(lines[readIdx])![1] !== indent) v.push("the HALT is nested at a different level than the counter read (inside a conditional?)");
  let end = -1;
  for (let i = start + 1; i < lines.length; i++) {
    if (lines[i] === `${indent}fi`) {
      end = i;
      break;
    }
  }
  if (end < 0) return [...v, "the HALT block has no closing fi at its own indent"];
  const body = lines.slice(start + 1, end);
  if (!body.some((l) => /^\s*exit 1\s*$/.test(l))) v.push("the HALT body does not `exit 1`");
  // Executable lines only: the prose of an `echo "::error::..."` may legitimately say "no ack token" or quote an exit code.
  const exec = body.filter((l) => !/^\s*echo\b/.test(l));
  if (exec.some((l) => /\bexit 0\b/.test(l))) v.push("the HALT body can `exit 0`");
  // No acknowledgement path: nothing executable (non-echo) in the body mentions an ack/skip/override.
  if (exec.some((l) => /ack|skip|override|bypass/i.test(l))) v.push("the HALT body carries an acknowledgement/skip path");
  return v;
}

// --- load the real workflows ------------------------------------------------------------------------------
const workflowFiles = readdirSync(WORKFLOW_DIR).filter((f) => /\.ya?ml$/.test(f)).sort();
const realDocs: Record<string, Doc> = {};
for (const f of workflowFiles) realDocs[f] = parseYaml(readFileSync(join(WORKFLOW_DIR, f), "utf8")) as Doc;
const WEB = realDocs["apply-web-platform-infra.yml"];
const FIX = realDocs["apply-deploy-pipeline-fix.yml"];
const clone = <T,>(x: T): T => JSON.parse(JSON.stringify(x));

const realCreating = (): Array<[string, string]> => {
  const out: Array<[string, string]> = [];
  for (const [f, d] of Object.entries(realDocs)) for (const id of hostCreatingJobIds(d, realReadAction)) out.push([f, id]);
  return out;
};

describe("Guard 3: the real tree", () => {
  test("the workflow set is non-empty and both web workflows parse", () => {
    expect(workflowFiles.length).toBeGreaterThan(10);
    expect(Object.keys(WEB?.jobs ?? {}).length).toBeGreaterThan(5);
    expect(Object.keys(FIX?.jobs ?? {}).length).toBeGreaterThan(0);
  });

  test("the census finds the host-creating jobs: web_host_create and web_host_replace, and at least the floor", () => {
    const found = realCreating();
    expect(floorViolation(found.length)).toBeNull();
    const ids = found.filter(([f]) => f === "apply-web-platform-infra.yml").map(([, id]) => id);
    expect(ids).toContain("web_host_create");
    expect(ids).toContain("web_host_replace");
  });

  test("the predicate is a -target/-replace ARGUMENT: the three state-presence jq loops are NOT host-creating", () => {
    const ids = hostCreatingJobIds(WEB, realReadAction);
    for (const notCreator of ["inngest_volume_recut", "workspaces_luks_cutover", "workspaces_luks_recut"]) {
      expect(WEB.jobs![notCreator], `${notCreator} must exist (a renamed job would make this row vacuous)`).toBeDefined();
      expect(jobText(WEB.jobs![notCreator], realReadAction)).toContain("hcloud_server.web[");
      expect(ids).not.toContain(notCreator);
    }
  });

  test("every host-creating job on the real tree runs the preflight, unconditionally, before any Terraform command", () => {
    const bad: string[] = [];
    for (const [f, d] of Object.entries(realDocs)) for (const v of censusViolations(d, realReadAction)) bad.push(`${f}: ${v}`);
    expect(bad).toEqual([]);
  });

  test("the two refusing routes keep their host_creates HALT (pinned by name, independent of the predicate)", () => {
    expect(haltViolations(WEB.jobs!.apply)).toEqual([]);
    expect(haltViolations(FIX.jobs!.apply)).toEqual([]);
  });

  test("the refusing routes never match the predicate (so only their HALTs keep 'every route' true)", () => {
    expect(hostCreatingJobIds(WEB, realReadAction)).not.toContain("apply");
    expect(hostCreatingJobIds(FIX, realReadAction)).not.toContain("apply");
  });
});

describe("Guard 3: mutation matrix (each row mutates a copy of the parsed real workflow)", () => {
  const stepIdx = (job: any, pred: (s: any) => boolean): number => job.steps.findIndex(pred);

  for (const jobId of ["web_host_create", "web_host_replace"]) {
    test(`M1 deleting the step from ${jobId} -> RED`, () => {
      const d = clone(WEB);
      const job = d.jobs![jobId];
      job.steps.splice(stepIdx(job, isPreflightStep), 1);
      expect(censusViolations(d, realReadAction).join("\n")).toContain(`${jobId}: no step runs exactly`);
    });
  }

  test("M2 moving the step after the first Terraform command -> RED (ordering)", () => {
    const d = clone(WEB);
    const job = d.jobs!.web_host_create;
    const [step] = job.steps.splice(stepIdx(job, isPreflightStep), 1);
    const planAt = stepIdx(job, (s) => isTerraformStep(s, realReadAction));
    job.steps.splice(planAt + 1, 0, step);
    expect(censusViolations(d, realReadAction).join("\n")).toContain("AFTER the first Terraform command");
  });

  for (const [label, mutate, needle] of [
    ["continue-on-error: true", (s: any) => (s["continue-on-error"] = true), "continue-on-error"],
    ["an if:", (s: any) => (s.if = "always()"), "'if:'"],
    ["a working-directory", (s: any) => (s["working-directory"] = "apps/web-platform/infra"), "working-directory"],
    ["a swallowed exit code (|| true)", (s: any) => (s.run = `${PREFLIGHT_RUN} || true`), "no step runs exactly"],
    ["a different timeout", (s: any) => (s["timeout-minutes"] = 30), "timeout-minutes: 2"],
    ["an extra env credential", (s: any) => (s.env.GH_TOKEN = "x"), "env must be exactly DOPPLER_TOKEN"],
  ] as Array<[string, (s: any) => void, string]>) {
    test(`M3 the step gains ${label} -> RED`, () => {
      const d = clone(WEB);
      const job = d.jobs!.web_host_replace;
      mutate(job.steps[stepIdx(job, isPreflightStep)]);
      expect(censusViolations(d, realReadAction).join("\n")).toContain(needle);
    });
  }

  test("M3b the JOB gains continue-on-error: true -> RED", () => {
    const d = clone(WEB);
    d.jobs!.web_host_create["continue-on-error"] = true;
    expect(censusViolations(d, realReadAction).join("\n")).toContain("the job carries continue-on-error");
  });

  for (const [label, run] of [
    ["the checker's --static mode", "bash scripts/check-web-host-escrow-config.sh --static"],
    ["a different script", "bash scripts/some-other-check.sh"],
    ["the checker --live called directly (no wrapper, no provider token plumbing)", "bash scripts/check-web-host-escrow-config.sh --live"],
  ] as Array<[string, string]>) {
    test(`M4 the step points at ${label} -> RED`, () => {
      const d = clone(WEB);
      const job = d.jobs!.web_host_create;
      job.steps[stepIdx(job, isPreflightStep)].run = run;
      expect(censusViolations(d, realReadAction).join("\n")).toContain("no step runs exactly");
    });
  }

  const rebirth = (withPreflight: boolean): any => {
    const steps: any[] = [{ uses: "actions/checkout@v4" }];
    if (withPreflight) steps.push({ name: "Escrow", run: PREFLIGHT_RUN, "timeout-minutes": 2, env: { DOPPLER_TOKEN: "${{ secrets.DOPPLER_TOKEN }}" } });
    steps.push({ name: "Plan", run: 'terraform plan -target="hcloud_server.web[\\"web-2\\"]" -out=tfplan' });
    steps.push({ name: "Apply", run: "terraform apply tfplan" });
    return { steps };
  };
  // The apply argument is carried on the plan in a saved-plan flow, so the fixture's apply names the target too.
  const rebirthApply = (withPreflight: boolean): any => {
    const j = rebirth(withPreflight);
    j.steps[j.steps.length - 1].run = 'terraform apply -target="hcloud_server.web[\\"web-2\\"]" tfplan';
    return j;
  };

  test("M5 a THIRD job with terraform apply against hcloud_server.web[ and no preflight, after two compliant jobs -> RED (the scan does not stop at the first compliant job)", () => {
    const d = clone(WEB);
    d.jobs!.web_host_rebirth_fixture = rebirthApply(false);
    const v = censusViolations(d, realReadAction);
    expect(v.join("\n")).toContain("web_host_rebirth_fixture: no step runs exactly");
    expect(v.filter((x) => x.startsWith("web_host_create:") || x.startsWith("web_host_replace:"))).toEqual([]);
  });

  test("M6 a NEW workflow file of the rebirth shape with no preflight -> RED (unexempt by default)", () => {
    const d: Doc = { jobs: { rebirth: rebirthApply(false) } };
    expect(censusViolations(d, realReadAction)).toEqual(["rebirth: no step runs exactly 'bash scripts/web-host-escrow-preflight.sh'"]);
  });

  test("M6b a rebirth-shaped workflow WITH the compliant step is GREEN (the RED rows are not 'everything fails')", () => {
    const d: Doc = { jobs: { rebirth: rebirthApply(true) } };
    expect(hostCreatingJobIds(d, realReadAction)).toEqual(["rebirth"]);
    expect(censusViolations(d, realReadAction)).toEqual([]);
  });

  test("M6c a job that applies through a LOCAL composite action is still seen (the predicate reads the action's run text)", () => {
    const action = `runs:\n  using: composite\n  steps:\n    - shell: bash\n      run: terraform apply -target="hcloud_server.web[\\"web-2\\"]" tfplan\n`;
    const d: Doc = { jobs: { viaAction: { steps: [{ uses: "./.github/actions/rebirth" }] } } };
    const read: ReadAction = (p) => (p === "./.github/actions/rebirth" ? action : "");
    expect(hostCreatingJobIds(d, read)).toEqual(["viaAction"]);
    expect(censusViolations(d, read).join("\n")).toContain("viaAction: no step runs exactly");
  });

  test("M7 removing the host_creates HALT from apply-web-platform-infra.yml:apply -> RED", () => {
    const d = clone(WEB);
    for (const s of d.jobs!.apply.steps) if (typeof s.run === "string") s.run = s.run.replace(/if \[\[ "\$host_creates" -gt 0 \]\]; then/g, "if false; then");
    expect(haltViolations(d.jobs!.apply).join("\n")).toContain("no `if [[ \"$host_creates\" -gt 0 ]]; then` HALT");
  });

  test("M7b removing the host_creates HALT from apply-deploy-pipeline-fix.yml:apply -> RED", () => {
    const d = clone(FIX);
    for (const s of d.jobs!.apply.steps) if (typeof s.run === "string") s.run = s.run.replace(/if \[\[ "\$host_creates" -gt 0 \]\]; then/g, "if false; then");
    expect(haltViolations(d.jobs!.apply).join("\n")).toContain("HALT (exact, unconditioned)");
  });

  test("M7c a HALT that gained an acknowledgement condition, an exit 0, or a skip branch -> RED", () => {
    for (const [from, to, needle] of [
      ['if [[ "$host_creates" -gt 0 ]]; then', 'if [[ "$host_creates" -gt 0 && "$ACK" != true ]]; then', "HALT (exact, unconditioned)"],
      ["exit 1", "exit 0", "does not `exit 1`"],
    ] as Array<[string, string, string]>) {
      const d = clone(FIX);
      let landed = false;
      for (const s of d.jobs!.apply.steps) {
        if (typeof s.run !== "string" || !s.run.includes('host_creates" -gt 0')) continue;
        const at = s.run.indexOf('if [[ "$host_creates" -gt 0 ]]; then');
        const blockEnd = s.run.indexOf("\nfi\n", at); // a parsed YAML block scalar carries no base indent
        expect(blockEnd, "the HALT block must close").toBeGreaterThan(at);
        const block = s.run.slice(at, blockEnd);
        const mutated = from === "exit 1" ? block.split("exit 1").join("exit 0") : block.replace(from, to);
        landed = mutated !== block;
        // exit 1 -> exit 0 must replace every exit 1 in the block, not only the first
        s.run = s.run.slice(0, at) + mutated + s.run.slice(blockEnd);
      }
      expect(landed, `the mutation '${from}' must land`).toBe(true);
      expect(haltViolations(d.jobs!.apply).join("\n")).toContain(needle);
    }
  });

  test("M7d a HALT with a skip path in an executable line (no exit 0 involved) -> RED", () => {
    const d = clone(FIX);
    let landed = false;
    for (const s of d.jobs!.apply.steps) {
      if (typeof s.run === "string" && s.run.includes('host_creates" -gt 0')) {
        const before = s.run;
        s.run = s.run.replace(/\n(  exit 1\nfi\necho "deploy-pipeline-fix plan creates no hcloud_server)/, '\n  [[ -n "${SKIP_HALT:-}" ]] && continue_apply=1\n$1');
        landed = landed || s.run !== before;
      }
    }
    expect(landed, "the mutation must land").toBe(true);
    expect(haltViolations(d.jobs!.apply).join("\n")).toContain("acknowledgement/skip path");
  });

  test("M7e a HALT that can exit 0 in an executable line -> RED", () => {
    const d = clone(FIX);
    let landed = false;
    for (const s of d.jobs!.apply.steps) {
      if (typeof s.run === "string" && s.run.includes('host_creates" -gt 0')) {
        const before = s.run;
        s.run = s.run.replace(/\n(  exit 1\nfi\necho "deploy-pipeline-fix plan creates no hcloud_server)/, '\n  [[ -n "${X:-}" ]] && exit 0\n$1');
        landed = landed || s.run !== before;
      }
    }
    expect(landed, "the mutation must land").toBe(true);
    expect(haltViolations(d.jobs!.apply).join("\n")).toContain("can `exit 0`");
  });

  test("M7f a HALT nested inside an outer conditional (a skip branch around it) -> RED", () => {
    const nested = [
      "          host_creates=$(echo \"$counts\" | jq -r '.host_creates')",
      '          if [[ "$SKIP" != 1 ]]; then',
      '            if [[ "$host_creates" -gt 0 ]]; then',
      "              exit 1",
      "            fi",
      "          fi",
    ];
    // The checker anchors on the HALT's own indent: the nested copy sits two levels away from the counter read.
    const job = { steps: [{ run: nested.join("\n") }] };
    expect(haltViolations(job).join("\n")).toContain("nested at a different level");
    const flat = { steps: [{ run: ["host_creates=$(echo \"$counts\" | jq -r '.host_creates')", 'if [[ "$host_creates" -gt 0 ]]; then', "  exit 1", "fi"].join("\n") }] };
    expect(haltViolations(flat)).toEqual([]);
  });

  test("P1 predicate precision: a -replace-only job and a plan-only job (no terraform apply) are classified correctly", () => {
    const replaceOnly: Doc = { jobs: { r: { steps: [{ run: 'terraform apply -replace="hcloud_server.web[\\"web-2\\"]" tfplan' }] } } };
    expect(hostCreatingJobIds(replaceOnly, realReadAction)).toEqual(["r"]);
    const planOnly: Doc = { jobs: { p: { steps: [{ run: 'terraform plan -target="hcloud_server.web[\\"web-2\\"]" -out=tfplan' }] } } };
    expect(hostCreatingJobIds(planOnly, realReadAction)).toEqual([]);
    const commentOnly: Doc = { jobs: { c: { steps: [{ run: '# terraform apply -target="hcloud_server.web[\\"web-2\\"]"\necho hi' }] } } };
    expect(hostCreatingJobIds(commentOnly, realReadAction)).toEqual([]);
  });

  test("M8 the census finding fewer than the floor of host-creating jobs -> RED (it must not pass over an empty set)", () => {
    expect(floorViolation(0)).toContain("below the floor");
    expect(floorViolation(HOST_CREATING_FLOOR - 1)).toContain("below the floor");
    const d = clone(WEB);
    delete d.jobs!.web_host_create;
    delete d.jobs!.web_host_replace;
    expect(floorViolation(hostCreatingJobIds(d, realReadAction).length)).toContain("below the floor");
  });

  test("H1 harness: the preflight under a different step name with unrelated steps reordered is still GREEN", () => {
    const d = clone(WEB);
    const job = d.jobs!.web_host_create;
    const at = stepIdx(job, isPreflightStep);
    job.steps[at].name = "Totally different name";
    // Reorder two unrelated steps that sit BEFORE the first Terraform command (the SSH key step and the dispatch validation).
    const firstTf = stepIdx(job, (s) => isTerraformStep(s, realReadAction));
    const early = job.steps.slice(0, firstTf).filter((s: any) => !isPreflightStep(s));
    expect(early.length).toBeGreaterThan(3);
    const a = job.steps.indexOf(early[1]);
    const b = job.steps.indexOf(early[2]);
    [job.steps[a], job.steps[b]] = [job.steps[b], job.steps[a]];
    expect(censusViolations(d, realReadAction)).toEqual([]);
  });

  test("H2 harness: the census over a workflow with the dispatch removed is RED via the floor, not green by emptiness", () => {
    const d = clone(WEB);
    for (const id of hostCreatingJobIds(d, realReadAction)) delete d.jobs![id];
    expect(censusViolations(d, realReadAction)).toEqual([]);
    expect(floorViolation(hostCreatingJobIds(d, realReadAction).length)).not.toBeNull();
  });

  test("H3 harness: the HALT checker returns violations for a job that has no run text at all", () => {
    expect(haltViolations({ steps: [] }).length).toBeGreaterThan(0);
    expect(haltViolations(undefined).length).toBeGreaterThan(0);
  });
});

// --- suite-level anti-vacuity ------------------------------------------------------------------------------
describe("this suite itself cannot be silently narrowed", () => {
  const selfText = readFileSync(resolve(import.meta.dir, "web-host-escrow-preflight-census.test.ts"), "utf8");

  test("no test or describe is skipped, focused, or stubbed out", () => {
    for (const bad of [".skip(", ".only(", ".todo(", ".failing("]) {
      const hits = selfText.split("\n").filter((l) => l.includes(`test${bad}`) || l.includes(`describe${bad}`));
      expect(hits).toEqual([]);
    }
  });

  test("the declared test count is at or above the shipped floor", () => {
    // Loop-generated rows (for ... test(`...`)) count once in the source and N times at run time; the floor is
    // hand-ratcheted to the SOURCE count, deliberately exact: deleting a row costs one deliberate edit here.
    const declared = selfText.match(/^\s*test\(/gm)?.length ?? 0;
    expect(declared).toBeGreaterThanOrEqual(TEST_FLOOR);
  });
});

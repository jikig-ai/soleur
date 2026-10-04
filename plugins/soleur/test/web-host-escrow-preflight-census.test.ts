// Guard 3 census (#9377, decision B1): every workflow job that can create or replace hcloud_server.web[...] runs
// scripts/web-host-escrow-preflight.sh, fail-closed, before any Terraform command.
//
// PREDICATE. A job is host-creating when its whole non-comment text (every step's `run`, and the `run` text of any
// local composite action a step `uses`) contains a `terraform apply` (any global-option form, e.g.
// `terraform -chdir=DIR apply`) AND a `-target`/`-replace` ARGUMENT (`=value` or ` value`, any quoting) that is one of
//   (a) an indexed server address `hcloud_server.web[...]`, anywhere in the job text;
//   (b) the BARE map `hcloud_server.web` (it targets every host), inside a `terraform apply|plan|destroy|refresh`
//       statement that is not operator prose. Prose is excluded POSITIVELY: a `terraform` word inside a quoted string
//       (see quotedMask: apply-deploy-pipeline-fix.yml carries four "Do NOT run terraform apply -replace=hcloud_server.web"
//       sentences inside quoted messages and creates nothing through them) or on an `echo`/`printf`/`::` line. If the
//       quotes of a run text do not balance nothing is excluded, so a lexer upset can only over-flag. A quoted string
//       whose FIRST word is the binary is a command line, not prose (`bash -c "terraform apply ..."`, `sh -c '...'`,
//       `eval "..."`, `ssh h "..."`, `doppler run -- sh -c "..."`, and a `$(...)`/backtick on an echo line).
//       KNOWN OVER-FLAGS (no real job is affected): a message string that merely STARTS with the binary
//       (`msg="terraform apply -replace=hcloud_server.web is forbidden"`), and prose inside an unquoted heredoc.
//       OUT OF SCOPE, undecidable statically: the flags held in a variable or array and expanded at the call
//       (`F="-target=hcloud_server.web"` ... `terraform apply $F`), or a command word built at run time.
//       Address forms: `hcloud_server.web...` optionally behind a `module.<m>[...].` path; the binary may be `terraform` or
//       `tofu`, bare or path-qualified; `terraform \\` + newline + subcommand is one command (continuations are joined);
//   (c) a NON-LITERAL value (starts with `$`: `$VAR`, `${VAR}`, `$(cmd)`, `${ARR[@]}`), anywhere in the job text, because
//       a variable can hold any address including (a)/(b), and an array built on one line and applied on another is
//       the same route. This over-flags, deliberately: the cost of a false match is one extra preflight line.
// A bare mention is NOT enough: three jobs (`inngest_volume_recut`, `workspaces_luks_cutover`, `workspaces_luks_recut`)
// loop over that address in `jq` state-presence checks and create nothing. Still outside the predicate (the floor and
// review of any new workflow are the backstop, recorded in the plan's Risks): a plan/apply SPLIT across two jobs where the
// apply job names no target, a birth wrapped in a script file or nested composite, a dependency pull (`-target` of a
// resource whose closure includes the server, which the per-merge `apply` jobs rely on their `host_creates` HALT for), and
// a terraform call whose binary name is built at run time. Also outside the later-step rule: job/workflow-level
// `defaults.run.shell` (DEFERRED), and a plan/apply SPLIT across jobs (DEFERRED).
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
const TEST_FLOOR = 35;
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
function jobRuns(job: any, readAction: ReadAction): string[] {
  const parts: string[] = [];
  for (const s of job?.steps ?? []) {
    if (typeof s?.run === "string") parts.push(stripShellComments(s.run));
    parts.push(actionRunText(s, readAction));
  }
  return parts;
}
const jobText = (job: any, readAction: ReadAction): string => jobRuns(job, readAction).join("\n");

// The Terraform binary: `terraform` or `tofu`, bare or path-qualified (`/usr/local/bin/terraform`, `./terraform`).
const TF_BIN = String.raw`(?:[A-Za-z0-9_.\/-]*\/)?(?:terraform|tofu)`;
const NOT_WORD_BEFORE = String.raw`(?<![A-Za-z0-9_.\/-])`;
// An optional module path in front of the address: `module.m.`, `module.m["k"].`, nested.
const MOD = String.raw`(?:module\.[A-Za-z0-9_-]+(?:\[[^\]]*\])?\.)*`;
const TF_APPLY_RE = new RegExp(String.raw`${NOT_WORD_BEFORE}${TF_BIN}\s+(?:-[^\s]+\s+)*apply\b`);
// (a) A -target / -replace argument naming an indexed server, however the quotes are spelled (`-target="hcloud_server.web[\"k\"]"`,
// `-replace='hcloud_server.web["k"]'`, `-target hcloud_server.web[...]`, `-target=module.m.hcloud_server.web[...]`).
const HOST_ARG_RE = new RegExp(String.raw`-{1,2}(?:target|replace)(?:=|\s+)\\?["']?${MOD}hcloud_server\.web\[`);
// (b) The bare map address; tested only against terraform STATEMENTS (see quotedMask).
const BARE_ARG_RE = new RegExp(String.raw`(?<![A-Za-z0-9_-])-{1,2}(?:target|replace)(?:=|\s+)\\?["']?${MOD}hcloud_server\.web(?![A-Za-z0-9_])`);
// (c) A non-literal value: the first character of the value (after an optional quote) is `$`.
const NONLITERAL_ARG_RE = /(?<![A-Za-z0-9_-])-{1,2}(?:target|replace)(?:=|\s+)\\?["']?\$/;
// The ordering rule's "any Terraform command" matcher: global options may sit between `terraform` and the subcommand
// (`terraform -chdir=DIR init`), exactly as TF_APPLY_RE allows for apply; run on continuation-joined text.
const TF_CMD_RE = new RegExp(String.raw`(?:^|[\s;&|(])${TF_BIN}\s+(?:-[^\s]+\s+)*(?:init|plan|apply|validate|state|import|output|show|fmt|workspace|providers|force-unlock|destroy|taint|untaint)\b`, "m");
// A terraform statement: `terraform [global options] apply|plan|destroy|refresh ...` to the end of its logical line.
const TF_STMT_RE = new RegExp(String.raw`${NOT_WORD_BEFORE}${TF_BIN}\s+(?:-[^\s]+\s+)*(?:apply|plan|destroy|refresh)\b`, "g");

/** A shell text with backslash-newline continuations joined (so `terraform \` + newline + `apply` reads as one command). */
const joinCont = (t: string): string => t.replace(/\\\n[ \t]*/g, " ");
const logicalLines = (t: string): string[] => joinCont(t).split("\n");

/**
 * For each index of `t`, whether it sits inside a quoted string (double or single; a `$( )` inside double quotes is code
 * again). That is how operator prose is told from a command: a `terraform` word inside a quoted message, such as the four
 * "Do NOT run terraform apply -replace=hcloud_server.web" sentences of apply-deploy-pipeline-fix.yml, is text. Returns null
 * when the quotes do not balance (a stray apostrophe in a comment or heredoc): nothing is then excluded, so detection wins
 * over exclusion and a parity flip can only over-flag.
 */
function quotedMask(t: string): boolean[] | null {
  const mask = new Array<boolean>(t.length).fill(false);
  const st: Array<"cmd" | "paren" | "dq" | "sq"> = ["cmd"];
  for (let i = 0; i < t.length; i++) {
    const m = st[st.length - 1];
    const c = t[i];
    if (m === "sq") {
      mask[i] = true;
      if (c === "'") st.pop();
      continue;
    }
    if (c === "\\") {
      if (m === "dq") mask[i] = mask[i + 1] = true;
      i++;
      continue;
    }
    if (m === "dq") {
      mask[i] = true;
      if (c === '"') st.pop();
      else if (c === "$" && t[i + 1] === "(") {
        st.push("paren");
        i++;
      }
      continue;
    }
    if (c === "'") {
      st.push("sq");
      mask[i] = true;
    } else if (c === '"') {
      st.push("dq");
      mask[i] = true;
    } else if (c === "$" && t[i + 1] === "(") {
      st.push("paren");
      i++;
    } else if (c === ")" && m === "paren") st.pop();
  }
  return st.length === 1 ? mask : null;
}

/** Every terraform apply|plan|destroy|refresh statement of one shell text (to the end of its logical line), prose excluded. */
function terraformStatements(run: string): string[] {
  const t = joinCont(run);
  const mask = quotedMask(t);
  const out: string[] = [];
  let lineStart = 0;
  for (const line of t.split("\n")) {
    const hits = [...line.matchAll(TF_STMT_RE)];
    hits.forEach((m, i) => {
      const prefix = line.slice(0, m.index);
      // Inside a quoted string the word is prose, UNLESS it is the string's first word (`bash -c "terraform apply ..."`,
      // `sh -c '...'`, `eval "..."`, `ssh h "..."`, `doppler run -- sh -c "..."`): then the string is a command line.
      const quoted = mask?.[lineStart + m.index!] === true && !/["']\s*$/.test(prefix);
      // An echo/printf/`::` line is a sentence, unless a command substitution (`$(` or a backtick) on it runs the word.
      const sentence =
        /^\s*(?:echo|printf|::)/.test(prefix) && !/[;&|]/.test(prefix.replace(/^\s*(?:echo|printf)\b/, "")) && !/\$\(|`/.test(prefix);
      // A statement ends where the next `terraform` word begins, so a documented command followed by prose is two statements.
      if (!quoted && !sentence) out.push(line.slice(m.index, hits[i + 1]?.index ?? line.length));
    });
    lineStart += line.length + 1;
  }
  return out;
}

function isHostCreating(job: any, readAction: ReadAction): boolean {
  const runs = jobRuns(job, readAction);
  const t = runs.map(joinCont).join("\n");
  if (!TF_APPLY_RE.test(t)) return false;
  return HOST_ARG_RE.test(t) || NONLITERAL_ARG_RE.test(t) || runs.flatMap(terraformStatements).some((st) => BARE_ARG_RE.test(st));
}

function hostCreatingJobIds(doc: Doc, readAction: ReadAction): string[] {
  return Object.entries(doc.jobs ?? {})
    .filter(([, job]) => isHostCreating(job, readAction))
    .map(([id]) => id);
}

const isPreflightStep = (s: any): boolean => typeof s?.run === "string" && stripShellComments(s.run).trim() === PREFLIGHT_RUN;
const isTerraformStep = (s: any, readAction: ReadAction): boolean =>
  (typeof s?.run === "string" && TF_CMD_RE.test(joinCont(stripShellComments(s.run)))) || TF_CMD_RE.test(joinCont(actionRunText(s, readAction)));

// An `if:` that lets a step run after an earlier step failed: the status functions (case-insensitive in GitHub expressions),
// `!success()`, and a comparison of a step's outcome/conclusion against a failure value (`== 'failure'`, `!= 'success'`).
const RUNS_AFTER_FAILURE_RE =
  /\b(?:always|failure|cancelled)\s*\(|!\s*success\s*\(|\b(?:outcome|conclusion)\s*(?:==\s*['"](?:failure|cancelled|skipped)['"]|!=\s*['"]success['"])/i;

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
  // A Terraform step AFTER the preflight must not run when the preflight failed: `if: always()|failure()|cancelled()` would
  // let `terraform apply` execute after a red preflight, which is the birth the preflight exists to stop.
  steps.forEach((st, i) => {
    if (i <= idx || !isTerraformStep(st, readAction)) return;
    const cond = typeof st?.if === "string" ? st.if : "";
    if (RUNS_AFTER_FAILURE_RE.test(cond)) v.push(`step #${i} runs Terraform after the preflight under 'if: ${cond}' (it would run after a red preflight)`);
  });
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
  // EVERY host_creates HALT block must hold (apply-deploy-pipeline-fix.yml carries two: the plan and the re-push plan);
  // checking only the first let the second be neutered with the suite green.
  const starts = lines.map((l, i) => (ifRe.test(l) ? i : -1)).filter((i) => i >= 0);
  if (starts.length === 0) return ["no `if [[ \"$host_creates\" -gt 0 ]]; then` HALT (exact, unconditioned) found"];
  const v: string[] = [];
  // Both read spellings in the tree: `host_creates=$(echo "$counts" | jq -r '.host_creates')` and the re-push plan's
  // `host_creates=$(jq -r '.host_creates' <<<"$counts") || rc=$?`.
  const readRe = /^\s*host_creates=\$\((?:echo "\$counts" \| jq -r '\.host_creates'|jq -r '\.host_creates' <<<"\$counts")\)(?: \|\| rc=\$\?)?\s*$/;
  for (const start of starts) {
    const indent = ifRe.exec(lines[start])![1];
    // The HALT must sit at the same nesting level as the counter read that PRECEDES it, i.e. not inside an ack/skip branch.
    let readIdx = -1;
    for (let i = start - 1; i >= 0; i--) {
      if (readRe.test(lines[i])) {
        readIdx = i;
        break;
      }
    }
    if (readIdx < 0) v.push("the host_creates counter is not read from the destroy-guard filter output");
    else if (/^(\s*)/.exec(lines[readIdx])![1] !== indent) v.push("the HALT is nested at a different level than the counter read (inside a conditional?)");
    let end = -1;
    for (let i = start + 1; i < lines.length; i++) {
      if (lines[i] === `${indent}fi`) {
        end = i;
        break;
      }
    }
    if (end < 0) {
      v.push("the HALT block has no closing fi at its own indent");
      continue;
    }
    const body = lines.slice(start + 1, end);
    if (!body.some((l) => /^\s*exit 1\s*$/.test(l))) v.push("the HALT body does not `exit 1`");
    // Executable lines only: the prose of an `echo "::error::..."` may legitimately say "no ack token" or quote an exit code.
    const exec = body.filter((l) => !/^\s*echo\b/.test(l));
    if (exec.some((l) => /\bexit 0\b/.test(l))) v.push("the HALT body can `exit 0`");
    // No acknowledgement path: nothing executable (non-echo) in the body mentions an ack/skip/override.
    if (exec.some((l) => /ack|skip|override|bypass/i.test(l))) v.push("the HALT body carries an acknowledgement/skip path");
  }
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

  test("M7g neutering ONLY the second host_creates HALT block of apply-deploy-pipeline-fix.yml (the re-push plan) -> RED", () => {
    const d = clone(FIX);
    const haltSteps = d.jobs!.apply.steps.filter((s: any) => typeof s.run === "string" && s.run.includes('host_creates" -gt 0'));
    expect(haltSteps.length, "the workflow must carry two HALT-bearing steps (plan and re-push plan)").toBeGreaterThanOrEqual(2);
    expect(haltSteps[0]).not.toBe(haltSteps[1]);
    const second = haltSteps[haltSteps.length - 1];
    const at = second.run.indexOf('if [[ "$host_creates" -gt 0 ]]; then');
    const blockEnd = second.run.indexOf("\nfi\n", at);
    expect(blockEnd).toBeGreaterThan(at);
    second.run = second.run.slice(0, at) + second.run.slice(at, blockEnd).split("exit 1").join("exit 0") + second.run.slice(blockEnd);
    expect(haltViolations(d.jobs!.apply).join("\n")).toContain("does not `exit 1`");
    // Control: the first block alone is still clean, so the violation above came from the second block.
    const e = clone(FIX);
    expect(haltViolations(e.jobs!.apply)).toEqual([]);
  });

  test("P1 predicate precision: a -replace-only job and a plan-only job (no terraform apply) are classified correctly", () => {
    const replaceOnly: Doc = { jobs: { r: { steps: [{ run: 'terraform apply -replace="hcloud_server.web[\\"web-2\\"]" tfplan' }] } } };
    expect(hostCreatingJobIds(replaceOnly, realReadAction)).toEqual(["r"]);
    const planOnly: Doc = { jobs: { p: { steps: [{ run: 'terraform plan -target="hcloud_server.web[\\"web-2\\"]" -out=tfplan' }] } } };
    expect(hostCreatingJobIds(planOnly, realReadAction)).toEqual([]);
    const commentOnly: Doc = { jobs: { c: { steps: [{ run: '# terraform apply -target="hcloud_server.web[\\"web-2\\"]"\necho hi' }] } } };
    expect(hostCreatingJobIds(commentOnly, realReadAction)).toEqual([]);
  });

  // P2: every address shape the broadened predicate must catch, and its must-not-match neighbours. Each fixture is one job with
  // one run step; `-chdir`, space-form, bare-map and non-literal values are the shapes the indexed-only predicate missed.
  const jobOf = (run: string): Doc => ({ jobs: { j: { steps: [{ run }] } } });
  const creating = (run: string): boolean => hostCreatingJobIds(jobOf(run), realReadAction).length === 1;

  for (const [label, run] of [
    ["the bare map address, = form", "terraform apply -target=hcloud_server.web tfplan"],
    ["the bare map address, quoted", `terraform apply -target="hcloud_server.web" tfplan`],
    ["the bare map address, space form", "terraform apply -target hcloud_server.web tfplan"],
    ["the bare map address through -replace", "terraform apply -replace=hcloud_server.web"],
    ["an indexed address, space form", `terraform apply -target 'hcloud_server.web["web-2"]'`],
    ["-chdir before the subcommand", `terraform -chdir=apps/web-platform/infra apply -replace="hcloud_server.web[\\"web-2\\"]"`],
    ["-chdir with the bare map", "terraform -chdir=apps/web-platform/infra apply -target=hcloud_server.web"],
    ["a quoted variable value", `terraform apply -target="$HOST_ADDR" tfplan`],
    ["a braced variable value", "terraform apply -target=${HOST_ADDR} tfplan"],
    ["a command substitution value", "terraform apply -replace=$(cat addr.txt)"],
    ["a variable value, space form", `terraform apply -target "$ADDR"`],
    ["an array expansion", `terraform apply "\${ARGS[@]}" -target="\${TARGETS[@]}"`],
    ["an array built on one line and applied on another", `ARGS+=("-target=$ADDR")\nterraform apply "\${ARGS[@]}"`],
    ["a line continuation between the words", "terraform apply \\\n  -target=hcloud_server.web"],
    ["a wrapped call (doppler run ... --)", "doppler run -- terraform apply -target=hcloud_server.web"],
    ["bash -c with the command line in double quotes", `bash -c "terraform apply -target=hcloud_server.web"`],
    ["sh -c with the command line in single quotes", `sh -c 'terraform apply -replace=hcloud_server.web'`],
    ["eval of a quoted command line", `eval "terraform apply -target=hcloud_server.web"`],
    ["a command line sent over ssh", `ssh deploy@host "terraform apply -target=hcloud_server.web"`],
    ["a wrapped shell: doppler run -- sh -c", `doppler run -- sh -c "terraform apply -target=hcloud_server.web"`],
    ["a path-qualified binary as the first word of a quoted line", `bash -c "/usr/local/bin/terraform apply -replace=hcloud_server.web"`],
    ["an echo of a command substitution", "echo $(terraform apply -target=hcloud_server.web)"],
    ["a backtick command substitution on an echo line", "echo `terraform apply -target=hcloud_server.web`"],
    ["a module-qualified bare address","terraform apply -target=module.fleet.hcloud_server.web tfplan"],
    ["a module-qualified indexed address", `terraform apply -replace='module.fleet["eu"].hcloud_server.web["web-2"]'`],
    ["a nested module path", "terraform apply -target=module.a.module.b.hcloud_server.web"],
    ["a module-qualified indexed address built into an array on another line", `ARGS+=("-target=module.m.hcloud_server.web[\\"web-2\\"]")\nterraform apply "\${ARGS[@]}"`],
    ["a path-qualified binary", "/usr/local/bin/terraform apply -target=hcloud_server.web"],
    ["a relative binary", "./terraform apply -target=hcloud_server.web"],
    ["tofu", "tofu apply -target=hcloud_server.web"],
    ["a path-qualified tofu with -chdir", "/opt/bin/tofu -chdir=infra apply -replace=hcloud_server.web"],
    ["the subcommand on the line after a continuation", "terraform \\\n  apply -target=hcloud_server.web"],
    ["a real command inside a command substitution inside double quotes", `out="$(terraform apply -target=hcloud_server.web)"`],
    ["a quote upset (unbalanced apostrophe) disables the prose exclusion, so it can only over-flag", `LEVER="Do NOT run terraform apply -replace=hcloud_server.web"; x=it's\nterraform apply tfplan`],
  ] as Array<[string, string]>) {
    test(`P2 predicate catches ${label}`, () => {
      expect(creating(run)).toBe(true);
    });
  }

  test("P2b must-not-match neighbours: other addresses, a plan-only job, prose, comments", () => {
    for (const run of [
      "terraform apply -target=hcloud_server.web_other tfplan", // a different resource that merely shares the prefix
      "terraform apply -target=hcloud_server.webhook tfplan",
      "terraform apply -target=hcloud_firewall.web tfplan",
      "terraform apply -target=cloudflare_record.web tfplan",
      "terraform apply -target=terraform_data.deploy_pipeline_fix tfplan",
      "terraform apply tfplan", // no target at all: the saved-plan apply carries none (an acknowledged limit)
      `terraform plan -target="$ADDR" -out=tfplan`, // no apply in the job
      "terraform plan -target=hcloud_server.web -out=tfplan",
      "# terraform apply -target=hcloud_server.web\necho hi",
      `terraform apply --rehearse-target "$T" tfplan`, // a different option that merely ends in -target
      // operator prose (the real apply-deploy-pipeline-fix.yml shape): a documented command, then a sentence naming the bare map
      `echo "run: terraform apply -target=terraform_data.x -input=false . Do NOT run terraform apply -replace=hcloud_server.web -- that host cannot be re-provisioned"\nterraform apply tfplan`,
      `echo "Never use terraform apply -target=hcloud_server.web here"\nterraform apply tfplan`,
      // positive prose exclusion: a quoted multi-line message, a single-quoted message, an unquoted echo/printf line
      `LEVER="the lever is: terraform apply -target=terraform_data.x -input=false .\n  Do NOT run terraform apply -replace=hcloud_server.web -- that host cannot be re-provisioned"\nterraform apply tfplan`,
      `msg='Never terraform apply -replace=hcloud_server.web'\nterraform apply tfplan`,
      `printf '%s\\n' 'terraform apply -target=hcloud_server.web'\nterraform apply tfplan`,
      "echo terraform apply -replace=hcloud_server.web\nterraform apply tfplan",
      // neighbours of the new address and binary forms
      "terraform apply -target=module.fleet.hcloud_server.webhook",
      "terraform apply -target=module.fleet.hcloud_firewall.web",
      "my-terraform apply -target=hcloud_server.web", // a different binary that merely ends in the name
      "terraform-docs apply -target=hcloud_server.web",
      // neighbours of the quoted-command-line rule: the word is NOT the string's first word, or the line is a plain echo
      `bash -c "echo terraform apply -target=hcloud_server.web"`,
      `ssh h "echo Never terraform apply -replace=hcloud_server.web"`,
      `echo "terraform apply -target=hcloud_server.web"`,
      `printf '%s\\n' "terraform apply -replace=hcloud_server.web"`,
      `bash -c "terraform apply -target=terraform_data.x" # a quoted command line naming another resource`,
    ]) {
      expect(creating(run), run).toBe(false);
    }
  });

  test("P2c the prose fixture is not vacuous: the same sentence at command position IS host-creating", () => {
    expect(creating("terraform apply -replace=hcloud_server.web -- that host")).toBe(true);
  });

  test("P2d DOCUMENTED out-of-scope shapes (undecidable statically; listed in the header): flags held in a variable/array", () => {
    // These are NOT host-creating to the predicate. The row exists so a future widening is a deliberate edit of this row and
    // the header, not an accident. The non-literal arm (c) still catches `-target=$VAR`; it cannot see a whole flag in a variable.
    for (const run of [
      'F="-target=hcloud_server.web"\nterraform apply $F',
      'FLAGS=(-replace=hcloud_server.web)\nterraform apply "${FLAGS[@]}"',
      'ADDR=hcloud_server.web\nterraform apply -target=$ADDR', // caught by (c), the control: out of scope is only the whole-flag form
    ]) {
      const hit = creating(run);
      if (run.includes("-target=$ADDR")) expect(hit, run).toBe(true);
      else expect(hit, run).toBe(false);
    }
  });

  test("P3 ordering: a flag-prefixed Terraform command before the preflight is seen (TF_CMD_RE accepts -chdir)", () => {
    const mk = (first: string): Doc => ({
      jobs: {
        j: {
          steps: [
            { run: first },
            { run: PREFLIGHT_RUN, "timeout-minutes": 2, env: { DOPPLER_TOKEN: "x" } },
            { run: 'terraform apply -target="hcloud_server.web[\\"web-2\\"]" tfplan' },
          ],
        },
      },
    });
    for (const cmd of [
      "terraform -chdir=apps/web-platform/infra init",
      "terraform -chdir=x plan -out=tfplan",
      "terraform init",
      "terraform \\\n  init", // the subcommand on the line after a continuation
      "terraform \\\n  -chdir=x \\\n  init",
      "/usr/local/bin/terraform init",
      "./terraform plan",
      "tofu init",
      "/opt/bin/tofu -chdir=x init",
    ]) {
      expect(censusViolations(mk(cmd), realReadAction).join("\n"), cmd).toContain("AFTER the first Terraform command");
    }
    expect(censusViolations(mk("echo no terraform here"), realReadAction)).toEqual([]);
  });

  test("P4 a later Terraform step under if: always()/failure()/cancelled() would run after a red preflight -> RED; benign later steps are GREEN", () => {
    const mk = (extra: any): Doc => ({
      jobs: {
        j: {
          steps: [
            { run: PREFLIGHT_RUN, "timeout-minutes": 2, env: { DOPPLER_TOKEN: "x" } },
            { run: 'terraform apply -target="hcloud_server.web[\\"web-2\\"]" tfplan' },
            extra,
          ],
        },
      },
    });
    for (const cond of [
      "always()",
      "failure()",
      "cancelled() || success()",
      "${{ always() }}",
      "ALWAYS()", // status functions are case-insensitive in GitHub expressions
      "Failure()",
      "!success()",
      "${{ ! success() }}",
      "steps.pre.outcome == 'failure'",
      "steps.pre.conclusion != 'success'",
      "STEPS.PRE.OUTCOME == 'FAILURE'",
    ]) {
      expect(censusViolations(mk({ if: cond, run: "terraform -chdir=x apply tfplan" }), realReadAction).join("\n"), cond).toContain("after the preflight under 'if:");
    }
    expect(censusViolations(mk({ if: "always()", run: "echo cleanup" }), realReadAction)).toEqual([]);
    expect(censusViolations(mk({ if: "success()", run: "terraform output" }), realReadAction)).toEqual([]);
    for (const benign of ["success()", "steps.pre.outcome == 'success'", "github.event_name == 'workflow_dispatch'", "env.PLAN_ONLY != 'true'"]) {
      expect(censusViolations(mk({ if: benign, run: "terraform -chdir=x apply tfplan" }), realReadAction), benign).toEqual([]);
    }
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

  test("the declared test count equals the shipped floor exactly (add or delete a row, move TEST_FLOOR in the same edit)", () => {
    // Loop-generated rows (for ... test(`...`)) count once in the source and N times at run time; the floor is
    // hand-ratcheted to the SOURCE count, deliberately exact: deleting a row costs one deliberate edit here.
    const declared = selfText.match(/^\s*test\(/gm)?.length ?? 0;
    expect(declared).toBe(TEST_FLOOR);
  });
});

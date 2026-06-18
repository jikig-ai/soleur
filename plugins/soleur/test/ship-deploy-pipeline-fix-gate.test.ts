// Deploy-pipeline-fix drift gate — verifies plugins/soleur/skills/ship/SKILL.md
// Phase 5.5 contains the canonical gate definition (#2881) and the file+systemd
// post-apply verification contract (#3034). The gate is documentation that an
// LLM agent reads at /ship time; the only safety net against drift between the
// gate's bash array, its regex, and apps/web-platform/infra/server.tf's
// triggers_replace block is this test file.
//
// Test harness: bun:test (matches sibling tests in plugins/soleur/test/*.ts).

import { describe, test, expect, beforeAll } from "bun:test";
import { resolve } from "path";
import { readFileSync, existsSync } from "fs";

// plugins/soleur/test/ → ../../.. is the worktree (repo) root
const REPO_ROOT = resolve(import.meta.dir, "../../..");
const SHIP_SKILL = resolve(REPO_ROOT, "plugins/soleur/skills/ship/SKILL.md");
const POSTMERGE_RUNBOOK = resolve(
  REPO_ROOT,
  "plugins/soleur/skills/postmerge/references/deploy-status-debugging.md",
);
const SERVER_TF = resolve(REPO_ROOT, "apps/web-platform/infra/server.tf");
const APPLY_DPF_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-deploy-pipeline-fix.yml",
);
const APPLY_WEBPLAT_WORKFLOW = resolve(
  REPO_ROOT,
  ".github/workflows/apply-web-platform-infra.yml",
);

const GATE_HEADING = "### Deploy Pipeline Fix Drift Gate";
const NEXT_HEADING = "### Retroactive Gate Application";

// The 5 trigger files MUST match apps/web-platform/infra/server.tf
// `terraform_data.deploy_pipeline_fix.triggers_replace.sha256(join(",",...))`.
// If a future infra refactor changes the basenames, this fixture, the gate's
// bash array, and the gate's regex must update together. The
// "server.tf is in sync with TRIGGER_FILES" describe block below auto-detects
// drift between server.tf and this fixture (#3068).
const TRIGGER_FILES = [
  "apps/web-platform/infra/ci-deploy.sh",
  "apps/web-platform/infra/ci-deploy-wrapper.sh",
  "apps/web-platform/infra/webhook.service",
  "apps/web-platform/infra/cat-deploy-state.sh",
  "apps/web-platform/infra/canary-bundle-claim-check.sh",
  "apps/web-platform/infra/hooks.json.tmpl",
  "apps/web-platform/infra/deploy-inngest-bootstrap.sudoers",
  "apps/web-platform/infra/infra-config-apply.sh",
  "apps/web-platform/infra/infra-config-install.sh",
  "apps/web-platform/infra/push-infra-config.sh",
  "apps/web-platform/infra/cat-infra-config-state.sh",
  "apps/web-platform/infra/inngest-enumerate-reminders.sh",
  "apps/web-platform/infra/inngest-rearm-reminders.sh",
  "apps/web-platform/infra/inngest-wiped-volume-verify.sh",
  "apps/web-platform/infra/cat-inngest-verify-state.sh",
  "apps/web-platform/infra/inngest-inventory.sh",
];

function buildTriggerRegex(files: string[]): RegExp {
  const basenames = files.map((p) => {
    const base = p.replace(/^apps\/web-platform\/infra\//, "");
    return base.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
  });
  return new RegExp(`^apps/web-platform/infra/(${basenames.join("|")})$`);
}

let SHIP_TEXT: string;
let GATE_SECTION: string;

function getGateSection(text: string): string {
  const start = text.indexOf(GATE_HEADING);
  const end = text.indexOf(NEXT_HEADING, start);
  if (start === -1 || end === -1 || end <= start) {
    throw new Error(
      `Gate section boundary not found: start=${start} end=${end}. ` +
        `The "${GATE_HEADING}" or "${NEXT_HEADING}" heading was renamed/removed.`,
    );
  }
  return text.slice(start, end);
}

beforeAll(() => {
  if (!existsSync(SHIP_SKILL)) {
    throw new Error(`ship SKILL.md not found at ${SHIP_SKILL}`);
  }
  SHIP_TEXT = readFileSync(SHIP_SKILL, "utf8");
  GATE_SECTION = getGateSection(SHIP_TEXT);
});

describe("ship/SKILL.md Deploy Pipeline Fix Drift Gate — structure", () => {
  test("Phase 5.5 contains the gate subsection heading", () => {
    expect(SHIP_TEXT).toMatch(/^### Deploy Pipeline Fix Drift Gate/m);
  });

  test("gate cites the per-command authorization rule", () => {
    expect(GATE_SECTION).toContain("hr-menu-option-ack-not-prod-write-auth");
  });

  test("gate references both issues (#2881 and #3034)", () => {
    expect(GATE_SECTION).toContain("#2881");
    expect(GATE_SECTION).toContain("#3034");
  });
});

describe("ship/SKILL.md gate — verbatim canonical command + verification", () => {
  test("emits the canonical terraform apply command verbatim", () => {
    expect(GATE_SECTION).toContain(
      "terraform apply -target=terraform_data.deploy_pipeline_fix -input=true",
    );
    expect(GATE_SECTION).toContain("doppler run -p soleur -c prd_terraform");
  });

  test("emits the file+systemd verification contract", () => {
    expect(GATE_SECTION).toMatch(/sha256sum\s+\/usr\/local\/bin\/ci-deploy\.sh/);
    expect(GATE_SECTION).toMatch(/systemctl is-active webhook/);
    expect(GATE_SECTION).toContain("terraform output -raw server_ip");
  });

  test("has a headless-mode fallback chain (gh pr comment → stderr → step summary)", () => {
    expect(GATE_SECTION).toMatch(/gh pr comment/);
    expect(GATE_SECTION).toMatch(/GITHUB_STEP_SUMMARY/);
    expect(GATE_SECTION).toMatch(/>&2/);
  });
});

describe("ship/SKILL.md gate — bash-array + regex match canonical fixture", () => {
  // P2-1 from code-quality review: a typo in the gate's array or regex must
  // fail the suite, not pass silently. Parse the gate's actual bash literal
  // from SKILL.md and compare to TRIGGER_FILES + buildTriggerRegex.

  test("gate's DEPLOY_PIPELINE_FIX_TRIGGERS bash array matches TRIGGER_FILES token-for-token", () => {
    const arrayMatch = GATE_SECTION.match(
      /DEPLOY_PIPELINE_FIX_TRIGGERS=\(\s*\n([\s\S]*?)\n\s*\)/,
    );
    expect(arrayMatch).not.toBeNull();
    const lines = arrayMatch![1]
      .split("\n")
      .map((l) => l.trim())
      .filter((l) => l.length > 0);
    const parsed = lines.map((l) => {
      const m = l.match(/^"([^"]+)"$/);
      if (!m) {
        throw new Error(`bash array entry not double-quoted: ${l}`);
      }
      return m[1];
    });
    expect(parsed).toEqual(TRIGGER_FILES);
  });

  test("gate's DPF_REGEX literal equals buildTriggerRegex(TRIGGER_FILES).source", () => {
    const regexMatch = GATE_SECTION.match(/DPF_REGEX='([^']+)'/);
    expect(regexMatch).not.toBeNull();
    // Bash regex literals don't escape forward slashes; JS's RegExp.source does.
    // Normalize the JS source for the comparison.
    const expected = buildTriggerRegex(TRIGGER_FILES).source.replace(/\\\//g, "/");
    expect(regexMatch![1]).toBe(expected);
  });
});

describe("Trigger regex behavior (derived from canonical array)", () => {
  const regex = buildTriggerRegex(TRIGGER_FILES);

  test.each(TRIGGER_FILES)("matches trigger file: %s", (path) => {
    expect(regex.test(path)).toBe(true);
  });

  test.each([
    "apps/web-platform/app/page.tsx",
    "plugins/soleur/skills/ship/SKILL.md",
    "apps/web-platform/infra/cloud-init.yml",
    "apps/web-platform/infra/main.tf",
    "knowledge-base/project/plans/something.md",
  ])("does NOT match unrelated path: %s", (path) => {
    expect(regex.test(path)).toBe(false);
  });

  test.each([
    "apps/web-platform/infra/ci-deploy.sh.bak",
    "apps/web-platform/infra/ci-deploy.sh.j2",
    "apps/web-platform/infra/webhook.service.disabled",
    "apps/web-platform/infra/cat-deploy-state.sh~",
    "apps/web-platform/infra/hooks.json.tmpl.old",
  ])("does NOT match suffixed variant: %s", (path) => {
    expect(regex.test(path)).toBe(false);
  });

  test("rejects paths with leading/trailing whitespace (anchored end-of-line)", () => {
    expect(regex.test(" apps/web-platform/infra/ci-deploy.sh")).toBe(false);
    expect(regex.test("apps/web-platform/infra/ci-deploy.sh ")).toBe(false);
  });

  test("rejects paths with carriage-return (defensive against \\r\\n diff output)", () => {
    expect(regex.test("apps/web-platform/infra/ci-deploy.sh\r")).toBe(false);
  });
});

describe("Trigger array and server.tf are in sync (path-glob verification)", () => {
  let serverTf: string;

  beforeAll(() => {
    expect(existsSync(SERVER_TF)).toBe(true);
    serverTf = readFileSync(SERVER_TF, "utf8");
  });

  test.each(TRIGGER_FILES)("trigger file exists at documented path: %s", (path) => {
    expect(existsSync(resolve(REPO_ROOT, path))).toBe(true);
  });

  test.each(TRIGGER_FILES)(
    "server.tf references basename via file()/templatefile(): %s",
    (path) => {
      const basename = path.split("/").pop()!;
      // Direct triggers are referenced via file("${path.module}/<basename>")
      // inside the triggers_replace block. hooks.json.tmpl is rendered by
      // templatefile("${path.module}/hooks.json.tmpl", ...) in a locals block
      // and folded into triggers_replace via local.hooks_json. Either form proves
      // terraform tracks the file's contents.
      const escaped = basename.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
      const referenced = new RegExp(
        `(file|templatefile)\\(\\s*"\\$\\{path\\.module\\}/${escaped}"`,
      ).test(serverTf);
      expect(referenced).toBe(true);
    },
  );

  // Self-healing direction (#3068): if server.tf grows a new file in
  // triggers_replace, this test fails until TRIGGER_FILES (and therefore the
  // gate's array + regex via the "matches token-for-token" tests above) is
  // updated. Closes the gap that caused PR #3042 to slip past the gate and
  // file drift issue #3061.
  test("every basename hashed by triggers_replace appears in TRIGGER_FILES", () => {
    // Locate the deploy_pipeline_fix resource block (server.tf has several
    // `triggers_replace = sha256(join(",", [ ... ]))` blocks; we want only the
    // one under `terraform_data "deploy_pipeline_fix"`).
    const resourceStart = serverTf.indexOf(
      'resource "terraform_data" "deploy_pipeline_fix"',
    );
    expect(resourceStart).toBeGreaterThanOrEqual(0);
    // Bound by the next top-level HCL block — `resource`, `data`, `module`,
    // `output`, `locals`, `variable`, `provider`, `terraform`. Bare `\nresource `
    // would absorb downstream non-resource blocks if `deploy_pipeline_fix`
    // ever became the last `resource` in the file (P2 review finding).
    const TOP_LEVEL_BLOCK_RE =
      /\n(resource|data|module|output|locals|variable|provider|terraform)\b/;
    const tail = serverTf.slice(resourceStart + 1);
    const tailMatch = tail.match(TOP_LEVEL_BLOCK_RE);
    const resourceBlock =
      tailMatch && tailMatch.index !== undefined
        ? serverTf.slice(resourceStart, resourceStart + 1 + tailMatch.index)
        : serverTf.slice(resourceStart);

    const blockMatch = resourceBlock.match(
      /triggers_replace\s*=\s*sha256\(join\(\s*",\s*"\s*,\s*\[([\s\S]*?)\]\s*\)\s*\)/,
    );
    expect(blockMatch).not.toBeNull();
    const inner = blockMatch![1];

    // Direct file() references.
    const fileBasenames = Array.from(
      inner.matchAll(/file\(\s*"\$\{path\.module\}\/([^"]+)"\s*\)/g),
    ).map((m) => m[1]);

    // local.<name> references → resolved against the file-level `locals { ... }`
    // block. Scoping the lookup (rather than searching the whole file) keeps the
    // resolver from accidentally matching same-named identifiers in unrelated
    // contexts (P2 review finding).
    // `^locals` (file start) or `\nlocals` (subsequent line). Closing brace on
    // its own line at column 0 (`\n}`) bounds the body — the templatefile()'s
    // nested `})` is column-2 indented and won't match.
    const localsBlockMatch = serverTf.match(/(?:^|\n)locals\s*\{([\s\S]*?)\n\}/);
    if (!localsBlockMatch) {
      throw new Error(
        "server.tf has no top-level `locals { ... }` block but " +
          "triggers_replace references `local.*` — refactor required.",
      );
    }
    const localsBody = localsBlockMatch[1];

    const localNames = Array.from(inner.matchAll(/\blocal\.([A-Za-z0-9_]+)\b/g)).map(
      (m) => m[1],
    );
    const templatefileBasenames = localNames.map((name) => {
      const escaped = name.replace(/[.+*?^$(){}|[\]\\]/g, "\\$&");
      const localMatch = localsBody.match(
        new RegExp(
          `\\b${escaped}\\s*=\\s*templatefile\\(\\s*"\\$\\{path\\.module\\}/([^"]+)"`,
        ),
      );
      if (!localMatch) {
        throw new Error(
          `triggers_replace references local.${name} but no matching ` +
            `\`${name} = templatefile("\${path.module}/...")\` was found in the ` +
            `top-level locals { ... } block. Either add the local definition, or ` +
            `replace the local with a direct file()/templatefile() reference.`,
        );
      }
      return localMatch[1];
    });

    // Order-insensitive comparison: regex alternation is commutative, so the
    // physical order in server.tf vs. TRIGGER_FILES is irrelevant for gate
    // semantics. The token-for-token bash-array test above (line ~125) is
    // where editorial ordering between SKILL.md and TRIGGER_FILES is enforced.
    const triggerBasenames = [...fileBasenames, ...templatefileBasenames].sort();
    const fixtureBasenames = TRIGGER_FILES.map((p) => p.split("/").pop()!).sort();

    expect(triggerBasenames).toEqual(fixtureBasenames);
  });
});

describe("postmerge runbook updates (#3034)", () => {
  let runbook: string;

  beforeAll(() => {
    if (!existsSync(POSTMERGE_RUNBOOK)) {
      throw new Error(`postmerge runbook not found at ${POSTMERGE_RUNBOOK}`);
    }
    runbook = readFileSync(POSTMERGE_RUNBOOK, "utf8");
  });

  test("contains a 'When NOT to use this probe' subsection", () => {
    expect(runbook).toMatch(/^## When NOT to use this probe/m);
  });

  test("references the post-apply file+systemd contract", () => {
    expect(runbook).toMatch(/sha256sum/);
    expect(runbook).toMatch(/systemctl is-active webhook/);
  });

  test("links to the 2026-04-29 verification-contract learning", () => {
    expect(runbook).toContain(
      "2026-04-29-deploy-pipeline-fix-postapply-verification-cf-access",
    );
  });
});

// #5505: the FIFTH coupled surface. The on.push.paths filter in
// apply-deploy-pipeline-fix.yml is what actually decides whether the dedicated
// auto-apply fires on merge. It must equal the hashed trigger set (TRIGGER_FILES)
// PLUS server.tf itself (a change to the hash *definition* must also re-apply).
// This surface was previously unguarded: #5492 added the 4 inngest scripts to
// server.tf + the ship array/regex + TRIGGER_FILES, the gate went green, but the
// workflow paths filter was never updated — so the inngest-only #5504 merge did
// NOT auto-apply and the fix had to be deployed by a manual workflow_dispatch.
describe("apply-deploy-pipeline-fix.yml on.push.paths in sync with TRIGGER_FILES (#5505)", () => {
  let paths: string[];

  beforeAll(() => {
    expect(existsSync(APPLY_DPF_WORKFLOW)).toBe(true);
    const yml = readFileSync(APPLY_DPF_WORKFLOW, "utf8");
    // Bound to the `on:` section (everything before the top-level `jobs:` key),
    // then collect the quoted list items under the single `paths:` key there.
    const jobsIdx = yml.indexOf("\njobs:");
    const onSection = jobsIdx >= 0 ? yml.slice(0, jobsIdx) : yml;
    const pathsIdx = onSection.indexOf("paths:");
    expect(pathsIdx).toBeGreaterThanOrEqual(0);
    const pathsBlock = onSection.slice(pathsIdx);
    // Anchor to the apps/web-platform/infra/ prefix so a future workflow_dispatch
    // `type: choice` input with quoted `options:` list items (which would also fall
    // inside this slice of the `on:` section) cannot leak in as a phantom path
    // (P3, #5505 review). Comment lines `# - "x"` are already excluded by `^\s+-`.
    paths = [...pathsBlock.matchAll(/^\s+-\s+"(apps\/web-platform\/infra\/[^"]+)"/gm)].map(
      (m) => m[1],
    );
    expect(paths.length).toBeGreaterThan(0);
  });

  test("paths filter equals TRIGGER_FILES ∪ {server.tf} (set equality)", () => {
    const expected = new Set([
      ...TRIGGER_FILES,
      "apps/web-platform/infra/server.tf",
    ]);
    expect(new Set(paths)).toEqual(expected);
  });

  test("every TRIGGER_FILES entry is in the workflow paths filter (auto-apply reachability)", () => {
    const inPaths = new Set(paths);
    const missing = TRIGGER_FILES.filter((f) => !inPaths.has(f));
    expect(missing).toEqual([]);
  });
});

// #5515: deploy_pipeline_fix (the HTTPS webhook push of the managed deploy-config
// files) must ORDER AFTER infra_config_handler_bootstrap (the root-SSH bridge that
// delivers the webhook handler `infra-config-apply.sh` + the rendered hooks.json to
// the host). Without the depends_on edge, a merge that BOTH replaces the handler
// (new FILE_MAP entry + new hooks.json env key) AND fires the push runs the push
// against the host's STALE handler/hooks.json: the new file's env var is unset, so
// the handler's per-file `missing_env` arm (infra-config-apply.sh:105-112, the #4804
// self-heal) drops it and the file lands ONE APPLY LATE (op=inventory 500s until the
// next unrelated apply). `-target` does NOT impose ordering — only the graph edge
// does — even though apply-deploy-pipeline-fix.yml lists BOTH as explicit -target=s.
// Do NOT "simplify" the edge away: the co-targeting (Test 2) is what makes it
// load-bearing, and the edge is what makes the ordering deterministic.
describe("deploy_pipeline_fix orders after the handler bridge (#5515)", () => {
  let serverTf: string;

  beforeAll(() => {
    expect(existsSync(SERVER_TF)).toBe(true);
    serverTf = readFileSync(SERVER_TF, "utf8");
  });

  // Test 1 — the depends_on edge. Bound the deploy_pipeline_fix resource block
  // with the same top-level-block regex the triggers_replace test uses, then run a
  // FRESH depends_on-list match against the bounded slice (NOT the triggers_replace
  // join extractor, which matches sha256(join(...))).
  test("Test 1 — deploy_pipeline_fix depends_on lists BOTH apparmor_bwrap_profile AND infra_config_handler_bootstrap", () => {
    const resourceStart = serverTf.indexOf(
      'resource "terraform_data" "deploy_pipeline_fix"',
    );
    expect(resourceStart).toBeGreaterThanOrEqual(0);
    const TOP_LEVEL_BLOCK_RE =
      /\n(resource|data|module|output|locals|variable|provider|terraform)\b/;
    const tail = serverTf.slice(resourceStart + 1);
    const tailMatch = tail.match(TOP_LEVEL_BLOCK_RE);
    const resourceBlock =
      tailMatch && tailMatch.index !== undefined
        ? serverTf.slice(resourceStart, resourceStart + 1 + tailMatch.index)
        : serverTf.slice(resourceStart);

    const dependsMatch = resourceBlock.match(/depends_on\s*=\s*\[([\s\S]*?)\]/);
    expect(dependsMatch).not.toBeNull();
    const dependsList = dependsMatch![1];
    expect(dependsList).toContain("terraform_data.apparmor_bwrap_profile");
    expect(dependsList).toContain(
      "terraform_data.infra_config_handler_bootstrap",
    );
  });

  // Test 2 — the co-targeting invariant (the load-bearing one, SpecFlow P0-A). The
  // depends_on edge only orders the apply if BOTH resources are co-`-target`ed in
  // apply-deploy-pipeline-fix.yml's single `terraform apply` — if either target were
  // dropped the edge would be inert and Test 1 would still pass green.
  test("Test 2 — apply-deploy-pipeline-fix.yml terraform apply co-targets BOTH resources", () => {
    expect(existsSync(APPLY_DPF_WORKFLOW)).toBe(true);
    const yml = readFileSync(APPLY_DPF_WORKFLOW, "utf8");
    // Bound to the `terraform apply` invocation (the durable apply, not the plan
    // step) so a future plan-only -target= change cannot satisfy this vacuously.
    const applyIdx = yml.indexOf("terraform apply -target=");
    expect(applyIdx).toBeGreaterThanOrEqual(0);
    // The multi-line `\`-continued apply command ends at the first non-continued
    // line; bound generously to the next ~600 chars (the command spans a handful
    // of -target= lines plus trailing flags).
    const applyBlock = yml.slice(applyIdx, applyIdx + 800);
    expect(applyBlock).toContain(
      "-target=terraform_data.deploy_pipeline_fix",
    );
    expect(applyBlock).toContain(
      "-target=terraform_data.infra_config_handler_bootstrap",
    );
  });

  // Test 3 — cross-workflow blast-radius guard (deepen P2-2). The OTHER infra
  // workflow shares the concurrency group but must target NEITHER fix resource, so
  // the new edge is never traversed by it (it SSH-targets only apparmor_bwrap_profile
  // among shared resources). Pins that a future edit cannot silently widen its blast.
  test("Test 3 — apply-web-platform-infra.yml targets NEITHER fix resource", () => {
    expect(existsSync(APPLY_WEBPLAT_WORKFLOW)).toBe(true);
    const yml = readFileSync(APPLY_WEBPLAT_WORKFLOW, "utf8");
    expect(yml).not.toContain("-target=terraform_data.deploy_pipeline_fix");
    expect(yml).not.toContain(
      "-target=terraform_data.infra_config_handler_bootstrap",
    );
  });
});

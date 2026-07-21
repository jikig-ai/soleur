import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyDiscoverabilityResult,
  extractObservabilityBlock,
  matchExpected,
  parseCommand,
  parseExpected,
  rejectReason,
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

// The production Form-A parser — the runtime of record. The parity harness
// (P1/P2/P3) executes THIS file, not a regex-scrape of SKILL.md prose.
const AWK_PATH = join(
  import.meta.dir,
  "..",
  "skills",
  "preflight",
  "scripts",
  "parse-form-a.awk",
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

  test("8-state decision matrix exists with exactly one PASS terminal", () => {
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    const rows = check10Block![0].match(/^\|\s*\d+\s*\|/gm) ?? [];
    expect(rows.length).toBeGreaterThanOrEqual(8);
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

describe("classifyDiscoverabilityResult — 8 decision states", () => {
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

// ---------------------------------------------------------------------------
// #6772 — YAML folded-scalar parsing for `discoverability_test.command`.
//
// Every fixture below is registered in FORM_A_FIXTURES so the parity harness
// (P1) can execute BOTH surfaces over it. Each row names the surface it pins:
//   "both" — the assertion holds identically on awk and TS
//   "awk"  — awk-side detail (e.g. the fold join operator)
//   "ts"   — TS-side detail (e.g. the widened block-header regex)
// ---------------------------------------------------------------------------

const obs = (...lines: string[]) => lines.join("\n");

type Surface = "awk" | "ts" | "both";
type Fixture = { id: string; surface: Surface; block: string };

const FORM_A_FIXTURES: Fixture[] = [];
const reg = (id: string, surface: Surface, block: string): string => {
  FORM_A_FIXTURES.push({ id, surface, block });
  return block;
};

/**
 * Assert a `surface: both` row on BOTH surfaces.
 *
 * Asserting only parseCommand() would leave every awk-side mutation invisible
 * to the named test — it would redden P1 alone, which reports as a parity
 * failure rather than as the behaviour the row exists to pin. Verified via the
 * sandbox mutation protocol: with a TS-only assertion, the I1/N3/B2/E1/F5
 * mutations all left their named test green.
 */
function expectBoth(block: string, expected: string): void {
  expect(parseCommand(block)).toBe(expected);
  expect(runAwk(block)).toBe(expected);
}

/** Run the production awk over an Observability block; strip ONE trailing \n. */
function runAwk(block: string): string {
  const proc = Bun.spawnSync({
    cmd: ["awk", "-f", AWK_PATH],
    stdin: new TextEncoder().encode(block),
    stdout: "pipe",
    stderr: "pipe",
  });
  const err = new TextDecoder().decode(proc.stderr);
  if (proc.exitCode !== 0) {
    throw new Error(`awk rc=${proc.exitCode}: ${err}`);
  }
  return new TextDecoder().decode(proc.stdout).replace(/\n$/, "");
}

describe("#6772 F1-F5 — folded scalars parse (permissive)", () => {
  // F1-F3 [both]: all three indicators × with/without a trailing comment.
  // The comment column is load-bearing: anchoring the header regex to a bare
  // `$` makes `command: >- # note` fall through to the inline rule and return
  // the literal indicator — i.e. it reproduces #6772 exactly.
  const INDICATORS = [">", ">-", ">+"] as const;
  const TAILS = ["", " # trailing comment"] as const;
  const EXPECTED_F =
    'curl -fsS -o /dev/null -w "%{http_code}" --max-time 10 https://app.soleur.ai/api/health';

  for (const ind of INDICATORS) {
    for (const tail of TAILS) {
      const id = `F1-3[${ind}${tail ? "+comment" : ""}]`;
      const block = reg(
        id,
        "both",
        obs(
          "discoverability_test:",
          `  command: ${ind}${tail}`,
          '    curl -fsS -o /dev/null -w "%{http_code}" --max-time 10',
          "    https://app.soleur.ai/api/health",
          '  expected_output: "200"',
        ),
      );
      test(`${id} parses to the space-joined line, not the literal indicator`, () => {
        expectBoth(block, EXPECTED_F);
        expect(parseCommand(block)).not.toBe(`${ind}`);
      });
    }
  }

  // F4 [awk]: the separator is PREPENDED, so there is no trailing space.
  // Reddening mutation: change the join to append (`printf "%s "`).
  const f4 = reg(
    "F4",
    "awk",
    obs(
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("F4 single continuation has no leading or trailing space", () => {
    const got = parseCommand(f4);
    expectBoth(f4, "curl -fsS https://app.soleur.ai/health");
    expect(got).not.toMatch(/^\s/);
    expect(got).not.toMatch(/\s$/);
  });

  // F5 [both]: fold + trailing backslash. Folding joins with a space, so `\`
  // becomes an ESCAPED SPACE rather than a line continuation. This is
  // spec-correct YAML but differs from what a reviewer reads — documented in
  // the .awk header, pinned here so a future "repair" reddens.
  const f5 = reg(
    "F5",
    "both",
    obs(
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS \\",
      "    https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("F5 fold + trailing backslash yields the documented escaped-space form", () => {
    expectBoth(f5, "curl -fsS \\ https://app.soleur.ai/health");
  });
});

describe("#6772 N1-N6/S1 — folded scalars do NOT over-consume (restrictive)", () => {
  // N1 [both]: sibling key at the SAME indent as `command:` ends the scalar.
  const n1 = reg(
    "N1",
    "both",
    obs(
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("N1 stops at a sibling key; parseExpected still reads it", () => {
    expect(parseCommand(n1)).not.toMatch(/expected_output/);
    expect(parseExpected(n1)).toBe("200");
  });

  // N1b [both]: a key at LESS indent than `command:` also ends the scalar.
  // Pins the `<` half of `indent <= key`; asserting only a sibling would leave
  // a mutation to `==` undetected.
  const n1b = reg(
    "N1b",
    "both",
    obs(
      "discoverability_test:",
      "    command: >-",
      "      curl -fsS https://app.soleur.ai/health",
      '  parent_key: "must not be consumed"',
    ),
  );
  test("N1b stops at a LESS-indented parent key (the `<` half of `<=`)", () => {
    expectBoth(n1b, "curl -fsS https://app.soleur.ai/health");
    expect(parseCommand(n1b)).not.toMatch(/parent_key/);
  });

  // N5 [both]: a DEEPER-indented `key: value` inside the command is content,
  // not a terminator. Modelled on the real corpus plan
  // 2026-07-03-fix-seccomp-loaded-sha-deploy-status-discriminators-plan.md,
  // whose folded command ends in a jq object filter. Any key-regex terminator
  // truncates this mid-expression.
  const n5 = reg(
    "N5",
    "both",
    obs(
      "discoverability_test:",
      "  command: >",
      "    curl -fsS --max-time 10 https://deploy.soleur.ai/hooks/deploy-status",
      "      '{matches: .seccomp_profile_loaded_matches_host,",
      "        host_present: .seccomp_profile_host_present}'",
      '  expected_output: "true"',
    ),
  );
  test("N5 does not truncate on a deeper-indented `key: value` (jq object filter)", () => {
    const got = parseCommand(n5);
    expect(got).toMatch(/host_present/);
    expect(got).toMatch(/seccomp_profile_host_present\}'$/);
  });

  // S1 [both] — THE SECURITY DIFFERENTIAL (security review F4).
  // A less-indented, non-key line reads to a PR reviewer as outside the
  // command. Before the fix the continuation rule matched ANY indented line,
  // so it was consumed and executed. `indent > key` closes it.
  const s1 = reg(
    "S1",
    "both",
    obs(
      "discoverability_test:",
      "    command: >-",
      "      curl -fsS https://app.soleur.ai/health",
      "  touch /tmp/BLOCK_LESS_INDENT_PWN",
      '    expected_output: "200"',
    ),
  );
  test("S1 does NOT consume a less-indented non-key line (reviewer/executor differential)", () => {
    const got = parseCommand(s1);
    expectBoth(s1, "curl -fsS https://app.soleur.ai/health");
    expect(got).not.toMatch(/touch/);
  });

  // N3 [both]: dedent to column 0, then INDENTED content resumes. The resumed
  // block is what makes this fixture live — a column-0-prose-only fixture is
  // byte-identical with and without the terminator (column-0 lines match no
  // continuation rule), so it pins nothing.
  const n3 = reg(
    "N3",
    "both",
    obs(
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS https://app.soleur.ai/health",
      "Column-zero prose ends the scalar.",
      "  resumed_indented_content: must not be appended",
    ),
  );
  test("N3 stops at a column-0 dedent even when indented content resumes after", () => {
    expectBoth(n3, "curl -fsS https://app.soleur.ai/health");
    expect(parseCommand(n3)).not.toMatch(/resumed_indented_content/);
  });

  // N6 [both]: a blank line inside a scalar carries no indentation, so
  // indent("") === 0 <= key. The blank-line skip MUST sit above the
  // terminator or every scalar ends at its first blank line.
  const n6fold = reg(
    "N6-fold",
    "both",
    obs(
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS",
      "",
      "    https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  const n6block = reg(
    "N6-block",
    "both",
    obs(
      "discoverability_test:",
      "  command: |",
      "    curl -fsS",
      "",
      "    https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("N6 blank line inside a fold is skipped, scalar continues", () => {
    expectBoth(n6fold, "curl -fsS https://app.soleur.ai/health");
  });
  test("N6 blank line inside a block is skipped, scalar continues", () => {
    expectBoth(n6block, "curl -fsS\nhttps://app.soleur.ai/health");
  });
});

describe("#6772 I1/B1-B3/E1 — existing forms stay green (non-shadowing)", () => {
  // I1 [both]: the inline path survives the fold rule being placed ahead of it.
  // NOTE: I1 pins only that inline still works — it does NOT pin rule ORDER.
  // Moving the inline rule ahead of the fold rule leaves I1 green and reddens
  // F1-F4. Do not mistake this for ordering coverage.
  const i1 = reg(
    "I1",
    "both",
    obs(
      "discoverability_test:",
      "  command: curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("I1 inline command is unchanged", () => {
    expectBoth(i1, "curl -fsS https://app.soleur.ai/health");
  });

  // B1 [both] — DEFECT 2 PIN. The block branch had no terminator, so the
  // indented sibling `expected_output:` was swallowed and became a second
  // command under `bash -c`, corrupting the rc-based decision states.
  const b1 = reg(
    "B1",
    "both",
    obs(
      "discoverability_test:",
      "  command: |",
      "    curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("B1 `command: |` no longer swallows the sibling expected_output key", () => {
    expectBoth(b1, "curl -fsS https://app.soleur.ai/health");
    expect(parseCommand(b1)).not.toMatch(/expected_output/);
  });

  // B2 [both]: block joins with \n (fold joins with a space); both dedent.
  const b2 = reg(
    "B2",
    "both",
    obs(
      "discoverability_test:",
      "  command: |",
      "    curl -fsS https://app.soleur.ai/health",
      "    curl -fsS https://app.soleur.ai/api/inngest",
      '  expected_output: "200"',
    ),
  );
  test("B2 block joins with newline, not a space, and dedents", () => {
    expectBoth(
      b2,
      "curl -fsS https://app.soleur.ai/health\ncurl -fsS https://app.soleur.ai/api/inngest",
    );
  });

  // B3 [ts]: `command: |-` — zero corpus usage, but bash prefix-matched into
  // block mode while the TS anchored regex fell through to inline and returned
  // the literal `|-`. Continuation lines are what make this fixture live; a
  // header-only fixture is empty on both surfaces and passes trivially.
  const b3 = reg(
    "B3",
    "ts",
    obs(
      "discoverability_test:",
      "  command: |-",
      "    curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ),
  );
  test("B3 `command: |-` enters block mode on both surfaces", () => {
    expectBoth(b3, "curl -fsS https://app.soleur.ai/health");
    expect(parseCommand(b3)).not.toBe("|-");
  });

  // E1 [both]: a fold header with no continuations returns EMPTY (FAIL state 3
  // — "no command could be parsed"), never the literal indicator.
  const e1 = reg(
    "E1",
    "both",
    obs(
      "discoverability_test:",
      "  command: >-",
      '  expected_output: "200"',
    ),
  );
  test("E1 fold header with no continuations returns empty, not the indicator", () => {
    expectBoth(e1, "");
    expect(parseCommand(e1)).not.toBe(">-");
  });
});

describe("#6772 R1-R3 — reject-set coverage for the fail-open transition", () => {
  // R1 [both] (security review F1): newline was NOT in the reject set, so a
  // block scalar was an unguarded command-chaining primitive. Verified before
  // the fix: the second line executed.
  test("R1 block scalar carrying a second command line is rejected (newline is shell-active)", () => {
    const block = obs(
      "discoverability_test:",
      "  command: |",
      "    curl -fsS https://app.soleur.ai/health",
      "    touch /tmp/PWNED",
      '  expected_output: "200"',
    );
    const cmd = parseCommand(block);
    expect(cmd).toMatch(/\n/);
    expect(rejectReason(cmd) ?? "").toMatch(/shell-active|refusing/i);
  });

  // R2 [both] — CPO CONDITION C1. This PR is what makes these commands
  // executable: before the fix they parsed to the literal `>` and self-rejected
  // at the shell-active gate. Folding joins with a SPACE and introduces no
  // shell-active token, so the Step 10.5 reject does NOT cover them — the
  // credentialed-CLI reject at Step 10.4 is the load-bearing control.
  // `env -i` does not scrub the Doppler token: $HOME is preserved and the CLI
  // reads a live dp.ct.* credential from ~/.doppler/.doppler.yaml.
  test("R2 folded doppler prd_terraform command is rejected as a credentialed CLI", () => {
    const block = obs(
      "discoverability_test:",
      "  command: >",
      "    doppler run -p soleur -c prd_terraform --",
      "    scripts/betterstack-query.sh --since 90m --grep X",
      '  expected_output: "ok"',
    );
    const cmd = parseCommand(block);
    expect(cmd).toBe(
      "doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 90m --grep X",
    );
    // The credentialed-CLI reject is the ONLY thing stopping this command.
    // Proven without duplicating SUBST_REJECT_RE here (an inline copy would
    // silently stop tracking the real reject set): swap the credentialed verb
    // for an unauthenticated one and the command passes every other gate —
    // so nothing but the verb reject covers this class.
    expect(rejectReason(cmd.replace(/^doppler\b/, "curl"))).toBeNull();
    expect(rejectReason(cmd) ?? "").toMatch(/credentialed CLI/i);
  });

  test("R2b every credentialed CLI in the reject set is caught, including path-qualified", () => {
    for (const cmd of [
      "doppler secrets get FOO --plain",
      "gh api /repos/x/y",
      "/usr/local/bin/gh pr list",
      "aws s3 ls",
      "supabase db dump",
      "stripe events list",
    ]) {
      expect(rejectReason(cmd) ?? "").toMatch(/credentialed CLI/i);
    }
  });

  // R3 [both]: word boundaries keep legitimate probes runnable. A bare
  // substring match would false-reject anything containing `gh` (e.g. `high`,
  // `--flag=through`).
  test("R3 unauthenticated probes are NOT rejected by the credentialed-CLI branch", () => {
    for (const cmd of [
      "curl -fsS -o /dev/null --max-time 10 https://app.soleur.ai/api/health",
      "bun test plugins/soleur/test/preflight-discoverability-test.test.ts",
      "bash plugins/soleur/test/c4-model-freshness.test.sh",
      "curl -fsS https://app.soleur.ai/highlights",
    ]) {
      expect(rejectReason(cmd) ?? "").not.toMatch(/credentialed CLI/i);
    }
  });
});

describe("#6772 P1-P3 — awk/TS parity harness", () => {
  // P3: the harness is only meaningful over Form-A inputs. parseCommand() runs
  // Form A and then FALLS BACK to Form B; the awk has no Form B. A fixture
  // carrying a fence would compare two different programs and produce a
  // spurious parity failure (or mask a real one).
  test("P3 every parity fixture is Form-A-only (has `command:`, no fenced block)", () => {
    expect(FORM_A_FIXTURES.length).toBeGreaterThan(0);
    for (const { id, block } of FORM_A_FIXTURES) {
      expect(block, `${id} must carry a command: key`).toMatch(
        /^[ \t]*command:/m,
      );
      expect(block, `${id} must not carry a fenced block`).not.toMatch(
        /^[ \t]*```/m,
      );
    }
  });

  // P1: byte-exact, no normalization. Draft 2 normalized block indentation,
  // which would have blinded the harness to the exact drift the "bash wins"
  // contract exists to arbitrate. The indent model makes both surfaces dedent
  // identically, so no normalization is needed.
  test("P1 awk and TS agree byte-exactly on every Form-A fixture", () => {
    for (const { id, surface, block } of FORM_A_FIXTURES) {
      expect(runAwk(block), `${id} [surface=${surface}]`).toBe(
        parseCommand(block),
      );
    }
  });

  // P2: known divergences asserted AS KNOWN, so AC8 is not a tautology. A
  // change on either surface reddens here and forces an explicit decision.
  test("P2 known divergence — inline quote stripping (TS strips, awk does not)", () => {
    const block = obs(
      "discoverability_test:",
      '  command: "curl -fsS https://app.soleur.ai/health"',
      '  expected_output: "200"',
    );
    expect(runAwk(block)).toBe('"curl -fsS https://app.soleur.ai/health"');
    expect(parseCommand(block)).toBe("curl -fsS https://app.soleur.ai/health");
  });

  test("P2 known divergence — CRLF (TS splits on /\\r?\\n/, awk leaves the \\r)", () => {
    const block = [
      "discoverability_test:",
      "  command: >-",
      "    curl -fsS https://app.soleur.ai/health",
      '  expected_output: "200"',
    ].join("\r\n");
    expect(runAwk(block)).toBe("curl -fsS https://app.soleur.ai/health\r");
    expect(parseCommand(block)).toBe("curl -fsS https://app.soleur.ai/health");
  });

  // A CI image swapping mawk for gawk (or busybox awk) surfaces as a NAMED
  // failure here rather than a mystery diff in P1.
  test("awk interpreter is a known implementation (mawk or gawk)", () => {
    const proc = Bun.spawnSync({ cmd: ["awk", "--version"], stdout: "pipe", stderr: "pipe" });
    const banner =
      new TextDecoder().decode(proc.stdout) +
      new TextDecoder().decode(proc.stderr);
    expect(banner).toMatch(/mawk|GNU Awk|gawk/i);
  });
});

describe("#6772 AC1 — rule order in the production awk", () => {
  // Read lazily: before the fix this file does not exist, and a throw at
  // collection time would abort the entire suite and hide the RED evidence.
  // Strip comments first: a later comment mentioning the pattern must not flip
  // a first-match capture. AC1 is about the executable rules only.
  const ruleText = (): string =>
    readFileSync(AWK_PATH, { encoding: "utf8" })
      .split("\n")
      .filter((l) => !/^\s*#/.test(l) && l.trim() !== "")
      .join("\n");

  test("AC1 the fold header rule precedes the inline rule (first-match capture)", () => {
    const rules = ruleText();
    const foldIdx = rules.search(/command:\[\[:space:\]\]\*>/);
    const inlineIdx = rules.search(/\/\^\[\[:space:\]\]\*command:\/ *\{/);
    expect(foldIdx).toBeGreaterThanOrEqual(0);
    expect(inlineIdx).toBeGreaterThanOrEqual(0);
    expect(foldIdx).toBeLessThan(inlineIdx);
  });

  test("AC1 the blank-line skip precedes the indent terminator", () => {
    const rules = ruleText();
    const blankIdx = rules.search(/mode && \/\^\[\[:space:\]\]\*\$\//);
    const termIdx = rules.search(/mode && indent\(\$0\) <= key/);
    expect(blankIdx).toBeGreaterThanOrEqual(0);
    expect(termIdx).toBeGreaterThanOrEqual(0);
    expect(blankIdx).toBeLessThan(termIdx);
  });
});

describe("#6772 SKILL.md wiring invariants", () => {
  const skill = readFileSync(SKILL_PATH, { encoding: "utf8" });

  test("Step 10.4 calls the extracted awk via git rev-parse, not CLAUDE_PLUGIN_ROOT", () => {
    expect(skill).toMatch(
      /FORM_A_AWK="\$\(git rev-parse --show-toplevel\)\/plugins\/soleur\/skills\/preflight\/scripts\/parse-form-a\.awk"/,
    );
    expect(skill).toMatch(/test -r "\$FORM_A_AWK"/);
  });

  test("Step 10.4 hard-fails on awk rc≠0 instead of falling through to Form B", () => {
    expect(skill).toMatch(/refusing to fall through to Form B/);
  });

  test("Step 10.4 carries the credentialed-CLI reject (CPO condition C1)", () => {
    expect(skill).toMatch(
      /\(\^\|\[\[:space:\]\]\|\/\)\(doppler\|gh\|aws\|supabase\|stripe\)\(\[\[:space:\]\]\|\$\)/,
    );
  });

  test("Step 10.5 reject set includes newline", () => {
    expect(skill).toMatch(/\$'\\n'/);
  });

  test("Form A prose names all three scalar shapes", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    expect(check10![0]).toMatch(/inline/i);
    expect(check10![0]).toMatch(/block/i);
    expect(check10![0]).toMatch(/folded/i);
  });
});

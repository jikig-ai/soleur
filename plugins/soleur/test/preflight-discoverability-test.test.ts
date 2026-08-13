import { describe, expect, test } from "bun:test";
import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyDiscoverabilityResult,
  extractObservabilityBlock,
  matchExpected,
  parseCommand,
  parseCredentialsRequired,
  parseExpected,
  PROBE_VERB_ALLOWLIST,
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
const GATE_PATH = join(
  import.meta.dir,
  "..",
  "skills",
  "preflight",
  "scripts",
  "probe-verb-gate.sh",
);

// Shapes the gate deliberately does not opine on — rejected downstream by the
// classifier's ssh branch or its shell-active-token branch, never by the verb
// gate. Kept as NARROW as possible: the previous predicate skipped any command
// containing any of `;&|<>` backtick `$`, which measured at 60.3% of the real
// producer corpus — and every one of the 149 real bash/TS divergences fell
// inside the skipped region while zero fell inside the compared one. The harness
// was verifying parity exactly where the two implementations trivially agree.
const SKIPPED_BY_DESIGN = /(^|[\s/])ssh([\s]|$)|\n/;
// How many PARITY_CASES rows the predicate is expected to skip. Pinned so a
// widened predicate (which silently shrinks coverage) fails rather than passes.
// Measured: exactly ONE row skips (the embedded-newline block scalar). The `ssh`
// alternative matches ZERO rows today — it guards a shape the table does not yet
// carry. This was pinned at 2 and never asserted, so it granted a free row of
// slack: widening the predicate by one row stayed green, which is precisely what
// the constant exists to prevent. It is now asserted exactly, below.
const SKIPPED_BY_DESIGN_COUNT = 1;

const AWK_PATH = join(
  import.meta.dir,
  "..",
  "skills",
  "preflight",
  "scripts",
  "parse-form-a.awk",
);

// Window helpers, SHARED so there is exactly one implementation.
//
// These were duplicated once, and the duplication is the whole lesson: a hardened
// copy (comment-stripping + unique-anchor) was added in one describe while the
// UNHARDENED original stayed wired to the live Step 10.5 reject. The fix guarded
// a helper with zero call sites, the vulnerable one remained in use, and deleting
// the `$'\n'` alternative from the real reject stayed green. One implementation
// now, at module scope, so a future hardening cannot land on a dead copy.
//
// stripComments: a gate's own explanatory comment must not satisfy the gate's test.
// uniqueIndex:  a decoy occurrence of the anchor must fail loudly, not retarget.
const stripComments = (src: string): string =>
  src
    .split("\n")
    .filter((l) => !/^\s*#/.test(l))
    .join("\n");

const uniqueIndex = (lines: string[], pred: (l: string) => boolean, label: string): number => {
  const hits = lines.map((l, i) => (pred(l) ? i : -1)).filter((i) => i >= 0);
  expect(hits.length, `${label}: anchor must resolve to exactly one line`).toBe(1);
  return hits[0];
};

const makeGateWindow =
  (lines: string[]) =>
  (anchor: RegExp): string => {
    const idx = uniqueIndex(
      lines,
      (l) => anchor.test(l) && /^if \[\[ "\$CMD/.test(l),
      `gate ${anchor}`,
    );
    return stripComments(lines.slice(Math.max(0, idx - 8), idx + 4).join("\n"));
  };

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
  // These two arrays generate 6 tests from ONE backtick `test(` site, and `sort -u`
  // collapses all 6 to a single manifest entry — so the named-test manifest
  // identifies the TEMPLATE, not the instances, and shrinking INDICATORS to [">"]
  // deletes the `>-`/`>+` regression shapes with the manifest wholly unaffected.
  // Pin the generator's shape here, where it lives.
  test("the generated fold-indicator matrix is pinned (manifest sees one entry for all six)", () => {
    expect(INDICATORS.length * TAILS.length, "generated parity coverage is pinned").toBe(6);
  });
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
  // N7 [both] — the `!mode` guard on the awk's header + inline rules.
  //
  // The header and inline rules match on a KEY NAME. Without `!mode` they
  // re-fire on a continuation that happens to begin `command:`, and the inline
  // rule then TRUNCATES the scalar there AND concatenates its value onto the
  // accumulated fold with no separator (printf had not yet emitted a newline).
  // Verified divergence before the fix:
  //   awk => "curl -fsS https://app.soleur.ai/apibar"      (truncated + welded)
  //   TS  => "curl -fsS https://app.soleur.ai/api command: bar"
  // Production would have silently executed the corrupted string. The TS mirror
  // was already correct (all three rules sit behind `if (mode === null)`), so
  // this is the awk-side half of the parity contract.
  const n7 = reg(
    "N7",
    "both",
    obs(
      "discoverability_test:",
      "  command: >",
      "    curl -fsS https://app.soleur.ai/api",
      "    command: bar",
      '  expected_output: "200"',
    ),
  );
  test("N7 a continuation beginning `command:` is CONTENT, not a re-triggered key", () => {
    expectBoth(n7, "curl -fsS https://app.soleur.ai/api command: bar");
    // The two halves of the defect, pinned separately so a partial regression
    // (guard on the headers but not the inline rule) still reddens.
    expect(runAwk(n7)).not.toMatch(/apibar/); // welded
    expect(runAwk(n7)).toMatch(/bar$/); // truncated
  });

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

  // R2 [both] — originally CPO CONDITION C1, retargeted by #7393. This case was
  // what the retired credentialed-CLI DENYLIST existed for: #6772 made folded
  // scalars executable (they used to parse to the literal `>` and self-reject at
  // the shell-active gate), and folding joins with a SPACE, so the shell-active
  // reject covers none of that class.
  //
  // Under #7393 the same command is still rejected — now by the deny-by-default
  // verb allowlist, which covers it without enumerating `doppler` at all.
  test("R2 a folded credentialed command is rejected by the verb allowlist", () => {
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
    // Proven non-vacuous without duplicating SUBST_REJECT_RE here (an inline
    // copy would silently stop tracking the real reject set): swap the verb for
    // an allowlisted one and the command passes every other gate — so nothing
    // but the verb gate covers this class.
    expect(rejectReason(cmd.replace(/^doppler\b/, "curl"))).toBeNull();
    expect(rejectReason(cmd) ?? "").toMatch(/not on the probe-verb allowlist/i);
  });

  test("R2b the retired denylist's verbs stay rejected, and so do verbs it never named", () => {
    // The regression guarantee: nothing the denylist caught may become
    // reachable. The last two entries are the POINT of deny-by-default — a
    // denylist could never have covered them.
    for (const cmd of [
      "doppler secrets get FOO --plain",
      "gh api /repos/x/y",
      "aws s3 ls",
      "supabase db dump",
      "stripe events list",
      "hcloud server list",
      "wrangler deploy",
      "terraform plan",
      "flyctl status",
      "vercel ls",
      "some-future-vendor-cli whoami",
      "kubectl get pods",
    ]) {
      expect(rejectReason(cmd) ?? "", cmd).toMatch(
        /not on the probe-verb allowlist/i,
      );
    }
    // Path-qualified invocation is caught too — by the repo-relative program
    // rule rather than by a `/` alternative in a verb alternation.
    expect(rejectReason("/usr/local/bin/gh pr list") ?? "").toMatch(
      /repo-relative/i,
    );
  });

  // R3 [both]: legitimate probes stay runnable. Under the denylist this was
  // about word boundaries (a bare substring match would false-reject anything
  // containing `gh`, e.g. `--flag=through`). Under a first-token allowlist the
  // substring class cannot arise at all — the invariant asserted is the one that
  // still matters: these probes are not rejected.
  test("R3 unauthenticated probes remain runnable", () => {
    for (const cmd of [
      "curl -fsS -o /dev/null --max-time 10 https://app.soleur.ai/api/health",
      "bun test plugins/soleur/test/preflight-discoverability-test.test.ts",
      "bash plugins/soleur/test/c4-model-freshness.test.sh",
      // Would have been a substring false-reject under the retired denylist.
      "curl -fsS https://app.soleur.ai/highlights",
    ]) {
      expect(rejectReason(cmd), cmd).toBeNull();
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

  // Scope every assertion below to the EXECUTABLE bash fence that owns the gate,
  // never the whole file. Review proved the whole-file form vacuous: deleting the
  // real `$'\n'` alternative from the Step 10.5 reject left the suite green,
  // because the same literal appears in a Sharp Edge *explaining* that reject.
  // A gate's own documentation must not be able to satisfy the gate's test
  // (`cq-assert-anchor-not-bare-token`).
  // Slice a WINDOW around the gate's own `if [[ ... =~` line rather than pairing
  // ``` fences (inline backticks in prose make fence pairing unreliable) or
  // grepping the whole file (proved vacuous — see above).
  // Shared hardened helper (module scope). The previous LOCAL copy retained
  // comments and used findIndex, so a decoy anchor or the gate's own explanatory
  // comment satisfied it — and the hardened version added later landed on a
  // helper with zero call sites while THIS one stayed wired to the live reject.
  const gateWindow = makeGateWindow(skill.split("\n"));
  const shellGate = () => gateWindow(/shell-active|\$'\\n'/);

  test("Step 10.4 calls the extracted awk via git rev-parse, not CLAUDE_PLUGIN_ROOT", () => {
    expect(skill).toMatch(
      /FORM_A_AWK="\$\(git rev-parse --show-toplevel\)\/plugins\/soleur\/skills\/preflight\/scripts\/parse-form-a\.awk"/,
    );
    expect(skill).toMatch(/test -r "\$FORM_A_AWK"/);
  });

  test("Step 10.4 hard-fails on awk rc≠0 instead of falling through to Form B", () => {
    expect(skill).toMatch(/refusing to fall through to Form B/);
  });

  test("Step 10.4 delegates to the extracted probe-verb gate (#7393, ex-CPO condition C1)", () => {
    // AC1 originally required PROBE_VERB_ALLOWLIST to sit inside a Step 10.4
    // gate WINDOW. The gate was extracted to a real file so a parity harness can
    // execute it (see the #7393 GATE describe), so AC1 is REWORDED rather than
    // waived: the same invariants are asserted, against the script.
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    // The runtime invokes the extracted gate and fails closed if it is missing.
    expect(check10![0]).toMatch(/probe-verb-gate\.sh/);
    expect(check10![0]).toMatch(/test -r "\$PROBE_GATE"/);

    const gate = readFileSync(GATE_PATH, { encoding: "utf8" });
    // The allowlist is assigned in the gate, not merely named in prose.
    expect(gate).toMatch(/^PROBE_VERB_ALLOWLIST='/m);
    // Dequoting is retained — `"doppler"` must not launder the verb.
    expect(gate).toMatch(/CMD_DEQ="\$\{CMD\/\//);
    // The retired denylist alternation is gone from the runtime.
    expect(gate).not.toMatch(/\(doppler\|gh\|aws\|supabase\|stripe/);
  });

  test("Step 10.5 reject set includes newline", () => {
    // Scoped to the gate fence: the whole-file form was satisfied by the Sharp
    // Edge that documents this very alternative, so deleting the real one stayed
    // green. Mutation-verified: removing `|$'\n'` from the gate now reddens this.
    expect(shellGate()).toMatch(/\$'\\n'/);
  });

  test("Form A prose names all three scalar shapes", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    expect(check10![0]).toMatch(/inline/i);
    expect(check10![0]).toMatch(/block/i);
    expect(check10![0]).toMatch(/folded/i);
  });
});

// ---------------------------------------------------------------------------
// #7393 — probe-verb allowlist, sandboxed execution, declared-credentialed path
// ---------------------------------------------------------------------------

describe("#7393 GATE — executable parity between the runtime and its TS mirror", () => {
  // The runtime of record is `probe-verb-gate.sh`; `rejectReason()` is the
  // mirror. Content pins (set-equality on the allowlist literal) cannot detect
  // BEHAVIOURAL drift, and demonstrably did not: two parser asymmetries — a
  // Form B command keeping its markdown indentation, and a Form A block scalar
  // keeping a leading `#` — both shipped green because the mirror silently
  // trimmed and the bash did not.
  //
  // This is the P1/P2/P3 pattern (which executes parse-form-a.awk) applied to
  // the gate. It asserts identical VERDICT and identical REASON, so a message
  // reworded on one side alone also reddens.
  const runGate = (cmd: string): { rejected: boolean; reason: string } => {
    const p = Bun.spawnSync({ cmd: ["bash", GATE_PATH, cmd], stdout: "pipe", stderr: "pipe" });
    const out = new TextDecoder().decode(p.stdout).trim();
    expect(p.exitCode, `gate must exit 0 or 1 for: ${cmd}`).not.toBe(2);
    return { rejected: p.exitCode === 1, reason: out };
  };

  // Every row is a shape the producer can actually emit. The first two are the
  // asymmetries that motivated the extraction.
  const PARITY_CASES: string[] = [
    // Form B keeps markdown indentation.
    '  curl -fsS -o /dev/null -w "%{http_code}" https://app.soleur.ai/api/inngest',
    // Form A block scalar keeps a leading `#` comment line.
    "# Run from the operator workstation (NO SSH)\ncurl -fsS https://app.soleur.ai/api/inngest",
    // An allowlisted verb that is nonetheless a full execution vector — accepted
    // deliberately, and named in ADR-175 as the worked example.
    "git -c alias.pwn=!printf X pwn",
    // The path-shaped bypass that used to skip the allowlist entirely.
    "./doppler secrets get FOO --plain",
    "./node_modules/.bin/vitest run x",
    "gh/Sentry query for op:image-verify",
    // Shapes the reduced gate must now ACCEPT (they were false-rejected before).
    "bun test plugins/soleur/test/x.test.ts -p",
    "python3 scripts/check.py --print json",
    "node scripts/probe.mjs -e prod",
    "bash scripts/x.sh -c foo",
    // Ordinary accepts and rejects.
    "curl -fsS -o /dev/null https://app.soleur.ai/api/inngest",
    "grep -c . AGENTS.md",
    "doppler secrets get FOO --plain",
    "awk BEGIN{system(id)}",
    '"doppler" secrets get X',
    "",
    "   ",
    // Separator characters: U+2028 is in glibc UTF-8's space class and not in
    // C's, so the gate pins LC_ALL=C. Without a row here the divergence is
    // invisible to this harness.
    "curl\u2028evilarg",
    "curl\u00a0evilarg",
    // LEADING separators — the shape that actually diverged. JS `.trim()` strips
    // these and LC_ALL=C does not, so the mirror accepted what the runtime
    // rejects. A plan pasted from a browser or a doc is how they arrive.
    "\u00a0curl -fsS https://app.soleur.ai/api/inngest",
    "\u2028curl -fsS https://app.soleur.ai/api/inngest",
    "\u3000curl -fsS https://app.soleur.ai/api/inngest",
    "\u2009doppler secrets get FOO",
  ];

  test("the gate and rejectReason agree on verdict and reason for every shape", () => {
    let compared = 0;
    const seenShapes = new Set<string>();
    for (const cmd of PARITY_CASES) {
      // Skip BEFORE spawning: `ssh` and the shell-active reject live in the
      // classifier, not the gate, so the gate has no opinion on them. Skipping
      // after the spawn burned a subprocess per skipped row.
      if (SKIPPED_BY_DESIGN.test(cmd)) continue;
      const gate = runGate(cmd);
      const mirror = rejectReason(cmd);
      compared++;
      seenShapes.add(cmd);
      expect(gate.rejected, `verdict mismatch for: ${JSON.stringify(cmd)}`).toBe(mirror !== null);
      if (gate.rejected) {
        expect(gate.reason, `reason mismatch for: ${JSON.stringify(cmd)}`).toBe(mirror);
      }
    }
    // MEASURE THE WORK, NOT THE INPUT. The previous non-vacuity check counted
    // ROWS in the table, so a table rewritten to rows the predicate skips left
    // the harness comparing ZERO pairs while still reporting green — the same
    // vacuity shape it exists to prevent, one level up.
    //
    // But a floor indexed to `PARITY_CASES.length` still SCALES WITH ITS OWN
    // INPUT: deleting rows lowers the bar they were being measured against.
    // Measured, that is exploitable end-to-end — delete the six separator rows
    // (whose own comment reads "without a row here the divergence is invisible")
    // and the suite stays green; THEN delete `export LC_ALL=C` from the runtime
    // of record and it is still green, while the gate really does start
    // accepting `curl<U+2028>evilarg`. With the rows present that same runtime
    // edit reddens immediately. So the floor must be ABSOLUTE, and it ratchets
    // upward only — never derived from the table it guards.
    const MIN_COMPARED = 22;
    // DISTINCT shapes, not iterations: `compared` increments once per surviving
    // row regardless of what the row IS, so replacing the six separator rows with
    // six duplicate reject-rows held the floor at 22 — and deleting `export
    // LC_ALL=C` from the runtime of record was then green again. That is this
    // test's own headline exploit, one level down.
    expect(
      seenShapes.size,
      "the harness must compare DISTINCT shapes, not repeat one row",
    ).toBeGreaterThanOrEqual(MIN_COMPARED);

    // The separator rows are the only thing that reddens on an LC_ALL=C deletion,
    // so pin them by identity rather than trusting the count to imply them.
    for (const sep of ["\u2028", "\u00a0", "\u3000", "\u2009"]) {
      expect(
        PARITY_CASES.some((c) => c.includes(sep)),
        `a row carrying U+${sep.codePointAt(0)!.toString(16).toUpperCase().padStart(4, "0")} must exist`,
      ).toBe(true);
    }
    // And assert the runtime property those rows exist to protect, directly.
    expect(
      readFileSync(GATE_PATH, { encoding: "utf8" }),
      "the gate pins LC_ALL=C; without it U+2028 is accepted",
    ).toMatch(/^export LC_ALL=C$/m);
  });

  test("the skip predicate is pinned — widening it cannot silently shrink coverage", () => {
    // Every skipped row must be skipped for a SANCTIONED reason. An exact count
    // was tried first and rejected: it false-REDs on a legitimate `ssh` row
    // addition — the very shape the predicate's ssh alternative exists for — while
    // the absolute MIN_COMPARED floor above already catches a widened predicate
    // (widening drops `compared` below 22). Reason-pinning catches the case the
    // count was actually for: a predicate rewritten to skip an UNSANCTIONED shape.
    const skipped = PARITY_CASES.filter((c) => SKIPPED_BY_DESIGN.test(c));
    expect(skipped.length, "at least the sanctioned skip is present").toBeGreaterThanOrEqual(
      SKIPPED_BY_DESIGN_COUNT,
    );
    for (const c of skipped) {
      expect(
        /\n/.test(c) || /(^|[\s/])ssh([\s]|$)/.test(c),
        `unsanctioned skip (predicate widened?): ${JSON.stringify(c)}`,
      ).toBe(true);
    }
  });

  test("the parity table is non-vacuous — it contains both accepts and rejects", () => {
    const verdicts = PARITY_CASES.map((c) => rejectReason(c) !== null);
    expect(verdicts.filter(Boolean).length, "needs reject cases").toBeGreaterThanOrEqual(5);
    expect(verdicts.filter((v) => !v).length, "needs accept cases").toBeGreaterThanOrEqual(5);
  });
});

describe("#7393 A — deny-by-default probe-verb allowlist", () => {
  // Ten verbs, each with >= 2 uses in the measured corpus. ADR-175 §Layer 2
  // states the extraction method (642 parseable commands: top-level .md under
  // knowledge-base/project/plans/, archive/ excluded) rather than repeating a
  // bare number three artifacts previously disagreed on. Deny-by-default is the
  // point: a verb not here is rejected, and widening is a reviewed one-line PR.
  const ALLOWLISTED = [
    "curl -fsS -o /dev/null -w '%{http_code}' https://app.soleur.ai/api/inngest",
    "bash scripts/lint-workflows.sh --help",
    "grep -c . AGENTS.md",
    "rg --count PROBE_VERB_ALLOWLIST plugins/soleur/skills/preflight/SKILL.md",
    "jq -r .version package.json",
    "python3 scripts/lint-agents-rule-budget.py",
    "node scripts/probe.mjs",
    "bun test plugins/soleur/test/preflight-discoverability-test.test.ts",
    "printf hello",
    "git rev-parse HEAD",
  ];

  test("A1 every allowlisted verb is accepted", () => {
    for (const cmd of ALLOWLISTED) {
      expect(rejectReason(cmd), `expected null for: ${cmd}`).toBeNull();
    }
  });

  test("A2 a verb outside the allowlist is rejected", () => {
    for (const cmd of [
      "doppler secrets get FOO --plain",
      "gh api /repos/x/y",
      "aws s3 ls",
      "supabase db dump",
      "stripe events list",
      "psql -c 'select 1'",
      "docker ps",
      "systemctl status nginx",
      "sentry-cli info",
      // The point of deny-by-default: a vendor CLI that no denylist enumerated.
      "flyio-next-gen status",
    ]) {
      expect(rejectReason(cmd) ?? "", cmd).toMatch(/not on the probe-verb allowlist/i);
    }
  });

  test("A3 the reject reason names both remedies and the widening route", () => {
    const reason = rejectReason("doppler secrets get FOO --plain") ?? "";
    // Remedy 1 — wrap it in a repo-relative script.
    expect(reason).toMatch(/repo-relative/i);
    // Remedy 2 — declare it when the probe genuinely needs credentials.
    expect(reason).toMatch(/credentials_required/);
    // Remedy 3 — the allowlist is extensible by a reviewed PR, not a dead end.
    expect(reason).toMatch(/PROBE_VERB_ALLOWLIST/);
  });

  test("A4 dequoting still applies to the verb (quotes do not launder it)", () => {
    for (const cmd of [
      '"doppler" secrets get X',
      "\\doppler secrets get X",
      'dopp""ler secrets get X',
    ]) {
      expect(rejectReason(cmd) ?? "", cmd).toMatch(/not on the probe-verb allowlist/i);
    }
  });
});

describe("#7393 B — retired rules stay retired", () => {
  // The inline-program arg rules and the repo-relative program-path rule were
  // DELETED (CTO ruling on #7393). Not because they were merely redundant:
  // the gate's own remedy — "wrap it in a repo-relative script" => `bash
  // scripts/x.sh` — confers strictly MORE capability than anything they
  // rejected, and Step 10.5 runs `bash -c "$CMD"` regardless, so every probe
  // already is an inline program. They rejected a spelling, not a capability,
  // and measurably false-rejected legitimate probes.
  //
  // These assertions pin the DELETION, so a future author cannot reintroduce
  // the rules without confronting the reasoning.
  test("B1 inline-program flags no longer false-reject legitimate probes", () => {
    for (const cmd of [
      "bun test plugins/soleur/test/x.test.ts -p",
      "python3 scripts/check.py --print json",
      "node scripts/probe.mjs -e prod",
      "bash scripts/x.sh -c foo",
    ]) {
      expect(rejectReason(cmd), `should be accepted: ${cmd}`).toBeNull();
    }
  });

  test("B2 awk/sed/find are still rejected — by frequency, not by capability", () => {
    // They are absent from the corpus-frequency allowlist. The old rationale
    // ("they are `bash -c` in disguise") was retired as incoherent: `bash` and
    // `git` are BOTH on the allowlist and both are full execution vectors.
    for (const cmd of [
      "awk BEGIN{system(id)}",
      "sed -e 1e_wc AGENTS.md",
      "find . -name x -exec wc -c {} +",
    ]) {
      expect(rejectReason(cmd) ?? "", cmd).toMatch(/not on the probe-verb allowlist/i);
    }
  });
});

describe("#7393 C — no path-shaped bypass", () => {
  // The allowlist used to be skipped entirely whenever the first token
  // contained a `/`. That made "deny-by-default" false as printed: measured,
  // `./doppler secrets get FOO` ACCEPTED while a bare `doppler` rejected 124
  // times, and the pure-prose corpus entry `gh/Sentry query for …` accepted for
  // the same reason. Removing the exemption is what makes the phrase true.
  test("C1 a path-shaped verb is subject to the allowlist like any other", () => {
    for (const cmd of [
      "./doppler secrets get FOO --plain",
      "~/bin/doppler secrets get FOO",
      "/usr/local/bin/gh api user",
      "gh/Sentry query for op:image-verify",
      "./node_modules/.bin/vitest run x",
    ]) {
      expect(rejectReason(cmd) ?? "", cmd).toMatch(/not on the probe-verb allowlist/i);
    }
  });

  test("C2 an allowlisted verb running a repo-relative script is still accepted", () => {
    expect(rejectReason("bash scripts/lint-workflows.sh --help")).toBeNull();
    expect(rejectReason("python3 scripts/lint-agents-rule-budget.py")).toBeNull();
  });

  test("C3 rejectReason stays a pure synchronous string -> string|null", () => {
    // No `git ls-files` oracle: it interrogates the PR-HEAD index (the
    // attacker's own branch) and preflight runs before merge, so "tracked" is
    // not "reviewed".
    const out = rejectReason("bash scripts/lint-workflows.sh --help");
    expect(out === null || typeof out === "string").toBe(true);
    expect(out).not.toBeInstanceOf(Promise);
  });

  test("C4 normalization is applied before the verb is read", () => {
    // Form B keeps markdown indentation; a Form A block scalar can keep a
    // leading `#`. Both used to yield a nonsense verb ("" / "#") and a FAIL
    // whose message named remedies that could not apply.
    expect(rejectReason("  curl -fsS https://app.soleur.ai/api/inngest")).toBeNull();
    expect(
      rejectReason("# a comment line\ncurl -fsS https://app.soleur.ai/api/inngest"),
    ).toBeNull();
  });
});

describe("#7393 D — credentials_required => SKIP-DECLARED", () => {
  const throwingExecutor: Executor = async () => {
    throw new Error("executor must not be called");
  };

  const declaredBlock = obs(
    "discoverability_test:",
    "  command: doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 24h --grep SOLEUR_ZOT_INVENTORY --limit 20",
    '  expected_output: "≥1 row"',
    '  credentials_required: "doppler:soleur/prd_terraform — Better Stack\'s query API has no unauthenticated form."',
  );

  test("D1 parseCredentialsRequired reads the sub-field", () => {
    expect(parseCredentialsRequired(declaredBlock)).toMatch(
      /doppler:soleur\/prd_terraform/,
    );
    expect(
      parseCredentialsRequired(
        obs("discoverability_test:", "  command: curl https://x", '  expected_output: "200"'),
      ),
    ).toBe("");
  });

  test("D2 a declared probe classifies SKIP-DECLARED without executing", async () => {
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: `## Observability\n\n${declaredBlock}\n`,
      prBody: "",
      runner: throwingExecutor,
    });
    expect(out.result).toBe("SKIP-DECLARED");
    // The declared scope is surfaced verbatim — it is the reviewable artifact.
    expect(out.reason ?? "").toMatch(/doppler:soleur\/prd_terraform/);
  });

  // Each of the three shapes below was measured to yield SKIP-DECLARED — i.e. to
  // silently waive the entire check — before the sub-block scoping landed.
  test("D2b a declaration outside the discoverability_test sub-block does NOT waive", async () => {
    const body = [
      "## Observability",
      "",
      "liveness_signal:",
      "  what: the thing",
      "  credentials_required: Grafana viewer role",
      "",
      "discoverability_test:",
      "  command: grep -c . AGENTS.md",
      '  expected_output: "110"',
      "",
    ].join("\n");
    expect(parseCredentialsRequired(body)).toBe("");
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: body,
      prBody: "",
      runner: stubExecutor(0, "110\n"),
    });
    // The runnable unauthenticated probe must actually run.
    expect(out.result).toBe("PASS");
  });

  test("D2c copying the documented template does NOT waive the check", async () => {
    // plan-issue-templates.md ships this line verbatim. Before the fix it parsed
    // as a valid non-placeholder declaration whose "declared scope" was the
    // template's own explanatory comment.
    const body = [
      "## Observability",
      "",
      "discoverability_test:",
      "  command: doppler secrets get FOO --plain",
      '  expected_output: "x"',
      "  credentials_required: # OPTIONAL. Only when the property has no unauthenticated substitute.",
      "",
    ].join("\n");
    expect(parseCredentialsRequired(body)).toBe("");
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: body,
      prBody: "",
      runner: throwingExecutor,
    });
    // Falls through to the verb gate — the correct outcome for a doppler probe.
    expect(out.result).toBe("FAIL");
    expect(out.reason ?? "").toMatch(/not on the probe-verb allowlist/i);
  });

  test("D2d a bare block/fold indicator does NOT waive the check", () => {
    // Includes the CHOMPED forms: #6772 made those first-class for `command:`,
    // so they are the likelier shape an author reaches for, and the original set
    // covered only the two least likely.
    for (const ind of [">", ">-", ">+", "|", "|-", "|+"]) {
      const body = [
        "## Observability",
        "",
        "discoverability_test:",
        "  command: doppler secrets get FOO",
        `  credentials_required: ${ind}`,
        "",
      ].join("\n");
      expect(parseCredentialsRequired(body), `indicator ${ind}`).toBe("");
    }
  });

  test("D3 a placeholder declaration FAILs (existing placeholder machinery)", async () => {
    for (const placeholder of [
      "TBD",
      "TODO",
      "N/A",
      "tbd",
      "<fill me in>",
      // The two markers the rest of the repo treats as canonical "this field
      // says nothing" — originally absent from preflight's set, so they GRANTED
      // the waiver instead of refusing it.
      "placeholder",
      "manual operator check",
      // Quoted and trailing-whitespace forms. These were the bash-ONLY bypass:
      // the runtime stripped `"` and never trimmed, so `'placeholder'` and
      // `TODO  ` reached SKIP-DECLARED while this mirror correctly FAILed them.
      // The suite could not see it because every fixture went through the mirror.
      "'placeholder'",
      '"TODO"',
      "TODO  ",
      "  TBD",
    ]) {
      const body = `## Observability\n\n${obs(
        "discoverability_test:",
        "  command: doppler secrets get FOO --plain",
        '  expected_output: "ok"',
        `  credentials_required: ${placeholder}`,
      )}\n`;
      const out = await classifyDiscoverabilityResult({
        planPath: "plans/x.md",
        planBody: body,
        prBody: "",
        runner: throwingExecutor,
      });
      expect(out.result, placeholder).toBe("FAIL");
      expect(out.reason ?? "", placeholder).toMatch(/placeholder/i);
    }
  });

  test("D4 ssh is NOT overridable by a declaration", async () => {
    const body = `## Observability\n\n${obs(
      "discoverability_test:",
      "  command: ssh web-1 systemctl status inngest",
      '  expected_output: "active"',
      '  credentials_required: "ssh:web-1 — needs host access"',
    )}\n`;
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: body,
      prBody: "",
      runner: throwingExecutor,
    });
    expect(out.result).toBe("FAIL");
    expect(out.reason ?? "").toMatch(/ssh/i);
  });

  test("D5 the SKIP-DECLARED fixture classifies without executing", async () => {
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/10.md",
      planBody: fx("10-credentials-required-skip.md"),
      prBody: "",
      runner: throwingExecutor,
    });
    expect(out.result).toBe("SKIP-DECLARED");
    expect(out.reason ?? "").toMatch(/prd_terraform/);
  });

  test("D5b the advisory fires only when the declared verb IS executable", async () => {
    // Applying the verb gate to declared probes as a REJECT would re-close the
    // door #7393 opened (`doppler` is deliberately off the allowlist). A plain
    // advisory would fire on ~100% of declarations. So it targets the actual
    // abuse gradient: a declared probe whose verb Check 10 could have run.
    const mk = (command: string) =>
      `## Observability\n\n${obs(
        "discoverability_test:",
        `  command: ${command}`,
        '  expected_output: "x"',
        '  credentials_required: "doppler:soleur/prd_terraform — no unauthenticated form"',
      )}\n`;

    const notExecutable = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: mk("doppler run -p soleur -c prd_terraform -- scripts/q.sh"),
      prBody: "",
      runner: throwingExecutor,
    });
    expect(notExecutable.result).toBe("SKIP-DECLARED");
    expect(notExecutable.reason ?? "", "no advisory for a genuinely un-runnable verb").not.toMatch(
      /advisory/i,
    );

    const executable = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: mk("curl -fsS -o /dev/null https://app.soleur.ai/api/inngest"),
      prBody: "",
      runner: throwingExecutor,
    });
    expect(executable.result).toBe("SKIP-DECLARED");
    expect(executable.reason ?? "", "advisory expected for an executable verb").toMatch(
      /advisory/i,
    );
    // Still does not execute — the advisory is a signal, not a downgrade.
    expect(executable.reason ?? "").toMatch(/did NOT execute/);
  });

  test("D6 the not-allowlisted fixture FAILs without executing", async () => {
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/09.md",
      planBody: fx("09-verb-not-allowlisted.md"),
      prBody: "",
      runner: throwingExecutor,
    });
    expect(out.result).toBe("FAIL");
    expect(out.reason ?? "").toMatch(/not on the probe-verb allowlist/i);
  });
});

describe("#7393 E — fail-closed sandbox, no unsandboxed fallback", () => {
  const throwingExecutor: Executor = async () => {
    throw new Error("executor must not be called");
  };

  const passBody = `## Observability\n\n${obs(
    "discoverability_test:",
    "  command: grep -c . AGENTS.md",
    '  expected_output: "110"',
  )}\n`;

  test("E1 sandbox unavailable => SKIP naming the sandbox, executor never called", async () => {
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: passBody,
      prBody: "",
      runner: throwingExecutor,
      sandboxAvailable: false,
    });
    // Its OWN terminal — folded into ordinary SKIP, "the gate verified nothing"
    // was indistinguishable from "the gate had nothing to do".
    expect(out.result).toBe("SKIP-NOSANDBOX");
    expect(out.reason ?? "").toMatch(/sandbox/i);
    // Fail-closed, stated: a degraded sandbox must never revert to the status quo.
    expect(out.reason ?? "").toMatch(/bwrap|bubblewrap/i);
    // bwrap is Linux-only, so on macOS this is permanent, not transient. The
    // message must say so rather than implying a retryable condition.
    expect(out.reason ?? "").toMatch(/Linux-only|macOS/i);
  });

  test("E2 sandbox available => the executor IS reached (E1 is not vacuous)", async () => {
    const out = await classifyDiscoverabilityResult({
      planPath: "plans/x.md",
      planBody: passBody,
      prBody: "",
      runner: stubExecutor(0, "110\n"),
      sandboxAvailable: true,
    });
    expect(out.result).toBe("PASS");
  });
});

describe("#7393 F — SKILL.md runtime wiring (gate windows, never whole-file)", () => {
  const skill = readFileSync(SKILL_PATH, { encoding: "utf8" });
  const lines = skill.split("\n");

  // Window helpers are shared at module scope (see makeGateWindow).

  // The sandbox flags live in ONE array so the establishment probe and the real
  // run cannot drift; anchor the window on that array rather than on the exec
  // line, which references it by name.
  //
  // window-assembly: sandboxWindow — this window spans ONLY the `BWRAP_ARGS=( … )`
  // literal, which is NARROWER than the mount set. The full assembly is
  // BWRAP_ARGS + GIT_BIND + BWRAP_PROC + the exec line, and three separate
  // one-line edits outside this window each re-opened the operator's credential
  // surface with the whole suite green. The sibling assertions at "1e" below pin
  // the assembly's remainder: gitBindAssigns and procAssigns are matched against
  // the WHOLE Check 10 body (not this window), and the `+=` checks at "2" bound
  // append sites for all three arrays. The FOURTH member — the exec line — is
  // pinned separately by the anchored full-invocation regex in test F2 above,
  // NOT by 1e or 2; loosening F2 would leave this declaration reading true while
  // that member went unpinned. Any new mount-injection site must be added to
  // those assertions, not here.
  const sandboxWindow = (): string => {
    const idx = uniqueIndex(lines, (l) => /^BWRAP_ARGS=\(/.test(l), "BWRAP_ARGS=(");
    const end = lines.findIndex((l, i) => i > idx && /^\)/.test(l));
    expect(end).toBeGreaterThan(idx);
    return stripComments(lines.slice(idx, end + 1).join("\n"));
  };

  test("F1 AC1 — Step 10.4 delegates to the extracted gate, not to inline bash", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    // The gate is a real file so the parity harness below can EXECUTE it. An
    // inline copy plus a hand-maintained mirror is what let two parser
    // asymmetries ship green inside the PR that created the mirror.
    expect(check10![0]).toMatch(/probe-verb-gate\.sh/);
    // The retired denylist alternation must be gone from the runtime (it is
    // still legitimately named in the surrounding prose as history).
    expect(readFileSync(GATE_PATH, { encoding: "utf8" })).not.toMatch(
      /\(doppler\|gh\|aws\|supabase\|stripe/,
    );
  });

  test("F1c the runtime normalizes $CMD ONCE, before the gate, the reject and the exec", () => {
    // Gate/execute coherence. Normalizing inside the gate alone produced a real
    // laundering gap: the gate judged the NORMALIZED command while Step 10.5's
    // shell-active reject tested the RAW one, so a Form A block scalar with a
    // leading `#` comment was accepted by the gate and rejected by the runtime on
    // its embedded newline. The parity harness compares only the GATE, so it was
    // structurally blind to this — hence a positional assertion here.
    const norm = lines.findIndex((l) => /^CMD="\$\(printf '%s' "\$CMD" \| sed/.test(l));
    const gate = lines.findIndex((l) => /^PROBE_GATE=/.test(l));
    const reject = lines.findIndex((l) => /shell-active token; refusing to run/.test(l));
    const exec = lines.findIndex((l) => /^DT_OUT=\$\(/.test(l));
    expect(norm, "normalization line must exist").toBeGreaterThan(-1);
    expect(gate, "gate invocation must exist").toBeGreaterThan(-1);
    expect(reject, "shell-active reject must exist").toBeGreaterThan(-1);
    expect(exec, "exec line must exist").toBeGreaterThan(-1);
    // Every consumer must see the normalized string.
    expect(norm, "normalize before the verb gate").toBeLessThan(gate);
    expect(norm, "normalize before the shell-active reject").toBeLessThan(reject);
    expect(norm, "normalize before the sandboxed exec").toBeLessThan(exec);
  });

  test("F2 AC2 — the sandbox carries the load-bearing binds", () => {
    const w = sandboxWindow();
    expect(w).toMatch(/--ro-bind "\$REPO_ROOT" "\$REPO_ROOT"/);
    expect(w).toMatch(/--tmpfs \/home/);
    expect(w).toMatch(/--tmpfs \/run/);
    expect(w).toMatch(/--unshare-all/);
    // `/var` is not bound, so without this `/var/tmp` does not exist and every
    // probe using this repo's own scratch convention (TMPDIR=/var/tmp) dies on
    // `mktemp: No such file or directory`. Found by the execution replay.
    expect(w).toMatch(/--tmpfs \/var\/tmp/);
    // `--tmpfs /run` removes /run/systemd/resolve/stub-resolv.conf, which
    // /etc/resolv.conf symlinks to; without the rebind every curl probe returns
    // rc=6 — indistinguishable from the #4148 DNS-typo regression.
    expect(w).toMatch(/--ro-bind "\$RESOLV" "\$RESOLV"/);
    // In a worktree `.git` is a FILE pointing at the git common dir under the
    // bare repo root — outside $REPO_ROOT. Without this bind every `git` probe
    // fails `fatal: not a git repository`, and `git` is an allowlisted verb.
    // Soleur runs in worktrees by default, so this is the common case.
    expect(w).toMatch(/\$\{GIT_BIND\[@\]\}/);
    // The exec must consume that same array — one source of truth for the flags,
    // so the establishment probe and the real run cannot diverge.
    const execLine = lines.find((l) => /^DT_OUT=\$\(/.test(l)) ?? "";
    expect(execLine).toMatch(/bwrap/);
    expect(execLine).toMatch(/\$\{BWRAP_ARGS\[@\]\}/);
    // Without this the probe inherits preflight's stdin: a command that reads
    // stdin either eats input the caller was still using, or blocks the full
    // 15s and misreports as a timeout.
    expect(execLine).toMatch(/<\/dev\/null/);
    // ANCHORED PREFIX, not three independent presence checks. Presence alone
    // permits arbitrary EXTRA bwrap flags between the array expansion and the
    // interpreter — `… "${BWRAP_ARGS[@]}" --ro-bind /home /home /usr/bin/env …`
    // satisfied every assertion above while restoring the operator's $HOME.
    // The mount set being closed (F2b) is worth nothing if the exec line may
    // append to it, so pin the two as ADJACENT.
    //
    // `env -i` is load-bearing and is asserted HERE because it is the ONLY
    // control over environment-resident credentials. bwrap does not scrub the
    // environment: measured, a variable set in preflight's env survives into the
    // sandbox verbatim. DOPPLER_TOKEN, GH_TOKEN and ANTHROPIC_API_KEY live in
    // the environment ONLY — no on-disk store to unmount — so the surrounding
    // "the files are gone anyway" reasoning does not reach them. With `curl`
    // allowlisted and --share-net retaining egress, dropping `-i` is a one-token
    // edit that exfiltrates every credential in preflight's environment.
    expect(
      execLine,
      "nothing may sit between the mount array and env -i, and -i must survive",
    ).toMatch(
      /bwrap "\$\{BWRAP_PROC\[@\]\}" "\$\{BWRAP_ARGS\[@\]\}" \/usr\/bin\/env -i PATH=\/usr\/local\/bin:\/usr\/bin:\/bin HOME=\/tmp timeout 15s bash -c "\$CMD"/,
    );
  });

  test("F2b AC2 — the sandbox mount set is CLOSED, not merely populated", () => {
    // Presence assertions ask "are the good flags there?" and never "are ONLY
    // the good flags there?" — and on a mount-flag array ADDITION is the attack.
    // Measured, all three of these stayed 119/0 green against presence-only
    // assertions, and each restores the operator's real $HOME (Doppler token,
    // SSH keys, D-Bus keyring) inside the sandbox whose entire purpose is
    // removing them:
    //   BWRAP_ARGS+=(--bind /home /home)   appended after the array closes
    //   GIT_BIND+=(--bind /home /home)     appended after its assignment
    //   --bind /home /home                 added INSIDE the array
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    const body = stripComments(check10![0]);

    // 1. Every bind in Check 10 is READ-ONLY. Enumerate what is there and
    //    set-compare, rather than grepping for the ones we hope to find.
    const binds = [...body.matchAll(/(^|\s)(--(?:ro-)?bind[a-z-]*)\b/g)].map((m) => m[2]);
    expect(binds.length, "expected some binds").toBeGreaterThan(0);
    expect(
      [...new Set(binds)].sort(),
      "only --ro-bind may appear; a writable --bind re-opens the credential surface",
    ).toEqual(["--ro-bind"]);

    // 1b. THE SOURCE SET IS CLOSED. The assertion above is a WRITABILITY
    //     predicate, not a closure one: `--ro-bind /home /home` satisfies it and
    //     restores the operator's real $HOME wholesale. Measured against live
    //     bwrap with that single line added, an absolute-path read of
    //     the Doppler config under ~/.doppler/ returned the 294-byte token and
    //     ~/.ssh listed private keys — inside the sandbox built to remove them,
    //     with this suite reporting 115/0 green and the integrity gate 7/7.
    //     Read-only is sufficient to EXFILTRATE: Check 10 prints probe stdout,
    //     `curl` is allowlisted, and --share-net retains egress. --ro-bind only
    //     closes write-back escalation, never the credential surface.
    //     So enumerate SOURCES over the array window and set-compare.
    const win = sandboxWindow();
    expect(
      [...new Set([...win.matchAll(/--ro-bind\s+(\S+)/g)].map((m) => m[1]))].sort(),
      "the --ro-bind SOURCE set is closed; a read-only /home re-bind restores the credential surface",
    ).toEqual(['"$REPO_ROOT"', '"$RESOLV"', "/etc", "/usr"]);

    // 1c. Closed in the DELETION direction too. Removing `--tmpfs /home` exposes
    //     the real home exactly as an added bind would, and presence-style
    //     assertions are all green when a tmpfs is deleted rather than added.
    expect(
      [...new Set([...win.matchAll(/--tmpfs\s+(\S+)/g)].map((m) => m[1]))].sort(),
      "the --tmpfs set is closed; deleting --tmpfs /home re-exposes the operator home",
    ).toEqual(["/home", "/root", "/run", "/tmp", "/var/tmp"]);

    // 1d. Only GIT_BIND may inject mounts by expansion — otherwise 1b is bypassed
    //     by `FOO_BIND=(--ro-bind /home /home)` declared outside the window and
    //     expanded inside it.
    expect(
      [...new Set([...win.matchAll(/\$\{(\w+)\[@\]\}/g)].map((m) => m[1]))].sort(),
      "only GIT_BIND may inject mounts by expansion",
    ).toEqual(["GIT_BIND"]);
    // Quotes are NOT part of the pattern above: requiring them made an UNQUOTED
    // `${FOO_BIND[@]}` inside the window invisible to this very assertion —
    // the exact case its comment describes, defeated by dropping two characters.
    // Unquoted expansion is also a word-splitting bug, so pin it separately.
    expect(
      [...win.matchAll(/(.?)\$\{\w+\[@\]\}(.?)/g)].map((m) => m[1] + m[2]),
      "every array expansion in the mount vector must be double-quoted",
    ).toEqual(Array((win.match(/\$\{\w+\[@\]\}/g) ?? []).length).fill('""'));

    // 1e. The arrays that reach the exec line must be ASSIGNED exactly where we
    //     think. 1d pins WHICH names may expand; it does not bound how many times
    //     each is ASSIGNED, and both arrays are assigned OUTSIDE sandboxWindow().
    //     Measured, all three of these left the suite green: a second
    //     `GIT_BIND=(--ro-bind /home /home)` after the `fi`; an `else` branch
    //     assigning the same; and `BWRAP_PROC=(--proc /proc --ro-bind /home /realhome)`.
    //     The destination matters — `--tmpfs /home` does not shadow /realhome, and a
    //     live bwrap replay reached the Doppler token, ~/.ssh and the gh token store.
    const gitBindAssigns = [...body.matchAll(/^\s*GIT_BIND=\((.*)\)\s*$/gm)].map((m) => m[1]);
    expect(
      gitBindAssigns,
      "GIT_BIND is assigned exactly twice: the empty init and the conditional ro-bind",
    ).toEqual(["", '--ro-bind "$GIT_COMMON_DIR" "$GIT_COMMON_DIR"']);
    const procAssigns = [...body.matchAll(/^\s*BWRAP_PROC=\((.*)\)\s*$/gm)].map((m) => m[1]);
    expect(
      procAssigns,
      "BWRAP_PROC carries --proc only; its degrade form is empty",
    ).toEqual(["--proc /proc", ""]);

    // 2. The arrays are ASSIGNED, never appended to. `uniqueIndex` pins the
    //    assignment; nothing stopped a later `+=`.
    expect((body.match(/BWRAP_ARGS\+=/g) ?? []).length, "BWRAP_ARGS must never be appended to").toBe(0);
    expect((body.match(/GIT_BIND\+=/g) ?? []).length, "GIT_BIND must never be appended to").toBe(0);
    expect((body.match(/BWRAP_PROC\+=/g) ?? []).length, "BWRAP_PROC must never be appended to").toBe(0);

    // 3. No --dev-bind / --bind-try smuggling a writable mount under another name.
    expect(body).not.toMatch(/--dev-bind\b/);
    expect(body).not.toMatch(/--bind-try\b/);
    // The overlay family matches NONE of the bind regexes above (it does not
    // contain the token `bind`), so it would re-expose /home past every
    // assertion in this test. Named explicitly rather than left to the
    // enumeration, because the enumeration cannot see it at all.
    expect(body).not.toMatch(/--(?:ro-|tmp-)?overlay(?:-src)?\b/);
  });

  test("F3 AC2 — mount order is load-bearing: --tmpfs /home precedes the repo bind", () => {
    const w = sandboxWindow();
    const tmpfsHome = w.indexOf("--tmpfs /home");
    const repoBind = w.indexOf('--ro-bind "$REPO_ROOT"');
    expect(tmpfsHome).toBeGreaterThanOrEqual(0);
    expect(repoBind).toBeGreaterThanOrEqual(0);
    // Reversed, the tmpfs silently clobbers the repo bind and every probe dies
    // with `Can't chdir` — a failure that reads as bwrap incompatibility.
    expect(tmpfsHome).toBeLessThan(repoBind);
  });

  test("F4 AC5b — --proc /proc degrades rather than failing the sandbox", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    // /proc cannot be mounted in a nested user namespace (the repo already knows
    // this: `enableWeakerNestedSandbox`, #1557). A hard --proc would SKIP Check 10
    // in every containerized run — including the one-shot pipeline's own — while
    // looking exactly like the fail-closed design working correctly.
    //
    // Assert the DEGRADATION STRUCTURE, not the presence of the token. A bare
    // `toMatch(/BWRAP_PROC/)` survived renaming the assignment away, because the
    // name still occurred in the `"${BWRAP_PROC[@]}"` expansions further down —
    // the `cq-assert-anchor-not-bare-token` trap, caught by mutation.
    const body = check10![0];
    // 1. The strong form is attempted first.
    expect(body).toMatch(/^BWRAP_PROC=\(--proc \/proc\)$/m);
    // 2. On establishment failure it is emptied and retried ONCE.
    expect(body).toMatch(/^\s*BWRAP_PROC=\(\)$/m);
    // 3. The retry really is the sandbox minus --proc, not a second identical try.
    expect(body).toMatch(/if ! bwrap "\$\{BWRAP_ARGS\[@\]\}" true/);
    // 4. Only then does it give up — fail-closed, never unsandboxed.
    expect(body).toMatch(/SKIP-NOSANDBOX: Check 10 could not establish the bwrap sandbox/);
    // The give-up must state MEASURED causes, not a hypothesis (AP-021): the
    // earlier message named apparmor_restrict_unprivileged_userns without ever
    // reading it, while 2>/dev/null discarded bwrap's own stderr.
    expect(body).toMatch(/max_user_namespaces/);
    expect(body).toMatch(/SOLEUR_PREFLIGHT_CHECK10_NOSANDBOX/);
    expect(body).toMatch(/enableWeakerNestedSandbox|nested user namespace/i);
  });

  test("F4b the git common dir is bound read-only, and only when it is outside the repo", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    const body = check10![0];
    // Resolve it the way git itself does — `.git/` string-concatenation is wrong
    // in a worktree, where `.git` is a file rather than a directory.
    expect(body).toMatch(/GIT_COMMON_DIR="\$\(git rev-parse --path-format=absolute --git-common-dir\)"/);
    // Conditional: in a NON-worktree checkout the common dir is already inside
    // $REPO_ROOT, and binding it again is redundant.
    expect(body).toMatch(/if \[\[ "\$GIT_COMMON_DIR" != "\$REPO_ROOT"\/\* \]\]/);
    // READ-ONLY — a writable bind would reopen the .git/hooks/pre-commit
    // write-back escalation that `/soleur:ship` would then execute with the
    // operator's real $HOME.
    expect(body).toMatch(/GIT_BIND=\(--ro-bind "\$GIT_COMMON_DIR" "\$GIT_COMMON_DIR"\)/);
    expect(body).not.toMatch(/GIT_BIND=\(--bind "\$GIT_COMMON_DIR"/);
  });

  test("F5 no unsandboxed fallback survives in Check 10", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    expect(check10).not.toBeNull();
    // The pre-#7393 unsandboxed exec line must be gone: an `env -i ... timeout`
    // that is not wrapped by bwrap is exactly the fallback this design forbids.
    const execLines = check10![0]
      .split("\n")
      .filter((l) => /^DT_OUT=\$\(/.test(l));
    expect(execLines.length).toBe(1);
    expect(execLines[0]).toMatch(/bwrap|BWRAP/);
  });

  test("F6 AC16 — exactly one PASS terminal survives the matrix growth", () => {
    const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
    const rows = check10![0].match(/^\|\s*\d+\s*\|/gm) ?? [];
    expect(rows.length).toBeGreaterThanOrEqual(11);
    const passRows =
      check10![0].match(/^\|\s*\d+\s*\|[^\n]*\*\*PASS\*\*/gm) ?? [];
    expect(passRows.length).toBe(1);
    // SKIP-DECLARED is its own terminal, never folded into ordinary SKIP.
    expect(check10![0]).toMatch(/\*\*SKIP-DECLARED\*\*/);
  });

  test("F7 AC13 — SKIP-DECLARED is visible headless and in the Phase 2 aggregate", () => {
    // The global headless contract says "on PASS/SKIP continue silently"; a
    // terminal that exists only to be reviewable must not be silenced by it.
    const headless = skill.match(/On all PASS[^\n]*\n/);
    expect(headless).not.toBeNull();
    expect(headless![0]).toMatch(/SKIP-DECLARED/);
  });

  test("F8 the retired denylist is documented as retired, not silently deleted", () => {
    // Keeping the retired control named (and its limitation) is what stops a
    // future reader re-deriving it. The Sharp Edge must survive.
    expect(skill).toMatch(/PROBE_VERB_ALLOWLIST/);
    expect(skill).toMatch(/every allowlist entry is an authority grant/i);
  });
});

describe("#7393 G — credentials_required corpus baseline", () => {
  // AC14: every new adoption of the waiver must be a reviewable diff line rather
  // than invisible drift. The anchor is a PARSED declaration inside a plan's
  // `## Observability` block — never a bare `grep -c credentials_required:`,
  // which counts the prose in the plan that INTRODUCED the field (measured: 5
  // line-hits, 0 declarations) and would read as adoption that never happened.
  //
  // 0 -> 1 on 2026-08-11 (#7440). THIS IS THE REVIEWABLE DIFF LINE THE COMMENT ABOVE
  // ASKS FOR — the first genuine adoption of the waiver.
  //
  // Declaring plan: `2026-08-11-fix-registry-zot-log-shipping-plan.md`. Confirmed
  // intentional against this gate's own instruction (delete a stray line, baseline only a
  // genuine one) on three counts:
  //   1. PLACEMENT — it is a correctly-indented child of the `discoverability_test:`
  //      sub-block, not a leftover template comment or a stray top-level line.
  //   2. TRUTH — the probe it describes
  //      (`scripts/followthroughs/zot-log-channel-7440.sh`) reads the Better Stack Logs
  //      ClickHouse warehouse, which needs BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}.
  //   3. NO SUBSTITUTE — the warehouse exposes no public read surface, and the property
  //      under test is "a row reached THIS specific source", which is unverifiable from
  //      outside it. So this is not a probe that could have been written credential-free.
  // Note the waiver is orthogonal to `hr-observability-as-plan-quality-gate`'s no-SSH
  // requirement, which that probe satisfies: it is a warehouse query, not a host login.
  //
  // 1 -> 2 on 2026-08-13 (#7462/#7516). Second genuine adoption, same warehouse.
  //
  // Declaring plan: `2026-08-12-fix-inngest-zot-primary-bootstrap-pull-plan.md` (archived
  // by that PR's compound step; this walk is deliberately recursive, so `archive/` counts
  // — an archived plan's waiver is still an adopted waiver). Confirmed intentional on the
  // same three counts:
  //   1. PLACEMENT — a correctly-indented child of the `discoverability_test:` sub-block,
  //      verified by parsing rather than by grep (a bare grep also hits the plan that
  //      INTRODUCED the field, which declares nothing).
  //   2. TRUTH — the probe is
  //      `doppler run -p soleur -c prd_terraform -- scripts/betterstack-query.sh --since 1h
  //      --grep inngest_zot --grep inngest_ghcr_fallback`, i.e. the SAME Better Stack
  //      ClickHouse warehouse as the entry above, needing the same
  //      BETTERSTACK_QUERY_{HOST,USERNAME,PASSWORD}. The script is committed and +x, and
  //      the equivalent query was executed successfully during that PR's review.
  //   3. NO SUBSTITUTE — the dedicated inngest host (10.0.1.40) is deny-all-public and
  //      not SSH-inspectable by policy, and its ONLY off-box channel is a direct-curl POST
  //      to that warehouse. The property under test is "this host's boot markers reached
  //      that source", which is unverifiable from outside it. Also a warehouse query, not
  //      a host login, so the no-SSH requirement is satisfied.
  //
  // WHY THIS SURFACED LATE, so the next reader does not misdiagnose it as archival drift:
  // the declaration landed with the plan at the branch's first commit, but every CI run on
  // that branch until the last was CANCELLED by the next push, so this gate never completed
  // until then. Measured both ways — the count is 2 with the plan at its live path and 2
  // with it archived; the move is not the cause.
  const BASELINE_DECLARED_PROBES = 2;

  test("G1 the number of plans declaring credentials_required equals the baseline", () => {
    const plansDir = join(import.meta.dir, "..", "..", "..", "knowledge-base", "project", "plans");
    // RECURSIVE. `readdirSync` alone is non-recursive, and per-feature
    // subdirectories are an established shape in this tree
    // (`plans/feat-one-shot-reconcile-no-workspace-match/`, plus `archive/`),
    // so a flat walk left the drift control with a live blind spot: a declaring
    // plan one directory down was simply invisible to the baseline.
    const walk = (dir: string): string[] =>
      readdirSync(dir, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory()
          ? walk(join(dir, e.name))
          : e.name.endsWith(".md")
            ? [join(dir, e.name)]
            : [],
      );
    const declaring = walk(plansDir).filter((f) => {
      const body = readFileSync(f, { encoding: "utf8" });
      const block = extractObservabilityBlock(body);
      return block !== "" && parseCredentialsRequired(block) !== "";
    });
    expect(
      declaring.length,
      `plans declaring credentials_required: ${JSON.stringify(declaring)}. FIRST confirm each declaration is intentional — a leftover template comment or a stray line outside the discoverability_test sub-block must be DELETED, not baselined. Only if every declaration is genuine does raising this baseline become the reviewable diff line the waiver's drift control depends on.`,
    ).toBe(BASELINE_DECLARED_PROBES);
  });
});

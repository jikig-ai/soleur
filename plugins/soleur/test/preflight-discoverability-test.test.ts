import { describe, expect, test } from "bun:test";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import {
  classifyDiscoverabilityResult,
  EMITTER_ALLOWLIST_PATHSPECS,
  extractAllObservabilityBlocks,
  extractObservabilityBlock,
  matchExpected,
  parseCommand,
  parseExpected,
  parseKind,
  parseMarker,
  runLogSubstRejectReason,
  sshRejectReason,
  stripShellComments,
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
    // The negated word class, NOT `[[:space:]]`. A whitespace-only delimiter
    // misses `|ssh`, `;ssh`, `&&ssh`, `"ssh"` — and cannot be mirrored in JS
    // without `\s`-vs-`[[:space:]]` Unicode drift.
    expect(skill).toMatch(
      /\(\^\|\[\^A-Za-z0-9_\.-\]\)ssh\(\[\^A-Za-z0-9_\.-\]\|\$\)/,
    );
    expect(skill).not.toMatch(/\(\^\|\[\[:space:\]\]\|\/\)ssh/);
  });

  test("Both Form A and Form B parser shapes are documented inside Check 10", () => {
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    expect(check10Block![0]).toMatch(/Form A/);
    expect(check10Block![0]).toMatch(/Form B/);
  });

  test("decision matrix row count MATCHES the prose header, with one PASS terminal", () => {
    // F10: `rows.length >= 12` never cross-checked the prose. A `>=` bound
    // passes when a row is added and the header is not updated (and vice
    // versa), so the two could drift silently in both directions. Derive the
    // expected count from the header and assert EQUALITY.
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    const header = check10Block![0].match(
      /Decision matrix \((\d+) states, (\d+) PASS terminal\)/,
    );
    expect(header).not.toBeNull();
    const declaredStates = Number(header![1]);
    const declaredPass = Number(header![2]);

    const rows = check10Block![0].match(/^\|\s*\d+\s*\|/gm) ?? [];
    expect(rows.length).toBe(declaredStates);

    // Row numbers must be 1..N with no gaps or duplicates — a renumbering slip
    // would otherwise still satisfy a bare count.
    const numbers = rows.map((r) => Number(r.match(/\d+/)![0]));
    expect(numbers).toEqual(
      Array.from({ length: declaredStates }, (_, i) => i + 1),
    );

    const passRows =
      check10Block![0].match(/^\|\s*\d+\s*\|[^\n]*\*\*PASS\*\*/gm) ?? [];
    expect(passRows.length).toBe(declaredPass);
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

  test("guardrail 4 restricts the emitter grep to the executing-surface allowlist", () => {
    // A two-entry blacklist (`:!knowledge-base/project/{plans,specs}`) was
    // self-satisfiable — every OTHER author-controlled file counted, including
    // this suite's own fixtures. The allowlist inverts the burden. Asserted
    // against the shared EMITTER_ALLOWLIST_PATHSPECS constant so the two copies
    // cannot drift, not against hand-copied literals.
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    expect(check10Block).not.toBeNull();
    expect(check10Block![0]).toMatch(/git grep[^\n]*-F -- "\$MARKER"/);
    for (const spec of EMITTER_ALLOWLIST_PATHSPECS) {
      expect(check10Block![0]).toContain(`'${spec}'`);
    }
    // The self-satisfiable blacklist must be gone, not merely supplemented.
    expect(check10Block![0]).not.toMatch(/':!knowledge-base\/project\/plans'/);
  });

  test("F7: every guardrail-4 pathspec is cwd-independent (`:(top)`)", () => {
    // A bare `knowledge-base/project/plans` pathspec is CWD-relative: run from
    // `knowledge-base/project/` it silently stops covering what it names. The
    // PR's original test only grepped SKILL.md for the literal strings, so it
    // passed with the cwd-dependent form too. Assert the PROPERTY instead.
    for (const spec of EMITTER_ALLOWLIST_PATHSPECS) {
      expect(spec.startsWith(":(top)")).toBe(true);
    }
    const check10Block = skill.match(
      /### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m,
    );
    const grepLine = check10Block![0]
      .split("\n")
      .find((l) => l.includes('git grep -q -F -- "$MARKER"'));
    expect(grepLine).toBeDefined();
    // No pathspec on the runtime's grep line may lack the `:(top)` prefix.
    const pathspecs = grepLine!.match(/'[^']+'/g) ?? [];
    expect(pathspecs.length).toBeGreaterThan(0);
    for (const p of pathspecs) {
      expect(p.startsWith("':(top)")).toBe(true);
    }
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

// ---------------------------------------------------------------------------
// F2 — bash ↔ TS logic-parity guard.
//
// THE DEFECT THIS EXISTS TO KILL: every test above this block exercises the
// TypeScript MIRROR. The bash in SKILL.md is the production runtime. Mutating
// the bash — turning all seven guardrail `exit 1`s into `:`, widening the
// marker charset to `^.+$`, inverting the command-names-marker predicate,
// deleting guardrail 7's block, making the run-log terminal emit `PASS:` —
// left the 85-test suite fully green. Seven guards that structurally cannot
// fail, inside the deliverable whose thesis is that guards must be able to fail.
//
// Shape follows the precedent named in plugins/soleur/AGENTS.md: "a presence
// grep is insufficient — the copy that runs must match the copy that is
// tested" (plan-review/lib/named-panel.mjs + plan-review-named-panel.test.ts).
// Full normalized equivalence is impossible across two LANGUAGES, so this guard
// has two halves:
//
//   (a) PREDICATE PARITY — for each decision literal that exists in both
//       copies, extract it from each SOURCE FILE and compare after normalizing
//       away only the escapes bash ERE requires and JS does not. Not a presence
//       grep: the two literals must be equal.
//   (b) EXECUTABLE STRUCTURE — assert the properties a mutation destroys:
//       every FAIL diagnostic is followed by a real `exit 1`, each predicate
//       appears in NON-COMMENT text with the correct polarity, and the run-log
//       terminal emits SKIP and never PASS.
// ---------------------------------------------------------------------------
describe("F2: the bash runtime and the TS mirror cannot silently drift", () => {
  const skill = readFileSync(SKILL_PATH, { encoding: "utf8" });
  const parserSrc = readFileSync(
    join(import.meta.dir, "lib", "discoverability-test-parser.ts"),
    { encoding: "utf8" },
  );

  const check10 = skill.match(/### Check 10:[\s\S]*?(?=^### Check \d+|^## )/m);
  if (!check10) throw new Error("Check 10 section not found in preflight/SKILL.md");

  /** Every fenced code block inside Check 10, concatenated. */
  const fencedSource = (check10![0].match(/```(?:bash|text)\n[\s\S]*?```/g) ?? [])
    .map((f) => f.replace(/^```(?:bash|text)\n/, "").replace(/```$/, ""))
    .join("\n");

  /**
   * Lines of the runtime that ACTUALLY EXECUTE — full-line `#` comments and
   * blanks removed. Every assertion below runs against this, never against the
   * raw text: a predicate that survives only inside a comment is a predicate
   * that does not run, which is precisely the mutation class this guard hunts.
   */
  const execLines = fencedSource
    .split("\n")
    .filter((l) => l.trim() !== "" && !/^\s*#/.test(l));
  const execText = execLines.join("\n");

  /**
   * Normalize away escapes that bash ERE requires inside `[[ =~ ]]` but a JS
   * regex literal does not. Nothing else is touched — in particular `\|`,
   * `\$` and `\(` survive, so an actual alternation/anchor difference between
   * the copies still fails the comparison.
   *
   * The newline alternative is a SPELLING difference, not a predicate one, and
   * the two runtimes cannot spell it the same way. POSIX ERE does not define
   * `\n` as an escape, so bash must write `$'\n'` — ANSI-C quoting expands it to
   * a real newline character before the regex is parsed. JS regex literals do
   * define `\n`. Both match exactly one newline; folding them here keeps the
   * guard sensitive to real drift instead of red on an unavoidable difference.
   * Do NOT "fix" this by putting a bare `\n` in the bash: it matches a literal
   * `n` on some EREs, silently dropping newline from the reject set.
   */
  const norm = (re: string): string =>
    re.replace(/\\([;&<>`])/g, "$1").replace(/\$'\\n'/g, "\\n");

  /** The ERE from the bash `[[ … =~ <ERE> ]]` line matching `anchor`. */
  const bashEre = (anchor: string | RegExp): string => {
    const line = execLines.find((l) =>
      typeof anchor === "string" ? l.includes(anchor) : anchor.test(l),
    );
    if (!line) return "";
    const m = line.match(/=~\s+(.+?)\s+\]\]/);
    return m ? norm(m[1]) : "";
  };

  /** The pattern body of `const <name> = /…/flags;` in the TS mirror. */
  const tsRe = (name: string): string => {
    const m = parserSrc.match(
      new RegExp(`^const ${name} = /(.*)/[a-z]*;$`, "m"),
    );
    return m ? norm(m[1]) : "";
  };

  // ---- (a) predicate parity: same literal in both copies ----

  // Anchors are chosen to be unique across the two substitution rejects, which
  // are otherwise near-identical: only guardrail 8 has `\|\||\&|\$` (no bare
  // `|`/`>`/`<` alternatives), only Step 10.5 has `\|\||\||\>`.
  const ANCHOR_RUNLOG = "\\|\\||\\&|\\$";
  const ANCHOR_SUBST = "\\|\\||\\||\\>";
  const PARITY: Array<[label: string, tsName: string, bashAnchor: string]> = [
    ["ssh reject", "SSH_REJECT_RE", '"$CMD" =~ (^|[^A-Za-z0-9_.-])ssh'],
    ["marker charset", "MARKER_CHARSET_RE", '"$MARKER" =~'],
    ["run-log endorsement reject", "RUNLOG_SUBST_REJECT_RE", ANCHOR_RUNLOG],
    ["live-probe substitution reject", "SUBST_REJECT_RE", ANCHOR_SUBST],
  ];

  for (const [label, tsName, anchor] of PARITY) {
    test(`${label}: the bash literal and the TS literal are identical`, () => {
      const ts = tsRe(tsName);
      const bash = bashEre(anchor);
      expect(ts).not.toBe(""); // the TS literal must be extractable
      expect(bash).not.toBe(""); // the bash literal must be extractable
      expect(bash).toBe(ts);
    });
  }

  test("guardrail 8 is strictly narrower than the live-probe reject", () => {
    // The whole point of a separate run-log reject: bare `|`, `<`, `>` must be
    // ALLOWED (the canonical `gh run view <run-id> --log | grep MARKER` needs
    // them) while `;`, `&&`, `||`, `&`, `$…` are not. If someone "simplifies"
    // by pointing guardrail 8 at SUBST_REJECT_RE, the feature breaks.
    expect(tsRe("RUNLOG_SUBST_REJECT_RE")).not.toBe(tsRe("SUBST_REJECT_RE"));
    expect(runLogSubstRejectReason("gh run view <run-id> --log | grep M")).toBeNull();
    expect(substRejectReason("gh run view <run-id> --log | grep M")).not.toBeNull();
  });

  // ---- (b) executable structure: the properties each mutation destroys ----

  test("MUTATION `exit 1` → `:` — every FAIL diagnostic is followed by a real exit 1", () => {
    // Kills the mutation that neuters all seven (now eight) guardrails at once.
    // A guard that prints FAIL and returns 0 is not a guard.
    const failEchoes = execLines
      .map((l, i) => [l, i] as const)
      .filter(([l]) => /echo "FAIL:/.test(l));
    expect(failEchoes.length).toBeGreaterThanOrEqual(8);
    for (const [line, i] of failEchoes) {
      // `exit 1` on the diagnostic's own line (the `|| { echo …; exit 1; }`
      // shape) or within the next two executable lines (the `if … then` shape).
      const window = [line, ...execLines.slice(i + 1, i + 3)].join("\n");
      expect(
        /(^|\s)exit 1\s*(;|$)/m.test(window),
        `FAIL diagnostic is not paired with an executable \`exit 1\`: ${line.trim()}`,
      ).toBe(true);
    }
  });

  test("MUTATION charset → `^.+$` — guardrail 3 runs the real charset predicate", () => {
    expect(execText).toContain('[[ ! "$MARKER" =~ ^[A-Za-z0-9_]+$ ]]');
    expect(bashEre('"$MARKER" =~')).toBe("^[A-Za-z0-9_]+$");
  });

  test("MUTATION invert guardrail 5 — the command-names-marker polarity is pinned", () => {
    // `!=` is the only correct polarity: FAIL when the command does NOT name
    // the marker. Inverting to `==` FAILs every valid run-log and passes every
    // invalid one, and left the mirror-only suite green.
    expect(execText).toContain('[[ "$CMD_CODE" != *"$MARKER"* ]]');
    expect(execText).not.toMatch(/\[\[ "\$CMD(_CODE)?" == \*"\$MARKER"\* \]\]/);
    // Comment-stripped, per F5 — the raw $CMD must NOT be the tested value.
    expect(execText).toMatch(/CMD_CODE=\$\(printf[^\n]*sed[^\n]*#/);
  });

  test("MUTATION delete guardrail 7 — the marker-without-run-log block is executable", () => {
    expect(execText).toMatch(
      /\[\[ "\$KIND" != "run-log" && "\$HAS_MARKER_TOKEN" -gt 0 \]\]/,
    );
  });

  test("MUTATION SKIP → PASS — the run-log terminal emits SKIP and never PASS", () => {
    expect(execText).toMatch(/echo "SKIP: discoverability_test declares kind: run-log/);
    expect(execText).not.toMatch(/echo "PASS:/);
    // The terminal must exit 0 (a SKIP), not fall through into the live probe.
    const skipIdx = execLines.findIndex((l) => /echo "SKIP: discoverability_test declares kind: run-log/.test(l));
    expect(skipIdx).toBeGreaterThan(-1);
    expect(execLines[skipIdx + 1].trim()).toBe("exit 0");
  });

  test("MUTATION drop the emitter allowlist — guardrail 4's grep is restricted", () => {
    const grepLine = execLines.find((l) =>
      l.includes('git grep -q -F -- "$MARKER"'),
    );
    expect(grepLine).toBeDefined();
    for (const spec of EMITTER_ALLOWLIST_PATHSPECS) {
      expect(grepLine!).toContain(`'${spec}'`);
    }
  });

  test("MUTATION reorder — kind resolution stays between the two rejects, in the EXECUTABLE text", () => {
    // The prose-index version of this test (above) compares positions in the
    // raw markdown, so a comment mentioning the reject would satisfy it. This
    // one runs against executable lines only.
    const idx = (needle: string) =>
      execLines.findIndex((l) => l.includes(needle));
    const ssh = idx('"$CMD" =~ (^|[^A-Za-z0-9_.-])ssh');
    const kind = idx("KIND=$(grep -oE");
    const subst = idx(ANCHOR_SUBST);
    expect(ssh).toBeGreaterThan(-1);
    expect(kind).toBeGreaterThan(ssh);
    expect(subst).toBeGreaterThan(kind);
  });

  test("the mirror's SSOT contract is stated in both files", () => {
    expect(parserSrc).toMatch(/the bash wins and this file\s*\n?\s*\*?\s*is the bug/);
    expect(check10![0]).toMatch(/If they drift, the bash wins/);
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
      ...EMITTER_ALLOWLIST_PATHSPECS,
    ]).stdout.toString();
    expect(out.trim().length).toBeGreaterThan(0);
    expect(out).toMatch(/apps\/web-platform\/infra\//);
  });
});

// ---------------------------------------------------------------------------
// F1 — the run-log arm reopened the ssh reject, and endorsed shell-active
// commands. Both halves are regressions RELATIVE TO origin/main: on main the
// fused reject ran ssh + substitution unconditionally, so `|ssh` tripped the
// substitution rule's `|`. Moving the substitution reject below the run-log
// branch removed that accidental cover.
// ---------------------------------------------------------------------------
describe("F1a: the ssh reject survives every delimiter, not just whitespace", () => {
  const SSH_SHAPES: Array<[fixture: string, cmd: string]> = [
    ["17-run-log-piped-ssh.md", "gh run view 1 --log|ssh box grep SOLEUR_TEST_MARKER_09"],
    ["18-run-log-semicolon-ssh.md", "gh run view 1 --log;ssh box grep SOLEUR_TEST_MARKER_09"],
    ["19-run-log-andand-ssh.md", "gh run view 1 --log&&ssh box grep SOLEUR_TEST_MARKER_09"],
    ["20-run-log-spaced-semicolon-ssh.md", "gh run view 1 --log ; ssh box grep SOLEUR_TEST_MARKER_09"],
    ["21-run-log-quoted-ssh.md", '"ssh" box grep SOLEUR_TEST_MARKER_09'],
  ];

  for (const [fixture, cmd] of SSH_SHAPES) {
    test(`fixture ${fixture} → FAIL on ssh (every guardrail otherwise satisfied)`, async () => {
      const result = await classify(fx(fixture), { markerLookup: () => true });
      expect(`${fixture}:${result.result}`).toBe(`${fixture}:FAIL`);
      expect(result.reason).toMatch(/ssh/i);
    });

    test(`sshRejectReason fires directly on: ${cmd}`, () => {
      expect(sshRejectReason(cmd)).not.toBeNull();
    });
  }

  test("the widened class does NOT create false positives", () => {
    // `sshd`, `pushshell` and identifiers containing `ssh` must still pass —
    // `.`, `-` and `_` remain word characters.
    for (const safe of [
      "systemctl status sshd",
      "grep pushshell /var/log/x",
      "gh run view <run-id> --log | grep SOLEUR_ssh_x",
      "curl https://ssh.example.com.invalid/health",
      "curl https://x/health",
    ]) {
      expect(`${safe}:${sshRejectReason(safe)}`).toBe(`${safe}:null`);
    }
  });

  test("the reject is not delegated to the substitution rule (which no longer runs here)", () => {
    // On origin/main `|ssh` was caught only because the substitution reject ran
    // unconditionally and tripped on `|`. Prove the ssh rule stands alone:
    // strip every shell-active token and it must STILL fire.
    expect(sshRejectReason('"ssh" box grep M')).not.toBeNull();
    expect(runLogSubstRejectReason('"ssh" box grep M')).toBeNull();
  });
});

describe("F1b: guardrail 8 — a run-log SKIP must not endorse a chaining/expanding command", () => {
  test("fixture 22: command substitution → FAIL, and NOT via a marker guardrail", async () => {
    const result = await classify(fx("22-run-log-command-substitution.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/endorse/i);
    expect(result.reason).not.toMatch(/does not contain that literal/);
  });

  test("fixture 23: `&& curl …?d=$TOKEN` → FAIL even though every marker guardrail passes", async () => {
    const result = await classify(fx("23-run-log-chained-exfil.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/endorse/i);
  });

  test("MANY chaining/expansion shapes all FAIL under run-log", async () => {
    const bad = [
      "gh run view 1 --log | grep SOLEUR_M; curl https://attacker.example",
      "gh run view 1 --log | grep SOLEUR_M && rm -rf /tmp/x",
      "gh run view 1 --log | grep SOLEUR_M || curl https://attacker.example",
      "gh run view 1 --log | grep SOLEUR_M &",
      "gh run view $(id) --log | grep SOLEUR_M",
      "gh run view `id` --log | grep SOLEUR_M",
      "gh run view <(id) --log | grep SOLEUR_M",
      "gh run view >(id) --log | grep SOLEUR_M",
      "gh run view 1 --log | grep SOLEUR_M?t=$TOKEN",
      "gh run view 1 --log | grep SOLEUR_M?t=${SUPABASE_SERVICE_ROLE_KEY}",
    ];
    for (const cmd of bad) {
      const result = await classify(
        yamlPlan([
          "kind: run-log",
          "marker: SOLEUR_M",
          `command: ${cmd}`,
          'expected_output: "row"',
        ]),
        { markerLookup: () => true },
      );
      expect(`${cmd}:${result.result}`).toBe(`${cmd}:FAIL`);
    }
  });

  test("bare `|`, `<`, `>` are STILL allowed — the canonical run-log shape survives", async () => {
    // If guardrail 8 were the full live-probe reject, this would FAIL and the
    // feature would be dead on its own canonical example.
    const result = await classify(
      yamlPlan([
        "kind: run-log",
        "marker: SOLEUR_M",
        "command: gh run view <run-id> --log | grep SOLEUR_M",
        'expected_output: "row"',
      ]),
      { markerLookup: () => true },
    );
    expect(result.result).toBe("SKIP");
    expect(result.marker).toBe("SOLEUR_M");
  });

  test("guardrail 8 does not leak into live-probe (which has its own, wider reject)", async () => {
    // A live-probe with `|` must still FAIL — via the Step 10.5 reject.
    const result = await classify(
      yamlPlan([
        "kind: live-probe",
        "command: curl https://app.soleur.ai/health | sh",
        'expected_output: "200"',
      ]),
    );
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/shell-active/i);
  });
});

describe("F3: quote charset follows the bash, which accepts `\"` only", () => {
  test("fixture 24: `kind: 'run-log'` FAILs, matching the bash runtime", async () => {
    const result = await classify(fx("24-single-quoted-kind.md"), {
      markerLookup: () => true,
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/kind/i);
  });

  test("double quotes parse; single quotes do not (both keys)", () => {
    expect(parseKind(yamlPlan(['kind: "run-log"']))).toBe("run-log");
    expect(parseKind(yamlPlan(["kind: 'run-log'"]))).toBeNull();
    expect(parseMarker(yamlPlan(['marker: "SOLEUR_M"']))).toBe("SOLEUR_M");
    expect(parseMarker(yamlPlan(["marker: 'SOLEUR_M'"]))).toBe("'SOLEUR_M'");
  });

  test("a single-quoted marker is malformed, never silently unquoted", async () => {
    const result = await classify(
      yamlPlan([
        "kind: run-log",
        "marker: 'SOLEUR_M'",
        "command: gh run view <run-id> --log | grep SOLEUR_M",
        'expected_output: "row"',
      ]),
      { markerLookup: () => true },
    );
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/malformed/i);
  });
});

describe("F4: the single-block runtime view anchors `## Observability` exactly", () => {
  const CITATION_FIRST = [
    "# Plan",
    "",
    "## Observability layer citation",
    "",
    "Per hr-observability-layer-citation, errors surface in Sentry.",
    "",
    "## Observability",
    "",
    "```yaml",
    "discoverability_test:",
    "  command: curl -fsS https://app.soleur.ai/health",
    '  expected_output: "200"',
    "```",
    "",
    "## Acceptance Criteria",
  ].join("\n");

  const SUFFIXED_ONLY = [
    "# Plan",
    "",
    "## Observability / Rollback",
    "",
    "Roll back by reverting the deploy; alerts fire in Better Stack.",
    "",
    "## Acceptance Criteria",
  ].join("\n");

  test("a `## Observability layer citation` section does not shadow the real block", () => {
    // Measured before the fix: bash extracted the real block (PASS), the
    // prefix-matching mirror extracted the citation (FAIL).
    const block = extractObservabilityBlock(CITATION_FIRST);
    expect(block).toMatch(/discoverability_test/);
    expect(block).not.toMatch(/hr-observability-layer-citation/);
  });

  test("`## Observability / Rollback` alone yields NO block, exactly as the awk does", () => {
    // Measured before the fix: bash yielded 0 bytes (FAIL), the mirror yielded
    // 251 bytes and parsed on. That shape exists on disk today.
    expect(extractObservabilityBlock(SUFFIXED_ONLY)).toBe("");
  });

  test("a suffixed-heading plan therefore FAILs on the missing block, not on a parse", async () => {
    const result = await classifyDiscoverabilityResult({
      planPath: "fixtures/synthetic-suffixed.md",
      planBody: SUFFIXED_ONLY,
      prBody: "knowledge-base/project/plans/fixtures/synthetic-suffixed.md",
      runner: stubExecutor(0, "200\n"),
    });
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/missing the ## Observability block/);
  });

  test("extractAllObservabilityBlocks KEEPS the prefix form for its second consumer", () => {
    // The schema-parity guard walks plan-issue-templates.md's per-tier
    // sections, whose headings are suffixed. Anchoring that view would break it.
    expect(extractAllObservabilityBlocks(CITATION_FIRST).length).toBe(2);
    expect(extractAllObservabilityBlocks(SUFFIXED_ONLY).length).toBe(1);
  });

  test("the runtime awk in SKILL.md is anchored too (the mirror follows it)", () => {
    const skill = readFileSync(SKILL_PATH, { encoding: "utf8" });
    expect(skill).toMatch(/awk '\/\^## Observability\$\/\{ino=1; next\}/);
  });
});

describe("F5: guardrail 5 rejects a marker mentioned only in a comment", () => {
  test("fixture 25: block scalar whose only marker mention is commented out → FAIL", async () => {
    const result = await classify(
      fx("25-run-log-block-scalar-commented-marker.md"),
      { markerLookup: () => true },
    );
    expect(result.result).toBe("FAIL");
    expect(result.reason).toMatch(/outside of shell comments/);
  });

  test("the fixture really is a block scalar carrying the marker in its raw text", () => {
    // Pins WHY the old check passed: Form A block scalars keep `#` lines, so
    // the raw command DOES contain the marker literal.
    const block = extractObservabilityBlock(
      fx("25-run-log-block-scalar-commented-marker.md"),
    );
    const cmd = parseCommand(block);
    expect(cmd).toContain("SOLEUR_TEST_MARKER_25");
    expect(cmd).toMatch(/^\s*#/m);
  });

  test("MANY comment-only mention shapes all FAIL", async () => {
    const commentedOnly = [
      "echo unrelated\n# SOLEUR_M",
      "echo unrelated\n  # grep SOLEUR_M would show it",
      "echo unrelated # SOLEUR_M",
    ];
    for (const cmd of commentedOnly) {
      const result = await classify(
        [
          "## Observability",
          "",
          "```yaml",
          "discoverability_test:",
          "  kind: run-log",
          "  marker: SOLEUR_M",
          '  expected_output: "row"',
          "  command: |",
          ...cmd.split("\n").map((l) => `    ${l.replace(/^\s+/, "")}`),
          "```",
        ].join("\n"),
        { markerLookup: () => true },
      );
      expect(`${JSON.stringify(cmd)}:${result.result}`).toBe(
        `${JSON.stringify(cmd)}:FAIL`,
      );
      expect(result.reason).toMatch(/outside of shell comments/);
    }
  });

  test("an executable mention still passes — the fix is not a blanket reject", async () => {
    const result = await classify(
      [
        "## Observability",
        "",
        "```yaml",
        "discoverability_test:",
        "  kind: run-log",
        "  marker: SOLEUR_M",
        '  expected_output: "row"',
        "  command: |",
        "    # find the marker in the run log",
        "    gh run view <run-id> --log | grep SOLEUR_M",
        "```",
      ].join("\n"),
      { markerLookup: () => true },
    );
    expect(result.result).toBe("SKIP");
    expect(result.marker).toBe("SOLEUR_M");
  });

  test("a `#` glued to a non-space character is a URL fragment, not a comment", () => {
    // `https://x/y#SOLEUR_M` must keep the marker: stripping it would create a
    // false FAIL, the opposite failure mode.
    expect(
      stripShellComments("curl https://x/y#SOLEUR_M"),
    ).toContain("SOLEUR_M");
    expect(stripShellComments("echo x # SOLEUR_M")).not.toContain("SOLEUR_M");
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
    expect(substRejectReason(cmd) ?? "").toMatch(/shell-active|refusing/i);
  });

  // R2 [both] — CPO CONDITION C1. This PR is what makes these commands
  // executable: before the fix they parsed to the literal `>` and self-rejected
  // at the shell-active gate. Folding joins with a SPACE and introduces no
  // shell-active token, so the Step 10.5 reject does NOT cover them — the
  // credentialed-CLI reject at Step 10.4 is the load-bearing control.
  // `env -i` does not scrub the Doppler token: $HOME is preserved and the CLI
  // reads a live dp.ct.* credential from its on-disk config under ~/.doppler/.
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
    expect(substRejectReason(cmd.replace(/^doppler\b/, "curl"))).toBeNull();
    expect(substRejectReason(cmd) ?? "").toMatch(/credentialed CLI/i);
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
      expect(substRejectReason(cmd) ?? "").toMatch(/credentialed CLI/i);
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
      expect(substRejectReason(cmd) ?? "").not.toMatch(/credentialed CLI/i);
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
  const gateWindow = (anchor: RegExp): string => {
    const lines = skill.split("\n");
    const idx = lines.findIndex((l) => anchor.test(l) && /^if \[\[ "\$CMD/.test(l));
    expect(idx).toBeGreaterThan(-1); // anchor must resolve to the executable line
    return lines.slice(Math.max(0, idx - 6), idx + 4).join("\n");
  };
  const credGate = () => gateWindow(/CMD_DEQ/);
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

  test("Step 10.4 carries the credentialed-CLI reject (CPO condition C1)", () => {
    const g = credGate();
    // The verb set, anchored inside the gate fence.
    expect(g).toMatch(/\(doppler\|gh\|aws\|supabase\|stripe/);
    // The word boundaries that keep `curl https://host/gh-pages` runnable.
    expect(g).toMatch(/\(\^\|\[\[:space:\]\]\|\/\)/);
    // The gate must test the DEQUOTED copy — `"doppler"` / `\doppler` /
    // `dopp""ler` all resolve to the same binary and bypassed the raw match.
    expect(g).toMatch(/CMD_DEQ="\$\{CMD\/\//);
    expect(g).toMatch(/\[\[ "\$CMD_DEQ" =~ /);
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

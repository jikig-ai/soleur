/**
 * Reference implementation of preflight Check 10's parser + classifier.
 *
 * The production runtime is the bash in `plugins/soleur/skills/preflight/SKILL.md`
 * §"Check 10: Discoverability Test Execution". This TypeScript mirror exists
 * so the decision matrix can be unit-tested without subshells, fake `curl`,
 * or live network. If the bash and TS drift, the bash wins and this file
 * is the bug.
 */

export type ExecResult = { rc: number; stdout: string };
export type Executor = (cmd: string, timeoutMs: number) => Promise<ExecResult>;

/**
 * `discoverability_test.kind` — which property Check 10 is able to observe.
 *
 * - `live-probe` (the default when `kind:` is absent) — today's behaviour,
 *   byte-for-byte: the command is executed and its output matched.
 * - `run-log` — the evidence lives in a run log that does not exist yet at
 *   preflight time (e.g. `gh run view <run-id> --log`). Check 10 declines to
 *   execute and returns SKIP **with the marker recorded**, so a post-merge
 *   follow-through can assert it.
 *
 * `run-log` is not a weakening: guardrails 4 and 5 (below) require that a real
 * emitter for the marker exists in the tree and that the declared command
 * actually names it — assertions the live-probe path never makes.
 */
export type DiscoverabilityKind = "live-probe" | "run-log";

export type ClassificationResult = {
  result: "PASS" | "FAIL" | "SKIP";
  reason?: string;
  /** Set only on a valid `kind: run-log` SKIP — the recorded marker literal. */
  marker?: string;
};

export type ClassifyInput = {
  planPath: string;
  planBody: string;
  prBody: string;
  runner: Executor;
  timeoutMs?: number;
  /**
   * Guardrail 4's oracle: does an emitter for `marker` exist in the tree
   * OUTSIDE planning artifacts? Injected so this module stays pure and so
   * fixtures 09 (emitter present) and 11 (emitter absent) — which are
   * otherwise byte-identical in shape — are distinguishable.
   *
   * The production runtime supplies
   *   git grep -F -- "$MARKER" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs'
   * The exclusions are load-bearing: the plan declaring the marker is itself in
   * the tree, so without them the check always matches and is vacuous.
   *
   * Defaults to fail-closed (`() => false`) — an omitted oracle must never
   * silently satisfy the guardrail.
   */
  markerLookup?: (marker: string) => boolean;
};

// Use POSIX [:space:] equivalent (not \s) so the TS reject regex behaves
// identically to bash's [[:space:]] in C-locale. \s in JS matches Unicode
// whitespace (U+00A0, U+2028, etc.); bash [[:space:]] in C-locale does not.
// Keeping the surface narrow avoids cross-runtime drift bypasses.
const SSH_REJECT_RE = /(^|[\t\n\r \f\v/])ssh([\t\n\r \f\v]|$)/;

// Shell-active tokens that route command output / chain commands / spawn
// subshells / expand vars. The plan author is trust-on-PR-review but the env
// scrub in SKILL.md Step 10.5 is the load-bearing mitigation — this regex
// is defense-in-depth. Note: `$` (parameter expansion) IS rejected to block
// `curl https://api.example.com/?leak=$TOKEN` even with env scrub.
const SUBST_REJECT_RE = /(\$\(|`|<\(|>\(|;|&&|\|\||\||>|<|&|\$\{?[A-Za-z_])/;

// Return the body of EVERY `## Observability` section (each: lines after the
// heading up to the next `^## ` heading). A doc may carry several such sections
// (e.g. plan-issue-templates.md ships one per verbosity tier), which the
// schema-parity guard walks. `extractObservabilityBlock` below is the
// first-block-only view the preflight runtime consumes.
export function extractAllObservabilityBlocks(planBody: string): string[] {
  const lines = planBody.split(/\r?\n/);
  const blocks: string[] = [];
  let collected: string[] | null = null;
  for (const line of lines) {
    if (/^## Observability(?:\s|$)/.test(line)) {
      if (collected) blocks.push(collected.join("\n"));
      collected = [];
      continue;
    }
    if (collected && /^## /.test(line)) {
      blocks.push(collected.join("\n"));
      collected = null;
      continue;
    }
    if (collected) collected.push(line);
  }
  if (collected) blocks.push(collected.join("\n"));
  return blocks;
}

// First `## Observability` section body — the view the preflight runtime consumes
// (plan bodies carry a single such section). NOTE: not byte-identical to a hand-
// written first-only loop for the malformed case of two ADJACENT `## Observability`
// headings with no intervening `^## ` — the old loop merged their bodies, this
// returns only the first. That input does not occur in real plans, so preflight
// behavior is unchanged; the split-then-`[0]` shape is what the parity guard needs.
export function extractObservabilityBlock(planBody: string): string {
  return extractAllObservabilityBlocks(planBody)[0] ?? "";
}

export function parseCommand(observabilityBlock: string): string {
  const lines = observabilityBlock.split(/\r?\n/);

  // Form A — strict YAML key (strongest signal).
  let inBlockScalar = false;
  const blockScalarLines: string[] = [];
  for (const line of lines) {
    if (inBlockScalar) {
      if (/^\s*$/.test(line)) {
        blockScalarLines.push("");
        continue;
      }
      if (/^\s+\S/.test(line)) {
        blockScalarLines.push(line.replace(/^\s+/, ""));
        continue;
      }
      break;
    }
    if (/^\s*command:\s*\|\s*$/.test(line)) {
      inBlockScalar = true;
      continue;
    }
    const inlineKey = line.match(/^\s*command:\s+(\S.*)$/);
    if (inlineKey) return stripQuotes(inlineKey[1].trim());
  }
  if (blockScalarLines.length > 0) return blockScalarLines.join("\n").trim();

  // Form B — prose `discoverability_test` marker + first fenced code block.
  let sawMarker = false;
  let inFence = false;
  const fenceLines: string[] = [];
  for (const line of lines) {
    if (!sawMarker && /discoverability_test/.test(line)) {
      sawMarker = true;
      continue;
    }
    if (!sawMarker) continue;
    if (/^\s*```/.test(line)) {
      if (!inFence) {
        inFence = true;
        continue;
      }
      break;
    }
    if (inFence) {
      if (/^\s*#/.test(line)) continue;
      fenceLines.push(line);
    }
  }
  return fenceLines.join("\n").trim();
}

export function parseExpected(observabilityBlock: string): string {
  const lines = observabilityBlock.split(/\r?\n/);
  for (const line of lines) {
    const yamlKey = line.match(/^\s*expected_output:\s*(.+)$/);
    if (yamlKey) return stripQuotes(yamlKey[1].trim());
  }
  // Prose form accepts bold-wrapped (`**Expected output:**`) since markdown
  // plans frequently bold the inline label. Both `Expected output:` and
  // `**Expected output:**` produce the same captured value.
  for (const line of lines) {
    const prose = line.match(/^\s*(?:\*\*)?Expected output:(?:\*\*)?\s*(.+)$/i);
    if (prose) return stripQuotes(prose[1].trim());
  }
  return "";
}

export function matchExpected(expected: string, actualStdout: string): boolean {
  const normalized = actualStdout.replace(/\n+$/, "").trim();
  if (normalized === "") return false;
  const tokens = tokenizeExpected(expected);
  return tokens.some((tok) => {
    if (tok === "") return false;
    // Short tokens (≤ 2 chars) match only when stdout is exactly the token —
    // prevents `expected_output: "0"` matching every HTTP error response that
    // happens to contain a `0` digit (500, 404, 200, 302, etc.).
    if (tok.length <= 2) return normalized === tok;
    return normalized.includes(tok);
  });
}

export function tokenizeExpected(expected: string): string[] {
  return expected
    .split(/,|\s+or\s+|\bor\b|[`"'\[\]/]+/i)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

/**
 * The SSH reject. Runs UNCONDITIONALLY for every `kind` — see F2 in the plan.
 *
 * This was deliberately split out of the old fused `rejectReason`. If it sat
 * behind the `kind` branch, `kind: run-log` + `command: ssh host 'grep M …'`
 * would return SKIP and `hr-no-ssh-fallback-in-runbooks` would be silently
 * defeated. Never move this below kind resolution.
 */
export function sshRejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }
  return null;
}

/**
 * The shell-substitution reject. Applies to `live-probe` ONLY, because it is a
 * property of *executing* the command — under `run-log` nothing is executed, so
 * the tokens carry no execution risk (a run-log command is characteristically
 * `gh run view <run-id> --log | grep MARKER`, which trips `|`, `<` and `>`).
 *
 * The message string is operator-facing and is asserted verbatim downstream —
 * it enumerates every rejected token. Do not reword it.
 */
export function substRejectReason(cmd: string): string | null {
  if (SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains shell-active token (;, &&, ||, |, >, <, &, $var, $(, `, <(, >() — refusing to run. Plans must compose single-statement commands without chaining or substitution.";
  }
  return null;
}

/**
 * Back-compat wrapper preserving the original fused order for any caller that
 * still wants "reject for either reason". `classifyDiscoverabilityResult` no
 * longer uses it — it calls the two halves at their correct positions.
 */
export function rejectReason(cmd: string): string | null {
  return sshRejectReason(cmd) ?? substRejectReason(cmd);
}

// `kind`/`marker` are Form-A-only sub-fields of `discoverability_test` and MUST
// be indented. A column-0 `kind:` would become a sixth TOP-LEVEL key of the
// `## Observability` schema and break `observability-schema-parity.test.ts`'s
// `CANONICAL.length === 5` (plus three sibling assertions) — so the strict
// parsers below require leading whitespace, and the loose token detectors
// deliberately DO match a column-0 or prose form so it FAILs loudly (guardrail 6)
// rather than being silently ignored.
const KIND_STRICT_RE = /^[ \t]+kind:[ \t]*["']?(live-probe|run-log)["']?[ \t]*$/m;
const MARKER_STRICT_RE = /^[ \t]+marker:[ \t]*["']?([^\s"']*)["']?[ \t]*$/m;

// "a line whose first meaningful token is a `kind`/`marker` key", tolerating
// list bullets, blockquotes and bold decoration. Narrow enough not to fire on
// incidental prose like "this kind of check".
const KIND_TOKEN_RE = /^[ \t]*(?:[->*]+[ \t]*)*\**[ \t]*kind[ \t]*\**[ \t]*:/im;
const MARKER_TOKEN_RE = /^[ \t]*(?:[->*]+[ \t]*)*\**[ \t]*marker[ \t]*\**[ \t]*:/im;

/** The declared kind, or null if absent OR present-but-unparseable. */
export function parseKind(
  observabilityBlock: string,
): DiscoverabilityKind | null {
  const m = observabilityBlock.match(KIND_STRICT_RE);
  return m ? (m[1] as DiscoverabilityKind) : null;
}

/** Whether SOME `kind` key token appears — the guardrail-6 fail-closed trigger. */
export function hasKindToken(observabilityBlock: string): boolean {
  return KIND_TOKEN_RE.test(observabilityBlock);
}

/**
 * The declared marker, RAW — malformed values are returned as-is so the
 * classifier (not the parser) owns the charset verdict and can name the bad
 * value in its diagnostic.
 */
export function parseMarker(observabilityBlock: string): string | null {
  const m = observabilityBlock.match(MARKER_STRICT_RE);
  return m ? m[1] : null;
}

/** Whether SOME `marker` key token appears — the guardrail-7 fail-closed trigger. */
export function hasMarkerToken(observabilityBlock: string): boolean {
  return MARKER_TOKEN_RE.test(observabilityBlock);
}

const MARKER_CHARSET_RE = /^[A-Za-z0-9_]+$/;

export async function classifyDiscoverabilityResult(
  input: ClassifyInput,
): Promise<ClassificationResult> {
  const {
    planPath,
    planBody,
    runner,
    timeoutMs = 15_000,
    markerLookup = () => false, // fail-closed; see ClassifyInput.markerLookup
  } = input;

  if (!planPath || planBody === "") {
    return {
      result: "SKIP",
      reason:
        "no plan file linked from PR body — Check 10 deferred to next preflight run after PR has a plan link",
    };
  }

  const block = extractObservabilityBlock(planBody);
  if (block === "") {
    return {
      result: "FAIL",
      reason: `plan ${planPath} is missing the ## Observability block (sensitive-path diff requires one per hr-observability-as-plan-quality-gate)`,
    };
  }

  const cmd = parseCommand(block);
  if (cmd === "") {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares an Observability block but no discoverability_test.command could be parsed (see plan-issue-templates.md §Observability for the canonical YAML schema)`,
    };
  }

  // ---- ORDER IS LOAD-BEARING (plan F2). Do not reorder these three stages. ----
  //   1. ssh reject        — ALWAYS, before any `kind` branch
  //   2. kind resolution + guardrails 2-7
  //   3. subst reject      — live-probe only
  // Moving (1) below (2) lets `kind: run-log` + `ssh …` return SKIP, defeating
  // hr-no-ssh-fallback-in-runbooks. That is a LARGER downgrade than the one
  // direction 3 was rejected for.

  // --- Stage 1: the SSH reject, unconditionally, for both kinds. ---
  const sshRejected = sshRejectReason(cmd);
  if (sshRejected !== null) return { result: "FAIL", reason: sshRejected };

  // --- Stage 2: kind resolution + guardrails 2-7. ---

  const kindDeclared = parseKind(block);

  // Guardrails 2 + 6: a `kind` token that the strict Form-A parser cannot read
  // is malformed — an unknown value, a prose `Kind:`, or a column-0 key. Fail
  // loudly. Never fall back to live-probe: an author who wrote `kind:` believes
  // they declared something, and silently ignoring it is the downgrade.
  if (kindDeclared === null && hasKindToken(block)) {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares a discoverability_test kind that could not be parsed. \`kind:\` is Form A only (a strictly INDENTED sub-field of \`discoverability_test:\`) and must be exactly \`live-probe\` or \`run-log\`. A prose or column-0 \`kind\` is refused rather than defaulted.`,
    };
  }

  // Guardrail 1: absent `kind` means live-probe — every pre-existing plan
  // behaves exactly as it did before this field existed.
  const kind: DiscoverabilityKind = kindDeclared ?? "live-probe";

  // Guardrail 7: a `marker:` outside `kind: run-log` is consumed by nothing. It
  // signals an author who thinks they declared a run-log test. Fail, don't ignore.
  if (kind !== "run-log" && hasMarkerToken(block)) {
    return {
      result: "FAIL",
      reason: `plan ${planPath} declares a discoverability_test marker but kind is \`${kind}\` — \`marker:\` is only meaningful under \`kind: run-log\` and nothing consumes it otherwise. Either set \`kind: run-log\` or remove the marker.`,
    };
  }

  if (kind === "run-log") {
    const marker = parseMarker(block);

    // Guardrail 3: run-log without a well-formed marker records nothing, so
    // nothing downstream could ever assert anything — strictly worse than a FAIL.
    if (marker === null || !MARKER_CHARSET_RE.test(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` but its discoverability_test marker is ${marker === null ? "missing" : `malformed (${JSON.stringify(marker)})`}. \`marker:\` is required under run-log and must match ^[A-Za-z0-9_]+$ so a post-merge follow-through can grep for it.`,
      };
    }

    // Guardrail 4: the marker must have a REAL emitter in the tree, outside
    // planning artifacts. Without the plans/specs exclusion this check is
    // vacuous — the plan declaring the marker is itself in the tree.
    if (!markerLookup(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` with marker ${marker}, but no emitter for it exists in the tree outside knowledge-base/project/{plans,specs}. A run-log test may only be declared once something actually emits the marker (git grep -F -- "${marker}" -- ':!knowledge-base/project/plans' ':!knowledge-base/project/specs').`,
      };
    }

    // Guardrail 5: the command must actually name the marker, else run-log
    // would certify a command with nothing to do with the recorded evidence.
    if (!cmd.includes(marker)) {
      return {
        result: "FAIL",
        reason: `plan ${planPath} declares \`kind: run-log\` with marker ${marker}, but its discoverability_test command does not contain that literal. The command must be the one that surfaces the marker.`,
      };
    }

    // Valid run-log. SKIP — not PASS: the gate must never certify a property it
    // did not observe. Per
    // knowledge-base/project/learnings/2026-04-27-preflight-security-gates-skip-vs-fail-defaults.md
    // SKIP is correct only when truly indeterminate, and a run that has not
    // executed yet is genuinely indeterminate.
    return {
      result: "SKIP",
      marker,
      reason: `discoverability_test declares \`kind: run-log\` with marker ${marker}; the evidence lives in a run log that does not exist at preflight time, so the probe is deferred rather than run. Verified statically: an emitter for ${marker} exists in the tree and the command names it.`,
    };
  }

  // --- Stage 3: the substitution reject — live-probe only (nothing is executed
  // under run-log, so these tokens carry no execution risk there). ---
  const substRejected = substRejectReason(cmd);
  if (substRejected !== null) return { result: "FAIL", reason: substRejected };

  const expected = parseExpected(block);
  const result = await runner(cmd, timeoutMs);

  if (result.rc === 6) {
    return {
      result: "FAIL",
      reason: `command failed DNS resolution (curl rc=6 — hostname did not resolve). Verify the hostname in plan ${planPath}'s discoverability_test.command.`,
    };
  }

  if (result.rc === 28 || result.rc === 124) {
    return {
      result: "FAIL",
      reason: `command timed out after ${timeoutMs} ms (rc=${result.rc}). Either the endpoint is unreachable or the command lacks --max-time.`,
    };
  }

  if (result.rc === 22 && /401|403/.test(result.stdout)) {
    const tokens = tokenizeExpected(expected);
    const listsAuth = tokens.some((t) => /401|403/.test(t));
    if (!listsAuth) {
      return {
        result: "SKIP",
        reason: `auth-gated probe returned ${result.stdout.trim()} but expected_output does not list 401/403. Add the auth shape to expected_output OR provision Doppler creds for the probe variant.`,
      };
    }
  }

  if (!matchExpected(expected, result.stdout)) {
    return {
      result: "FAIL",
      reason: `stdout mismatch: command returned ${JSON.stringify(result.stdout.trim())}, expected_output was ${JSON.stringify(expected)} (rc=${result.rc}). Plan's expectation has drifted from production reality.`,
    };
  }

  return { result: "PASS" };
}

function stripQuotes(value: string): string {
  return value.replace(/^["'](.*)["']$/, "$1");
}

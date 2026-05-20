/**
 * Reference implementation of preflight Check 10's parser + classifier.
 *
 * The production runtime is the bash in `plugins/soleur/skills/preflight/SKILL.md`
 * §"Check 10: Discoverability Test Execution". This TypeScript mirror exists
 * so the 8 decision states can be unit-tested without subshells, fake `curl`,
 * or live network. If the bash and TS drift, the bash wins and this file
 * is the bug.
 */

export type ExecResult = { rc: number; stdout: string };
export type Executor = (cmd: string, timeoutMs: number) => Promise<ExecResult>;

export type ClassificationResult = {
  result: "PASS" | "FAIL" | "SKIP";
  reason?: string;
};

export type ClassifyInput = {
  planPath: string;
  planBody: string;
  prBody: string;
  runner: Executor;
  timeoutMs?: number;
};

const SSH_REJECT_RE = /(^|[\s/])ssh([\s]|$)/;
const SUBST_REJECT_RE = /(\$\(|`|<\(|>\()/;

export function extractObservabilityBlock(planBody: string): string {
  const lines = planBody.split(/\r?\n/);
  const collected: string[] = [];
  let inBlock = false;
  for (const line of lines) {
    if (/^## Observability(?:\s|$)/.test(line)) {
      inBlock = true;
      continue;
    }
    if (inBlock && /^## /.test(line)) break;
    if (inBlock) collected.push(line);
  }
  return collected.join("\n");
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
  for (const line of lines) {
    const prose = line.match(/^\s*Expected output:\s*(.+)$/i);
    if (prose) return stripQuotes(prose[1].trim());
  }
  return "";
}

export function matchExpected(expected: string, actualStdout: string): boolean {
  const normalized = actualStdout.replace(/\n+$/, "").trim();
  if (normalized === "") return false;
  const tokens = tokenizeExpected(expected);
  return tokens.some((tok) => tok !== "" && normalized.includes(tok));
}

export function tokenizeExpected(expected: string): string[] {
  return expected
    .split(/,|\s+or\s+|\bor\b|[`"'\[\]/]+/i)
    .map((s) => s.trim())
    .filter((s) => s.length > 0);
}

export function rejectReason(cmd: string): string | null {
  if (SSH_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains ssh (rule violation per hr-observability-as-plan-quality-gate)";
  }
  if (SUBST_REJECT_RE.test(cmd)) {
    return "discoverability_test.command contains command or process substitution; refusing to run (defense-in-depth)";
  }
  return null;
}

export async function classifyDiscoverabilityResult(
  input: ClassifyInput,
): Promise<ClassificationResult> {
  const { planPath, planBody, runner, timeoutMs = 15_000 } = input;

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

  const rejected = rejectReason(cmd);
  if (rejected !== null) return { result: "FAIL", reason: rejected };

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

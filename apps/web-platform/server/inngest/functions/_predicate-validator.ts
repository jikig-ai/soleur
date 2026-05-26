// SSRF hardening — Layer 3 defense for cron-follow-through-monitor (#4068).
//
// Validates predicate URLs server-side BEFORE the LLM agent runs.
// The agent no longer has Bash(curl:*) or Bash(dig:*) — all network
// predicates are executed here with strict validation:
//   1. HTTPS-only, no userinfo in URL
//   2. Host must be in ALLOWED_PREDICATE_HOSTS (Set.has() exact match)
//   3. Resolved IP must be public (ipaddr.js range() === "unicast")
//   4. Fetch with redirect: "error" and 10s timeout
//
// Follows the Set.has() pattern from agent-runner.ts (FILE_TOOLS_TO_REMOVE).

import { promises as dnsPromises } from "node:dns";
import * as ipaddr from "ipaddr.js";

// --- Public allowlist (Set.has() exact match) --------------------------------

export const ALLOWED_PREDICATE_HOSTS = new Set([
  "app.soleur.ai",
  "api.github.com",
  "api.doppler.com",
]);

// --- IP validation -----------------------------------------------------------

/**
 * Returns true if the IP is a public unicast address.
 * Fail-closed: any parse error or non-unicast range returns false.
 */
export function isPublicIp(ip: string): boolean {
  try {
    const addr = ipaddr.process(ip);
    return addr.range() === "unicast";
  } catch {
    return false;
  }
}

// --- URL validation ----------------------------------------------------------

export interface UrlValidationResult {
  valid: boolean;
  reason?: string;
}

/**
 * Validates a predicate URL for SSRF safety:
 *   - Must be HTTPS
 *   - Must not contain userinfo (user:pass@)
 *   - Hostname must be in ALLOWED_PREDICATE_HOSTS
 *   - Resolved IP must be public unicast (not private/loopback/link-local)
 */
export async function validatePredicateUrl(
  rawUrl: string,
): Promise<UrlValidationResult> {
  let parsed: URL;
  try {
    parsed = new URL(rawUrl);
  } catch {
    return { valid: false, reason: "Malformed URL" };
  }

  // HTTPS only
  if (parsed.protocol !== "https:") {
    return { valid: false, reason: `Protocol must be HTTPS, got ${parsed.protocol}` };
  }

  // No userinfo
  if (parsed.username || parsed.password) {
    return { valid: false, reason: "URL must not contain userinfo (user:pass@)" };
  }

  // Host allowlist — strip IPv6 brackets before comparison
  const hostname = parsed.hostname.replace(/^\[|\]$/g, "");
  if (!ALLOWED_PREDICATE_HOSTS.has(hostname)) {
    return {
      valid: false,
      reason: `Host "${hostname}" not in allowlist: ${[...ALLOWED_PREDICATE_HOSTS].join(", ")}`,
    };
  }

  // DNS resolution — verify resolved IP is public
  try {
    const { address } = await dnsPromises.lookup(hostname);
    if (!isPublicIp(address)) {
      return {
        valid: false,
        reason: `Resolved IP ${address} is not a public unicast address`,
      };
    }
  } catch (err) {
    return {
      valid: false,
      reason: `DNS lookup failed for ${hostname}: ${(err as Error).message}`,
    };
  }

  return { valid: true };
}

// --- HTTP predicate execution ------------------------------------------------

export interface HttpPredicateResult {
  passed: boolean;
  statusCode: number | null;
  error?: string;
}

/**
 * Executes an http-200 predicate: fetches the URL and checks for status 200.
 * Uses redirect: "error" (no following redirects) and 10s timeout.
 */
export async function executeHttpPredicate(
  url: string,
): Promise<HttpPredicateResult> {
  try {
    const response = await fetch(url, {
      redirect: "error",
      signal: AbortSignal.timeout(10_000),
    });
    return {
      passed: response.status === 200,
      statusCode: response.status,
    };
  } catch (err) {
    return {
      passed: false,
      statusCode: null,
      error: (err as Error).message,
    };
  }
}

// --- DNS predicate execution -------------------------------------------------

export interface DnsPredicateResult {
  passed: boolean;
  result?: string[];
  error?: string;
}

const DNS_TIMEOUT_MS = 10_000;

/**
 * Executes a DNS predicate (dns-txt or dns-a).
 * For dns-txt: resolves TXT records and checks if any contains `expected`.
 * For dns-a: resolves A records and checks if any matches `expected`.
 */
export async function executeDnsPredicate(
  type: "dns-txt" | "dns-a",
  domain: string,
  expected: string,
): Promise<DnsPredicateResult> {
  try {
    const ac = new AbortController();
    const timer = setTimeout(() => ac.abort(), DNS_TIMEOUT_MS);

    try {
      if (type === "dns-txt") {
        const records = await dnsPromises.resolveTxt(domain);
        // resolveTxt returns string[][] — each record is an array of chunks
        const flat = records.map((chunks) => chunks.join(""));
        const passed = flat.some((r) => r.includes(expected));
        return { passed, result: flat };
      } else {
        const addresses = await dnsPromises.resolve4(domain);
        const passed = addresses.includes(expected);
        return { passed, result: addresses };
      }
    } finally {
      clearTimeout(timer);
    }
  } catch (err) {
    return {
      passed: false,
      error: (err as Error).message,
    };
  }
}

// --- Predicate YAML parsing --------------------------------------------------

export type PredicateType =
  | "http-200"
  | "dns-txt"
  | "dns-a"
  | "manual"
  | "api-curl"
  | "cli"
  | "auto";

export interface ParsedPredicate {
  issueNumber: number;
  issueTitle: string;
  type: PredicateType;
  url?: string;
  domain?: string;
  expected?: string;
  slaBusinessDays: number;
}

/**
 * Parses the `<!-- soleur:followthrough ... -->` YAML-like directives from an
 * issue body. Falls back to extracting the YAML code block after `## Verification`.
 *
 * Returns null if no predicate block is found.
 */
export function parsePredicateYaml(
  issueBody: string,
  issueNumber: number,
  issueTitle: string,
): ParsedPredicate | null {
  if (!issueBody) return null;

  // Try HTML comment format first: <!-- soleur:followthrough type: http-200 url: ... -->
  const commentMatch = issueBody.match(
    /<!--\s*soleur:followthrough\s+([\s\S]*?)-->/,
  );

  // Try YAML code block after ## Verification heading
  const verificationMatch = issueBody.match(
    /## Verification\s*\n+```(?:ya?ml)?\s*\n([\s\S]*?)```/,
  );

  const yamlSource = commentMatch?.[1] ?? verificationMatch?.[1];
  if (!yamlSource) return null;

  // Simple YAML-like key: value parser (no nested structures needed).
  // Handles both multi-line YAML and single-line "key: value key2: value2"
  // formats (the HTML comment form is often single-line).
  const fields: Record<string, string> = {};
  const lines = yamlSource.split("\n");
  for (const line of lines) {
    // Multi-line: each line is "key: value"
    const kv = line.match(/^\s*(\w[\w_-]*)\s*:\s*(.+?)\s*$/);
    if (kv) {
      // Check if this is actually multiple key:value pairs on one line
      // by looking for "key: value key2: value2" pattern
      const multiKv = line.matchAll(/(\w[\w_-]*)\s*:\s*(\S+)/g);
      let count = 0;
      for (const m of multiKv) {
        fields[m[1]] = m[2];
        count++;
      }
      if (count === 0) {
        fields[kv[1]] = kv[2];
      }
    }
  }

  const rawType = fields["type"] ?? "manual";
  const knownTypes: PredicateType[] = [
    "http-200",
    "dns-txt",
    "dns-a",
    "manual",
    "api-curl",
    "cli",
    "auto",
  ];
  const type: PredicateType = knownTypes.includes(rawType as PredicateType)
    ? (rawType as PredicateType)
    : "manual";

  return {
    issueNumber,
    issueTitle,
    type,
    url: fields["url"],
    domain: fields["domain"],
    expected: fields["expected"],
    slaBusinessDays: parseInt(fields["sla_business_days"] ?? "5", 10) || 5,
  };
}

// --- Orchestrator ------------------------------------------------------------

export interface ValidatedPredicate {
  issueNumber: number;
  issueTitle: string;
  type: PredicateType;
  validationResult?: UrlValidationResult;
  executionResult?: HttpPredicateResult | DnsPredicateResult;
  skipped?: boolean;
  skipReason?: string;
}

export interface IssueData {
  number: number;
  title: string;
  body: string;
}

/**
 * Validates and executes predicates for a list of issues.
 * - http-200: validates URL, then executes
 * - dns-txt / dns-a: executes directly (no URL to validate, uses domain)
 * - manual / api-curl / cli / auto: skipped (agent handles these)
 */
export async function validateAndExecutePredicates(
  issues: IssueData[],
): Promise<ValidatedPredicate[]> {
  const results: ValidatedPredicate[] = [];

  for (const issue of issues) {
    const parsed = parsePredicateYaml(issue.body, issue.number, issue.title);

    if (!parsed) {
      results.push({
        issueNumber: issue.number,
        issueTitle: issue.title,
        type: "manual",
        skipped: true,
        skipReason: "No predicate block found in issue body",
      });
      continue;
    }

    if (parsed.type === "http-200") {
      if (!parsed.url) {
        results.push({
          issueNumber: parsed.issueNumber,
          issueTitle: parsed.issueTitle,
          type: parsed.type,
          skipped: true,
          skipReason: "http-200 predicate missing url field",
        });
        continue;
      }

      const validation = await validatePredicateUrl(parsed.url);
      if (!validation.valid) {
        results.push({
          issueNumber: parsed.issueNumber,
          issueTitle: parsed.issueTitle,
          type: parsed.type,
          validationResult: validation,
        });
        continue;
      }

      const execution = await executeHttpPredicate(parsed.url);
      results.push({
        issueNumber: parsed.issueNumber,
        issueTitle: parsed.issueTitle,
        type: parsed.type,
        validationResult: validation,
        executionResult: execution,
      });
    } else if (parsed.type === "dns-txt" || parsed.type === "dns-a") {
      if (!parsed.domain || !parsed.expected) {
        results.push({
          issueNumber: parsed.issueNumber,
          issueTitle: parsed.issueTitle,
          type: parsed.type,
          skipped: true,
          skipReason: `${parsed.type} predicate missing domain or expected field`,
        });
        continue;
      }

      const execution = await executeDnsPredicate(
        parsed.type,
        parsed.domain,
        parsed.expected,
      );
      results.push({
        issueNumber: parsed.issueNumber,
        issueTitle: parsed.issueTitle,
        type: parsed.type,
        executionResult: execution,
      });
    } else {
      // manual, api-curl, cli, auto — agent handles these
      results.push({
        issueNumber: parsed.issueNumber,
        issueTitle: parsed.issueTitle,
        type: parsed.type,
        skipped: true,
        skipReason: `Type "${parsed.type}" handled by agent, not pre-validated`,
      });
    }
  }

  return results;
}

// --- Formatter ---------------------------------------------------------------

/**
 * Formats predicate results as markdown for injection into the agent prompt.
 */
export function formatPredicateResults(
  results: ValidatedPredicate[],
): string {
  if (results.length === 0) {
    return "No predicate results to report.";
  }

  const lines: string[] = [
    "## Pre-Validated Predicate Results",
    "",
    "The following predicates were validated and executed server-side.",
    "Use these results directly — do NOT re-execute network requests.",
    "",
    "| Issue | Type | Status | Details |",
    "|-------|------|--------|---------|",
  ];

  for (const r of results) {
    const issue = `#${r.issueNumber}`;
    const type = r.type;

    if (r.skipped) {
      lines.push(`| ${issue} | ${type} | SKIPPED | ${r.skipReason ?? ""} |`);
      continue;
    }

    if (r.validationResult && !r.validationResult.valid) {
      lines.push(
        `| ${issue} | ${type} | BLOCKED | URL validation failed: ${r.validationResult.reason ?? ""} |`,
      );
      continue;
    }

    if (r.executionResult) {
      if ("statusCode" in r.executionResult) {
        // HTTP predicate
        const http = r.executionResult as HttpPredicateResult;
        const status = http.passed ? "PASSED" : "FAILED";
        const detail = http.error
          ? `Error: ${http.error}`
          : `HTTP ${http.statusCode}`;
        lines.push(`| ${issue} | ${type} | ${status} | ${detail} |`);
      } else {
        // DNS predicate
        const dns = r.executionResult as DnsPredicateResult;
        const status = dns.passed ? "PASSED" : "FAILED";
        const detail = dns.error
          ? `Error: ${dns.error}`
          : `Records: ${(dns.result ?? []).join(", ")}`;
        lines.push(`| ${issue} | ${type} | ${status} | ${detail} |`);
      }
    }
  }

  lines.push("");
  return lines.join("\n");
}

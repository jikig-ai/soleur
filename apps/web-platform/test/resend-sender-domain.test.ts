import { execFileSync } from "node:child_process";
import { readFileSync } from "node:fs";
import { describe, expect, it } from "vitest";

/**
 * Resend only accepts mail from a domain carrying its verification records (a
 * DKIM TXT at `resend._domainkey.<domain>` and the bounce subdomain
 * `send.<domain>`). soleur.ai carries both; jikigai.com carries neither, so a
 * send whose sender sits on it is rejected by the vendor outright.
 *
 * Not hypothetical: the GHA->Inngest port (#4227, 2026-05-21) moved two cron
 * alert paths onto a jikigai.com sender, and neither inspected the response, so
 * both channels were dead for 111 days while reporting success.
 *
 * SCOPE, stated so a green run is not read as more than it is. This covers the
 * SENDER half of deliverability — a send the vendor will refuse. It CANNOT see
 * recipient-side non-delivery: a bounce at the recipient MX returns 2xx from
 * Resend. The `to:` on these paths is still on jikigai.com, whose DNS is
 * mid-migration (#7995), and nothing here detects that breaking.
 *
 * Every source read is comment-stripped before matching: a source-scanning
 * guard that matched against prose would be satisfied by its own explanatory
 * comments, and this file necessarily discusses the domain it guards against.
 */
/**
 * Sender domains Resend will actually accept, i.e. those carrying its
 * verification records. This is an ALLOWLIST on purpose. A denylist of the one
 * domain that broke answers "is it jikigai.com again", which is a narrower
 * question than the one this file's name asks — a third unverified domain would
 * pass it. Verified live 2026-09-09: soleur.ai carries a DKIM TXT at
 * `resend._domainkey` and SPF+MX at `send`; outbound.soleur.ai is the separate
 * verified cold-send subdomain (ADR/#5325). Adding a domain here is a claim that
 * it carries those records — check before you add one.
 */
const VERIFIED_SENDER_DOMAINS = new Set(["soleur.ai", "outbound.soleur.ai"]);

/** `Name <local@domain>` or a bare address -> domain, lowercased. */
function domainOf(sender: string): string | null {
  const m = sender.match(/@([A-Za-z0-9.-]+)>?\s*$/);
  return m ? m[1].toLowerCase().replace(/>$/, "") : null;
}

/** Raw `fetch` against the REST endpoint. */
const RAW_FETCH_PATTERN = "api\\.resend\\.com/emails";
/**
 * The SDK surface. Invisible to the pattern above and equally able to send.
 * Matched as a FIXED string: `git grep` defaults to BRE, where `\(` opens a
 * capture group rather than matching a paren, so the regex form of this
 * pattern silently matches nothing.
 */
const SDK_PATTERN = "emails.send(";

/**
 * Send sites that legitimately resolve no static sender, each with its reason.
 * A site reaching zero extracted senders and NOT listed here FAILS: an
 * unresolvable sender is an unchecked sender, and the two are otherwise
 * indistinguishable in a green run.
 */
const UNRESOLVED_SENDER_ACK: Record<string, string> = {
  "apps/web-platform/test/email-brand-compliance.test.ts":
    "assertion-only — inspects senders, emits none",
};

function repoRoot(): string {
  return execFileSync("git", ["rev-parse", "--show-toplevel"], {
    encoding: "utf8",
  }).trim();
}

function grepFiles(root: string, pattern: string, fixed: boolean): string[] {
  const args = ["grep", "-l"];
  if (fixed) args.push("-F");
  args.push("--", pattern, ":!knowledge-base/");
  try {
    return execFileSync("git", args, {
      cwd: root,
      encoding: "utf8",
      maxBuffer: 1 << 20,
    })
      .split("\n")
      .filter(Boolean);
  } catch {
    // `git grep` exits 1 on zero matches. Returning [] lets the set assertion
    // below report a collapsed enumeration instead of throwing at collection,
    // where the failure surfaces as an opaque "Command failed".
    return [];
  }
}

const NOT_THIS_GUARD = (p: string) => !p.endsWith("resend-sender-domain.test.ts");

/** Every tracked file that can send through Resend, by either surface. */
function resendSendSites(root: string): string[] {
  return [
    ...new Set([
      ...grepFiles(root, RAW_FETCH_PATTERN, false),
      ...grepFiles(root, SDK_PATTERN, true),
    ]),
  ]
    .filter(NOT_THIS_GUARD)
    .sort();
}

/** Files sending via raw `fetch` — where the response is ours to inspect. */
function rawFetchSites(root: string): string[] {
  return grepFiles(root, RAW_FETCH_PATTERN, false)
    .filter((p) => p.endsWith(".ts"))
    .filter(NOT_THIS_GUARD)
    .sort();
}

/** Strip line and block comments so no assertion can be met by prose. */
function stripComments(source: string): string {
  return source
    .replace(/\/\*[\s\S]*?\*\//g, "")
    .split("\n")
    .map((l) => l.replace(/(^|\s)(\/\/|#).*$/, "$1"))
    .join("\n");
}

/**
 * Extract sender addresses by CONSTRUCT, never by proximity. An earlier version
 * matched any quoted `@` string on a line mentioning "from", which read the
 * RECIPIENT out of the jq payload `{from: $from, to: ["…"], …}` and reported it
 * as a sender — too broad in exactly the direction no fixture covered.
 */
function sendersIn(source: string): string[] {
  const src = stripComments(source);
  const found: string[] = [];
  const patterns = [
    /(?:^|[\s{,])from:\s*"([^"\n]+)"/gm, // object literal
    /--arg\s+from\s+"([^"\n]+)"/gm, // jq payload construction
    /\bfrom\s*=\s*(?:[^;\n]*\?\?\s*)?"([^"\n]+)"/gm, // variable, incl. env default
    /\b[A-Z_]*FROM\s*=\s*"([^"\n]+)"/gm, // module-level constant
  ];
  for (const re of patterns) {
    for (const m of src.matchAll(re)) found.push(m[1]);
  }
  return found;
}

describe("Resend sender domain", () => {
  const root = repoRoot();
  const sites = resendSendSites(root);
  const rawSites = rawFetchSites(root);

  it("enumerates every Resend send surface", () => {
    // The SET, not a cardinality floor. A floor cannot see a substitution, and
    // one set well below the real count tolerates most of the enumeration
    // vanishing. Pinning the set makes a new send site a reviewable diff line.
    expect(sites).toEqual([
      ".github/actions/notify-ops-email/action.yml",
      ".github/workflows/scheduled-prod-version-drift.yml",
      ".github/workflows/web-platform-release.yml",
      "apps/web-platform/infra/container-restart-monitor.sh",
      "apps/web-platform/infra/cron-egress-alarm.sh",
      "apps/web-platform/infra/disk-monitor.sh",
      "apps/web-platform/infra/resource-monitor.sh",
      "apps/web-platform/server/email-triage/outbound.ts",
      "apps/web-platform/server/inngest/functions/cron-bug-fixer.ts",
      "apps/web-platform/server/inngest/functions/cron-email-ingress-probe.ts",
      "apps/web-platform/server/inngest/functions/cron-github-app-drift-guard.ts",
      "apps/web-platform/server/inngest/functions/cron-oauth-probe.ts",
      "apps/web-platform/server/notifications.ts",
      "apps/web-platform/test/email-brand-compliance.test.ts",
    ]);
  });

  it("never sends from a domain without Resend verification records", () => {
    const offenders: string[] = [];
    for (const rel of sites) {
      for (const sender of sendersIn(readFileSync(`${root}/${rel}`, "utf8"))) {
        const domain = domainOf(sender);
        if (domain === null) {
          offenders.push(`${rel}: unparseable sender ${sender}`);
        } else if (!VERIFIED_SENDER_DOMAINS.has(domain)) {
          offenders.push(`${rel}: from=${sender} (domain ${domain} not verified)`);
        }
      }
    }
    expect(offenders).toEqual([]);
  });

  it("resolves a sender for every send site, or acknowledges why not", () => {
    // Totality. Without it, a site whose sender the extractor cannot parse is
    // indistinguishable from one that passed — which is how the first version
    // of this guard cleared cron-bug-fixer.ts, the single site whose sender is
    // runtime-overridable and therefore the one most worth reading.
    const unresolved = sites.filter(
      (rel) =>
        sendersIn(readFileSync(`${root}/${rel}`, "utf8")).length === 0 &&
        !(rel in UNRESOLVED_SENDER_ACK),
    );
    expect(unresolved).toEqual([]);
  });

  it("inspects the Resend response at every raw-fetch send site", () => {
    // Swept across the class rather than pinned to the two files this PR fixed,
    // and anchored on the captured identifier: a bare `.ok` is satisfied by any
    // unrelated `probeResult.ok` in a 900-line file, and by a comment.
    const discarding: string[] = [];
    for (const rel of rawSites) {
      const src = stripComments(readFileSync(`${root}/${rel}`, "utf8"));
      const capture = src.match(
        /(?:const|let)\s+(\w+)\s*=\s*await\s+fetch\(\s*"https:\/\/api\.resend\.com\/emails"/,
      );
      if (!capture) {
        discarding.push(`${rel}: response not captured`);
        continue;
      }
      if (!new RegExp(`!\\s*${capture[1]}\\.ok\\b`).test(src)) {
        discarding.push(`${rel}: captured as '${capture[1]}' but never checked`);
      }
    }
    expect(discarding).toEqual([]);
  });
});

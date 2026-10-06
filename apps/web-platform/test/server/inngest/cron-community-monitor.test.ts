// TR9 PR-11 — cron-community-monitor handler unit tests.
//
// Minimal test coverage focused on the invariants the substrate-extraction
// cohort (PR-5/PR-7/PR-8/PR-9/PR-10) flagged as load-bearing PLUS this
// PR's bucket-ii-specific surface (buildSpawnEnv allowlist widening):
//   1. Registration shape (cron + manual-trigger event triggers, concurrency,
//      retries) — drift here breaks the Inngest scheduler contract.
//   2. Prompt-canary anchors (## Instructions, community-router.sh path,
//      Hacker News / Discord / Bluesky verbs, digest output path) — original
//      anchors from the GHA prompt that must survive silent paraphrasing.
//   3. Safety-guard anchors (platform-persistence directive, "Do NOT push
//      directly to main"). #7122: the agent no longer files the issue or writes
//      the digest, so the MILESTONE RULE, brand-guide, issue-creation,
//      CLONE DEPTH and quotes/contributor/interaction directives are asserted
//      ABSENT below. NOTE: the prompt-level
//      DEDUP RULE was removed in #6143 (same-day dedup is now code-side via
//      digestIssueExistsForDate before the eval spawns) — a regression guard
//      below asserts those three strings stay absent.
//   4. Timing constants exported (MAX_TURN_DURATION_MS, KILL_ESCALATION_MS).
//   5. buildSpawnEnv allowlist — bucket-ii positive class (7 community vars
//      added) AND negative class (9-item sensitive denylist + spread operator).
//      This is the primary security regression detector: additions to the
//      allowlist are caught by code review; widening to a passthrough/denylist
//      shape (e.g., `...process.env`) is caught here.

import { describe, expect, it, vi } from "vitest";

// vi.hoisted runs BEFORE all ES-module imports below — sets NEXT_PHASE so
// the inngest client's startup-key check short-circuits (same path Next.js
// `next build` uses). Mirrors cron-roadmap-review.test.ts.
vi.hoisted(() => {
  process.env.NEXT_PHASE = "phase-production-build";
});

import {
  COMMUNITY_MONITOR_PROMPT,
  cronCommunityMonitor,
  KILL_ESCALATION_MS,
  MAX_TURN_DURATION_MS,
} from "@/server/inngest/functions/cron-community-monitor";
import {
  COMMUNITY_DISALLOWED_TOOLS,
  FINAL_MESSAGE_CAP_BYTES,
} from "@/server/inngest/functions/_cron-claude-eval-substrate";
import {
  COMMUNITY_FAILURE_CAUSES,
  COMMUNITY_FINAL_MESSAGE_MAX_BYTES,
  COMMUNITY_METRICS,
  COMMUNITY_PERIOD_DAYS,
  COMMUNITY_PLATFORMS,
  COMMUNITY_STATUSES,
  COMMUNITY_TOPIC_CATEGORIES,
  buildExampleDraftLine,
  parseCommunityDraft,
} from "@/server/inngest/functions/_cron-community-publication";
import { injectRunDate } from "@/server/inngest/functions/_cron-shared";

describe("cronCommunityMonitor — registration shape (import-time smoke)", () => {
  it("loads without throwing (handler + client startup pass)", () => {
    expect(cronCommunityMonitor).toBeDefined();
    expect(typeof cronCommunityMonitor).toBe("object");
  });
});

describe("cronCommunityMonitor — exported timing constants", () => {
  it("MAX_TURN_DURATION_MS is 50 minutes (cohort budget)", () => {
    expect(MAX_TURN_DURATION_MS).toBe(50 * 60 * 1000);
  });

  it("KILL_ESCALATION_MS is 5 seconds (SIGTERM → SIGKILL grace)", () => {
    expect(KILL_ESCALATION_MS).toBe(5_000);
  });
});

// Source-file-content tests — read the SUT file and assert the prompt
// constant and buildSpawnEnv allowlist contain the verbatim anchors. Per
// AGENTS.md `cq-test-fixtures-synthesized-only`, we read the production
// source via readFileSync rather than synthesising a parallel prompt
// fixture (the prompt + allowlist ARE the artifacts under test).

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const SUT_SOURCE = readFileSync(
  resolve(
    __dirname,
    "../../../server/inngest/functions/cron-community-monitor.ts",
  ),
  "utf-8",
);

// The handler's code with whole-line `//` comments removed. A source anchor that
// matches inside a COMMENT proves nothing about the code (cq-assert-anchor-not-bare-token):
// wrapping the flag lines in a comment must turn the anchors below red. Only whole
// lines are dropped: a block-comment stripper would mangle the prompt template.
function stripLineComments(src: string): string {
  return src
    .split("\n")
    .filter((l) => !l.trim().startsWith("//"))
    .join("\n");
}
const SUT_CODE = stripLineComments(SUT_SOURCE);

describe("cron-community-monitor — turn budget (max-turns exhaustion fix)", () => {
  it("spawns claude with --max-turns 80 (daily-triage parity; was 50)", () => {
    // Root cause of Sentry WEB-PLATFORM-1Z (2026-06-03 08:06 UTC): the spawn
    // exhausted its 50-turn budget ("Error: Reached max turns (50)", exitCode 1,
    // ~6 min elapsed — NOT a wall-clock timeout) before reaching the final
    // issue-create step, so this always-create producer filed no
    // scheduled-community-monitor issue and the output-aware heartbeat
    // (resolveOutputAwareOk, #4714) correctly went RED. 80 matches the
    // proven-healthy cron-daily-triage budget through the same
    // DEFAULT_CLAUDE_SETTINGS. See plan
    // 2026-06-03-fix-cron-community-monitor-max-turns-exhaustion-plan.md.
    expect(SUT_SOURCE).toMatch(/"--max-turns",\s*"80"/);
    expect(SUT_SOURCE).not.toMatch(/"--max-turns",\s*"50"/);
  });
});

describe("#7122 — spawn flags and credential custody (source anchors)", () => {
  it("the agent holds Bash only, and the file tools are also removed from its pool", () => {
    // Comment-stripped: the BEHAVIOURAL proof (the flags handed to spawnClaudeEval)
    // is in cron-community-monitor-publication-flow.test.ts; this is the cheap guard.
    expect(SUT_CODE).toMatch(/"--allowedTools",\s*"Bash",/);
    expect(SUT_CODE).not.toMatch(/"--allowedTools",\s*"Bash,/);
    expect(SUT_CODE).toMatch(/"--disallowedTools",\s*COMMUNITY_DISALLOWED_TOOLS/);
    // Non-vacuity: the same anchor, commented out, no longer matches.
    expect(stripLineComments('  // "--disallowedTools", COMMUNITY_DISALLOWED_TOOLS,\n')).not.toMatch(
      /"--disallowedTools",\s*COMMUNITY_DISALLOWED_TOOLS/,
    );
  });

  it("opts in to the capped final-message capture (the default is off for every other cron)", () => {
    expect(SUT_CODE).toMatch(/captureFinalMessage: true,/);
  });

  it("clones and spawns with the READ token; the WRITE token is minted by a separate post-spawn step", () => {
    expect(SUT_SOURCE).toMatch(/permissions: COMMUNITY_SPAWN_TOKEN_PERMISSIONS,\s*repositories: \[REPO_NAME\]/);
    expect(SUT_SOURCE).toMatch(/permissions: DEFAULT_CRON_TOKEN_PERMISSIONS,\s*repositories: \[REPO_NAME\]/);
    expect(SUT_SOURCE).toContain('step.run("mint-write-token"');
    // The write token reaches safeCommitAndPr only with the rendered bytes it must equal.
    expect(SUT_CODE).toMatch(/expectedContent: \{ \[digestPath\]: renderedDigest \},/);
    expect(SUT_SOURCE).toContain("setOriginToken(spawnCwd, token)");
    expect(SUT_SOURCE).toContain("installationToken: readToken");
    expect(SUT_SOURCE).not.toContain("ISSUE_CREATOR_CRON_TOKEN_PERMISSIONS");
  });

  it("persists by exact path: no directory-prefix allowlist constant remains", () => {
    expect(SUT_SOURCE).not.toContain("COMMUNITY_MONITOR_ALLOWED_PATHS");
    expect(SUT_SOURCE).toMatch(/exactPaths: \[digestPath\]/);
  });
});

// #7122 — replay across a deploy. Memoized step ids are the replay contract: a run
// started under the OLD code (write-scoped mint, old allowlist clone) and re-driven by
// the NEW code would read both back from its memo and run the new prompt under old
// containment. The two steps whose meaning changed therefore carry NEW ids.
describe("#7122 — step ids that changed meaning are new (stale memo is never reused)", () => {
  it("mints and clones under the new ids; the old ids are gone from the handler code", () => {
    expect(SUT_CODE).toContain('"mint-read-token"');
    expect(SUT_CODE).toContain('"setup-workspace-ro"');
    expect(SUT_CODE).not.toContain('"mint-installation-token"');
    expect(SUT_CODE).not.toMatch(/step\.run\(\s*"setup-workspace"/);
  });

  it("the id contract is documented where the ids are defined", () => {
    expect(SUT_SOURCE).toContain("STEP IDS (#7122)");
  });
});

// #7122 — constants mirrored across a module boundary, pinned equal (a drift in either
// direction would be silent: oversize is rejected twice, the tool lists fail safe).
describe("#7122 — mirrored constants stay equal", () => {
  it("the substrate's final-message cap equals the publication module's", () => {
    expect(FINAL_MESSAGE_CAP_BYTES).toBe(COMMUNITY_FINAL_MESSAGE_MAX_BYTES);
    expect(COMMUNITY_FINAL_MESSAGE_MAX_BYTES).toBe(16 * 1024);
  });

  it("--disallowedTools equals the hook's no-file-tools deny set plus NotebookEdit (equality, not subset)", () => {
    const hook = readFileSync(
      resolve(__dirname, "../../../server/inngest/cron-bash-allowlist-hook.mjs"),
      "utf-8",
    );
    const m = /const NO_FILE_TOOL_NAMES = new Set\(\[([\s\S]*?)\]\);/.exec(hook);
    expect(m, "NO_FILE_TOOL_NAMES not found in the hook source").not.toBeNull();
    const hookTools = [...m![1].matchAll(/"([A-Za-z]+)"/g)].map((x) => x[1]);
    expect(hookTools.length).toBeGreaterThanOrEqual(9);
    // NotebookEdit is not a recognised class in the hook (its catch-all denies it), so
    // the CLI layer adds it; every other member must match in BOTH directions.
    const cli = COMMUNITY_DISALLOWED_TOOLS.split(",");
    expect([...cli].filter((t) => t !== "NotebookEdit").sort()).toEqual([...hookTools].sort());
    expect(cli).toContain("NotebookEdit");
  });
});

describe("registration source-shape anchors (cross-check the import-time smoke)", () => {
  it.each([
    ['id: "cron-community-monitor"', "canonical function id"],
    ['cron: "0 8 * * *"', "daily 08:00 UTC schedule"],
    [
      'event: "cron/community-monitor.manual-trigger"',
      "operator manual trigger",
    ],
    ['scope: "fn"', "fn-scoped serialization"],
    // #6143 — the full { scope: "fn", limit: 1 } is now the SOLE same-day TOCTOU
    // guard (the prompt-level DEDUP RULE was removed). Mirror
    // cron-roadmap-review.test.ts's concurrency anchor.
    ['{ scope: "fn", limit: 1 }', "sole same-day dedup serializer (#6143)"],
    ['scope: "account"', "account-shared lane (cron-platform)"],
    ['key: \'"cron-platform"\'', "cross-handler concurrency lane"],
    ["retries: 1", "no retry storm on agent-loop failure"],
  ])("source contains %s (%s)", (anchor) => {
    expect(SUT_SOURCE).toContain(anchor);
  });
});

describe("COMMUNITY_MONITOR_PROMPT — anchor strings (regression-detection)", () => {
  describe("original GHA-workflow prompt anchors (must survive port)", () => {
    it.each([
      ["You are a community monitoring agent", "opening line"],
      ["## Instructions", "section marker"],
      [
        "plugins/soleur/skills/community/scripts/community-router.sh",
        "router path (NOT abbreviated as router.sh)",
      ],
      [
        // #5199 restore: the prompt now writes the LITERAL router path in every
        // invocation (no `ROUTER=` shell-var assignment) so each `bash <router>`
        // matches the containment hook's literal-path allowlist prefix.
        "do NOT assign it to a shell",
        "literal-path containment instruction (no shell-var)",
      ],
      [
        "COMMUNITY_DIGEST_DIR_PATH",
        "digest output directory (re-exported from the publication module, defined once)",
      ],
      // #7122: the dated digest filename, the `## Period` / `## Activity Summary`
      // headings and the issue body are rendered handler-side from fixed templates
      // (asserted in cron-community-publication.test.ts), so they are no longer
      // prompt text. The title prefix is the shared constant the dedup read and the
      // audit fallback use.
      ["titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX", "issue title prefix (shared constant)"],
      ["scheduled-community-monitor", "label name"],
      ["discord messages <channel_id>", "Discord messages invocation (literal verb, prompt-parity)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh discord", "Discord platform invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh github activity", "GitHub activity invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh hn mentions", "Hacker News invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh bsky get-metrics", "Bluesky invocation (literal path)"],
      ["bash plugins/soleur/skills/community/scripts/community-router.sh linkedin fetch-metrics", "LinkedIn fetch-metrics invocation (literal path)"],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  describe("safety-guard anchors (cohort discipline)", () => {
    it.each([
      [
        "Do NOT push directly to main",
        "no direct main writes (handler-side PR persistence)",
      ],
      [
        "PERSISTENCE: Do NOT run git add",
        "platform-persistence directive (#5111)",
      ],
      [
        "publishes everything itself from your final message",
        "handler-side persistence note (#5111, #7122)",
      ],
    ])("contains %s (%s)", (anchor) => {
      expect(SUT_SOURCE).toContain(anchor);
    });
  });

  // #7122 — the agent can no longer publish: these directives were retired with
  // the verbs/tools they drove. Asserting them ABSENT keeps a revert of the
  // prompt rewrite from silently re-arming an instruction the hook now denies
  // (which would only provoke denied filings and a RED monitor).
  describe("#7122 — retired publication directives are absent from the prompt", () => {
    it.each([
      ["## Top Contributors", "contributor section directive (R3)"],
      ["Community Interactions", "interaction table directive (R3)"],
      ["| User | Issue/PR | Comment |", "commenter table"],
      ["--milestone", "gh issue create flag"],
      ["MILESTONE RULE", "issue-creation rule"],
      ["gh issue", "any issue verb (create/list/comment)"],
      ["gh label", "any label verb"],
      ["Create GitHub Issue", "issue-creation step"],
      ["brand-guide", "brand-guide read step"],
      ["Brief contextual", "quote allowance (R3)"],
      ["CLONE DEPTH RULE", "gh issue list dedup paragraph (env-dump verb)"],
      ["Creating the monitor issue above is REQUIRED", "persistence gate sentence"],
      ["Only changes under knowledge-base/support/community/", "persistence path sentence"],
      ["FAILED", "retired misconfiguration-issue branch"],
      ["new stargazers in the period (username", "stargazer username directive"],
      // The window label is a handler constant now (and per platform); the model never chooses one.
      ["periodDays", "model-chosen period (the handler renders each platform's window itself)"],
      ["fixed 1-day window", "false claim: the collectors do NOT share one 1-day window"],
      ["fetch-activity", "dropped LinkedIn verb: nothing consumed it and the hook no longer admits it"],
      ["period_days", "collector period field the model used to pick a window"],
      // Allowlist narrowing: both verbs left the hook, so the prompt must not request them.
      ["discord members", "dropped verb: member count comes from guild-info"],
      ["hn trending", "dropped verb: nothing consumed it"],
      ["AGENTS.md rule", "garbled rule line"],
    ])("prompt does NOT contain %s (%s)", (removed) => {
      expect(COMMUNITY_MONITOR_PROMPT).not.toContain(removed);
    });
  });

  describe("#7122 — final-message draft contract (generated from the module's constants)", () => {
    it("embeds the generated one-line example verbatim, and the example passes the schema", () => {
      const line = buildExampleDraftLine();
      expect(COMMUNITY_MONITOR_PROMPT).toContain(line);
      expect(line).not.toMatch(/[\r\n]/);
      expect(parseCommunityDraft(line).ok).toBe(true);
    });

    it("names every draft key and closed-enum member the schema defines", () => {
      for (const key of ["platforms", "topics", "status", "failureCause", "metrics", "category", "count"]) {
        expect(COMMUNITY_MONITOR_PROMPT, key).toContain(key);
      }
      for (const platform of COMMUNITY_PLATFORMS) {
        expect(COMMUNITY_MONITOR_PROMPT, platform).toContain(`"${platform}":`);
        for (const metric of Object.keys(COMMUNITY_METRICS[platform])) {
          expect(COMMUNITY_MONITOR_PROMPT, `${platform}.${metric}`).toContain(`"${metric}"`);
        }
      }
      for (const member of [...COMMUNITY_STATUSES, ...COMMUNITY_FAILURE_CAUSES, ...COMMUNITY_TOPIC_CATEGORIES]) {
        expect(COMMUNITY_MONITOR_PROMPT, member).toContain(member);
      }
      expect(COMMUNITY_MONITOR_PROMPT).toContain("ONE line of compact JSON");
    });

    it("keeps the {{RUN_DATE}} sentinel (injectRunDate throws without it)", () => {
      expect(() => injectRunDate(COMMUNITY_MONITOR_PROMPT, "2026-10-06T08:00:00.000Z")).not.toThrow();
      expect(injectRunDate(COMMUNITY_MONITOR_PROMPT, "2026-10-06T08:00:00.000Z")).toContain("2026-10-06");
    });

    it("tells the agent a truncated collector output is partial/output-too-large, not guessed (it has no file tools to read a spill)", () => {
      expect(COMMUNITY_MONITOR_PROMPT).toContain("truncated or exceeds the inline limit");
      expect(COMMUNITY_MONITOR_PROMPT).toContain("you have no file tools");
      expect(COMMUNITY_MONITOR_PROMPT).toContain('failureCause "output-too-large"');
      expect(COMMUNITY_FAILURE_CAUSES).toContain("output-too-large");
    });

    // The prompt text AFTER string interpolation (what the agent reads), minus the
    // runnable-literal parity concerns covered by the allowlist suite.
    const PROMPT = COMMUNITY_MONITOR_PROMPT;

    it("one Bash call per platform: no call combines commands of two platforms, and every call is ONE LINE", () => {
      expect(PROMPT).toContain("ONE Bash call PER PLATFORM");
      expect(PROMPT).toContain("Each Bash call is ONE LINE");
      const ROUTER = "bash plugins/soleur/skills/community/scripts/community-router.sh";
      // Every backtick-delimited command group is a single platform's call.
      const groups = [...PROMPT.matchAll(/`(bash plugins\/soleur[^`]*)`/g)].map((m) => m[1]);
      expect(groups.length).toBeGreaterThanOrEqual(9);
      for (const g of groups) {
        expect(g, "a command span must not contain a line break").not.toMatch(/[\r\n]/);
        const platforms = new Set(
          g.split(";").map((seg) => seg.trim().replace(`${ROUTER} `, "").split(" ")[0]),
        );
        expect(platforms.size, g).toBe(1);
      }
      // Discord messages are fetched per channel, with a bounded limit, never chained.
      expect(PROMPT).toContain("discord messages <channel_id> 50");
      expect(PROMPT).toMatch(/ONE more Bash call PER channel ID/);
    });

    it("Discord: guild-info and channels are SEPARATE calls, at most the first 40 channels are read, a failing channel is skipped (not partial), and an over-cap server is partial/timeout", () => {
      const ROUTER = "bash plugins/soleur/skills/community/scripts/community-router.sh";
      const groups = [...PROMPT.matchAll(/`(bash plugins\/soleur[^`]*)`/g)].map((m) => m[1]);
      expect(groups).toContain(`${ROUTER} discord guild-info`);
      expect(groups).toContain(`${ROUTER} discord channels`);
      // never chained together
      expect(groups.some((g) => g.includes("guild-info") && g.includes("channels"))).toBe(false);
      expect(PROMPT).toMatch(/guild-info[\s\S]*approximate_member_count[\s\S]*discord channels/);
      expect(PROMPT).toContain("FIRST 40 channels");
      expect(PROMPT).toMatch(/more than 40 channels[\s\S]*"partial" with failureCause "timeout"/);
      expect(COMMUNITY_FAILURE_CAUSES).toContain("timeout");
      expect(PROMPT).toMatch(/A channel whose call fails[\s\S]*is simply skipped: it does NOT make Discord\s+"partial"/);
    });

    it("GitHub watchers come from subscribers_count, never watchers_count (an alias of stars)", () => {
      expect(PROMPT).toContain("`subscribers_count`");
      expect(PROMPT).toMatch(/NOT\s+`watchers_count`/);
      expect(PROMPT).not.toMatch(/watchers_count` from repo-stats/);
    });

    it("never claims one shared collection window; the GitHub day argument is the handler's COMMUNITY_PERIOD_DAYS", () => {
      expect(PROMPT).not.toMatch(/fixed 1-day window|runs over a fixed|every collector below/);
      expect(PROMPT).toContain("do NOT share one\nwindow");
      // the five github verbs are the ONLY ones with a day argument, and it is the constant
      const days = [...PROMPT.matchAll(/community-router\.sh github ([a-z-]+) (\d+)/g)];
      expect(days.map((m) => m[1]).sort()).toEqual(["activity", "contributors", "discussions", "fetch-interactions", "repo-stats"]);
      for (const m of days) expect(Number(m[2]), `github ${m[1]}`).toBe(COMMUNITY_PERIOD_DAYS);
    });

    it("tells the agent an all-zero 'collected' platform is shown as unverified", () => {
      expect(PROMPT).toContain("whose every value is 0 is\n     shown to readers as unverified");
    });

    it("Discord members come from guild-info; the dropped verbs are not requested", () => {
      expect(PROMPT).toContain("approximate_member_count");
      expect(PROMPT).not.toContain("discord members");
      expect(PROMPT).not.toContain("hn trending");
    });

    it("defines the GitHub external counts from the collector's own output, not a maintainer guess", () => {
      expect(PROMPT).toContain("DISTINCT `user` values");
      expect(PROMPT).toContain("fetch-interactions");
      expect(PROMPT).toContain("length of");
      expect(PROMPT).toContain("`interactions` list");
      expect(PROMPT).not.toContain("other than the maintainers");
    });

    it("tells the agent the LinkedIn engagement figure is a 0-1 ratio to multiply by 100", () => {
      expect(PROMPT).toContain("0 to 1 RATIO");
      expect(PROMPT).toContain("multiply it by 100");
    });

    it("states the router's `bsky` is the draft's `bluesky`, and reconciles failureCause with the closed example", () => {
      expect(PROMPT).toContain("The router names Bluesky `bsky`");
      expect(PROMPT).toContain("its key is `bluesky`");
      expect(PROMPT).toContain("the only extra key you may add is failureCause");
    });

    it("an unavailable metric makes the platform partial/failed with a cause, never a measured 0", () => {
      expect(PROMPT).toContain("must never\n   be presented as a measured 0");
      expect(PROMPT).toContain("AND mark that platform");
      expect(PROMPT).not.toContain("keep 0 only when the value is unavailable");
    });

    it("tells the agent it has no file or issue tools and must not add a text field", () => {
      expect(COMMUNITY_MONITOR_PROMPT).toContain("You cannot write files, create issues or post anywhere");
      expect(COMMUNITY_MONITOR_PROMPT).toContain("no field for names, usernames, quotes or message text");
    });
  });

  // #6143 — the prompt-level DEDUP RULE (24h window, comment-and-exit) was
  // removed; same-day manual+cron duplicates are now handled code-side by
  // digestIssueExistsForDate BEFORE the eval spawns (serialized by the
  // registration's { scope: "fn", limit: 1 } concurrency). These strings must
  // stay ABSENT from cron-community-monitor.ts — scoped to THIS file only,
  // since _cron-shared.ts legitimately still contains dedup-related language.
  // Mirrors cron-roadmap-review.test.ts's post-#6139 regression guard.
  describe("#6143 — prompt-level DEDUP RULE removed (regression guard)", () => {
    it.each([
      ["DEDUP RULE", "removed prompt-level dedup keyword"],
      ["within the last 24 hours", "removed 24h rolling window"],
      [
        "post your findings as a comment on the most recent existing issue",
        "removed comment-and-exit fallback",
      ],
    ])("SUT_SOURCE does NOT contain %s (%s)", (removed) => {
      expect(SUT_SOURCE).not.toContain(removed);
    });

    it("still publishes the dated digest issue unconditionally (prefix constant wired)", () => {
      // The unconditional-publish contract survives, now handler-side (#7122): the
      // code-level dedup skip happens before the eval spawns and both the dedup read
      // and the audit fallback key on the shared title prefix.
      expect(SUT_SOURCE).toContain("titlePrefix: SCHEDULED_DIGEST_TITLE_PREFIX");
    });
  });
});

describe("buildSpawnEnv allowlist (PR-11 bucket-ii security surface)", () => {
  // Extract the buildSpawnEnv function body from SUT_SOURCE for targeted
  // grep. The function is a single returned object literal; we slice from
  // the function signature to its closing brace.
  const buildEnvMatch = SUT_SOURCE.match(
    /function buildSpawnEnv\([\s\S]+?\n\}\n/,
  );
  const buildEnvBody = buildEnvMatch ? buildEnvMatch[0] : "";

  it("buildSpawnEnv function is present in source", () => {
    expect(buildEnvBody.length).toBeGreaterThan(0);
  });

  describe("positive class — community vars MUST be allowlisted", () => {
    it.each([
      "DISCORD_BOT_TOKEN",
      "DISCORD_GUILD_ID",
      "BSKY_HANDLE",
      "BSKY_APP_PASSWORD",
      "LINKEDIN_ACCESS_TOKEN",
      "LINKEDIN_PERSON_URN",
      "LINKEDIN_ORG_ACCESS_TOKEN",
      "LINKEDIN_ORG_ID",
      "X_API_KEY",
      "X_API_SECRET",
      "X_ACCESS_TOKEN",
      "X_ACCESS_TOKEN_SECRET",
    ])("allowlist contains %s", (key) => {
      expect(buildEnvBody).toContain(`${key}: process.env.${key}`);
    });
  });

  describe("negative class — sensitive vars MUST NOT be allowlisted", () => {
    // The list is intentionally over-broad: anything sensitive in `prd`
    // Doppler that a future careless edit could add. The spread operator
    // is the catch-all that would defeat the allowlist entirely.
    it.each([
      ["DOPPLER_TOKEN", "Doppler service token; full secrets-read on prd"],
      [
        "GITHUB_APP_PRIVATE_KEY",
        "GitHub App PEM; full repo write across installations",
      ],
      [
        "DISCORD_WEBHOOK_URL",
        "Discord POSTING credential; no read-path verb consumes it (#7122)",
      ],
      [
        "SENTRY_AUTH_TOKEN",
        "Sentry write API token; full project access",
      ],
      [
        "SENTRY_IAC_AUTH_TOKEN",
        "Sentry IaC-write token; destructive against Sentry resources",
      ],
      [
        "SUPABASE_SERVICE_ROLE_KEY",
        "Supabase service role; bypasses RLS",
      ],
      [
        "INNGEST_SIGNING_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      [
        "INNGEST_EVENT_KEY",
        "Inngest substrate auth; arbitrary event forging",
      ],
      ["STRIPE_SECRET_KEY", "Stripe API; payment surface"],
      ["RESEND_API_KEY", "Resend email; impersonation surface"],
      [
        "BYOK_ENCRYPTION_KEY",
        "Symmetric key for user BYOK secrets; full plaintext recovery",
      ],
      [
        "VAPID_PRIVATE_KEY",
        "Web Push VAPID signing key; push notification impersonation",
      ],
      [
        "STRIPE_WEBHOOK_SECRET",
        "Webhook signature verification bypass; event forgery",
      ],
      [
        "CF_API_TOKEN_PURGE",
        "Cloudflare cache-purge API token; cache-poisoning surface",
      ],
    ])("allowlist does NOT contain %s (%s)", (key) => {
      expect(buildEnvBody).not.toContain(key);
    });

    it("allowlist does NOT use ...process.env spread (would defeat allowlist)", () => {
      expect(buildEnvBody).not.toMatch(/\.\.\.process\.env/);
    });

    // #6695 — the effective spawn env is now composed at the CALL SITE, which
    // wraps buildSpawnEnv to add the collector-status dir. That composition sits
    // outside `buildEnvBody`, so every assertion above is blind to it: a future
    // `...buildSpawnEnv(token), ...process.env` inside the wrapper would pass
    // the whole negative class with a green suite. Assert against the WHOLE
    // file — this module has no legitimate use of that spread anywhere.
    it("no ...process.env spread anywhere in the module (incl. the call-site wrapper)", () => {
      expect(SUT_SOURCE).not.toMatch(/\.\.\.process\.env/);
    });

    it("the call-site wrapper adds only the non-secret collector-status dir", () => {
      const wrapper = SUT_SOURCE.match(
        /buildSpawnEnv:\s*\(token: string\) => \(\{[\s\S]*?\}\),/,
      )?.[0];
      expect(wrapper).toBeDefined();
      // Exactly one added key, and it is a path — not a credential.
      expect(wrapper).toContain("...buildSpawnEnv(token)");
      expect(wrapper).toContain("SOLEUR_COLLECTOR_STATUS_DIR");
      expect(wrapper).not.toMatch(/process\.env\./);
    });

    // Read-only invariant: the community monitor forwards X read credentials
    // (X_API_KEY etc., positive class above) but MUST NOT forward X_ALLOW_POST
    // — the posting defense-in-depth guard (x-community.sh, the `X_ALLOW_POST`
    // check in cmd_post; content anchor, not a line number). Only the
    // publisher (cron-content-publisher.ts) arms posting. A future careless
    // edit that adds X_ALLOW_POST here would silently enable posting from a
    // read-only digest path.
    it("allowlist does NOT contain X_ALLOW_POST (monitor is read-only)", () => {
      expect(buildEnvBody).not.toContain("X_ALLOW_POST");
    });
  });
});

describe("#4730 — output-aware heartbeat (always-create producer)", () => {
  it("gates the heartbeat on output, not the bare spawn exit code", () => {
    // This cron writes a dated digest and creates a GitHub issue summarizing the
    // findings every run (even the no-platform-enabled path creates a titled
    // issue), so a clean exit that produced no artifact must turn the monitor
    // RED (output-aware) instead of false-green. Mirrors the 3 producers wired
    // by PR #4714. The pre-fix line was the forbidden `ok: spawnResult.ok`.
    expect(SUT_SOURCE).not.toContain("ok: spawnResult.ok");
    expect(SUT_SOURCE).toContain("resolveOutputAwareOk(");
    expect(SUT_SOURCE).toContain("runStartedAt");
    expect(SUT_SOURCE).toContain("ok: heartbeatOk");
  });
});

describe("#5111 — handler-side persistence (safeCommitAndPr migration)", () => {
  it("prompt carries the platform-persistence directive, not a commit block", () => {
    expect(SUT_SOURCE).toContain("PERSISTENCE: Do NOT run git add");
    expect(SUT_SOURCE).not.toContain("MANDATORY FINAL STEP");
    // No prompt-side staging command survives. The PERSISTENCE directive's
    // own "git add," mention is comma-delimited, so the trailing-space form
    // below only matches a real `git add <paths>` shell command.
    expect(SUT_SOURCE).not.toMatch(/git add /);
  });

  it("wires the gated safe-commit-pr step (issue-verified AND not timed out)", () => {
    expect(SUT_SOURCE).toContain('from "./_cron-safe-commit"');
    expect(SUT_SOURCE).toContain('step.run("safe-commit-pr"');
    // Plan AC: persistence MUST be gated on issue-verified output AND
    // not-timed-out — a regression to `spawnResult.ok` (the #4747 hazard)
    // or a dropped timeout clause turns this red. Mirrors the parity test.
    expect(SUT_SOURCE).toMatch(
      /if \(heartbeatOk && !spawnResult\.abortedByTimeout\) \{[\s\S]{0,800}?safeCommitAndPr\(\{/,
    );
  });
});

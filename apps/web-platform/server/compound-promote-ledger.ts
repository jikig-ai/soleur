// #8293 -- the proposal ledger READER. GitHub PR state is the ledger of record for what the
// weekly proposer already put in front of a human (ADR-300): `promotion-log.md` records accepted-or-
// pending proposals only, and a second row-landing write path is forbidden (ADR-054). So a rejected
// cluster is recognised by reading the `self-healing/auto-*` PRs back, through Octokit (the runtime
// image has no `gh`), and suppressing a cluster whose recomputed hash was already proposed.
//
// Contract (CTO rulings F1-F3, C1, C2, C5 in the plan's decision record):
//   - one search query, `head:<PROMOTE_BRANCH_PREFIX>` bounded to the App's own PRs by `author:`
//     (`head:` is a prefix match on the branch name and a trailing hyphen is not significant, so the
//     author qualifier is what keeps a fork or human PR on a look-alike branch from filling the page cap), paged through the shared `fetchAllPages`
//     (cap 10 pages of 100; it throws on a full last page, so 999 hits is the usable ceiling and the
//     Search API's own 1,000-result limit is never reached); NO per-hit detail fetch and no
//     `pulls?state=all` listing: the search item already carries state, closed_at, merged_at,
//     user.login and title;
//   - identity: only a PR authored by the Soleur App ever suppresses (a name-only match never does);
//   - the cluster hash is read from the anchored PR TITLE, built and parsed by ONE pair
//     (`promotePrTitle` / `PROMOTE_PR_TITLE_RE`). `Cluster-Hash:` is a commit trailer, not a PR-body line;
//   - suppression is the EXACT hash: open or merged suppresses; closed-unmerged suppresses while
//     now - closed_at < 60 days (at exactly 60 days it lapses);
//   - a read that cannot be proven complete THROWS a typed error (fail closed, loud): an API/network
//     error, a rate limit, the page cap, `incomplete_results`, a `total_count` over the items
//     retrieved, a closed item with an unparseable `closed_at`, a malformed item, or bot-authored hits with
//     none parsing as a promote title (title drift must not read as "nothing to suppress").
//     A zero-hit read, and hits that are all foreign (a fork or human PR on a self-healing/auto-*
//     branch; the author qualifier keeps them out of the response, so the login check is a second
//     layer), are accepted as an empty ledger: the live search returns 0 today, search-index lag can
//     briefly return 0 after a PR opens, and the consequence is at most one duplicate DRAFT PR,
//     bounded by the week cap and human review (ADR-300, accepted residuals).
// The search response carries every matching PR's full issue object (body included; the Search API
// has no field projection), so the process RECEIVES that text. The reader uses five fields, never
// reads a body or comment, and returns no PR text: entries are `{hash, state, closed_at}`, and the
// step output `step.run` persists is those entries plus two counts (`scanned`, `titleSkipped`).
import { SOLEUR_BOT_LOGIN, fetchAllPages } from "@/server/inngest/functions/_cron-shared";

export const LEDGER_TTL_DAYS = 60;
export const LEDGER_MAX_SEARCH_PAGES = 10;
export const LEDGER_BOT_LOGIN = SOLEUR_BOT_LOGIN;
/** The search qualifier for the App's PRs: the login without its `[bot]` suffix, under `app/`. */
const LEDGER_AUTHOR_QUALIFIER = `author:app/${SOLEUR_BOT_LOGIN.replace(/\[bot\]$/, "")}`;

/**
 * The branch prefix every promotion PR is opened on. The ONE definition: the apply step builds the
 * branch from it and the ledger query searches for it, so changing one cannot desync the other.
 */
export const PROMOTE_BRANCH_PREFIX = "self-healing/auto-";

const DAY_MS = 24 * 60 * 60 * 1000;
const SEARCH_PER_PAGE = 100;
/** `closed_at` must be an ISO timestamp WITH a zone; `new Date("2026")` or `new Date("1")` also parse, and a zone-less one is read as local time. */
const ISO_TIMESTAMP_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})$/;

/** The PR title the apply step gives a promotion PR. The ONLY builder: the reader's parser is derived from the same shape. */
export function promotePrTitle(hash: string, date: string): string {
  return `self-healing(auto): promote cluster ${hash} ${date}`;
}

/** Anchored inverse of {@link promotePrTitle}: lower-case 64-hex hash, ISO date, nothing else. */
export const PROMOTE_PR_TITLE_RE = /^self-healing\(auto\): promote cluster ([0-9a-f]{64}) (\d{4}-\d{2}-\d{2})$/;

export const LEDGER_FAILURE_CAUSES = [
  "http-5xx",
  "rate-limit",
  "page-cap",
  "incomplete",
  "unparseable",
  "drift",
  "transport",
] as const;
export type LedgerFailureCause = (typeof LEDGER_FAILURE_CAUSES)[number];

/** A ledger read that cannot be trusted. `ledgerCause` is a closed enum, safe as a low-cardinality Sentry tag. */
export class LedgerReadError extends Error {
  readonly ledgerCause: LedgerFailureCause;
  constructor(ledgerCause: LedgerFailureCause, message: string) {
    super(message);
    this.name = "LedgerReadError";
    this.ledgerCause = ledgerCause;
  }
}

export interface LedgerEntry {
  hash: string;
  state: "open" | "merged" | "closed";
  /** ISO timestamp; present for `closed` entries (validated), omitted otherwise. */
  closed_at?: string;
}

export interface LedgerResult {
  entries: LedgerEntry[];
  /** RAW search hit count, before identity and title filtering. */
  scanned: number;
  /** Soleur-App-authored hits skipped because the title did not match the builder's shape. */
  titleSkipped: number;
}

/** The one method the reader needs; the handler adapts its Octokit to this. */
export interface LedgerOctokit {
  request(route: string, params: Record<string, unknown>): Promise<{ data: unknown }>;
}

interface SearchItem {
  title: string;
  state: string;
  closed_at: string | null;
  user: { login?: string } | null;
  pull_request?: { merged_at?: string | null };
}

function isRecord(v: unknown): v is Record<string, unknown> {
  return typeof v === "object" && v !== null && !Array.isArray(v);
}

function asSearchItem(v: unknown): SearchItem | null {
  if (!isRecord(v)) return null;
  if (typeof v.title !== "string" || (v.state !== "open" && v.state !== "closed")) return null;
  // `is:pr` items always carry a `pull_request` object; without it `merged_at` is unreadable and a
  // merged PR would degrade to a 60-day closed one, so a missing object is a malformed item.
  if (!isRecord(v.pull_request)) return null;
  if (v.closed_at !== null && v.closed_at !== undefined && typeof v.closed_at !== "string") return null;
  const user = isRecord(v.user) ? { login: typeof v.user.login === "string" ? v.user.login : undefined } : null;
  const pr = { merged_at: typeof v.pull_request.merged_at === "string" ? v.pull_request.merged_at : null };
  return { title: v.title, state: v.state, closed_at: (v.closed_at as string | null | undefined) ?? null, user, pull_request: pr };
}

function classifyTransportError(err: unknown): LedgerReadError {
  if (err instanceof LedgerReadError) return err;
  const status = isRecord(err) && typeof err.status === "number" ? err.status : undefined;
  const message = err instanceof Error ? err.message : String(err);
  // The page-cap error is fetchAllPages' own and carries no status.
  if (/page cap/i.test(message)) return new LedgerReadError("page-cap", "ledger search exceeded the page cap");
  if (status === 403 || status === 429) return new LedgerReadError("rate-limit", `ledger search was refused (${status})`);
  if (status !== undefined && status >= 500) return new LedgerReadError("http-5xx", `ledger search failed (${status})`);
  // Page 11 is never requested (the cap throws first), so a 422 is the query itself being rejected.
  if (status === 422) return new LedgerReadError("transport", "ledger search query was rejected (422)");
  // Deliberately NOT the raw message: an Octokit error can echo a response body.
  return new LedgerReadError("transport", "ledger search failed before a response");
}

/**
 * Read the bot's prior proposal outcomes. THROWS {@link LedgerReadError} on any read that cannot be
 * proven complete; never returns a partial view as if it were whole.
 */
export async function readLedger(args: { octokit: LedgerOctokit; owner: string; repo: string }): Promise<LedgerResult> {
  const { octokit, owner, repo } = args;
  const q = `repo:${owner}/${repo} is:pr ${LEDGER_AUTHOR_QUALIFIER} head:${PROMOTE_BRANCH_PREFIX}`;
  let totalCount = 0;
  let incomplete = false;
  let malformed = false;

  let raw: unknown[];
  try {
    raw = await fetchAllPages<unknown>(
      async (page) => {
        const { data } = await octokit.request("GET /search/issues", { q, per_page: SEARCH_PER_PAGE, page });
        if (!isRecord(data) || !Array.isArray(data.items)) {
          malformed = true;
          return { data: [] };
        }
        if (data.incomplete_results === true) incomplete = true;
        if (typeof data.total_count === "number") totalCount = data.total_count;
        else malformed = true;
        return { data: data.items as unknown[] };
      },
      { perPage: SEARCH_PER_PAGE, maxPages: LEDGER_MAX_SEARCH_PAGES },
    );
  } catch (err) {
    throw classifyTransportError(err);
  }

  if (malformed) throw new LedgerReadError("unparseable", "ledger search returned an unexpected shape");
  if (incomplete) throw new LedgerReadError("incomplete", "ledger search reported incomplete_results");
  if (totalCount > raw.length) {
    throw new LedgerReadError("incomplete", "ledger search total exceeds the items retrieved");
  }

  const entries: LedgerEntry[] = [];
  let titleSkipped = 0;
  let botHits = 0;
  for (const rawItem of raw) {
    const item = asSearchItem(rawItem);
    if (item === null) throw new LedgerReadError("unparseable", "ledger search item has an unexpected shape");
    if (item.user?.login !== LEDGER_BOT_LOGIN) continue; // identity binding: a name-only match never suppresses
    botHits++;
    const m = PROMOTE_PR_TITLE_RE.exec(item.title);
    if (m === null) {
      titleSkipped++;
      continue;
    }
    const hash = m[1];
    if (item.pull_request?.merged_at) {
      entries.push({ hash, state: "merged" });
    } else if (item.state === "open") {
      entries.push({ hash, state: "open" });
    } else {
      const closedAt = item.closed_at;
      if (closedAt === null || !ISO_TIMESTAMP_RE.test(closedAt) || Number.isNaN(new Date(closedAt).getTime())) {
        throw new LedgerReadError("unparseable", "a closed ledger entry has no parseable closed_at");
      }
      entries.push({ hash, state: "closed", closed_at: closedAt });
    }
  }

  // Bot-authored hits but none parses as a promote title: the title format drifted (or a reviewer
  // retitled every bot PR). That must not read as "nothing to suppress". Foreign-only hits do not
  // reach here: they say nothing about the bot's own history.
  if (botHits > 0 && entries.length === 0) {
    throw new LedgerReadError("drift", "ledger search returned bot-authored hits but none matched the promote-title shape");
  }
  return { entries, scanned: raw.length, titleSkipped };
}

/**
 * The ONLY function that returns a suppression verdict. Exact hash: an open or merged prior PR
 * suppresses; a closed-unmerged one suppresses while `now - closed_at < LEDGER_TTL_DAYS` (so it
 * lapses at exactly 60 days). `now` must derive from the run's memoized start, never a fresh Date.
 */
export function decideSuppression(args: { entries: readonly LedgerEntry[]; hash: string; now: Date }): boolean {
  const { entries, hash, now } = args;
  // An unusable clock cannot prove any closed entry has aged out: fail closed (suppress).
  if (Number.isNaN(now.getTime())) return entries.some((e) => e.hash === hash);
  for (const e of entries) {
    if (e.hash !== hash) continue;
    if (e.state === "open" || e.state === "merged") return true;
    const closedAt = e.closed_at === undefined ? Number.NaN : new Date(e.closed_at).getTime();
    // An unparseable timestamp suppresses (fail closed); readLedger already rejects one.
    if (Number.isNaN(closedAt)) return true;
    if (now.getTime() - closedAt < LEDGER_TTL_DAYS * DAY_MS) return true;
  }
  return false;
}

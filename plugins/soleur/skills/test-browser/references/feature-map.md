# Feature map convention

A **feature map** is a committed, user-POV inventory of a repository's
navigable features. Each entry names how to reach a route, its stable
selectors, the expected outcome, the session state it needs, and its gotchas.
It is the artifact that turns browser testing from flailing — re-deriving
file-to-route mappings on every run and discarding them at session end —
into navigation. The prescription comes from the poteto note in
[Agentic Verification](https://addyo.substack.com/p/agentic-verification):
agents that test in a real browser need a maintained map to navigate by.

This document is the convention the `test-browser`, `qa`, `ux-audit`, and
`reproduce-bug` skills read: the path, the entry schema, the parse contract
consumers rely on, the update contract, and how the map stays fresh.

## Canonical location

The map lives at **`docs/feature-map.md`** in the repository root. One path
keeps every consumer's check trivial: a skill looks for that file, reads it
when present, and falls back to file-to-route inference when absent.

`docs/` is the right home even when the repository publishes a docs site —
the map is internal agent tooling, not user-facing documentation. If the
site builds from `docs/`, mark the file accordingly (a comment in the site
config or a build ignore) so it is not rendered as a page.

## Entry schema

Each mapped route is one `##` heading naming the route in backticks,
followed by field bullets:

```markdown
## `/settings/billing`

- route: `/settings/billing`
- entry: rail nav → settings → billing tab, or direct URL
- selectors: `data-testid="plan-card"`, `data-testid="manage-subscription"`
- expects: current plan and invoices render; a missing subscription shows the upgrade empty state
- auth: signed-in fixture with an active subscription
- gotchas: the invoices table lazy-loads — wait for `data-testid="invoice-row"` before asserting row count
```

The fence markers above are display-only — they delimit the example in this
document and must never be copied into the map itself (see "Consumer-parse
constraints" below).

Field semantics:

- `route` — the route path, matching the heading. Dynamic segments stay
  literal (`/posts/[id]`, `/docs/[...path]`, `/t/:token`) — the map documents
  the route shape, not a concrete id.
- `entry` — how an agent reaches the route: a nav link, a direct URL, or a
  redirect from another surface.
- `selectors` — stable anchors an agent can assert on. Prefer `data-testid`
  values, then role/text anchors (`getByRole`/`getByText` style). Do not list
  selectors you have not observed.
- `expects` — the user-POV outcome of reaching the route, not an
  implementation detail.
- `auth` — the session state the route needs: anonymous, a signed-in
  fixture, or a role-gated account. Name the fixture class, not credentials.
- `gotchas` — anything that makes naive navigation or assertions wrong:
  conditional banners, redirects, lazy mounts, duplicated testids.

## Deliberately unmapped

Some routes should not be mapped — error surfaces, routes pending removal,
surfaces intentionally out of test scope. Exempt them in a
`## Deliberately unmapped` section at the end of the map, one bullet each,
of the exact shape:

`- \`/route\` — <reason>`

The em-dash and a non-empty reason are part of the grammar. An exemption is
a recorded decision, not silent absorption: a route absent from both the
entries and this section reads as "unmapped and unexempted" to coverage
checks, which is exactly what the section exists to distinguish.

## Consumer-parse constraints

Consumers anchor on lines, not on rendered structure:

- A `## \`/route\`` heading (a `##`, a space, a backtick, a slash) opens an
  entry; its field bullets run until the next `##` heading or end of file. <!-- markdownlint-disable-line MD038 -->
- `- selectors:` and `- expects:` bullets are how a consumer sees that an
  entry is complete — mentioning the field names in prose inside the entry
  does NOT conform.
- `## Deliberately unmapped` carries no backtick in the heading, and its
  bullets match `- \`/route\` — <reason>` exactly.

**No fenced code blocks inside the map itself.** Every consumer here is
line-anchored, so a `## \`/route\`` line inside a fenced block reads as a
real entry and its fenced body as real fields. The map documents routes
with inline backticks; it needs no fences.

## Update contract

Adding, renaming, or deleting a route surface requires an edit to the map —
or to `## Deliberately unmapped` — in the same change. State this contract
in the map's own header so a reader of the artifact sees it. A map whose
entries drift from the routes is worse than no map: tombstoned entries
navigate to nothing and unmapped new routes are invisible.

## Authoring the map

There is no universal route glob — the agent enumerates route surfaces from
the repository's own shapes:

- Next.js app router: `git ls-files '<app dir>' | grep -E '/page\.tsx$'`
- Next.js pages router: `git ls-files '<pages dir>' | grep -vE '/_(app|document|error)\.'`
- Rails: `config/routes.rb` plus the `app/views` tree
- SPAs: the router config (`createRouter`, route tables, `<Route>` elements)

Use a prefix pathspec plus a suffix filter — never a `**/` glob, which
silently drops zero-directory roots on some git versions. The commands above
are POSIX-safe and run on stock macOS; adapt the prefix and suffix to the
repository's actual layout.

Fill `selectors`, `expects`, and `gotchas` only from observed navigation or
read page source. An unvisited entry that asserts unverified selectors is
worse than no entry — it navigates an agent toward anchors that may not
exist.

## Keeping the map fresh

Three mechanisms, cheapest first:

1. **Refresh on run.** `test-browser` writes or refreshes the map on each
   run: it seeds the map when absent (exercised routes only), refreshes
   entries a run contradicted, and appends newly exercised routes. See the
   `test-browser` skill's "Write or refresh the feature map" step.
2. **The update contract.** Human route changes carry map edits in the same
   change (above).
3. **A coverage lint (optional, user-adapted).** A shell lint can enforce
   the contract mechanically with five arms:
   - *Coverage* — every route surface the lint derives is either a mapped
     entry or a `Deliberately unmapped` bullet.
   - *Staleness* — every mapped entry and exemption still corresponds to a
     real route (tombstones red).
   - *Completeness* — every entry carries `- selectors:` and `- expects:`
     field bullets.
   - *Contradiction* — no route appears in both the entries and the
     exemptions.
   - *Grammar* — no fenced code blocks anywhere in the map.
   Add an anti-vacuity check that the route enumeration actually derived at
   least one route, so a broken glob cannot certify an empty map. The
   coverage and staleness arms need the repository's own route-file glob;
   the other arms are portable to any map.

## Edge cases

- **Non-web repositories carry no map.** With no route surfaces there is
  nothing to inventory; consumers skip the lookup silently.
- **Zero exercised routes means no seed is written.** A vacuous map
  certifies nothing.
- **A partial map is valid.** Entries cover the routes actually observed;
  the update contract and the coverage lint keep uncovered routes visible.
  A map is authoritative per-route — never a reason to skip an unmapped
  route.
- **Refresh is field-scoped.** A producer refresh updates the fields a run
  contradicted and appends new entries; it must leave untouched entries and
  the header byte-identical so operator annotations survive.

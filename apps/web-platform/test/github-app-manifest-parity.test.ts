import { describe, test, expect } from "vitest";
import { readFileSync, existsSync } from "node:fs";
import path from "node:path";

// Symbol-parity test for the committed GitHub App manifest.
//
// Asserts:
//   1. apps/web-platform/infra/github-app-manifest.json exists and parses.
//   2. hook_attributes.url template references /api/webhooks/github.
//   3. callback_urls is an array with >= 3 entries (per
//      knowledge-base/project/learnings/integration-issues/2026-05-04-github-app-callback-url-three-entries.md).
//   4. default_permissions.administration === "write".
//   5. public === false.
//   6. setup_on_update === true.
//   7. redirect_url ends with /internal/github-app-init.
//   8. Every doppler_secret resource name declared in
//      apps/web-platform/infra/github-app.tf (GITHUB_APP_*) has documented
//      coverage — the manifest cannot guarantee CLIENT_SECRET / WEBHOOK_SECRET
//      values (those land via operator paste / random_id), but the secret
//      _names_ must be enumerable so the runbook stays in sync.
//
// Ref #4115.

const REPO_ROOT = path.resolve(__dirname, "../../..");
const MANIFEST_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/github-app-manifest.json",
);
const TF_PATH = path.join(
  REPO_ROOT,
  "apps/web-platform/infra/github-app.tf",
);

// PR #4150 deleted `github_app_client_id` + `github_app_client_secret` as dead
// plumbing (zero TS consumers). Post-#4150, github-app.tf declares only 3
// doppler_secret resources for the App identity material.
const EXPECTED_TF_SECRETS = [
  "GITHUB_APP_ID",
  "GITHUB_APP_PRIVATE_KEY",
  "GITHUB_APP_WEBHOOK_SECRET",
];

// (#8209, ADR-241) The two App-IDENTITY names are no longer Terraform-MANAGED. Their
// `doppler_secret` resources pinned `config = "prd"`, so web-platform state held a copy
// of the App's live private key -- and the Tier-A `prd_terraform` R2 backend keys read
// that state object. They were replaced with `removed` blocks.
//
// The map below says, per name, how github-app.tf is expected to account for it. It is a
// map rather than a second list so a name cannot silently fall out of BOTH checks: the
// loop asserts over EXPECTED_TF_SECRETS and looks the mode up here, so a name with no
// entry fails rather than being skipped.
const TF_SECRET_MODE: Record<string, "managed" | "forgotten"> = {
  // Soleur-generated from random_id; Terraform owns it and must keep owning it.
  GITHUB_APP_WEBHOOK_SECRET: "managed",
  // Operator-supplied App identity: forgotten, never destroyed. Doppler `prd` keeps the
  // live values, which is what the web app mints installation tokens with.
  GITHUB_APP_ID: "forgotten",
  GITHUB_APP_PRIVATE_KEY: "forgotten",
};

// Terraform resource address for each forgotten name, so the assertion can pin the
// EXACT `removed` block rather than merely "some removed block exists".
const TF_FORGOTTEN_ADDRESS: Record<string, string> = {
  GITHUB_APP_ID: "doppler_secret.github_app_id",
  GITHUB_APP_PRIVATE_KEY: "doppler_secret.github_app_private_key",
};

// Exact set of permissions in the committed manifest. Reconciled to the live
// App state at #4169 post-merge attestation (added `secrets: write` which the
// live App already had but #4115 plan-time snapshot missed). Extended again
// after PR #4226 AC9 enablement granted `issues`, `repository_advisories`,
// and `secret_scanning_alerts` at `read` so PR-H #3244's `triage.p0p1_issue`
// and `security.cve_alert` event routes can deliver. Updated again for #4189:
// `issues` bumped read->write (restores the cron issue-filing trail — the
// drift-guard, oauth-probe, and stale-deferred-scope-outs crons write issues
// via the installation-scoped App token and 403'd silently under `issues:read`).
// `members: read` is RETAINED — it is load-bearing for org-level installation
// ownership verification (server/github-app.ts calls GET /orgs/{org}/members/
// {user} via the installation token in verifyInstallationOwnership +
// findOrgInstallationForUser). The #4189 installation_permission_drift
// (members:read missing on the live install) is cleared by re-consenting to
// GRANT the already-declared scope, not by dropping it.
// The drift-guard cron is the runtime signal for divergence; this test catches
// an in-band manifest mutation that adds an unexpected permission via a
// malicious or sloppy PR.
// #6031 (ADR-088): `packages: read` added for the control-plane installation-token
// minter (cron-ghcr-token-minter). This is a PER-INSTALLATION standing grant on the
// SHARED App — every re-consenting installation grants packages:read, so a private-key
// leak reads every consenting tenant's packages (documented in ADR-088 Consequences;
// requires_cpo_signoff). Plane-c activation needs org-owner re-consent (AC10).
// #6657: `pages: write` added so cron-gh-pages-cert-reissue can PUT /repos/{owner}/
// {repo}/pages (the custom-domain cname toggle that re-orders the bad_authz cert).
// live-fire proved `administration:write` alone 403s "Resource not accessible by
// integration" on that endpoint — the Pages permission is required. Needs org-owner
// re-consent on the live App before the reissue's pages:write-scoped mint succeeds.
const EXPECTED_PERMISSION_KEYS = [
  "actions",
  "administration",
  "checks",
  "contents",
  "issues",
  "members",
  "metadata",
  "packages",
  "pages",
  "pull_requests",
  "repository_advisories",
  "secret_scanning_alerts",
  "secrets",
];

const APP_DOMAIN_PLACEHOLDER = "${app_domain}";

interface Manifest {
  name: string;
  url: string;
  description: string;
  public: boolean;
  redirect_url: string;
  hook_attributes: { url: string; active?: boolean };
  callback_urls: string[];
  setup_url: string;
  setup_on_update: boolean;
  default_permissions: Record<string, string>;
  default_events: string[];
}

describe("github-app-manifest.json symbol parity", () => {
  test("manifest file exists and parses as JSON", () => {
    expect(existsSync(MANIFEST_PATH), `missing ${MANIFEST_PATH}`).toBe(true);
    const raw = readFileSync(MANIFEST_PATH, "utf-8");
    expect(() => JSON.parse(raw)).not.toThrow();
  });

  test("hook_attributes.url template references /api/webhooks/github", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.hook_attributes?.url).toContain("/api/webhooks/github");
  });

  test("callback_urls is an array with >= 3 entries", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(Array.isArray(m.callback_urls)).toBe(true);
    expect(m.callback_urls.length).toBeGreaterThanOrEqual(3);
  });

  test("default_permissions.administration === 'write'", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.administration).toBe("write");
  });

  test("default_permissions.issues === 'write'", () => {
    // #4189 root-cause guard: the cron issue-filing trail (drift-guard,
    // oauth-probe, stale-deferred-scope-outs) 403s silently if `issues`
    // regresses to `read`. The exact-key-set test only checks keys, not
    // values, so this dedicated value assertion prevents a silent revert
    // that would reintroduce the dark-issue-trail outage with a green suite.
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.issues).toBe("write");
  });

  test("default_permissions.checks === 'write' (synthetic check-run POST requires it)", () => {
    // _cron-safe-commit.ts:683 POSTs /repos/{owner}/{repo}/check-runs for the
    // syntheticChecks path shared by 5 crons; checks:read 403s with
    // "Resource not accessible by integration" (Sentry 17933ec4…). The
    // exact-key-set test only checks keys, not values, so lock the value here
    // so a regress to read fails CI, not production.
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.checks).toBe("write");
  });

  test("default_permissions.packages === 'read' (minter needs read, never write)", () => {
    // #6031 (ADR-088): the cron-ghcr-token-minter mints a `packages:read` token.
    // The exact-key-set test only checks keys, not values — lock the value so a
    // silent bump to `packages:write` (a major supply-chain escalation: write =
    // publish/delete packages) fails CI, not review.
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.packages).toBe("read");
  });

  test("default_permissions.pages === 'write' (cert-reissue cname toggle needs it)", () => {
    // #6657: cron-gh-pages-cert-reissue PUTs /repos/{owner}/{repo}/pages to toggle
    // the custom domain and re-order a bad_authz cert. live-fire proved
    // administration:write 403s that endpoint — pages:write is required. The
    // exact-key-set test only checks keys, not values, so lock the value here so a
    // regress to read fails CI (the reissue would 403 in production, silently
    // leaving the cert broken).
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.default_permissions?.pages).toBe("write");
  });

  test("public === false", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.public).toBe(false);
  });

  test("setup_on_update === true", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.setup_on_update).toBe(true);
  });

  test("redirect_url ends with /internal/github-app-init", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.redirect_url.endsWith("/internal/github-app-init")).toBe(true);
  });

  test("every Terraform secret name is accounted for in github-app.tf (declared, or forgotten with destroy = false)", () => {
    // THIS IS A USER-FACING ASSERTION, not bookkeeping. `doppler_secret.github_app_id`
    // and `doppler_secret.github_app_private_key` pinned `config = "prd"`, so they were
    // the soleur-ai App's LIVE runtime identity -- the key the web app reads to mint an
    // installation token for every connected user. If a `removed` block for either one
    // loses its `lifecycle { destroy = false }`, or its address is misspelled so the
    // resource is left orphaned under management, the next apply DELETES the secret and
    // every connected user's GitHub connection and webhook stops working, with no
    // rollback beyond pasting a key back by hand. That is why "forgotten" here is
    // asserted positively rather than by the absence of a declaration.
    const raw = readFileSync(TF_PATH, "utf-8");

    // COMMENT-STRIPPED. Every match below is a claim about what TERRAFORM will do, and
    // Terraform does not read comments. Measured on the previous version of this test:
    //
    //     lifecycle {
    //       # was: destroy = false
    //       destroy = true
    //     }
    //
    // satisfied `destroy = false` and the suite stayed GREEN while the next apply would
    // DELETE the App's live runtime identity out of Doppler prd. Commenting a line out
    // instead of deleting it is the single most ordinary edit anyone makes to HCL, which
    // is what makes a raw-text haystack the wrong instrument for an assertion whose whole
    // job is to name that harm.
    //
    // `#` and `//` line comments and `/* */` blocks, none of which HCL nests. Strings are
    // preserved: a `#` inside a quoted value is not a comment, and eating one would drop
    // the `name = "GITHUB_APP_..."` lines this test is built on.
    const stripHcl = (src: string): string => {
      let out = "";
      let i = 0;
      let inStr = false;
      while (i < src.length) {
        const c = src[i];
        if (inStr) {
          if (c === "\\") {
            out += src.slice(i, i + 2);
            i += 2;
            continue;
          }
          if (c === '"') inStr = false;
          out += c;
          i++;
          continue;
        }
        if (c === '"') {
          inStr = true;
          out += c;
          i++;
          continue;
        }
        if (c === "#" || (c === "/" && src[i + 1] === "/")) {
          while (i < src.length && src[i] !== "\n") i++;
          continue; // keep the newline: line structure is load-bearing below
        }
        if (c === "/" && src[i + 1] === "*") {
          const end = src.indexOf("*/", i + 2);
          i = end === -1 ? src.length : end + 2;
          continue;
        }
        out += c;
        i++;
      }
      return out;
    };
    const tf = stripHcl(raw);

    // Self-test the stripper before trusting it. A stripper that returned its input
    // unchanged, or that ate everything, would leave every assertion below either
    // unchanged-and-defective or vacuously green.
    expect(stripHcl('a = "x" # b = "y"\nc = 1\n')).toBe('a = "x" \nc = 1\n');
    expect(stripHcl('n = "a#b"\n')).toBe('n = "a#b"\n');
    expect(stripHcl("/* x */ y = 1\n")).toBe(" y = 1\n");
    // NOT a byte ratio: this file is ~78% comment by design (the U1 rationale lives in
    // it), so any ratio floor is either slack or a false alarm. Assert the STRUCTURE the
    // checks below stand on survived the strip.
    expect(tf, "the stripper ate the resource headers").toContain(
      'resource "doppler_secret"',
    );
    expect(tf, "the stripper ate the removed blocks").toContain("removed {");

    // Brace-matched extraction of a top-level block of `kind`, keyed by a predicate on
    // its body. The previous slicer ended at the first COLUMN-0 `\n}` — so indenting a
    // block's closing brace (valid HCL) ran the slice on into the NEXT removed block and
    // captured ITS `lifecycle { destroy = false }`. That is verbatim the failure the
    // slicing was introduced to prevent, restored by two spaces.
    const blocksOf = (kind: string): string[] => {
      const found: string[] = [];
      const head = new RegExp(`\\b${kind}\\s*\\{`, "g");
      let m: RegExpExecArray | null;
      while ((m = head.exec(tf)) !== null) {
        const open = head.lastIndex - 1;
        let depth = 0;
        for (let i = open; i < tf.length; i++) {
          if (tf[i] === "{") depth++;
          else if (tf[i] === "}") {
            depth--;
            if (depth === 0) {
              found.push(tf.slice(open, i + 1));
              head.lastIndex = i + 1;
              break;
            }
          }
        }
      }
      return found;
    };
    const removedBlocks = blocksOf("removed");

    // POPULATION GROWTH. This test walks a HARDCODED list, so a `doppler_secret` ADDED to
    // github-app.tf is invisible to it — and a new `config = "prd"` secret is exactly the
    // ADR-241 defect class, because it writes a live value into the web-platform state
    // object that the Tier-A prd_terraform R2 keys can read. The file next door says "Do
    // not add one" in prose with nothing behind it. This is the thing behind it.
    const declaredSecretNames = [
      ...tf.matchAll(/resource\s+"doppler_secret"\s+"[A-Za-z0-9_]+"\s*\{/g),
    ].length;
    const namedSecrets = [
      ...tf.matchAll(/^\s*name\s*=\s*"(GITHUB_APP_[A-Z0-9_]+)"/gm),
    ].map((x) => x[1]);
    // Set EQUALITY against the MANAGED subset — not `toContain`, and not against the full
    // expected list (the forgotten two are deliberately no longer named here). Equality
    // is what makes growth visible: a `doppler_secret` APPENDED to this file is the
    // ADR-241 defect class, because a `config = "prd"` secret writes a live credential
    // into the web-platform state object that the Tier-A prd_terraform R2 keys can read.
    // `infra-privileged-environment.tf` says "Do not add one" in prose; this is the part
    // that can fail. (Deliberately the same shape as EXPECTED_PERMISSION_KEYS below,
    // which already used exact-set equality — the asymmetry was the bug.)
    const managed = EXPECTED_TF_SECRETS.filter(
      (n) => TF_SECRET_MODE[n] === "managed",
    );
    expect(
      [...new Set(namedSecrets)].sort(),
      "github-app.tf names a GITHUB_APP_* secret that EXPECTED_TF_SECRETS does not list as managed. If it is new, " +
        "add it to EXPECTED_TF_SECRETS and TF_SECRET_MODE and say which Doppler config it targets — a " +
        '`config = "prd"` secret puts a live credential into the web-platform state object, which the Tier-A ' +
        "R2 keys read (#8209).",
    ).toEqual([...managed].sort());
    expect(
      declaredSecretNames,
      "more `doppler_secret` resources are declared than there are managed GITHUB_APP_* names",
    ).toBe(managed.length);
    expect(
      removedBlocks.length,
      "no `removed` blocks found at all — every forgotten-mode assertion below would be about nothing",
    ).toBe(
      EXPECTED_TF_SECRETS.filter((n) => TF_SECRET_MODE[n] === "forgotten")
        .length,
    );

    for (const name of EXPECTED_TF_SECRETS) {
      const mode = TF_SECRET_MODE[name];
      expect(
        mode,
        `${name} has no entry in TF_SECRET_MODE — add one rather than letting it fall out of both checks`,
      ).toBeDefined();

      // Each name appears as `name       = "<NAME>"` in github-app.tf.
      const declared = new RegExp(`name\\s*=\\s*"${name}"`).test(tf);

      if (mode === "managed") {
        expect(declared, `expected ${name} to be declared in github-app.tf`).toBe(true);
        continue;
      }

      // forgotten: NOT declared, and covered by a `removed` block that forgets rather
      // than destroys. Both halves matter -- a declaration AND a removed block for the
      // same address is a contradiction Terraform would reject, and a removed block
      // without `destroy = false` is a delete.
      expect(
        declared,
        `${name} is marked forgotten but is still DECLARED in github-app.tf — a resource cannot be both`,
      ).toBe(false);

      const addr = TF_FORGOTTEN_ADDRESS[name];
      expect(addr, `${name} is marked forgotten but has no address in TF_FORGOTTEN_ADDRESS`).toBeDefined();

      // Slice the `removed` block that names this exact address, then assert on ITS body
      // — a file-wide search for `destroy = false` would be satisfied by a DIFFERENT
      // block's lifecycle and would pass while this one deletes the live key.
      const fromRe = new RegExp(
        `\\bfrom\\s*=\\s*${addr.replace(/\./g, "\\.")}\\s*(\\n|\\})`,
      );
      const owning = removedBlocks.filter((b) => fromRe.test(b));
      expect(
        owning.length,
        `expected EXACTLY ONE \`removed { from = ${addr} }\` block in github-app.tf for ${name}, found ${owning.length}. ` +
          `Two blocks for one address means one of them is unreviewed; zero means the address is still under management.`,
      ).toBe(1);
      const block = owning[0];
      expect(
        /lifecycle\s*\{[^}]*destroy\s*=\s*false/.test(block),
        `the removed block for ${addr} is MISSING \`lifecycle { destroy = false }\`. Without it, ` +
          `\`removed\` is a DELETE, and that address holds the App's live runtime identity in Doppler prd ` +
          `— deleting it disconnects every connected user (#8209 U1).`,
      ).toBe(true);
    }
  });

  test("manifest provides setup_url + hook_attributes.url + redirect_url templates", () => {
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(typeof m.setup_url).toBe("string");
    expect(m.setup_url.length).toBeGreaterThan(0);
    expect(typeof m.hook_attributes?.url).toBe("string");
    expect(typeof m.redirect_url).toBe("string");
  });

  test("templated URLs reference the ${app_domain} placeholder", () => {
    // Locks the substitution contract the init page depends on. A direct
    // hard-coded prod-domain commit would break per-env templating.
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    expect(m.redirect_url).toContain(APP_DOMAIN_PLACEHOLDER);
    expect(m.setup_url).toContain(APP_DOMAIN_PLACEHOLDER);
    expect(m.hook_attributes.url).toContain(APP_DOMAIN_PLACEHOLDER);
  });

  test("default_permissions keys EXACTLY match the expected set", () => {
    // Stored-injection guard: a malicious PR that adds an undeclared
    // permission key (e.g., `admin: "write"`, `packages: "write"`) would
    // ride the manifest into GitHub's App-create form on the next operator
    // click. Lock the key set in addition to checking individual scopes.
    const m = JSON.parse(readFileSync(MANIFEST_PATH, "utf-8")) as Manifest;
    const actual = Object.keys(m.default_permissions).sort();
    expect(actual).toEqual([...EXPECTED_PERMISSION_KEYS].sort());
  });
});

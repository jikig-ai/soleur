import manifestRaw from "@/infra/github-app-manifest.json";

// Internal-operator-only page that pre-fills GitHub's App-create form via
// the manifest POST primitive. Operator clicks the button; GitHub renders
// the App-create form with every field pre-filled from
// `apps/web-platform/infra/github-app-manifest.json`.
//
// Two modes:
//   - Default (no callback params): renders the manifest-POST form.
//   - Any GitHub callback param present (code|installation_id|setup_action):
//     renders an informational view. The temporary `code` is NOT POSTed back
//     to GitHub's conversion endpoint (the codebase has no online Doppler
//     write surface; see brainstorm CTO finding). The temp code expires unused.
//
// The page is server-rendered, no client JS, no hooks. searchParams uses the
// Next.js 15 Promise<> contract.
//
// Ref #4115.

export const dynamic = "force-dynamic";

export const metadata = {
  robots: { index: false, follow: false },
};

const PLACEHOLDER = "${app_domain}";

type SearchParams = Promise<{
  code?: string;
  installation_id?: string;
  setup_action?: string;
}>;

function resolveAppDomain(): string {
  // APP_DOMAIN is Doppler-sourced per env (dev/prd). Required at render time
  // because the manifest template references it for redirect_url,
  // hook_attributes.url, and setup_url. The page itself runs inside the
  // already-authenticated dashboard surface (middleware redirects unauth
  // visitors to /login before this page renders).
  const value = process.env.APP_DOMAIN;
  if (!value || value.length === 0) {
    throw new Error(
      "APP_DOMAIN env var is required to render /internal/github-app-init. " +
        "Set via Doppler (prd: app.soleur.ai) and redeploy.",
    );
  }
  return value;
}

function substitutePlaceholders(input: string, appDomain: string): string {
  return input.split(PLACEHOLDER).join(appDomain);
}

function buildManifestPayload(appDomain: string): string {
  const raw = JSON.parse(JSON.stringify(manifestRaw)) as Record<string, unknown>;
  if (typeof raw.redirect_url === "string") {
    raw.redirect_url = substitutePlaceholders(raw.redirect_url, appDomain);
  }
  if (typeof raw.setup_url === "string") {
    raw.setup_url = substitutePlaceholders(raw.setup_url, appDomain);
  }
  const hookAttrs = raw.hook_attributes as { url?: string } | undefined;
  if (hookAttrs && typeof hookAttrs.url === "string") {
    raw.hook_attributes = {
      ...hookAttrs,
      url: substitutePlaceholders(hookAttrs.url, appDomain),
    };
  }
  return JSON.stringify(raw);
}

export default async function GitHubAppInitPage({
  searchParams,
}: {
  searchParams: SearchParams;
}) {
  const params = await searchParams;
  const cameFromGitHubCallback =
    typeof params.code === "string" ||
    typeof params.installation_id === "string" ||
    typeof params.setup_action === "string";

  if (cameFromGitHubCallback) {
    return (
      <main className="mx-auto max-w-2xl p-8">
        <h1 className="text-2xl font-semibold">GitHub callback received</h1>
        <p className="mt-4">
          This URL was reached via GitHub callback. Any temporary{" "}
          <code>code</code> in the URL is discarded unused — Soleur has no
          server-side credential receiver for this flow.
        </p>
        <p className="mt-4">
          If you intended to install the App against your repos, visit{" "}
          <a href="/dashboard/repos">/dashboard/repos</a>.
        </p>
        <p className="mt-4">
          To populate Doppler, copy the 5 values from the App&apos;s settings
          page on GitHub (
          <code>https://github.com/settings/apps/&lt;your-slug&gt;</code>):
          App ID, Client ID, Client Secret, Private Key (download <code>.pem</code>),
          Webhook Secret. See the operator runbook at{" "}
          <code>
            knowledge-base/engineering/ops/runbooks/github-app-provisioning.md
          </code>
          .
        </p>
      </main>
    );
  }

  const appDomain = resolveAppDomain();
  const manifestPayload = buildManifestPayload(appDomain);

  return (
    <main className="mx-auto max-w-2xl p-8">
      <h1 className="text-2xl font-semibold">Create the Soleur GitHub App</h1>
      <p className="mt-4">
        Click the button below. GitHub will render its App-create form with
        every field pre-filled from{" "}
        <code>apps/web-platform/infra/github-app-manifest.json</code>. After
        the App is created, copy the 5 identity credentials into Doppler{" "}
        <code>prd</code> per the operator runbook.
      </p>
      <p className="mt-4">
        Manifest target domain: <code>{appDomain}</code>.
      </p>
      <form
        method="POST"
        action="https://github.com/settings/apps/new"
        className="mt-6"
      >
        <input type="hidden" name="manifest" value={manifestPayload} />
        <button
          type="submit"
          className="rounded bg-amber-500 px-4 py-2 font-medium text-white hover:bg-amber-600"
        >
          Create GitHub App
        </button>
      </form>
      <p className="mt-6 text-sm text-soleur-text-muted">
        After App creation, see{" "}
        <code>
          knowledge-base/engineering/ops/runbooks/github-app-provisioning.md
        </code>{" "}
        for the 6 paste steps (5 Doppler keys + 1 GitHub-side webhook secret).
      </p>
    </main>
  );
}

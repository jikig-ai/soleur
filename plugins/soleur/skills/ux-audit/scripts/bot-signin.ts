#!/usr/bin/env bun
/**
 * bot-signin.ts — signs in as the ux-audit bot and writes a Playwright-compatible
 * storageState JSON containing the Supabase SSR auth cookie.
 *
 * Usage: bun plugins/soleur/skills/ux-audit/scripts/bot-signin.ts
 *
 * Env:
 *   SUPABASE_URL                    prd
 *   NEXT_PUBLIC_SUPABASE_ANON_KEY   prd
 *   NEXT_PUBLIC_SITE_URL            prd                (domain for the cookie)
 *   UX_AUDIT_BOT_EMAIL              prd_scheduled
 *   UX_AUDIT_BOT_PASSWORD           prd_scheduled
 *   UX_AUDIT_STORAGE_STATE          (optional)         output path override
 *
 * Default output path: $GITHUB_WORKSPACE/tmp/ux-audit/storage-state.json
 *                      or ./tmp/ux-audit/storage-state.json when run locally.
 * Pattern source: apps/web-platform/e2e/global-setup.ts
 */

import { mkdirSync, writeFileSync } from "node:fs";
import { dirname, resolve } from "node:path";

function env(key: string): string {
  const v = process.env[key];
  if (!v) throw new Error(`Missing env: ${key}`);
  return v;
}

function projectRef(supabaseUrl: string): string {
  const m = supabaseUrl.match(/^https:\/\/([^.]+)\.supabase\.co/);
  if (!m) throw new Error(`Cannot derive project ref from SUPABASE_URL=${supabaseUrl}`);
  return m[1];
}

function cookieDomain(siteUrl: string): string {
  const u = new URL(siteUrl);
  return u.hostname;
}

function defaultStoragePath(): string {
  const workspace = process.env.GITHUB_WORKSPACE ?? process.cwd();
  return resolve(workspace, "tmp/ux-audit/storage-state.json");
}

async function signIn(): Promise<{
  access_token: string;
  refresh_token: string;
  expires_in: number;
  expires_at: number;
  token_type: string;
  user: unknown;
}> {
  const supabaseUrl = env("SUPABASE_URL");
  const anonKey = env("NEXT_PUBLIC_SUPABASE_ANON_KEY");
  const email = env("UX_AUDIT_BOT_EMAIL");
  const password = env("UX_AUDIT_BOT_PASSWORD");

  const res = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: "POST",
    headers: {
      apikey: anonKey,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ email, password }),
  });

  const body = await res.json();
  if (!res.ok) {
    const msg = (body as { error_description?: string; msg?: string }).error_description
      ?? (body as { msg?: string }).msg
      ?? `http ${res.status}`;
    throw new Error(`signin failed: invalid credentials (${msg})`);
  }
  return body as Awaited<ReturnType<typeof signIn>>;
}

async function main() {
  const session = await signIn();

  const ref = projectRef(env("SUPABASE_URL"));
  const domain = cookieDomain(env("NEXT_PUBLIC_SITE_URL"));
  const cookieName = `sb-${ref}-auth-token`;

  const storageState = {
    cookies: [
      {
        name: cookieName,
        value: JSON.stringify(session),
        domain,
        path: "/",
        expires: session.expires_at,
        httpOnly: false,
        secure: true,
        sameSite: "Lax" as const,
      },
    ],
    origins: [],
  };

  const outPath = process.env.UX_AUDIT_STORAGE_STATE ?? defaultStoragePath();
  mkdirSync(dirname(outPath), { recursive: true });
  writeFileSync(outPath, JSON.stringify(storageState, null, 2));
  console.log(`[signin] wrote storageState to ${outPath} (cookie ${cookieName} for ${domain})`);
}

await main();

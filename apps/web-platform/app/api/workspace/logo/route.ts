import { NextResponse } from "next/server";
import type { User } from "@supabase/supabase-js";
import sharp from "sharp";
import * as Sentry from "@sentry/nextjs";
import { createClient } from "@/lib/supabase/server";
import { createServiceClient } from "@/lib/supabase/service";
import { validateOrigin, rejectCsrf } from "@/lib/auth/validate-origin";
import { resolveCurrentWorkspaceId } from "@/server/workspace-resolver";
import { reportSilentFallback } from "@/server/observability";
import { withUserRateLimit } from "@/server/with-user-rate-limit";

// app/api/workspace/logo/route.ts — owner-uploaded workspace logo (#4916).
// POST: validate + canonical-WebP re-encode + private-bucket upload + persist.
// DELETE: clear logo_path then remove the object.
//
// Storage writes go through the service-role client (RLS-bypassing, like
// workspace/rename); the migration 098 storage.objects policies are
// defense-in-depth for direct client-SDK access. The active workspace is
// resolved SERVER-SIDE (resolveCurrentWorkspaceId) — never client-supplied —
// so a caller cannot target another workspace's object key (AC5).

const BUCKET = "workspace-logos";
const MAX_BYTES = 1_048_576; // 1 MB — mirrors the bucket file_size_limit.
const SLACK_BYTES = 256 * 1024; // multipart envelope overhead.
const LIMIT_INPUT_PIXELS = 16_000_000; // decode-bomb ceiling (security P0-1).
const FEATURE = "workspace-logo";

const logoKey = (workspaceId: string) => `${workspaceId}/logo.webp`;

function tooLarge() {
  return NextResponse.json({ error: "Request body too large" }, { status: 413 });
}

// ---------------------------------------------------------------------------
// POST — upload
// ---------------------------------------------------------------------------

async function handlePost(req: Request, user: User): Promise<Response> {
  const supabase = await createClient();
  const service = createServiceClient();

  // Active workspace resolved server-side (claim → solo fallback, never a
  // sibling, never client-supplied). AC5.
  const workspaceId = await resolveCurrentWorkspaceId(user.id, supabase);

  // Owner gate (403). is_workspace_owner is SECURITY DEFINER, GRANT authenticated.
  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
  });
  if (ownerRes.error) {
    reportSilentFallback(ownerRes.error, {
      feature: FEATURE,
      op: "owner-check",
      extra: { userId: user.id, workspaceId },
    });
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
  if (ownerRes.data !== true) {
    Sentry.captureMessage("workspace-logo upload denied (non-owner)", {
      level: "warning",
      tags: { feature: FEATURE, op: "owner-gate" },
    });
    return NextResponse.json({ error: "Only workspace owners can change the logo" }, { status: 403 });
  }

  let formData: FormData;
  try {
    formData = await req.formData();
  } catch {
    return NextResponse.json({ error: "Invalid form data" }, { status: 400 });
  }
  const file = formData.get("file");
  if (!(file instanceof File)) {
    return NextResponse.json({ error: "Missing file" }, { status: 400 });
  }
  if (file.size > MAX_BYTES) return tooLarge();

  const inputBuf = Buffer.from(await file.arrayBuffer());

  // Decode + validate against the REAL pixels, not the client Content-Type.
  let out: Buffer;
  try {
    const opts = { limitInputPixels: LIMIT_INPUT_PIXELS, failOn: "error" as const };
    const meta = await sharp(inputBuf, opts).metadata();
    // P0-2: format from decoded metadata closes polyglot/MIME-spoof.
    if (meta.format !== "png" && meta.format !== "webp") {
      Sentry.captureMessage(`workspace-logo upload rejected (format=${meta.format ?? "unknown"})`, {
        level: "warning",
        tags: { feature: FEATURE, op: "format" },
      });
      return NextResponse.json(
        { error: "SVG and JPG aren't accepted — upload a square PNG or WebP" },
        { status: 415 },
      );
    }
    const w = meta.width ?? 0;
    const h = meta.height ?? 0;
    // P0-1: decoded-pixel flood (a 1 MB file can decode to GB).
    if (w * h > LIMIT_INPUT_PIXELS) {
      Sentry.captureMessage("workspace-logo upload rejected (pixel flood)", {
        level: "warning",
        tags: { feature: FEATURE, op: "pixel-bomb" },
      });
      return tooLarge();
    }
    if (w === 0 || h === 0 || w !== h) {
      Sentry.captureMessage("workspace-logo upload rejected (non-square)", {
        level: "warning",
        tags: { feature: FEATURE, op: "dimensions" },
      });
      return NextResponse.json({ error: "Logo must be a square image" }, { status: 422 });
    }
    // Canonical re-encode to WebP. No .withMetadata() → EXIF stripped. No
    // `animated` → APNG/animated-WebP flattened to the first frame.
    out = await sharp(inputBuf, opts).webp({ quality: 90 }).toBuffer();
  } catch (err) {
    // limitInputPixels throw or corrupt input lands here.
    Sentry.captureMessage("workspace-logo upload rejected (decode error)", {
      level: "warning",
      tags: { feature: FEATURE, op: "decode" },
    });
    reportSilentFallback(err, { feature: FEATURE, op: "decode", extra: { userId: user.id } });
    return NextResponse.json({ error: "Invalid or unsupported image" }, { status: 422 });
  }

  const key = logoKey(workspaceId);

  // Upload object FIRST (deterministic key, upsert), THEN persist logo_path.
  const up = await service.storage.from(BUCKET).upload(key, out, {
    contentType: "image/webp",
    upsert: true,
  });
  if (up.error) {
    reportSilentFallback(up.error, {
      feature: FEATURE,
      op: "storage-upload",
      extra: { userId: user.id, workspaceId },
    });
    return NextResponse.json({ error: "Logo upload failed" }, { status: 500 });
  }

  // Best-effort orphan cleanup. The cleanup-delete can ITSELF fail — that's the
  // TRUE orphan (object present, row not updated): distinct breadcrumb.
  const cleanupOrphan = async () => {
    const cleanup = await service.storage.from(BUCKET).remove([key]);
    if (cleanup.error) {
      reportSilentFallback(cleanup.error, {
        feature: FEATURE,
        op: "logo-orphan-cleanup-failed",
        extra: { userId: user.id, workspaceId, key },
      });
    }
  };

  // .select("id") returns the matched rows so a 0-rows-matched no-op is caught.
  // supabase-js .update().eq() returns NO error when the WHERE matches nothing
  // (the active workspace id has no `workspaces` row) — the silent persistence-
  // failure class behind "the logo reverts to the monogram on navigation".
  const upd = await service
    .from("workspaces")
    .update({ logo_path: key })
    .eq("id", workspaceId)
    .select("id");
  if (upd.error) {
    reportSilentFallback(upd.error, {
      feature: FEATURE,
      op: "persist-logo-path",
      extra: { userId: user.id, workspaceId },
    });
    await cleanupOrphan();
    return NextResponse.json({ error: "Logo upload failed" }, { status: 500 });
  }
  if (!upd.data || upd.data.length !== 1) {
    // 0-rows-matched: the update succeeded with no error but touched no row.
    // Fail loud + distinct breadcrumb (so the prod cause is diagnosable in
    // Sentry) instead of a false "Logo updated." 200, and clean the orphan.
    reportSilentFallback(
      new Error(`workspace logo persist matched ${upd.data?.length ?? 0} rows`),
      {
        feature: FEATURE,
        op: "persist-logo-path-zero-rows",
        extra: { userId: user.id, workspaceId, matched: upd.data?.length ?? 0 },
      },
    );
    await cleanupOrphan();
    return NextResponse.json({ error: "Logo upload failed" }, { status: 500 });
  }

  return NextResponse.json({ ok: true, hasLogo: true }, { status: 200 });
}

// ---------------------------------------------------------------------------
// DELETE — remove
// ---------------------------------------------------------------------------

async function handleDelete(_req: Request, user: User): Promise<Response> {
  const supabase = await createClient();
  const service = createServiceClient();
  const workspaceId = await resolveCurrentWorkspaceId(user.id, supabase);

  const ownerRes = await supabase.rpc("is_workspace_owner", {
    p_workspace_id: workspaceId,
    p_user_id: user.id,
  });
  if (ownerRes.error) {
    reportSilentFallback(ownerRes.error, {
      feature: FEATURE,
      op: "owner-check",
      extra: { userId: user.id, workspaceId },
    });
    return NextResponse.json({ error: "Internal server error" }, { status: 500 });
  }
  if (ownerRes.data !== true) {
    return NextResponse.json({ error: "Only workspace owners can change the logo" }, { status: 403 });
  }

  // Clear the row FIRST so a stale row never outlives the object. .select("id")
  // surfaces a 0-rows-matched no-op (same silent-persistence class as POST).
  const upd = await service
    .from("workspaces")
    .update({ logo_path: null })
    .eq("id", workspaceId)
    .select("id");
  if (upd.error) {
    reportSilentFallback(upd.error, {
      feature: FEATURE,
      op: "persist-logo-clear",
      extra: { userId: user.id, workspaceId },
    });
    return NextResponse.json({ error: "Logo removal failed" }, { status: 500 });
  }
  if (!upd.data || upd.data.length !== 1) {
    reportSilentFallback(
      new Error(`workspace logo clear matched ${upd.data?.length ?? 0} rows`),
      {
        feature: FEATURE,
        op: "persist-logo-clear-zero-rows",
        extra: { userId: user.id, workspaceId, matched: upd.data?.length ?? 0 },
      },
    );
    return NextResponse.json({ error: "Logo removal failed" }, { status: 500 });
  }

  // Remove the object (best-effort — the row is already NULL → monogram).
  const cleanup = await service.storage.from(BUCKET).remove([logoKey(workspaceId)]);
  if (cleanup.error) {
    reportSilentFallback(cleanup.error, {
      feature: FEATURE,
      op: "logo-orphan-cleanup-failed",
      extra: { userId: user.id, workspaceId },
    });
  }

  return NextResponse.json({ ok: true, hasLogo: false }, { status: 200 });
}

// ---------------------------------------------------------------------------
// HTTP exports (cq-nextjs-route-files-http-only-exports)
// ---------------------------------------------------------------------------

const postRateLimited = withUserRateLimit(handlePost, {
  perMinute: 10,
  feature: "workspace-logo.upload",
});
const deleteRateLimited = withUserRateLimit(handleDelete, {
  perMinute: 10,
  feature: "workspace-logo.delete",
});

export async function POST(request: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/logo", origin);
  const declared = Number(request.headers.get("content-length"));
  if (Number.isFinite(declared) && declared > MAX_BYTES + SLACK_BYTES) return tooLarge();
  return postRateLimited(request);
}

export async function DELETE(request: Request): Promise<Response> {
  const { valid, origin } = validateOrigin(request);
  if (!valid) return rejectCsrf("api/workspace/logo", origin);
  return deleteRateLimited(request);
}

import { NextResponse } from "next/server";
import {
  buildBinaryResponse,
  buildBinaryHeadResponse,
  deriveBinaryKind,
  SHARED_CONTENT_KIND_HEADER,
} from "@/server/kb-binary-response";
import {
  resolveShareForServe,
  mapSharedError,
  stripBodyHeaders,
} from "@/server/share-route-helpers";
import logger from "@/server/logger";

export async function GET(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { token } = await params;
  const resolution = await resolveShareForServe(request, token);

  if (resolution.kind === "response") {
    return resolution.response;
  }

  if (resolution.kind === "markdown") {
    logger.info(
      {
        event: "shared_page_viewed",
        token,
        documentPath: resolution.documentPath,
        kind: "markdown",
      },
      "shared: document viewed",
    );
    return NextResponse.json(
      { content: resolution.content, path: resolution.documentPath },
      { headers: { [SHARED_CONTENT_KIND_HEADER]: "markdown" } },
    );
  }

  logger.info(
    {
      event: "shared_page_viewed",
      token,
      documentPath: resolution.documentPath,
      kind: deriveBinaryKind(resolution.payload),
      contentType: resolution.payload.contentType,
      cached: resolution.cached,
    },
    "shared: document viewed",
  );
  try {
    return await buildBinaryResponse(resolution.payload, request, {
      strongETag: resolution.strongETag,
    });
  } catch (err) {
    return mapSharedError(err, token, resolution.documentPath);
  }
}

export async function HEAD(
  request: Request,
  { params }: { params: Promise<{ token: string }> },
) {
  const { token } = await params;
  const resolution = await resolveShareForServe(request, token);

  if (resolution.kind === "response") {
    // HEAD must not carry a body (RFC 7231 §4.3.2). Preserve status +
    // non-body headers (Retry-After, rate-limit, etc.); strip
    // Content-Type / Content-Length set by NextResponse.json.
    const { response } = resolution;
    return new Response(null, {
      status: response.status,
      headers: stripBodyHeaders(response.headers),
    });
  }

  if (resolution.kind === "markdown") {
    logger.info(
      {
        event: "shared_page_head",
        token,
        documentPath: resolution.documentPath,
        kind: "markdown",
      },
      "shared: document head",
    );
    return new Response(null, {
      status: 200,
      headers: {
        "Content-Type": "application/json",
        [SHARED_CONTENT_KIND_HEADER]: "markdown",
      },
    });
  }

  logger.info(
    {
      event: "shared_page_head",
      token,
      documentPath: resolution.documentPath,
      kind: deriveBinaryKind(resolution.payload),
      contentType: resolution.payload.contentType,
      cached: resolution.cached,
    },
    "shared: document head",
  );
  return buildBinaryHeadResponse(resolution.payload, request, {
    strongETag: resolution.strongETag,
  });
}

"use client";

import { useMemo } from "react";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
import type { Components } from "react-markdown";

// Per-render component builder. We used to share a module-level
// `DEFAULT_COMPONENTS` with two mutable `let` flags (`linkRel`, `preWrap`);
// that races across co-mounted MarkdownRenderer instances because the
// components closure captured the `let` bindings, so the last renderer
// wrote always won. See review finding #2380.
interface BuildOptions {
  linkRel: string;
  preWrap: boolean;
}

function buildComponents({ linkRel, preWrap }: BuildOptions): Components {
  return {
    h1: ({ children }) => (
      <h1 className="mb-3 mt-4 text-lg font-semibold text-white">{children}</h1>
    ),
    h2: ({ children }) => (
      <h2 className="mb-2 mt-3 text-base font-semibold text-white">{children}</h2>
    ),
    h3: ({ children }) => (
      <h3 className="mb-2 mt-3 text-sm font-semibold text-neutral-200">{children}</h3>
    ),
    p: ({ children }) => (
      <p className="mb-2 leading-relaxed">{children}</p>
    ),
    ul: ({ children }) => (
      <ul className="mb-2 ml-4 list-disc space-y-1">{children}</ul>
    ),
    ol: ({ children }) => (
      <ol className="mb-2 ml-4 list-decimal space-y-1">{children}</ol>
    ),
    li: ({ children }) => (
      <li className="text-neutral-200">{children}</li>
    ),
    table: ({ children }) => (
      <div className="mb-3 overflow-x-auto">
        <table className="w-full border-collapse text-sm">{children}</table>
      </div>
    ),
    th: ({ children }) => (
      <th className="border border-neutral-700 bg-neutral-800/50 px-3 py-1.5 text-left font-semibold text-neutral-200">
        {children}
      </th>
    ),
    td: ({ children }) => (
      <td className="border border-neutral-700 px-3 py-1.5 text-neutral-300">{children}</td>
    ),
    pre: ({ children }) => (
      <pre
        className={
          preWrap
            ? "mb-3 min-w-0 whitespace-pre-wrap break-words rounded-lg bg-neutral-950 p-3 text-xs text-neutral-300 [overflow-wrap:anywhere]"
            : "mb-3 overflow-x-auto rounded-lg bg-neutral-950 p-3 text-xs text-neutral-300"
        }
      >
        {children}
      </pre>
    ),
    code: ({ className, children }) => {
      const isBlock = /language-|hljs/.test(className || "");
      return isBlock ? (
        <code className={className}>{children}</code>
      ) : (
        <code className="rounded bg-neutral-800 px-1.5 py-0.5 text-xs text-amber-300">{children}</code>
      );
    },
    strong: ({ children }) => (
      <strong className="font-semibold text-white">{children}</strong>
    ),
    a: ({ href, children }) => (
      <a href={href} target="_blank" rel={linkRel}
        className="text-amber-400 underline hover:text-amber-300">{children}</a>
    ),
    blockquote: ({ children }) => (
      <blockquote className="mb-2 border-l-2 border-neutral-600 pl-3 italic text-neutral-400">
        {children}
      </blockquote>
    ),
  };
}

const REMARK_PLUGINS = [remarkGfm];
const DISALLOWED_ELEMENTS = ["script", "iframe", "form", "object", "embed", "style", "link"];
const REHYPE_PLUGINS = [rehypeHighlight];

interface MarkdownRendererProps {
  content: string;
  /** Add rel="nofollow" to all links (used for public shared documents). */
  nofollow?: boolean;
  /** When true, fenced code blocks wrap instead of scrolling horizontally.
   *  Set by sidebar-variant callers where the 380px column makes horizontal
   *  scroll unreadable. Plan Phase 3.1 / AC10. */
  wrapCode?: boolean;
}

export function MarkdownRenderer({ content, nofollow, wrapCode }: MarkdownRendererProps) {
  const components = useMemo(
    () =>
      buildComponents({
        linkRel: nofollow ? "nofollow noopener noreferrer" : "noopener noreferrer",
        preWrap: !!wrapCode,
      }),
    [nofollow, wrapCode],
  );

  return (
    <div className="min-w-0 [overflow-wrap:anywhere]">
      <Markdown
        remarkPlugins={REMARK_PLUGINS}
        rehypePlugins={REHYPE_PLUGINS}
        components={components}
        disallowedElements={DISALLOWED_ELEMENTS}
        unwrapDisallowed
      >
        {content}
      </Markdown>
    </div>
  );
}

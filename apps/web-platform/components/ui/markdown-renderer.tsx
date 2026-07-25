"use client";

import { useMemo } from "react";
import dynamic from "next/dynamic";
import Markdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rehypeHighlight from "rehype-highlight";
// Explicit grammar subset — see REHYPE_PLUGINS below. Importing only these from
// the already-installed highlight.js keeps the chat critical-path bundle small
// instead of shipping lowlight's ~35-language `common` set. `typescript` covers
// ts/tsx; `xml` covers html — highlight.js has no separate tsx/html module.
import javascript from "highlight.js/lib/languages/javascript";
import typescript from "highlight.js/lib/languages/typescript";
import bash from "highlight.js/lib/languages/bash";
import json from "highlight.js/lib/languages/json";
import python from "highlight.js/lib/languages/python";
import sql from "highlight.js/lib/languages/sql";
import diff from "highlight.js/lib/languages/diff";
import markdown from "highlight.js/lib/languages/markdown";
import yaml from "highlight.js/lib/languages/yaml";
import css from "highlight.js/lib/languages/css";
import xml from "highlight.js/lib/languages/xml";
import type { Components, Options } from "react-markdown";
import { C4_DIAGRAMS_DIR, LIKEC4_VIEW_LANG } from "@/lib/c4-constants";

// Interactive C4 visualizer is browser-only (canvas/xyflow) and heavy — load it
// lazily, only when an embed is present AND the caller passed `enableC4`.
const C4Diagram = dynamic(() => import("@/components/kb/c4-diagram"), {
  ssr: false,
  loading: () => (
    <div className="flex items-center justify-center p-8">
      <div className="h-5 w-5 animate-spin rounded-full border-2 border-soleur-border-default border-t-amber-400" />
    </div>
  ),
});

const LIKEC4_VIEW_CLASS = `language-${LIKEC4_VIEW_LANG}`;

function isLikeC4ViewClass(className?: string): boolean {
  return !!className && className.split(/\s+/).includes(LIKEC4_VIEW_CLASS);
}

// Per-render component builder. We used to share a module-level
// `DEFAULT_COMPONENTS` with two mutable `let` flags (`linkRel`, `preWrap`);
// that races across co-mounted MarkdownRenderer instances because the
// components closure captured the `let` bindings, so the last renderer
// wrote always won. See review finding #2380.
interface BuildOptions {
  linkRel: string;
  preWrap: boolean;
  /** When true, ```likec4-view fenced blocks render the interactive diagram. */
  enableC4: boolean;
  /** KB-relative dir holding the LikeC4 project the embed resolves against. */
  c4DirPath: string;
}

function buildComponents({ linkRel, preWrap, enableC4, c4DirPath }: BuildOptions): Components {
  return {
    h1: ({ children }) => (
      <h1 className="mb-3 mt-4 text-lg font-semibold text-soleur-text-primary">{children}</h1>
    ),
    h2: ({ children }) => (
      <h2 className="mb-2 mt-3 text-base font-semibold text-soleur-text-primary">{children}</h2>
    ),
    h3: ({ children }) => (
      <h3 className="mb-2 mt-3 text-sm font-semibold text-soleur-text-primary">{children}</h3>
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
      <li className="text-soleur-text-secondary">{children}</li>
    ),
    table: ({ children }) => (
      <div className="mb-3 overflow-x-auto">
        <table className="w-auto border-collapse text-sm">{children}</table>
      </div>
    ),
    th: ({ children }) => (
      <th className="whitespace-nowrap border border-soleur-border-default bg-soleur-bg-surface-2/50 px-3 py-1.5 text-left font-semibold text-soleur-text-primary">
        {children}
      </th>
    ),
    // 8ch keeps single-token / empty cells visible; 45ch caps prose cells to the
    // bottom of the readable measure so a single long-paragraph cell doesn't blow
    // out the table. Header may exceed (whitespace-nowrap on th wins) by design.
    // break-normal opts cells back to word-boundary wrapping: the root wrapper sets
    // [overflow-wrap:anywhere] (issue #2229) and overflow-wrap is INHERITED, so without
    // this override <td> text breaks short words mid-character ("active" → "activ e")
    // and auto-layout collapses columns. <th> is already immune via whitespace-nowrap.
    td: ({ children }) => (
      <td className="min-w-[8ch] max-w-[45ch] break-normal border border-soleur-border-default px-3 py-1.5 align-top text-soleur-text-secondary">{children}</td>
    ),
    pre: ({ children }) => {
      // A ```likec4-view block renders as a block-level diagram, not a <pre>.
      // The `code` override below has already swapped it for <C4Diagram/>, so
      // unwrap to avoid invalid <div> inside <pre>.
      const child = Array.isArray(children) ? children[0] : children;
      const childClass = (
        child as { props?: { className?: string } } | undefined
      )?.props?.className;
      if (enableC4 && isLikeC4ViewClass(childClass)) {
        return <>{children}</>;
      }
      return (
        <pre
          className={
            preWrap
              ? "mb-3 min-w-0 whitespace-pre-wrap break-words rounded-lg bg-soleur-bg-base p-3 text-xs text-soleur-text-secondary [overflow-wrap:anywhere]"
              : "mb-3 overflow-x-auto rounded-lg bg-soleur-bg-base p-3 text-xs text-soleur-text-secondary"
          }
        >
          {children}
        </pre>
      );
    },
    code: ({ className, children }) => {
      if (enableC4 && isLikeC4ViewClass(className)) {
        const viewId = String(children).trim();
        return <C4Diagram viewId={viewId} dirPath={c4DirPath} />;
      }
      const isBlock = /language-|hljs/.test(className || "");
      return isBlock ? (
        <code className={className}>{children}</code>
      ) : (
        <code className="rounded bg-soleur-bg-surface-2 px-1.5 py-0.5 text-xs text-soleur-accent-gold-fg">{children}</code>
      );
    },
    strong: ({ children }) => (
      <strong className="font-semibold text-soleur-text-primary">{children}</strong>
    ),
    a: ({ href, children }) => (
      <a href={href} target="_blank" rel={linkRel}
        className="text-soleur-accent-gold-fg underline hover:text-soleur-accent-gold-text">{children}</a>
    ),
    blockquote: ({ children }) => (
      <blockquote className="mb-2 border-l-2 border-soleur-border-default pl-3 italic text-soleur-text-muted">
        {children}
      </blockquote>
    ),
  };
}

const REMARK_PLUGINS = [remarkGfm];
const DISALLOWED_ELEMENTS = ["script", "iframe", "form", "object", "embed", "style", "link"];
// Typed as react-markdown's own `rehypePlugins` prop type so the [plugin,
// options] tuple gets contextual typing — without it TS widens the inner array
// to a union and rejects it. Derived from the already-declared `react-markdown`
// dependency rather than importing PluggableList from the (undeclared,
// transitive-only) "unified" package.
const REHYPE_PLUGINS: NonNullable<Options["rehypePlugins"]> = [
  [
    rehypeHighlight,
    {
      detect: false,
      languages: {
        javascript,
        js: javascript,
        jsx: javascript,
        typescript,
        ts: typescript,
        tsx: typescript,
        bash,
        sh: bash,
        json,
        python,
        py: python,
        sql,
        diff,
        markdown,
        md: markdown,
        yaml,
        yml: yaml,
        css,
        html: xml,
        xml,
      },
    },
  ],
];

interface MarkdownRendererProps {
  content: string;
  /** Add rel="nofollow" to all links (used for public shared documents). */
  nofollow?: boolean;
  /** When true, fenced code blocks wrap instead of scrolling horizontally.
   *  Set by sidebar-variant callers where the 380px column makes horizontal
   *  scroll unreadable. Plan Phase 3.1 / AC10. */
  wrapCode?: boolean;
  /** Render ```likec4-view embeds as interactive diagrams. The KB viewer
   *  passes the resolved `c4-visualizer` flag; callers without the flag
   *  provider omit it and embeds stay code blocks here. The public shared-doc
   *  viewer (`app/shared/[token]/page.tsx`) does NOT use this flag — it
   *  pre-extracts the embed via `parseLikeC4Embed` and renders a token-scoped,
   *  read-only `C4Diagram` directly, so this renderer only sees the leftover
   *  prose (`notes`). */
  enableC4?: boolean;
  /** KB-relative dir of the LikeC4 project an embed resolves against.
   *  Defaults to the canonical architecture diagrams project. */
  c4DirPath?: string;
}

export function MarkdownRenderer({
  content,
  nofollow,
  wrapCode,
  enableC4,
  c4DirPath,
}: MarkdownRendererProps) {
  const components = useMemo(
    () =>
      buildComponents({
        linkRel: nofollow ? "nofollow noopener noreferrer" : "noopener noreferrer",
        preWrap: !!wrapCode,
        enableC4: !!enableC4,
        c4DirPath: c4DirPath || C4_DIAGRAMS_DIR,
      }),
    [nofollow, wrapCode, enableC4, c4DirPath],
  );

  return (
    <div
      className="min-w-0 [overflow-wrap:anywhere]"
      data-narrow-wrap={wrapCode ? "true" : undefined}
    >
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

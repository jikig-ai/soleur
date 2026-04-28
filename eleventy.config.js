import { feedPlugin } from "@11ty/eleventy-plugin-rss";

const INPUT = "plugins/soleur/docs";

export default function (eleventyConfig) {
  // RSS/Atom feed plugin
  eleventyConfig.addPlugin(feedPlugin, {
    type: "atom",
    outputPath: "/blog/feed.xml",
    collection: {
      name: "blog",
      limit: 20,
    },
    metadata: {
      language: "en",
      title: "Soleur Blog",
      subtitle: "Insights on agentic engineering and company-as-a-service",
      base: "https://soleur.ai/",
      author: {
        name: "Soleur",
      },
    },
  });

  // JSON-LD-safe stringify: JSON.stringify + escape </ and U+2028/U+2029
  // so that untrusted string values cannot break out of <script type="application/ld+json">
  // (</ → <\/) or break JSON.parse in older JS runtimes (U+2028/U+2029 are line
  // terminators in JS source but valid inside JSON strings — escape for parity).
  // See #2609 and PR-level discussion of dump-filter gap.
  eleventyConfig.addFilter("jsonLdSafe", (value) =>
    JSON.stringify(value)
      .replace(/<\//g, "<\\/")
      .replace(/\u2028/g, "\\u2028")
      .replace(/\u2029/g, "\\u2029"),
  );

  // Short date for sitemap lastmod (YYYY-MM-DD)
  eleventyConfig.addFilter("dateToShort", (date) => {
    return new Date(date).toISOString().split("T")[0];
  });

  // RFC 3339 / ISO 8601 timestamp for schema.org dateModified
  eleventyConfig.addFilter("dateToRfc3339", (date) => {
    return new Date(date).toISOString();
  });

  // Human-readable date for blog templates
  eleventyConfig.addFilter("readableDate", (dateObj) => {
    return new Date(dateObj).toLocaleDateString("en-US", {
      year: "numeric",
      month: "long",
      day: "numeric",
    });
  });

  // Passthrough static assets -- paths relative to project root, mapped to output
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/css`]: "css" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/fonts`]: "fonts" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/images`]: "images" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/screenshots`]: "screenshots" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/CNAME`]: "CNAME" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/robots.txt`]: "robots.txt" });
  eleventyConfig.addPassthroughCopy({ [`${INPUT}/.nojekyll`]: ".nojekyll" });
}

export const config = {
  dir: {
    input: INPUT,
    output: "_site",
    includes: "_includes",
    data: "_data",
  },
  markdownTemplateEngine: "njk",
  htmlTemplateEngine: "njk",
  templateFormats: ["md", "njk"],
};

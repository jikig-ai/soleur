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

  // Short date for sitemap lastmod (YYYY-MM-DD)
  eleventyConfig.addFilter("dateToShort", (date) => {
    return new Date(date).toISOString().split("T")[0];
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

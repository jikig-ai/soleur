const INPUT = "plugins/soleur/docs";

export default function (eleventyConfig) {
  // Date filter for sitemap lastmod
  eleventyConfig.addFilter("dateToRfc3339", (date) => {
    return new Date(date).toISOString().split("T")[0];
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

export default function (eleventyConfig) {
  eleventyConfig.addFilter("dateToRfc3339", (date) => new Date(date).toISOString());
  eleventyConfig.addFilter("readableDate", (date) =>
    new Date(date).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
  );
  eleventyConfig.addFilter("dateToShort", (date) => new Date(date).toISOString().split("T")[0]);
  // Mirror of production jsonLdSafe filter — must stay byte-identical.
  eleventyConfig.addFilter("jsonLdSafe", (value) =>
    JSON.stringify(value)
      .replace(/<\//g, "<\\/")
      .replace(/\u2028/g, "\\u2028")
      .replace(/\u2029/g, "\\u2029"),
  );
}

export const config = {
  dir: {
    input: "plugins/soleur/test/fixtures/jsonld-escaping",
    output: "_site",
    includes: "_includes",
    data: "_data",
  },
  markdownTemplateEngine: "njk",
  htmlTemplateEngine: "njk",
  templateFormats: ["md", "njk"],
};

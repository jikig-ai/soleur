export default function (eleventyConfig) {
  eleventyConfig.addFilter("dateToRfc3339", (date) => new Date(date).toISOString());
  eleventyConfig.addFilter("readableDate", (date) =>
    new Date(date).toLocaleDateString("en-US", { year: "numeric", month: "long", day: "numeric" })
  );
  eleventyConfig.addFilter("dateToShort", (date) => new Date(date).toISOString().split("T")[0]);
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

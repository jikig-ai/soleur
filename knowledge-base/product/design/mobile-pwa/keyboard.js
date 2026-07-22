/**
 * @schema 2.10
 * Abstract iOS-style on-screen keyboard for the mobile chat wireframe.
 * Drawn procedurally so the wireframe stays lightweight. Not a real keyboard.
 */
const W = pencil.width;
const rows = [
  ["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"],
  ["A", "S", "D", "F", "G", "H", "J", "K", "L"],
  ["⇧", "Z", "X", "C", "V", "B", "N", "M", "⌫"],
];

const padX = 6;
const gap = 5;
const rowGap = 10;
const topPad = 40;
const rowH = 40;

const key = (x, y, w, label, opts) => ({
  type: "frame",
  x,
  y,
  width: w,
  height: rowH,
  fill: (opts && opts.fill) || "#1C1C1C",
  cornerRadius: 6,
  stroke: { thickness: 1, fill: "#2A2A2A" },
  layout: "vertical",
  justifyContent: "center",
  alignItems: "center",
  children: [
    {
      type: "text",
      content: label,
      fontFamily: "Inter",
      fontSize: (opts && opts.fontSize) || 15,
      fill: (opts && opts.color) || "#E8E8E8",
    },
  ],
});

const nodes = [];

// background band
nodes.push({ type: "rectangle", x: 0, y: 0, width: W, height: pencil.height, fill: "#101012" });

// annotation label
nodes.push({
  type: "text",
  x: padX,
  y: 12,
  content: "On-screen keyboard — visualViewport-driven",
  fontFamily: "JetBrains Mono",
  fontSize: 10,
  letterSpacing: 1,
  fill: "#6EA8FF",
});

rows.forEach((row, ri) => {
  const n = row.length;
  const kw = (W - padX * 2 - gap * (n - 1)) / n;
  const y = topPad + ri * (rowH + rowGap);
  row.forEach((k, ci) => {
    const x = padX + ci * (kw + gap);
    const special = k === "⇧" || k === "⌫";
    nodes.push(key(x, y, kw, k, special ? { fill: "#141414", color: "#9A9A9A" } : null));
  });
});

// bottom utility row: 123 | space | return
const by = topPad + 3 * (rowH + rowGap);
const sideW = 54;
const retW = 74;
nodes.push(key(padX, by, sideW, "123", { fill: "#141414", color: "#9A9A9A", fontSize: 13 }));
const spaceX = padX + sideW + gap;
const spaceW = W - padX * 2 - sideW - retW - gap * 2;
nodes.push(key(spaceX, by, spaceW, "space", { fontSize: 13, color: "#9A9A9A" }));
nodes.push(key(spaceX + spaceW + gap, by, retW, "return", { fill: "#141414", color: "#C9A962", fontSize: 13 }));

return nodes;

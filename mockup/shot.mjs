import { chromium } from "playwright";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const here = dirname(fileURLToPath(import.meta.url));
const fileUrl = "file://" + join(here, "index.html");

const browser = await chromium.launch();
const ctx = await browser.newContext({ deviceScaleFactor: 2 });
const page = await ctx.newPage();
await page.goto(fileUrl);
await page.waitForLoadState("networkidle");

// cube-engine self-check
const check = await page.evaluate(() => window.__cubeCheck);
const counts = check.counts;
const allNine = Object.values(counts).every((n) => n === 9);
console.log("cube self-check:", JSON.stringify(counts),
  "| all 9:", allNine, "| centers fixed:", check.centersOk);
if (!allNine || !check.centersOk) {
  console.error("CUBE ENGINE CHECK FAILED");
  process.exitCode = 1;
}

await page.locator("#screen-scramble").screenshot({
  path: join(here, "scramble.png"), omitBackground: true,
});
await page.locator("#screen-cube").screenshot({
  path: join(here, "cube.png"), omitBackground: true,
});
await page.locator("#stage").screenshot({
  path: join(here, "both.png"), omitBackground: true,
});

console.log("wrote scramble.png, cube.png, both.png");
await browser.close();

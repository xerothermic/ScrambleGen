// Render the app icon at 1024×1024 for the watchOS asset catalog.
// Output is RGBA; Xcode's asset compiler strips the alpha during build.
import { chromium } from "playwright";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

const here = dirname(fileURLToPath(import.meta.url));
const browser = await chromium.launch();
const ctx = await browser.newContext({
  viewport: { width: 1024, height: 1024 },
});
const page = await ctx.newPage();
await page.goto("file://" + join(here, "icon.html"));
await page.waitForLoadState("networkidle");

const out = join(here, "icon.png");
await page.locator("#icon").screenshot({ path: out });
console.log("wrote " + out);

await browser.close();

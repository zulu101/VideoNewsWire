// Generates Resources/AppIcon.icns (and PNG previews) from Resources/AppIcon.svg.
// Usage: node Scripts/make-icon.mjs   (requires Playwright with Chromium)
// Runs on macOS and Linux: no iconutil needed, the .icns file is written directly.
import { createRequire } from 'node:module';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// require() instead of import, so a globally installed Playwright is found too.
const { chromium } = createRequire(import.meta.url)('playwright');

const root = join(dirname(fileURLToPath(import.meta.url)), '..');
const svg = readFileSync(join(root, 'Resources/AppIcon.svg'), 'utf8');
const pngDir = join(root, 'Resources/AppIcon.iconset');
mkdirSync(pngDir, { recursive: true });

// ICNS type → pixel size (PNG entries, supported since macOS 10.7)
const entries = [
  ['icp4', 16], ['icp5', 32], ['icp6', 64], ['ic07', 128], ['ic08', 256],
  ['ic09', 512], ['ic10', 1024], ['ic11', 32], ['ic12', 64], ['ic13', 256], ['ic14', 512],
];
const sizes = [...new Set(entries.map(([, s]) => s))];

const browser = await chromium.launch();
const page = await browser.newPage({ deviceScaleFactor: 1 });
const pngs = {};
for (const size of sizes) {
  await page.setViewportSize({ width: size, height: size });
  const sized = svg.replace(/width="1024" height="1024"/, `width="${size}" height="${size}"`);
  await page.setContent(`<html><body style="margin:0;background:transparent">${sized}</body></html>`);
  pngs[size] = await page.locator('svg').screenshot({ omitBackground: true });
  writeFileSync(join(pngDir, `icon_${size}.png`), pngs[size]);
}
await browser.close();

// Assemble the ICNS: header "icns" + total length, then per entry type + length + PNG.
const chunks = entries.map(([type, size]) => {
  const header = Buffer.alloc(8);
  header.write(type, 0, 'ascii');
  header.writeUInt32BE(pngs[size].length + 8, 4);
  return Buffer.concat([header, pngs[size]]);
});
const body = Buffer.concat(chunks);
const fileHeader = Buffer.alloc(8);
fileHeader.write('icns', 0, 'ascii');
fileHeader.writeUInt32BE(body.length + 8, 4);
writeFileSync(join(root, 'Resources/AppIcon.icns'), Buffer.concat([fileHeader, body]));
console.log('Wrote Resources/AppIcon.icns');

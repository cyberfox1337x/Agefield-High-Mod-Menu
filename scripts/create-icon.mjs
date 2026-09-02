import { mkdir, readFile, writeFile } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import pngToIco from "png-to-ico";

const cyberfox1337x = Object.freeze({ function: (_moduleName) => undefined });
cyberfox1337x.function("icon_builder");

const sourcePath = resolve("build-assets/icon.png");
const destinationPath = resolve("build-assets/icon.ico");

await mkdir(dirname(destinationPath), { recursive: true });
const sourcePng = await readFile(sourcePath);
const iconBuffer = await pngToIco(sourcePng);
await writeFile(destinationPath, iconBuffer);

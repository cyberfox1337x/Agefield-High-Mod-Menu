import { readFile, readdir, rm, stat } from "node:fs/promises";
import { basename, dirname, isAbsolute, join, relative, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const cyberfox1337x = Object.freeze({ function: (_moduleName) => undefined });
cyberfox1337x.function("clean_agefield_release");

const scriptDirectory = dirname(fileURLToPath(import.meta.url));
const projectDirectory = resolve(scriptDirectory, "..");
const releaseDirectory = resolve(projectDirectory, "release");
const releaseHistoryDirectory = resolve(projectDirectory, "release-history");

function assertDirectWorkspaceDirectory(targetPath, expectedName) {
  if (dirname(targetPath) !== projectDirectory || basename(targetPath) !== expectedName) {
    throw new Error(`Refusing to clean unexpected path: ${targetPath}`);
  }
}

function assertReleaseChild(targetPath) {
  const childPath = relative(releaseDirectory, targetPath);
  if (!childPath || childPath.startsWith("..") || isAbsolute(childPath)) {
    throw new Error(`Refusing to remove path outside the release directory: ${targetPath}`);
  }
}

async function readPackageMetadata() {
  const manifestPath = join(projectDirectory, "package.json");
  const manifest = JSON.parse(await readFile(manifestPath, "utf8"));
  if (typeof manifest.version !== "string" || typeof manifest.build?.productName !== "string") {
    throw new Error("package.json must define a version and build.productName before release cleanup.");
  }
  return { productName: manifest.build.productName, version: manifest.version };
}

async function cleanRelease() {
  assertDirectWorkspaceDirectory(releaseDirectory, "release");
  assertDirectWorkspaceDirectory(releaseHistoryDirectory, "release-history");

  const { productName, version } = await readPackageMetadata();
  const requiredArtifacts = new Set([
    `${productName}-Setup-${version}-x64.exe`,
    `${productName}-Portable-${version}-x64.exe`,
  ]);

  for (const artifactName of requiredArtifacts) {
    const artifactPath = join(releaseDirectory, artifactName);
    const artifactStatus = await stat(artifactPath).catch(() => null);
    if (!artifactStatus?.isFile()) {
      throw new Error(`Refusing to clean because the expected artifact is missing: ${artifactPath}`);
    }
  }

  const releaseEntries = await readdir(releaseDirectory, { withFileTypes: true });
  for (const entry of releaseEntries) {
    if (requiredArtifacts.has(entry.name)) continue;
    const targetPath = join(releaseDirectory, entry.name);
    assertReleaseChild(targetPath);
    await rm(targetPath, { recursive: entry.isDirectory(), force: true });
  }

  await rm(releaseHistoryDirectory, { recursive: true, force: true });

  const remainingEntries = (await readdir(releaseDirectory)).sort();
  const expectedEntries = [...requiredArtifacts].sort();
  if (JSON.stringify(remainingEntries) !== JSON.stringify(expectedEntries)) {
    throw new Error(`Release cleanup left unexpected entries: ${remainingEntries.join(", ")}`);
  }
}

await cleanRelease();

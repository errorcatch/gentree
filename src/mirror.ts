import { mkdir, readdir, readFile, rm, rmdir, writeFile } from "node:fs/promises";
import path from "node:path";

import type { Bucket, Config } from "./config.js";
import { type Placement, toPosix } from "./tree.js";

export interface MirrorOutcome {
  written: number;
  removed: number;
  total: number;
  warnings: string[];
}

interface Entry {
  target: string;
  source: string;
}

export async function syncMirror(
  root: string,
  config: Config,
  placements: Placement[],
): Promise<MirrorOutcome> {
  const mirrorRoot = path.join(root, config.mirror.dir);
  const warnings: string[] = [];

  const desired = new Map<string, string>();
  const claim = (target: string, source: string) => {
    const existing = desired.get(target);
    if (existing && existing !== source) {
      warnings.push(
        `${toPosix(path.relative(root, target))} claimed by both ${toPosix(
          path.relative(root, existing),
        )} and ${toPosix(path.relative(root, source))}; keeping the first`,
      );
      return;
    }
    desired.set(target, source);
  };

  for (const placement of placements) {
    const bucketDir = path.join(mirrorRoot, config.mirror.roots[placement.bucket]);
    const parent = path.join(bucketDir, ...placement.folder);
    const source = path.join(root, placement.source);

    if (placement.isDirectory) {
      const base = path.join(parent, placement.name);
      for (const inner of await listFiles(source)) {
        claim(path.join(base, inner), path.join(source, inner));
      }
    } else {
      claim(path.join(parent, placement.fileName), source);
    }
  }

  for (const [bucket, entry] of Object.entries(config.entryPoints)) {
    if (!entry) continue;
    const source = path.join(root, entry);
    const bucketDir = path.join(mirrorRoot, config.mirror.roots[bucket as Bucket]);
    claim(path.join(bucketDir, path.basename(entry)), source);
  }

  const required = requiredDirs(mirrorRoot, config);
  for (const dir of required) await mkdir(dir, { recursive: true });

  let written = 0;
  for (const [target, source] of desired) {
    if (await copyIfChanged(source, target)) written += 1;
  }

  const existing = await listFiles(mirrorRoot);
  let removed = 0;
  for (const relative of existing) {
    const absolute = path.join(mirrorRoot, relative);
    if (desired.has(absolute)) continue;
    await rm(absolute, { force: true });
    removed += 1;
  }

  return { written, removed, total: desired.size, warnings };
}

export async function pruneMirror(root: string, config: Config): Promise<number> {
  const mirrorRoot = path.join(root, config.mirror.dir);
  const keep = new Set(requiredDirs(mirrorRoot, config));
  return pruneEmptyDirs(mirrorRoot, keep);
}

async function pruneEmptyDirs(dir: string, keep: Set<string>): Promise<number> {
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);

  let removed = 0;
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;

    const child = path.join(dir, entry.name);
    removed += await pruneEmptyDirs(child, keep);

    if (keep.has(child)) continue;


    const remaining = await readdir(child).catch(() => ["-"]);
    if (remaining.length > 0) continue;
    try {
      await rmdir(child);
      removed += 1;
    } catch {

    }
  }
  return removed;
}

export async function cleanMirror(root: string, config: Config): Promise<void> {
  await rm(path.join(root, config.mirror.dir), { recursive: true, force: true });
}

async function copyIfChanged(source: string, target: string): Promise<boolean> {
  const contents = await readFile(source).catch(() => null);
  if (contents === null) return false;

  const existing = await readFile(target).catch(() => null);
  if (existing && existing.equals(contents)) return false;

  await mkdir(path.dirname(target), { recursive: true });
  await writeFile(target, contents);
  return true;
}

async function listFiles(dir: string, prefix = ""): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);

  const files: string[] = [];
  for (const entry of entries) {
    const relative = prefix ? path.join(prefix, entry.name) : entry.name;
    if (entry.isDirectory()) {
      files.push(...(await listFiles(path.join(dir, entry.name), relative)));
    } else if (entry.isFile()) {
      files.push(relative);
    }
  }
  return files;
}

function requiredDirs(mirrorRoot: string, config: Config): string[] {
  const dirs: string[] = [];
  for (const bucket of Object.values(config.mirror.roots)) {
    const bucketDir = path.join(mirrorRoot, bucket);
    dirs.push(bucketDir);
    if (bucket === config.mirror.roots.client) continue;
    for (const folder of config.mirror.folders) dirs.push(path.join(bucketDir, folder));
  }
  return dirs;
}


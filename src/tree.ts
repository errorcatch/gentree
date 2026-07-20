import { readdir, readFile, writeFile } from "node:fs/promises";
import path from "node:path";

import {
  type Bucket,
  type Config,
  isInitStem,
  isQualifiedStem,
  isServerStem,
  isSourceExt,
} from "./config.js";

type Node = Record<string, unknown>;

type ScriptKind = "module" | "server" | "client";

interface ParsedName {
  stem: string;
  kind: ScriptKind;
}

export interface Placement {
  bucket: Bucket;
  folder: string[];
  name: string;
  source: string;
  isDirectory: boolean;
  fileName: string;
}

export function defaultScaffold(name: string, config: Config): Node {
  const { dir, roots } = config.mirror;

  return {
    name,
    tree: {
      $className: "DataModel",
      ReplicatedStorage: {
        Shared: { $path: `${dir}/${roots.shared}` },
        Packages: { $path: "Packages" },
        UI: { $path: "src/ui" },
      },
      ServerScriptService: { $path: `${dir}/${roots.server}` },
      StarterPlayer: {
        StarterPlayerScripts: { $path: `${dir}/${roots.client}` },
      },
    },
  };
}

export async function loadScaffold(root: string, config: Config): Promise<Node> {
  const base = path.join(root, config.base);

  const text = await readFile(base, "utf8").catch(() => null);
  if (text === null) return defaultScaffold(config.name, config);

  let parsed: Node;
  try {
    parsed = JSON.parse(text) as Node;
  } catch (error) {
    throw new Error(`${config.base} is not valid JSON: ${(error as Error).message}`);
  }

  if (typeof parsed.tree !== "object" || parsed.tree === null) {
    throw new Error(`${config.base} has no \`tree\` object`);
  }

  parsed.name = config.name;
  return parsed;
}

export async function writeProjectFile(root: string, config: Config): Promise<boolean> {
  const project = await loadScaffold(root, config);
  const rendered = `${JSON.stringify(project, null, 2)}\n`;

  const out = path.join(root, config.out);
  const existing = await readFile(out, "utf8").catch(() => null);
  if (existing === rendered) return false;

  await writeFile(out, rendered, "utf8");
  return true;
}

export async function collectFiles(
  src: string,
  dir: string,
  config: Config,
): Promise<string[]> {
  const entries = await readdir(dir, { withFileTypes: true }).catch(() => []);
  entries.sort((a, b) => a.name.localeCompare(b.name));

  const files: string[] = [];
  for (const entry of entries) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory()) {
      const relative = toPosix(path.relative(src, full));
      const excluded = config.scan.exclude.some(
        (pattern) => pattern.toLowerCase() === relative.toLowerCase(),
      );
      if (excluded) continue;
      files.push(...(await collectFiles(src, full, config)));
    } else if (entry.isFile()) {
      const ext = path.extname(entry.name).replace(/^\./, "");
      if (isSourceExt(config, ext)) files.push(path.relative(src, full));
    }
  }
  return files;
}

function parseName(file: string): ParsedName {
  const base = path.basename(file);
  const withoutExt = base.slice(0, base.length - path.extname(base).length);
  const lower = withoutExt.toLowerCase();

  if (lower.endsWith(".server")) {
    return { stem: withoutExt.slice(0, -".server".length), kind: "server" };
  }
  if (lower.endsWith(".client")) {
    return { stem: withoutExt.slice(0, -".client".length), kind: "client" };
  }
  return { stem: withoutExt, kind: "module" };
}

export function resolve(files: string[], config: Config): Placement[] {
  const claimed: string[][] = [];
  for (const file of files) {
    if (isInitStem(config, parseName(file).stem)) {
      claimed.push(folderSegments(file, config));
    }
  }

  const placements: Placement[] = [];
  for (const file of files) {
    const { stem, kind } = parseName(file);
    const segments = folderSegments(file, config);

    if (isInitStem(config, stem)) {
      const name = segments.at(-1) ?? "";
      placements.push({
        bucket: bucketFor(name, kind, config),
        folder: segments.slice(0, -1),
        name,
        source: toPosix(path.join(config.src, path.dirname(file))),
        isDirectory: true,
        fileName: name,
      });
      continue;
    }

    const suppressed = claimed.some(
      (claim) =>
        segments.length >= claim.length &&
        claim.every((part, index) => segments[index] === part),
    );
    if (suppressed) continue;

    const parent = segments.at(-1) ?? "";
    const name = isQualifiedStem(config, stem) ? `${parent}${pascal(stem)}` : stem;
    const suffix = kind === "module" ? "" : `.${kind}`;

    placements.push({
      bucket: bucketFor(stem, kind, config),
      folder: segments,
      name,
      source: toPosix(path.join(config.src, file)),
      isDirectory: false,
      fileName: `${name}${suffix}${path.extname(file)}`,
    });
  }
  return placements;
}

function bucketFor(stem: string, kind: ScriptKind, config: Config): Bucket {
  if (kind === "server") return "server";
  if (kind === "client") return "client";
  return isServerStem(config, stem) ? "server" : "shared";
}

function folderSegments(file: string, config: Config): string[] {
  const parent = path.dirname(file);
  if (parent === "." || parent === "") return [];

  return parent
    .split(/[\\/]/)
    .filter(Boolean)
    .map((part) => (config.naming.pascalCaseFolders ? pascal(part) : part));
}

export const toPosix = (value: string) => value.split(path.sep).join("/");

const pascal = (text: string) => (text ? text[0]!.toUpperCase() + text.slice(1) : "");

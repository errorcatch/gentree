import { readFile } from "node:fs/promises";
import path from "node:path";

export const CONFIG_FILE = "gentree.config.json";

export type Bucket = "shared" | "server" | "client";

export interface Config {
  name: string;
  src: string;
  out: string;
  base: string;
  mirror: {
    dir: string;
    roots: Record<Bucket, string>;
    folders: string[];
    pruneDirs: boolean;
    pruneDelayMs: number;
  };
  entryPoints: {
    server: string | null;
    client: string | null;
  };
  scan: {
    exclude: string[];
    extensions: string[];
  };
  naming: {
    qualify: string[];
    init: string[];
    pascalCaseFolders: boolean;
  };
  routing: {
    serverStems: string[];
  };
}

export function defaultConfig(name = "gentree"): Config {
  return {
    name,
    src: "src",
    out: "default.project.json",
    base: "base.project.json",
    mirror: {
      dir: ".gentree",
      roots: { shared: "shared", server: "server", client: "client" },
      folders: ["Services", "Classes", "Modules"],
      pruneDirs: true,
      pruneDelayMs: 1000,
    },
    entryPoints: {
      server: "src/startup/Server.server.luau",
      client: "src/startup/Client.client.luau",
    },
    scan: {
      exclude: ["ui", "startup"],
      extensions: ["luau", "lua"],
    },
    naming: {
      qualify: ["Server", "Client", "Utils", "Types"],
      init: ["init"],
      pascalCaseFolders: true,
    },
    routing: {
      serverStems: ["Server"],
    },
  };
}

export async function loadConfig(root: string): Promise<Config> {
  const file = path.join(root, CONFIG_FILE);

  let text: string;
  try {
    text = await readFile(file, "utf8");
  } catch {
    return defaultConfig(path.basename(path.resolve(root)));
  }

  let parsed: unknown;
  try {
    parsed = JSON.parse(text);
  } catch (error) {
    throw new Error(`${CONFIG_FILE} is not valid JSON: ${(error as Error).message}`);
  }

  return merge(defaultConfig(path.basename(path.resolve(root))), parsed);
}

function merge(base: Config, override: unknown): Config {
  if (typeof override !== "object" || override === null) return base;
  const partial = override as Partial<Config>;

  return {
    ...base,
    ...partial,
    mirror: {
      ...base.mirror,
      ...(partial.mirror ?? {}),
      roots: { ...base.mirror.roots, ...(partial.mirror?.roots ?? {}) },
    },
    entryPoints: { ...base.entryPoints, ...(partial.entryPoints ?? {}) },
    scan: { ...base.scan, ...(partial.scan ?? {}) },
    naming: { ...base.naming, ...(partial.naming ?? {}) },
    routing: { ...base.routing, ...(partial.routing ?? {}) },
  };
}

const eqCI = (list: string[], value: string) =>
  list.some((item) => item.toLowerCase() === value.toLowerCase());

export const isServerStem = (config: Config, stem: string) =>
  eqCI(config.routing.serverStems, stem);

export const isQualifiedStem = (config: Config, stem: string) =>
  eqCI(config.naming.qualify, stem);

export const isInitStem = (config: Config, stem: string) =>
  eqCI(config.naming.init, stem);

export const isSourceExt = (config: Config, ext: string) =>
  eqCI(config.scan.extensions, ext);

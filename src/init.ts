import { mkdir, readFile, writeFile } from "node:fs/promises";
import { existsSync } from "node:fs";
import path from "node:path";

import { build } from "./build.js";
import { CONFIG_FILE, defaultConfig, loadConfig } from "./config.js";
import * as report from "./report.js";
import { ROJO_MISSING, detectRojo } from "./rojo.js";
import { defaultScaffold } from "./tree.js";

function scaffoldFiles(name: string): Record<string, string> {
  const config = defaultConfig(name);

  return {
    [CONFIG_FILE]: `${JSON.stringify(config, null, 2)}\n`,
    "base.project.json": `${JSON.stringify(defaultScaffold(name, config), null, 2)}\n`,

    "src/services/ExampleService/Server.luau": [
      "local ExampleServiceServer = {}",
      "",
      "function ExampleServiceServer.init(self: ExampleServiceServer)",
      '\tprint("hi from ExampleServiceServer!")',
      "end",
      "",
      "export type ExampleServiceServer = typeof(ExampleServiceServer) & {}",
      "",
      "return ExampleServiceServer",
      "",
    ].join("\n"),

    "src/services/ExampleService/Client.luau": [
      "local ExampleServiceClient = {}",
      "",
      "return ExampleServiceClient",
      "",
    ].join("\n"),

    "src/services/ExampleService/Utils.luau": [
      "local ExampleServiceUtils = {}",
      "",
      "return ExampleServiceUtils",
      "",
    ].join("\n"),

    "src/startup/Server.server.luau": [
      'local ServerScriptService = game:GetService("ServerScriptService")',
      "",
      "local ExampleServiceServer = require(",
      "\tServerScriptService.Services.ExampleService.ExampleServiceServer",
      ")",
      "",
      "ExampleServiceServer:init()",
      "",
    ].join("\n"),

    "src/startup/Client.client.luau": "",
  };
}

const SCAFFOLD_DIRS = ["src/ui", "src/classes", "src/modules", "Packages"];

export async function init(root: string): Promise<void> {
  const rojo = await detectRojo(root);
  if (!rojo.installed) {
    throw new Error(ROJO_MISSING);
  }
  report.info(`found ${rojo.version}`);

  const name = path.basename(path.resolve(root));
  const files = scaffoldFiles(name);
  let created = 0;

  for (const [relative, contents] of Object.entries(files)) {
    const target = path.join(root, relative);
    if (existsSync(target)) {
      report.info(`${relative} ${report.dim("already exists, skipped")}`);
      continue;
    }

    await mkdir(path.dirname(target), { recursive: true });
    await writeFile(target, contents, "utf8");
    report.step(relative);
    created += 1;
  }

  for (const relative of SCAFFOLD_DIRS) {
    const target = path.join(root, relative);
    if (existsSync(target)) continue;
    await mkdir(target, { recursive: true });
    await writeFile(path.join(target, ".gitkeep"), "", "utf8");
    report.step(`${relative}/`);
  }

  const config = await loadConfig(root);
  await ignoreMirror(root, config.mirror.dir);
  report.build(await build(root, config), config);

  if (created === 0) {
    report.info("project was already initialized");
  }
  report.info(
    `next: ${report.bold("gentree watch")} in one terminal, ${report.bold("rojo serve")} in another`,
  );
}

async function ignoreMirror(root: string, dir: string): Promise<void> {
  const file = path.join(root, ".gitignore");
  const entry = `${dir}/`;

  const existing = await readFile(file, "utf8").catch(() => null);
  if (existing === null) {
    await writeFile(file, `${entry}\n`, "utf8");
    report.step(`.gitignore ${report.dim(`(${entry})`)}`);
    return;
  }

  const lines = existing.split(/\r?\n/).map((line) => line.trim());
  if (lines.includes(entry) || lines.includes(dir)) return;

  const separator = existing.endsWith("\n") ? "" : "\n";
  await writeFile(file, `${existing}${separator}${entry}\n`, "utf8");
  report.step(`.gitignore ${report.dim(`(+ ${entry})`)}`);
}

#!/usr/bin/env node
import { Command } from "commander";
import { existsSync } from "node:fs";
import path from "node:path";

import { build } from "./build.js";
import { loadConfig } from "./config.js";
import { init } from "./init.js";
import { cleanMirror, pruneMirror } from "./mirror.js";
import * as report from "./report.js";
import { watch } from "./watch.js";

const program = new Command();

program
  .name("gentree")
  .description("Generate a Rojo project tree from your source layout, live.")
  .version("0.1.0")
  .option("-C, --root <dir>", "project root to operate on", ".");

program
  .command("init")
  .description("scaffold the source layout and generate the first project file")
  .action(async () => {
    await init(rootOf());
  });

program
  .command("build")
  .description("generate the project file once")
  .action(async () => {
    const root = rootOf();
    const config = await loadConfig(root);
    requireSrc(root, config.src);
    const outcome = await build(root, config);
    report.build(outcome, config);

    if (config.mirror.pruneDirs) {
      // Same deferral as watch mode, in case a rojo server is running.
      await new Promise((done) => setTimeout(done, config.mirror.pruneDelayMs));
      const removed = await pruneMirror(root, config);
      if (removed) report.info(`pruned ${removed} empty folder${removed === 1 ? "" : "s"}`);
    }
  });

program
  .command("clean")
  .description("delete the generated mirror directory")
  .action(async () => {
    const root = rootOf();
    const config = await loadConfig(root);
    await cleanMirror(root, config);
    report.info(`removed ${config.mirror.dir}`);
  });

program
  .command("watch")
  .description("generate the project file and regenerate it as sources change")
  .action(async () => {
    const root = rootOf();
    const config = await loadConfig(root);
    requireSrc(root, config.src);
    await watch(root, config);
  });

function rootOf(): string {
  return path.resolve(program.opts<{ root: string }>().root);
}

function requireSrc(root: string, src: string): void {
  if (existsSync(path.join(root, src))) return;
  throw new Error(
    `no \`${src}\` directory in ${root}\n\nRun \`gentree init\` to scaffold one.`,
  );
}

async function main() {
  try {
    await program.parseAsync(process.argv);
  } catch (error) {
    report.error((error as Error).message);
    process.exitCode = 1;
  }
}

void main();

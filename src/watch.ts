import chokidar from "chokidar";
import path from "node:path";

import { build } from "./build.js";
import { CONFIG_FILE, type Config, loadConfig } from "./config.js";
import { pruneMirror } from "./mirror.js";
import * as report from "./report.js";

const DEBOUNCE_MS = 150;

export async function watch(root: string, initial: Config): Promise<void> {
  let config = initial;

  const src = path.join(root, config.src);
  const mirror = path.resolve(root, config.mirror.dir);
  const watcher = chokidar.watch(
    [src, path.join(root, CONFIG_FILE), path.join(root, config.base)],
    {
      ignoreInitial: true,
      ignored: (candidate) => {
        const resolved = path.resolve(candidate);
        return resolved === path.resolve(root, config.out) || resolved.startsWith(mirror);
      },
    },
  );

  let timer: NodeJS.Timeout | undefined;
  let pruneTimer: NodeJS.Timeout | undefined;
  let pendingConfigReload = false;
  let building = false;
  let queued = false;

  // Deferred so Rojo has processed the file removals first: deleting a
  // directory alongside its files crashes Rojo 7.7.0.
  const schedulePrune = () => {
    if (!config.mirror.pruneDirs) return;
    clearTimeout(pruneTimer);
    pruneTimer = setTimeout(() => {
      void pruneMirror(root, config)
        .then((removed) => {
          if (removed) report.info(`${report.dim(report.clock())} pruned ${removed} empty folder${removed === 1 ? "" : "s"}`);
        })
        .catch((error: unknown) => report.error((error as Error).message));
    }, config.mirror.pruneDelayMs);
  };

  const rebuild = async () => {
    if (building) {
      queued = true;
      return;
    }
    building = true;

    try {
      if (pendingConfigReload) {
        pendingConfigReload = false;
        config = await loadConfig(root);
        report.info(`reloaded ${CONFIG_FILE}`);
      }
      const outcome = await build(root, config);
      report.build(outcome, config, report.clock());
      if (outcome.mirror.removed) schedulePrune();
    } catch (error) {
      report.error((error as Error).message);
    } finally {
      building = false;
      if (queued) {
        queued = false;
        void rebuild();
      }
    }
  };

  const schedule = (changed: string) => {
    if (path.basename(changed) === CONFIG_FILE) pendingConfigReload = true;
    clearTimeout(timer);
    timer = setTimeout(() => void rebuild(), DEBOUNCE_MS);
  };

  watcher.on("all", (_event, changed) => schedule(changed));
  watcher.on("error", (error) => report.error(`watch error: ${(error as Error).message}`));

  report.info(`watching ${report.bold(config.src)} ${report.dim("(ctrl-c to stop)")}`);
  await rebuild();

  await new Promise<void>((resolve) => {
    const stop = () => {
      void watcher.close().then(resolve);
    };
    process.once("SIGINT", stop);
    process.once("SIGTERM", stop);
  });
}

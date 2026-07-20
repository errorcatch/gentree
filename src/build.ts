import path from "node:path";

import type { Config } from "./config.js";
import { type MirrorOutcome, syncMirror } from "./mirror.js";
import { collectFiles, resolve, writeProjectFile } from "./tree.js";

export interface BuildOutcome {
  moduleCount: number;
  mirror: MirrorOutcome;
  projectChanged: boolean;
  warnings: string[];
}

export async function build(root: string, config: Config): Promise<BuildOutcome> {
  const src = path.join(root, config.src);
  const files = await collectFiles(src, src, config);
  const placements = resolve(files, config);

  const mirror = await syncMirror(root, config, placements);
  const projectChanged = await writeProjectFile(root, config);

  return {
    moduleCount: placements.length,
    mirror,
    projectChanged,
    warnings: mirror.warnings,
  };
}

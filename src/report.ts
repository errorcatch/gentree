import pc from "picocolors";

import type { BuildOutcome } from "./build.js";
import type { Config } from "./config.js";

const tag = pc.dim("gentree");

export const info = (message: string) => console.log(`${tag} ${message}`);

export const step = (message: string) => console.log(`${tag} ${pc.green("+")} ${message}`);

export const warn = (message: string) =>
  console.warn(`${tag} ${pc.yellow("warning")} ${message}`);

export const error = (message: string) =>
  console.error(`${tag} ${pc.red("error")} ${message}`);

export function build(outcome: BuildOutcome, config: Config, time?: string) {
  for (const warning of outcome.warnings) warn(warning);

  const stamp = time ? `${pc.dim(time)} ` : "";
  const modules = `${outcome.moduleCount} ${outcome.moduleCount === 1 ? "module" : "modules"}`;
  const { written, removed } = outcome.mirror;

  const changes: string[] = [];
  if (written) changes.push(`${written} updated`);
  if (removed) changes.push(`${removed} removed`);
  if (outcome.projectChanged) changes.push(config.out);

  if (changes.length === 0) {
    info(`${stamp}${modules}${pc.dim(", no change")}`);
    return;
  }
  info(`${stamp}${modules} ${pc.dim("->")} ${pc.cyan(config.mirror.dir)} ${pc.dim(`(${changes.join(", ")})`)}`);
}

export const dim = (text: string) => pc.dim(text);

export const bold = (text: string) => pc.bold(text);

export const clock = () =>
  new Date().toLocaleTimeString(undefined, { hour12: false });

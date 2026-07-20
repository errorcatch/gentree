import { execFile } from "node:child_process";
import { promisify } from "node:util";

const run = promisify(execFile);

export interface RojoStatus {
  installed: boolean;
  version?: string;
}

export async function detectRojo(root: string): Promise<RojoStatus> {
  try {
    const { stdout } = await run("rojo", ["--version"], {
      cwd: root,
      shell: process.platform === "win32",
      timeout: 10_000,
    });
    return { installed: true, version: stdout.trim() };
  } catch {
    return { installed: false };
  }
}

const DIR_REMOVAL_CRASH = ["7.7.0"];

export function versionOf(status: RojoStatus): string | null {
  const match = status.version?.match(/(\d+\.\d+\.\d+)/);
  return match?.[1] ?? null;
}

export function crashesOnDirectoryRemoval(version: string | null): boolean {
  return version !== null && DIR_REMOVAL_CRASH.includes(version);
}

export const DIR_REMOVAL_WARNING = (version: string) =>
  [
    `Rojo ${version} crashes when a watched directory is removed`,
    "(rojo-rbx/rojo change_processor.rs). gentree will leave empty folders",
    "behind instead of deleting them, so your server survives.",
    "Pin Rojo 7.6.1 to get full deletion support:",
    "  rokit add rojo-rbx/rojo@7.6.1",
  ].join(" ");

export const ROJO_MISSING = [
  "Rojo was not found on PATH.",
  "",
  "  Install it with Rokit (recommended, version-pinned per project):",
  "    rokit init      # if the project has no rokit.toml yet",
  "    rokit add rojo",
  "",
  "  Or install it globally:",
  "    cargo install rojo",
  "",
  "Then run `gentree init` again.",
].join("\n");

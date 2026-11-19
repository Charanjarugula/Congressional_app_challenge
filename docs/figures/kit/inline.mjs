import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

// The kit's source with its `export` keywords stripped, so a built page can call the same functions
// (translateAlong, lineOnTop, …) while it animates without loading a module.
const KIT = dirname(fileURLToPath(import.meta.url));
export const kitScript = () => readFileSync(join(KIT, "iso-kit.mjs"), "utf8").replace(/^export /gm, "");

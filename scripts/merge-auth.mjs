import fs from "node:fs";
import path from "node:path";

const authPath = process.argv[2];
const apiKey = process.env.CUMOB_INSTALL_API_KEY;

if (!authPath) {
  console.error("merge-auth.mjs requires an auth.json path.");
  process.exit(2);
}

if (!apiKey) {
  process.exit(0);
}

let auth = {};
if (fs.existsSync(authPath)) {
  const parsed = JSON.parse(fs.readFileSync(authPath, "utf8"));
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error(`${authPath} must contain a JSON object.`);
  }
  auth = parsed;
}

auth.OPENAI_API_KEY = apiKey;
fs.mkdirSync(path.dirname(authPath), { recursive: true });

const tempPath = `${authPath}.cumob-installer-${process.pid}.tmp`;
fs.writeFileSync(tempPath, `${JSON.stringify(auth, null, 2)}\n`, { mode: 0o600 });
fs.renameSync(tempPath, authPath);
fs.chmodSync(authPath, 0o600);

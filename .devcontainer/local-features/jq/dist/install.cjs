"use strict";

// src/jq/install.ts
var import_node_crypto = require("node:crypto");
var import_node_child_process = require("node:child_process");
var import_node_fs = require("node:fs");
var import_node_os = require("node:os");
var import_node_path = require("node:path");
var VERSION = "1.8.2";
var DESTINATION = "/usr/local/bin/jq";
function selectArtifact(architecture) {
  const artifacts = {
    arm64: {
      name: "jq-linux-arm64",
      sha256: "8b85c817833814ddca00a144c33705546355afccf0cf39b188f3cdb48b852309"
    },
    x64: {
      name: "jq-linux-amd64",
      sha256: "b1c22172dd303f3be49e935aa56aa48a8b7a46e0bc838b4997d3bb451495870f"
    }
  };
  const artifact = Object.hasOwn(artifacts, architecture) ? artifacts[architecture] : void 0;
  if (!artifact) throw new Error(`unsupported architecture ${architecture}; select arm64 or x64`);
  return {
    ...artifact,
    url: `https://github.com/jqlang/jq/releases/download/jq-${VERSION}/${artifact.name}`
  };
}
function verifyDigest(bytes, expected) {
  const actual = (0, import_node_crypto.createHash)("sha256").update(bytes).digest("hex");
  if (actual !== expected) throw new Error(`artifact SHA-256 mismatch: expected ${expected}, received ${actual}`);
}
async function install() {
  const artifact = selectArtifact(process.arch);
  const response = await fetch(artifact.url, { signal: AbortSignal.timeout(12e4) });
  if (!response.ok) throw new Error(`download ${artifact.url}: HTTP ${response.status}`);
  const bytes = new Uint8Array(await response.arrayBuffer());
  verifyDigest(bytes, artifact.sha256);
  const scratch = (0, import_node_fs.mkdtempSync)((0, import_node_path.join)((0, import_node_os.tmpdir)(), "jq-install-"));
  try {
    const candidate = (0, import_node_path.join)(scratch, "jq");
    (0, import_node_fs.writeFileSync)(candidate, bytes);
    (0, import_node_fs.chmodSync)(candidate, 493);
    const version = (0, import_node_child_process.execFileSync)(candidate, ["--version"], { encoding: "utf8" }).trim();
    if (version !== `jq-${VERSION}`) throw new Error(`artifact reports unexpected version ${version}`);
    (0, import_node_fs.mkdirSync)("/usr/local/bin", { recursive: true });
    const staged = (0, import_node_fs.mkdtempSync)("/usr/local/bin/.jq-install-");
    try {
      const stagedBinary = (0, import_node_path.join)(staged, "jq");
      (0, import_node_fs.writeFileSync)(stagedBinary, bytes, { mode: 493 });
      (0, import_node_fs.renameSync)(stagedBinary, DESTINATION);
    } finally {
      (0, import_node_fs.rmSync)(staged, { recursive: true, force: true });
    }
    const effective = (0, import_node_child_process.execFileSync)("/bin/sh", ["-c", "command -v jq"], { encoding: "utf8" }).trim();
    if (effective !== DESTINATION) throw new Error(`PATH resolves jq to ${effective}, expected ${DESTINATION}`);
    console.log(`jq installed: artifact=${artifact.name} sha256=${artifact.sha256} version=${version} path=${effective}`);
  } finally {
    (0, import_node_fs.rmSync)(scratch, { recursive: true, force: true });
  }
}

// src/jq/cli.ts
install().catch((error) => {
  console.error(error instanceof Error ? error.stack : String(error));
  console.error("jq: the corrected publication input could not be installed.");
  console.error("The image build cannot establish Unicode-preserving jq selection.");
  console.error("Remedy: resolve the reported download, digest, architecture or PATH failure and rebuild this image.");
  process.exitCode = 1;
});

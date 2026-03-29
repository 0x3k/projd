import { describe, it, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import { execFile } from "node:child_process";
import { mkdtempSync, existsSync, readFileSync, statSync, rmSync } from "node:fs";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { dirname } from "node:path";

const __dirname = dirname(fileURLToPath(import.meta.url));
const CLI = join(__dirname, "projd.js");

// Run the CLI with a fake HOME so we never touch real user files.
function run(args, home) {
  return new Promise((resolve) => {
    execFile("node", [CLI, ...args], {
      env: { ...process.env, HOME: home },
      timeout: 10_000,
    }, (error, stdout, stderr) => {
      resolve({
        code: error ? error.code ?? 1 : 0,
        stdout,
        stderr,
      });
    });
  });
}

describe("projd CLI", () => {
  let tmpHome;

  beforeEach(() => {
    tmpHome = mkdtempSync(join(tmpdir(), "projd-test-"));
  });

  afterEach(() => {
    rmSync(tmpHome, { recursive: true, force: true });
  });

  // -- help ------------------------------------------------------------------

  describe("--help", () => {
    it("prints usage and exits 0", async () => {
      const { code, stdout } = await run(["--help"], tmpHome);
      assert.equal(code, 0);
      assert.ok(stdout.includes("Usage:"), "should contain usage info");
      assert.ok(stdout.includes("projd-create"), "should list projd-create skill");
      assert.ok(stdout.includes("projd-adopt"), "should list projd-adopt skill");
    });

    it("works with -h shorthand", async () => {
      const { code, stdout } = await run(["-h"], tmpHome);
      assert.equal(code, 0);
      assert.ok(stdout.includes("Usage:"));
    });
  });

  // -- unknown flag ----------------------------------------------------------

  describe("unknown flag", () => {
    it("exits 1 and prints error", async () => {
      const { code, stderr } = await run(["--bogus"], tmpHome);
      assert.equal(code, 1);
      assert.ok(stderr.includes("Unknown flag"), "should mention unknown flag");
    });
  });

  // -- install (default, no args) --------------------------------------------

  describe("install mode (no args)", () => {
    it("creates skill directories and SKILL.md files", async () => {
      const { code, stdout } = await run([], tmpHome);
      assert.equal(code, 0);

      for (const skill of ["projd-create", "projd-adopt"]) {
        const md = join(tmpHome, ".claude", "skills", skill, "SKILL.md");
        assert.ok(existsSync(md), `${skill}/SKILL.md should exist`);
        assert.ok(stdout.includes(`Installed /${skill}`), `stdout should confirm ${skill} install`);
      }
    });

    it("creates .projd-updater.sh with executable permissions", async () => {
      await run([], tmpHome);
      const updater = join(tmpHome, ".claude", "skills", ".projd-updater.sh");
      assert.ok(existsSync(updater), "updater script should exist");

      const mode = statSync(updater).mode;
      // Owner execute bit (0o100) should be set
      assert.ok((mode & 0o100) !== 0, "updater should be executable by owner");
    });

    it("replaces BOILERPLATE_REMOTE_URL placeholder in installed SKILL.md", async () => {
      await run([], tmpHome);

      for (const skill of ["projd-create", "projd-adopt"]) {
        const md = join(tmpHome, ".claude", "skills", skill, "SKILL.md");
        const content = readFileSync(md, "utf8");
        assert.ok(
          !content.includes("{{BOILERPLATE_REMOTE_URL}}"),
          `${skill}/SKILL.md should not contain raw BOILERPLATE_REMOTE_URL placeholder`,
        );
      }
    });

    it("replaces BOILERPLATE_LOCAL_PATH placeholder in installed SKILL.md", async () => {
      await run([], tmpHome);

      for (const skill of ["projd-create", "projd-adopt"]) {
        const md = join(tmpHome, ".claude", "skills", skill, "SKILL.md");
        const content = readFileSync(md, "utf8");
        assert.ok(
          !content.includes("{{BOILERPLATE_LOCAL_PATH}}"),
          `${skill}/SKILL.md should not contain raw BOILERPLATE_LOCAL_PATH placeholder`,
        );
      }
    });

    it("is idempotent -- second run says already up to date", async () => {
      await run([], tmpHome);
      const { code, stdout } = await run([], tmpHome);
      assert.equal(code, 0);

      for (const skill of ["projd-create", "projd-adopt"]) {
        assert.ok(
          stdout.includes("Already up to date"),
          `second install should report up to date for ${skill}`,
        );
      }
    });
  });

  // -- check mode ------------------------------------------------------------

  describe("--check mode", () => {
    it("reports not installed on a clean home", async () => {
      const { code, stdout } = await run(["--check"], tmpHome);
      assert.equal(code, 0);
      assert.ok(stdout.includes("Not installed"), "should report not installed");
    });

    it("reports up to date after install", async () => {
      await run([], tmpHome);
      const { code, stdout } = await run(["--check"], tmpHome);
      assert.equal(code, 0);
      assert.ok(stdout.includes("Already up to date"), "should report up to date");
    });
  });

  // -- remove mode -----------------------------------------------------------

  describe("--remove mode", () => {
    it("removes installed skills and updater", async () => {
      await run([], tmpHome);

      // Verify they exist first
      for (const skill of ["projd-create", "projd-adopt"]) {
        const md = join(tmpHome, ".claude", "skills", skill, "SKILL.md");
        assert.ok(existsSync(md), `${skill} should exist before removal`);
      }
      const updater = join(tmpHome, ".claude", "skills", ".projd-updater.sh");
      assert.ok(existsSync(updater), "updater should exist before removal");

      // Remove
      const { code, stdout } = await run(["--remove"], tmpHome);
      assert.equal(code, 0);

      for (const skill of ["projd-create", "projd-adopt"]) {
        const md = join(tmpHome, ".claude", "skills", skill, "SKILL.md");
        assert.ok(!existsSync(md), `${skill}/SKILL.md should be removed`);
        assert.ok(stdout.includes(`Removed /${skill}`), `stdout should confirm ${skill} removal`);
      }

      assert.ok(!existsSync(updater), "updater should be removed");
      assert.ok(stdout.includes("Removed"), "stdout should confirm updater removal");
    });

    it("reports not installed on a clean home", async () => {
      const { code, stdout } = await run(["--remove"], tmpHome);
      assert.equal(code, 0);
      assert.ok(
        stdout.includes("Not installed"),
        "should report not installed when nothing to remove",
      );
    });
  });
});

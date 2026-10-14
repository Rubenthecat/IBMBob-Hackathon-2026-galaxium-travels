# Plan: Fix `setup.sh` for Ubuntu/Debian Compatibility

## Top-Level Overview

`setup.sh` has three blocking issues that prevent it from running on Ubuntu/Debian after a fresh clone:
a UTF-8 BOM byte that corrupts the shebang, a Java apt package that is unavailable on Ubuntu 22.04 LTS,
and a Maven apt package that is too old to build the Spring Boot 3.x Hold Service.
This plan fixes all three in `setup.sh` only — no other scripts need to change.

---

## Sub-Task 1 — Remove the UTF-8 BOM from the shebang line

**Status:** `[x] done`

**Intent**
The first byte(s) of `setup.sh` are a UTF-8 BOM (`\xEF\xBB\xBF`) prepended before `#!/usr/bin/env bash`.
On Linux, the kernel reads the shebang literally, so the BOM corrupts the interpreter path and
the script fails with "bad interpreter: No such file or directory" before a single line of logic runs.

**Expected Outcomes**
- `setup.sh` opens with exactly `#!/usr/bin/env bash` on line 1, no BOM prefix.
- Running `bash setup.sh` on Ubuntu does not produce a bad-interpreter error.

**Todo List**
1. Re-save `setup.sh` as UTF-8 without BOM (strip the `\xEF\xBB\xBF` prefix from byte 1).
2. Confirm `file setup.sh` reports `ASCII text` or `UTF-8 Unicode text` (not `UTF-8 Unicode (with BOM) text`).

**Relevant Context**
- `setup.sh` line 1 — BOM character confirmed present in subagent exploration.
- This is the most critical fix; without it the script cannot execute on Linux at all.

---

## Sub-Task 2 — Fix Java 21 installation for Ubuntu 22.04 LTS

**Status:** `[x] done`

**Intent**
`require_tool java openjdk@21 openjdk-21-jdk "Java 21"` uses the apt package `openjdk-21-jdk`,
which is only available in Ubuntu 23.10+ and Debian 13. On Ubuntu 22.04 LTS (the dominant LTS release)
this package does not exist in the default repositories, causing apt-get to error out.

The pom.xml for the Java Hold Service declares `maven.compiler.source=17` and targets Spring Boot 3.4.1,
so Java 17 is perfectly valid. The CI workflow (`setup-test.yml` lines 127–136) also handles this by
checking the currently active Java version and only installing `openjdk-21-jdk` if Java is not already 17 or 21.

The fix is to attempt Java 21 first, fall back to Java 17 if 21 is unavailable, and — since the Hold
Service is a required component — print a clear error message with manual install instructions if
neither package can be installed, without exiting (so the user is informed and can act, but the rest
of setup still completes).

**Expected Outcomes**
- On Ubuntu 22.04 LTS: script installs `openjdk-17-jdk` (available by default) without error.
- On Ubuntu 23.10+ / Debian 13: script installs `openjdk-21-jdk` as before.
- If Java 17 or 21 is already on PATH (common in CI / developer machines): no apt install is attempted.
- If neither package can be installed: script prints a prominent warning with manual install instructions
  and continues (does not exit), so the rest of setup completes.

**Todo List**
1. Replace the single `require_tool java openjdk@21 openjdk-21-jdk "Java 21"` call in `setup.sh`
   with an inline Java detection block that:
   a. Checks if `java` is already on PATH and its major version is 17 or 21 — if so, print ✅ and continue.
   b. Otherwise attempts `apt-get install -y openjdk-21-jdk`; if that fails (non-zero exit), falls back to
      `apt-get install -y openjdk-17-jdk`.
   c. If both fail, print a clear warning (not a hard exit) with manual install instructions:
      `sudo apt-get install -y openjdk-17-jdk` or via SDKMAN.
2. Keep the macOS `brew install openjdk@21` + PATH export logic that follows — it is unaffected.

**Relevant Context**
- `setup.sh` lines 191–203 — current Java install block.
- `booking_system_inventory_hold_service/pom.xml` lines 25–26 — `<maven.compiler.source>17</maven.compiler.source>`.
- `.github/workflows/setup-test.yml` lines 127–136 — CI workaround that confirms the same strategy.

---

## Sub-Task 3 — Fix Maven installation to use a version compatible with Spring Boot 3.x

**Status:** `[x] done`

**Intent**
`require_tool mvn maven maven "Maven"` installs apt's bundled Maven, which on Ubuntu 22.04 LTS is
version 3.6.3. Spring Boot 3.x requires Maven 3.8.6+. The `mvn spring-boot:run` call in
`start_locally.sh` line 124 will fail at build time with a plugin compatibility error when Maven 3.6.x
is used.

The most efficient fix on Ubuntu/Debian is to use the official upstream binary tarball from
`downloads.apache.org` — one `curl` download, one `tar` extract, one symlink. No PPA to add, no
sdkman session to initialise, no extra dependencies. The macOS path (`brew install maven`) already
installs a current version and is unaffected.

The pinned version will be **3.9.9** (latest stable at time of writing). The download URL is:
`https://downloads.apache.org/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz`

**Expected Outcomes**
- `mvn --version` reports 3.9.9 on Ubuntu/Debian after setup.
- `mvn spring-boot:run` in the Hold Service directory completes without version-related plugin errors.

**Todo List**
1. Replace the `require_tool mvn maven maven "Maven"` call in `setup.sh` with a dedicated
   `install_maven_linux()` helper function (Linux-only) that:
   a. Skips if `mvn` is already on PATH and reports version 3.8.x or higher.
   b. Downloads `apache-maven-3.9.9-bin.tar.gz` to `/tmp/` via `curl`.
   c. Extracts to `/opt/maven/`.
   d. Creates a symlink: `sudo ln -sf /opt/maven/apache-maven-3.9.9/bin/mvn /usr/local/bin/mvn`.
   e. Verifies `mvn --version` succeeds after install.
2. Keep the macOS `require_tool mvn maven maven "Maven"` call unchanged — Homebrew's `maven`
   formula always installs a current version.

**Relevant Context**
- `setup.sh` line 205 — current Maven `require_tool` call.
- `scripts/local/start_locally.sh` line 124 — `mvn -q spring-boot:run` that requires Maven 3.8.6+.
- `.github/workflows/setup-test.yml` line 125 — CI installs apt `maven` but `ubuntu-latest` ships
  with a newer runner image that already has Maven 3.9.x available system-wide, masking this issue in CI.

---

## Non-Goals

- Do not modify `start_locally.sh`, `start.sh`, or any other script — all three issues are isolated to `setup.sh`.
- Do not add a Maven version check to `start_locally.sh` — fix the source of the problem in setup.
- Do not change the macOS (Homebrew) paths — they are unaffected.
- Do not address the cosmetic `apt-get update` per-tool call (minor inefficiency, not a failure).

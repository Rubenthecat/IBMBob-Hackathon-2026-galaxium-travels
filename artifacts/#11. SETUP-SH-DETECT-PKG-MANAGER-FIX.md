# Fix: `_detect_pkg_manager: command not found` in setup.sh

## Overview

`setup.sh` crashes on Linux at line 264 with `_detect_pkg_manager: command not found` when
the Docker Compose V2 plugin is missing. The function `_detect_pkg_manager` is called inside
`_ensure_docker_repo` but was never defined. The variables it would have set — `PKG_MANAGER`
and `DISTRO_ID` — are already populated as globals by the top-level detection block at lines
50–64, so the call is entirely redundant.

**Scope:** one-line fix, no logic changes.

---

## Sub-Task 1 — Remove the phantom `_detect_pkg_manager` call

**Status:** `[ ] pending`

**Intent**
Remove the stale call to the non-existent `_detect_pkg_manager` function from inside
`_ensure_docker_repo`. No substitute code is needed because `PKG_MANAGER` and `DISTRO_ID`
are already set unconditionally on Linux by the global block before any function is invoked.

**Expected Outcomes**
- `setup.sh` no longer errors with `_detect_pkg_manager: command not found` on Linux.
- `_ensure_docker_repo` reads the already-populated `PKG_MANAGER` global and proceeds to
  add the correct Docker repo for the distro.
- All existing `case "$PKG_MANAGER"` and `case "$DISTRO_ID"` branches inside
  `_ensure_docker_repo` continue to work unchanged.

**Todo List**
1. In `setup.sh`, inside `_ensure_docker_repo`, delete line 264 (`_detect_pkg_manager`)
   and the blank line immediately after it (line 265).
2. Verify no other call sites for `_detect_pkg_manager` exist in the file.
3. Confirm `PKG_MANAGER` and `DISTRO_ID` are set before `_ensure_docker_repo` is ever
   called (they are — the global block runs at script start, well before the Docker-mode
   section that calls `_ensure_docker_repo` at line 382).

**Relevant Context**
- `setup.sh` lines 50–64 — global `PKG_MANAGER` / `DISTRO_ID` detection block.
- `setup.sh` line 263 — `_ensure_docker_repo()` definition.
- `setup.sh` line 264 — the phantom call to delete.
- `setup.sh` line 382 — where `_ensure_docker_repo` is called.

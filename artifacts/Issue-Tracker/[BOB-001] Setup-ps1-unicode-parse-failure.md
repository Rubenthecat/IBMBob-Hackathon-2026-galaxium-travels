# BUG-001: setup.ps1 Unicode Parse Failure on Windows PowerShell 5.x

| Field         | Detail                          |
|---------------|---------------------------------|
| **File**      | `setup.ps1`                     |
| **Affected**  | Windows, PowerShell 5.x         |
| **Status**    | Resolved                        |

---

## Issue

Running `.\setup.ps1` on Windows PowerShell 5.x produced parse errors and garbled terminal output, preventing the script from executing.

The script contained two categories of problematic Unicode characters:

1. **Em dashes** (`—`, U+2014) inside `Write-Host` strings — caused **hard parse errors**, aborting execution entirely.
2. **Emoji and box-drawing characters** (`🌌 ━ ═ ✅ ⚠️ ❌`) — caused garbled terminal output (`â€"` etc.) even after the parse errors were resolved.

**Error output:**
```
Unexpected token ')' in expression or statement.
At setup.ps1:22 char:85
+ ... Docker  (recommended â€" no local dependencies needed beyond Docker)"
+                                                                         ~
Missing closing ')' in expression.
CategoryInfo : ParserError: (:) [], ParseException
```

**Root cause:** PowerShell 5.x reads UTF-8 files without a BOM using Windows-1252 encoding by default. The multi-byte UTF-8 sequence for the em dash (`0xE2 0x80 0x94`) is misread as three separate characters, one of which is a `)` lookalike that breaks the string parser.

---

## Recommended Solutions

| Option | Approach | Pros | Cons |
|--------|----------|------|------|
| A | Save file as **UTF-8 with BOM** | No code changes needed | Does not repair already-corrupted characters at runtime; BOM can cause issues in some toolchains |
| B | Run with **PowerShell 7+** (`pwsh`) | Handles UTF-8 natively; no file changes | Requires PS7 to be installed separately |
| **C ✓** | **Replace all non-ASCII characters with plain ASCII equivalents** | Works on all PowerShell versions; no encoding assumptions | Minor cosmetic change to output text |

---

## Attempts to Fix

### Attempt 1 — Save file as UTF-8 with BOM (via VS Code)

Opened `setup.ps1` in VS Code and re-saved with "UTF-8 with BOM" encoding using the bottom status bar encoding picker.

**Result: Failed — same errors persisted.**

Saving with a BOM does not re-encode characters already stored in the file. The em dashes were already present as valid UTF-8 bytes on disk; the issue was PowerShell 5's parser misinterpreting them at read time, which the BOM alone could not resolve.

### Attempt 2 — Replace em dashes with plain hyphens

Used search-and-replace to swap all 5 occurrences of `—` for a plain ASCII `-`. This resolved the hard parse errors and allowed the script to run.

**Result: Partial fix — script ran, but terminal output was still garbled.**

Remaining emoji and box-drawing characters rendered as multi-character garbage sequences in the Windows console.

---

## Actual Fix

Replaced all non-ASCII Unicode characters throughout `setup.ps1` with plain ASCII equivalents. No encoding settings were changed.

| Original Character | Replaced With | Occurrences |
|--------------------|---------------|-------------|
| `—` Em dash (U+2014) | `-` | 5 |
| `━━━` / `═══` Box-drawing lines | `=======` | 6 |
| `✅` `⚠️` `❌` Status emoji | `[OK]` `[!!]` `[ERR]` | 3 |
| `🌌` `🐳` `💻` `📡` `🎨` `🌟` Decorative emoji | Removed (text labels retained) | 6 |

After this change, `.\setup.ps1` parses and runs cleanly on Windows PowerShell 5.x with no encoding configuration required.

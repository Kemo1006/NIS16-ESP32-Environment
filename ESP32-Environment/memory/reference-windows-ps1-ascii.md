---
name: reference-windows-ps1-ascii
description: Gotcha — write all .ps1/.bat for this repo in pure ASCII (Windows PowerShell 5.1 mojibake)
metadata:
  type: reference
---

**This project runs Windows PowerShell 5.1**, which reads `.ps1` as the ANSI codepage unless the file has a BOM. The Write tool emits UTF-8 **without** a BOM, so any non-ASCII char (em-dash `-`/`—`, smart quotes, arrows `→`, bullets) becomes mojibake (`—` -> `â€"`), which breaks string quoting and cascades into "Missing closing '}'" parse errors.

**Rule: write every `.ps1` / `.bat` / `.cmd` in this repo in pure ASCII.** Use `-` not em-dash, `->` not arrow, straight quotes only. Verify after writing:
```
$errs=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($f,[ref]$null,[ref]$errs); $errs
([System.IO.File]::ReadAllBytes($f) | ? {$_ -gt 127}).Count   # must be 0
```
Also avoid reusing the automatic variable `$args` as a normal variable (use `$exArgs` etc.). Hit while building `menu.ps1` 2026-09-14 — see [[panel-change-2026-09]] tooling.

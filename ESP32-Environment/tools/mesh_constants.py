"""
Read numeric #defines from the firmware's mesh_config.h, so host tools never
keep their own copy of the run schedule.

Before oct. 1, 2026 PHASE_BASELINE_S / PHASE_ATTACK_S / PHASE_COOLDOWN_S /
PHASE_STABILISE_S / BURST_COUNT were typed by hand into preprocess.py,
validate_integrity.py, verify_topology.py and verify_burst.py. Change one in
mesh_config.h and the tools silently kept the old value. (tools/audit_dataset.py
already read them from the header; this is the same idea, shared.)

`default` is used only when the header is missing or the name isn't in it
(e.g. a tools-only checkout), and a warning says so - it is never silent.
"""
from __future__ import annotations

import os
import re
import sys

MESH_CONFIG_H = os.path.normpath(os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..",
    "components", "mesh_common", "include", "mesh_config.h"))

_cache: str | None = None


def _header() -> str:
    global _cache
    if _cache is None:
        try:
            with open(MESH_CONFIG_H, encoding="utf-8") as f:
                _cache = f.read()
        except OSError:
            _cache = ""
    return _cache


def mesh_config_int(name: str, default: int) -> int:
    """Value of `#define NAME <int>[U]` in mesh_config.h, else `default`.

    The first #define wins: mesh_config.h guards these with #ifndef, so the
    first one IS the built-in default (a -DNAME=... build flag can't be seen
    from here - validate_integrity.py's --phase-durations covers that case).
    """
    m = re.search(rf"^\s*#define\s+{re.escape(name)}\s+(\d+)[uU]?\b",
                  _header(), re.MULTILINE)
    if m:
        return int(m.group(1))
    print(f"WARNING: {name} not found in {MESH_CONFIG_H} - using {default}",
          file=sys.stderr)
    return default

"""
Minimal console progress bar with elapsed time + ETA, for the slow per-window
loops in preprocess.py (build_windows) and features.py (topology / RSSI).

Writes to STDOUT, never stderr: Windows PowerShell 5.1 promotes a native
command's first stderr line to a terminating error under
$ErrorActionPreference='Stop' (menu.ps1 and run_wizard.ps1 both set it), so a
bar on stderr would kill the caller with an empty exception message.

Only draws when stdout is a real console. When output is captured or piped
(Tee-Object, `> log.txt`, a test harness) it prints nothing, so logs never
fill with carriage-return redraws. No dependency (tqdm is not in
requirements.txt).
"""

from __future__ import annotations

import sys
import time

_BAR_WIDTH = 30
_REDRAW_S = 0.25


def _fmt(seconds: float) -> str:
    seconds = int(round(seconds))
    m, s = divmod(seconds, 60)
    h, m = divmod(m, 60)
    return f"{h}:{m:02d}:{s:02d}" if h else f"{m}:{s:02d}"


class Progress:
    """Usage:  bar = Progress("Windowing", total); bar.update() per item; bar.close().

    inline=False is for a few long stages (eda.py) instead of many short items:
    every update() prints its own full line, naming the stage that just
    finished, so a warning printed mid-stage can't land inside the bar.
    """

    def __init__(self, label: str, total: int, inline: bool = True):
        self.label = label
        self.total = max(int(total), 0)
        self.inline = inline
        self.note = ""
        self.done = 0
        self.start = time.monotonic()
        self._last_draw = 0.0
        try:
            self.enabled = self.total > 0 and sys.stdout.isatty()
        except (AttributeError, ValueError):
            self.enabled = False
        if inline:
            self._draw()

    def update(self, n: int = 1, note: str = "") -> None:
        self.done += n
        self.note = note
        now = time.monotonic()
        if (not self.inline or now - self._last_draw >= _REDRAW_S
                or self.done >= self.total):
            self._last_draw = now
            self._draw()

    def _draw(self, final: bool = False) -> None:
        if not self.enabled:
            return
        frac = min(self.done / self.total, 1.0)
        filled = int(frac * _BAR_WIDTH)
        elapsed = time.monotonic() - self.start
        if final or self.done >= self.total:
            tail = f"done in {_fmt(elapsed)}"
        elif self.done == 0:
            tail = "ETA --:--"
        else:
            tail = f"ETA {_fmt(elapsed / self.done * (self.total - self.done))}"
        line = (f"  {self.label} [{'#' * filled}{'-' * (_BAR_WIDTH - filled)}] "
                f"{frac * 100:3.0f}%  {self.done}/{self.total}  "
                f"elapsed {_fmt(elapsed)}  {tail}")
        if self.note:
            line += f"  ({self.note})"
        if self.inline:
            sys.stdout.write("\r" + line.ljust(100))
        else:
            sys.stdout.write(line + "\n")
        sys.stdout.flush()

    def close(self) -> None:
        if not self.enabled or not self.inline:
            return
        self._draw(final=True)
        sys.stdout.write("\n")
        sys.stdout.flush()

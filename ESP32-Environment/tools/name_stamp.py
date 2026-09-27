"""The date/time stamp inside datasets\\ file and folder names.

sep. 27, 2026: names switched from the old  20260927_031130  (YYYYMMDD_HHMMSS)
to the readable  sept27_0311AM  (month word + day, zero-padded 12-hour time).
Existing files were NOT renamed, so every reader must accept BOTH - match with
STAMP and read with parse(), never with a hand-written \\d{8}_\\d{6}.

The new stamp has no seconds and no year:
  - Two names made in the same minute would be identical, so writers go
    through unique_path(), which appends -2, -3, ... (sept27_0311AM-2).
  - The year comes from the file's modified time (see parse()).

The new stamp does NOT sort chronologically as text (1012AM < 0311PM,
aug < sept), so "which capture is newer" must compare parse() results,
never the names themselves.

The .ps1 scripts carry their own copy of make()/make_date() (Get-NameStamp /
Get-NameDate) since PowerShell cannot import this - keep MONTHS in sync.
"""

import datetime as _dt
import os
import re

MONTHS = ["jan", "feb", "mar", "apr", "may", "jun",
          "jul", "aug", "sept", "oct", "nov", "dec"]

_OLD = r"\d{8}_\d{6}"
_NEW = r"(?:" + "|".join(MONTHS) + r")(?:0[1-9]|[12]\d|3[01])_(?:0[1-9]|1[0-2])[0-5]\d[AP]M(?:-\d+)?"

# Regex fragment for either stamp format. No groups of its own, so it can be
# dropped into a larger pattern (wrap it in (?P<stamp>...) to capture it).
STAMP = r"(?:" + _OLD + r"|" + _NEW + r")"

_OLD_RE = re.compile(r"^(\d{8})_(\d{6})$")
_NEW_RE = re.compile(r"^(" + "|".join(MONTHS) + r")(\d{2})_(\d{2})(\d{2})([AP]M)(?:-(\d+))?$")
_ANY_RE = re.compile(r"(?<![0-9A-Za-z])" + STAMP + r"(?![0-9A-Za-z])")


def make(when=None):
    """'sept27_0311AM' for `when` (default: now)."""
    when = when or _dt.datetime.now()
    hour12 = when.hour % 12 or 12
    ampm = "AM" if when.hour < 12 else "PM"
    return f"{MONTHS[when.month - 1]}{when.day:02d}_{hour12:02d}{when.minute:02d}{ampm}"


def make_date(when=None):
    """'sept27' for `when` (default: now) - archive folder names."""
    when = when or _dt.datetime.now()
    return f"{MONTHS[when.month - 1]}{when.day:02d}"


def _with_year(month, day, hour, minute, year):
    # feb29 in a non-leap year: step back to the leap year it came from.
    for y in range(year, year - 8, -1):
        try:
            return _dt.datetime(y, month, day, hour, minute)
        except ValueError:
            if not (month == 2 and day == 29):
                raise
    raise ValueError(f"no year fits {month}/{day}")


def parse(stamp, path=None):
    """(datetime, seq) for a stamp in either format. seq is the -N collision
    suffix (1 when there is none), so sorting on the tuple puts sept27_0311AM
    before sept27_0311AM-2.

    The new format has no year: it is taken from `path`'s modified time (the
    current year if no path is given or it cannot be read), then moved back
    one year if that puts the stamp more than a day AFTER the file was last
    written - a dec31 file first looked at in January.

    Raises ValueError for anything that is not a stamp: a name we cannot read
    must fail loudly, not sort as 'oldest'."""
    m = _OLD_RE.match(stamp)
    if m:
        return _dt.datetime.strptime(m.group(1) + m.group(2), "%Y%m%d%H%M%S"), 1
    m = _NEW_RE.match(stamp)
    if not m:
        raise ValueError(f"not a date/time stamp: {stamp!r}")
    mon, day, hh, mm, ampm, seq = m.groups()
    hour12, minute = int(hh), int(mm)
    if not (1 <= hour12 <= 12 and minute <= 59):
        raise ValueError(f"not a date/time stamp: {stamp!r}")
    hour = hour12 % 12 + (12 if ampm == "PM" else 0)
    ref = _dt.datetime.now()
    if path:
        try:
            ref = _dt.datetime.fromtimestamp(os.path.getmtime(path))
        except OSError:
            pass
    try:
        when = _with_year(MONTHS.index(mon) + 1, int(day), hour, minute, ref.year)
        if when > ref + _dt.timedelta(days=1):
            when = _with_year(when.month, when.day, hour, minute, ref.year - 1)
    except ValueError as e:   # e.g. sept31
        raise ValueError(f"not a date/time stamp: {stamp!r} ({e})") from e
    return when, int(seq) if seq else 1


def find(name):
    """The last stamp in a file/folder name, or None."""
    hits = _ANY_RE.findall(name)
    return hits[-1] if hits else None


def unique_path(path, taken=()):
    """`path`, or the same name with -2, -3, ... after its stamp if that name
    is already on disk or in `taken`. Without a stamp the suffix goes before
    the extension."""
    if not os.path.exists(path) and path not in taken:
        return path
    folder, name = os.path.split(path)
    stamp = find(name)
    if stamp:
        cut = name.rfind(stamp) + len(stamp)
        base = re.sub(r"-\d+$", "", stamp)
        head, tail = name[:name.rfind(stamp)] + base, name[cut:]
    else:
        head, tail = os.path.splitext(name)
    n = 2
    while True:
        cand = os.path.join(folder, f"{head}-{n}{tail}")
        if not os.path.exists(cand) and cand not in taken:
            return cand
        n += 1

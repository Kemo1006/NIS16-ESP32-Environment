"""Which analysis CODE made an analysis folder (oct. 21 2026).

features.py writes analysis_info.json next to feature_table.csv:
    {"code": <fingerprint>, "made": <unix time>, "laptop": "<COMPUTER>_<USER>"}

The fingerprint is a hash of the analysis source (analysis/*.py + tools/pcap_retry.py),
line endings normalised so CRLF and LF laptops agree. tools/smart_sync.py uses it: when
this laptop and GitHub both hold a "current" analysis of the same captures but the
numbers differ, the one made with the CURRENT code wins - instead of calling every
difference "a re-render" (the #75/#76 re-analysis was held back that way).
"""
import hashlib
import json
import os
import re
import time

_HERE = os.path.dirname(os.path.abspath(__file__))
_REPO = os.path.dirname(_HERE)
INFO_NAME = "analysis_info.json"
# fake-data generators and tests do not change any real analysis
_SKIP = re.compile(r"^(generate_|test_)")


def code_files():
    out = [os.path.join(_HERE, f) for f in sorted(os.listdir(_HERE))
           if f.endswith(".py") and not _SKIP.match(f)]
    extra = os.path.join(_REPO, "tools", "pcap_retry.py")
    if os.path.isfile(extra):
        out.append(extra)
    return out


def fingerprint():
    h = hashlib.sha1()
    for p in code_files():
        with open(p, "rb") as fh:
            data = fh.read().replace(b"\r\n", b"\n")
        h.update(os.path.basename(p).encode() + b"\0" + hashlib.sha1(data).digest())
    return h.hexdigest()[:16]


def _tag(s):
    return re.sub(r"[^A-Za-z0-9-]", "-", s or "unknown").strip("-") or "unknown"


def write_info(feature_table_path):
    path = os.path.join(os.path.dirname(os.path.abspath(feature_table_path)), INFO_NAME)
    info = {"code": fingerprint(), "made": int(time.time()),
            "laptop": _tag(os.environ.get("COMPUTERNAME")) + "_" + _tag(os.environ.get("USERNAME"))}
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(info, fh, indent=2)
    return info


def read_info(cell_dir):
    try:
        with open(os.path.join(cell_dir, INFO_NAME), encoding="utf-8") as fh:
            return json.load(fh)
    except (OSError, ValueError):
        return None

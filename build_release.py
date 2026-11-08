"""Builds the install zip:   python build_release.py
Creates dist/QuestSharing-<version>.zip with one top-level folder "QuestSharing/" (the folder to drop into
Interface/AddOns) and dist/RELEASE_NOTES.md (the newest section of CHANGELOG.md, for a GitHub release)."""
import pathlib
import re
import sys
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
ADDON = ROOT / "QuestSharing"


def version():
    m = re.search(r"^## Version:\s*(\S+)", (ADDON / "QuestSharing.toc").read_text(), re.M)
    if not m:
        raise SystemExit("no ## Version in QuestSharing.toc")
    return m.group(1)


def notes(ver):
    text = (ROOT / "CHANGELOG.md").read_text()
    m = re.search(r"^## %s\s*\n(.*?)(?=^## |\Z)" % re.escape(ver), text, re.M | re.S)
    if not m:
        raise SystemExit(f"CHANGELOG.md has no section for {ver}")
    return m.group(1).strip() + "\n"


def build():
    ver = version()
    toc = (ADDON / "QuestSharing.toc").read_text().splitlines()
    listed = [line.strip() for line in toc if line.strip() and not line.startswith("#")]
    missing = [f for f in listed if not (ADDON / f).exists()]
    if missing:
        raise SystemExit(f"the .toc lists files that do not exist: {missing}")
    files = sorted(p for p in ADDON.iterdir() if p.suffix in (".lua", ".toc", ".xml"))
    out = ROOT / "dist"
    out.mkdir(exist_ok=True)
    zpath = out / f"QuestSharing-{ver}.zip"
    with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
        for p in files:
            z.write(p, f"QuestSharing/{p.name}")
    (out / "RELEASE_NOTES.md").write_text(notes(ver))
    return zpath, ver, [p.name for p in files]


if __name__ == "__main__":
    zpath, ver, names = build()
    print(f"built {zpath.name} ({zpath.stat().st_size // 1024} KB), version {ver}, {len(names)} files:")
    print("  " + ", ".join(names))

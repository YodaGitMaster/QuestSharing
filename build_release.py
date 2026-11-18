"""Builds the install zip from an allowlist and verifies it before reporting success.

    python build_release.py            build dist/QuestSharing-<version>.zip + dist/RELEASE_NOTES.md
    python build_release.py --check    do every check and build in memory; write nothing
    python build_release.py --force    overwrite a zip of the same version / rebuild an already tagged version
    python build_release.py --bump [patch|minor|major]
                                       start the next release: raise ## Version in the .toc and turn the CHANGELOG's
                                       "## Unreleased" notes into that version's section (default: patch)

What ships (nothing else can get in):
  * every file listed in QuestSharing/QuestSharing.toc,
  * QuestSharing.toc itself,
  * Bindings.xml (the game loads it by name, so the .toc does not list it).
Everything else in the QuestSharing/ folder (.DS_Store, notes, scratch files, sub-folders) is skipped and reported.
Everything outside QuestSharing/ (tests, tools, context, docs, dist) is never looked at.

The build stops when:
  * the .toc lists a file that is missing, listed twice, or spelled with different capitals than on disk,
  * a .lua/.xml file sits in the folder that the game would never load (not in the .toc),
  * CHANGELOG.md has no section for the .toc version,
  * the version does not progress by exactly one step from the last release (git tag vX.Y.Z): the next one is
    X.Y.(Z+1), X.(Y+1).0 or (X+1).0.0; a version that already has a tag, one that skips ahead or goes back, a
    CHANGELOG that is not newest-first, or a newer zip already in dist/ are all refused (--force only allows
    rebuilding a version that already has a tag),
  * dist/QuestSharing-<version>.zip already exists (so a published release is never replaced by newer code by
    accident; bump ## Version in the .toc, or pass --force).
After writing, the zip is opened again and compared byte for byte with the sources.
The zip is reproducible: fixed timestamps and permissions, sorted order, so the same sources give the same SHA256.
"""
import hashlib
import io
import pathlib
import argparse
import re
import subprocess
import zipfile

ROOT = pathlib.Path(__file__).resolve().parent
ADDON = ROOT / "QuestSharing"
TOP = "QuestSharing"                          # the one folder inside the zip: what goes into Interface/AddOns
TOC = "QuestSharing.toc"
LOADED_BY_NAME = ("Bindings.xml",)            # shipped although the .toc does not list them
CODE_SUFFIXES = (".lua", ".xml")              # a file like this that is not shipped is a mistake, not clutter
STAMP = (2000, 1, 1, 0, 0, 0)                 # fixed so builds are reproducible


def toc_text():
    return (ADDON / TOC).read_text()


def version():
    m = re.search(r"^## Version:\s*(\S+)", toc_text(), re.M)
    if not m:
        raise SystemExit(f"no '## Version' line in {TOC}")
    return m.group(1)


def notes(ver):
    text = (ROOT / "CHANGELOG.md").read_text()
    m = re.search(r"^## %s\s*\n(.*?)(?=^## |\Z)" % re.escape(ver), text, re.M | re.S)
    if not m:
        raise SystemExit(f"CHANGELOG.md has no '## {ver}' section")
    return m.group(1).strip() + "\n"


def parse_version(text):
    m = re.fullmatch(r"(\d+)\.(\d+)\.(\d+)", text.strip())
    return tuple(int(x) for x in m.groups()) if m else None


def next_steps(prev):
    a, b, c = prev
    return [(a, b, c + 1), (a, b + 1, 0), (a + 1, 0, 0)]


def fmt(v):
    return ".".join(str(x) for x in v)


def changelog_titles():
    return re.findall(r"^## (.+?)\s*$", (ROOT / "CHANGELOG.md").read_text(), re.M)


def dist_versions():
    out = []
    for p in (ROOT / "dist").glob("QuestSharing-*.zip") if (ROOT / "dist").is_dir() else []:
        out.append(p.stem[len("QuestSharing-"):])
    return out


def git_tags():
    """Released versions (tags vX.Y.Z), or None when git cannot be asked."""
    try:
        r = subprocess.run(["git", "tag", "--list", "v*"], cwd=ROOT, capture_output=True, text=True, timeout=15)
    except (OSError, subprocess.SubprocessError):
        return None
    if r.returncode != 0:
        return None
    return [t[1:] for t in r.stdout.split() if parse_version(t[1:])]


def version_problems(ver, released, titles, zips, allow_released=False):
    """The rules that keep versions progressive. Pure, so it is tested without git.
    released: versions that have a git tag, or None when git is not available;
    titles: the CHANGELOG '## ' headings from top to bottom; zips: versions of the zips already in dist/."""
    cur = parse_version(ver)
    if cur is None:
        return [f"'{ver}' in the .toc is not MAJOR.MINOR.PATCH numbers"]
    problems = []
    nums = []
    for i, t in enumerate(titles):
        if t.lower() == "unreleased":
            if i != 0:
                problems.append("'## Unreleased' must be the first CHANGELOG section")
            continue
        v = parse_version(t)
        if v is None:
            problems.append(f"CHANGELOG section '## {t}' is not a version")
        else:
            nums.append((t, v))
    for (ta, va), (tb, vb) in zip(nums, nums[1:]):
        if va <= vb:
            problems.append(f"CHANGELOG sections are not newest-first: {ta} sits above {tb}")
    if nums and cur < nums[0][1]:
        problems.append(f"the .toc version {ver} is older than the newest CHANGELOG section {nums[0][0]}")
    for z in zips:
        v = parse_version(z)
        if v and v > cur:
            problems.append(f"dist/ already holds QuestSharing-{z}.zip, newer than {ver}")
    if released is None:                                  # no git: the previous release is the section below this one
        previous = max((v for _, v in nums if v < cur), default=None)
        tagged = False
    else:
        rel = [parse_version(t) for t in released]
        tagged = cur in rel
        previous = max((v for v in rel if v != cur), default=None)
    if tagged:
        if not allow_released:
            problems.append(f"{ver} is already released (git tag v{ver}); start the next one with: python build_release.py --bump")
    elif previous is not None:
        if cur <= previous:
            problems.append(f"{ver} is not newer than the last release {fmt(previous)}")
        elif cur not in next_steps(previous):
            problems.append(f"{ver} skips ahead of the last release {fmt(previous)}; the next version is "
                            + " or ".join(fmt(v) for v in next_steps(previous)))
    return problems


def check_versions(ver, allow_released=False):
    problems = version_problems(ver, git_tags(), changelog_titles(), dist_versions(), allow_released)
    if problems:
        raise SystemExit("version check failed:\n  - " + "\n  - ".join(problems))


def bump(kind="patch"):
    """Raise the version by one step and give the unreleased notes their own section. Refuses to skip a release."""
    ver = version()
    cur = parse_version(ver)
    if cur is None:
        raise SystemExit(f"'{ver}' in the .toc is not MAJOR.MINOR.PATCH numbers")
    tags = git_tags()
    if tags is not None and ver not in tags:
        raise SystemExit(f"{ver} is not released yet (no git tag v{ver}): build and release it before starting the next version")
    if unreleased_lines() == 0:
        raise SystemExit("CHANGELOG.md has nothing under '## Unreleased' to release")
    a, b, c = cur
    new = fmt({"patch": (a, b, c + 1), "minor": (a, b + 1, 0), "major": (a + 1, 0, 0)}[kind])
    toc = ADDON / TOC
    toc.write_text(re.sub(r"^(## Version:\s*)\S+", lambda m: m.group(1) + new, toc.read_text(), count=1, flags=re.M))
    log = ROOT / "CHANGELOG.md"
    log.write_text(re.sub(r"^## Unreleased[ \t]*$", "## Unreleased\n\n## " + new, log.read_text(), count=1, flags=re.M))
    problems = version_problems(new, tags, changelog_titles(), dist_versions())
    if problems:
        raise SystemExit("bumped, but the result is inconsistent:\n  - " + "\n  - ".join(problems))
    return ver, new


def unreleased_lines():
    m = re.search(r"^## Unreleased\s*\n(.*?)(?=^## |\Z)", (ROOT / "CHANGELOG.md").read_text(), re.M | re.S)
    return len([l for l in m.group(1).splitlines() if l.strip()]) if m else 0


def plan():
    """Return (shipped names in zip order, skipped names). Raises SystemExit on any inconsistency."""
    listed = [l.strip() for l in toc_text().splitlines() if l.strip() and not l.lstrip().startswith("#")]
    on_disk = {p.name for p in ADDON.iterdir()}
    problems = []
    seen = set()
    for f in listed:
        if f in seen:
            problems.append(f"listed twice in the .toc: {f}")
        seen.add(f)
        if f not in on_disk:
            near = [n for n in on_disk if n.lower() == f.lower()]
            problems.append(f"the .toc lists {f}, which is missing" + (f" (the folder has {near[0]}: wrong capitals)" if near else ""))
        elif not (ADDON / f).is_file():
            problems.append(f"the .toc lists {f}, which is not a file")
    shipped = set(listed) | {TOC} | {n for n in LOADED_BY_NAME if n in on_disk}
    orphans = sorted(n for n in on_disk - shipped if n.endswith(CODE_SUFFIXES) and (ADDON / n).is_file())
    for n in orphans:
        problems.append(f"{n} is in the folder but not in the .toc: the game would never load it (add it or delete it)")
    if problems:
        raise SystemExit("cannot build:\n  - " + "\n  - ".join(problems))
    skipped = sorted(on_disk - shipped)
    return sorted(shipped), skipped


def write_zip(target, names):
    with zipfile.ZipFile(target, "w", zipfile.ZIP_DEFLATED) as z:
        for n in names:
            info = zipfile.ZipInfo(f"{TOP}/{n}", STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, (ADDON / n).read_bytes())


def verify(source, names):
    """Open the finished zip again; it must hold exactly the planned files, unchanged, under one folder."""
    with zipfile.ZipFile(source) as z:
        bad = z.testzip()
        if bad:
            raise SystemExit(f"verify failed: corrupt member {bad}")
        got = z.namelist()
        want = [f"{TOP}/{n}" for n in names]
        if len(got) != len(set(got)):
            raise SystemExit("verify failed: duplicate entries in the zip")
        if sorted(got) != sorted(want):
            extra, lost = sorted(set(got) - set(want)), sorted(set(want) - set(got))
            raise SystemExit(f"verify failed: unexpected {extra}, missing {lost}")
        for n in got:
            if n.startswith("/") or ".." in n.split("/") or not n.startswith(TOP + "/"):
                raise SystemExit(f"verify failed: bad path {n}")
        for n in names:
            if z.read(f"{TOP}/{n}") != (ADDON / n).read_bytes():
                raise SystemExit(f"verify failed: {n} in the zip differs from the source")
        listed = [l.strip() for l in z.read(f"{TOP}/{TOC}").decode().splitlines() if l.strip() and not l.startswith("#")]
        lost = [f for f in listed if f"{TOP}/{f}" not in got]
        if lost:
            raise SystemExit(f"verify failed: the zip's .toc lists files it does not contain: {lost}")


def build(check=False, force=False, out=None, policy=True):
    """out: folder for the zip and notes (default dist/). Tests pass a temp folder so dist/ is never touched.
    policy: apply the progressive-version rules (tests turn it off: they must not depend on the release state)."""
    ver = version()
    if policy:
        check_versions(ver, allow_released=force)
    names, skipped = plan()
    out = pathlib.Path(out) if out else ROOT / "dist"
    zpath = out / f"QuestSharing-{ver}.zip"
    release_notes = notes(ver)
    if zpath.exists() and not (force or check):
        raise SystemExit(f"{zpath} already exists. Bump '## Version' in {TOC} for a new release, "
                         "or pass --force to replace it.")
    if check:
        buf = io.BytesIO()
        write_zip(buf, names)
        buf.seek(0)
        verify(buf, names)
        data = buf.getvalue()
    else:
        out.mkdir(exist_ok=True)
        write_zip(zpath, names)
        verify(zpath, names)
        data = zpath.read_bytes()
        (out / "RELEASE_NOTES.md").write_text(release_notes)
    return ver, zpath, names, skipped, data


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Build and verify the Quest Sharing install zip.")
    ap.add_argument("--check", action="store_true", help="run every check, build in memory, write nothing")
    ap.add_argument("--force", action="store_true", help="replace a zip of the same version / rebuild a tagged version")
    ap.add_argument("--bump", nargs="?", const="patch", choices=("patch", "minor", "major"),
                    help="start the next release (default: patch) instead of building")
    args = ap.parse_args()
    if args.bump:
        old, new = bump(args.bump)
        print(f"version {old} -> {new}: .toc updated and the CHANGELOG notes moved to '## {new}'. "
              "Build with: python build_release.py")
        raise SystemExit(0)
    ver, zpath, names, skipped, data = build(check=args.check, force=args.force)
    verb = "checked (nothing written)" if args.check else "built " + zpath.relative_to(ROOT).as_posix()
    print(f"{verb}: version {ver}, {len(names)} files, {len(data) // 1024} KB, sha256 {hashlib.sha256(data).hexdigest()}")
    print(f"skipped in {TOP}/: {', '.join(skipped) if skipped else 'nothing'}")
    n = unreleased_lines()
    if n:
        print(f"warning: CHANGELOG.md has {n} lines under '## Unreleased'; the zip ships the current code but "
              f"RELEASE_NOTES.md only covers {ver}.")

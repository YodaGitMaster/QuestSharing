"""Regenerate the bundled factual Cooking snapshot from a pinned MIT dataset.

Usage: python3 tools/build_cooking_reference.py [local-recipes.json]
Runtime never downloads anything. NPC/farming records remain in installed Questie.
"""
import json
import pathlib
import sys
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
REV = "6e74500005e80750081b215a0b6dc82748f0ac9f"
URL = f"https://raw.githubusercontent.com/ExcEssIv3/profit/{REV}/export/recipes.json"


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, list):
        return "{" + ",".join(lua(x) for x in value) + "}"
    return "{" + ",".join("[" + lua(k) + "]=" + lua(v) for k, v in value.items() if v is not None) + "}"


def build():
    data = json.loads(pathlib.Path(sys.argv[1]).read_text() if len(sys.argv) > 1 else urllib.request.urlopen(URL).read())
    recipes, item_ids = [], set()
    for r in data["recipes"]:
        if r["profession"] != "Cooking":
            continue
        ingredients = [[i["item"], i["count"]] for i in r["reagents"]]
        books = [i["item"] for i in r["recipe_items"]]
        item_ids.update(i[0] for i in ingredients)
        item_ids.update(books)
        provenance = r.get("zockify", {})
        source = provenance.get("where") or []
        if not source:
            if "trainer" in r["sources"]:
                source = ["Cooking trainer (guide/client data)"]
            elif "trainer_inferred" in r["sources"]:
                source = ["Trainer suggested by client data; unconfirmed"]
            elif books:
                source = ["Learn from recipe item; exact source unknown"]
            else:
                source = ["Source unknown in the reference"]
        recipes.append(dict(id=r["spell"], name=r["name"], skill=r["skill"]["learn"],
                            ingredients=ingredients, books=books, sources=source,
                            uncertain=bool(r["issues"]), output=(r.get("makes") or {}).get("item")))
    recipes.sort(key=lambda r: (r["skill"] if r["skill"] is not None else 10000, r["name"], r["id"]))
    items = {int(i): dict(name=v["name"], vendor=bool(v.get("vendor"))) for i, v in data["items"].items() if int(i) in item_ids}
    license_text = urllib.request.urlopen(f"https://raw.githubusercontent.com/ExcEssIv3/profit/{REV}/LICENSE").read().decode()
    text = ("-- Generated factual Cooking subset; build " + data["build"] + "; checked 2026-11-17.\n"
            "-- Source: " + URL + "\n-- Snapshot includes unknown/unconfirmed entries, labelled by the UI.\n"
            "--[[\nAdapted data from Profit:\n" + license_text + "\n]]\n"
            "local _, ns = ...\nns.cookingReference = { build=" + lua(data["build"]) + ", recipes={\n")
    text += "\n".join("    " + lua(r) + "," for r in recipes)
    text += "\n}, items=" + lua(items) + " }\n"
    (ROOT / "QuestSharing/CookingReference.lua").write_text(text)
    print(f"Generated {len(recipes)} Cooking records and {len(items)} item names")


if __name__ == "__main__":
    build()

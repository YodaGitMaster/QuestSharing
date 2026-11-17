"""Export actual Lua browser rows into a local layout emulation (game textures are approximated)."""
import argparse
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_optional import game as rewards_game
from test_loot import game as loot_game
from test_dungeon_quests import game as dungeon_game


def plain(value):
    text = re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", str(value or ""))
    return re.sub(r"\|H[^|]*\|h(.*?)\|h", r"\1", text)


def capture(g, key):
    api = {"quests": "rewards", "dungeons": "loot", "dungeonQuests": "dungeonQuests"}[key]
    w = g.eval(f"NS.{api}._window()")
    rows = []
    while True:
        for row in w.rows.values():
            if not row.result:
                continue
            row.choose()
            text = w.route.text if key == "quests" else w.detailsText.text
            rows.append(dict(name=plain(row.item.text), subtitle=plain(row["from"].text),
                             task=plain(row.task.text) if key == "dungeonQuests" else "",
                             pickup=plain(row.pickup.text) if key == "dungeonQuests" else "",
                             turnIn=plain(row.turnIn.text) if key == "dungeonQuests" else "",
                             detail=plain(text)))
        if not g.eval(f"NS.{api}.go")(1):
            break
    return rows


def reference(g, directory):
    """Optionally use an external read-only raw QuestieDB reference; never package it."""
    g.run("REFERENCE={};QuestieLoader={ImportModule=function()return REFERENCE end}")
    for kind in ("quest", "npc", "object", "item"):
        g.run((directory / f"questsharing-dungeon-{kind}db.lua").read_text())
    g.run('''
    for kind,api in pairs({quest="QuestDB",npc="NpcDB",object="ObjectDB",item="ItemDB"}) do
      local data=assert(loadstring(REFERENCE[kind.."Data"]))()
      local keys=REFERENCE[kind.."Keys"]
      _G[api]={Get=function(id,key)local row=data[id];return row and row[keys[key]] end,
        GetAllIds=function()local ids={};for id in pairs(data)do ids[#ids+1]=id end;table.sort(ids);return ids end}
    end
    local old=C_Map.GetAreaInfo
    C_Map.GetAreaInfo=function(id)return ({[40]="Westfall",[44]="Redridge Mountains",[1519]="Stormwind City",[1581]="The Deadmines"})[id] or old(id) end
    ''')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument("--questie-reference", type=pathlib.Path)
    parser.add_argument("--addon-dir", type=pathlib.Path, help="Use an isolated runtime snapshot for concurrent work")
    args = parser.parse_args()
    if args.addon_dir:
        import harness
        harness.ADDON_DIR=args.addon_dir.resolve()
        harness.FILES=[line.strip() for line in (harness.ADDON_DIR/'QuestSharing.toc').read_text().splitlines() if line.strip().endswith('.lua')]
    q = rewards_game("modern"); q.slash("rewards"); q.advance(3)
    loot = loot_game("modern"); loot.slash("loot"); loot.advance(3)
    d = dungeon_game("modern", open_tab=False)
    if args.questie_reference:
        reference(d, args.questie_reference)
    d.slash("dungeons"); d.advance(1000)
    d.eval("NS.dungeonQuests._window().dungeon.chooseValue")(1581)
    data = {"quests": capture(q, "quests"), "dungeons": capture(loot, "dungeons"),
            "dungeonQuests": capture(d, "dungeonQuests")}
    template = (ROOT / "tools/search-journal-preview.html").read_text()
    output = args.output.resolve(); output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(template.replace("__JOURNAL_DATA__", json.dumps(data).replace("</", "<\\/")))
    print(output, {key: len(rows) for key, rows in data.items()})


if __name__ == "__main__":
    main()

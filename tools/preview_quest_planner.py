"""Export real Lua guide rows into the interactive Westfall emulation fragment.

Run with the repository's Lua test environment:
  /tmp/questsharing-test-env/bin/python tools/preview_quest_planner.py OUTPUT.html
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tests"))
from test_quest_planner_zone_steps import game, rows

SAMPLE = r'''
QUESTS={}
-- Illustrative metric fixture, not a claim about actual Westfall dimensions.
C_Map.GetMapWorldSize=function(map) if map==1436 then return 3000,2000 end end
GetPlayerFacing=function() return 0 end
QUESTIE_NPCS[603]={name="Field Scout",spawns={[40]={{70,62}}}}
QUESTIE_NPCS[605]={name="Patrol Target",spawns={[40]={{64,82}}}}
QUESTIE_OBJECTS[800]={name="Supply Crates",spawns={[40]={{33,52}}}}
ObjectDB.Get=function(id,key) local o=QUESTIE_OBJECTS[id];return o and o[key] end
QUESTIE_QUESTS[9005]={name="Missing Supplies",questLevel=8,startedBy={{600}},objectives={nil,{{800}}},finishedBy={{600}}}
QUESTIE_QUESTS[9006]={name="Clear the Fields",questLevel=8,startedBy={{600}},objectives={{{603}}},finishedBy={{600}}}
QUESTIE_QUESTS[9007]={name="A Final Patrol",questLevel=8,startedBy={{600}},objectives={{{605}}},finishedBy={{600}},preQuestSingle={9000}}
QuestieLoader.ImportModule=function(_,name)
 if name=="QuestieDB" then return {
  IsDoable=function(id) return id~=9007 end,
  IsDoableVerbose=function() return nil,true,1 end,
  DoableStates={NO_PREQUESTSINGLE=1},
 } end
end
C_Map.GetMapInfoAtPosition=function(map,x,y)
 if map~=1436 then return end
 local name
 if y>0.75 then name="Southern fields"
 elseif x>0.6 then name="Eastern farm"
 elseif x<0.4 then name="Western supply camp"
 elseif x>0.5 then name="Sentinel Hill"
 else name="Harvest fields" end
 return {name=name,mapType=4,parentMapID=1436}
end
'''


def plain(text):
    return re.sub(r"\|c[0-9a-fA-F]{8}|\|r", "", text)


def guide_data():
    g = game("modern", SAMPLE)
    steps = []
    while True:
        row = rows(g)[0]
        g.eval("NS.questPlanner.pin")()
        point = g.eval("WAYPOINT")
        title = plain(row.title.text)
        heading, coordinates = title.split("\n", 1)
        steps.append({"step": row.stepIndex,
                      "heading": re.sub(r"^Step \d+: ", "", heading),
                      "coordinates": coordinates,
                      "lines": plain(row.detail.text).splitlines(),
                      "point": {"map": point.map, "x": point.x, "y": point.y},
                      "nativeRowHeight": row.height,
                      "guidance": {"title": plain(g.eval("QuestSharingDirection.title.text")),
                                   "distance": plain(g.eval("QuestSharingDirection.distance.text")),
                                   "angle": g.eval("QuestSharingDirection.arrow.rotation") or 0}})
        if not g.eval("NS.questPlanner.navigate")(1):
            break
    assert len(steps) == 8, len(steps)
    return {"zone": "Westfall", "example": True, "player": {"x": 0.5, "y": 0.5}, "steps": steps}


def main():
    if len(sys.argv) != 2:
        raise SystemExit("Usage: preview_quest_planner.py OUTPUT.html")
    template = pathlib.Path(__file__).with_name("quest-guide-preview.html").read_text()
    data = guide_data()
    output = pathlib.Path(sys.argv[1]).resolve()
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(template.replace("__QUEST_GUIDE_DATA__", json.dumps(data, ensure_ascii=False)))
    print(f"Wrote {output}: {len(data['steps'])} actual planner steps, {output.stat().st_size} bytes")


if __name__ == "__main__":
    main()

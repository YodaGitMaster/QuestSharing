"""UX review 2026-11-19, batch B4 (map and world): fishing spots, teammate spots, travel pins, zone levels, map search
and /qs gather, through the real Lua modules.        python tests/test_ux_b4.py"""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
import test_optional as optional  # noqa: E402
import test_vendor_map as vendor  # noqa: E402
import test_travel_map as travel  # noqa: E402
import test_zone_levels as zones  # noqa: E402
import test_gather_sources as gather  # noqa: E402
import test_where as where  # noqa: E402

STYLES = ("modern", "classic")


# ---- UX-07 / UX-41: the fishing spots editor -----------------------------------------------------------------------------
def fishing(style):
    g = optional.game(style, 'C_Map.GetMapInfo = function(id) return ({ [1429] = { name = "Elwynn Forest" } })[id] end')
    g.slash("fishing")
    return g, g.eval("NS.fishing._editor()")


def click(g, text):
    g.run('for _,f in ipairs(FRAMES) do if f.text==%r and f.scripts.OnClick then f.scripts.OnClick(f,"LeftButton"); break end end' % text)


def fill_water(e):
    for key, value in (("name", "Crystal Lake"), ("map", "1429"), ("x", "52"), ("y", "66")):
        box = e[key]
        box.SetText(box, value)


def test_ux07_save_hint_names_the_real_setting(style):
    g, e = fishing(style)
    fill_water(e)
    click(g, "Save water")
    text = e.message.text
    assert "Optional" not in text, text
    assert "Show saved spots on the world map" in text and "Settings >" in text, text


def test_ux41_editor_names_the_zone_in_the_list_the_field_and_the_location_button(style):
    g, e = fishing(style)
    fill_water(e)
    click(g, "Save water")
    row = e.rows[1]
    assert "Elwynn Forest" in row.label.text and "map 1429" not in row.label.text, row.label.text
    assert e.zone.text and "Elwynn Forest" in e.zone.text, "the zone name stands beside the Map ID field"
    click(g, "Map location")
    out = "\n".join(g.printed())
    assert "Elwynn Forest" in out and "52.0, 66.0" in out, out


def test_ux41_pin_label_and_tooltip_name_the_skill_and_zone(style):
    g, e = fishing(style)
    g.eval("NS.fishing.save")(g.eval('{name="Crystal Lake",map=1429,x=52,y=66}'))
    g.run("WorldMapFrame.shown=true"); g.slash("fishing on")
    p = g.eval("NS.fishing._pins()[1]")
    assert "(?)" not in p.label.text and "skill unknown" in p.label.text, p.label.text
    p.scripts.OnEnter(p)
    assert any("Elwynn Forest" in str(v) for v in g.eval("TOOLTIP.lines").values())


# ---- UX-10: a teammate's spot does not replace my own fresh waypoint ------------------------------------------------------
SPOT_PRE = r'''
C_Map.GetMapInfo = function(id) return ({ [1429] = { name = "Elwynn Forest" } })[id] end
ITEMREF = {}
EventRegistry = { RegisterCallback = function(self, event, fn, owner) ITEMREF[event] = { fn = fn, owner = owner } end }
function CLICK_LINK(link)
    local cb = ITEMREF.SetItemRef
    cb.fn(cb.owner, link, "[x]", "LeftButton", DEFAULT_CHAT_FRAME)
end
'''


def spot_party(style):
    g = where.party(style, pre=SPOT_PRE)
    where.peer(g, listed="100:0:3/8,2/4")
    return g


def test_ux10_own_recent_waypoint_is_kept_and_the_line_offers_a_link(style):
    g = spot_party(style)
    g.run("C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1429, 0.9, 0.9))")   # the player's own pin
    g.peer("Anna", "S|100|1429|0.3000|0.4000|Wolf Pelt")
    assert g.eval("WAYPOINT.x") == 0.9, "my own waypoint was replaced"
    line = g.printed()[-1]
    assert "Elwynn Forest" in line and "30.0, 40.0" in line, line
    assert "|Haddon:QuestSharing:" in line and "Set waypoint" in line, line
    link = "addon:" + line.split("|Haddon:")[1].split("|h")[0]
    g.eval("CLICK_LINK")(link)
    assert g.eval("WAYPOINT.map") == 1429 and g.eval("WAYPOINT.x") == 0.3 and g.eval("WAYPOINT.y") == 0.4


def test_ux10_without_a_recent_own_waypoint_the_spot_is_set_and_names_the_zone(style):
    g = spot_party(style)
    g.peer("Anna", "S|100|1429|0.3000|0.4000|Wolf Pelt")
    assert g.eval("WAYPOINT.x") == 0.3
    assert "Elwynn Forest" in g.printed()[-1]
    # a teammate's spot may replace a teammate's spot; an old own waypoint does not block either
    g.peer("Anna", "S|100|1429|0.5000|0.6000|Wolf Pelt")
    assert g.eval("WAYPOINT.x") == 0.5
    g.run("C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(1429, 0.9, 0.9)); NOW = NOW + 600")
    g.peer("Anna", "S|100|1429|0.3000|0.4000|Wolf Pelt")
    assert g.eval("WAYPOINT.x") == 0.3


# ---- UX-35: dungeon and transport pins set a waypoint --------------------------------------------------------------------
def test_ux35_dungeon_and_stop_pins_set_a_waypoint_and_say_so(style):
    g = travel.game(style)
    for kind in ("dungeon", "stop"):
        pin = travel.pins(g, kind)[0]
        pin.scripts.OnEnter(pin)
        _, lines = travel.tooltip(g)
        assert any("Click to set a waypoint" in line for line in lines), (kind, lines)
        g.run("WAYPOINT = nil")
        pin.scripts.OnClick(pin, "LeftButton")
        wp = g.eval("WAYPOINT")
        assert wp.map == pin.entry.map and abs(wp.x - pin.entry.x / 100) < 1e-9 and abs(wp.y - pin.entry.y / 100) < 1e-9, kind


# ---- UX-36: zone level badges coloured for my level ----------------------------------------------------------------------
def test_ux36_badges_use_difficulty_colours_for_my_level_and_the_panel_shows_it(style):
    g = zones.game(style, "LEVEL = 15; UnitLevel = function() return LEVEL end")
    v = zones.show(g)
    p = zones.labels(v)
    elwynn, westfall, coast, unknown = (p[i].text.text for i in (1429, 1436, 2001, 2002))
    assert "|cffffd100" not in elwynn + westfall + coast, "ranges are no longer all gold"
    assert len({elwynn[:10], westfall[:10], coast[:10]}) == 3, (elwynn, westfall, coast)
    assert westfall.startswith("|cffffff00"), "10-20 is right for level 15 (yellow): " + westfall
    assert coast.startswith("|cffff1919"), "45-60 is far above level 15 (red): " + coast
    assert unknown.startswith("|cff9d9d9d") and "?" in unknown
    assert "15" in v.heading.text, v.heading.text


# ---- UX-37 / UX-38 / UX-39: map search -----------------------------------------------------------------------------------
def test_ux37_status_explains_elsewhere_and_one_click_sets_the_waypoint(style):
    g = vendor.game(style)
    vendor.type_query(g, "Silken Thread")
    assert "Click Elsewhere to find the closest one." in " ".join(vendor.labels(g))
    button = next(f for f in g.eval("FRAMES").values() if f.text == "Elsewhere" and f.shown)
    button.scripts.OnClick(button)
    assert g.eval("WAYPOINT.map") == 1436, "one click on Elsewhere sets the waypoint"
    text = " ".join(vendor.labels(g))
    assert "Westfall" in text and "Waypoint set" in text, text


def test_ux38_finished_words_are_not_offered_and_trainers_are_labelled_trainers(style):
    g = vendor.game(style, vendor.CLASS_TRAINERS)
    vendor.type_query(g, "vendor")
    labels = [r.suggestion.label for r in vendor.suggestions(g)]
    assert not any("Vendor type" in label for label in labels), labels
    vendor.type_query(g, "pala")
    labels = [r.suggestion.label for r in vendor.suggestions(g)]
    assert "Trainer: Paladin Trainer" in labels and "Vendor: Paladin Trainer" not in labels, labels
    vendor.type_query(g, "trainer")
    labels = [r.suggestion.label for r in vendor.suggestions(g)]
    assert "Trainer: Druid Trainer" in labels and not any(label.startswith("Vendor") for label in labels), labels


def test_ux38_general_goods_is_offered_by_its_kind(style):
    g = vendor.game(style)
    vendor.type_query(g, "gene")
    labels = [r.suggestion.label for r in vendor.suggestions(g)]
    assert "Vendor: General Goods" in labels, labels


def test_ux39_in_combat_the_search_says_it_waits_and_never_says_indexing(style):
    g = vendor.game(style)
    g.run("IN_COMBAT = true")
    vendor.type_query(g, "General Goods")
    text = " ".join(vendor.labels(g))
    assert "Search waits until the fight ends." in text, text
    assert "Indexing" not in text and "QuestieDB NPCs" not in text, text
    g.run("IN_COMBAT = false"); g.fire("PLAYER_REGEN_ENABLED"); g.advance(3)
    assert sorted(p.result.vendor.id for p in vendor.pins(g)) == [1, 1, 2]


# ---- UX-40: /qs gather in plain sentences --------------------------------------------------------------------------------
def test_ux40_gather_command_prints_plain_sentences(style):
    g = gather.game(style)
    g.run("NS.gatherSources.command('1000')"); g.advance(2)
    out = "\n".join(g.printed())
    for word in ("class 7", "subclass", "QuestieDB found", "skinning table", "creature drops"):
        assert word not in out, (word, out)
    assert "Light Hide: shown." in out and "zones known" in out, out
    g.run("QUESTIE_ITEMS[1001].name = 'Copper Bar'; NS.gatherSources.command('1001')")
    assert "Copper Bar is not something you gather, so no places are listed." in "\n".join(g.printed())
    g.run("NS.db.itemSources = false; NS.gatherSources.command('1000')")
    last = g.printed()[-1]
    assert "OFF" not in last and "Settings >" in last, last


# ---- UX-49: the dungeon tooltip names flight master towns -------------------------------------------------------------
def test_ux49_dungeon_tooltip_says_flight_master_town_and_only_you_can_use_for_one_faction(style):
    g = travel.game(style, 1413)
    travel.hover(g, "Wailing Caverns")
    _, lines = travel.tooltip(g)
    assert "Closest flight master towns:" in lines and not any("you can use" in l for l in lines), lines
    g.run("NS.db.travelFaction = 'Horde'; NS.travelMap.refresh()")
    travel.hover(g, "Wailing Caverns")
    _, lines = travel.tooltip(g)
    assert "Closest flight master town you can use:" in lines, lines


ALL_TEXTS = """(function() local out = {}
    for _, f in pairs(FRAMES) do
        if type(f.text) == "string" then out[#out + 1] = f.text end
        for _, c in pairs(f.children or {}) do if type(c.text) == "string" then out[#out + 1] = c.text end end
    end
    return out end)()"""


# ---- UX-63: one name per feature: Zone levels, Fishing spots ---------------------------------------------------------
def test_ux63_zone_levels_panel_is_called_zone_levels(style):
    v = zones.show(zones.game(style))
    assert v.heading.text.startswith("|cffffd100Zone levels|r"), v.heading.text
    assert "Questing levels" not in v.heading.text


def test_ux63_fishing_window_and_map_box_are_called_fishing_spots(style):
    g, e = fishing(style)
    assert g.eval("QuestSharingFishing.title.text") == "Fishing spots"
    g.run("WorldMapFrame.shown=true"); g.slash("fishing on"); g.advance(1)
    texts = list(g.eval(ALL_TEXTS).values())
    assert any("Fishing spots|r" in t for t in texts) and not any("Fishing waters" in t for t in texts), texts


# ---- UX-66: one item tooltip, plain headings -------------------------------------------------------------------------
def test_ux66_item_tooltip_says_sold_by_and_mined_from_veins(style):
    import test_professions as prof
    g = prof.game(style, r"""
      Enum=Enum or {};Enum.TooltipDataType={Item=0}
      POST={}
      TooltipDataProcessor={AddTooltipPostCall=function(kind,fn)POST[#POST+1]=fn end}
      QUESTIE_NPCS[9901]={name="Trader A",subName="General Goods"}
      QUESTIE_NPCS[9902]={name="Trader B",subName="Trade Supplies"}
      QUESTIE_OBJECTS[9903]={name="Copper Vein"}
      QUESTIE_ITEMS[9900]={name="Test Ore",vendors={9901,9902},objectDrops={9903}}
    """)
    g.run('NS.db.itemSources=true;NS.itemSources.refresh()')
    g.run('GameTooltip:SetOwner(UIParent);for _,fn in ipairs(POST) do fn(GameTooltip,{id=9900}) end')
    text = "\n".join(str(v) for v in g.eval('TOOLTIP.lines').values())
    assert "Questie sources" not in text, text
    assert "Sold by: General Goods, Trade Supplies" in text and "Mined from veins" in text, text


def test_ux66_gather_heading_is_where_to_gather(style):
    lines = gather.hover(gather.game(style), 1000)
    assert "Where to gather (for your level and faction)" in lines and not any("Where to get it" in l for l in lines), lines


# ---- UX-67 / UX-68: map search panel matches the other map panels ----------------------------------------------------
def test_ux67_suggestion_box_has_the_stone_and_bronze_panel(style):
    g = vendor.game(style)
    vendor.type_query(g, "gene")
    rows = vendor.suggestions(g)
    assert rows and rows[0].parent.stone, "the suggestion box uses S.panel"


def test_ux68_search_heading_is_gold(style):
    g = vendor.game(style)
    heading = next(t for t in vendor.labels(g) if t and "Search this map" in t)
    assert heading.startswith("|cffffd100Search this map"), heading


if __name__ == "__main__":
    import inspect
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        styles = STYLES if inspect.signature(fn).parameters else (None,)
        for style in styles:
            total += 1
            label = f"{name}[{style}]" if style else name
            try:
                fn(style) if style else fn()
                print("ok  ", label)
            except Exception as e:                       # noqa: BLE001
                failed += 1
                print("FAIL", label, type(e).__name__, str(e)[:400])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)

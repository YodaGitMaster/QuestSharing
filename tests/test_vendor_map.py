"""Map-local seller discovery and search feedback through the real Lua modules."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game
from test_questmap import DATA

SETUP = DATA + r'''
QUESTIE_NPCS = {
    [1]={subName="General Goods",spawns={[12]={{20,30},{25,35}}}},
    [2]={subName="General Goods",spawns={[12]={{40,50}}}},
    [3]={subName="Tailor",spawns={[40]={{60,70}}}},
    [4]={subName="Trade Supplies",spawns={[12]={{70,80}}}},
}
QUESTIE_ITEMS = {
    [10]={name="Refreshing Water",vendors={1}},
    [11]={name="Silken Thread",vendors={3}},
    [12]={name="General Goods Crate",vendors={4}},
}
NpcDB.Get=function(id,key) local r=QUESTIE_NPCS[id]; return r and r[key] end
ItemDB.Get=function(id,key) local r=QUESTIE_ITEMS[id]; return r and r[key] end
NpcDB.GetAllIds=function() return {1,2,3,4} end
ItemDB.GetAllIds=function() return {10,11,12} end
LibQuestieDB.Support.Get=function(name)
    if name=="ZoneDB" then return {private={areaIdToUiMapId="return {[12]=1429,[40]=1436}",areaIdToUiMapIdOverride="return {}"}} end
end
Enum={UIMapType={Continent=2,Zone=3}}
C_Map.GetMapInfo=function(id)
    return ({[1429]={name="Elwynn Forest",parentMapID=100,mapType=3},
             [1436]={name="Westfall",parentMapID=100,mapType=3},
             [100]={name="Eastern Kingdoms",parentMapID=0,mapType=2}})[id]
end
C_Map.GetMapRectOnMap=function(id,parent)
    if parent==100 then
        if id==1429 then return 0,0.5,0,0.5 end
        if id==1436 then return 0.5,1,0.5,1 end
    end
end
'''


def game(style, extra=""):
    g = Game(style, SETUP + extra, fresh=True)
    g.start()
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    g.advance(2)
    return g


def ui(g):
    # Locate the real unnamed edit box, without adding test-only runtime exports.
    return next(f for f in g.eval("FRAMES").values() if f.scripts.OnTabPressed)


def pins(g):
    return [f for f in g.eval("FRAMES").values() if f.result and f.shown]


def labels(g):
    edit = ui(g)
    return [c.text for c in edit.parent.children.values() if c.isFontString]


def type_query(g, text, settle=True):
    edit = ui(g)
    edit.SetText(edit, text)
    edit.scripts.OnTextChanged(edit)
    if settle:
        g.advance(3)


def suggestions(g):
    return [f for f in g.eval("FRAMES").values() if f.suggestion and f.shown and f.parent.shown]


def test_role_search_includes_unlinked_npcs_and_all_spawns(style):
    g = game(style)
    g.eval("NS.vendorMap.search")("General Goods", True, "vendor")
    g.advance(3)
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2]


def test_pins_use_an_icon_for_the_kind_of_npc(style):
    g = game(style, "CLASS_ICON_TCOORDS = { DRUID = { 0.5, 0.75, 0.5, 0.75 } }")
    icon = g.eval("function(t) local tex, c = NS.vendorMap.iconFor(t); return tex .. '|' .. (c and c[1] or '') end")
    assert icon("Druid Trainer") == "Interface\\GLUES\\CHARACTERCREATE\\UI-CHARACTERCREATE-CLASSES|0.5"
    assert icon("Mining Trainer").endswith("Trade_Mining|") and icon("Alchemy Trainer").endswith("Trade_Alchemy|")
    assert icon("Innkeeper").endswith("INV_Misc_Rune_01|") and icon("Flight Master").endswith("INV_Misc_Map_01|")
    assert icon("Banker").endswith("INV_Misc_Coin_01|") and icon("Weapon Master").endswith("INV_Sword_04|")
    assert icon("Warrior Trainer").endswith("INV_Misc_Book_09|"), "no class art on this client: the generic trainer book"
    assert icon("Fishing Trainer").endswith("Trade_Fishing|") and icon("Cooking Trainer").endswith("INV_Misc_Food_15|")
    assert icon("First Aid Trainer").endswith("INV_Misc_Bandage_15|")
    assert icon("Food & Drink").endswith("INV_Misc_Bag_10|"), "a food vendor must not look like the cooking trainer"
    assert icon("General Goods").endswith("INV_Misc_Bag_10|") and icon("").endswith("INV_Misc_Bag_10|")
    g.eval("NS.vendorMap.search")("General Goods", True, "vendor")
    g.advance(3)
    assert {p.icon.texture for p in pins(g)} == {"Interface\\Icons\\INV_Misc_Bag_10"}


def test_suggestions_only_offer_results_on_the_shown_map(style):
    g = game(style)
    type_query(g, "ta")
    assert not suggestions(g), "Remote Tailor must not be offered in Elwynn"
    type_query(g, "gene")
    assert suggestions(g)


def test_role_suggestion_does_not_mix_in_item_name_matches(style):
    g = game(style)
    type_query(g, "general")
    row = next(r for r in suggestions(g) if r.suggestion.value == "General Goods")
    row.scripts.OnClick(row)
    g.advance(3)
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2]


def test_item_search_only_pins_known_sellers_and_names_query_and_map(style):
    g = game(style)
    type_query(g, "Refreshing Water")
    assert [p.result.vendor.id for p in pins(g)] == [1, 1]
    text = " ".join(labels(g))
    assert "Elwynn Forest" in text and "Refreshing Water" in text and "2" in text


def test_remote_results_require_explicit_elsewhere_action(style):
    g = game(style)
    type_query(g, "Silken Thread")
    assert not pins(g)
    assert "Closest" not in " ".join(labels(g))
    button = next(f for f in g.eval("FRAMES").values() if f.text == "Elsewhere" and f.shown)
    assert button.label.text == "Elsewhere"
    button.scripts.OnClick(button)                       # one click finds the closest one and sets the waypoint
    assert "Closest" in " ".join(labels(g)) and "Westfall" in " ".join(labels(g))
    assert button.label.text == "Waypoint"
    assert g.eval("WAYPOINT.map") == 1436


def test_map_change_updates_suggestions_and_local_pins(style):
    g = game(style)
    type_query(g, "ta")
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert len(pins(g)) == 1
    assert any(r.suggestion.value == "Tailor" for r in suggestions(g))
    assert "Westfall" in " ".join(labels(g))


def test_continent_projects_both_zones_and_clear_hides_every_pin(style):
    g = game(style)
    g.run("WORLDMAP_ID=100")
    type_query(g, "Goods")
    assert len(pins(g)) >= 3
    type_query(g, "")
    assert not pins(g) and not suggestions(g)


def test_category_search_works_without_enumerable_items(style):
    g = game(style, "ItemDB.GetAllIds=nil")
    g.eval("NS.vendorMap.search")("General Goods", True, "vendor")
    g.advance(3)
    assert len(pins(g)) == 3


def test_old_provider_retains_item_linked_vendor_search(style):
    g = game(style, "NpcDB.GetAllIds=nil")
    g.eval("NS.vendorMap.search")("Refreshing Water", True)
    g.advance(3)
    assert len(pins(g)) == 2


def test_item_suggestion_is_exact_and_keeps_its_kind_when_submitted(style):
    g = game(style, '''
QUESTIE_ITEMS[13]={name="Refreshing Water Bottle",vendors={4}}
ItemDB.GetAllIds=function() return {10,11,12,13} end
''')
    type_query(g, "Refresh")
    row = next(r for r in suggestions(g) if r.suggestion.value == "Refreshing Water")
    row.scripts.OnClick(row)
    g.advance(3)
    edit = ui(g)
    edit.scripts.OnEnterPressed(edit)
    assert [p.result.vendor.id for p in pins(g)] == [1, 1]
    assert not suggestions(g)


def test_invalid_and_dungeon_coordinates_do_not_produce_suggestions_or_pins(style):
    g = game(style, '''
QUESTIE_NPCS[3].spawns={[12]={{-1,-1},{120,20},{20,-2}}}
''')
    type_query(g, "Tail")
    assert not pins(g) and not suggestions(g)


LARGE_CATALOGUE = r'''
NPC_ENUMERATIONS=0
local all={}
for id=1,600 do
    all[#all+1]=id
    QUESTIE_NPCS[id]={subName="General Goods",spawns={[12]={{id/10,50}}}}
end
NpcDB.GetAllIds=function() NPC_ENUMERATIONS=NPC_ENUMERATIONS+1; return all end
'''


def test_typing_during_batched_loading_refreshes_pins_and_suggestions(style):
    g = Game(style, SETUP + LARGE_CATALOGUE, fresh=True)
    g.start()
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    type_query(g, "gene", settle=False)
    assert not pins(g)
    g.advance(20)
    assert len(pins(g)) == 600
    assert any(r.suggestion.value == "General Goods" for r in suggestions(g))


def test_cancelled_loading_cannot_reset_a_replacement_scan(style):
    g = Game(style, SETUP + LARGE_CATALOGUE, fresh=True)
    g.start()
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    type_query(g, "gene", settle=False)
    g.advance(0.5)
    assert g.eval("NPC_ENUMERATIONS") == 1
    g.run("NS.db.vendorSearch=false; NS.vendorMap.refresh(); NS.db.vendorSearch=true; NS.vendorMap.refresh()")
    g.eval("NS.vendorMap.search")("General Goods", True, "vendor")
    g.advance(20)
    assert g.eval("NPC_ENUMERATIONS") == 1, "the replacement scan reads the NPC list saved by the first one"
    assert len(pins(g)) == 600
    assert not suggestions(g)


def test_map_change_and_new_query_reset_elsewhere_mode(style):
    g = game(style)
    type_query(g, "Silken Thread")
    button = next(f for f in g.eval("FRAMES").values() if f.text == "Elsewhere" and f.shown)
    button.scripts.OnClick(button)
    type_query(g, "Tailor")
    assert "Closest" not in " ".join(labels(g)) and button.label.text == "Elsewhere"
    button.scripts.OnClick(button)
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert len(pins(g)) == 1 and not button.shown


def test_escape_dismisses_suggestions_and_hover_explains_query(style):
    g = game(style)
    type_query(g, "gene")
    assert suggestions(g)
    edit = ui(g)
    edit.scripts.OnEscapePressed(edit)
    assert not suggestions(g)
    pin = pins(g)[0]
    pin.scripts.OnEnter(pin)
    assert any("gene" in line for line in g.eval("TOOLTIP.lines").values())


SELLERS = r'''
LibQuestieDB.RequireContract=function(version) assert(version==4); return true end
LibQuestieDB.Enum={npcFlags={VENDOR=1024}}
QUESTIE_NPCS[5]={npcFlags=1030,spawns={[12]={{80,90}}}}
QUESTIE_NPCS[6]={subName="Captain",npcFlags=2,spawns={[12]={{10,10}}}}
QUESTIE_NPCS[3].npcFlags=1024
QUESTIE_NPCS[7]={subName="General Store",npcFlags=1024,spawns={[40]={{50,60}}}}
QUESTIE_NPCS[8]={subName="Tailoring Trainer",npcFlags=16,spawns={[12]={{15,15}}}}
NpcDB.GetAllIds=function() return {1,2,3,4,5,6,7,8} end
'''


def test_vendor_means_all_local_sellers_including_untitled_flagged_npcs(style):
    g = game(style, SELLERS)
    for query in ("vendor", "vendors", "all vendors", "seller", "merchants"):
        type_query(g, query)
        assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2, 4, 5], query


def test_general_vendor_narrows_roles_without_item_name_matches_or_remote_pins(style):
    g = game(style, SELLERS)
    for query in ("general vendor", "general vendors", "vendor general", "General seller"):
        type_query(g, query)
        assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2], query


def test_vendor_query_replaces_pins_when_browsing_another_zone(style):
    g = game(style, SELLERS)
    type_query(g, "vendor")
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert sorted(p.result.vendor.id for p in pins(g)) == [3, 7]
    assert all(p.result.spawn.map == 1436 for p in pins(g))


def test_general_vendor_suggestions_use_local_role_meaning(style):
    g = game(style, SELLERS)
    type_query(g, "general vendor")
    row = next(r for r in suggestions(g) if r.suggestion.value == "General Goods")
    row.scripts.OnClick(row)
    g.advance(3)
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2]


def test_vendor_without_flag_enum_keeps_known_linked_and_role_sellers(style):
    g = game(style)
    type_query(g, "vendor")
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2, 4]


def test_seller_suggestion_keeps_non_sellers_out_of_general_results(style):
    g = game(style, SELLERS + '''
QUESTIE_NPCS[6].subName="General Commander"
''')
    type_query(g, "gener vendor")                         # word completions only while the word is unfinished
    row = next(r for r in suggestions(g) if r.suggestion.value == "General")
    row.scripts.OnClick(row)
    g.advance(3)
    ui(g).scripts.OnEnterPressed(ui(g))
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2]


def test_provider_rejecting_flag_contract_falls_back_without_guessing_mask(style):
    g = game(style, SELLERS + "\nLibQuestieDB.RequireContract=function() return false end")
    type_query(g, "vendor")
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2, 4]


def test_explicit_item_query_can_contain_vendor_word(style):
    g = game(style, SELLERS + '''
QUESTIE_ITEMS[13]={name="Vendor Token",vendors={4}}
ItemDB.GetAllIds=function() return {10,11,12,13} end
''')
    type_query(g, "Vendor T")
    row = next(r for r in suggestions(g) if r.suggestion.value == "Vendor Token")
    row.scripts.OnClick(row)
    g.advance(3)
    assert [p.result.vendor.id for p in pins(g)] == [4]


CLASS_TRAINERS = r'''
QUESTIE_NPCS[1].subName="Druid Trainer"
QUESTIE_NPCS[2].subName="Paladin Trainer"
'''


def test_class_trainers_are_found_independently_of_item_seller_links(style):
    g = game(style, CLASS_TRAINERS)
    for query, expected in (("druid trainer", [1, 1]), ("paladin trainer", [2])):
        type_query(g, query)
        assert sorted(p.result.vendor.id for p in pins(g)) == expected, query
        ui(g).scripts.OnEnterPressed(ui(g))
        assert sorted(p.result.vendor.id for p in pins(g)) == expected, query


def test_unlinked_paladin_trainer_has_local_suggestion_and_clickable_waypoint(style):
    g = game(style, CLASS_TRAINERS)
    type_query(g, "paladin tra")
    row = next(r for r in suggestions(g) if r.suggestion.value == "Paladin Trainer")
    row.scripts.OnClick(row)
    g.advance(3)
    pin = pins(g)[0]
    assert pin.result.vendor.id == 2
    pin.scripts.OnClick(pin)
    assert g.eval("WAYPOINT.map") == 1429
    assert g.eval("WAYPOINT.x") == 0.4 and g.eval("WAYPOINT.y") == 0.5


def test_paladin_trainer_is_not_pinned_on_a_different_zone_map(style):
    g = game(style, CLASS_TRAINERS)
    type_query(g, "paladin trainer")
    assert len(pins(g)) == 1
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert not pins(g)
    text = " ".join(labels(g))
    assert "0 locations" in text and "Westfall" in text


def test_skinner_alias_plural_punctuation_and_word_order_find_skinning_trainer(style):
    g = game(style, 'QUESTIE_NPCS[2].subName="Skinning Trainer"')
    for query in ("skinner trainer", "skinners trainers", "SKINNER-TRAINER", "trainer skinner",
                  "skiner trainer", "skinning tranier", "skin trainer"):
        type_query(g, query)
        assert [p.result.vendor.id for p in pins(g)] == [2], query
    row = next(r for r in suggestions(g) if r.suggestion.value == "Skinning Trainer")
    row.scripts.OnClick(row)
    g.advance(3)
    assert [p.result.vendor.id for p in pins(g)] == [2]


def test_profession_worker_names_match_training_titles(style):
    for worker, profession in (("miner", "Mining"), ("blacksmith", "Blacksmithing"),
                               ("leatherworker", "Leatherworking"), ("herbalist", "Herbalism"),
                               ("alchemist", "Alchemy"), ("engineer", "Engineering"),
                               ("enchanter", "Enchanting"), ("fisherman", "Fishing"),
                               ("tailor", "Tailoring"), ("cook", "Cooking")):
        g = game(style, f'QUESTIE_NPCS[2].subName="{profession} Trainer"')
        type_query(g, worker + " trainer")
        assert [p.result.vendor.id for p in pins(g)] == [2], worker


def test_one_typo_or_transposition_in_class_and_trainer_is_tolerated(style):
    g = game(style, CLASS_TRAINERS)
    for query in ("paldin trainer", "paladinn trainer", "paladin tranier", "paladim trainer"):
        type_query(g, query)
        assert [p.result.vendor.id for p in pins(g)] == [2], query
        assert any(r.suggestion.value == "Paladin Trainer" for r in suggestions(g)), query


def test_short_or_unrelated_queries_do_not_get_arbitrary_fuzzy_matches(style):
    g = game(style, CLASS_TRAINERS)
    for query in ("xxx trainer", "palxxin trainer", "skinner trainer"):
        type_query(g, query)
        assert not pins(g), query


def test_elastic_matches_stay_on_displayed_map_and_explicit_items_stay_exact(style):
    g = game(style, 'QUESTIE_NPCS[3].subName="Skinning Trainer"')
    type_query(g, "skinner trainer")
    assert not pins(g) and not suggestions(g)
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert [p.result.vendor.id for p in pins(g)] == [3]
    g.eval("NS.vendorMap.search")("Silken Threaf", True, "item")
    g.advance(3)
    assert not pins(g)


def test_exact_local_role_wins_over_near_spelling_match(style):
    g = game(style, '''
QUESTIE_NPCS[1].subName="Paladin Trainer"
QUESTIE_NPCS[2].subName="Paladim Trainer"
''')
    type_query(g, "paladin trainer")
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1]


def test_suggestion_ranking_keeps_exact_word_ahead_of_spelling_fallback(style):
    g = game(style, '''
QUESTIE_NPCS[1].subName="Paladin Trainer"
QUESTIE_NPCS[2].subName="Paladim Trainer"
''')
    type_query(g, "paladin tra")
    rows = suggestions(g)
    assert rows[0].suggestion.value == "Paladin Trainer"
    assert any(r.suggestion.value == "Paladim Trainer" for r in rows)


def test_exact_local_item_does_not_gain_unrelated_fuzzy_role_pins(style):
    g = game(style, '''
QUESTIE_NPCS[2].subName="Paladim Trainer"
QUESTIE_ITEMS[10].name="Paladin Trainer"
''')
    type_query(g, "paladin trainer")
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1]


def test_empty_and_short_typo_queries_do_not_expand_to_everything(style):
    g = game(style, 'QUESTIE_NPCS[2].subName="Mage Trainer"')
    for query in (" ", "---", "maeg trainer", "all", "the"):
        type_query(g, query)
        assert not pins(g), query


def test_generic_vendor_typos_still_mean_local_sellers(style):
    g = game(style, SELLERS)
    for query in ("vendro", "all vednors", "seler"):
        type_query(g, query)
        assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2, 4, 5], query
    type_query(g, "general vednor")
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2]


def test_remote_exact_role_does_not_suppress_a_local_spelling_match(style):
    g = game(style, '''
QUESTIE_NPCS[2].subName="Paladim Trainer"
QUESTIE_NPCS[3].subName="Paladin Trainer"
''')
    type_query(g, "paladin trainer")
    assert [p.result.vendor.id for p in pins(g)] == [2]


def test_non_ascii_role_tokens_keep_literal_matching(style):
    g = game(style, 'QUESTIE_NPCS[2].subName="Écorcheur Maître"')
    type_query(g, "Écorcheur Maître")
    assert [p.result.vendor.id for p in pins(g)] == [2]


# Classic Era size (QuestieDB read-performance.md): 10,122 NPCs and 14,899 items. NPCs 1..1500 are sellers in Elwynn
# (area 12, the shown map 1429), the rest are untitled mobs; items 1..3000 are sold by them. debugprofilestop is a
# virtual clock that charges each database read like the game does: 4 us for a scalar (or nil), 10 us for a table.
CLASSIC_CATALOGUE = r'''
local NPCS, SELLERS, ITEMS, SOLD = 10122, 1500, 14899, 3000
QUESTIE_NPCS, QUESTIE_ITEMS = {}, {}
local npcIDs, itemIDs = {}, {}
for id = 1, NPCS do
    npcIDs[id] = id
    QUESTIE_NPCS[id] = id <= SELLERS and { subName = id % 3 == 0 and "Trade Supplies" or "General Goods",
        spawns = { [12] = { { (id % 100) / 1.01, 50 } } } } or { name = "Mob " .. id }
end
for id = 1, ITEMS do
    itemIDs[id] = 100000 + id
    QUESTIE_ITEMS[100000 + id] = id <= SOLD and { name = "Linen Cloth " .. id, vendors = { id % SELLERS + 1 } }
        or { name = "Drop " .. id }
end
VCLOCK, ENUMS, SPAWN_READS = 0, { npc = 0, item = 0 }, 0
debugprofilestop = function() return VCLOCK end
local function charge(v) VCLOCK = VCLOCK + (type(v) == "table" and 0.010 or 0.004); return v end
NpcDB.Get = function(id, key)
    if key == "spawns" then SPAWN_READS = SPAWN_READS + 1 end
    local r = QUESTIE_NPCS[id]; return charge(r and r[key])
end
ItemDB.Get = function(id, key) local r = QUESTIE_ITEMS[id]; return charge(r and r[key]) end
NpcDB.GetAllIds = function() ENUMS.npc = ENUMS.npc + 1; return npcIDs end
ItemDB.GetAllIds = function() ENUMS.item = ENUMS.item + 1; return itemIDs end
-- test-side reader of the visible suggestion rows (one Lua loop instead of one Python call per frame)
function SHOWN_SUGGESTIONS()
    local out = {}
    for _, f in ipairs(FRAMES) do
        if f.suggestion and f.shown and f.parent and f.parent.shown then out[#out + 1] = f.suggestion.value end
    end
    return table.concat(out, "|")
end
'''


def classic_game(style):
    g = Game(style, SETUP + CLASSIC_CATALOGUE, fresh=True)
    g.start()
    g.run("NS.db.vendorSearch=true; WorldMapFrame:Show(); NS.vendorMap.refresh()")
    g.advance(3)
    return g


def type_keys(g, edit, word, start=1):
    """A player typing 10 keys per second; returns right after the last key."""
    for i in range(start, len(word) + 1):
        edit.SetText(edit, word[:i])
        edit.scripts.OnTextChanged(edit)
        if i < len(word):
            g.advance(0.1)


def wait_for(g, ready, cap=30, each=None):
    """Seconds (0.1 s frames) from the last keystroke until ready(); None if it never happens within cap."""
    for frame in range(1, int(cap * 10) + 1):
        g.advance(0.1)
        if each:
            each(frame)
        if ready():
            return frame / 10
    return None


def test_classic_size_suggestions_arrive_quickly_while_typing(style):
    g = classic_game(style)
    assert dict(g.eval("ENUMS").items()) == {"npc": 0, "item": 0}, "map open enumerated the catalogue"
    assert g.eval("VCLOCK") == 0, "map open read the database"
    edit = ui(g)
    shown = lambda: g.eval("SHOWN_SUGGESTIONS()")
    status = []
    type_keys(g, edit, "gene")
    cold = wait_for(g, lambda: "General Goods" in shown(), each=lambda _: status.append(" ".join(labels(g))))
    assert cold is not None, "no suggestion for cold 'gene'"
    assert cold <= 1.5, f"cold 'gene' first suggestion after {cold}s (target <= 1.5 s)"
    assert any("Reading the NPC list" in s and "/ 10,122" in s for s in status), status

    # Refining the text keeps the last suggestions visible until the new ones replace them.
    type_keys(g, edit, "gener", start=5)
    for _ in range(10):
        g.advance(0.1)
        assert "General Goods" in shown(), "suggestions blinked out while refining the query"
    spawn_reads = g.eval("SPAWN_READS")
    type_keys(g, edit, "general", start=6)
    g.advance(2)
    assert g.eval("SPAWN_READS") == spawn_reads, "locations of the same matches were read again"

    # An unrelated query never shows the previous suggestions, then gets its own from the warm index.
    type_keys(g, edit, "trade")
    assert "General" not in shown()
    warm = wait_for(g, lambda: "Trade Supplies" in shown())
    assert warm is not None, "no suggestion for warm 'trade'"
    assert warm <= 0.3, f"warm 'trade' first suggestion after {warm}s (target <= 0.3 s)"
    assert dict(g.eval("ENUMS").items()) == {"npc": 1, "item": 0}, "keystrokes restarted the catalogue index"


def test_classic_size_item_query_indexes_items_once_and_suggests_local_items(style):
    g = classic_game(style)
    edit = ui(g)
    type_keys(g, edit, "linen")
    first = wait_for(g, lambda: "Linen Cloth" in g.eval("SHOWN_SUGGESTIONS()"))
    assert first is not None, "no item suggestion for 'linen'"
    assert first <= 3, f"cold 'linen' first suggestion after {first}s"
    type_keys(g, edit, "linen cloth 1", start=6)
    g.advance(2)
    assert "Linen Cloth 1" in g.eval("SHOWN_SUGGESTIONS()")
    assert dict(g.eval("ENUMS").items()) == {"npc": 1, "item": 1}


def test_typing_uses_the_foreground_slice_and_a_programmatic_search_keeps_the_shared_one(style):
    def slices(g, seconds):
        out, before = [], g.eval("VCLOCK")
        for _ in range(int(seconds * 10)):
            g.advance(0.1)
            now = g.eval("VCLOCK")
            out.append(now - before)
            before = now
        return out

    g = classic_game(style)
    edit = ui(g)
    type_keys(g, edit, "g")
    typed = slices(g, 1.5)
    assert max(typed) <= 8.02, typed  # 8 ms foreground slice plus at most one database read
    assert max(typed) > 6, typed
    g = classic_game(style)
    g.eval("NS.vendorMap.search")("General Goods", True, "vendor")
    assert max(slices(g, 1.5)) <= 2.02  # no typing: the shared 2 ms slice, as for every background job


def test_hidden_map_pauses_the_typed_index_and_reopening_continues_it(style):
    g = classic_game(style)
    edit = ui(g)
    type_keys(g, edit, "gene")
    g.advance(0.2)
    g.run("WorldMapFrame:Hide(); NS.vendorMap.refresh()")
    before = g.eval("VCLOCK")
    g.advance(3)
    assert g.eval("VCLOCK") == before, "the index read data while the map was hidden"
    g.run("WorldMapFrame:Show(); NS.vendorMap.refresh()")
    assert wait_for(g, lambda: "General Goods" in g.eval("SHOWN_SUGGESTIONS()"), cap=5) is not None
    assert g.eval("ENUMS.npc") == 1


def test_locations_stay_cached_across_queries_until_map_change_or_provider_loss(style):
    g = game(style)
    type_query(g, "gene")
    general = pins(g)[0].result.vendor
    type_query(g, "trade")
    trade = pins(g)[0].result.vendor
    assert general.spawns is not None, "a keystroke wiped the cached locations"
    g.run("WORLDMAP_ID=1436; NS.vendorMap.refresh()")
    assert general.spawns is None, "map change kept locations of an earlier query"
    assert trade.spawns is not None, "map change dropped the current matches"
    g.run("SAVED_NPC_DB=NpcDB; SAVED_ITEM_DB=ItemDB; " + NO_DATABASE + "; NS.vendorMap.refresh()")
    assert trade.spawns is None


NO_DATABASE = "QuestDB=nil; NpcDB=nil; ItemDB=nil; ObjectDB=nil; LibQuestieDB=nil; QuestieLoader=nil; Questie=nil"


def test_missing_database_explained_before_and_after_typing(style):
    g = game(style, NO_DATABASE)
    for query in ("", "vendor", "Paladin Trainer"):
        type_query(g, query)
        text = " ".join(labels(g))
        assert "requires QuestieDB" in text, text
        assert "/qs questie" in text and "Questie is optional" in text
        assert "No known seller" not in text
        assert not pins(g) and not suggestions(g)
        assert not g.eval('NS.dataWork.busy("vendor-search")')


def test_non_enumerable_database_explains_update_instead_of_no_seller(style):
    g = game(style, "NpcDB.GetAllIds=nil; ItemDB.GetAllIds=nil")
    type_query(g, "vendor")
    text = " ".join(labels(g))
    assert "newer QuestieDB" in text and "/qs questie" in text, text
    assert not pins(g)


def test_questiedb_without_questie_addon_can_search_and_says_so(style):
    g = game(style, "Questie=nil; QuestieLoader=nil")
    assert "QuestieDB" in " ".join(labels(g))
    type_query(g, "vendor")
    assert len(pins(g)) >= 3


def test_late_database_recovers_same_query_without_toggle_or_reload(style):
    g = game(style, "SAVED_NPC_DB=NpcDB; SAVED_ITEM_DB=ItemDB; SAVED_LIB=LibQuestieDB; " + NO_DATABASE)
    type_query(g, "vendor")
    g.run("NpcDB=SAVED_NPC_DB; ItemDB=SAVED_ITEM_DB; LibQuestieDB=SAVED_LIB; NS.vendorMap.refresh()")
    g.advance(3)
    assert len(pins(g)) >= 3
    assert "requires QuestieDB" not in " ".join(labels(g))


def test_lost_database_clears_stale_results_and_restores_fresh_index(style):
    g = game(style)
    type_query(g, "vendor")
    assert pins(g)
    g.run("SAVED_NPC_DB=NpcDB; SAVED_ITEM_DB=ItemDB; SAVED_LIB=LibQuestieDB; " + NO_DATABASE + "; NS.vendorMap.refresh()")
    assert not pins(g) and not suggestions(g)
    assert "requires QuestieDB" in " ".join(labels(g))
    g.run("QUESTIE_NPCS[2].subName='Mage Trainer'; NpcDB=SAVED_NPC_DB; ItemDB=SAVED_ITEM_DB; LibQuestieDB=SAVED_LIB; NS.vendorMap.refresh()")
    g.advance(3)
    assert 2 not in [p.result.vendor.id for p in pins(g)]


FAIL_ONCE = r'''
WorldMapFrame.ScrollContainer.HookScript = function(self, event, fn) self.hooks = self.hooks or {}; self.hooks[event] = fn end
'''
# An error in the add-on's own job code (QuestieDB getter errors are already caught): once in the role index, or
# once while the search job reads locations.
BREAK_ONCE = {
    "index": '''local get = NS.questie.get
NS.questie.get = function(kind, id, key)
    if key == "subName" then NS.questie.get = get; error("simulated index failure") end
    return get(kind, id, key)
end''',
    "search": '''local spawns = NS.questie.spawnList
NS.questie.spawnList = function(...) NS.questie.spawnList = spawns; error("simulated search failure") end''',
}


def explicit_search(g, action):
    edit = ui(g)
    if action == "enter":
        edit.scripts.OnEnterPressed(edit)
    elif action == "icon":
        icon = next(c for c in edit.children.values() if c.scripts and c.scripts.OnClick)
        icon.scripts.OnClick(icon)
    else:
        g.run("CTRL=true; WorldMapFrame.ScrollContainer.hooks.OnMouseDown(WorldMapFrame.ScrollContainer, 'RightButton'); CTRL=false")


def test_explicit_search_with_the_same_text_retries_after_a_failed_vendor_job(style):
    g = game(style, FAIL_ONCE)
    type_query(g, "gene")
    expected = sorted(p.result.vendor.id for p in pins(g))
    assert expected
    for job, code in BREAK_ONCE.items():
        for action in ("enter", "icon", "ctrl-right-click"):
            g = game(style, FAIL_ONCE)
            g.run(code)
            type_query(g, "gene")
            g.advance(3)  # the map's own redraws do not retry a failed job
            assert not pins(g), (job, action)
            assert "try the search again" in " ".join(labels(g)), (job, action)
            explicit_search(g, action)
            assert ui(g).text == "gene"
            g.advance(3)
            assert sorted(p.result.vendor.id for p in pins(g)) == expected, (job, action)
            assert "try the search again" not in " ".join(labels(g)), (job, action)


def test_libquestiedb_only_provider_is_supported(style):
    g = game(style, "LibQuestieDB.Npc=NpcDB; LibQuestieDB.Item=ItemDB; "
             "QuestDB=nil; NpcDB=nil; ItemDB=nil; Questie=nil; QuestieLoader=nil")
    type_query(g, "vendor")
    assert len(pins(g)) >= 3
    assert "requires QuestieDB" not in " ".join(labels(g))


def test_item_search_reads_vendor_links_only_for_items_with_the_typed_words(style):
    g = game(style, r'''
VENDOR_READS, ITEM_SCANS = {}, 0
local get, ids = ItemDB.Get, ItemDB.GetAllIds
ItemDB.Get = function(id, key) if key == "vendors" then VENDOR_READS[id] = (VENDOR_READS[id] or 0) + 1 end; return get(id, key) end
ItemDB.GetAllIds = function() ITEM_SCANS = ITEM_SCANS + 1; return ids() end
''')
    type_query(g, "silk")
    reads = g.eval("VENDOR_READS")
    assert reads[11] == 1 and reads[10] is None and reads[12] is None
    assert g.eval("ITEM_SCANS") == 1
    type_query(g, "silken")                       # the scan for "silk" already holds every match
    assert g.eval("ITEM_SCANS") == 1
    type_query(g, "thread")                       # other words: a new scan, the links already read are kept
    assert g.eval("ITEM_SCANS") == 2 and g.eval("VENDOR_READS")[11] == 1
    type_query(g, "")
    assert g.eval("ITEM_SCANS") == 2


def test_seller_search_does_not_scan_items_when_the_provider_flags_vendors(style):
    g = game(style, SELLERS + "\nITEM_SCANS=0\nlocal ids=ItemDB.GetAllIds\nItemDB.GetAllIds=function() ITEM_SCANS=ITEM_SCANS+1; return ids() end")
    type_query(g, "vendor")
    assert g.eval("ITEM_SCANS") == 0
    assert sorted(p.result.vendor.id for p in pins(g)) == [1, 1, 2, 4, 5]


def test_npcs_friendly_only_to_the_other_faction_get_no_row(style):
    g = game(style, SELLERS + '''
UnitFactionGroup = function() return "Alliance" end
QUESTIE_NPCS[1].friendlyToFaction = "H"
QUESTIE_NPCS[2].friendlyToFaction = "AH"
QUESTIE_NPCS[4].friendlyToFaction = "A"
''')
    type_query(g, "vendor")
    assert sorted(p.result.vendor.id for p in pins(g)) == [2, 4, 5]


def test_map_search_index_is_kept_for_the_session_until_purged_and_rebuilt_by_the_next_search(style):
    g = game(style)
    g.fire("PLAYER_LOGIN")  # the harness does not send it; it starts the map's own timer
    type_query(g, "General Goods")
    assert g.eval("NS.vendorMap._state()")[2], "the typed search built the index"
    g.run("WorldMapFrame:Hide()")
    g.advance(3600)
    assert g.eval("NS.vendorMap._state()")[2], "kept long after the map closed"
    g.eval("NS.vendorMap.purge")()
    assert not any(g.eval("NS.vendorMap._state()")), "purge drops it"
    g.run("WorldMapFrame:Show()")
    g.advance(2)
    type_query(g, "General Goods")
    assert g.eval("NS.vendorMap._state()")[2] and pins(g), "the next search rebuilds it"


if __name__ == "__main__":
    failed = total = 0
    for name, test in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in ("modern", "classic"):
            total += 1
            try:
                test(style)
                print("ok", name, style)
            except Exception as error:
                failed += 1
                print("FAIL", name, style, type(error).__name__, str(error)[:300])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))

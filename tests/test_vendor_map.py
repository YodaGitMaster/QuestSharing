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
    button.scripts.OnClick(button)
    assert "Closest" in " ".join(labels(g))
    assert button.label.text == "Waypoint"
    assert g.eval("WAYPOINT") is None
    button.scripts.OnClick(button)
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
    assert g.eval("NPC_ENUMERATIONS") == 2
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
    type_query(g, "general vendor")
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


def test_libquestiedb_only_provider_is_supported(style):
    g = game(style, "LibQuestieDB.Npc=NpcDB; LibQuestieDB.Item=ItemDB; "
             "QuestDB=nil; NpcDB=nil; ItemDB=nil; Questie=nil; QuestieLoader=nil")
    type_query(g, "vendor")
    assert len(pins(g)) >= 3
    assert "requires QuestieDB" not in " ".join(labels(g))


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

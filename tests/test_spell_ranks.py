"""Real Lua spell-rank updates: learned ranks, normal bar pages and guarded cursor swaps."""
import sys
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parent))
from harness import Game
STYLES=("modern","classic")
DATA=r'''
BOOK_READS,PICKUPS,PLACEMENTS,CLEARS=0,0,{},0
MAX_ACTION_BUTTONS=180
SPELL_DATA={
 [101]={name="Healing Touch",rank="Rank 1"},[102]={name="Healing Touch",rank="Rank 2"},
 [103]={name="Healing Touch",rank="Rank 10"},[201]={name="Wrath",rank="Rang 1"},
 [202]={name="Wrath",rank="Rang 2"},[203]={name="Wrath",rank="Rang 3",future=true},
 [301]={name="Passive",rank="Rank 5",passive=true},[401]={name="Attack",rank=""},
 [501]={name="Healing Touch",rank="Rank 10"},
}
SPELL_BOOK={102,101,103,201,202,203,301,401}
ACTION_SLOTS={
 [1]={"spell",101},[2]={"spell",102},[3]={"spell",103},[4]={"macro",42},
 [5]={"item",55},[6]={"spell",101,"pet"},[7]={"spell",401},[8]={"spell",999},
 [73]={"spell",201},[145]={"spell",101},
}
function GetActionInfo(slot) local t=ACTION_SLOTS[slot];if t then return unpack(t)end end
function GetCursorInfo() if CURSOR then return unpack(CURSOR)end end
function ClearCursor() CLEARS=CLEARS+1;CURSOR=nil;FIRE("CURSOR_CHANGED")end
function Pick(id)
 assert(not IN_COMBAT,"must not change bars in combat")
 PICKUPS=PICKUPS+1
 local index
 for i,n in ipairs(SPELL_BOOK)do if n==id then index=i end end
 CURSOR={"spell",index or 999,"spell",id};FIRE("CURSOR_CHANGED")
end
function PlaceAction(slot)
 assert(not IN_COMBAT,"must not place in combat")
 assert(CURSOR and CURSOR[1]=="spell")
 local id=CURSOR[4];local old=ACTION_SLOTS[slot]
 ACTION_SLOTS[slot]={"spell",id};PLACEMENTS[#PLACEMENTS+1]={slot,id}
 CURSOR=old and {"spell",999,"spell",old[2]} or nil
 FIRE("ACTIONBAR_SLOT_CHANGED",slot);FIRE("CURSOR_CHANGED")
end
function GetSpellInfo(id)local t=SPELL_DATA[id];if t then return t.name,t.rank end end
'''
LEGACY=r'''
function GetNumSpellTabs()BOOK_READS=BOOK_READS+1;return 2 end
function GetSpellTabInfo(i)if i==1 then return "Restoration",nil,0,3,false,0 else return "Balance",nil,3,#SPELL_BOOK-3,false,0 end end
function GetSpellBookItemInfo(i,bank)
 assert(bank=="spell");local id=SPELL_BOOK[i];local t=SPELL_DATA[id]
 return t.future and "FUTURESPELL" or "SPELL",id
end
function GetSpellBookItemName(i,bank)local t=SPELL_DATA[SPELL_BOOK[i]];return t.name,t.rank end
function IsPassiveSpell(i,bank)return SPELL_DATA[SPELL_BOOK[i]].passive end
function PickupSpell(id)Pick(id)end
function PickupSpellBookItem(i,bank)assert(bank=="spell");Pick(SPELL_BOOK[i])end
'''
MODERN=r'''
Enum=Enum or {};Enum.SpellBookSpellBank={Player=0,Pet=1};Enum.SpellBookItemType={Spell=1,FutureSpell=2,Flyout=4}
C_SpellBook={
 GetNumSpellBookSkillLines=function()BOOK_READS=BOOK_READS+1;return 2 end,
 GetSpellBookSkillLineInfo=function(i)return {itemIndexOffset=i==1 and 0 or 3,numSpellBookItems=i==1 and 3 or #SPELL_BOOK-3}end,
 GetSpellBookItemInfo=function(i,bank)
  assert(bank==0);local id=SPELL_BOOK[i];local t=SPELL_DATA[id]
  return {name=t.name,subName=t.rank,spellID=id,actionID=id,itemType=t.future and 2 or 1,isPassive=t.passive,isOffSpec=t.offspec}
 end,
 PickupSpellBookItem=function(i,bank)assert(bank==0);Pick(SPELL_BOOK[i])end,
}
C_Spell={
 PickupSpell=Pick,
 GetSpellInfo=function(id)local t=SPELL_DATA[id];if t then return {name=t.name}end end,
 GetSpellSubtext=function(id)local t=SPELL_DATA[id];return t and t.rank end,
}
GetSpellInfo=nil
'''


def game(style,extra="",enabled=False):
    g=Game(style,DATA+(MODERN if style=="modern" else LEGACY)+extra,fresh=True)
    if enabled:g.run('QuestSharingDB={autoSpellRanks=true,dbVersion=3}')
    g.start();g.advance(1)
    return g


def enable(g):
    g.eval("NS.setSetting")("autoSpellRanks",True);g.advance(.6)


def test_opt_in_default_and_settings_window_layout(style):
    g=game(style)
    assert not g.eval("NS.db.autoSpellRanks") and g.eval("BOOK_READS")==g.eval("PICKUPS")==0
    g.slash("settings");g.eval("NS.settingsTab")("optional")
    w=g.eval("NS._settingsWindow()")
    assert w.bottom<w.win.height-30
    g.run('for i,r in ipairs(NS.settingRows)do if r.key=="autoSpellRanks"then NS.settingsClick(i,"LeftButton")end end')
    g.advance(.6);assert g.eval("ACTION_SLOTS[1][2]")==103


def test_highest_numeric_learned_rank_updates_every_bar_copy_and_hidden_pages(style):
    g=game(style);enable(g)
    for slot in (1,2,145):assert g.eval(f"ACTION_SLOTS[{slot}][2]")==103
    assert g.eval("ACTION_SLOTS[73][2]")==202 # future rank 3 is not learned
    assert g.eval("#PLACEMENTS")==4 and g.eval("CURSOR")==None
    assert g.eval("NS.spellRanks.update")(True)==0 and g.eval("#PLACEMENTS")==4


def test_preserves_macros_items_empty_pet_unranked_unknown_and_already_max(style):
    g=game(style);enable(g)
    for slot,kind,id in ((3,"spell",103),(4,"macro",42),(5,"item",55),(6,"spell",101),(7,"spell",401),(8,"spell",999)):
        assert (g.eval(f"ACTION_SLOTS[{slot}][1]"),g.eval(f"ACTION_SLOTS[{slot}][2]"))==(kind,id)
    assert g.eval("ACTION_SLOTS[9]")==None


def test_login_saved_choice_and_learning_events_refresh_without_duplicate_work(style):
    g=game(style,enabled=True);assert g.eval("ACTION_SLOTS[1][2]")==103
    g.run('SPELL_DATA[104]={name="Healing Touch",rank="Rank 11"};table.insert(SPELL_BOOK,104)')
    for event in ("SPELLS_CHANGED","LEARNED_SPELL_IN_TAB","LEARNED_SPELL_IN_SKILL_LINE"):g.fire(event,104)
    before=g.eval("BOOK_READS");g.advance(.6)
    assert g.eval("ACTION_SLOTS[1][2]")==104 and g.eval("BOOK_READS")==before+1
    count=g.eval("#PLACEMENTS");g.advance(2);assert g.eval("#PLACEMENTS")==count


def test_combat_and_cursor_defer_then_retry_without_disturbing_drag(style):
    g=game(style,'IN_COMBAT=true;CURSOR={"item",77}');enable(g)
    assert g.eval("PICKUPS")==g.eval("CLEARS")==0 and g.eval("CURSOR[2]")==77
    g.run("IN_COMBAT=false");g.fire("PLAYER_REGEN_ENABLED");g.advance(.6)
    assert g.eval("PICKUPS")==0 and g.eval("CURSOR[2]")==77
    g.run("CURSOR=nil");g.fire("CURSOR_CHANGED");g.advance(.6)
    assert g.eval("ACTION_SLOTS[1][2]")==103


def test_vehicle_and_override_bars_wait_for_normal_action_bars(style):
    g=game(style,'TEMP=true;function HasVehicleActionBar()return TEMP end');enable(g)
    assert g.eval("PICKUPS")==0
    g.run("TEMP=false");g.fire("UPDATE_VEHICLE_ACTIONBAR");g.advance(.6)
    assert g.eval("ACTION_SLOTS[1][2]")==103


def test_disabling_master_or_option_and_reset_cancel_queued_changes(style):
    for key in ("enabled","autoSpellRanks"):
        g=game(style);g.eval("NS.setSetting")("autoSpellRanks",True);g.eval("NS.setSetting")(key,False);g.advance(1)
        assert g.eval("PICKUPS")==0
    g=game(style);g.eval("NS.setSetting")("autoSpellRanks",True);g.eval("NS.resetSettings")();g.advance(1)
    assert not g.eval("NS.db.autoSpellRanks") and g.eval("PICKUPS")==0


def test_replacing_manually_placed_lower_rank_and_not_downgrading_unknown_higher_rank(style):
    g=game(style);enable(g)
    g.run('ACTION_SLOTS[2]={"spell",101};SPELL_DATA[105]={name="Healing Touch",rank="Rank 20"};ACTION_SLOTS[3]={"spell",105}')
    g.fire("ACTIONBAR_SLOT_CHANGED",2);g.advance(.6)
    assert g.eval("ACTION_SLOTS[2][2]")==103 and g.eval("ACTION_SLOTS[3][2]")==105


def test_collapsed_book_and_localized_ranks_compare_existing_spell_id_metadata(style):
    g=game(style,'SPELL_BOOK={103,401,301,202};SPELL_DATA[103].rank="Rang 10"');enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==103 and g.eval("ACTION_SLOTS[73][2]")==202


def test_ambiguous_highest_rank_is_not_picked_arbitrarily(style):
    g=game(style,'table.insert(SPELL_BOOK,501)');enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==101 and g.eval("ACTION_SLOTS[73][2]")==202


def test_passive_and_future_ranks_are_not_used(style):
    g=game(style,'SPELL_DATA[103].passive=true;SPELL_DATA[202].future=true');enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==102 and g.eval("ACTION_SLOTS[73][2]")==201


def test_missing_api_explains_and_never_changes_any_slot(style):
    g=game(style,'GetActionInfo=nil');enable(g)
    assert g.eval("PICKUPS")==0 and "APIs" in g.eval("NS.spellRanks.status()")


def test_pickup_refusal_pauses_once_and_preserves_original_slots(style):
    extra='C_Spell.PickupSpell=function()error("blocked")end' if style=="modern" else 'PickupSpell=function()error("blocked")end'
    g=game(style,extra);enable(g)
    assert g.eval("NS.isBlocked")("spellRanks") and g.eval("#PLACEMENTS")==0 and g.eval("ACTION_SLOTS[1][2]")==101
    count=len(g.printed());g.fire("SPELLS_CHANGED");g.advance(1)
    assert len(g.printed())==count


def test_noop_placement_and_wrong_pickup_do_not_delete_original_action(style):
    for extra in ('PlaceAction=function()end', 'Pick=function()CURSOR={"spell",7,"spell",301}end'):
        # Rebind the public pickup so both APIs use the fault-injected implementation.
        if extra.startswith('Pick='):
            extra+=';'+('C_Spell.PickupSpell=Pick' if style=="modern" else 'PickupSpell=Pick')
        g=game(style,extra);enable(g)
        assert g.eval("ACTION_SLOTS[1][2]")==101 and g.eval("NS.isBlocked")("spellRanks")
        assert g.eval("CURSOR")==None


def test_book_slot_pickup_fallback_works_without_spell_id_pickup(style):
    extra='C_Spell.PickupSpell=nil' if style=="modern" else 'PickupSpell=nil'
    g=game(style,extra);enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==103 and g.eval("CURSOR")==None


def test_unreadable_cursor_prevents_any_pickup(style):
    g=game(style,'CURSOR={"item",77};GetCursorInfo=function()error("unavailable")end');enable(g)
    assert g.eval("PICKUPS")==0 and g.eval("CURSOR[2]")==77


def test_client_block_event_pauses_automatic_retries(style):
    g=game(style,'PlaceAction=function()FIRE("ADDON_ACTION_BLOCKED","QuestSharing","PlaceAction")end');enable(g)
    assert g.eval("NS.isBlocked")("spellRanks") and g.eval("ACTION_SLOTS[1][2]")==101


def test_active_zero_spec_ids_are_not_treated_as_other_specializations(style):
    extra='local old=C_SpellBook.GetSpellBookSkillLineInfo;C_SpellBook.GetSpellBookSkillLineInfo=function(i)local t=old(i);t.offSpecID=0;return t end' if style=="modern" else ''
    g=game(style,extra);enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==103


def test_offspec_skill_lines_and_entries_are_excluded(style):
    if style=="modern":
        extra='local old=C_SpellBook.GetSpellBookSkillLineInfo;C_SpellBook.GetSpellBookSkillLineInfo=function(i)local t=old(i);if i==1 then t.offSpecID=71 end;return t end'
    else:
        extra='GetSpellTabInfo=function(i)if i==1 then return "Other spec",nil,0,3,false,71 else return "Balance",nil,3,#SPELL_BOOK-3,false,0 end end'
    g=game(style,extra);enable(g)
    assert g.eval("ACTION_SLOTS[1][2]")==101 and g.eval("ACTION_SLOTS[73][2]")==202


def test_combat_start_during_pickup_stops_before_placement_and_retries_after_combat(style):
    rebind='C_Spell.PickupSpell=StartCombat' if style=="modern" else 'PickupSpell=StartCombat'
    g=game(style,'FIRST=true;function StartCombat(id)Pick(id);if FIRST then FIRST=false;IN_COMBAT=true end end;'+rebind)
    enable(g)
    assert g.eval("#PLACEMENTS")==0 and g.eval("ACTION_SLOTS[1][2]")==101 and g.eval("CURSOR")==None
    g.run('IN_COMBAT=false');g.fire('PLAYER_REGEN_ENABLED');g.advance(.6)
    assert g.eval("ACTION_SLOTS[1][2]")==103


def test_partial_placement_failure_preserves_cursor_for_manual_recovery(style):
    g=game(style,'PlaceAction=function(slot)ACTION_SLOTS[slot]={"macro",99};CURSOR={"spell",999,"spell",101}end');enable(g)
    assert g.eval("NS.isBlocked")("spellRanks")
    assert g.eval("CURSOR[4]")==101 and g.eval("ACTION_SLOTS[2][2]")==102


def test_manual_check_cancels_duplicate_debounced_scan_and_reports_status(style):
    g=game(style);g.eval("NS.setSetting")("autoSpellRanks",True)
    assert g.eval("NS.spellRanks.update")(True)==4
    reads=g.eval("BOOK_READS");g.advance(.6)
    assert g.eval("BOOK_READS")==reads
    assert "Updated 4 spell buttons" in '\n'.join(g.printed())


def test_page_count_does_not_limit_hidden_or_form_slots(style):
    g=game(style,'MAX_ACTION_BUTTONS=nil;NUM_ACTIONBAR_BUTTONS=12;NUM_ACTIONBAR_PAGES=6');enable(g)
    assert g.eval("ACTION_SLOTS[145][2]")==103 and g.eval("ACTION_SLOTS[73][2]")==202


def test_slot_changed_by_another_addon_during_pickup_is_preserved(style):
    rebind='C_Spell.PickupSpell=Intercept' if style=="modern" else 'PickupSpell=Intercept'
    g=game(style,'function Intercept(id)Pick(id);ACTION_SLOTS[1]={"macro",42}end;'+rebind);enable(g)
    assert (g.eval("ACTION_SLOTS[1][1]"),g.eval("ACTION_SLOTS[1][2]"))==("macro",42)
    assert not any(entry[1]==1 for entry in g.eval("PLACEMENTS").values())


if __name__=="__main__":
    total=failed=0
    for name,fn in sorted(list(globals().items())):
        if not name.startswith("test_"):continue
        for style in STYLES:
            total+=1
            try:fn(style);print("ok",name,style)
            except Exception as e:failed+=1;print("FAIL",name,style,type(e).__name__,str(e)[:700])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))

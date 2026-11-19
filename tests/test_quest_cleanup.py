"""Destructive bag cleanup: conservative candidates, fresh checks and explicit per-stack confirmation."""
import inspect
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game

STYLES = ("modern", "classic")
DATA = r'''
NUM_BAG_SLOTS=4
DBQ={}; DBI={}; DELETED={}; PICKUPS=0; CLEAN_CURSOR=nil; ITEM_READS=0
for _,q in ipairs(QUESTS) do if q.id then DBQ[q.id]={name=q.title} end end
DBQ[100].objectives={nil,nil,{{400}}}
DBQ[200].sourceItemId=401
DBQ[101].requiredSourceItems={402}
QuestDB={Get=function(id,key) return DBQ[id] and DBQ[id][key] end}
ItemDB={Get=function(id,key) ITEM_READS=ITEM_READS+1;return DBI[id] and DBI[id][key] end}
NpcDB={Get=function()end}; ObjectDB={Get=function()end}
local function put(bag,slot,id,extra)
 BAGS[bag]=BAGS[bag] or {}; ITEMS[id]={name="Quest item "..id}
 DBI[id]={name=ITEMS[id].name,class=12}
 local it={id=id,count=3,link="|Hitem:"..id.."|h[Quest item]|h",isQuestItem=false}
 for k,v in pairs(extra or {}) do it[k]=v end
 BAGS[bag][slot]=it
end
PUT=put
put(0,1,300) -- leftover
put(0,2,400) -- active objective
put(0,3,401) -- active source, different zone
put(0,4,402) -- completed quest still in log
put(0,5,403);DBI[403].relatedQuests={100} -- reverse relation
put(0,6,404);DBI[404].startQuest=900 -- unaccepted starter
put(0,7,405,{questID=901}) -- native starter
put(0,8,406,{isActive=true}) -- native active item
put(0,9,407);DBI[407].class=7 -- ordinary material
put(0,10,408,{locked=true})
put(0,11,409);DBI[409]=nil -- unknown item
put(0,12,410);ITEMS[410].name="Wolf Pelt" -- active objective text
put(1,1,301,{count=1}) -- second leftover in equipped bag
put(-1,1,302) -- bank excluded
put(5,1,303) -- bank bag on Classic, excluded
local function info(bag,slot)
 local it=BAGS[bag] and BAGS[bag][slot]
 return it and {itemID=it.id,stackCount=it.count,isLocked=it.locked,hyperlink=it.link}
end
local function quest(bag,slot)
 local it=BAGS[bag] and BAGS[bag][slot]
 return it and {isQuestItem=it.isQuestItem,questID=it.questID,isActive=it.isActive or false}
end
local function pickup(bag,slot)
 PICKUPS=PICKUPS+1
 local it=BAGS[bag][slot]; BAGS[bag][slot]=nil
 CLEAN_CURSOR={kind="item",id=it.id,link=it.link,item=it,bag=bag,slot=slot}
end
CLEAN_INFO,CLEAN_QUEST,CLEAN_PICKUP=info,quest,pickup
C_Container.GetContainerItemInfo=info
C_Container.GetContainerItemQuestInfo=quest
C_Container.GetContainerItemLink=function(bag,slot) local i=info(bag,slot);return i and i.hyperlink end
C_Container.GetContainerNumSlots=function(bag) return bag==0 and 12 or 1 end
C_Container.PickupContainerItem=pickup
function GetCursorInfo() if CLEAN_CURSOR then return CLEAN_CURSOR.kind,CLEAN_CURSOR.id,CLEAN_CURSOR.link end end
function DeleteCursorItem() DELETED[#DELETED+1]=CLEAN_CURSOR.item;CLEAN_CURSOR=nil end
function ClearCursor()
 if CLEAN_CURSOR and CLEAN_CURSOR.item then BAGS[CLEAN_CURSOR.bag][CLEAN_CURSOR.slot]=CLEAN_CURSOR.item end
 CLEAN_CURSOR=nil
end
'''
LEGACY = r'''
GetContainerItemInfo=function(bag,slot) local i=CLEAN_INFO(bag,slot);if i then return "icon",i.stackCount,i.isLocked end end
GetContainerItemID=function(bag,slot) local i=CLEAN_INFO(bag,slot);return i and i.itemID end
GetContainerItemLink=C_Container.GetContainerItemLink
GetContainerNumSlots=C_Container.GetContainerNumSlots
PickupContainerItem=CLEAN_PICKUP
GetContainerItemQuestInfo=function(bag,slot) local q=CLEAN_QUEST(bag,slot);if q then return q.isQuestItem,q.questID,q.isActive end end
C_Container=nil
'''


def game(style, extra=""):
    g = Game(style, DATA + (LEGACY if style == "classic" else "") + extra)
    g.start()
    return g


def ids(g):
    return [r.id for r in g.eval("NS.questCleanup._results()").values()]


def review(g):
    g.slash("cleanup")
    g.run("CHOSEN=NS.questCleanup._results()[1]; NS.questCleanup.review(CHOSEN)")


def test_protect_active_sources_objectives_completed_quests_starters_and_unknown_items(style):
    g = game(style)
    g.slash("cleanup")
    assert ids(g) == [300, 301], ids(g)
    assert g.eval("#DELETED") == 0


def test_no_cleanup_item_reads_or_window_at_login_or_closed_events(style):
    g = game(style)
    assert g.eval("ITEM_READS") == 0
    for event in ("BAG_UPDATE", "QUEST_LOG_UPDATE", "PLAYER_ENTERING_WORLD"):
        g.fire(event)
    assert g.eval("ITEM_READS") == 0
    assert g.eval("NS.questCleanup._window()") is None


def test_review_and_cancel_do_not_pick_up_or_delete_items(style):
    g = game(style)
    review(g)
    assert g.eval("NS.questCleanup._window().confirm.shown")
    g.eval("NS.questCleanup.cancel")()
    assert not g.eval("NS.questCleanup._window().confirm.shown")
    assert not g.eval("NS.questCleanup.confirm")()
    assert g.eval("PICKUPS") == 0


def test_confirm_deletes_only_reviewed_stack_and_rescans(style):
    g = game(style)
    review(g)
    assert g.eval("NS.questCleanup.confirm")()
    assert g.eval("#DELETED") == 1
    assert g.eval("DELETED[1].id") == 300
    assert g.eval("DELETED[1].count") == 3
    assert ids(g) == [301]
    assert g.eval("BAGS[0][2].id") == 400


def test_changed_slot_id_stack_count_or_link_cannot_be_deleted(style):
    for change in ("BAGS[0][1]=BAGS[0][2]", "BAGS[0][1].count=4", "BAGS[0][1].link='changed'"):
        g = game(style)
        review(g)
        g.run(change)
        assert not g.eval("NS.questCleanup.confirm")(), change
        assert g.eval("PICKUPS") == 0


def test_new_active_quest_relation_is_rechecked_without_waiting_for_event(style):
    for change in ("DBQ[100].sourceItemId=300", "DBI[300].relatedQuests={100}", "DBI[300].startQuest=900",
                   "BAGS[0][1].isActive=true", "BAGS[0][1].locked=true"):
        g = game(style)
        review(g)
        g.run(change)
        assert not g.eval("NS.questCleanup.confirm")(), change
        assert g.eval("#DELETED") == 0


def test_events_invalidate_confirmation_without_rescanning(style):
    for event in ("BAG_UPDATE", "BAG_UPDATE_DELAYED", "QUEST_LOG_UPDATE", "QUEST_ACCEPTED", "QUEST_REMOVED", "PLAYER_REGEN_DISABLED"):
        g = game(style)
        review(g)
        count = g.eval("ITEM_READS")
        g.fire(event)
        assert ids(g) == []
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("ITEM_READS") == count


def test_own_deletion_bag_events_keep_the_list_but_later_changes_still_clear_it(style):
    # UX-12: the bag events the game fires after our own Delete must not empty the list.
    g = game(style)
    review(g)
    assert g.eval("NS.questCleanup.confirm")()
    assert ids(g) == [301]
    count = g.eval("ITEM_READS")
    g.fire("BAG_UPDATE", 0)
    g.fire("BAG_UPDATE_DELAYED")
    assert ids(g) == [301]
    assert "Click Refresh" not in g.eval("NS.questCleanup._window().status.text")
    assert g.eval("ITEM_READS") == count       # no background re-scan
    g.fire("BAG_UPDATE", 0)                    # an outside change after that still clears the list
    assert ids(g) == []
    assert "Refresh bags" in g.eval("NS.questCleanup._window().status.text")


def test_own_deletion_does_not_hide_other_bag_or_late_changes(style):
    g = game(style)
    review(g)
    assert g.eval("NS.questCleanup.confirm")()
    g.fire("BAG_UPDATE", 1)                    # a different bag changed: outside change
    assert ids(g) == []
    g = game(style)
    review(g)
    assert g.eval("NS.questCleanup.confirm")()
    g.advance(5)                               # the game never sent the follow-up events
    g.fire("BAG_UPDATE", 0)
    assert ids(g) == []


def test_busy_unreadable_or_unavailable_cursor_blocks_pickup(style):
    for extra in ("CLEAN_CURSOR={kind='spell',id=7}", "GetCursorInfo=function()error('blocked')end", "GetCursorInfo=nil"):
        g = game(style)
        review(g)
        g.run(extra)
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("PICKUPS") == 0


def test_pickup_failure_or_wrong_cursor_never_destroys_another_item(style):
    for extra in ("function()end", "function()CLEAN_CURSOR={kind='item',id=999}end", "function()error('blocked')end"):
        g = game(style)
        review(g)
        g.run(("C_Container.PickupContainerItem=" if style == "modern" else "PickupContainerItem=") + extra)
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("#DELETED") == 0


def test_pickup_callbacks_cannot_bypass_new_quest_combat_or_master_checks(style):
    for change in ("DBQ[100].sourceItemId=300", "IN_COMBAT=true", "NS.db.enabled=false"):
        g = game(style)
        review(g)
        api = "C_Container.PickupContainerItem" if style == "modern" else "PickupContainerItem"
        g.run(f"{api}=function(bag,slot) CLEAN_PICKUP(bag,slot); {change} end")
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("#DELETED") == 0
        assert g.eval("BAGS[0][1].id") == 300


def test_hidden_native_active_quest_relation_is_protected(style):
    g = game(style)
    g.run("C_QuestLog=C_QuestLog or {}; C_QuestLog.IsOnQuest=function(id)return id==999 end;DBI[300].relatedQuests={999}")
    g.slash("cleanup")
    assert ids(g) == [301]


def test_refused_deletion_returns_item_and_explains_manual_fallback(style):
    for extra in ("DeleteCursorItem=function()error('protected')end", "DeleteCursorItem=function()end"):
        g = game(style)
        review(g)
        g.run(extra)
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("BAGS[0][1].id") == 300
        assert g.eval("CLEAN_CURSOR") is None
        assert "manually" in g.eval("NS.questCleanup._window().status.text")


def test_combat_master_disable_and_missing_data_stop_cleanup(style):
    for extra in ("IN_COMBAT=true", "NS.db.enabled=false", "QuestDB=nil", "DBQ[100]=nil"):
        g = game(style)
        review(g)
        g.run(extra)
        assert not g.eval("NS.questCleanup.confirm")()
        assert g.eval("PICKUPS") == 0
        g.eval("NS.questCleanup.refresh")()
        assert ids(g) == []


def test_special_quest_items_are_protected(style):
    g = game(style, "SPECIAL[2]=300")
    g.slash("cleanup")
    assert 300 not in ids(g)


def test_native_flag_identifies_nonstandard_quest_class_and_missing_metadata_skips(style):
    g = game(style, "DBI[300].class=7;BAGS[0][1].isQuestItem=true;BAGS[1][1].count=nil")
    g.slash("cleanup")
    assert ids(g) == [300]


def test_missing_native_quest_api_or_uncached_name_skips_items(style):
    extra = "C_Container.GetContainerItemQuestInfo=nil" if style == "modern" else "GetContainerItemQuestInfo=nil"
    g = game(style, extra)
    g.slash("cleanup")
    assert ids(g) == []
    g = game(style, "ITEMS[300].name=nil")
    g.slash("cleanup")
    assert ids(g) == [301]


def test_paging_and_settings_entry_reach_review_window(style):
    g = game(style, "for slot=1,12 do PUT(0,slot,500+slot) end")
    g.slash("cleanup")
    assert g.eval("NS.questCleanup._window().rows[1].item.id") == 501
    g.run("local w=NS.questCleanup._window();w.next.scripts.OnClick(w.next,'LeftButton')")
    assert g.eval("NS.questCleanup._window().rows[1].item.id") == 507
    g.run("NS.questCleanup._window():Hide(); for i,r in ipairs(NS.settingRows) do if r.button=='Review items' then NS.settingsClick(i,'LeftButton') end end")
    assert g.eval("NS.questCleanup._window().shown")


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"):
            continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total += 1
            try:
                fn(style) if style else fn()
                print("ok", name, style)
            except Exception as error:
                failed += 1
                print("FAIL", name, style, type(error).__name__, str(error)[:500])
    print(f"{total-failed}/{total} passed")
    raise SystemExit(bool(failed))

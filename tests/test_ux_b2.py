"""UX review 2026-11-19, batch B2 (Quest guide): IDs and names, settings button, chat feedback, time limit,
empty zone, camp busy, report wording, one name for the guide and its goals."""
import pathlib
import sys

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game  # noqa: E402
from test_quest_planner_ui import DATA  # noqa: E402
from test_quest_planner_zone_steps import WESTFALL, BUSY_CAMPS, TWO_CAMPS, game, rows, objective_waypoint, near  # noqa: E402


def button(g, label):
    panel = g.eval("QuestSharingPlannerPanel")
    return next(c for c in panel.children.values() if c.text == label and c.scripts.OnClick)


def said(g):
    return "\n".join(str(m) for m in g.printed())


def hover(g, frame):
    frame.scripts.OnEnter(frame)
    lines = g.eval("TOOLTIP.lines")
    return str(g.eval("TOOLTIP.text")) + "\n" + "\n".join(str(lines[i]) for i in range(1, len(lines) + 1))


def report_text(g):
    return g.eval("NS.questPlanner.reportText")()


# UX-02: the guide row tooltip shows each quest's ID, and quest names work like IDs.
def test_row_tooltip_shows_the_quest_id(style):
    g = game(style)
    tip = hover(g, rows(g)[0])
    assert "Local Harvest" in tip and "Quest ID 9000" in tip, tip


def test_chosen_quests_accepts_quest_names_in_the_command(style):
    g = game(style)
    g.slash("plan selected Local Harvest"); g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "selected"
    assert g.eval("NS.db.questPlannerGoal") == "selected"
    assert "enter quest" not in said(g).lower()
    assert "Local Harvest (9000)" in said(g), said(g)


def test_chosen_quests_accepts_names_and_ids_in_the_saved_setting(style):
    g = game(style)
    g.run('NS.db.questPlannerSelected = "local harvest, 9001"; NS.db.questPlannerGoal = "selected"')
    assert g.eval("NS.questPlanner.applySettings")() is True
    g.advance(5)
    assert g.eval("NS.questPlanner.report")().mode == "selected"
    assert "Local Harvest" in "\n".join(r.detail.text for r in rows(g))


def test_unknown_quest_name_is_named_in_the_reply(style):
    g = game(style)
    g.slash("plan selected Nothing Like This"); g.advance(5)
    assert "Nothing Like This" in said(g) or "nothing like this" in said(g), said(g)


# UX-09: the "..." button opens Settings > Quest guide.
def test_settings_button_opens_the_quest_guide_tab(style):
    g = game(style)
    b = button(g, "...")
    b.scripts.OnClick(b)
    assert g.eval("NS._settingsWindow().tab") == "guide"


# UX-13: every goal change prints one line; the Plan tooltip shows the goal; unknown words list the commands.
def test_goal_and_scope_commands_confirm_in_chat(style):
    g = game(style)
    g.slash("plan xp"); g.advance(5)
    assert "Quest guide: Quest XP/hour" in said(g), said(g)
    g.slash("plan all"); g.advance(5)
    assert "Quest guide: Complete zone" in said(g), said(g)
    g.slash("plan range"); g.advance(5)
    assert "Green and yellow only" in said(g), said(g)
    g.slash("plan unrestricted"); g.advance(5)
    assert "Every level" in said(g), said(g)


def test_plan_button_tooltip_shows_the_active_goal(style):
    g = game(style)
    g.slash("plan xp"); g.advance(5)
    tip = hover(g, button(g, "Plan"))
    assert "Quest XP/hour" in tip and "Every level" in tip, tip


def test_unknown_plan_word_lists_the_commands(style):
    g = game(style)
    g.slash("plan bogus")
    out = said(g)
    assert "bogus" in out and "/qs plan xp" in out and "/qs plan busy" in out, out


def test_next_on_the_last_step_says_so(style):
    g = game(style)
    g.slash("plan next"); g.slash("plan next")
    assert "last step" not in said(g)
    g.slash("plan next")
    assert "this is the last step" in said(g), said(g)


# UX-14: one range (5-240) and the value used is confirmed.
def test_time_limit_command_uses_the_settings_range_and_confirms(style):
    g = game(style)
    g.slash("plan budget 600"); g.advance(5)
    assert g.eval("NS.db.questPlannerBudget") == 240
    assert g.eval("NS.questPlanner.report")().mode == "budget"
    assert "Time limit 240 min" in said(g), said(g)
    g.slash("plan budget 2"); g.advance(5)
    assert g.eval("NS.db.questPlannerBudget") == 5
    assert "Time limit 5 min" in said(g), said(g)
    g.slash("plan budget soon")
    assert "from 5 to 240 minutes" in said(g), said(g)


def test_saved_time_limit_is_read_with_the_same_range(style):
    g = game(style)
    g.run('NS.db.questPlannerBudget = 600; NS.db.questPlannerGoal = "budget"')
    g.eval("NS.questPlanner.applySettings")(); g.advance(5)
    assert "budget seconds=14400" in g.eval("NS.questPlanner.debugText")()


def done_quest(quest_id):
    """The quest counts as turned in, on both clients (Classic has no C_QuestLog; Questie's own record is used)."""
    return ("if C_QuestLog then C_QuestLog.IsQuestFlaggedCompleted=function(id) return id==%d end "
            "else Questie={db={char={complete={[%d]=true}}}} end" % (quest_id, quest_id))


# UX-20: a finished zone and an unplannable zone say different things.
def test_finished_zone_says_every_quest_is_done(style):
    g = game(style, done_quest(9000) + "\nQUESTS={}")
    out = empty_text(g)
    assert rows(g) == []
    assert "You have done every quest the guide knows in Westfall." in out, out


def test_unplannable_zone_points_to_the_report(style):
    g = game(style, "QUESTIE_QUESTS[9000].exclusiveTo={9050}\n"
             + done_quest(9050) + "\nQUESTS={}")
    assert rows(g) == []
    out = empty_text(g)
    assert "Show report" in out and "No active or ready quests" not in out, out


def empty_text(g):
    from test_quest_planner_ui import planner_rows
    _, _, content, _ = planner_rows(g)
    return "\n".join(str(content.children[i].text) for i in range(1, len(content.children) + 1)
                     if getattr(content.children[i], "isFontString", False))


# UX-21: "/qs plan busy" and a Busy button, with a chat line and a note on the row.
def test_plan_busy_command_marks_the_camp_and_names_the_next_one(style):
    g = game(style, TWO_CAMPS)
    assert near(objective_waypoint(g), 0.30, 0.30)
    g.slash("plan busy"); g.advance(5)
    assert near(objective_waypoint(g), 0.80, 0.80), objective_waypoint(g)
    out = said(g)
    assert "Quest guide: Harvest Watcher camp marked busy for 5 min" in out, out
    assert "next free camp 80.0, 80.0" in out, out
    detail = next(r.detail.text for r in rows(g) if "Complete these quests here" in r.detail.text)
    assert "busy" in detail.lower(), detail


def test_busy_button_shows_on_objective_steps_only(style):
    g = game(style, TWO_CAMPS)
    b = button(g, "Busy")
    first = rows(g)[0]
    assert ("Complete these quests here" in first.detail.text) == bool(b.shown)
    objective_waypoint(g)
    assert b.shown
    b.scripts.OnClick(b); g.advance(5)
    assert near(objective_waypoint(g), 0.80, 0.80), objective_waypoint(g)


def test_plan_busy_without_an_objective_step_explains(style):
    g = game(style)
    g.slash("plan busy")
    assert "select a kill or collect step" in said(g), said(g)


# UX-26: plain report wording with quest names.
REPORT_DATA = DATA + "\nC_Map.GetMapWorldSize=nil"


def report_game(style):
    g = Game(style, REPORT_DATA, fresh=True)
    g.start()
    g.run("NS.db.questPlannerScope = 'green-yellow'")
    g.eval("NS.setSetting")("questPlanner", True)
    g.advance(5)
    return g


def test_report_uses_quest_names_and_plain_words(style):
    g = report_game(style)
    text = report_text(g)
    assert "Green Quest (8100)" in text, text
    for jargon in ("bounded search", "nearest-first", "illustrative", "Not read", "one cheap check",
                   "0.0 kills", "unfinished, excluded", "Quest 8100"):
        assert jargon not in text, (jargon, text)
    assert "Travel times are rough guesses: this map's size is unknown." in text, text
    assert text.count("(8100)") == 1, text
    assert "scale=estimated 3000x2000" in g.eval("NS.questPlanner.debugText")()


def test_unknown_plan_word_lists_on_and_close(style):
    g = game(style)
    g.slash("plan nonsense")
    out = said(g)
    assert "/qs plan on," in out and "close" in out, out


# UX-27: one name, "Quest guide".
def test_the_guide_is_called_quest_guide_everywhere(style):
    g = game(style)
    assert "QUEST GUIDE" in g.eval("QuestSharingPlannerPanel.title.text")
    g.slash("plan on")
    assert "quest planner" not in said(g).lower()
    g.eval("NS.questPlanner.settingChanged")(False)
    assert "Quest guide is off." in empty_text(g)
    g.run("C_Map.IsCityMap=function() return true end")
    g.eval("NS.questPlanner.settingChanged")(True); g.advance(3)
    out = empty_text(g)
    assert "The Quest guide only works in outdoor zones" in out and "planner" not in out, out


# UX-28: Settings names in the report and in chat.
def test_report_and_chat_use_the_settings_goal_names(style):
    g = game(style)
    first = report_text(g).split("\n")[0]
    assert first == "Complete zone • Every level", first
    g.slash("plan selected")
    assert "Chosen quests" in said(g) and "Selected quests" not in said(g), said(g)
    assert g.eval("NS.questPlanner.goalNames").selected == "Chosen quests"
    assert g.eval("NS.questPlanner.scopeNames")["green-yellow"] == "Green and yellow only"



# ---- low findings (UX-47, UX-51, UX-59, UX-60, UX-61) ------------------------------------------------------------------
def click_row(g, row, which):
    g.eval("function(r, b) r.scripts.OnClick(r, b) end")(row, which)


# UX-47: one click action on a guide step, the same in and out of combat, and the tooltip says so.
def test_step_tooltip_names_one_click_action(style):
    g = game(style)
    tip = hover(g, rows(g)[0])
    assert "Click: set a waypoint here." in tip, tip
    assert "Right-click" not in tip and "Left-click" not in tip, tip


def test_step_click_sets_the_waypoint_in_combat_too(style):
    g = game(style)
    g.run("IN_COMBAT = true")
    click_row(g, rows(g)[0], "LeftButton")
    assert g.eval("WAYPOINT") is not None
    assert "after combat" not in said(g), said(g)


# UX-51: the guide says what is wrong with Questie and how to check it.
def guide_message(g):
    return empty_text(g)


def test_guide_without_questie_says_install_and_check(style):
    g = Game(style, DATA + "\nQuestDB=nil; QuestieLoader=nil; Questie=nil", fresh=True)
    g.start(); g.eval("NS.setSetting")("questPlanner", True); g.advance(5)
    out = guide_message(g)
    assert "Install or enable Questie" in out and "/reload" in out and "/qs questie" in out, out
    assert "recent QuestieDB" not in out, out


def test_guide_with_old_questie_says_update_and_check(style):
    g = Game(style, DATA + "\nQuestDB.GetAllIds=nil", fresh=True)
    g.start(); g.eval("NS.setSetting")("questPlanner", True); g.advance(5)
    out = guide_message(g)
    assert "Update Questie" in out and "/qs questie" in out, out


# UX-59: the guide keeps the classic stone (no flat fill over it) and its word buttons use the button art.
def test_guide_panel_shows_the_stone_and_word_buttons_have_art(style):
    from test_classic_style import RECORD, stone
    g = Game(style, DATA, fresh=True)
    g.run(RECORD + "\nPANEL_FILLS={} local f2=NS.style.fill\n"
          "NS.style.fill=function(frame,layer,r,gg,b,a) local t=f2(frame,layer,r,gg,b,a); "
          "if frame==QuestSharingPlannerPanel then PANEL_FILLS[#PANEL_FILLS+1]={t=t,layer=layer or 'BACKGROUND',a=a} end; return t end")
    g.start(); g.eval("NS.setSetting")("questPlanner", True); g.advance(5)
    panel = stone(g, "QuestSharingPlannerPanel")
    covers = g.eval("(function() local n=0 for _, f in ipairs(PANEL_FILLS) do if f.layer=='BACKGROUND' and f.a==1 "
                    "and f.t~=QuestSharingPlannerPanel.stone.base and f.t.height==nil then n=n+1 end end return n end)()")
    assert panel.stone and covers == 0, "a flat fill covers the stone"
    for label in ("Plan", "Lock"):
        assert button(g, label).bg.shown is not False, label + " has no button art"


# UX-60: route-search notes stay in the report; steps show only advice the player can use.
def test_steps_do_not_show_route_search_notes(style):
    g = game(style)
    from test_quest_planner_zone_steps import text
    assert "Work time estimated" not in text(g), text(g)
    assert "Work time estimated" in "\n".join(str(v) for v in g.eval("NS.questPlanner.report")().reasons.values())


def test_shared_kill_advice_is_kept_for_steps(style):
    import test_quest_optimizer as opt
    g = opt.game(style)
    _, rep = g.eval("solve")("all")
    notes = list(rep.stepNotes.values())
    assert any("shared kill credit" in n for n in notes), notes
    assert not any("Starting here saves" in n for n in notes), notes
    assert any("Starting here saves" in n for n in rep.reasons.values())


# UX-61: pickup and hand-in steps name the giver once in the heading, then list the quests.
def test_pickup_and_handin_steps_name_the_giver_once(style):
    g = game(style)
    visible = rows(g)
    assert visible[0].detail.text.endswith("Pick up from Sentinel Hill Giver:\n[1] Local Harvest|r"), visible[0].detail.text
    assert visible[2].detail.text.endswith("Hand in to Sentinel Hill Giver:\n[1] Local Harvest|r"), visible[2].detail.text
    assert "Pick up Local Harvest" not in visible[0].detail.text and "Take these quests" not in visible[0].detail.text

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

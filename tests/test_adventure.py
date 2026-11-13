"""Quest invitation generation, preview and any-chat drafting through the real Lua modules."""
import inspect
import pathlib
import sys
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))
from harness import Game

STYLES = ("modern", "classic")


def game(style, pre=""):
    g = Game(style, pre, fresh=True)
    g.start()
    g.run("SENT={}; PRINTED={}; OPENED={}")
    return g


def quest(g, qid=100):
    return g.eval("NS.compat.findEntry")(qid)


def message(g, qid=100, style=1):
    return g.eval("NS.adventure.message")(quest(g, qid), style)


def button(g, label):
    g.run('for _,f in ipairs(FRAMES) do if f.text==%s then f.scripts.OnClick(f,"LeftButton"); return end end' % repr(label))


def test_three_roleplay_wordings_keep_quest_and_question(style):
    g = game(style)
    texts = [message(g, style=i) for i in range(1, 4)]
    assert len(set(texts)) == 3
    for text in texts:
        assert "Wolves Among Us" in text and "|Hquest:100:" in text and text.endswith("?")
        assert "Elwynn Forest" in text and len(text.encode()) <= 255


def test_other_zone_quest_does_not_claim_current_zone(style):
    g = game(style)
    g.run('ZONE="Durotar"')
    assert "in Durotar" not in message(g)


def test_long_unicode_titles_fit_without_partial_links_or_broken_utf8(style):
    g = game(style)
    g.run('BYID(100).title = string.rep("é", 200)')
    text = message(g)
    assert len(text.encode()) <= 255 and text.endswith("Who will join me?")
    assert "|Hquest:" not in text and "[" in text and "]" in text


def test_finished_or_removed_quest_is_not_recruited(style):
    g = game(style)
    assert message(g, 101) is None
    e = quest(g)
    g.run("BYID(100).complete=true")
    assert g.eval("NS.adventure.prepare")(e, "Join me?", "say")[0] is False
    assert not g.opened() and not g.sent()


def test_command_quest_id_name_and_link_select_same_quest(style):
    g = game(style)
    for arg in ("100", "Wolves Among Us", g.eval("NS.compat.link")(quest(g))):
        g.slash("adventure " + arg)
        w = g.eval("NS.adventure._window()")
        assert w.frame.shown and "Wolves Among Us" in w.quest.text
    assert not g.opened() and not g.sent()


def test_menu_action_is_available_without_party_or_questie(style):
    g = game(style)
    g.eval("NS.openQuestMenu")(quest(g))
    menu, lines = g.eval("NS._questMenu()")
    invite = next(b for b in lines.values() if b.shown and "Seek fellow" in b.text)
    invite.scripts.OnClick(invite, "LeftButton")
    assert not menu.shown and g.eval("NS.adventure._window().frame.shown")


def test_preview_can_change_wording_quest_and_edit_text(style):
    g = game(style)
    g.slash("adventure 100")
    w = g.eval("NS.adventure._window()")
    first = w.preview.GetText(w.preview)
    button(g, "Another wording")
    assert w.preview.GetText(w.preview) != first
    w.preview.SetText(w.preview, "Fellow wanderers, will you join my quest?")
    w.channel.SetText(w.channel, "guild")
    button(g, "Prepare chat")
    assert g.opened()[-1] == "/g Fellow wanderers, will you join my quest?"
    assert not w.frame.shown and not g.sent()


def test_standard_whisper_and_numbered_chat_routes(style):
    g = game(style)
    routes = {"say": "/s ", "yell": "/y ", "party": "/p ", "raid": "/raid ",
              "guild": "/g ", "officer": "/o ", "instance": "/i ",
              "whisper Anna-Realm": "/w Anna-Realm ", "1": "/1 ", "/2": "/2 "}
    for route, prefix in routes.items():
        g.run("CLOSE_CHAT()")
        assert g.eval("NS.adventure.prepare")(quest(g), message(g), route) is True
        assert g.opened()[-1].startswith(prefix), (route, g.opened()[-1])
    assert not g.sent()


def test_joined_channel_name_resolves_and_unknown_is_rejected(style):
    g = game(style, '''function GetChannelName(x)
        if x=="LookingForGroup" or x==4 then return 4,"LookingForGroup" end
        return 0,nil
    end''')
    assert g.eval("NS.adventure.prepare")(quest(g), message(g), "LookingForGroup") is True
    assert g.opened()[-1].startswith("/4 ")
    g.run("CLOSE_CHAT()")
    for name in ("Unknown", "1", "whisper Anna Other", "0", "1.5"):
        assert g.eval("NS.adventure.prepare")(quest(g), message(g), name)[0] is False


def test_current_chat_keeps_channel_recipient_and_existing_text(style):
    g = game(style)
    g.run('ACTIVE_BOX=EDITBOX; EDITBOX.text="Hello!"; EDITBOX.chat="/w"; EDITBOX.target="Anna-Realm"')
    assert g.eval("NS.adventure.prepare")(quest(g), "Fellow adventurers, who will join me?", "current") is True
    assert g.eval("EDITBOX.chat") == "/w" and g.eval("EDITBOX.target") == "Anna-Realm"
    assert g.eval("EDITBOX.text").startswith("Hello! Fellow adventurers")
    assert not g.opened() and not g.sent()


def test_existing_draft_is_not_moved_to_a_different_channel(style):
    g = game(style)
    g.run('ACTIVE_BOX=EDITBOX; EDITBOX.text="A private thought"; EDITBOX.chat="/w"')
    ok, why = g.eval("NS.adventure.prepare")(quest(g), message(g), "say")
    assert not ok and "draft" in why
    assert g.eval("EDITBOX.text") == "A private thought" and not g.opened()


def test_duplicate_and_full_draft_are_not_overwritten(style):
    g = game(style)
    g.run('ACTIVE_BOX=EDITBOX; EDITBOX.text=NS.compat.link(NS.compat.findEntry(100))')
    assert not g.eval("NS.adventure.prepare")(quest(g), message(g), "current")[0]
    g.run('EDITBOX.text=string.rep("x",250)')
    assert not g.eval("NS.adventure.prepare")(quest(g), message(g), "current")[0]
    assert g.eval("#EDITBOX.text") == 250


def test_sending_mode_never_bypasses_enter_for_invitations(style):
    g = game(style, 'SendChatMessage=function() error("invitation must not send automatically") end')
    g.run('NS.db.mode="send"; NS.db.quickSend=true')
    assert g.eval("NS.adventure.prepare")(quest(g), message(g), "say") is True
    assert len(g.opened()) == 1 and not g.sent()


def test_completed_quest_while_preview_open_requires_new_selection(style):
    g = game(style)
    g.slash("adventure 100")
    w = g.eval("NS.adventure._window()")
    g.run("BYID(100).complete=true")
    g.fire("QUEST_LOG_UPDATE")
    button(g, "Prepare chat")
    assert "unfinished quest" in w.status.text and not g.opened()


def test_empty_log_master_switch_and_missing_chat_api_fail_cleanly(style):
    g = game(style)
    g.slash("adventure")
    g.slash("off")
    assert not g.eval("NS.adventure._window().frame.shown")
    assert not g.eval("NS.adventure.prepare")(quest(g), "Join me?", "say")[0]
    g.slash("on")
    g.run("ChatFrame_OpenChat=nil")
    assert not g.eval("NS.adventure.prepare")(quest(g), "Join me?", "say")[0]
    g.run("QUESTS={}")
    g.slash("adventure")
    assert "No unfinished quests" in g.eval("NS.adventure._window().quest.text")


def test_multiline_or_oversized_user_edit_is_rejected(style):
    g = game(style)
    for text in ("", "a\nb", "é" * 128):
        assert not g.eval("NS.adventure.prepare")(quest(g), text, "say")[0]
    assert not g.opened() and not g.sent()


if __name__ == "__main__":
    failed = total = 0
    for name, fn in sorted(list(globals().items())):
        if not name.startswith("test_"): continue
        for style in STYLES if inspect.signature(fn).parameters else (None,):
            total += 1
            try:
                fn(style) if style else fn(); print("ok  ", f"{name}[{style}]")
            except Exception as e:
                failed += 1; print("FAIL", f"{name}[{style}]", type(e).__name__, str(e)[:500])
    print(f"\n{total - failed}/{total} passed")
    raise SystemExit(1 if failed else 0)

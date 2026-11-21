-- Static Cooking/fishing reference. Guide facts checked 2026-11-17; no network at runtime.
-- These guides flag higher-level content as beta-derived; validate with the live trainer.
local _, ns = ...
ns.inModule(nil)          -- core: always on (Modules.lua)
local D = { date = "2026-11-17", fish = {}, vendorPlaces = {}, cookingSources = {} }
ns.professionReference = D
-- Practical example waters, not exhaustive fish distributions or guaranteed catches.
-- safeSkill is effective skill including pole/lure bonuses; nil means unverified.
-- Source: Forever fishing-and-cooking-leveling-guide (linked in the research note).
local function fish(id, name, map, water, minimum, safe, note)
    D.fish[id]={name=name, locations={{map=map,water=water,minSkill=minimum,safeSkill=safe,note=note}}}
end
fish(6291,"Raw Brilliant Smallfish",1429,"Crystal Lake, Elwynn Forest",1,nil)
fish(6303,"Raw Slitherskin Mackerel",1411,"Coast south of Sen'jin Village, Durotar",1,nil)
fish(6289,"Raw Longjaw Mud Snapper",1453,"Stormwind canals",nil,75)
fish(6308,"Raw Bristle Whisker Catfish",1456,"Thunder Bluff pond near the Auction House",nil,75)
fish(8365,"Raw Mithril Head Trout",1445,"Dustwallow Marsh inland waters (not the sea)",nil,nil,"Guide route: fish here around skill 205-255; use a lure below 225. Exact entry/no-getaway thresholds unverified.")
fish(13758,"Raw Redgill",1444,"Feralas lakes/rivers, excluding Jademir Lake",nil,nil,"Guide route: 255+ with Nightcrawlers; exact entry/no-getaway thresholds unverified.")
fish(13759,"Raw Nightfin Snapper",1444,"Feralas lakes/rivers, excluding Jademir Lake",nil,nil,"Guide route: 255+ with Nightcrawlers. No bites 12:00-18:00 game time; exact skill thresholds unverified.")
-- Known vendor localities supplement the dataset's NPC-only recipe hints.
D.vendorPlaces={
    ["Catherine Leland"]="Stormwind",["Tharynn Bouden"]="Goldshire, Elwynn Forest (Alliance)",
    ["Harn Longcast"]="Bloodhoof Village, Mulgore (Horde)",["Sewa Mistrunner"]="Thunder Bluff (Horde)",
    ["Naal Mistrunner"]="Thunder Bluff (Horde)",["Ronald Burch"]="Undercity (Horde)",
    ["Lizbeth Cromwell"]="Undercity (Horde)",["Zansoa"]="Sen'jin Village, Durotar (Horde)",
    ["Tansy Puddlefizz"]="Ironforge (Alliance)",["Nyoma"]="Dolanaar, Teldrassil (Alliance)",
    ["Kelsey Yance"]="Booty Bay, Stranglethorn Vale (both factions)",
    ["Gikkix"]="Steamwheedle Port, Tanaris (both factions)",
    ["Kendor Kabonka"]="Old Town, Stormwind (Alliance)",
    ["Wulan"]="Shadowprey Village, Desolace (Horde)",
    ["Sheendra Tallgrass"]="Camp Mojache, Feralas (Horde)",["Vivianna"]="Feathermoon Stronghold, Feralas (Alliance)",
}
-- Guides fill gaps where the client lists a recipe item but no seller name.
D.cookingSources={
    [7751]={"Alliance: buy Recipe: Brilliant Smallfish from Tharynn Bouden (Goldshire, Elwynn Forest) or Catherine Leland (Stormwind).", "Horde: Harn Longcast (Bloodhoof Village, Mulgore) or Sewa Mistrunner (Thunder Bluff)."},
    [7752]={"Alliance: buy Recipe: Slitherskin Mackerel from Tansy Puddlefizz (Ironforge) or Nessa Shadowsong (Rut'theran Village, Teldrassil).", "Horde: Zansoa (Sen'jin Village, Durotar) or Martine Tramblay (Tirisfal Glades)."},
    [7753]={"Alliance: buy Recipe: Longjaw Mud Snapper from Tharynn Bouden (Goldshire) or Tansy Puddlefizz (Ironforge).", "Horde: Harn Longcast (Mulgore), Naal Mistrunner (Thunder Bluff), Lizbeth Cromwell (Undercity)."},
    [7755]={"Alliance: buy Recipe: Bristle Whisker Catfish from Catherine Leland (Stormwind).", "Horde: Naal Mistrunner (Thunder Bluff) or Ronald Burch (Undercity)."},
    [7827]={"Alliance: buy Recipe: Rainbow Fin Albacore from Catherine Leland (Stormwind) or Nessa Shadowsong (Teldrassil).", "Horde: Zansoa (Durotar), Shankys (Orgrimmar) or Ronald Burch (Undercity). Both: Kilxx (Ratchet, The Barrens)."},
    [20916]={"Both factions: buy Recipe: Mithril Head Trout from Kelsey Yance (Booty Bay, Stranglethorn Vale)."},
    [15855]={"Alliance: buy Recipe: Roast Raptor from Hammon Karwn (Refuge Pointe, Arathi Highlands).", "Horde: Keena (Hammerfall, Arathi Highlands) or Ogg'marr (Brackenwall Village, Dustwallow Marsh)."},
    [6412]={"Alliance quest: Recipe of the Kaldorei from Zarrin in Dolanaar, Teldrassil."},
}

-- Static Forever rank reference. Guide facts checked 2026-11-17; no network at runtime.
-- Per-profession sources: https://www.wow-professions.com/forever/<slug>-leveling-guide
-- These guides flag higher-level content as beta-derived; validate with the live trainer.
local _, ns = ...
local D = { date = "2026-11-17", professions = {}, fish = {}, vendorPlaces = {}, cookingSources = {} }
ns.professionReference = D
local function profession(id, name, apprenticeA, apprenticeH, journeyA, journeyH, expertA, expertH, artisanA, artisanH)
    local p = { id=id, name=name, source="https://www.wow-professions.com/forever/" .. string.lower(name):gsub(" ", "-") .. "-leveling-guide", ranks={} }
    local function rank(name, cap, skill, level, a, h, method)
        p.ranks[#p.ranks+1] = { name=name, cap=cap, skill=skill, level=level, Alliance=a, Horde=h, method=method or "Train the next rank." }
    end
    rank("Apprentice",75,0,0,apprenticeA,apprenticeH,"Learn the profession from this trainer; ask a city guard for directions.")
    rank("Journeyman",150,50,10,journeyA or apprenticeA,journeyH or apprenticeH)
    rank("Expert",225,125,20,expertA,expertH)
    rank("Artisan",300,200,35,artisanA,artisanH)
    D.professions[#D.professions+1] = p
    return p
end
profession(171,"Alchemy","Tel'Athir - Stormwind","Whuut - Orgrimmar",
    "Lilyssia Nightbreeze - Stormwind","Yelmak - Orgrimmar",
    "Ainethil - Darnassus","Doctor Herbert Halsey - Undercity",
    "Kylanna Windwhisper - Feathermoon Stronghold, Feralas","Rogvar - Stonard, Swamp of Sorrows")
profession(164,"Blacksmithing","Groum Stonebeard - Ironforge","Ug'thok - Orgrimmar",
    "Therum Deepforge - Stormwind","Snarl - Orgrimmar",
    "Bengus Deepforge - Ironforge","Saru Steelfury - Orgrimmar",
    "Brikk Keencraft - Booty Bay, Stranglethorn Vale","Brikk Keencraft - Booty Bay, Stranglethorn Vale")
local cooking=profession(185,"Cooking","Stephen Ryback - Stormwind","Zamja - Orgrimmar",nil,nil,
    "Shandrina - Mystral Lake, Ashenvale","Wulan - Shadowprey Village, Desolace",
    "Dirge Quikcleave - Gadgetzan, Tanaris","Dirge Quikcleave - Gadgetzan, Tanaris")
cooking.ranks[2].level=0
cooking.ranks[3].level=0; cooking.ranks[3].method="Buy and read Expert Cookbook."
cooking.ranks[4].skill=225; cooking.ranks[4].method="Complete Clamlette Surprise: bring 12 Giant Eggs, 10 Zesty Clam Meat and 20 Alterac Swiss. Optional breadcrumb: Daryl Riknussun (Ironforge) / Zamja (Orgrimmar)."
local enchanting=profession(333,"Enchanting","Alanna Raveneye - Teldrassil","Jhag - Orgrimmar",
    "Lucan Cordell - Stormwind","Godan - Orgrimmar",
    "Kitta Firewind - Tower of Azora, Elwynn Forest","Hgarth - Sun Rock Retreat, Stonetalon Mountains",
    "Annora - inside Uldaman, Badlands","Annora - inside Uldaman, Badlands")
enchanting.ranks[4].method="Take a group through Uldaman (back entrance). Clear the scorpions in Annora's room to make her appear; bring materials and learn later recipes before leaving."
profession(202,"Engineering","Bronk Guzzlegear - Dun Morogh","Thund - Orgrimmar",
    "Trixie Quikswitch - Ironforge","Nogg - Orgrimmar",
    "Springspindle Fizzlegear - Ironforge","Roxxik - Orgrimmar",
    "Buzzek Bracketswing - Gadgetzan, Tanaris","Buzzek Bracketswing - Gadgetzan, Tanaris")
local aid=profession(129,"First Aid","Shaina Fuller - Stormwind","Arnok - Orgrimmar",nil,nil,
    "Deneb Walker - Stromgarde Keep, Arathi Highlands","Balai Lok'Wein - Brackenwall Village, Dustwallow Marsh",
    "Doctor Gustaf VanHowzen - Theramore, Dustwallow Marsh","Doctor Gregory Victor - Hammerfall, Arathi Highlands")
aid.ranks[2].level=0; aid.ranks[3].level=0
aid.ranks[3].method="Buy and read Expert First Aid - Under Wraps; also buy the Heavy Silk and Mageweave Bandage manuals."
aid.ranks[4].skill=225; aid.ranks[4].method="Complete Triage: use the supplied bandages to save 15 patients; prioritize critically injured patients. Return to the doctor for later bandages."
local fishing=profession(356,"Fishing","Arnold Leland - Stormwind","Lumak - Orgrimmar",nil,nil,
    "Old Man Heming - Booty Bay, Stranglethorn Vale","Old Man Heming - Booty Bay, Stranglethorn Vale",
    "Nat Pagle - Tidefury Cove, Dustwallow Marsh","Nat Pagle - Tidefury Cove, Dustwallow Marsh")
fishing.ranks[3].method="Buy and read Expert Fishing - The Bass and You."
fishing.ranks[4].skill=225; fishing.ranks[4].method="Complete Nat Pagle, Angler Extreme: catch Feralas Ahi (Feralas), Misty Reed Mahi Mahi (Swamp of Sorrows), Sar'theris Striker (Desolace), Savage Coast Blue Sailfin (Stranglethorn Vale)."
local herb=profession(182,"Herbalism","Tannysa - Stormwind","Jandi - Orgrimmar",nil,nil,
    "Tannysa - Stormwind","Jandi - Orgrimmar","Tannysa - Stormwind","Jandi - Orgrimmar")
profession(165,"Leatherworking","Adele Fielder - Elwynn Forest","Kamari - Orgrimmar",
    "Simon Tanner - Stormwind","Karolek - Orgrimmar",
    "Telonis - Darnassus","Una - Thunder Bluff",
    "Drakk Stonehand - Aerie Peak, The Hinterlands","Hahrana Ironhide - Camp Mojache, Feralas")
local mining=profession(186,"Mining","Gelman Stonehand - Stormwind","Makaru - Orgrimmar",nil,nil,
    "Gelman Stonehand - Stormwind","Makaru - Orgrimmar","Gelman Stonehand - Stormwind","Makaru - Orgrimmar")
local skin=profession(393,"Skinning","Maris Granger - Stormwind","Thuwd - Orgrimmar",nil,nil,
    "Maris Granger - Stormwind","Thuwd - Orgrimmar","Maris Granger - Stormwind","Thuwd - Orgrimmar")
for _, p in ipairs({herb,mining,skin}) do
    for _, rank in ipairs(p.ranks) do rank.level=0 end
end
profession(197,"Tailoring","Lawrence Schneider - Stormwind","Snang - Orgrimmar",
    "Sellandus - Stormwind","Magar - Orgrimmar",
    "Georgio Bolero - Stormwind","Josef Gregorian - Undercity",
    "Timothy Worthington - Theramore, Dustwallow Marsh","Daryl Stack - Tarren Mill, Hillsbrad Foothills")

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

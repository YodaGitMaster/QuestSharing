# Architecture
Last updated: 2026-11-13

## File tree
```text
QuestSharing/  # Repository root
├── .gitignore  # Exclude caches and release output
├── CHANGELOG.md  # Release history
├── QuestSharing/  # WoW addon runtime
│   ├── Adventure.lua  # Role-play quest invitation preview and chosen-channel chat drafts
│   ├── Bags.lua  # quest items marked in your bags, so you only carry what this zone needs
│   ├── Bindings.xml  # Game key bindings
│   ├── Compat.lua  # one place that knows the differences between the classic and the modern quest APIs
│   ├── Core.lua  # settings, timers, events, chat helpers and the /qs commands
│   ├── Diagnostics.lua  # an error log and a "doctor" report, so problems on a real game client are easy to report
│   ├── Friends.lua  # add the people you group with to your friends list
│   ├── EquipmentUI.lua  # Shared equipment explorer, filters, item cards and inline details
│   ├── Fishing.lua  # Optional world-map water notes, editor and AnglerAtlas zone summaries
│   ├── Highlight.lua  # make quest objectives easier to find
│   ├── Loot.lua  # Equipment-only instance browser with AtlasLoot tables and partial QuestieDB fallback
│   ├── Marker.lua  # showing each other where you are
│   ├── Menu.lua  # the small menu a right click on a quest in the Party quests window opens
│   ├── MinimapButton.lua  # a small button on the minimap
│   ├── OptionalUI.lua  # Shared frames, edit boxes, scrolling, tooltips and read-only map directions
│   ├── Panel.lua  # shows which party members share your quests
│   ├── Ping.lua  # one key (or a click on the ring) pings the nearest creature one of your quests needs with the game's
│   ├── Progress.lua  # notices when the objectives of one of your quests are all done, tells the party
│   ├── QuestItems.lua  # quest items you can USE (a torch to light, a flare to throw...)
│   ├── QuestSharing.toc  # Addon metadata and module load order
│   ├── Questie.lua  # if the Questie addon is installed, its quest database tells us where a quest starts and which quests
│   ├── Quick.lua  # a quick-chat wheel
│   ├── Rewards.lua  # On-demand QuestieDB reward catalogue, eligibility filters and item comparisons
│   ├── Settings.lua  # the settings window.   /qs settings   (also: the minimap button, the "Settings" link on the Party quests
│   ├── Share.lua  # notice a new party, push the quests of the area one by one, read the game's replies
│   ├── SpellRanks.lua  # Opt-in learned spell-rank upgrades across player action-bar pages
│   ├── Status.lua  # what to say about a quest you click in the tracker, and the hooks that notice the click
│   ├── Style.lua  # one look for every window of the addon (settings, Party quests, reports)
│   ├── Sync.lua  # party members who also run Quest Sharing tell each other exactly which quests they have
│   ├── Team.lua  # "Picked up [Wolves Among Us] - Anna has it too. Want to do it together?"
│   ├── Track.lua  # keeps the quest tracker (the list on the right) filled with the quests closest to you
│   └── ZoneLevels.lua  # Read-only map questing ranges, outdoor zone badges and hover panel
├── README.md  # User documentation
├── build_release.py  # Build install ZIP and release notes
├── context/  # Session continuity and live architecture
│   ├── BUGS/  # Verified bug methodology and regressions
│   │   ├── 2026-11-13-equipment-duplicate-rows.md  # Filtered name grouping with complete source retention
│   │   ├── 2026-11-13-zone-levels-opt-in.md  # Once-only migration from auto-enabled map ranges
│   │   ├── 2026-11-13-spell-rank-zero-spec.md  # Numeric-zero active specialization in Lua
│   │   ├── 2026-11-13-spell-rank-cursor-read.md  # Preserve readability separately from an empty cursor
│   │   ├── 2026-11-13-spell-rank-hidden-pages.md  # Native slot range differs from visible pages
│   │   ├── 2026-11-13-dropdown-offscreen-selection.md  # Mixed wheel/keyboard dropdown navigation
│   │   ├── 2026-11-13-debounced-filter-reapply.md  # Range commit debounce cancellation playbook
│   │   └── 2026-11-13-instance-loot-non-equipment.md  # Equipment filtering reproduction and fix
│   ├── architecture.md  # Live source map and runtime diagrams
│   ├── decisions.md  # Choices and rationale
│   ├── insights.md  # Timestamped findings
│   ├── schema.md  # Data structures and formats
│   └── state.md  # Current task and handoff
└── tests/  # Python tests and Lua API harness
    ├── harness.py  # Mock WoW APIs and load Lua addon
    ├── test_adventure.py  # Invitation generation, chat routes, preview and draft preservation
    ├── test_bags.py  # Tests for bags
    ├── test_box.py  # Tests for box
    ├── test_done.py  # Tests for done
    ├── test_equipment.py  # Shared window, type/level filters, dungeon identity and cancellation
    ├── test_equipment_grouping.py  # Unique names, combined suppliers/routes, versions and filter boundaries
    ├── test_emotes.py  # Tests for emotes
    ├── test_extras.py  # Tests for extras
    ├── test_features.py  # Tests for features
    ├── test_friends.py  # Tests for friends
    ├── test_highlight.py  # Tests for highlight
    ├── test_items.py  # Tests for items
    ├── test_instance_focus.py  # Current dungeon opening, delayed catalogue focus, manual navigation and Extra tools label
    ├── test_log.py  # Tests for log
    ├── test_loot.py  # Instance loot parsing, search, provider fallback and asynchronous item names
    ├── test_look.py  # Tests for look
    ├── test_menu.py  # Tests for menu
    ├── test_optional.py  # Optional tool integration, water persistence, reward eligibility and comparisons
    ├── test_ping.py  # Tests for ping
    ├── test_questmap.py  # How-to quest text and retired map-overlay guards
    ├── test_questsharing.py  # Tests for questsharing
    ├── test_quick.py  # Tests for quick
    ├── test_ringtest.py  # Tests for ringtest
    ├── test_settings.py  # Tests for settings
    ├── test_stats.py  # Shared stat minimums, native API compatibility, live controls and cache invalidation
    ├── test_spell_ranks.py  # Learned ranks, guarded action-slot swaps, combat/cursor deferral and API compatibility
    ├── test_team.py  # Tests for team
    ├── test_together.py  # Tests for together
    ├── test_tracker.py  # Tests for tracker
    ├── test_triggers.py  # Tests for triggers
    ├── test_usability.py  # Direct choices, live searches, sorting, selection and navigation workflows
    ├── test_where.py  # Tests for where
    ├── test_zone.py  # Tests for zone
    └── test_zone_levels.py  # Native map ranges, geometry, hover, lifecycle, settings and safe read-only behavior
```

## Flowchart
```mermaid
flowchart TD
    TOC[QuestSharing.toc] --> Compat[Compat.lua: ns.compat]
    TOC --> Core[Core.lua: events, settings, timers]
    Core --> Share[Share.lua: quest offers]
    Core --> Sync[Sync.lua: party addon messages]
    DB[Optional QuestieDB] --> Q[Questie.lua: ns.questie]
    Share --> API[WoW APIs via Compat.lua]
    Sync --> API
    Settings[Settings.lua: Extra tools tab] --> Fishing[Fishing.lua: water notes]
    Settings --> Rewards[Rewards.lua: reward browser]
    OptionalUI[OptionalUI.lua] --> Equipment[EquipmentUI.lua: shared explorer, Rare+ only]
    Equipment --> Rewards
    Equipment --> Loot
    Rewards --> Group[EquipmentUI.groupItems: filter first, one row per name]
    Loot --> Group
    Group --> Inline[Single inline detail pane: every matching source and version]
    Equipment --> StatAPI[WoW GetItemStats: lazy link cache, invalidated on item events]
    Settings --> Ranks[SpellRanks.lua: opt-in action-bar rank updates]
    Core --> Ranks
    Ranks --> SpellBook[WoW learned player spell book]
    Ranks --> ActionSlots[WoW normal action slots, out of combat and cursor clear]
    Settings --> ZoneLevels[ZoneLevels.lua: zone questing ranges]
    Core --> ZoneLevels
    ZoneLevels --> NativeMap[C_Map level ranges, zone bounds and hover info]
    ZoneLevels --> MapLabels[Own click-through map labels and panel]
    OptionalUI --> Fishing
    OptionalUI --> Rewards
    Fishing --> Waters[(QuestSharingDB.fishingWaters)]
    Atlas[Optional AnglerAtlas] --> Fishing
    Rewards --> Q
    Rewards --> Items[WoW item info and comparison tooltips]
    Settings --> Loot[Loot.lua: instance drop search]
    Loot --> AtlasLoot[Optional AtlasLoot encounter tables]
    Loot --> Q
    Loot --> Items
    Loot --> Location[WoW GetInstanceInfo and localized subzone names]
    Loot --> Rewards
    QuestMenu[Menu.lua: Seek fellow adventurers] --> Adventure[Adventure.lua: invitation composer]
    Core --> Adventure
    Settings --> Adventure
    Adventure --> Compat[Compat.lua: quest log and links]
    Adventure --> Chat[Existing chat draft or ChatFrame_OpenChat]
```

## Sequence diagrams
```mermaid
sequenceDiagram
    participant User
    participant Map as Existing world map
    participant Levels as ZoneLevels.lua
    participant Data as C_Map
    User->>Map: Open or navigate map normally
    Levels->>Map: Read shown map, canvas and normalized cursor
    Levels->>Data: Read outdoor zone levels and child-zone rectangles
    Levels->>Map: Draw own click-through range badges and information panel
    Note over Levels,Map: Never opens, navigates or refreshes Blizzard map/pins
    User->>Map: Hover or view another zone
    Levels->>Data: Read hovered zone and its range
    Levels->>Map: Update own text only
```

```mermaid
sequenceDiagram
    participant User
    participant Settings as Settings.lua / Core.lua
    participant Ranks as SpellRanks.lua
    participant Game as WoW spell book and action bars
    User->>Settings: Enable highest learned ranks in Extra tools
    Settings->>Ranks: Debounce update; also login / learned spells / placed actions
    Ranks->>Game: Read learned player spells and existing normal bar slots
    alt Combat, temporary bar or cursor occupied
        Ranks->>Ranks: Wait for combat/cursor/bar event
    else Ready
        Ranks->>Game: Pick up higher learned rank; verify cursor; place in same spell slot
        Game-->>Ranks: Revalidate target after pickup; read back replacement and release swapped old rank
        Ranks->>User: Updated count or client limitation
    end
```

```mermaid
sequenceDiagram
    participant Game as WoW
    participant Core as Core.lua
    participant Saved as QuestSharingDB
    Game->>Core: ADDON_LOADED(addon name)
    Core->>Saved: Once-only zoneLevels opt-in migration, then preserve later choices
    Core->>Saved: Fill missing defaults and migrate dbVersion
    Core->>Core: ns.db = QuestSharingDB
    Core->>Core: Refresh settings if available
```


```mermaid
sequenceDiagram
    participant User
    participant Fishing as Fishing.lua
    participant Saved as QuestSharingDB.fishingWaters
    participant Map as World map canvas
    User->>Map: Open map with M, Alt-click water
    Map->>Fishing: OnMouseDown with normalized coordinates
    Fishing->>User: Water editor with selected coordinates
    User->>Fishing: Save name, skill, fish and notes
    Fishing->>Saved: Validate and store WaterNote
    Fishing->>Map: Draw own overlay frames for this map
    Note over Fishing,Map: Never opens or redraws Blizzard's map
```

```mermaid
sequenceDiagram
    participant User
    participant Rewards as Rewards.lua
    participant Items as QuestieDB ItemDB
    participant Q as Questie.lua
    participant Game as WoW item APIs
    User->>Rewards: Open shared EquipmentUI quest tab
    Rewards->>Items: GetAllIds; read 100 items per timer batch
    Items-->>Rewards: Equipment and questRewards links
    Rewards->>Q: Read quest level, class/race masks and starter
    Rewards->>Game: Get item details for eligible rewards
    Rewards->>Rewards: Group filtered equipment by name; collect every eligible quest route
    Rewards->>User: Paginated unique equipment names
    Game-->>Rewards: GET_ITEM_INFO_RECEIVED
    Rewards->>User: Debounced refresh of cached item details
    User->>Rewards: Hover item / click quest
    Rewards->>Game: Item and equipped comparison tooltip
    Rewards->>User: All matching quest starters/prerequisites inline; map directions use first route
```

```mermaid
sequenceDiagram
    participant User
    participant Menu as Menu.lua / Core.lua / Settings.lua
    participant Adventure as Adventure.lua
    participant Compat as Compat.lua
    participant Chat as WoW chat edit box
    User->>Menu: Right-click quest; Seek fellow adventurers (row 2)
    Note over User,Menu: Directly after Tell the party how I am doing; also qs adventure / Extra tools
    Menu->>Adventure: open quest invitation
    Adventure->>Compat: Read unfinished quest and link
    Adventure->>User: Editable invitation, wording and channel
    User->>Adventure: Prepare chat
    Adventure->>Compat: Revalidate unfinished quest
    Adventure->>Chat: Preserve active draft or open chosen channel
    User->>Chat: Press Enter to send
```

```mermaid
sequenceDiagram
    participant User
    participant Loot as Loot.lua
    participant Atlas as AtlasLoot ItemDB
    participant Questie as Questie.lua
    participant Game as WoW item APIs
    User->>Loot: Open instance drops
    Loot->>Game: Read current party-instance ID, name and subzone
    Loot->>Atlas: Read installed Classic/Forever dungeon tables; reject raids/world bosses
    alt Compatible AtlasLoot data available
        Atlas-->>Loot: Instances, encounters, difficulties and item IDs
    else No compatible encounter catalogue
        Loot->>Questie: Enumerate item drops from instance NPC/object spawns
        Note over Loot,Questie: Label coverage as partial
    end
    Loot->>Loot: Index up to 100 rows per timer batch
    Loot->>Loot: After indexing, select recognized current dungeon and reveal its navigation page
    Note over User,Loot: Manual location/search changes cancel pending focus; later refreshes preserve browsing
    Loot->>Game: Load up to 10 item details per timer batch (Rewards.itemInfo)
    User->>Loot: Filter dungeon, encounter or item/boss text; shared type/slot/level filters
    Loot->>Loot: Require recognized equipment slot and native quality 3+; hide unknown items
    Loot->>Loot: Group filtered names; combine each supplier's difficulty labels
    Loot->>User: One equipment row per name; all suppliers and versions inline
    Game-->>Loot: GET_ITEM_INFO_RECEIVED
    Loot->>User: Debounced equipment classification and name refresh
```

```mermaid
sequenceDiagram
    participant User
    participant E as EquipmentUI.lua
    participant Page as Rewards.lua / Loot.lua
    User->>E: Open quest or dungeon tab
    E->>Page: Hide old page and suspend pending work
    E->>Page: Show selected child in same host
    User->>E: Apply type, slot, inclusive level range or up to three stat minimums
    User->>E: Search dropdown choices / type live query / scroll results
    E->>Page: Debounced search or direct filter selection; keep quality 3+
    Page->>E: matches native item metadata
    E->>E: Read cached native stat table only for active conditions; require all minimums
    Page->>E: groupItems(filtered sources) by normalized name
    E->>Page: Sort unique equipment; preserve selected name if visible
    User->>Page: Select item card
    Page->>E: Update inline route/source pane
    User->>E: Close explorer
    E->>Page: Cancel unfinished timers and hide child
```

## Class diagram
The addon uses Lua tables and a shared namespace; these are data relationships, not declared classes.
```mermaid
classDiagram
    class Namespace {
        compat
        defaults
        db
        known
        offered
        questie
        adventure
        fishing
        rewards
        loot
        equipmentUI
        spellRanks
        zoneLevels
    }
    class Settings {
        dbVersion
        enabled
        bagMarks
        fishingMap
        rewardBrowser
        autoSpellRanks
        zoneLevels
        zoneLevelsOptInMigrated
        fishingWaters
        hideTracker
    }
    class WaterNote {
        name
        map
        x_0_to_100
        y_0_to_100
        minSkill_optional
        safeSkill_optional
        fish
        notes
    }
    class RewardOption {
        itemID
        info
        itemLevel
        slot
        questID
        questName
        requiredLevel
        zone
        cached
    }
    class InvitationDraft {
        questID
        wording_1_to_3
        previewText
        channelInput
    }
    class LootDrop {
        itemID
        item
        instanceKey
        instanceName
        who
        difficulty
        provider
        sourceID
        kind
    }
    class EquipmentGroup {
        key_normalized_name
        representative_source_fields
        sources
        itemIDs
        versions
        routes_or_suppliers
    }
    EquipmentGroup --> RewardOption : quest sources and routes
    EquipmentGroup --> LootDrop : dungeon sources and suppliers
    class DungeonRecord {
        key
        name
        count
        instanceID_optional
        subzones_localized_names
    }
    LootDrop --> DungeonRecord : instanceKey
    class NativeItemInfo {
        name
        link
        quality
        level
        required
        slot
        kind
        sub
        texture
    }
    RewardOption --> NativeItemInfo : info
    LootDrop --> NativeItemInfo : item.info
    class EquipmentFilter {
        category
        subtype
        slot
        mode
        sort
        min_optional
        max_optional
        stats_three_conditions
    }
    class StatCondition {
        stat_optional
        min_1_to_100000
    }
    EquipmentFilter --> StatCondition : three AND conditions
    class LearnedSpellRank {
        id
        name
        rank_numeric
        index
        ambiguous_optional
    }
    Namespace --> LearnedSpellRank : spellRanks builds ephemeral highest-rank catalogue
    class ZoneLevelRange {
        id
        name
        x_normalized
        y_normalized
        min_optional
        max_optional
    }
    Namespace --> ZoneLevelRange : zoneLevels builds viewed-map labels from native data
    Namespace --> EquipmentFilter : equipmentUI owns session filters
    Namespace --> LootDrop : loot builds an on-demand index
    Namespace --> InvitationDraft : adventure session-only composer
    Settings --> WaterNote : fishingWaters indexed by local numeric ID
    Namespace --> RewardOption : rewards builds ephemeral catalogue
    Namespace --> Settings : ns.db aliases QuestSharingDB
```

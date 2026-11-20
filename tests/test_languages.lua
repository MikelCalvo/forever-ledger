-- Game text read by ID or the game's own names, so any game language works (Frank,
-- November 19: "make it so that translation to any language will work as well as possible").
local T = ...
local ns = T.ns

T.test("Languages: every quest-item quest has its quest IDs", function()
  local missing = {}
  for _, q in ipairs(ns.QUEST_LIST) do
    if not (ns.QUEST_IDS[q[1]] and #ns.QUEST_IDS[q[1]] > 0) then missing[#missing + 1] = q[1] end
  end
  T.eq(table.concat(missing, ", "), "")
  for _, q in ipairs(ns.QUEST_LIST) do
    T.ok(ns.QUEST_ZONE_MAPS[q[2]] or q[2] == "a capital city" or q[2] == "Blackrock Depths", "a map for " .. q[2])
  end
end)

T.test("Languages: a quest is done by ID, any of them, or all for a group", function()
  local done = { [7802] = true, [2581] = true }
  local isDone = function(id) return done[id] or false end
  T.eq(ns.QuestDoneByID(ns.QUEST_IDS["A Donation of Wool"], isDone), true, "one city's donation")
  T.eq(ns.QuestDoneByID(ns.QUEST_IDS["Stocking Jetsteam"], isDone), false)
  T.eq(ns.QuestDoneByID(ns.QUEST_IDS["Blasted Lands quests (five)"], isDone), false, "one of five isn't the group")
  T.eq(ns.QuestDoneByID(nil, isDone), nil)
end)

T.test("Languages: professions keyed in English from the game's skill line", function()
  T.eq(ns.ProfessionKey("Verzauberkunst", 333), "Enchanting")
  T.eq(ns.ProfessionKey("Verzauberkunst"), "Enchanting", "a name seen with its skill line before")
  T.eq(ns.ProfessionKey("Schneiderei", 197), "Tailoring")
  T.eq(ns.ProfessionKey("Tailoring"), "Tailoring", "English as is")
  local profs = { ["Алхимия"] = { rank = 50, recipes = { [1] = true } } }
  ns.MoveProfessionKey(profs, "Алхимия", "Alchemy")
  T.eq(profs["Алхимия"], nil)
  T.eq(profs.Alchemy.rank, 50, "an old entry under the game's name moves over")
end)

T.test("Languages: the Trade channel found by the game's channel number", function()
  local channels = { { number = 1, name = "Allgemein - Sturmwind" }, { number = 2, name = "Handel - Sturmwind" },
    { number = 4, name = "Handel (Dienstleistungen)" } }
  local zones = { [1] = 1, [2] = 2, [4] = 42 }
  local n = ns.PickAdChannel(channels, function(number) return zones[number] end)
  T.eq(n, 2)
  T.eq(ns.PickAdChannel({ { number = 3, name = "Trade - City" } }, function() end), 3, "English name when the game doesn't say")
  T.eq(ns.PickAdChannel({ { number = 5, name = "Trade (Services)" } }, function() end), 5)
end)

T.test("Languages: words for the customer finder from the language's file", function()
  local words, asking, offering = { Enchanting = { "enchanter" } }, { "lf" }, { "wts" }
  local services = { { key = "mage", words = { "water" } } }
  ns.AddChatWords({ asking = { "ищу" }, offering = { "продам" }, professions = { Enchanting = { "чант" } }, services = { mage = { "вода" } } },
    words, asking, offering, services)
  T.eq(asking[2], "ищу"); T.eq(offering[2], "продам"); T.eq(words.Enchanting[2], "чант"); T.eq(services[1].words[2], "вода")
end)

T.test("Languages: Arcane Salvager and riding by the game's own names", function()
  local real = ns.SpellName
  ns.SpellName = function(id) return ({ [33388] = "Верховая езда (ученик)" })[id] end
  local ok, err = pcall(function()
    T.ok(ns.IsRidingName("Верховая езда (ученик)"), "the game's name for the riding spell")
    T.ok(ns.IsRidingName("Journeyman Riding"), "English fallback")
    T.ok(not ns.IsRidingName("Огненный шар"))
  end)
  ns.SpellName = real
  if not ok then error(err, 0) end
end)

T.test("Languages: two entries for one profession merge, keeping every recipe", function()
  -- (Codex review, November 19: the English entry was kept whole and newer recipes saved
  -- under the game's name were dropped.)
  local profs = {
    Enchanting = { rank = 150, max = 150, updated = 100, recipes = { [771001] = { n = "old" }, [771003] = { n = "old copy" } } },
    Verzauberkunst = { rank = 160, max = 225, updated = 200, recipes = { [771002] = { n = "new" }, [771003] = { n = "new copy" } } },
  }
  T.ok(ns.MoveProfessionKey(profs, "Verzauberkunst", "Enchanting"))
  local p = profs.Enchanting
  T.eq(profs.Verzauberkunst, nil)
  T.ok(p.recipes[771001] and p.recipes[771002], "both entries' recipes kept")
  T.eq(p.recipes[771003].n, "new copy", "the newer entry's copy of a shared recipe")
  T.eq(p.rank, 160); T.eq(p.max, 225); T.eq(p.updated, 200)
end)

T.test("Languages: a partner's professions under a known translated name are moved, unknown ones kept", function()
  local saved = ns.db.profAliases
  ns.db.profAliases = { ["Schneiderei"] = "Tailoring" }
  ns.db.chars["Testpartner Zwei-PvE"] = { profs = { Schneiderei = { rank = 75, updated = 5, recipes = { [5] = {} } }, Unbekannt = { rank = 1, recipes = {} } } }
  local ok, err = pcall(function()
    T.ok(ns.NormalizeProfessions(ns.db))
    local c = ns.db.chars["Testpartner Zwei-PvE"]
    T.eq(c.profs.Tailoring.rank, 75)
    T.eq(c.profs.Schneiderei, nil)
    T.ok(c.profs.Unbekannt, "a name not known yet stays")
    T.eq(ns.NormalizeProfessions(ns.db), false, "nothing more to move")
  end)
  ns.db.chars["Testpartner Zwei-PvE"], ns.db.profAliases = nil, saved
  if not ok then error(err, 0) end
end)

T.test("Languages: a channel number learned from chat isn't trusted once the channel changed", function()
  -- (Codex review, November 19: Trade left and its number reused for a custom channel.)
  local realChat = C_ChatInfo
  C_ChatInfo = nil
  local ok, err = pcall(function()
    local seen = ns.AdZoneSeen
    wipe(seen)
    seen[2] = { zone = 2, name = "Trade - City" }
    T.eq(ns.AdZoneChannel(2, "Trade - City"), 2, "the same channel")
    T.eq(ns.AdZoneChannel(2, "Friends"), nil, "another channel by that number")
    C_ChatInfo = { GetChannelInfoFromIdentifier = function(name) return { zoneChannelID = name == "Friends" and 0 or 2 } end }
    T.eq(ns.AdZoneChannel(2, "Friends"), 0, "the game's answer first")
    T.eq(ns.PickAdChannel({ { number = 2, name = "Friends" } }, ns.AdZoneChannel), nil, "no ad to a custom channel")
    wipe(seen)
  end)
  C_ChatInfo = realChat
  if not ok then error(err, 0) end
end)

T.test("Languages: a bag's slots read from its tooltip line in the client's own format", function()
  local file = assert(io.open("Tooltip.lua", "rb"))
  local code = file:read("*a"):gsub("\r\n", "\n"); file:close()
  local chunk = assert(code:match("\n(local bagSlots.-\nlocal SLOTS_PATTERN[^\n]*)"))
  local real = CONTAINER_SLOTS
  local function slots(format, line)
    CONTAINER_SLOTS = format
    local pattern = assert(loadstring(chunk .. "\nreturn SLOTS_PATTERN"))()
    return line:match(pattern)
  end
  local ok, err = pcall(function()
    T.eq(slots("%d Slot %s", "10 Slot Bag"), "10", "English")
    T.eq(slots("%d Slot %s", "Blue Leather Bag"), nil, "a line that isn't the slots")
    local ru = "%2$s (%1$d |4ячейка:ячейки:ячеек;)"
    T.eq(slots(ru, "Сумка (8 ячеек)"), "8", "Russian, as shown")
    T.eq(slots(ru, "Сумка (1 |4ячейка:ячейки:ячеек;)"), "1", "Russian, before the client picks the word form")
    T.eq(slots(ru, "Синяя кожаная сумка"), nil, "the bag's name")
    T.eq(slots(ru, "Требуется (10-й уровень)"), nil, "another line with brackets")
    T.eq(slots("%2$s [%1$d slots]. +", "Bag [10 slots]. +"), "10", "brackets, a dot and a plus")
  end)
  CONTAINER_SLOTS = real
  if not ok then error(err, 0) end
end)

T.test("Languages: the five Blasted Lands deliveries", function()
  local done = { [2581] = true, [2583] = true, [2585] = true, [2601] = true, [2603] = true }
  T.eq(ns.QuestDoneByID(ns.QUEST_IDS["Blasted Lands quests (five)"], function(id) return done[id] or false end), true)
end)

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

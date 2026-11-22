-- RecipesTab.lua: the Professions tab's Where from filter (November 16).
local T = ...
local ns = T.ns

T.test("Professions: Where from groups a recipe's source", function()
  local kind = ns.RecipeSourceKind
  T.eq(kind(nil, false), "trainer", "nothing seen and no recipe item: a trainer (or new in Forever)")
  T.eq(kind(nil, true), "unseen", "a recipe item nobody has spotted")
  T.eq(kind({ kind = "mob" }), "drop"); T.eq(kind({ kind = "drop" }), "drop")
  T.eq(kind({ kind = "vendor" }), "vendor"); T.eq(kind({ kind = "trainer" }), "trainer")
  T.eq(kind({ kind = "quest" }), "quest"); T.eq(kind({ kind = "ah" }), "ah")
end)

T.test("Professions: recipes from the game data show the client's own name", function()
  local oldF, oldSpell = ns.FOREVER_CRAFTS, GetSpellInfo
  ns.FOREVER_CRAFTS = {
    { id = 97201, prof = "Alchemy", n = "Minor Healing Potion", out = 97202, low = 1, high = 1, r = { { 97203, 1 } } },
    { id = 97204, prof = "Alchemy", n = "Unknown Brew", out = 97205, low = 1, high = 1, r = { { 97203, 1 } } },
  }
  GetSpellInfo = function(id) if id == 97201 then return "Малое лечебное зелье" end end
  local book = ns.ForeverRecipeBook("Alchemy")
  T.eq(book[97201].n, "Малое лечебное зелье")
  T.eq(book[97201].en, "Minor Healing Potion", "the English name stays for the Classic data")
  T.eq(book[97204].n, "Unknown Brew", "a spell the client doesn't have keeps the data's name")
  ns.FOREVER_CRAFTS, GetSpellInfo = oldF, oldSpell
end)

T.test("Professions: the list is built over several frames, the same as in one go", function()
  -- (Frank's /fl perf, November 21: up to 101 ms in one go on opening the tab.)
  local R = ns._recipesTest
  local book = {}
  for i = 1, 300 do book[98000 + i] = { n = ("Test Recipe %03d"):format(i) } end
  ns.db.recipeBook.Testcraft = book
  local s = R.settings()
  s.view, s.skill, s.source, s.type, s.group, s.least, s.sort = "all", "all", "all", "all", "all", 0, nil
  local whole = R.buildList("Testcraft", s, "")
  T.eq(whole.total, 300)
  local realClock, ms = debugprofilestop, 0
  local result
  local ok, err = pcall(function()
    debugprofilestop = function() ms = ms + 1; return ms end   -- (each look at the clock: 1 ms)
    ns.RunInSlices("Recipes list test", function() return R.buildList("Testcraft", s, "") end, function(r) result = r end)
    T.eq(result, nil, "not all in the first frame")
    T.runTimers()
  end)
  debugprofilestop = realClock
  ns.db.recipeBook.Testcraft = nil
  T.runTimers()
  assert(ok, err)
  T.ok(result, "finished")
  T.eq(result and result.total, 300)
  T.eq(result and #result.list, #whole.list)
  for i = 1, #whole.list do T.eq(result.list[i].id, whole.list[i].id, "row " .. i) end
end)

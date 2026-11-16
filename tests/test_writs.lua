-- Writs.lua: Craftsman's Writs (Frank, November 16): the order a writ item is, and what
-- filling it costs per point of reputation.
local T = ...
local ns, S = T.ns, T.S

T.test("Writs: 150 orders, each with a profession, tier and item", function()
  T.eq(#ns.WRITS, 150)
  local per = {}
  for _, e in ipairs(ns.WRITS) do
    T.ok(e.item and e.prof and ns.WRIT_TIERS[e.tier], "order " .. e.n)
    per[e.prof] = (per[e.prof] or 0) + 1
  end
  for _, p in ipairs({ "Alchemy", "Blacksmithing", "Engineering", "Leatherworking", "Tailoring" }) do T.eq(per[p], 30, p) end
end)

T.test("Writs: a writ item is found by its ID, its name, or its sealed tier", function()
  local e = ns:WritFor(264012)
  T.eq(e.item, 3383, "Elixir of Wisdom by the writ's ID")
  ns.db.itemNames[3391] = "Elixir of Ogre Strength"
  ns.db.itemNames[999001] = "Craftsman's Writ: Elixir of Ogre Strength"
  local ogre = ns:WritFor(999001)
  T.ok(ogre, "by name, for a writ whose ID isn't known")
  T.eq(ogre and ogre.item, 3391)
  local _, tier = ns:WritFor(262889)
  T.eq(tier.label, "Expert")
  ns.db.itemNames[999002] = "Sealed Artisan's Writ"
  _, tier = ns:WritFor(999002)
  T.eq(tier and tier.label, "Artisan")
  T.eq(ns:WritFor(2589), nil, "linen cloth is no writ")
end)

T.test("Writs: cost per reputation after the coin pouch", function()
  T.eq(ns.WritPerRep(10800, "J"), 100, "(10800 - 3300) / 75")
  T.ok(ns.WritPerRep(1000, "J") < 0, "a cheap order: the pouch pays more")
  T.eq(ns.WritPerRep(nil, "J"), nil)
  local key = ns.MarketKey()
  ns.db.prices[key] = ns.db.prices[key] or {}
  ns.db.prices[key][3383] = { m = 900, a = 900, q = 5, l = "900:5", t = S.now }
  local c = ns:WritCost(ns:WritFor(264012))
  T.ok(c, "priced from the auction house")
  T.eq(c and c.total, 900)
  T.eq(c and c.plan[3383].bought, 1)
end)

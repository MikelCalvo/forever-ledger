-- The neutral auction house against yours (Values.lua ns:NeutralCompare): each side after
-- its own cut, 15% at the neutral one (Booty Bay mail, October 5), and neutral prices
-- never read as your own.
local T = ...
local ns = T.ns
local ID = 2589
local HOME, NEUTRAL = "Testrealm|Alliance", "Testrealm|Neutral"

local function prices(here, there)
  ns.db.settings.ahCut = 5
  ns.neutralAH = nil
  ns.db.prices[HOME] = here and { [ID] = { m = here, q = 10, t = T.S.now } } or {}
  ns.db.prices[NEUTRAL] = there and { [ID] = { m = there, q = 3, t = T.S.now } } or {}
end

T.test("Selling there: both prices after their own cut", function()
  prices(1000, 2000)
  local c = ns:NeutralCompare(ID)
  T.eq(c.netHere, 950, "5% here")
  T.eq(c.netThere, 1700, "15% there")
  T.eq(c.gain, 750)
  T.eq(c.listedThere, 3)
end)

T.test("Buying there and selling here", function()
  prices(1000, 600)
  local c = ns:NeutralCompare(ID)
  T.eq(c.buyProfit, 350, "950 after the cut here, minus 600")
  T.ok(c.gain < 0, "not worth selling there")
end)

T.test("Nothing to compare without both prices", function()
  prices(1000, nil)
  T.eq(ns:NeutralCompare(ID), nil)
  prices(nil, 1000)
  T.eq(ns:NeutralCompare(ID), nil)
end)

T.test("A neutral auctioneer is found by the zone's map number, in any language", function()
  -- (GitHub #23, November 19: an EU player's Booty Bay scans were saved as their faction's.)
  local oldExists, oldFaction, oldMap, oldSub, oldMini = UnitExists, UnitFactionGroup, C_Map, GetSubZoneText, GetMinimapZoneText
  local npcFaction, map = nil, 1434
  UnitExists = function(u) return u == "npc" end
  UnitFactionGroup = function(u) if u == "npc" then return npcFaction end return "Alliance" end
  C_Map = { GetBestMapForUnit = function() return map end }
  GetSubZoneText = function() return "Baie-du-Butin" end
  GetMinimapZoneText = function() return "Baie-du-Butin" end
  local ok, err = pcall(function()
    T.eq(ns.IsNeutralAuctioneer(), true, "Booty Bay in French, by Stranglethorn's map")
    map = 1446; T.eq(ns.IsNeutralAuctioneer(), true, "Gadgetzan")
    map = 1452; T.eq(ns.IsNeutralAuctioneer(), true, "Everlook")
    map = 1453; T.eq(ns.IsNeutralAuctioneer(), false, "Stormwind")
    npcFaction, map = "Alliance", 1434
    T.eq(ns.IsNeutralAuctioneer(), false, "an auctioneer with a faction never is")
    npcFaction, C_Map = nil, nil
    GetSubZoneText = function() return "Booty Bay" end
    T.eq(ns.IsNeutralAuctioneer(), true, "without a map, the English town name")
  end)
  UnitExists, UnitFactionGroup, C_Map, GetSubZoneText, GetMinimapZoneText = oldExists, oldFaction, oldMap, oldSub, oldMini
  assert(ok, err)
end)

T.test("Away from Booty Bay your prices are your faction's", function()
  prices(1000, 5000)
  T.eq(ns.MarketKey(), HOME)
  T.eq(ns.db.prices[ns.MarketKey()][ID].m, 1000, "the neutral price isn't read as yours")
end)

local T = ...
local ns = T.ns
local api = ForeverLedgerAPI
local LEATHER, HIDE, BOOTS, GONE, COPIED = 2319, 4234, 2307, 4304, 8170

local function prices()
  ns.db.lastFullScan = 5000
  ns.db.prices[ns.MarketKey()] = {
    [LEATHER] = { m = 40, a = 52, q = 30, l = "40:5,45:12,60:30", t = 4000, src = "full" },
    [HIDE] = { m = 300, a = 280, q = 3, t = 3000, src = "scan" },
    [BOOTS] = { m = 900, a = 900, q = 50, l = "900:2,950:4", t = 4500, src = "full" },
    [GONE] = { t = 4800, src = "full", none = true },
    [COPIED] = { m = 70, a = 70, t = 4900, src = "Auctionator" },
  }
end

T.test("API: the price is the typical one, never under the cheapest, with how many are listed and when", function()
  prices()
  T.eq(api.version, 1)
  local price, cheapest, listed, seen = api.GetPrice(LEATHER)
  T.eq(price, 52, "typical")
  T.eq(cheapest, 40, "cheapest")
  T.eq(listed, 30, "listed")
  T.eq(seen, 4000, "seen")
  T.eq((api.GetPrice(HIDE)), 300, "a typical price under the cheapest gives the cheapest")
end)

T.test("API: none listed has no price but a time, an item never seen has nothing", function()
  prices()
  local price, cheapest, listed, seen = api.GetPrice(GONE)
  T.eq(price, nil, "price")
  T.eq(cheapest, nil, "cheapest")
  T.eq(listed, 0, "listed")
  T.eq(seen, 4800, "seen")
  T.eq(select("#", api.GetPrice(1)), 0, "never seen")
  T.eq(api.GetPrice("2319"), nil, "an ID that isn't a number")
end)

T.test("API: prices copied from another addon are not handed out as ours", function()
  prices()
  T.eq(api.GetPrice(COPIED), nil, "price")
  T.eq(api.GetListings(COPIED), nil, "listings")
  T.eq(api.GetCost(COPIED, 5), nil, "cost")
end)

T.test("API: listings are the last scan's price levels, each with its own count", function()
  prices()
  local list, listed, seen = api.GetListings(LEATHER)
  T.same(list, { { price = 40, count = 5 }, { price = 45, count = 7 }, { price = 60, count = 18 } })
  T.eq(listed, 30, "listed")
  T.eq(seen, 4000, "seen")
  T.same((api.GetListings(HIDE)), { { price = 300, count = 3 } }, "a record without levels: its cheapest, all listed")
  T.same((api.GetListings(GONE)), {}, "none listed")
end)

T.test("API: the cost of many walks up the levels and says how many it could price", function()
  prices()
  local total, got, seen = api.GetCost(LEATHER, 10)
  T.eq(total, 5 * 40 + 5 * 45, "ten")
  T.eq(got, 10, "all ten priced")
  T.eq(seen, 4000, "seen")
  total, got = api.GetCost(LEATHER, 100)
  T.eq(total, 5 * 40 + 7 * 45 + 18 * 60, "more than are listed")
  T.eq(got, 30, "only what is listed")
  total, got = api.GetCost(BOOTS, 10)
  T.eq(total, 2 * 900 + 2 * 950, "past the saved levels nothing is guessed")
  T.eq(got, 4, "priced")
  total, got = api.GetCost(GONE, 3)
  T.eq(total, nil, "none listed: no cost")
  T.eq(got, 0, "none listed: none priced")
  T.eq(api.GetCost(LEATHER, 0), nil, "no quantity")
end)

T.test("API: the usual price is the week's unless another window is asked for", function()
  prices()
  local real = ns.UsualPrice
  ns.UsualPrice = function(_, id, window)
    if id == LEATHER then return window == "month" and 48 or 50, 6 end
    return nil, 0
  end
  local ok, err = pcall(function()
    local price, points = api.GetUsualPrice(LEATHER)
    T.eq(price, 50, "week")
    T.eq(points, 6, "points")
    T.eq((api.GetUsualPrice(LEATHER, "month")), 48, "month")
    T.eq(api.GetUsualPrice(LEATHER, "decade"), nil, "a window that doesn't exist")
    T.eq(api.GetUsualPrice(HIDE), nil, "no history")
  end)
  ns.UsualPrice = real
  assert(ok, err)
end)

T.test("API: the last full scan's time", function()
  prices()
  T.eq(api.GetLastFullScan(), 5000)
end)

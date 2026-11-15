local _, ns = ...

---------------------------------------------------------------------------
-- The cheapest way to get a number of items, buying or making each one (redesign,
-- Frank's comment on the Gold making mockup, November 15: a Felblood Soul Bag needs 4
-- Bolts of Runecloth: buy the few cheap bolts listed, make the rest from Runecloth, and
-- never count both the bolts and the cloth). Pure, for the tests; Gold making and
-- shopping lists will call it.
--
-- Each unit is filled from whichever is cheapest next:
--   your bags      first, at what they'd sell for (opts.ownedFree: at no cost)
--   the AH         the next listing on its price ladder (cheapest first; each used once)
--   a vendor       its price, as many as wanted
--   a craft        one more made from the cheapest of its materials, worked out the
--                  same way (a recipe's own materials can be made too, up to MAX_DEPTH)
-- so a thin cheap end on the auction house is used, then making takes over when that
-- gets dearer. Every unit is counted once, bought or made, never both.
--
-- sourceOf(id) returns { ladder = { { price, count }, ... } (cheapest first) or nil,
--   vendor = copper each or nil, recipe = { makes = n, mats = { { id, qty }, ... } } or
--   nil, owned = count in your bags or nil, ownedValue = copper each or nil }.
-- need = { [id] = units }. Returns total copper (nil if something can't be had) and the
-- plan: { [id] = { owned = n, bought = n, boughtCost = c, vendor = n, vendorCost = c,
--   made = n, top = highest AH price paid } }.
---------------------------------------------------------------------------
local MAX_DEPTH = 4

function ns.CraftPlan(need, sourceOf, opts)
  opts = opts or {}
  local cache, pos, ownedLeft, plan = {}, {}, {}, {}
  local function src(id)
    local s = cache[id]
    if s == nil then
      s = sourceOf(id) or {}
      cache[id] = s
      ownedLeft[id] = s.owned or 0
      pos[id] = { level = 1, used = 0 }
    end
    return s
  end
  local function entry(id)
    plan[id] = plan[id] or { owned = 0, bought = 0, boughtCost = 0, vendor = 0, vendorCost = 0, made = 0 }
    return plan[id]
  end
  -- The next AH listing's price, without taking it.
  local function nextListing(id)
    local s, p = src(id), pos[id]
    local ladder = s.ladder or {}
    local level, used = p.level, p.used
    while ladder[level] and used >= ladder[level][2] do level, used = level + 1, 0 end
    return ladder[level] and ladder[level][1] or nil
  end

  local unitCost, take
  -- What one more unit costs now, and from where, without taking anything.
  -- (The craft's estimate peeks at each material's next units the same way.)
  local function peek(id, n, depth)
    -- n units of id, walking its sources without taking them.
    local s = src(id)
    local total, owned = 0, ownedLeft[id]
    local ladder = s.ladder or {}
    local p = pos[id]
    local level, used = p.level, p.used
    local craftEach = (depth < MAX_DEPTH and s.recipe) and unitCost(id, depth + 1, true) or nil
    for _ = 1, n do
      local best
      if owned > 0 then
        best = opts.ownedFree and 0 or (s.ownedValue or 0)
        owned = owned - 1
      else
        while ladder[level] and used >= ladder[level][2] do level, used = level + 1, 0 end
        local listing = ladder[level] and ladder[level][1]
        best = listing
        if s.vendor and (not best or s.vendor < best) then best = s.vendor end
        if craftEach and (not best or craftEach < best) then best = craftEach end
        if not best then return nil end
        if best == listing then used = used + 1 end
      end
      total = total + best
    end
    return total
  end
  -- The cost of making one more of id (per unit), or nil.
  unitCost = function(id, depth, onlyCraft)
    local s = src(id)
    if not (s.recipe and depth <= MAX_DEPTH) then return nil end
    local total = 0
    for _, m in ipairs(s.recipe.mats or {}) do
      local c = peek(m[1], m[2], depth)
      if not c then return nil end
      total = total + c
    end
    local each = total / math.max(s.recipe.makes or 1, 1)
    if onlyCraft then return each end
    return each
  end

  -- Takes n units of id, cheapest first. Returns the copper, or nil if it can't be had.
  take = function(id, n, depth)
    local s = src(id)
    local e = entry(id)
    local total = 0
    local made = 0   -- units still to hand out from a craft that makes several
    for _ = 1, n do
      if made > 0 then
        -- The next one from the batch already made: its share of the batch.
        made = made - 1
        total = total + (e.batchEach or 0)
      elseif ownedLeft[id] > 0 then
        ownedLeft[id] = ownedLeft[id] - 1
        e.owned = e.owned + 1
        total = total + (opts.ownedFree and 0 or (s.ownedValue or 0))
      else
        local listing = nextListing(id)
        local craftEach = (depth < MAX_DEPTH and s.recipe) and unitCost(id, depth + 1) or nil
        local best, how = listing, "ah"
        if s.vendor and (not best or s.vendor < best) then best, how = s.vendor, "vendor" end
        if craftEach and (not best or craftEach < best) then best, how = craftEach, "craft" end
        if not best then return nil end
        if how == "ah" then
          local p = pos[id]
          local ladder = s.ladder
          while ladder[p.level] and p.used >= ladder[p.level][2] do p.level, p.used = p.level + 1, 0 end
          p.used = p.used + 1
          e.bought, e.boughtCost = e.bought + 1, e.boughtCost + listing
          e.top = math.max(e.top or 0, listing)
          total = total + listing
        elseif how == "vendor" then
          e.vendor, e.vendorCost = e.vendor + 1, e.vendorCost + s.vendor
          total = total + s.vendor
        else
          -- Make one batch: take its materials for real.
          local batch = 0
          for _, m in ipairs(s.recipe.mats) do
            local c = take(m[1], m[2], depth + 1)
            if not c then return nil end
            batch = batch + c
          end
          local makes = math.max(s.recipe.makes or 1, 1)
          e.made = e.made + makes
          made = makes - 1
          total = total + batch / makes   -- this unit's share; the rest come with the batch
          e.batchEach = batch / makes
        end
      end
    end
    -- Units of a batch beyond what was needed are left over (counted at their share, so
    -- the whole batch is paid for; a leftover isn't handed to another recipe yet).
    if made > 0 then total = total + made * (e.batchEach or 0) end
    return total
  end

  local total = 0
  for id, n in pairs(need) do
    local c = take(id, n, 0)
    if not c then return nil, plan end
    total = total + c
  end
  return math.floor(total + 0.5), plan
end

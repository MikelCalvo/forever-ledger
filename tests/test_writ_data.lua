-- The generated reference file must not fabricate actionable quest requirements.
local T = ...
local data = T.ns.WRIT_DATA

T.test("Writ data: all pinned client orders keep distinct writ and quest IDs", function()
  T.eq(data.build, "1.60.1.70938")
  T.eq(#data.orders, 150)
  T.eq(data.complete, false)
  local writs, quests = {}, {}
  for _, e in ipairs(data.orders) do
    T.ok(not writs[e.writ] and not quests[e.quest], "distinct writ and quest")
    writs[e.writ], quests[e.quest] = true, true
    T.eq(e.questPresent, true)
    T.eq(e.complete, false)
    T.eq(e.qty, nil, "missing requirement must not become quantity 1")
    T.eq(e.tier, nil, "sealed name or ID range does not prove an order's tier")
    T.eq(e.skill, nil, "craft minimum is not skill to learn")
    T.eq(e.who, nil)
    T.eq(e.zone, nil)
    T.eq(e.coinPouch, nil)
    T.eq(e.reputation, nil)
  end
end)

T.test("Writ data: preserve all sealed identities and unresolved name collisions", function()
  T.eq(#data.sealed, 6)
  local sealed, orders = {}, {}
  for _, e in ipairs(data.sealed) do sealed[e.item] = e end
  for _, e in ipairs(data.orders) do orders[e.writ] = e end
  T.ok(sealed[22568] and sealed[248206], "two plain sealed items share a name, not an ID")
  T.eq(sealed[262887].label, "Apprentice")
  T.eq(sealed[262890].opening[1].spell, 1269675)
  T.eq(orders[264011].quest, 94004, "not an invented sequential quest ID")
  T.eq(orders[264078].item, nil, "two craftable Golden Scale Gauntlets IDs")
  T.eq(#orders[264078].itemCandidates, 2)
  T.eq(orders[264012].item, 3383)
  T.eq(orders[264012].itemBasis, "client name")
  T.eq(#data.coinPouches, 4, "identities only; not an asserted reward link")
end)

T.test("Writs: every order the game data knows is found by its writ's item ID", function()
  local ns = T.ns
  local found = 0
  for _, o in ipairs(ns.WRIT_DATA.orders) do
    if o.item then
      local e = ns:WritFor(o.writ)
      T.ok(e, "writ " .. o.writ .. " is known by its ID")
      T.eq(e and e.item, o.item, "writ " .. o.writ .. " asks for its item")
      found = found + 1
    end
  end
  T.eq(found, 146)
  local ogre = ns:WritFor(264011)
  T.eq(ogre and ogre.item, 3391, "Ogre's Strength / Ogre Strength")
end)

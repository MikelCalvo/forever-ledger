# Writ client data and integration limits

Checked November 18, 2026. `WritsData.lua` is a **partial reference catalog**, not
an actionable replacement for Writs.lua's order requirements yet. Nothing changes
on screen on this branch. UI integration is a separate change.

## Rebuild

```
python tools/build-forever-writs.py
python tools/build-forever-writs.py --offline --cache-dir <download-folder> --check
python -m unittest discover -s tools -p test_forever_writs.py
```

The exact build is **1.60.1.70938**, matching ForeverCrafts. URLs, input byte
counts, row counts and SHA-256 values are in `forever-writs-source.json`.
Downloaded CSVs stay outside the repository. Existing pinned inputs cannot be
silently refreshed; a build update requires reviewing the build and manifest
together. `--check` writes neither generated file. CI checks the generator with
synthetic tables and loads the shipped Lua catalog in the normal test suite;
rebuilding from the full public CSVs was also checked locally.

Wago's current [robots.txt](https://wago.tools/robots.txt) and
[agent instructions](https://wago.tools/llms.txt) explicitly direct tools to CSV
exports and APIs. Only those permitted routes were used. No addon tables, guide
assignments, server emulator data or private player/game caches were imported.
All generated facts come from Wago; table schemas were inspected directly.

## What the public tables establish

- **150 order-item IDs and 150 quest IDs.** ItemSparse's `StartQuestID` links each
  Craftsman's Writ item to a quest. Every quest exists in QuestV2. The first,
  264011, starts **94004**, not the sequential 94211 one might guess from its
  neighbors.
- **146 requested-item name matches.** The writ's English suffix is matched
  case-insensitively to ItemSparse's display name. A duplicate name is resolved
  only when exactly one candidate has a create-item craft in SkillLineAbility
  and SpellEffect. This is labeled `itemBasis = "client name"`: it is useful
  evidence, **not a published quest-objective item-ID link**. A quest capture
  should confirm it before filling orders.
- **Profession and craft routes** for matched craftable items, including each
  craft spell and its `MinSkillLineRank`. Multiple professions are retained as
  separate `crafts` routes; `prof` is supplied only if they agree. Many minimums
  are 1. This is not the skill needed to learn the recipe, nor the guide's
  skill breakpoint. The aggregate uses `craftMinSkill`, deliberately not the
  old UI's `skill` field.
- **Six sealed-item IDs**: 22568 and 248206 both have the name Sealed Craftsman's
  Writ; Apprentice 262887, Journeyman 262888, Expert 262889, Artisan 262890.
  Keep the same-name IDs separate. ItemXItemEffect -> ItemEffect -> SpellEffect
  supplies opening spells for the latter five. No opening effect is published
  for 22568 in these tables; that does not prove whether it is obtainable.
  Each opening has effect 189 with distinct `misc0` values 134596-134600 and
  `misc1` 562. The raw references are retained, **not decoded into order pools**.
- **Four Coin Pouch identities**, 284583-284586. Their existence and names do not
  link them to a writ, establish a payout, or establish which is for which tier.

## What remains unknown

The requested quantities, per-order tier, customer/NPC, delivery zone, reputation
amount/faction and coin-pouch reward links are not present in the exported joins.
QuestV2 has only ID, UniqueBitFlag and UiQuestDetailsThemeID. QuestPOIBlob has
**zero rows for these 150 quests**. It supplies no alternative customer/zone
join. Sealed opening spells supply loot references, but not their contents.

The pinned exports for QuestObjective, QuestV2CliTask, QuestPackageItem,
QuestCache, ItemLoot and Treasure returned HTTP 400 (unavailable for this build).
No blocked page was scraped and no private/server endpoint was substituted.
The available QuestFactionReward and QuestMoneyReward tables contain generic
difficulty schedules, not these quests' reward assignments. Creature, AreaTable
and Faction provide names but no missing per-writ relationship. These checks
cannot establish the full server-side quests or sealed-item loot pools.

Four name mappings remain unresolved and are deliberately not repaired by hand:

| Writ | Client name suffix | Reason |
|---|---|---|
| 264011 | Elixir of Ogre's Strength | Item 3391 is named Elixir of Ogre Strength; spelling differs. |
| 264078 | Golden Scale Gauntlets | Both 9366 and 217273 match and have crafting records. |
| 264089 | Gyromatic Micro-Adjuster | Item 10498 is named Gyromatic Micro-Adjustor. |
| 264116 | Potion of Demonslaying | No exact item display-name match. |

Those are evidence gaps, not permission to copy an addon's assignments. No tier
is inferred from ID intervals, item level, profession skill or the order of rows.
No quantity is inferred from a recipe's output count or an item's stack size.

## Integration contract

`ns.WRIT_DATA` contains `orders`, `sealed`, `coinPouches`, source/build and an
explicit `complete = false`. Each order keeps `writ`, `item` and `prof` where
supported; it adds `name`, `quest`, `questPresent`, `itemBasis`, `itemName`,
`crafts` and `craftMinSkill`. Unresolved item names have `itemCandidates` instead
of `item`. `qty`, `tier`, `skill`, `who`, `zone` and rewards remain **nil**.

**Do not substitute these rows straight into Writs.lua's current defaults.** Its
`qty or 1` and guide-based tier reward assumptions would fabricate requirements
and costs. Use the generated IDs/names now if useful, but gate shopping-list
filling and per-reputation maths on verified quantity/tier/reward evidence, or
keep the existing explicitly separate guide rows until that integration is
designed. Never treat the catalog's absent field as a verified zero.

Completing the requirements needs quest details/requirements, reward and ender
evidence plus sealed-item outcomes from a permitted public source or the live
game. This inert catalog does not claim live quest confirmation. The missing
evidence needs capture rather than guesses in the generated data.

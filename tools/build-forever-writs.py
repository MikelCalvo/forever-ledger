"""Build a partial writ catalog from pinned public Wago client tables.

No server quest/loot tables, addon tables or guide assignments are inferred.
Unknown counts stay absent, never 1. See tools/FOREVER_WRITS.md before integration.
"""
import argparse
import collections
import csv
import hashlib
import io
import json
import pathlib
import tempfile
import urllib.request

BUILD = "1.60.1.70938"
DATE = "2026-11-18"
TABLES = ("ItemSparse", "QuestV2", "QuestPOIBlob", "SkillLine", "SkillLineAbility",
          "SpellEffect", "ItemXItemEffect", "ItemEffect")
PREFIX = "Craftsman's Writ: "
SOURCE = "https://wago.tools"
UNKNOWN = ["qty", "tier", "skill", "who", "zone", "reputation", "rewardFaction", "coinPouch"]


def lua(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        # JSON's Unicode/control escapes aren't Lua 5.1 escapes.
        value = value.replace("\\", "\\\\").replace('"', '\\"')
        for char, replacement in (("\n", "\\n"), ("\r", "\\r"), ("\t", "\\t")):
            value = value.replace(char, replacement)
        if any(ord(c) < 32 for c in value):
            raise ValueError("Unsupported control character in client text")
        return '"' + value + '"'
    if isinstance(value, list):
        return "{ " + ", ".join(lua(v) for v in value) + " }"
    return "{ " + ", ".join(k + " = " + lua(v) for k, v in value.items()) + " }"


def generate(tables):
    items = {int(r["ID"]): r for r in tables["ItemSparse"]}
    names = collections.defaultdict(list)
    for item, row in items.items():
        names[row["Display_lang"].casefold()].append(item)
    # Profession attribution follows a craft's actual output, not the item's usage
    # requirement. Multiple routes/professions remain visible in `crafts`.
    professions = {int(r["ID"]): r["DisplayName_lang"] for r in tables["SkillLine"]
                   if r["CategoryID"] == "11"}
    effects = collections.defaultdict(list)
    for row in tables["SpellEffect"]:
        if row["DifficultyID"] == "0":
            effects[int(row["SpellID"])].append(row)
    crafts = collections.defaultdict(list)
    for row in tables["SkillLineAbility"]:
        prof, spell = int(row["SkillLine"]), int(row["Spell"])
        if prof not in professions:
            continue
        for effect in effects[spell]:
            if effect["Effect"] == "24" and int(effect["EffectItemType"]) > 0:
                craft = dict(id=spell, prof=professions[prof], skill=int(row["MinSkillLineRank"]))
                target = int(effect["EffectItemType"])
                if craft not in crafts[target]:
                    crafts[target].append(craft)
    quests = {int(r["ID"]) for r in tables["QuestV2"]}
    pois = collections.defaultdict(list)
    for row in tables["QuestPOIBlob"]:
        pois[int(row["QuestID"])].append(int(row["ID"]))
    orders = []
    for writ, row in sorted(items.items()):
        name = row["Display_lang"]
        if not name.startswith(PREFIX):
            continue
        candidates = sorted(names.get(name[len(PREFIX):].casefold(), []))
        # Name evidence is explicit. It is not a quest objective assertion. Prefer
        # the sole craftable exact-name candidate when duplicate client names exist.
        craftable = [i for i in candidates if crafts[i]]
        target = candidates[0] if len(candidates) == 1 else craftable[0] if len(craftable) == 1 else None
        quest = int(row["StartQuestID"])
        entry = dict(writ=writ, name=name, source=SOURCE, build=BUILD, complete=False)
        if quest:
            entry.update(quest=quest, questPresent=quest in quests)
            if pois[quest]:
                entry["poiBlobs"] = sorted(pois[quest])
        if target:
            entry.update(item=target, itemBasis="client name", itemName=items[target]["Display_lang"])
            routes = sorted(crafts[target], key=lambda r: (r["prof"], r["skill"], r["id"]))
            if routes:
                entry["crafts"] = routes
                profs = {r["prof"] for r in routes}
                if len(profs) == 1:
                    entry.update(prof=routes[0]["prof"], craftMinSkill=min(r["skill"] for r in routes))
        else:
            entry["itemCandidates"] = candidates
        orders.append(entry)
    item_effects = {int(r["ID"]): r for r in tables["ItemEffect"]}
    links = collections.defaultdict(list)
    for row in tables["ItemXItemEffect"]:
        links[int(row["ItemID"])].append(int(row["ItemEffectID"]))
    sealed, pouches = [], []
    for item, row in sorted(items.items()):
        name = row["Display_lang"]
        if name.startswith("Sealed ") and name.endswith("'s Writ"):
            opening = []
            for link in sorted(links[item]):
                effect = item_effects[link]
                spell = int(effect["SpellID"])
                opening.append(dict(itemEffect=link, spell=spell,
                                    effects=[dict(id=int(e["ID"]), effect=int(e["Effect"]),
                                                  misc0=int(e["EffectMiscValue_0"]),
                                                  misc1=int(e["EffectMiscValue_1"]))
                                             for e in sorted(effects[spell], key=lambda r: int(r["ID"]))]))
            # The label identifies the sealed item's name only; no output pool/tier
            # assignment is inferred from item/quest ID ranges or craft skill.
            sealed.append(dict(item=item, name=name, label=name[7:-7], opening=opening))
        if name == "Coin Pouch":
            pouches.append(dict(item=item, name=name))
    return dict(build=BUILD, source=SOURCE, complete=False, unknown=UNKNOWN,
                orders=orders, sealed=sealed, coinPouches=pouches)


def render(data):
    lines = ["-- Generated by tools/build-forever-writs.py; do not edit.",
             f"-- Wago client build {BUILD}. See tools/FOREVER_WRITS.md for evidence and gaps.",
             "-- INCOMPLETE: absent qty/tier/rewards MUST NOT default to 1/a guessed tier.",
             "local _, ns = ...", "ns.WRIT_DATA = {"]
    for key in ("build", "source", "complete", "unknown"):
        lines.append(f"  {key} = {lua(data[key])},")
    for key in ("orders", "sealed", "coinPouches"):
        lines.append(f"  {key} = {{")
        lines.extend("    " + lua(row) + "," for row in data[key])
        lines.append("  },")
    lines.extend(["}", ""])
    return "\n".join(lines)


def load_tables(cache, pinned, offline):
    tables, sources = {}, {}
    for name in TABLES:
        path = cache / (name + ".csv")
        url = f"{SOURCE}/db2/{name}/csv?version={BUILD}"
        if not path.exists():
            if offline:
                raise ValueError(f"Missing cached table: {path}")
            request = urllib.request.Request(url, headers={"User-Agent": "ForeverLedger-Data/1.0"})
            with urllib.request.urlopen(request, timeout=60) as response:
                raw = response.read()
            # Validate a response before it enters the persistent download cache.
            headers = next(csv.reader(io.StringIO(raw.decode("utf-8-sig"))), [])
            if "ID" not in headers:
                raise ValueError(f"{name}: response is not a table export")
            path.write_bytes(raw)
        raw = path.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        if pinned and (pinned["build"] != BUILD or pinned["tables"][name]["sha256"] != digest):
            raise ValueError(f"{name}: snapshot differs from pinned build; review a new manifest")
        tables[name] = list(csv.DictReader(io.StringIO(raw.decode("utf-8-sig"))))
        sources[name] = dict(url=url, sha256=digest, bytes=len(raw), rows=len(tables[name]))
    return tables, sources


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cache-dir", type=pathlib.Path,
                        default=pathlib.Path(tempfile.gettempdir()) / "fl-forever-public")
    parser.add_argument("--offline", action="store_true")
    parser.add_argument("--check", action="store_true", help="verify generated files without writing")
    args = parser.parse_args()
    repo = pathlib.Path(__file__).resolve().parent.parent
    manifest_path = repo / "tools" / "forever-writs-source.json"
    pinned = json.loads(manifest_path.read_text()) if manifest_path.exists() else None
    if args.check and not pinned:
        raise SystemExit("--check requires the pinned manifest")
    args.cache_dir.mkdir(parents=True, exist_ok=True)
    tables, sources = load_tables(args.cache_dir, pinned, args.offline)
    data = generate(tables)
    coverage = dict(orders=len(data["orders"]), sealed=len(data["sealed"]),
                    nameMatchedItems=sum("item" in r for r in data["orders"]),
                    questIDs=sum("quest" in r for r in data["orders"]),
                    questsPresent=sum(r.get("questPresent", False) for r in data["orders"]),
                    questPOIs=sum("poiBlobs" in r for r in data["orders"]),
                    knownQuantities=0, knownOrderTiers=0, knownRewards=0)
    manifest = dict(build=BUILD, date=DATE, source=SOURCE, tables=sources, coverage=coverage)
    generated = {repo / "WritsData.lua": render(data),
                 manifest_path: json.dumps(manifest, indent=2) + "\n"}
    for path, text in generated.items():
        if args.check:
            if path.read_text(encoding="utf-8") != text:
                raise SystemExit(f"Generated file differs: {path}")
        else:
            path.write_text(text, encoding="utf-8", newline="\n")
    print(json.dumps(coverage, sort_keys=True))


if __name__ == "__main__":
    main()

"""Generator invariants; synthetic public-table shapes, no network dependency."""
import copy
import hashlib
import importlib.util
import pathlib
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("writs", pathlib.Path(__file__).with_name("build-forever-writs.py"))
writs = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(writs)


def fixture():
    tables = {name: [] for name in writs.TABLES}
    tables["ItemSparse"] = [
        {"ID": "100", "Display_lang": "Cloth Hat", "StartQuestID": "0"},
        {"ID": "200", "Display_lang": "Craftsman's Writ: Cloth Hat", "StartQuestID": "300"},
        {"ID": "201", "Display_lang": "Sealed Apprentice's Writ", "StartQuestID": "0"},
        {"ID": "202", "Display_lang": "Coin Pouch", "StartQuestID": "0"},
    ]
    tables["QuestV2"] = [{"ID": "300"}]
    tables["SkillLine"] = [{"ID": "197", "DisplayName_lang": "Tailoring", "CategoryID": "11"}]
    tables["SkillLineAbility"] = [{"SkillLine": "197", "Spell": "400", "MinSkillLineRank": "1"}]
    tables["SpellEffect"] = [{"ID": "500", "DifficultyID": "0", "SpellID": "400", "Effect": "24", "EffectItemType": "100"}]
    return tables


class WritDataTests(unittest.TestCase):
    def test_unknown_count_tier_reward_and_learning_skill_stay_absent(self):
        data = writs.generate(fixture())
        order = data["orders"][0]
        self.assertEqual((order["writ"], order["item"], order["quest"], order["prof"]), (200, 100, 300, "Tailoring"))
        self.assertEqual(order["craftMinSkill"], 1)
        self.assertTrue(order["questPresent"])
        self.assertFalse(order["complete"])
        for key in writs.UNKNOWN:
            self.assertNotIn(key, order)
        self.assertEqual(order["itemBasis"], "client name")

    def test_ambiguous_names_are_not_arbitrarily_resolved(self):
        tables = fixture()
        tables["ItemSparse"].append({"ID": "101", "Display_lang": "Cloth Hat", "StartQuestID": "0"})
        # Both copies can be crafted: neither has evidence for the objective.
        tables["SpellEffect"].append(dict(tables["SpellEffect"][0], ID="501", EffectItemType="101"))
        order = writs.generate(tables)["orders"][0]
        self.assertNotIn("item", order)
        self.assertEqual(order["itemCandidates"], [100, 101])

    def test_only_craftable_exact_name_candidate_is_marked_as_name_evidence(self):
        tables = fixture()
        tables["ItemSparse"].append({"ID": "101", "Display_lang": "Cloth Hat", "StartQuestID": "0"})
        self.assertEqual(writs.generate(tables)["orders"][0]["item"], 100)

    def test_case_fold_is_allowed_but_spelling_aliases_are_not_guessed(self):
        tables = fixture()
        tables["ItemSparse"][0]["Display_lang"] = "cloth hat"
        self.assertEqual(writs.generate(tables)["orders"][0]["item"], 100)
        tables["ItemSparse"][0]["Display_lang"] = "Cloth Hats"
        order = writs.generate(tables)["orders"][0]
        self.assertNotIn("item", order)
        self.assertEqual(order["itemCandidates"], [])

    def test_two_professions_keep_both_routes_without_first_wins(self):
        tables = fixture()
        tables["SkillLine"].append({"ID": "171", "DisplayName_lang": "Alchemy", "CategoryID": "11"})
        tables["SkillLineAbility"].append({"SkillLine": "171", "Spell": "400", "MinSkillLineRank": "50"})
        order = writs.generate(tables)["orders"][0]
        self.assertNotIn("prof", order)
        self.assertEqual(len(order["crafts"]), 2)

    def test_quest_presence_never_creates_requirements_or_reward_links(self):
        tables = fixture()
        tables["QuestV2"] = []
        tables["QuestPOIBlob"] = [{"ID": "600", "QuestID": "300"}]
        order = writs.generate(tables)["orders"][0]
        self.assertFalse(order["questPresent"])
        self.assertEqual(order["poiBlobs"], [600])
        self.assertNotIn("zone", order)
        self.assertNotIn("coinPouch", order)

    def test_sealed_spell_chain_preserved_without_invented_contents(self):
        tables = fixture()
        tables["ItemXItemEffect"] = [{"ID": "700", "ItemID": "201", "ItemEffectID": "701"}]
        tables["ItemEffect"] = [{"ID": "701", "SpellID": "702"}]
        tables["SpellEffect"].append({"ID": "703", "DifficultyID": "0", "SpellID": "702", "Effect": "189", "EffectMiscValue_0": "999", "EffectMiscValue_1": "562"})
        data = writs.generate(tables)
        sealed = data["sealed"][0]
        self.assertEqual(sealed["label"], "Apprentice")
        self.assertEqual(sealed["opening"][0]["effects"][0]["misc0"], 999)
        self.assertNotIn("tier", data["orders"][0])
        self.assertNotIn("contents", sealed)
        self.assertEqual(data["coinPouches"], [{"item": 202, "name": "Coin Pouch"}])

    def test_render_is_stable_after_input_order_changes(self):
        tables = fixture()
        tables["ItemSparse"].append(dict(tables["ItemSparse"][2], ID="203"))
        first = writs.render(writs.generate(tables))
        flipped = copy.deepcopy(tables)
        for rows in flipped.values():
            rows.reverse()
        self.assertEqual(writs.render(writs.generate(flipped)), first)

    def test_lua_names_escape_quotes_backslashes_and_newlines(self):
        self.assertEqual(writs.lua('A "hat"\\\n'), '"A \\"hat\\"\\\\\\n"')
        self.assertEqual(writs.lua(False), "false")
        self.assertEqual(writs.lua(None), "nil")

    def test_pinned_cache_rejects_changed_input_without_writing(self):
        with tempfile.TemporaryDirectory() as temp:
            cache = pathlib.Path(temp)
            raw = b"ID,Display_lang\n100,Hat\n"
            for name in writs.TABLES:
                (cache / (name + ".csv")).write_bytes(raw)
            pin = dict(build=writs.BUILD, tables={name: dict(sha256=hashlib.sha256(raw).hexdigest()) for name in writs.TABLES})
            (cache / (writs.TABLES[0] + ".csv")).write_bytes(raw + b"101,Other\n")
            with self.assertRaisesRegex(ValueError, "snapshot differs"):
                writs.load_tables(cache, pin, True)


if __name__ == "__main__":
    unittest.main()

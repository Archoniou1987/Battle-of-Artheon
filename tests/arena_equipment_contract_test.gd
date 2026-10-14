extends SceneTree
# Arena equipment regression checks. Run with Godot --headless --script.

var errors: Array[String] = []

func _initialize() -> void:
	test_strength()
	test_armour()
	test_critical_rating()
	test_two_weapons()
	for error in errors:
		push_error(error)
	print("Arena equipment checks: %d failures" % errors.size())
	quit(1 if not errors.is_empty() else 0)

func check(ok: bool, description: String) -> void:
	if not ok:
		errors.append(description)

func fixture() -> Dictionary:
	var hero := CharacterState.new("test_hero", "Test")
	hero.progression.base_stats["PAR001"] = 4
	hero.progression.base_stats["PAR003"] = 2
	return {"hero": hero, "repo": ItemRepository.new()}

func put(hero: CharacterState, repo: ItemRepository, id: String, slot: String, extra: Dictionary) -> void:
	var item := {"instance_id": id, "id": id, "item_type": "armour", "equip_slots": [slot], "requirements": {}}
	item.merge(extra, true)
	if not Dictionary(item.get("damage", {})).is_empty():
		item["par_stats"] = {"PAR057":1}
	ItemDurabilityService.initialize_item(item, 100)
	check(repo.add_item(item), id + ": add failed")
	check(hero.receive_item(id, repo), id + ": receive failed")
	check(hero.equip(slot, id, repo), id + ": equip failed")

func test_strength() -> void:
	var f := fixture()
	var hero: CharacterState = f["hero"]
	var repo: ItemRepository = f["repo"]
	put(hero, repo, "test_sword", "main_hand", {"item_type": "weapon", "damage": {"min": 4, "max": 7, "type": "slashing"}})
	put(hero, repo, "test_ring", "ring1", {"par_bonuses": {"PAR001": 25}})
	check(int(hero.effective_stats(repo).get("PAR001", 0)) == 29, "Strength: expected 29")
	var view := CharacterStatsService.snapshot(hero, repo)
	var fighter := CharacterCombatBuilder.build(hero, repo)
	var profiles := WeaponAttackProfile.all(fighter)
	check(not profiles.is_empty(), "Strength: missing combat weapon")
	if not profiles.is_empty():
		check(is_equal_approx(float(profiles[0].get("damage_min", 0)), 33.0), "Strength: combat damage minimum should be 33")
		check(is_equal_approx(float(profiles[0].get("damage_max", 0)), 36.0), "Strength: combat damage maximum should be 36")
	check(view.has("main_hand_damage"), "Strength: missing displayed weapon damage")

func test_armour() -> void:
	var f := fixture()
	var hero: CharacterState = f["hero"]
	var repo: ItemRepository = f["repo"]
	put(hero, repo, "test_chest", "chest", {"armour_by_zone": {"chest": 100}})
	var equipped := CharacterCombatBuilder.build(hero, repo)
	check(is_equal_approx(float(equipped.armour.get("chest", {}).get("slashing", 0)), 100.0), "Armour: chest should be 100")
	hero.unequip("chest", repo)
	var unequipped := CharacterCombatBuilder.build(hero, repo)
	check(is_equal_approx(float(unequipped.armour.get("chest", {}).get("slashing", 0)), 0.0), "Armour: chest should return to zero")

func test_critical_rating() -> void:
	var f := fixture()
	var hero: CharacterState = f["hero"]
	var repo: ItemRepository = f["repo"]
	put(hero, repo, "test_crit_boots", "feet", {"par_stats": {"PAR033": 100}})
	var view := CharacterStatsService.snapshot(hero, repo)
	var fighter := CharacterCombatBuilder.build(hero, repo)
	check(is_equal_approx(float(fighter.combat_stats.get("crit_chance_rating", 0)), 110.0), "Critical: combat rating should be 110")
	check(is_equal_approx(float(view.get("crit_chance_rating", 0)), 110.0), "Critical: displayed rating should be 110")

func test_two_weapons() -> void:
	var f := fixture()
	var hero: CharacterState = f["hero"]
	var repo: ItemRepository = f["repo"]
	put(hero, repo, "test_sword", "main_hand", {"item_type": "weapon", "damage": {"min": 4, "max": 7, "type": "slashing"}})
	put(hero, repo, "test_dagger", "off_hand", {"item_type": "weapon", "damage": {"min": 2, "max": 5, "type": "piercing"}})
	var profiles := WeaponAttackProfile.all(CharacterCombatBuilder.build(hero, repo))
	check(profiles.size() == 2, "Dual wield: expected two weapon profiles")

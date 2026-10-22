extends SceneTree

## Four REAL inventory quickslots for Solo, distinct from ABI slots.
## This checks the immutable read contract before consumable mutations are
## wired to atomic terminal world publication.
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("SOLO_ELIXIR_LOADOUT_CASE=FAIL ",label)

func _initialize() -> void:
	_run()
	print("SOLO_ELIXIR_LOADOUT_TEST=", "PASS" if failures.is_empty() else "FAIL", " failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var hero := CharacterState.new("SOLO_ELIXIR_OWNER","Elixir Owner",5)
	var repo := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repo),"canonical_elixir_fixtures")
	var empty := SoloCombatElixirLoadout.inspect(hero,repo)
	check(bool(empty.get("ok",false)) and int(empty.get("capacity",-1))==0 and Array(empty.get("slots",[])).size()==4,"four_locked_without_belt")
	check(hero.equip("waist","elixir_test_belt_v1",repo),"real_belt_equipped")
	check(hero.elixir_capacity(repo)==4,"belt_unlocks_four_slots")
	check(hero.assign_elixir(0,"elixir_test_hp_v1",repo),"health_slot_assigned")
	check(hero.assign_elixir(1,"elixir_test_mana_v1",repo),"mana_slot_assigned")
	check(hero.assign_elixir(2,"elixir_test_fire_v1",repo),"ward_slot_assigned")
	check(hero.assign_elixir(3,"elixir_test_cleanse_v1",repo),"cleanse_slot_assigned")
	check(not hero.assign_elixir(1,"elixir_test_hp_v1",repo),"same_instance_cannot_fill_two_slots")
	var original_charges: Dictionary = {}
	for id in hero.elixir_slots:
		original_charges[id] = int(repo.get_item(id).get("charges",-1))
	var snapshot := JSON.stringify(repo.to_dict())
	var view := SoloCombatElixirLoadout.inspect(hero,repo)
	check(bool(view.get("ok",false)) and int(view.get("capacity",-1))==4,"live_belt_capacity")
	var entries: Array = view.get("slots",[])
	check(entries.size()==4,"four_slot_contract")
	for i in range(entries.size()):
		var entry: Dictionary = entries[i]
		var id := String(entry.get("instance_id",""))
		check(bool(entry.get("unlocked",false)) and bool(entry.get("valid",false)) and int(entry.get("slot",-1))==i,"slot_"+str(i)+"_validated")
		check(id==hero.elixir_slots[i],"slot_"+str(i)+"_preserves_item_identity")
		check(int(entry.get("charges",-1))==int(original_charges.get(id,-2)),"slot_"+str(i)+"_preserves_charges")
	check(JSON.stringify(repo.to_dict())==snapshot,"readout_never_consumes_charge")
	# A real charge mutation is reflected by the readout, but reading the
	# loadout itself must never mutate the owned item instance.
	var item: Dictionary = repo.get_item("elixir_test_hp_v1")
	var charges := int(item.get("charges",0))
	item["charges"] = charges-1
	check(repo.update_item(item),"test_fixture_charge_update")
	var after := SoloCombatElixirLoadout.inspect(hero,repo)
	check(bool(after.get("ok",false)) and int(Array(after.get("slots",[]))[0].get("charges",-1))==charges-1,"view_reflects_canonical_repository_charges")
	check(not hero.assign_elixir(0,"elixir_test_hp_v1",repo),"slot_does_not_reassign_existing_instance")
	var invalid_owner := CharacterState.new("DIFFERENT_PLAYER","Impostor",5)
	invalid_owner.elixir_slots[0] = "elixir_test_hp_v1"
	var rejected := SoloCombatElixirLoadout.inspect(invalid_owner,repo)
	check(not bool(rejected.get("ok",false)),"another_character_cannot_read_owned_quickslot")
	# The validator rejects a now-broken, formerly valid consumable rather
	# than silently presenting it as usable.
	var broken: Dictionary = repo.get_item("elixir_test_mana_v1")
	broken["elixir_components"] = []
	check(repo.update_item(broken),"corrupt_item_fixture_updated")
	var corrupted := SoloCombatElixirLoadout.inspect(hero,repo)
	check(bool(corrupted.get("ok",false)) and not bool(Array(corrupted.get("slots",[]))[1].get("valid",true)),"invalid_components_not_available")

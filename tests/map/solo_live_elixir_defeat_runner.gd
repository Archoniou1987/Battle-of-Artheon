extends SceneTree

## Audit regression: losing a REAL live fight does not refund a potion.
## The loss is published through the same stage/recover contract as gameplay.
const EXP := "user://test_elixir_defeat_exp.json"
const TOWN := "user://test_elixir_defeat_town.json"
const MANIFEST := "user://test_elixir_defeat_manifest.json"
const ID := "solo_exp_elixir_defeat"
const PLAYER := "player"
const NPC := "solo_npc_bandit_01"
const START := Vector2i(6,5)
const TARGET := Vector2i(7,5)
const ELIXIR := "elixir_test_hp_v1"
var failures: Array[String] = []

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("LIVE_ELIXIR_DEFEAT_CASE=FAIL ",label)

func wipe(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))

func _orders(sim: GroupCombatSimulator, slot: int) -> Dictionary:
	var controls := sim.player_controls(PLAYER)
	var attacks: Array[String] = []
	var blocks: Array[String] = []
	if not bool(controls.get("stunned",false)):
		for i in range(int(controls.get("attack_count",0))):
			attacks.append("chest")
		for zone in CombatCommandApi.BODY_ZONES:
			if blocks.size() < int(controls.get("block_capacity",0)):
				blocks.append(zone)
	return {"player_id":PLAYER,"attack_zones":attacks,"block_zones":blocks,"ability_id":"","elixir_slot":slot}

func _initialize() -> void:
	_run()
	print("LIVE_ELIXIR_DEFEAT_TEST=", "PASS" if failures.is_empty() else "FAIL"," failures=",failures)
	quit(0 if failures.is_empty() else 1)

func _run() -> void:
	var artifacts := SoloLiveNpcCombat._paths(ID,NPC)
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)
	var hero := CharacterState.new(PLAYER,"Elixir Defeat",1)
	hero.current_hp = 1
	var repo := ItemRepository.new()
	check(ArenaTestElixirs.seed(hero,repo),"elixirs_seeded")
	check(hero.equip("waist","elixir_test_belt_v1",repo),"belt_equipped")
	check(hero.assign_elixir(0,ELIXIR,repo),"health_elixir_equipped")
	var original := int(repo.get_item(ELIXIR).get("charges",-1))
	# Disk-loaded JSON can turn integer charges into an equivalent float.
	# This must not make a legitimate loss snapshot look like a forged item.
	var json_items: Variant = JSON.parse_string(JSON.stringify(repo.to_dict()))
	check(json_items is Dictionary,"roundtrip_repository_json")
	if json_items is Dictionary:
		var restored_repo := ItemRepository.from_dict(json_items)
		check(SoloCombatElixirJournal.same_repository(repo,restored_repo),"numeric_json_roundtrip_preserves_item_identity")
		var counterfeit := ItemRepository.from_dict(restored_repo.to_dict())
		var changed: Dictionary = counterfeit.get_item(ELIXIR)
		changed["charges"] = original-1
		check(counterfeit.update_item(changed),"tampered_charge_fixture")
		check(not SoloCombatElixirJournal.same_repository(repo,counterfeit),"charge_difference_still_rejected")
		var altered := ItemRepository.from_dict(restored_repo.to_dict())
		var wrong_item: Dictionary = altered.get_item(ELIXIR)
		wrong_item["name"] = "altered"
		check(altered.update_item(wrong_item),"tampered_item_fixture")
		check(not SoloCombatElixirJournal.same_repository(repo,altered),"other_item_properties_still_protected")
	check(bool(SoloTownSaveService.save(TOWN,hero,repo).get("ok",false)),"town_saved")
	check(bool(SoloTownExpeditionBridge.create_from_town(EXP,ID,995,START,hero,repo,MANIFEST).get("ok",false)),"expedition_created")
	var world := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(world.get("ok",false)),"expedition_opened")
	if not bool(world.get("ok",false)):
		return
	var encounter := SoloLiveNpcCombat.start(world["session"],TARGET)
	check(bool(encounter.get("ok",false)),"npc_contact_started")
	if not bool(encounter.get("ok",false)):
		print("LIVE_ELIXIR_DEFEAT_START=",encounter.get("reason","unknown"))
		return
	var combat: SoloLiveNpcCombat = encounter["combat"]
	var sim: GroupCombatSimulator = combat.battle["simulator"]
	# Consume one potion in a checkpointed round before the hero loses.
	var first := sim.run_round(_orders(sim,0))
	check(bool(first.get("ok",false)) and bool(first.get("checkpoint_ok",false)),"potion_round_checkpointed")
	if not bool(first.get("ok",false)) or not bool(first.get("checkpoint_ok",false)):
		return
	check(int(combat.owner.repository.get_item(ELIXIR).get("charges",-1))==original-1,"one_charge_spent")
	check(bool(SoloCombatElixirJournal.inspect(sim.state,hero,combat.owner.repository).get("ok",false)),"paid_elixir_journal_valid")
	sim.engine.combat_rng.seed = 20261022
	for n in range(100):
		if sim.controller.combat_finished():
			break
		var outcome := sim.run_round()
		if not bool(outcome.get("ok",false)) or not bool(outcome.get("checkpoint_ok",false)):
			check(false,"loss_round_"+str(n)+"_checkpoint_failed")
			return
	check(sim.controller.combat_finished() and sim.controller.winning_team() != "players","real_terminal_defeat")
	if not sim.controller.combat_finished() or sim.controller.winning_team()=="players":
		return
	var hero_actor := sim.state.get_combatant(PLAYER)
	check(hero_actor != null and hero_actor.is_death_finalized(),"death_finalized_at_end_of_round")
	var pinned := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(pinned.get("ok",false)),"pinned_world_readable")
	if bool(pinned.get("ok",false)):
		check(int(pinned["repository"].get_item(ELIXIR).get("charges",-1))==original,"pinned_world_unmodified_until_terminal")
	var pending := SoloLiveMapSession.open_pending(EXP,MANIFEST,ID,PLAYER)
	check(bool(pending.get("ok",false)),"pending_terminal_world")
	if not bool(pending.get("ok",false)):
		return
	var restored := SoloLiveNpcCombat.resume(pending["session"])
	check(bool(restored.get("ok",false)),"terminal_checkpoint_restored")
	if not bool(restored.get("ok",false)):
		print("LIVE_ELIXIR_DEFEAT_RESUME=",restored.get("reason","unknown"),":",restored.get("detail",""))
		return
	var resumed: SoloLiveNpcCombat = restored["combat"]
	check(int(resumed.owner.repository.get_item(ELIXIR).get("charges",-1))==original-1,"spent_charge_restored_before_terminal")
	var closed := resumed.play_round()
	check(bool(closed.get("ok",false)) and String(closed.get("state",""))=="defeat","defeat_published")
	if not bool(closed.get("ok",false)):
		print("LIVE_ELIXIR_DEFEAT_PUBLISH=",closed.get("reason","unknown"),":",closed.get("detail",""))
		return
	var published := ExpeditionSaveService.read(EXP,ID,PLAYER)
	check(bool(published.get("ok",false)),"published_world_valid")
	if not bool(published.get("ok",false)):
		return
	check(int(published["repository"].get_item(ELIXIR).get("charges",-1))==original-1,"loss_never_refunds_elixir")
	check(published["expedition"].player_position==START,"defeat_retreats_to_start")
	check(published["character"].current_hp>0,"hero_revived")
	var once_sha := String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))
	# Published world is now authoritative; reopening cannot refund spent items.
	var reopened := SoloLiveMapSession.open(EXP,MANIFEST,ID,PLAYER)
	check(bool(reopened.get("ok",false)),"live_world_reopened_after_defeat")
	if bool(reopened.get("ok",false)):
		check(int(reopened["session"].repository.get_item(ELIXIR).get("charges",-1))==original-1,"reopen_never_refunds")
	check(String(ExpeditionSaveService._read_payload_envelope(EXP).get("sha256",""))==once_sha,"reopen_does_not_double_publish")
	check(not FileAccess.file_exists(MANIFEST),"manifest_cleared_on_defeat")
	for path in [EXP,TOWN,MANIFEST,String(artifacts["checkpoint"]),String(artifacts["receipt"]),String(artifacts["terminal"])]:
		wipe(path)

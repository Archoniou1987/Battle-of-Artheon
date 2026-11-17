extends SceneTree

## Real v1.2 sword item cards must expose their four bound ABI names and details.
var problems: Array[String] = []

func _initialize() -> void:
	call_deferred("_verify")

func _check(ok: bool, code: String) -> void:
	if not ok:
		problems.append(code)
		print("ITEM_ABI_CARD_CASE_FAIL=", code)

func _verify() -> void:
	var hero := CharacterState.new("ABI_CARD_HERO", "Card Hero", 40)
	var repository := ItemRepository.new()
	var dialog := ItemDetailDialog.new(hero, repository)
	root.add_child(dialog)
	await process_frame
	for entry in [
		["SWORD_DEF", 202611041, ["ABI301", "ABI302", "ABI303", "ABI304"]],
		["SWORD_DODGE", 202611042, ["ABI305", "ABI306", "ABI307", "ABI308"]],
		["SWORD_CRIT", 202611043, ["ABI309", "ABI310", "ABI311", "ABI312"]]
	]:
		var item := ItemV12InstanceFactory.grant_sword(hero, repository, String(entry[0]), 40, "purple", int(entry[1]))
		_check(not item.is_empty(), String(entry[0]) + "_generated")
		if item.is_empty():
			continue
		dialog.show_item(String(item["instance_id"]))
		var found: Array[String] = []
		for control in dialog.content.get_children():
			if control is Button:
				var button := control as Button
				for abi_id in Array(entry[2]):
					if button.text.contains(String(abi_id)):
						found.append(String(abi_id))
		_check(found.size() == 4, String(entry[0]) + "_four_abi_links")
		for raw_id in Array(entry[2]):
			var abi_id := String(raw_id)
			_check(found.has(abi_id), String(entry[0]) + "_linked_" + abi_id)
		dialog._show_ability_info(String(Array(entry[2])[0]))
		_check(dialog.abi_info_popup.title.contains(String(AbilityCatalog.definition(AbilityCatalog.load_json("res://data/abilities/catalog.json"),String(Array(entry[2])[0])).get("name",""))), String(entry[0]) + "_abi_title")
		_check(dialog.abi_info_text.text.contains("Урон:"), String(entry[0]) + "_abi_description")
		_check(dialog.abi_info_text.scroll_active, String(entry[0]) + "_abi_scroll_enabled")
		_check(dialog.abi_info_popup.max_size.y <= 440, String(entry[0]) + "_abi_bounded_height")
		dialog.abi_info_popup.hide()
	dialog.queue_free()
	print("ITEM_ABI_CARD_TEST=", "PASS" if problems.is_empty() else "FAIL", " problems=", problems)
	quit(0 if problems.is_empty() else 1)

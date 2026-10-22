extends Control

const SCENE_TOWN := "res://scenes/main/main.tscn"
const SAVE := ExpeditionSaveService.DEFAULT_PATH
const MANIFEST := SoloCombatSessionManifest.PATH
const TOWN := SoloTownSaveService.DEFAULT_PATH
const PLAYER := "player"

var session: SoloLiveMapSession
var status_label: Label
var tile_container: GridContainer
var map_scroller: ScrollContainer
var live_combat: SoloLiveNpcCombat
var round_button: Button
var return_button: Button
var combat_panel: VBoxContainer
var combat_summary: Label
var combat_log_label: Label
var attack_zone_row: VBoxContainer
var block_zone_row: GridContainer
var ability_selector: OptionButton
var ability_slot_ids: Array[String] = []
var effects_label: Label
var elixir_summary: Label
var elixir_selector: OptionButton
var attack_controls: Array[OptionButton] = []
var block_controls: Array[CheckBox] = []
var ground_list: VBoxContainer
var pickup_ticket: String = ""
var pickup_active: bool = false

func _ready() -> void:
	var id := SoloTownExpeditionBridge.expedition_id_for_player(PLAYER)
	var opened := SoloLiveMapSession.open(SAVE,MANIFEST,id,PLAYER)
	_build_view()
	# Fail closed until a verified normal session is available.
	return_button.disabled = true
	if not bool(opened.get("ok",false)) and String(opened.get("state","")) == "resume_combat_checkpoint":
		opened = SoloLiveMapSession.open_pending(SAVE,MANIFEST,id,PLAYER)
		if bool(opened.get("ok",false)):
			session = opened["session"]
			var resumed := SoloLiveNpcCombat.resume(session)
			if not bool(resumed.get("ok",false)):
				_set_status("Восстановление боя заблокировано: "+String(resumed.get("reason","unknown")))
				return
			live_combat = resumed["combat"]
			round_button.visible = true
			round_button.text = "Подтвердить результат боя" if live_combat.battle["simulator"].controller.combat_finished() else "Следующий раунд"
			_refresh()
			_set_status("Восстановлен бой, завершён раунд "+str(resumed.get("round",0))+".")
			return
	if not bool(opened.get("ok",false)):
		_set_status("Экспедиция недоступна: "+String(opened.get("reason","unknown")))
		return
	session = opened["session"]
	return_button.disabled = false
	_refresh()

func _build_view() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#172334")
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(scroll)
	var root := VBoxContainer.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.add_theme_constant_override("separation",12)
	root.custom_minimum_size = Vector2(0,0)
	scroll.add_child(root)
	var header := Label.new()
	header.text = "Экспедиция — первая игровая карта"
	header.add_theme_font_size_override("font_size",22)
	root.add_child(header)
	status_label = Label.new()
	root.add_child(status_label)
	var explanation := Label.new()
	explanation.text = "Враги отмечены ⚔. Контакт запускает настоящий Combat Engine. Выберите зоны атаки, защиты и одну ABI (или пропустите её)."
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(explanation)
	combat_panel = VBoxContainer.new()
	combat_panel.visible = false
	root.add_child(combat_panel)
	combat_summary = Label.new()
	combat_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_panel.add_child(combat_summary)
	var attack_label := Label.new()
	attack_label.text = "Атака — зона каждого удара"
	combat_panel.add_child(attack_label)
	attack_zone_row = VBoxContainer.new()
	combat_panel.add_child(attack_zone_row)
	var block_label := Label.new()
	block_label.text = "Ручная защита — выберите доступные зоны"
	combat_panel.add_child(block_label)
	block_zone_row = GridContainer.new()
	block_zone_row.columns = 3
	combat_panel.add_child(block_zone_row)
	var ability_label := Label.new()
	ability_label.text = "ABI — до одной способности за раунд (5 слотов экипировки)"
	combat_panel.add_child(ability_label)
	ability_selector = OptionButton.new()
	ability_selector.custom_minimum_size.y = 48
	combat_panel.add_child(ability_selector)
	elixir_summary = Label.new()
	elixir_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_panel.add_child(elixir_summary)
	elixir_selector = OptionButton.new()
	elixir_selector.custom_minimum_size.y = 48
	elixir_selector.item_selected.connect(_on_elixir_selection_changed)
	combat_panel.add_child(elixir_selector)
	round_button = Button.new()
	round_button.text = "Следующий раунд"
	round_button.custom_minimum_size.y = 56
	round_button.visible = false
	round_button.pressed.connect(_play_combat_round)
	combat_panel.add_child(round_button)
	effects_label = Label.new()
	effects_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_panel.add_child(effects_label)
	combat_log_label = Label.new()
	combat_log_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	combat_panel.add_child(combat_log_label)
	map_scroller = ScrollContainer.new()
	map_scroller.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	map_scroller.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	map_scroller.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	root.add_child(map_scroller)
	tile_container = GridContainer.new()
	tile_container.columns = SoloLiveMapSession.WIDTH
	map_scroller.add_child(tile_container)
	var ground_heading := Label.new()
	ground_heading.text = "Добыча на текущей клетке • сбор 2 секунды"
	root.add_child(ground_heading)
	ground_list = VBoxContainer.new()
	root.add_child(ground_list)
	return_button = Button.new()
	return_button.custom_minimum_size.y = 48
	return_button.text = "Завершить экспедицию и вернуться в деревню"
	return_button.pressed.connect(_return_town)
	root.add_child(return_button)

func _set_status(value: String) -> void:
	if status_label != null:
		status_label.text = value

func _refresh() -> void:
	if session == null:
		return
	_set_status("Позиция: %s   •   Персонаж: %s" % [str(session.expedition.player_position),session.character.display_name])
	_refresh_combat_controls()
	for node in ground_list.get_children():
		ground_list.remove_child(node)
		node.queue_free()
	var on_ground := session.visible_ground_items()
	for entry in on_ground:
		var item_id := String(entry.get("instance_id",""))
		var item: Dictionary = session.repository.get_item(item_id)
		var pickup_button := Button.new()
		pickup_button.text = "Подобрать • " + String(item.get("name",item.get("display_name",item_id)))
		pickup_button.disabled = pickup_active or live_combat != null or FileAccess.file_exists(MANIFEST)
		pickup_button.pressed.connect(_pickup_item.bind(item_id))
		ground_list.add_child(pickup_button)
	if on_ground.is_empty():
		var empty := Label.new()
		empty.text = "Здесь нет доступной добычи."
		ground_list.add_child(empty)
	for n in tile_container.get_children():
		tile_container.remove_child(n)
		n.queue_free()
	for y in range(SoloLiveMapSession.HEIGHT):
		for x in range(SoloLiveMapSession.WIDTH):
			var pos := Vector2i(x,y)
			var btn := Button.new()
			btn.custom_minimum_size = Vector2(44,44)
			if pos == session.expedition.player_position:
				btn.text = "◆"
			elif not session.npc_bridge.npc_at(session.map,pos).is_empty() and HexGrid.distance(session.expedition.player_position,pos) <= 3:
				btn.text = "⚔"
			elif HexGrid.distance(session.expedition.player_position,pos) <= 3:
				btn.text = "·"
			else:
				btn.text = " "
			btn.disabled = pickup_active or live_combat != null or FileAccess.file_exists(MANIFEST) or HexGrid.distance(session.expedition.player_position,pos) != 1
			btn.pressed.connect(_move.bind(pos))
			tile_container.add_child(btn)

## Read-only widgets for the real checkpointed combatant and log.
## Display never creates another CombatEngine or overwrites saved stats.
func _refresh_combat_controls() -> void:
	combat_panel.visible = live_combat != null
	attack_controls.clear()
	block_controls.clear()
	for parent in [attack_zone_row,block_zone_row]:
		for child in parent.get_children():
			parent.remove_child(child)
			child.queue_free()
	if live_combat == null:
		return
	var view := live_combat.combat_view()
	if not bool(view.get("ok",false)):
		combat_summary.text = "Боевые данные недоступны."
		return
	var hero: Dictionary = view["player"]
	var elixir_view: Dictionary = view.get("elixir_loadout",{})
	var elixir_lines: Array[String] = []
	if bool(elixir_view.get("ok",false)):
		for raw_slot in Array(elixir_view.get("slots",[])):
			var slot: Dictionary = raw_slot
			var number := int(slot.get("slot",0)) + 1
			if not bool(slot.get("unlocked",false)):
				elixir_lines.append(str(number)+": закрыт")
			elif String(slot.get("instance_id","")).is_empty():
				elixir_lines.append(str(number)+": пусто")
			else:
				elixir_lines.append("%d: %s (%d/%d)" % [number,String(slot.get("instance_id","")),int(slot.get("charges",0)),int(slot.get("max_charges",0))])
		elixir_summary.text = "Эликсиры: " + " • ".join(PackedStringArray(elixir_lines))
	else:
		elixir_summary.text = "Слоты эликсиров недоступны: "+String(elixir_view.get("reason","unknown"))
	elixir_selector.clear()
	elixir_selector.add_item("Без эликсира",0)
	var journal := SoloCombatElixirJournal.inspect(live_combat.battle["simulator"].state,session.character,session.repository)
	var cooldown_until := int(journal.get("next_available_round",0))
	var next_round := int(view.get("round",0))+1
	for slot_index in range(4):
		var slot_entries: Array = elixir_view.get("slots",[])
		var slot: Dictionary = slot_entries[slot_index] if slot_index < slot_entries.size() else {}
		var caption := "%d. %s" % [slot_index+1,String(slot.get("instance_id","Пусто"))]
		if String(slot.get("instance_id","")).is_empty():
			caption = str(slot_index+1)+". Пусто"
		elixir_selector.add_item(caption,slot_index+1)
		if not bool(slot.get("valid",false)) or not bool(slot.get("unlocked",false)) or int(slot.get("charges",0)) <= 0 or not bool(journal.get("ok",false)) or next_round < cooldown_until or bool(view.get("finished",false)) or bool(Dictionary(view.get("controls",{})).get("stunned",false)):
			elixir_selector.set_item_disabled(slot_index+1,true)
	elixir_selector.select(0)
	elixir_selector.disabled = bool(view.get("finished",false))
	var enemies: Array = view.get("enemies",[])
	var opponent_text := ""
	for enemy in enemies:
		var npc: Dictionary = enemy
		if not opponent_text.is_empty():
			opponent_text += " • "
		opponent_text += "%s: %d/%d HP" % [String(npc["name"]),int(npc["hp"]),int(npc["max_hp"])]
		for raw_effect in Array(npc.get("effects",[])):
			var effect: Dictionary = raw_effect
			opponent_text += " [%s %s ×%d, %d р.]" % [String(effect.get("polarity","")),String(effect.get("name","")),int(effect.get("stacks",1)),int(effect.get("remaining_rounds",0))]
	combat_summary.text = "Раунд %d • %s: %d/%d HP, %d/%d MP\n%s" % [
		int(view["round"]),String(hero["name"]),int(hero["hp"]),int(hero["max_hp"]),
		int(hero["mana"]),int(hero["max_mana"]),opponent_text
	]
	var active_effects: Array[String] = []
	for raw_effect in Array(hero.get("effects",[])):
		var effect: Dictionary = raw_effect
		active_effects.append("%s %s ×%d (%d р.)" % [String(effect.get("polarity","")),String(effect.get("name","")),int(effect.get("stacks",1)),int(effect.get("remaining_rounds",0))])
	effects_label.text = "Эффекты героя: " + (", ".join(PackedStringArray(active_effects)) if not active_effects.is_empty() else "нет")
	var log_parts: Array[String] = []
	for raw_line in Array(view.get("last_round_log",[])):
		log_parts.append(String(raw_line))
	combat_log_label.text = "Последний раунд:\n" + ("\n".join(PackedStringArray(log_parts)) if not log_parts.is_empty() else "Событий пока нет")
	ability_slot_ids.clear()
	ability_selector.clear()
	ability_selector.add_item("Без ABI",0)
	for i in range(5):
		var slots: Array = view.get("ability_slots",[])
		var slot: Dictionary = slots[i] if i < slots.size() else {}
		var ability_id := String(slot.get("id",""))
		ability_slot_ids.append(ability_id)
		var caption := str(i + 1) + ". "
		if ability_id.is_empty():
			caption += "Пусто"
		else:
			caption += String(slot.get("name",ability_id)) + " • " + str(int(slot.get("mana_cost",0))) + " MP"
		ability_selector.add_item(caption,i+1)
		if not bool(slot.get("available",false)) or bool(view["finished"]):
			ability_selector.set_item_disabled(i+1,true)
	ability_selector.select(0)
	ability_selector.disabled = bool(view["finished"])
	_sync_abi_availability_with_elixir()
	if bool(view["finished"]):
		return
	var controls: Dictionary = view.get("controls",{})
	if not bool(controls.get("ok",false)):
		return
	if bool(controls.get("stunned",false)):
		var disabled_label := Label.new()
		disabled_label.text = "Оглушение: действия этого раунда пропускаются."
		attack_zone_row.add_child(disabled_label)
		return
	var zone_names := ["Голова","Грудь","Руки","Пояс","Ноги"]
	for attack_index in range(int(controls.get("attack_count",0))):
		var option := OptionButton.new()
		option.custom_minimum_size.y = 48
		for i in range(CombatCommandApi.BODY_ZONES.size()):
			option.add_item(zone_names[i],i)
		option.select(1)
		attack_zone_row.add_child(option)
		attack_controls.append(option)
	for i in range(CombatCommandApi.BODY_ZONES.size()):
		var cb := CheckBox.new()
		cb.custom_minimum_size.y = 44
		cb.text = zone_names[i]
		cb.button_pressed = [1,2,3,4,0].find(i) < int(controls.get("block_capacity",0))
		block_zone_row.add_child(cb)
		block_controls.append(cb)

## Recalculate the ABI's enabled state when a mana potion is selected.
## The simulator runs the SAME canonical order validation without spending
## mana or item charges. Only the selected potion changes affordability.
func _on_elixir_selection_changed(_index: int) -> void:
	_sync_abi_availability_with_elixir()

func _sync_abi_availability_with_elixir() -> void:
	if live_combat == null or session == null or elixir_selector == null or ability_selector == null:
		return
	var simulator: GroupCombatSimulator = live_combat.battle.get("simulator") as GroupCombatSimulator
	if simulator == null or simulator.controller.combat_finished():
		return
	var slot := elixir_selector.get_selected_id() - 1
	var controls := simulator.player_controls(session.character.character_id,slot)
	var options: Dictionary = {}
	if bool(controls.get("ok",false)):
		for raw_option in Array(controls.get("abilities",[])):
			var option: Dictionary = raw_option
			options[String(option.get("id",""))] = option
	for i in range(ability_slot_ids.size()):
		var id := ability_slot_ids[i]
		var ready := options.has(id) and bool(Dictionary(options.get(id,{})).get("available",false))
		ability_selector.set_item_disabled(i+1,not ready)
	var selected_id := ability_selector.get_selected_id()
	if selected_id > 0 and ability_selector.is_item_disabled(selected_id):
		ability_selector.select(0)

func _move(target: Vector2i) -> void:
	if session == null or pickup_active or live_combat != null or FileAccess.file_exists(MANIFEST):
		return
	var moved := session.move_one_step(target)
	if not bool(moved.get("ok",false)):
		if String(moved.get("reason","")) == "combat_ui_not_connected":
			_start_combat(target)
		else:
			_set_status("Шаг отклонён: "+String(moved.get("reason","unknown")))
		return
	_refresh()

func _start_combat(cell: Vector2i) -> void:
	if pickup_active:
		return
	var result := SoloLiveNpcCombat.start(session,cell)
	if not bool(result.get("ok",false)):
		# A failed start can still own a durable manifest. Do not visually
		# advertise movement/return if recovery must reconcile it first.
		if FileAccess.file_exists(MANIFEST):
			return_button.disabled = true
			_refresh()
		_set_status("Бой заблокирован: "+String(result.get("reason","unknown")))
		return
	live_combat=result["combat"]
	round_button.text="Следующий раунд"
	round_button.visible=true
	return_button.disabled=true
	_refresh()
	_set_status("Бой начался. Следующий раунд: базовые атаки обеих сторон.")

func _play_combat_round() -> void:
	if live_combat == null:
		return
	var submission: Dictionary = {}
	var before := live_combat.combat_view()
	if bool(before.get("ok",false)) and not bool(before.get("finished",false)):
		var attack_zones: Array[String] = []
		for option in attack_controls:
			var selected_index := option.get_selected_id()
			if selected_index >= 0 and selected_index < CombatCommandApi.BODY_ZONES.size():
				attack_zones.append(CombatCommandApi.BODY_ZONES[selected_index])
		var block_zones: Array[String] = []
		for i in range(block_controls.size()):
			if block_controls[i].button_pressed:
				block_zones.append(CombatCommandApi.BODY_ZONES[i])
		var abi_position := ability_selector.get_selected_id() - 1
		var ability_id := ability_slot_ids[abi_position] if abi_position >= 0 and abi_position < ability_slot_ids.size() else ""
		submission = {"player_id":PLAYER,"attack_zones":attack_zones,"block_zones":block_zones,"ability_id":ability_id,"elixir_slot":elixir_selector.get_selected_id()-1}
	var step := live_combat.play_round(submission)
	if not bool(step.get("ok",false)):
		var issue := String(step.get("reason",step.get("state","unknown")))
		if issue in ["invalid_attack_zone","invalid_block_zone","invalid_attack_zone_count","invalid_block_zone_count","invalid_player_order_format","invalid_player_orders_owner","manual_block_rejected","invalid_player_ability_format","stunned_cannot_cast","player_ability_unavailable","player_ability_not_equipped","invalid_elixir_slot","elixir_slot_unavailable","elixir_shared_cooldown","elixir_actor_unavailable","elixir_journal_invalid_source","elixir_journal_invalid_charges"]:
			_set_status("Неверный выбор зон: "+issue+". Проверьте количество зон атаки и защиты.")
			return
		round_button.disabled=true
		_set_status("Бой приостановлен: "+issue+". Сохранения не удалены; дальнейшие действия заблокированы.")
		return
	var state := String(step.get("state",""))
	if state == "victory" or state == "defeat":
		# Both outcomes publish new canonical owners. Never keep the
		# pre-combat character/repository in the map scene.
		var reopened := SoloLiveMapSession.open(SAVE,MANIFEST,session.expedition.expedition_id,PLAYER)
		if not bool(reopened.get("ok",false)):
			round_button.disabled = true
			_set_status("Результат боя сохранён, но карту не удалось обновить: "+String(reopened.get("reason","unknown")))
			return
		session = reopened["session"]
		live_combat=null
		round_button.visible=false
		round_button.text="Следующий раунд"
		return_button.disabled=false
		_refresh()
		if state == "victory":
			_set_status("Победа подтверждена и сохранена. Награды находятся на клетке противника.")
		else:
			_set_status("Поражение сохранено. Герой вернулся на стартовую клетку экспедиции; враг и добыча не изменены.")
	else:
		_refresh_combat_controls()
		_set_status("Раунд "+str(step.get("round",0))+" завершён и сохранён.")

func _pickup_item(item_id: String) -> void:
	if session == null or pickup_active or live_combat != null or FileAccess.file_exists(MANIFEST):
		return
	var began := session.begin_ground_pickup(item_id)
	if not bool(began.get("ok",false)):
		_set_status("Сбор отклонён: "+String(began.get("reason","unknown")))
		return
	pickup_ticket = String(began["ticket"])
	pickup_active = true
	return_button.disabled = true
	var current_session := session
	_refresh()
	_set_status("Собираем предмет: 2 секунды.")
	await get_tree().create_timer(float(SoloLiveMapSession.SOLO_PICKUP_SECONDS)).timeout
	if not is_inside_tree():
		return
	if current_session != session or not pickup_active or pickup_ticket.is_empty():
		return
	var ticket := pickup_ticket
	pickup_ticket = ""
	pickup_active = false
	var collected := session.finish_ground_pickup(ticket)
	return_button.disabled = FileAccess.file_exists(MANIFEST) or live_combat != null
	_refresh()
	if bool(collected.get("ok",false)):
		_set_status("Предмет добавлен в инвентарь и сохранён: "+String(collected["instance_id"]))
	else:
		_set_status("Сбор не завершён: "+String(collected.get("reason","unknown")))

func _return_town() -> void:
	if session == null or pickup_active or live_combat != null or FileAccess.file_exists(MANIFEST):
		return
	var result := session.return_to_town(TOWN)
	if not bool(result.get("ok",false)):
		_set_status("Возврат заблокирован: "+String(result.get("detail",result.get("reason","unknown"))))
		return
	get_tree().change_scene_to_file(SCENE_TOWN)

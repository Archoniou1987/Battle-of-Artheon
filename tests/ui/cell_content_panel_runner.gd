extends SceneTree

var errors: Array[String] = []

func check(ok:bool,label:String)->void:
	if not ok:
		errors.append(label)
		print("CELL_PANEL_CASE=FAIL ",label)

func _initialize()->void:
	var panel := CellContentPanel.new()
	root.add_child(panel)
	call_deferred("_test",panel)

func _test(panel:CellContentPanel)->void:
	check(panel.tabs != null and panel.tabs.get_tab_count()==2,"world_tabs_created")
	var no_data := {"ok":true,"cell":Vector2i(2,3),"total":0,"entries":[]}
	panel.set_projection(no_data)
	check(panel.entries_grid.get_child_count()==0,"empty_hex_has_no_icons")
	check(panel.cell_label.text.contains("2:3"),"current_coordinates_shown")
	var selection:Array[String]=[]
	panel.entry_selected.connect(func(kind:String,id:String,action:String)->void:
		selection.append(kind+":"+id+":"+action)
	)
	panel.set_projection({"ok":true,"cell":Vector2i(3,3),"total":3,"entries":[
		{"kind":CellContentService.KIND_ITEM,"id":"SCROLL01","actions":["inspect","pick_up"]},
		{"kind":CellContentService.KIND_NPC,"id":"DEER01","name":"Олень","actions":["inspect","attack"]},
		{"kind":CellContentService.KIND_OBJECT,"id":"ALTAR01","actions":["inspect"]}
	]})
	check(panel.entries_grid.get_child_count()==3,"three_compact_icons")
	check(panel.cell_label.text.contains("3:3"),"updated_coordinates")
	var node:Button=panel.entries_grid.get_child(1) as Button
	check(node != null,"npc_icon_is_button")
	if node!=null:
		node.pressed.emit()
	check(selection.size()==1 and selection[0]=="npc:DEER01:inspect","selection_emits_without_combat")
	var request:Array[String]=[]
	var cancelled:Array[bool]=[]
	panel.pickup_requested.connect(func(id:String)->void:
		request.append(id)
	)
	panel.pickup_cancel_requested.connect(func()->void:
		cancelled.append(true)
	)
	var scroll_button:Button=panel.entries_grid.get_child(0) as Button
	scroll_button.pressed.emit()
	check(panel.pickup_button.visible,"selected_item_offers_pickup")
	panel.pickup_button.pressed.emit()
	check(request==["SCROLL01"],"selected_item_requests_exact_instance")
	panel.show_pickup_progress(2.5)
	check(panel.pickup_progress.visible and absf(panel.pickup_progress.value-2.5)<0.001,"pickup_progress_is_visible")
	check(panel.cancel_button.visible and not panel.pickup_button.visible,"pickup_running_offer_cancel")
	panel.cancel_button.pressed.emit()
	check(cancelled.size()==1,"pickup_cancel_signal")
	panel.finish_pickup_display("Отменено")
	check(not panel.pickup_progress.visible and not panel.cancel_button.visible,"pickup_progress_cleared")
	panel.set_projection({"ok":true,"cell":Vector2i(4,3),"total":0,"entries":[]})
	check(panel.entries_grid.get_child_count()==0,"moving_clears_old_cell_icons")
	print("CELL_CONTENT_PANEL_TEST=" + ("PASS" if errors.is_empty() else "FAIL") + " errors=" + str(errors))
	quit(0 if errors.is_empty() else 1)

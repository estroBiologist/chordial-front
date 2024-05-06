extends Control

const STARTUP_FILE := "res://startup.chrp"

@onready var engine := $ChordialEngine as ChordialEngine

var popup_menu: PopupMenu = null

var current_file_path := ""

var debug_rect_draw := false
var current_rect := Rect2()

func _ready():
	load_state(STARTUP_FILE)


func load_state(file: String):
	var node_view := get_node_view()
	
	node_view.clear_connections()
	
	for node: Control in node_view.get_children():
		if not node is GraphNode:
			continue
		
		node_view.remove_child(node)
		node.queue_free()
	
	engine.load_state(file)
	
	# load nodes
	for i in engine.get_node_count():
		create_visual_node(i)
	
	# Connect nodes
	for i in engine.get_node_count():
		var graph_node := node_view.get_child(i) as GraphNode
		
		for j in engine.node_get_input_count(i):
			for k in engine.node_get_input_connection_count(i, j):
				var bus := engine.node_get_input_connection(i, j, k)
			
				if bus:
					var connect_node := node_view.get_child(bus.node).name
					node_view.connect_node(connect_node, bus.output, graph_node.name, j)
			
			
	node_view.arrange_nodes()


func _process(delta):
	if get_viewport().gui_get_focus_owner() != %TopBar/Position:
		%TopBar/Position.text = str(engine.position)
	
	var realtime_fac := 0.0
	
	if engine.playing:
		realtime_fac = engine.get_realtime_factor()
	
	%DbgText.text = "node count: %s - ct/rt: %.2f%%" % [
		engine.get_node_count(),
		realtime_fac * 100.0
	]


func _unhandled_input(event):
	if event.is_action_pressed("debug_draw") and not debug_rect_draw:
		debug_rect_draw = true
		enable_debug_view_recursive(self)


func enable_debug_view_recursive(node: Node):
	if node is Control:
		node.mouse_entered.connect(func():
			update_rect(node.get_global_rect())
		)
	
	for child in node.get_children():
		enable_debug_view_recursive(child)



func update_rect(rect: Rect2):
	current_rect = rect
	queue_redraw()


func _draw():
	if debug_rect_draw:
		draw_rect(current_rect, Color.DODGER_BLUE)


func create_node(ctor: String, pos := Vector2.ZERO):
	var i := engine.create_node(ctor)
	create_visual_node(i, pos)
	print("Creating node (", ctor, ") at ", pos)
	

func create_visual_node(i: int, pos := Vector2.ZERO):
	var node_view := get_node_view()
	var graph_node := GraphNode.new()
	
	graph_node.title = engine.node_get_name(i)
	graph_node.tooltip_text = engine.node_get_id(i)
	graph_node.resizable = true

	var port_count := maxi(
		engine.node_get_input_count(i),
		engine.node_get_output_count(i)
	)
	
	for j in port_count:
		var hbox := HBoxContainer.new()
		
		hbox.add_theme_constant_override("separation", 10.0)
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		
		if j < engine.node_get_input_count(i):
			var type := engine.node_get_input_type(i, j)
			var label := Label.new()
			
			graph_node.set_slot_enabled_left(j, true)
			graph_node.set_slot_color_left(j, get_port_color(type))
			graph_node.set_slot_type_left(j, type)
			graph_node.set_slot_enabled_left(j, true)
			
			label.text = engine.node_get_input_name(i, j)
			label.modulate = Color.DIM_GRAY
			hbox.add_child(label)
			
		var separator := Control.new()
		separator.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(separator)
		
		if j < engine.node_get_output_count(i):
			var type := engine.node_get_output_type(i, j)
			var label := Label.new()
			
			graph_node.set_slot_enabled_right(j, true)
			graph_node.set_slot_color_right(j, get_port_color(type))
			graph_node.set_slot_type_right(j, type)
			graph_node.set_slot_enabled_right(j, true)
			
			label.text = engine.node_get_output_name(i, j)
			label.modulate = Color.DIM_GRAY
			hbox.add_child(label)
	
		graph_node.add_child(hbox)
	
	var grid := GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	grid.columns = 2
	
	for j in engine.node_get_param_count(i):
		var label := Label.new()
		label.text = engine.node_get_param_name(i, j)

		var value = engine.node_get_param_value(i, j)
		grid.add_child(label)
		
		var line_edit := LineEdit.new()
		line_edit.text = str(value)
		line_edit.text_changed.connect(func(new_text: String):
			if value is String:
				engine.node_set_param_value(i, j, new_text)
				
			elif value is float:
				if not new_text.is_valid_float():
					new_text = str(float(new_text))
					line_edit.text = new_text
				engine.node_set_param_value(i, j, float(new_text))
				
			else:
				if new_text != str(int(new_text)):
					new_text = str(int(new_text))
					line_edit.text = new_text
				engine.node_set_param_value(i, j, int(new_text))
		)
		
		grid.add_child(line_edit)
	
	graph_node.add_child(grid)
	graph_node.update_minimum_size()
	graph_node.set_meta("id", i)
	node_view.add_child(graph_node)
	graph_node.position_offset = (pos + node_view.scroll_offset) / node_view.zoom


func show_popup_menu(menu: PopupMenu):
	if popup_menu:
		popup_menu.queue_free()
	
	popup_menu = menu
	add_child(popup_menu)
	popup_menu.visible = true


func get_port_color(type: int) -> Color:
	match type:
		0:
			return Color.DEEP_PINK
		1:
			return Color.DEEP_SKY_BLUE
		2:
			return Color.GREEN_YELLOW
		_:
			return Color.GRAY


func get_node_view() -> GraphEdit:
	return %Views.get_node("Node View")


func delete_node(node_name: String):
	var node_view := get_node_view()
	
	for connection in node_view.get_connection_list():
		if connection.to_node == node_name or connection.from_node == node_name:
			node_view.disconnect_node(
				connection.from_node,
				connection.from_port,
				connection.to_node,
				connection.to_port
			)
	
	var node := node_view.get_node(node_name) as Control
	engine.delete_node(node.get_meta("id"))
	node.queue_free()
	

func _on_position_text_changed(new_text: String) -> void:
	match %PosUnit.selected:
		0: # m:s:cs
			pass
	if new_text != str(int(new_text)):
		%TopBar/Position.text = str(int(new_text))
	engine.position = int(new_text)


func _on_stop_btn_pressed() -> void:
	engine.position = 0
	engine.set_playing(false)
	%PlayBtn.button_pressed = false
	%PlayBtn.update_texture()


func _on_play_btn_toggled(toggled_on: bool) -> void:
	engine.set_playing(toggled_on)


func _on_node_view_disconnection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	var node_view := get_node_view()
	var to_id := node_view.get_node(String(to_node)).get_meta("id") as int
	var from_id := node_view.get_node(String(from_node)).get_meta("id") as int
	var output_ref := OutputRef.new()
	
	output_ref.node = from_id
	output_ref.output = from_port
	
	engine.node_remove_input_connection(to_id, to_port, output_ref)
	get_node_view().disconnect_node(from_node, from_port, to_node, to_port)


func _on_node_view_connection_request(
	from_node: StringName,
	from_port: int,
	to_node: StringName,
	to_port: int
) -> void:
	var node_view := get_node_view()
	var to_id := node_view.get_node(String(to_node)).get_meta("id") as int
	var from_id := node_view.get_node(String(from_node)).get_meta("id") as int
	var output_ref := OutputRef.new()
	
	output_ref.node = from_id
	output_ref.output = from_port
	engine.node_add_input_connection(to_id, to_port, output_ref)
	node_view.connect_node(from_node, from_port, to_node, to_port)


func _on_node_creation_requested(ctor: String, pos: Vector2):
	create_node(ctor, pos)


func _on_node_deletion_requested(node: Control):
	delete_node(node.name)



func _on_delete_nodes_request(nodes):
	for node in nodes:
		delete_node(String(node))



func _on_file_index_pressed(index):
	match %File.get_item_text(index):
		"New":
			load_state(STARTUP_FILE)
		
		"Save":
			if current_file_path == "":
				var file_dialog := FileDialog.new()
				file_dialog.access = FileDialog.ACCESS_FILESYSTEM
				file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
				file_dialog.add_filter("*.chrp", "Chordial Project")
				add_child(file_dialog)
				file_dialog.show()
				await file_dialog.close_requested
			


func _on_bpm_value_changed(value):
	pass # Replace with function body.


func _on_pos_unit_item_selected(index):
	match index:
		0, 1:
			%PosA.visible = true
			%PosB.visible = true
			%Position.visible = false
			%PosA.suffix = "m" if index == 0 else "b"
			%PosA.suffix = "m" if index == 0 else "b"
		2:
			%PosA.visible = false
			%PosB.visible = false
			%Position.visible = true


func _on_debug_refresh_pressed():
	%DebugText.text = engine.get_debug_info()

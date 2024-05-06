extends GraphEdit

@onready var engine := %ChordialEngine as ChordialEngine

signal node_creation_requested(ctor: String, pos: Vector2)
signal node_deletion_requested(node: Control)

func show_popup_menu(pos: Vector2):
	var popup_menu := PopupMenu.new()
	var graph_pos := pos - global_position
	var hovered: GraphNode = null
	
	print("Graph pos: ", graph_pos)
	
	for node: Control in get_children():
		if not node is GraphNode:
			continue
		
		var rect := node.get_rect()
		
		if rect.has_point(graph_pos):
			popup_menu.add_item("Delete", 0)
			popup_menu.set_item_metadata(0, "cmd:delete")
			popup_menu.add_separator()
			hovered = node
			set_selected(hovered)
			break
	
	for ctor in engine.get_constructors():
		popup_menu.add_item(ctor)
		var id := popup_menu.get_item_id(popup_menu.item_count - 1)
		popup_menu.set_item_metadata(id, "ctor:%s" % ctor)
	
	popup_menu.position = pos
	popup_menu.transparent_bg = true
	get_tree().current_scene.show_popup_menu(popup_menu)

	popup_menu.index_pressed.connect(func(index):
		if not popup_menu.get_item_metadata(index) is String:
			return
		
		var meta := popup_menu.get_item_metadata(index) as String
		
		if meta.begins_with("ctor:"):
			node_creation_requested.emit(meta.substr(5), graph_pos)
		else:
			match popup_menu.get_item_metadata(index):
				"cmd:delete":
					node_deletion_requested.emit(hovered)
				_:
					pass
	)
	
	
func _gui_input(event):
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			show_popup_menu(event.global_position)


func _can_drop_data(at_position: Vector2, data):
	return data is String

func _drop_data(at_position: Vector2, data):
	if not data is String:
		return
	
	node_creation_requested.emit(data, at_position)
	

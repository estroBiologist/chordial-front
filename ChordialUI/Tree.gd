extends Tree

var path := "/home/ash"

const FileIcon := preload("res://icons/File.svg")
const FolderIcon := preload("res://icons/Folder.svg")
const TreeDragPreview := preload("res://TreeDragPreview.tscn")

@onready var engine := %ChordialEngine as ChordialEngine


var ctor_tree := {}

func rescan():
	clear()
	
	var ctors := create_item(null)
	ctors.set_text(0, "nodes")
	
	for ctor in engine.get_constructors():
		var path := ctor.split(".")
		var path_combined := path[0]
		var parent := ctors
		
		for i in range(path.size() - 1):
			var new_path_combined := path_combined + "." + path[i]
			
			if not ctor_tree.has(new_path_combined):
				var branch := create_item(ctor_tree.get(path_combined, ctors))
				branch.set_text(0, path[i])
				ctor_tree[new_path_combined] = branch
			
			parent = ctor_tree[new_path_combined]
		
		var ctor_item := create_item(parent)
		
		ctor_item.set_tooltip_text(0, ctor)
		ctor_item.set_metadata(0, ctor)
		ctor_item.set_text(0, path[path.size() - 1])
		
	scan_directory(path, null)
	

func scan_directory(dir: String, root: TreeItem):
	var dir_access := DirAccess.open(dir)
	
	if not dir_access:
		return
	
	var item := create_item(root)
	
	item.set_collapsed_recursive(true)
	item.set_text(0, dir.substr(dir.rfind("/")+1))
	item.set_icon(0, FolderIcon)	
	
	for subdir in dir_access.get_directories():
		scan_directory(path + "/" + subdir, item)
		
	for file in dir_access.get_files():
		var file_item := create_item(item)
		file_item.set_text(0, file)
		file_item.set_icon(0, FileIcon)

func _ready():
	rescan()

func _get_drag_data(at_position: Vector2):
	var item := get_item_at_position(at_position)
	
	if not item or not item.get_metadata(0) is String:
		return null
	
	var preview := TreeDragPreview.instantiate()
	var label := Label.new()
	var data := item.get_metadata(0) as String
	
	label.text = data
	
	preview.offset = Vector2(0.0, 32.0)
	preview.add_content(label)
	set_drag_preview(preview)
	preview.reset_position()
	
	print("Dragging: ", data)
	
	return data
	

@tool
extends PanelContainer

@export var track_index := 0:
	set(value):
		track_index = value
		
		if is_inside_tree():
			update()


func _ready():
	update()


func update():
	$Label.text = "Track %s" % (track_index + 1)
	

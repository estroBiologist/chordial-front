extends TextureButton

@export var normal_texture: Texture2D
@export var pressed_texture: Texture2D

func _on_button_down():
	modulate = Color.GRAY
	


func _on_button_up():
	modulate = Color.WHITE
	update_texture()


func update_texture():
	if normal_texture:
		if button_pressed:
			texture_normal = pressed_texture
		else:
			texture_normal = normal_texture

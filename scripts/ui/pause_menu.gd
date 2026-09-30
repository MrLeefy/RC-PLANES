class_name PauseMenu
extends Control

signal action(name: String)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = UITheme.theme()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.45)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	add_child(pc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	pc.add_child(vb)
	var t := UITheme.label("PAUSED", 36)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	for d in [["resume", "RESUME"], ["restart", "RESTART / REPAIR"], ["settings", "SETTINGS"], ["diag", "EXPORT DIAGNOSTICS"], ["hangar", "BACK TO HANGAR"]]:
		var b := UITheme.accent_button(d[1], 360) if d[0] == "resume" else UITheme.button(d[1], 360)
		var n: String = d[0]
		b.pressed.connect(func(): action.emit(n))
		vb.add_child(b)
	pc.reset_size()
	await get_tree().process_frame
	pc.position = (size - pc.size) * 0.5
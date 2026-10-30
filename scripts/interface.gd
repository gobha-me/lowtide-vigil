class_name VigilInterface
extends CanvasLayer

var hud: Label
var status: Label
var banner: Label
var overlay: ColorRect
var panel: VBoxContainer
var heading_font: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")


func _ready() -> void:
	var root := Control.new()
	root.theme = preload("res://assets/vigil_theme.tres")
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	hud = make_label("", 23)
	hud.position = Vector2(62, 22)
	hud.size = Vector2(1156, 62)
	root.add_child(hud)
	banner = make_label("", 28, true)
	banner.position = Vector2(65, 100)
	banner.size = Vector2(1150, 50)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(banner)
	status = make_label("", 21)
	status.position = Vector2(60, 685)
	status.size = Vector2(1160, 95)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(status)
	overlay = ColorRect.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0.025, 0.02, 0.055, 0.94)
	root.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	panel = VBoxContainer.new()
	panel.custom_minimum_size = Vector2(940, 0)
	panel.add_theme_constant_override("separation", 17)
	center.add_child(panel)


func make_label(text: String, size: int, heading: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if heading:
		label.add_theme_font_override("font", heading_font)
		label.add_theme_color_override("font_color", Color("ffcb8a"))
	return label


func show_panel(title: String, text: String) -> void:
	for child in panel.get_children():
		panel.remove_child(child)
		child.queue_free()
	overlay.show()
	var title_label := make_label(title, 36, true)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title_label)
	var body := make_label(text, 25)
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(940, 0)
	panel.add_child(body)


func add_button(text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(940, 62)
	button.pressed.connect(callback)
	panel.add_child(button)
	if panel.get_child_count() == 3:
		button.grab_focus()
	return button


func close_panel() -> void:
	overlay.hide()
	for child in panel.get_children():
		if child is Control:
			child.release_focus()


func update_hud(keeper: VigilKeeper, embers: int, room: int, upgrades: Array[String]) -> void:
	var flames := ""
	for index in keeper.max_hp:
		flames += "* " if index < keeper.hp else ". "
	var dash := "READY" if keeper.dash_cooldown <= 0.0 else "%.1fs" % keeper.dash_cooldown
	hud.text = (
		"LOWTIDE VIGIL     /     THE OVERGROWN NAVE                      DESCENT %d / 5\n" % room
		+ (
			"FLAMES  %s    EMBERS  %d    DASH  %s    |    %s"
			% [flames, embers, dash, ", ".join(upgrades)]
		)
	)

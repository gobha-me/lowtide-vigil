class_name VigilInterface
extends CanvasLayer

signal confirmed

var hud: Label
var status: Label
var banner: Label
var overlay: ColorRect
var panel: VBoxContainer
var heading_font: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")
var volume_label: Label
var volume_slider: HSlider
var mute_button: Button


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
	volume_label = null
	volume_slider = null
	mute_button = null
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
	button.pressed.connect(func(): confirmed.emit())
	button.pressed.connect(callback)
	panel.add_child(button)
	if panel.get_child_count() == 3:
		button.grab_focus()
	return button


func add_audio_controls(audio: VigilAudio) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size = Vector2(940, 52)
	row.add_theme_constant_override("separation", 18)
	panel.add_child(row)
	volume_label = make_label("", 23)
	volume_label.custom_minimum_size.x = 190
	row.add_child(volume_label)
	volume_slider = HSlider.new()
	volume_slider.max_value = 100.0
	volume_slider.step = 1.0
	volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	volume_slider.tooltip_text = "Master volume: use Left and Right to adjust."
	row.add_child(volume_slider)
	mute_button = Button.new()
	mute_button.custom_minimum_size.x = 280
	mute_button.pressed.connect(audio.toggle_mute)
	mute_button.pressed.connect(func(): confirmed.emit())
	row.add_child(mute_button)
	refresh_audio_controls(audio)
	volume_slider.value_changed.connect(func(value: float): audio.set_master_volume(value / 100.0))
	volume_slider.grab_focus()


func refresh_audio_controls(audio: VigilAudio) -> void:
	if not is_instance_valid(volume_slider):
		return
	volume_label.text = "MASTER %d%%" % roundi(audio.master_volume * 100.0)
	volume_slider.set_value_no_signal(audio.master_volume * 100.0)
	mute_button.text = "SOUND: MUTED [M]" if audio.muted else "SOUND: ON [M]"


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

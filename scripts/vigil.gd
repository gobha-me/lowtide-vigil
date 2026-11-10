extends Node2D
## Level 1: a bounded descent that keeps all combat and reward decisions local.

const KINDLES := [
	{"name": "Wick", "description": "+35% fire bolt damage.", "effect": "damage"},
	{"name": "Twin Wick", "description": "Fire a pair of diverging bolts.", "effect": "twin"},
	{"name": "Bellows", "description": "Fire bolts 25% faster.", "effect": "speed"},
	{
		"name": "Spare Wick",
		"description": "Gain and relight one maximum flame.",
		"effect": "health"
	},
	{"name": "Light Step", "description": "Dash recovers 25% sooner.", "effect": "dash"},
	{"name": "Phoenix Ash", "description": "Relight three missing flames.", "effect": "heal"},
]
const ROOM_REWARDS := [
	["KINDLE", "EMBERS", "ORDEAL"],
	["FONT", "SHOP", "KINDLE"],
	["ORDEAL", "EMBERS", "KINDLE"],
	["SHOP", "FONT", "ORDEAL"],
	["THE DROWNED TOLLING"],
]

var keeper: VigilKeeper
var ui: VigilInterface
var veil: Node2D
var foes: Array[VigilFoe] = []
var bolts: Array[VigilBolt] = []
var doors: Array[VigilDoor] = []
var state := "title"
var room := 0
var reward := ""
var embers := 0
var kills := 0
var room_time := 0.0
var banner_time := 0.0
var upgrades: Array[String] = []
var offered: Array = []
var shop_bought := false


func _ready() -> void:
	VigilControls.configure()
	add_child(preload("res://scripts/nave.gd").new())
	keeper = VigilKeeper.new()
	keeper.z_index = 2
	keeper.fired.connect(_fire_bolt)
	keeper.extinguished.connect(_lose_run)
	keeper.damaged.connect(func(): _announce("A flame gutters. Keep the vigil.", 1.2))
	add_child(keeper)
	veil = preload("res://scripts/veil.gd").new()
	veil.keeper = keeper
	veil.z_index = 10
	add_child(veil)
	ui = VigilInterface.new()
	add_child(ui)
	_show_title()
	if "--smoke" in OS.get_cmdline_user_args():
		var smoke := preload("res://scripts/export_smoke.gd").new()
		add_child(smoke)


func _process(delta: float) -> void:
	if state != "title":
		ui.update_hud(keeper, embers, room, upgrades)
	if Input.is_action_just_pressed("pause_run"):
		if state == "play":
			_pause_run()
		elif state == "paused":
			_resume_run()
	if state != "play":
		return
	room_time += delta
	banner_time = maxf(0.0, banner_time - delta)
	if banner_time <= 0.0:
		ui.banner.text = "THE OVERGROWN NAVE"
	keeper.step(delta)
	for foe: VigilFoe in foes.duplicate():
		if state != "play":
			break
		foe.step(delta, keeper)
	if state != "play":
		return
	_step_bolts(delta)
	if state != "play":
		return
	for door in doors:
		door.nearby = keeper.position.distance_to(door.position + Vector2(0, 20)) < 85
		door.queue_redraw()
		if door.unlocked and room_time > 0.9:
			if keeper.position.distance_to(door.position + Vector2(0, 20)) < 43:
				_enter_room(door.reward)
				break
	ui.update_hud(keeper, embers, room, upgrades)


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_fullscreen") and not event.is_echo():
		var fullscreen := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN
		DisplayServer.window_set_mode(
			(
				DisplayServer.WINDOW_MODE_WINDOWED
				if fullscreen
				else DisplayServer.WINDOW_MODE_FULLSCREEN
			)
		)
		get_viewport().set_input_as_handled()


func _show_title() -> void:
	state = "title"
	_clear_room()
	keeper.hide()
	veil.hide()
	ui.hud.text = ""
	ui.banner.text = "ONE NIGHT. ONE TIDE. ONE LIGHT."
	ui.status.text = "LEVEL 1  /  THE OVERGROWN NAVE"
	ui.show_panel(
		"LOWTIDE VIGIL",
		(
			"Once a year, the sea uncovers the drowned abbey of St. Maren.\n"
			+ "Tonight, the Saint below is weeping. You are the last bell-keeper.\n"
			+ "Carry her light down before dawn brings the water back.\n\n"
			+ "The town waits on the shore with candles."
		)
	)
	ui.add_button("BEGIN THE VIGIL", _start_run)
	ui.add_button("CONTROLS & THE LANTERN", _show_controls)
	ui.add_button("QUIT", get_tree().quit)


func _show_controls() -> void:
	ui.show_panel(
		"CARRY THE LIGHT",
		(
			"MOVE   WASD / left stick\n"
			+ "FIRE   hold left mouse / arrows / right stick\n"
			+ "DASH   Space / Shift / right mouse / controller A or RB\n"
			+ "PAUSE   Esc / P / controller Start\n\n"
			+ "FULLSCREEN   F11 (starts windowed)\n\n"
			+ "Dash through danger: you cannot be hurt during a dash.\n"
			+ "Flames are health. Each lost flame shrinks your lantern's light.\n"
			+ "Clear the room, then walk through a signed door to choose your reward.\n"
			+ "Menu: mouse, arrows and Enter, or controller D-pad and A."
		)
	)
	ui.add_button("BACK TO THE SHORE", _show_title)


func _start_run() -> void:
	_clear_room()
	keeper.hp = 5
	keeper.max_hp = 5
	keeper.damage = 1.0
	keeper.fire_interval = 0.25
	keeper.twin_wick = false
	keeper.max_dash_cooldown = VigilKeeper.DASH_COOLDOWN
	keeper.dash_left = 0.0
	keeper.dash_cooldown = 0.0
	keeper.invulnerable = 0.0
	keeper.fire_cooldown = 0.0
	keeper.facing = Vector2.UP
	keeper.dash_direction = Vector2.UP
	keeper.walking_time = 0.0
	keeper.position = Vector2(640, 560)
	keeper.show()
	veil.show()
	room = 0
	embers = 0
	kills = 0
	reward = ""
	offered.clear()
	shop_bought = false
	upgrades.clear()
	state = "play"
	room_time = 0.0
	ui.close_panel()
	_open_doors()
	ui.update_hud(keeper, embers, room, upgrades)
	_announce("The roots have broken the seal. Choose your descent.", 4.0)


func _clear_room() -> void:
	for foe in foes:
		foe.queue_free()
	foes.clear()
	for bolt in bolts:
		bolt.queue_free()
	bolts.clear()
	for door in doors:
		door.queue_free()
	doors.clear()


func _enter_room(chosen: String) -> void:
	_clear_room()
	room += 1
	reward = chosen
	room_time = 0.0
	keeper.position = Vector2(640, 585)
	keeper.dash_left = 0.0
	keeper.invulnerable = 0.8
	state = "play"
	ui.close_panel()
	ui.status.text = "Fire bolts to clear the room. Dash through the dark."
	if reward == "FONT":
		var restored := mini(2, keeper.max_hp - keeper.hp)
		keeper.hp += restored
		if restored == 0:
			embers += 12
		_announce("The Font relights %d flames. The shore feels closer." % restored, 4.0)
		_open_doors()
	elif reward == "SHOP":
		_show_shop()
	elif reward == "THE DROWNED TOLLING":
		_spawn_foe("boss", Vector2(640, 295))
		_announce("THE DROWNED TOLLING — The drowned bell calls you below.", 4.0)
	else:
		var count := 3 + room
		if reward == "ORDEAL":
			count += 1
		for index in count:
			var point := Vector2(220 + (index % 4) * 270, 280 + (index / 4) * 100)
			_spawn_foe("cantor" if index % 3 == 2 else "root", point, reward == "ORDEAL")
		_announce(
			(
				"ORDEAL — Hold the light; claim a stronger Kindle."
				if reward == "ORDEAL"
				else "Roots stir beneath the broken pews."
			),
			3.0
		)

	ui.update_hud(keeper, embers, room, upgrades)


func _spawn_foe(kind: String, point: Vector2, elite: bool = false) -> void:
	var foe := VigilFoe.new()
	foe.position = point
	foe.z_index = 2
	foe.setup(kind, elite)
	foe.shot.connect(_fire_hostile)
	foe.defeated.connect(_foe_defeated)
	foe.toll_changed.connect(
		func(): _announce("THE TOLLING BREAKS — Keep the lantern alight.", 3.0)
	)
	foes.append(foe)
	add_child(foe)


func _foe_defeated(foe: VigilFoe) -> void:
	foes.erase(foe)
	kills += 1
	embers += 5 if foe.elite else 3
	if foes.is_empty():
		if reward == "THE DROWNED TOLLING":
			_win_run()
		elif reward == "KINDLE" or reward == "ORDEAL":
			_show_kindles()
		else:
			embers += 22
			_announce("A hoard of embers. The doors are open.", 3.0)
			_open_doors()


func _open_doors() -> void:
	for bolt in bolts:
		bolt.spent = true
		bolt.queue_free()
	bolts.clear()
	state = "play"
	ui.close_panel()
	room_time = 0.0
	var rewards: Array = ROOM_REWARDS[mini(room, ROOM_REWARDS.size() - 1)]
	for index in rewards.size():
		var door := VigilDoor.new()
		door.reward = rewards[index]
		door.unlocked = true
		door.position = Vector2(640 + (index - (rewards.size() - 1) * 0.5) * 350, 220)
		door.z_index = 20
		doors.append(door)
		add_child(door)
	ui.update_hud(keeper, embers, room, upgrades)
	ui.status.text = (
		"ROOM CLEAR  /  Walk into a signed doorway to choose what waits beyond.\n"
		+ "KINDLE: upgrade   EMBERS: hoard   ORDEAL: elite reward   FONT: heal   SHOP: spend"
	)


func _show_kindles() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	state = "reward"
	offered = KINDLES.duplicate()
	offered.shuffle()
	offered.resize(3)
	ui.show_panel("CHOOSE A KINDLE", "One light, one choice. Carry it deeper.")
	for kindle: Dictionary in offered:
		ui.add_button(kindle.name + "  /  " + kindle.description, _take_kindle.bind(kindle))


func _take_kindle(kindle: Dictionary) -> void:
	_apply_kindle(kindle, 1.5 if reward == "ORDEAL" else 1.0)
	_open_doors()


func _apply_kindle(kindle: Dictionary, power: float = 1.0) -> void:
	upgrades.append(kindle.name)
	match kindle.effect:
		"damage":
			keeper.damage *= 1.0 + 0.35 * power
		"twin":
			var bonus_power := power if keeper.twin_wick else maxf(0.0, power - 1.0)
			keeper.damage *= 1.0 + 0.25 * bonus_power
			keeper.twin_wick = true
		"speed":
			keeper.fire_interval = maxf(0.08, keeper.fire_interval * (1.0 - 0.25 * power))
		"health":
			# Whole-flame rewards round up to retain fractional power.
			var flames := ceili(power)
			keeper.max_hp += flames
			keeper.hp += flames
		"dash":
			keeper.max_dash_cooldown *= 1.0 - 0.25 * power
		"heal":
			if power == 1.0:
				keeper.hp = mini(keeper.max_hp, keeper.hp + 3)
			else:
				keeper.hp = mini(keeper.max_hp, keeper.hp + ceili(3.0 * power))


func _show_shop() -> void:
	state = "shop"
	shop_bought = false
	offered = KINDLES.duplicate()
	offered.shuffle()
	_refresh_shop()


func _refresh_shop() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	ui.show_panel(
		"THE CANDLEWRIGHT",
		'"The shore is still watching, little wick."\nYou carry %d embers.' % embers
	)
	var ware: Dictionary = offered[0]
	var buy := ui.add_button(
		ware.name + "  /  " + ware.description + "  /  18 EMBERS", _buy_kindle.bind(ware)
	)
	buy.disabled = embers < 18 or shop_bought
	var mend := ui.add_button("MEND TWO FLAMES  /  10 EMBERS", _buy_mend)
	mend.disabled = embers < 10 or keeper.hp >= keeper.max_hp
	var leave := ui.add_button("LEAVE THE CANDLEWRIGHT", _open_doors)
	leave.grab_focus()


func _buy_kindle(kindle: Dictionary) -> void:
	if embers < 18 or shop_bought:
		return
	embers -= 18
	shop_bought = true
	_apply_kindle(kindle)
	_refresh_shop()


func _buy_mend() -> void:
	if embers < 10 or keeper.hp >= keeper.max_hp:
		return
	embers -= 10
	keeper.hp = mini(keeper.max_hp, keeper.hp + 2)
	_refresh_shop()


func _fire_bolt(origin: Vector2, direction: Vector2) -> void:
	_make_bolt(origin, direction, 640.0, false, keeper.damage)


func _fire_hostile(origin: Vector2, direction: Vector2, speed: float) -> void:
	_make_bolt(origin, direction, speed, true, 1.0)


func _make_bolt(
	origin: Vector2, direction: Vector2, speed: float, hostile: bool, damage: float
) -> void:
	var bolt := VigilBolt.new()
	bolt.position = origin
	bolt.direction = direction
	bolt.speed = speed
	bolt.hostile = hostile
	bolt.damage = damage
	bolt.z_index = 3
	bolts.append(bolt)
	add_child(bolt)


func _step_bolts(delta: float) -> void:
	for bolt: VigilBolt in bolts.duplicate():
		if state != "play":
			break
		var previous := bolt.position
		bolt.step(delta)
		if not bolt.spent:
			if bolt.hostile:
				if _bolt_near(keeper.position, previous, bolt.position, 16.0):
					keeper.hurt()
					bolt.spent = true
			else:
				for foe: VigilFoe in foes.duplicate():
					if _bolt_near(foe.position, previous, bolt.position, foe.radius + 5):
						foe.take_hit(bolt.damage)
						bolt.spent = true
						break
		if bolt.spent:
			bolts.erase(bolt)
			bolt.queue_free()


func _bolt_near(point: Vector2, from: Vector2, to: Vector2, radius: float) -> bool:
	return Geometry2D.get_closest_point_to_segment(point, from, to).distance_to(point) < radius


func _announce(text: String, duration: float) -> void:
	ui.banner.text = text
	banner_time = duration


func _pause_run() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	state = "paused"
	ui.show_panel("THE VIGIL WAITS", "The light holds while you rest.")
	ui.add_button("RESUME", _resume_run)
	ui.add_button("RESTART", _start_run)
	ui.add_button("RETURN TO SHORE", _show_title)


func _resume_run() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	state = "play"
	ui.close_panel()


func _lose_run() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	state = "lost"
	ui.show_panel(
		"THE LANTERN GOES OUT",
		(
			"The tide takes the nave. On the shore, a candle waits for you.\n"
			+ "%d foes silenced. %d embers carried.\nLight another lantern." % [kills, embers]
		)
	)
	ui.add_button("TRY THE VIGIL AGAIN", _start_run)
	ui.add_button("RETURN TO SHORE", _show_title)


func _win_run() -> void:
	ui.update_hud(keeper, embers, room, upgrades)
	state = "won"
	ui.show_panel(
		"THE TOLLING FALLS SILENT",
		(
			"The Overgrown Nave is open. Far below, the Saint is still weeping.\n"
			+ "A candle on the shore answers your lantern. The descent will continue.\n\n"
			+ "LEVEL 1 COMPLETE  /  %d foes silenced  /  %d embers\n" % [kills, embers]
			+ "Return to the shore. The Saint's vigil is not yet over."
		)
	)
	ui.add_button("CARRY ANOTHER LIGHT", _start_run)
	ui.add_button("RETURN TO SHORE", _show_title)

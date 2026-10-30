class_name VigilFoe
extends Node2D

signal shot(origin: Vector2, direction: Vector2, speed: float)
signal defeated(foe: VigilFoe)
signal toll_changed

var kind := "root"
var hp := 3.0
var max_hp := 3.0
var speed := 70.0
var radius := 18.0
var attack_clock := 1.5
var age := 0.0
var hit_flash := 0.0
var second_phase := false
var elite := false
var dead := false
var font: Font


func setup(foe_kind: String, is_elite: bool = false) -> void:
	kind = foe_kind
	elite = is_elite
	font = preload("res://assets/fonts/pixelifysans/PixelifySans-wght.ttf")
	if kind == "boss":
		max_hp = 100.0
		speed = 48.0
		radius = 40.0
		attack_clock = 2.0
	elif kind == "cantor":
		max_hp = 4.0
		speed = 44.0
	if elite:
		max_hp *= 1.8
		speed *= 1.15
		radius *= 1.2
	hp = max_hp


func step(delta: float, keeper: VigilKeeper) -> void:
	if dead:
		return
	age += delta
	hit_flash = maxf(0.0, hit_flash - delta)
	attack_clock -= delta
	var direction := (keeper.position - position).normalized()
	var distance := position.distance_to(keeper.position)
	if kind == "boss":
		position += direction * speed * delta * (1.35 if second_phase else 1.0)
		if hp < max_hp * 0.5 and not second_phase:
			second_phase = true
			toll_changed.emit()
		if attack_clock <= 0.0:
			attack_clock = 1.55 if second_phase else 2.1
			var count := 14 if second_phase else 10
			for index in count:
				var angle := TAU * index / count + age * 0.35
				shot.emit(position, Vector2.from_angle(angle), 155.0)
			shot.emit(position, direction, 220.0)
	elif kind == "cantor":
		if distance > 280.0:
			position += direction * speed * delta
		if attack_clock <= 0.0:
			attack_clock = 2.0
			shot.emit(position, direction, 175.0)
	else:
		position += direction * speed * delta
	position = position.clamp(Vector2(100, 205), Vector2(1180, 615))
	if distance < radius + 13.0:
		keeper.hurt()
	queue_redraw()


func take_hit(amount: float) -> void:
	if dead:
		return
	hp -= amount
	hit_flash = 0.09
	if hp <= 0.0:
		dead = true
		defeated.emit(self)
		queue_free()


func _draw() -> void:
	var ink := Color("d2c8ac") if kind == "cantor" else Color("63876f")
	if elite:
		ink = Color("d47b99")
	if hit_flash > 0.0:
		ink = Color("fff1d3")
	draw_circle(Vector2(0, radius * 0.6), radius * 0.85, Color(0, 0, 0, 0.3))
	if kind == "boss":
		draw_bell(ink)
	else:
		for index in 5:
			var angle := TAU * index / 5.0 + sin(age * 2.0) * 0.1
			draw_line(Vector2.ZERO, Vector2.from_angle(angle) * radius * 1.35, ink, 4, true)
		draw_circle(Vector2.ZERO, radius, ink)
		draw_circle(Vector2(-6, -3), 3.0, Color("1d2532"))
		draw_circle(Vector2(6, -3), 3.0, Color("1d2532"))
		if kind == "cantor":
			draw_arc(Vector2.ZERO, radius + 5, PI, TAU, 16, Color("c1a16d"), 3, true)
	if hp < max_hp:
		draw_rect(Rect2(-radius, -radius - 14, radius * 2, 5), Color("271b32"))
		draw_rect(Rect2(-radius, -radius - 14, radius * 2 * hp / max_hp, 5), ink)


func draw_bell(ink: Color) -> void:
	var bell_color := Color("bd865b") if not second_phase else Color("df7581")
	if hit_flash > 0.0:
		bell_color = ink
	draw_colored_polygon(
		PackedVector2Array(
			[
				Vector2(-43, 27),
				Vector2(-26, -28),
				Vector2(0, -43),
				Vector2(26, -28),
				Vector2(43, 27)
			]
		),
		bell_color
	)
	draw_arc(Vector2(0, -42), 10.0, PI, TAU, 12, bell_color, 5, true)
	draw_line(Vector2(-45, 28), Vector2(45, 28), Color("f3c889"), 7, true)
	draw_circle(Vector2(0, 36), 9.0, Color("372f40"))
	draw_line(Vector2(-12, -7), Vector2(10, 10), Color("372f40"), 6, true)
	if second_phase:
		draw_polyline(
			PackedVector2Array([Vector2(4, -38), Vector2(-9, -15), Vector2(9, 3), Vector2(0, 26)]),
			Color("fff0d2"),
			4,
			true
		)

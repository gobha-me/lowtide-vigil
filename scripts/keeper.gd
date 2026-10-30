class_name VigilKeeper
extends Node2D
## Flames drive both survivability and the veil's visible radius.

signal fired(origin: Vector2, direction: Vector2)
signal extinguished
signal damaged

const SPEED := 235.0
const DASH_SPEED := 790.0
const DASH_TIME := 0.19
const DASH_COOLDOWN := 0.85

var hp := 5
var max_hp := 5
var damage := 1.0
var fire_interval := 0.25
var twin_wick := false
var max_dash_cooldown := DASH_COOLDOWN
var dash_left := 0.0
var dash_cooldown := 0.0
var invulnerable := 0.0
var fire_cooldown := 0.0
var facing := Vector2.UP
var dash_direction := Vector2.UP
var arena := Rect2(95, 190, 1090, 430)
var walking_time := 0.0


func step(delta: float) -> void:
	dash_cooldown = maxf(0.0, dash_cooldown - delta)
	invulnerable = maxf(0.0, invulnerable - delta)
	fire_cooldown = maxf(0.0, fire_cooldown - delta)
	var movement := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var aim := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down")
	var shooting := aim.length() > 0.2
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		aim = (get_global_mouse_position() - position).normalized()
		shooting = true
	if shooting:
		facing = aim.normalized()
	if Input.is_action_just_pressed("dash") and dash_cooldown <= 0.0:
		dash_left = DASH_TIME
		dash_cooldown = max_dash_cooldown
		dash_direction = movement.normalized() if movement.length() > 0.1 else facing
	if dash_left > 0.0:
		position += dash_direction * DASH_SPEED * delta
		dash_left = maxf(0.0, dash_left - delta)
	else:
		position += movement * SPEED * delta
	position = position.clamp(arena.position, arena.end)
	walking_time += movement.length() * delta
	if shooting and fire_cooldown <= 0.0:
		fire_cooldown = fire_interval
		if twin_wick:
			fired.emit(position + facing * 22.0, facing.rotated(-0.10))
			fired.emit(position + facing * 22.0, facing.rotated(0.10))
		else:
			fired.emit(position + facing * 22.0, facing)
	queue_redraw()


func hurt() -> void:
	if dash_left > 0.0 or invulnerable > 0.0 or hp <= 0:
		return
	hp -= 1
	invulnerable = 1.1
	damaged.emit()
	if hp == 0:
		extinguished.emit()


func light_scale() -> float:
	return 0.5 + 0.5 * float(hp) / float(max_hp)


func _draw() -> void:
	if invulnerable > 0.0 and fmod(invulnerable, 0.14) < 0.06:
		return
	var glow := Color("ffc276")
	if dash_left > 0.0:
		draw_line(-dash_direction * 38.0, Vector2.ZERO, Color("8de5da"), 14.0, true)
	draw_ellipse_shadow()
	var bob := sin(walking_time * 15.0) * 2.0
	draw_colored_polygon(
		PackedVector2Array([Vector2(-14, 15), Vector2(0, -17 + bob), Vector2(14, 15)]),
		Color("5a8588")
	)
	draw_circle(Vector2(0, -14 + bob), 8.0, Color("d9b6a2"))
	draw_arc(Vector2(0, -15 + bob), 9.0, PI, TAU, 14, Color("233b4a"), 6.0, true)
	var lantern := facing * 21.0
	draw_line(Vector2(3, 0), lantern, Color("d9b6a2"), 4.0, true)
	draw_rect(Rect2(lantern - Vector2(7, 9), Vector2(14, 18)), Color("845c45"))
	draw_circle(lantern, 5.0, glow)
	draw_line(lantern, lantern + facing * 15.0, Color(glow, 0.6), 2.0, true)


func draw_ellipse_shadow() -> void:
	draw_set_transform(Vector2(0, 17), 0.0, Vector2(1, 0.3))
	draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.4))
	draw_set_transform(Vector2.ZERO)

class_name VigilBolt
extends Node2D

var direction := Vector2.UP
var speed := 640.0
var damage := 1.0
var hostile := false
var lifetime := 2.4
var spent := false


func step(delta: float) -> void:
	if spent:
		return
	position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0.0 or not Rect2(65, 160, 1150, 500).has_point(position):
		spent = true
	queue_redraw()


func _draw() -> void:
	var color := Color("eb7796") if hostile else Color("ffc979")
	draw_line(-direction * 14.0, Vector2.ZERO, Color(color, 0.4), 7.0, true)
	draw_circle(Vector2.ZERO, 5.0, color)
	draw_circle(-direction * 2.0, 2.5, Color("fff5d6"))

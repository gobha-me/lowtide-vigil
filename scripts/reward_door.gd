class_name VigilDoor
extends Node2D

const COLORS := {
	"KINDLE": Color("ffce7b"),
	"EMBERS": Color("f69b62"),
	"ORDEAL": Color("e47b9b"),
	"FONT": Color("8ce0ce"),
	"SHOP": Color("c4a3ed"),
	"THE DROWNED TOLLING": Color("df8697"),
}

var reward := "KINDLE"
var unlocked := false
var nearby := false
var heading: Font = preload("res://assets/fonts/silkscreen/Silkscreen-Regular.ttf")


func _draw() -> void:
	var color: Color = COLORS[reward]
	var shadow := Color("181523")
	draw_rect(Rect2(-43, -15, 86, 57), shadow)
	draw_arc(Vector2(0, -15), 43.0, PI, TAU, 24, color.darkened(0.45), 8, true)
	draw_line(Vector2(-43, -15), Vector2(-43, 42), color.darkened(0.45), 8, true)
	draw_line(Vector2(43, -15), Vector2(43, 42), color.darkened(0.45), 8, true)
	if unlocked:
		draw_rect(Rect2(-34, -15, 68, 55), Color(color, 0.15))
		draw_circle(Vector2(0, 12), 7, color)
	else:
		for index in 4:
			draw_line(Vector2(-30 + index * 20, -20), Vector2(-30 + index * 20, 38), shadow, 6)
	var text_size := 13 if reward.length() > 12 else 18
	var width := heading.get_string_size(reward, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size).x
	draw_rect(Rect2(-width * 0.5 - 12, -91, width + 24, 36), shadow)
	draw_string(
		heading, Vector2(-width * 0.5, -67), reward, HORIZONTAL_ALIGNMENT_LEFT, -1, text_size, color
	)
	if nearby and unlocked:
		draw_arc(Vector2(0, 15), 47, 0, TAU, 32, color, 2, true)

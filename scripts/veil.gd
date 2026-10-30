extends Node2D
## A feathered dark veil, cut around the lantern in canvas coordinates.

var keeper: VigilKeeper


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(keeper):
		return
	var center := keeper.position
	var radius := 355.0 * keeper.light_scale()
	for index in 96:
		var angle_a := TAU * index / 96.0
		var angle_b := TAU * (index + 1) / 96.0
		var a := Vector2.from_angle(angle_a)
		var b := Vector2.from_angle(angle_b)
		draw_colored_polygon(
			PackedVector2Array(
				[center + a * radius, center + a * 2200, center + b * 2200, center + b * radius]
			),
			Color(0.018, 0.015, 0.04, 0.92)
		)
		for ring in 7:
			var inner := radius - 56.0 + ring * 8.0
			draw_colored_polygon(
				PackedVector2Array(
					[
						center + a * inner,
						center + a * (inner + 8),
						center + b * (inner + 8),
						center + b * inner
					]
				),
				Color(0.018, 0.015, 0.04, (ring + 1) * 0.115)
			)

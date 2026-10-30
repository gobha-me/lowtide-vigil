extends Node2D
## Geometry-only abbey art: repeatable stones, water marks and creeping roots.


func _draw() -> void:
	draw_rect(Rect2(63, 163, 1154, 498), Color("222430"))
	for row in 10:
		for column in 24:
			var shade := 0.12 + float((row * 17 + column * 7) % 9) * 0.006
			var offset := 24 if row % 2 == 0 else 0
			var stone := Rect2(68 + column * 47 + offset, 168 + row * 48, 43, 44)
			stone = stone.intersection(Rect2(68, 168, 1144, 488))
			draw_rect(stone, Color(shade, shade + 0.018, shade + 0.035))
	draw_rect(Rect2(515, 170, 250, 480), Color(0.35, 0.22, 0.25, 0.25))
	for x in [85, 1195]:
		for y in [270, 440, 610]:
			draw_circle(Vector2(x, y + 9), 33, Color("111824"))
			draw_rect(Rect2(x - 18, y - 30, 36, 60), Color("414653"))
			draw_rect(Rect2(x - 25, y - 31, 50, 9), Color("59616a"))
			draw_rect(Rect2(x - 25, y + 24, 50, 10), Color("59616a"))
	for side in 2:
		var start := Vector2(110 + side * 1040, 640)
		for branch in 7:
			var end := start + Vector2((1 - side * 2) * (80 + branch * 29), -60 - branch * 35)
			draw_line(start, end, Color("344e48"), 5, true)
			draw_line(end, end + Vector2(35 - branch * 8, -40), Color("436352"), 3, true)
			for leaf in 4:
				var point := start.lerp(end, float(leaf + 1) / 5.0)
				draw_circle(point + Vector2(8, -5), 7, Color("426552"))
	for index in 8:
		var point := Vector2(155 + index * 137, 630 - (index % 3) * 110)
		draw_arc(point, 24, 0.15, 2.7, 18, Color(0.25, 0.52, 0.53, 0.24), 3, true)
	draw_rect(Rect2(62, 162, 1156, 500), Color("5a585d"), false, 5)

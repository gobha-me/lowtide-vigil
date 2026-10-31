extends GutTest
## VigilBolt: travel, lifetime and the arena bounds.


func _make_bolt(origin: Vector2, direction: Vector2, speed: float) -> VigilBolt:
	var bolt := VigilBolt.new()
	bolt.position = origin
	bolt.direction = direction
	bolt.speed = speed
	add_child_autofree(bolt)
	return bolt


func test_step_moves_along_direction_at_speed() -> void:
	var bolt := _make_bolt(Vector2(640, 400), Vector2.RIGHT, 100.0)
	bolt.step(0.1)
	assert_almost_eq(bolt.position.x, 650.0, 0.0001)
	assert_almost_eq(bolt.position.y, 400.0, 0.0001)
	assert_false(bolt.spent)


func test_spent_when_lifetime_expires() -> void:
	var bolt := _make_bolt(Vector2(640, 400), Vector2.RIGHT, 100.0)
	bolt.lifetime = 0.05
	bolt.step(0.05)
	assert_true(Rect2(65, 160, 1150, 500).has_point(bolt.position))
	assert_true(bolt.spent)


func test_spent_when_leaving_arena() -> void:
	var bolt := _make_bolt(Vector2(640, 165), Vector2.UP, 640.0)
	bolt.step(0.05)
	assert_true(bolt.lifetime > 0.0)
	assert_true(bolt.spent)

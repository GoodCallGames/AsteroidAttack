extends RefCounted

# The temporary powers a ship can pick up. One power at a time per ship; picking up another replaces it.
#   MAGNET   nearby asteroids are pulled toward the ship
#   TURBO    faster thrust, and the pulse recharges four times as fast
#   FREEZE   the level clock stops
#   HEAVY    the ship becomes heavy: it ploughs asteroids ahead of it and is hard to push around

enum Type { MAGNET, TURBO, FREEZE, HEAVY }

const DATA := {
	Type.MAGNET: {"name": "MAGNET", "color": Color(1.0, 0.35, 0.42), "duration": 8.0},
	Type.TURBO: {"name": "TURBO", "color": Color(1.0, 0.58, 0.15), "duration": 7.0},
	Type.FREEZE: {"name": "TIME FREEZE", "color": Color(0.7, 0.95, 1.0), "duration": 5.0},
	Type.HEAVY: {"name": "HEAVY BUMPER", "color": Color(0.78, 0.7, 1.0), "duration": 8.0},
}

# tuning, in one place
const MAGNET_RADIUS := 560.0
const MAGNET_FORCE := 1500.0
const TURBO_THRUST := 1.6
const TURBO_PULSE_COOLDOWN := 0.25
const HEAVY_MASS := 4.0
const HEAVY_THRUST := 3.0


static func power_name(type: int) -> String:
	return DATA[type].name


static func power_color(type: int) -> Color:
	return DATA[type].color


static func power_duration(type: int) -> float:
	return DATA[type].duration


# draw a power's icon in white, centred on `at`, about `r` pixels across, on any CanvasItem
static func draw_icon(canvas: CanvasItem, type: int, at: Vector2, r: float) -> void:
	var white := Color(1, 1, 1, 0.95)
	match type:
		Type.MAGNET:
			# a horseshoe with two bright tips
			canvas.draw_arc(at + Vector2(0, -r * 0.05), r * 0.5, PI, TAU, 24, white, r * 0.2, true)
			for side in [-1.0, 1.0]:
				canvas.draw_line(at + Vector2(side * r * 0.5, -r * 0.05), at + Vector2(side * r * 0.5, r * 0.5), white, r * 0.2)
				canvas.draw_line(at + Vector2(side * r * 0.5, r * 0.28), at + Vector2(side * r * 0.5, r * 0.55), Color(1.0, 0.3, 0.35), r * 0.2)
		Type.TURBO:
			# a lightning bolt
			var bolt := PackedVector2Array([
				Vector2(0.15, -0.75), Vector2(-0.4, 0.05), Vector2(-0.02, 0.05),
				Vector2(-0.18, 0.78), Vector2(0.42, -0.14), Vector2(0.05, -0.14)])
			for i in bolt.size():
				bolt[i] = at + bolt[i] * r * 0.8
			canvas.draw_colored_polygon(bolt, white)
		Type.FREEZE:
			# a snowflake: three crossing lines with small tips
			for i in 3:
				var dir := Vector2.from_angle(PI / 3.0 * i + PI / 6.0)
				canvas.draw_line(at - dir * r * 0.62, at + dir * r * 0.62, white, r * 0.13)
				for end in [-1.0, 1.0]:
					var tip: Vector2 = at + dir * r * 0.42 * end
					canvas.draw_line(tip, tip + (dir.rotated(0.8) * end) * r * 0.2, white, r * 0.1)
					canvas.draw_line(tip, tip + (dir.rotated(-0.8) * end) * r * 0.2, white, r * 0.1)
		Type.HEAVY:
			# a solid hexagon with a bar through it, like a weight
			var hex := PackedVector2Array()
			for i in 6:
				hex.append(at + Vector2.from_angle(PI / 3.0 * i + PI / 6.0) * r * 0.62)
			canvas.draw_colored_polygon(hex, white)
			canvas.draw_line(at + Vector2(-r * 0.4, 0), at + Vector2(r * 0.4, 0), Color(0.45, 0.35, 0.8), r * 0.16)

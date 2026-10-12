shader_type canvas_item;

// Circular iris wipe for scene changes. The visible "hole" shrinks to a point (closing) or grows from it (opening),
// with a mint rim and a purple glow on the cover next to the edge, matching the game's pulse rings.

uniform float progress : hint_range(0.0, 1.0) = 0.0;  // 0 = fully open, 1 = fully covered
uniform vec2 center = vec2(0.5);                       // where the iris closes on, 0..1 of the screen
uniform vec2 screen_size = vec2(1280.0, 720.0);

uniform vec4 cover_color : source_color = vec4(0.02, 0.03, 0.06, 1.0);
uniform vec4 rim_color : source_color = vec4(0.5, 1.0, 0.8, 1.0);
uniform vec4 glow_color : source_color = vec4(0.85, 0.45, 1.0, 1.0);

void fragment() {
	vec2 px = UV * screen_size;
	vec2 c = center * screen_size;
	float d = length(px - c);

	// radius needed to reveal the whole screen from this centre (distance to the farthest corner)
	float rmax = max(
		max(length(c), length(vec2(screen_size.x, 0.0) - c)),
		max(length(vec2(0.0, screen_size.y) - c), length(screen_size - c)));
	float radius = (1.0 - progress) * rmax * 1.03;

	float outside = smoothstep(radius - 1.5, radius + 1.5, d);

	// bright rim right on the edge, a fainter second ring just outside it
	float rim = 1.0 - smoothstep(0.0, 6.0, abs(d - radius));
	float echo = (1.0 - smoothstep(0.0, 4.0, abs(d - (radius + 34.0)))) * 0.35 * step(0.001, progress);

	// purple glow on the cover close to the edge
	float glow = outside * (1.0 - smoothstep(0.0, 110.0, d - radius)) * 0.4;

	vec3 rgb = cover_color.rgb;
	rgb = mix(rgb, glow_color.rgb, glow);
	rgb = mix(rgb, rim_color.rgb, max(rim * 0.95, echo * outside));
	float a = max(max(outside, rim * 0.95), echo * outside);

	// fully open: nothing drawn at all, so no rim artefacts at the corners
	a *= step(0.001, progress);
	COLOR = vec4(rgb, a);
}

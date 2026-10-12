shader_type canvas_item;

// Map edge in the game's flat, layered style: a few stacked tone steps with wobbly,
// slowly drifting outlines (like paper-cut cloud layers), ending in a solid dark wall.
// Everything is computed from world position, so one big quad covers it.

uniform sampler2D noise_tex : repeat_enable, filter_linear;

// The whole effect is drawn behind the planets (see Background in game.tscn).
// show_layers / show_wall can split it into two passes if a node needs only one.
uniform bool show_layers = true;
uniform bool show_wall = true;

uniform vec2 center = vec2(0.0);
uniform float edge_radius = 1505.0;          // where the collision wall is

// Each layer begins this many world px inside the edge.
uniform float layer1_dist = 480.0;
uniform float layer2_dist = 270.0;
uniform float wall_dist = 10.0;              // wall front sits this far inside the collision edge

uniform float layer1_wobble = 160.0;         // how far each outline wanders with the noise
uniform float layer2_wobble = 110.0;
uniform float wall_wobble = 30.0;
uniform float edge_softness = 5.0;           // outline softness in world px (small = crisp, flat)

uniform vec4 layer1_color : source_color = vec4(0.3, 0.8, 0.65, 1.0);
uniform float layer1_alpha : hint_range(0.0, 1.0) = 0.12;
uniform vec4 layer2_color : source_color = vec4(0.12, 0.45, 0.4, 1.0);
uniform float layer2_alpha : hint_range(0.0, 1.0) = 0.28;
uniform vec4 wall_color : source_color = vec4(0.03, 0.05, 0.07, 1.0);

uniform vec4 rim_color : source_color = vec4(0.5, 1.0, 0.8, 1.0);
uniform float rim_alpha : hint_range(0.0, 1.0) = 0.35;
uniform float rim_width = 6.0;

// flat, barely-there blobs drifting in the void so it isn't a dead black fill
uniform vec4 void_blob_color : source_color = vec4(0.1, 0.25, 0.25, 1.0);
uniform float void_blob_alpha : hint_range(0.0, 0.5) = 0.22;

// impact ripple, driven from player.gd when the ship hits the wall
uniform vec2 hit_pos = vec2(0.0);
uniform float hit_progress : hint_range(0.0, 1.0) = 1.0;   // 0 = just hit, 1 = finished
uniform float hit_strength : hint_range(0.0, 1.0) = 0.0;
uniform float hit_reach = 750.0;             // how far the ripple travels along the wall
uniform float hit_bulge = 34.0;              // how far the wall front is pushed out as it passes

uniform float noise_scale = 0.0007;          // lower = bigger, calmer shapes
uniform vec2 scroll_speed = vec2(0.010, 0.006);

varying vec2 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// composite colour c with alpha a over dst (straight alpha)
vec4 over(vec4 dst, vec3 c, float a) {
	float out_a = a + dst.a * (1.0 - a);
	vec3 out_rgb = (c * a + dst.rgb * dst.a * (1.0 - a)) / max(out_a, 0.0001);
	return vec4(out_rgb, out_a);
}

void fragment() {
	vec2 p = world_pos - center;
	float d = length(p);
	vec2 uv = p * noise_scale;

	// each outline uses its own slowly drifting noise so the layers move independently
	float n1 = texture(noise_tex, uv + TIME * scroll_speed).r;
	float n2 = texture(noise_tex, uv * 1.3 + vec2(0.37, 0.61) - TIME * scroll_speed * 0.8).r;
	float n3 = texture(noise_tex, uv * 0.6 + vec2(0.8, 0.2) + TIME * scroll_speed * 0.4).r;

	float t1 = edge_radius - layer1_dist;
	float t2 = edge_radius - layer2_dist;
	float tw = edge_radius - wall_dist;

	float d1 = d + (n1 - 0.5) * layer1_wobble;
	float d2 = d + (n2 - 0.5) * layer2_wobble;
	// ripple: a band travelling outward from the hit point, plus a flash that fades at the impact
	float hd = length(world_pos - hit_pos);
	float hit_fade = pow(1.0 - hit_progress, 1.6) * hit_strength;
	float ripple = exp(-pow((hd - hit_progress * hit_reach) / 70.0, 2.0)) * hit_fade;
	float flash = exp(-pow(hd / 200.0, 2.0)) * hit_fade;

	float dw = d + (n1 - 0.5) * wall_wobble - ripple * hit_bulge;

	float m1 = smoothstep(t1 - edge_softness, t1 + edge_softness, d1);
	float m2 = smoothstep(t2 - edge_softness, t2 + edge_softness, d2);
	float mw = smoothstep(tw - edge_softness, tw + edge_softness, dw);

	vec4 col = vec4(0.0);

	if (show_layers) {
		col = over(col, layer1_color.rgb, m1 * layer1_alpha);
		col = over(col, layer2_color.rgb, m2 * layer2_alpha);
		// the haze lights up where the wall was hit
		col = over(col, rim_color.rgb, m1 * (flash * 0.28 + ripple * 0.22));
	}

	if (show_wall) {
		// mint outline hugging the front of the wall, drawn like a cartoon rim
		float rim = 1.0 - smoothstep(rim_width - edge_softness, rim_width + edge_softness, abs(dw - tw));
		col = over(col, rim_color.rgb, clamp(rim * (rim_alpha + flash * 0.5 + ripple * 0.5), 0.0, 1.0));

		// solid wall: fully opaque so nothing behind it (planets, stars) shows through
		col = over(col, wall_color.rgb, mw);

		// flat blobs inside the void, only visible past the wall
		float blob = smoothstep(0.55, 0.57, n3) * mw * void_blob_alpha;
		col = over(col, void_blob_color.rgb, blob);
	}

	COLOR = col;
}

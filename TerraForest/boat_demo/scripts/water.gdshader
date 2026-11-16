shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// Wave constants are duplicated in water_surface.gd so buoyancy probes sample
// the same surface that is rendered here. Change both together.
const vec3 W1 = vec3(0.35, 0.22, 1.15);
const float A1 = 0.055;
const vec3 W2 = vec3(-0.21, 0.47, 1.6);
const float A2 = 0.035;
const vec3 W3 = vec3(0.58, -0.31, 2.1);
const float A3 = 0.022;

uniform float water_time = 0.0;
uniform vec3 deep_color : source_color = vec3(0.012, 0.062, 0.090);
uniform vec3 shelf_color : source_color = vec3(0.075, 0.260, 0.290);
uniform vec3 horizon_color : source_color = vec3(0.300, 0.430, 0.540);

float wave_height(vec2 p) {
	return A1 * sin(dot(W1.xy, p) + W1.z * water_time)
		+ A2 * sin(dot(W2.xy, p) + W2.z * water_time)
		+ A3 * sin(dot(W3.xy, p) + W3.z * water_time);
}

vec2 wave_gradient(vec2 p) {
	vec2 g;
	g.x = A1 * W1.x * cos(dot(W1.xy, p) + W1.z * water_time)
		+ A2 * W2.x * cos(dot(W2.xy, p) + W2.z * water_time)
		+ A3 * W3.x * cos(dot(W3.xy, p) + W3.z * water_time);
	g.y = A1 * W1.y * cos(dot(W1.xy, p) + W1.z * water_time)
		+ A2 * W2.y * cos(dot(W2.xy, p) + W2.z * water_time)
		+ A3 * W3.y * cos(dot(W3.xy, p) + W3.z * water_time);
	return g;
}

void vertex() {
	vec2 p = VERTEX.xz;
	VERTEX.y += wave_height(p);
	vec2 g = wave_gradient(p);
	NORMAL = normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	vec3 view = normalize(-VERTEX);
	float fresnel = pow(1.0 - clamp(dot(NORMAL, view), 0.0, 1.0), 4.0);
	vec3 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float ripple = 0.5 + 0.5 * sin(world.x * 2.1 + world.z * 1.7 + water_time * 1.3);
	vec3 base = mix(deep_color, shelf_color, clamp(0.22 + 0.30 * ripple, 0.0, 1.0));
	ALBEDO = mix(base, horizon_color, fresnel * 0.6);
	ROUGHNESS = mix(0.06, 0.24, fresnel);
	SPECULAR = 0.6;
	METALLIC = 0.0;
}

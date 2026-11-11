shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 neon_color : source_color = vec4(0.035, 0.36, 1.0, 1.0);
void fragment() {
	// Feather both radial edges; additive energy leaves the scene visible.
	float fade = smoothstep(0.0, 0.30, UV.y) * (1.0 - smoothstep(0.65, 1.0, UV.y));
	ALBEDO = neon_color.rgb * fade * 0.95;
	EMISSION = vec3(0.0);
	ALPHA = 1.0;
}

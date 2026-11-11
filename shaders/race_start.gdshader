shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add, shadows_disabled, fog_disabled;
uniform vec4 neon_color : source_color = vec4(1.0, 0.13, 0.58, 1.0);
varying float height_fade;
void vertex() {
	height_fade = clamp((2.5 - VERTEX.y) / 5.0, 0.0, 1.0);
}
void fragment() {
	float gradient = pow(height_fade, 1.4);
	ALBEDO = neon_color.rgb * gradient * 0.22;
	EMISSION = vec3(0.0);
	// Additive light transmits the scene underneath; fading lives in the additive color.
	ALPHA = 1.0;
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;

uniform sampler2D cloud_atlas : filter_linear, repeat_disable;
uniform vec4 top_color : source_color = vec4(1.0,0.61,0.87,1.0);
uniform vec4 bottom_color : source_color = vec4(0.81,0.20,0.56,1.0);
uniform float opacity = 0.68;
uniform float view_radius_m = 1900.0;
varying float cloud_alpha;
varying float atlas_tile;

void vertex() {
	// Camera-facing flat sprites in world space. Only presentation changes;
	// translation retains the original finite geographic-relative position.
	float d = length(MODEL_MATRIX[3].xz-CAMERA_POSITION_WORLD.xz);
	cloud_alpha = INSTANCE_CUSTOM.w*(1.0-smoothstep(view_radius_m*0.72,view_radius_m,d));
	atlas_tile = floor(INSTANCE_CUSTOM.z+0.5);
	MODELVIEW_MATRIX[0] = vec4(1.0,0.0,0.0,0.0);
	MODELVIEW_MATRIX[1] = vec4(0.0,1.0,0.0,0.0);
	MODELVIEW_MATRIX[2] = vec4(0.0,0.0,1.0,0.0);
	// Zero-area triangles outside the fade radius avoid rasterizing invisible
	// transparent quads from the recycled guard ring.
	VERTEX.xy *= INSTANCE_CUSTOM.xy*step(d,view_radius_m);
}

void fragment() {
	float mask = texture(cloud_atlas,vec2((UV.x+atlas_tile)*0.25,UV.y)).a;
	if (mask < 0.01) { discard; }
	ALBEDO = mix(top_color.rgb,bottom_color.rgb,smoothstep(0.25,0.85,UV.y));
	ALPHA = mask*opacity*cloud_alpha;
}

shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform sampler2D illustrated_smoke : source_color, filter_linear, repeat_disable;
varying float opacity;
void vertex() {
	float age=INSTANCE_CUSTOM.x;
	float angle=INSTANCE_CUSTOM.y*6.2831853;
	vec2 p=VERTEX.xy;
	VERTEX.xy=mat2(vec2(cos(angle),sin(angle)),vec2(-sin(angle),cos(angle)))*p*INSTANCE_CUSTOM.z*(0.35+age*1.15);
	MODELVIEW_MATRIX[0]=vec4(1.0,0.0,0.0,0.0);
	MODELVIEW_MATRIX[1]=vec4(0.0,1.0,0.0,0.0);
	MODELVIEW_MATRIX[2]=vec4(0.0,0.0,1.0,0.0);
	opacity=smoothstep(0.0,0.10,age)*(1.0-smoothstep(0.65,1.0,age))*INSTANCE_CUSTOM.w;
}
void fragment(){
	vec4 ink=texture(illustrated_smoke,UV);
	if(ink.a<0.01){discard;}
	ALBEDO=ink.rgb;
	ALPHA=ink.a*opacity;
}

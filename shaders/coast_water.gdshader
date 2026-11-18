shader_type spatial;
render_mode cull_disabled;
varying vec2 world_xz;
void vertex() {
	world_xz=(MODEL_MATRIX*vec4(VERTEX,1.0)).xz;
	VERTEX.y+=.08*sin(dot(world_xz,vec2(.42,.27))-TIME*1.2)+.04*sin(dot(world_xz,vec2(-.17,.53))+TIME*.8);
}
void fragment() {
	vec2 p=world_xz;
	float a=dot(p,vec2(.42,.27))-TIME*1.2;
	float b=dot(p,vec2(-.17,.53))+TIME*.8;
	float swell=sin(a)*.65+sin(b)*.35;
	float crest=smoothstep(.78,1.0,swell);
	float small=sin(dot(p,vec2(2.7,1.8))+TIME*2.1)*sin(dot(p,vec2(-1.9,3.1))-TIME*1.6);
	ALBEDO=mix(vec3(.025,.12,.22),vec3(.035,.36,.43),swell*.5+.5);
	ALBEDO=mix(ALBEDO,vec3(.24,.70,.76),crest*.35);
	NORMAL=normalize(NORMAL+vec3(cos(a)*.12,0.0,cos(b)*.10));
	ROUGHNESS=.24;METALLIC=.20;SPECULAR=.65;
	EMISSION=vec3(.015,.12,.17)*(crest*.55+max(0.0,small-.9)*.6);
}

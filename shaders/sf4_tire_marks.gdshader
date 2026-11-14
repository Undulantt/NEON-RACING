shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, shadows_disabled;
uniform float clock_mod=0.0;
uniform float lifetime_s=16.0;
varying float born;
varying float strength;
varying float seed;
void vertex(){born=INSTANCE_CUSTOM.x;strength=INSTANCE_CUSTOM.y;seed=INSTANCE_CUSTOM.z;}
void fragment(){
	float age=mod(clock_mod-born+64.0,64.0)/lifetime_s;
	float edge=0.08+sin(UV.y*15.0+seed*11.0)*0.025;
	float mask=smoothstep(0.0,edge,UV.x)*(1.0-smoothstep(1.0-edge,1.0,UV.x));
	float stripes=mix(0.78,1.0,step(0.15,fract(UV.x*5.0)));
	ALBEDO=vec3(0.008,0.009,0.015);
	ALPHA=mask*stripes*strength*(1.0-smoothstep(0.65,1.0,age))*0.82;
}

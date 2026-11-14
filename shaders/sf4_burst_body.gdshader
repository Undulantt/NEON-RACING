shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, shadows_disabled;
uniform float progress=0.0;
uniform float strength=0.85;
uniform float clock=0.0;
uniform float turbo_flash=0.0;
varying vec3 panel_position;
varying vec3 panel_normal;
void vertex(){
	panel_position=VERTEX;
	panel_normal=NORMAL;
	VERTEX+=NORMAL*0.002;
}
void fragment(){
	vec3 n=abs(panel_normal);
	vec2 p=n.y>0.55?panel_position.xz:(n.x>0.55?panel_position.yz:panel_position.xy);
	vec2 cell=abs(fract(p*3.5)-0.5);
	float grid=1.0-smoothstep(0.013,0.035,min(cell.x,cell.y));
	float diagonal=1.0-smoothstep(0.012,0.032,abs(fract((p.x+p.y)*3.5)-0.5));
	float sweep=pow(max(0.0,sin(p.y*5.0-clock*4.0)),12.0);
	float edge=pow(1.0-clamp(abs(dot(normalize(NORMAL),normalize(VIEW))),0.0,1.0),2.4);
	float circuitry=smoothstep(0.20,0.60,progress);
	float lattice=smoothstep(0.60,0.95,progress);
	float dots=(1.0-smoothstep(0.025,0.07,length(fract(p*3.5)-0.5)))*max(0.0,sin(clock*5.0+floor(p.x*3.5)*2.3));
	float mask=edge*progress*0.55+grid*circuitry*0.45+diagonal*lattice*0.25+sweep*circuitry*0.12+dots*lattice*0.4;
	vec3 color=mix(vec3(0.16,0.8,1.0),vec3(1.0,0.04,0.55),0.5+0.5*sin(p.y*2.0+clock*1.4));
	ALBEDO=color*min(mask,0.85)*strength+vec3(0.12,0.75,1.0)*edge*turbo_flash*0.32;
	ALPHA=1.0;
}

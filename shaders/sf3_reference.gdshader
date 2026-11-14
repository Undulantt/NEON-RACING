shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 base_color : source_color = vec4(1.0);
uniform bool lamp = false;
uniform bool edge = false;
uniform vec3 anchor = vec3(0.0);
uniform float radius_m = 85.0;
uniform float spacing_m = 5.0;
uniform float paint_gain = 0.0;
uniform float edge_gain = 0.0;
uniform float lamp_gain = 0.0;
varying vec3 world_pos;
void vertex(){ world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float cell_hash(vec2 p){ return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
void fragment(){
 float nearby=1.0-smoothstep(radius_m*0.55,radius_m,distance(world_pos.xz,anchor.xz));
 nearby*=1.0-smoothstep(4.0,10.0,abs(world_pos.y-anchor.y-(lamp?6.8:0.0)));
 vec3 color=COLOR.rgb*base_color.rgb;
 // Use chromatic contrast instead of multiplying already saturated cyan.
 vec3 enhanced=mix(color,vec3(0.98,0.99,1.0),clamp(nearby*paint_gain,0.0,1.0));
 if(edge){
  float ticks=smoothstep(0.45,0.75,cell_hash(floor(world_pos.xz/spacing_m)));
  vec3 reference=mix(color*0.60,vec3(0.92,0.98,1.0),ticks);
  enhanced=mix(color,reference,clamp(nearby*edge_gain,0.0,1.0));
 }
 if(lamp){
  float emitter=step(0.8,COLOR.r)*step(0.65,COLOR.b);
  enhanced=mix(color,vec3(1.0,0.94,1.0),clamp(nearby*lamp_gain*emitter,0.0,1.0));
 }
 ALBEDO=enhanced;
}

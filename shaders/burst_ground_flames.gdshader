shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform float clock = 0.0;
uniform float strength = 1.0;
varying vec4 track_data;
varying vec2 plane_kind;

void vertex() {
 track_data = INSTANCE_CUSTOM;
 plane_kind = UV2;
}

float fire_hash(vec2 p) {
 p = mod(p,32.0);
 return fract(sin(dot(p,vec2(127.1,311.7))) * 43758.5453);
}
float fire_noise(vec2 p) {
 vec2 cell = floor(p);
 vec2 f = fract(p);
 f = f*f*(3.0-2.0*f);
 return mix(mix(fire_hash(cell),fire_hash(cell+vec2(1.0,0.0)),f.x),mix(fire_hash(cell+vec2(0.0,1.0)),fire_hash(cell+vec2(1.0,1.0)),f.x),f.y);
}
void fragment() {
 float fade = 1.0 - smoothstep(0.35, 1.0, track_data.r);
 float start = track_data.g * 8.0;
 float track_phase = track_data.a * 2.1;
 float distance = start + UV.x * track_data.b;
 bool ground = max(plane_kind.x,plane_kind.y) < 0.5;
 bool cross_flame = plane_kind.y > 0.5;
 if (cross_flame) { distance = start + 0.5 * track_data.b + (UV.x - 0.5) * 0.4; }
 // Periodic waves join seamlessly across adjacent segments and the 8 m UV wrap.
 float flow = sin(distance * 9.424778 - clock * 6.283185 + track_phase);
 float detail = sin(distance * 17.278760 + clock * 9.424778 + track_phase * 2.0);
 float heat = 0.72 + flow * 0.16 + detail * 0.10;
 float alpha;
 vec3 pink;
 if (ground) {
  float width = abs(UV.y * 2.0 - 1.0);
  float edge = 1.0 - smoothstep(0.42, 1.0, width);
  pink = mix(vec3(1.0,0.015,0.34),vec3(1.0,0.34,0.70),edge * 0.7);
  alpha = edge * 0.58;
 } else {
  float height = UV.y;
  float tip = heat;
  if (cross_flame) {
   tip *= pow(max(0.0,1.0-abs(UV.x*2.0-1.0)),0.55);
  }
  float silhouette = 1.0 - smoothstep(tip-0.12,tip+0.03,height);
  float tongues = 0.70 + 0.30 * sin(distance * 21.991148 - height * 8.0 + clock * 12.566370);
  float turbulence = fire_noise(vec2(distance*4.0+height*1.8,height*3.5-clock*4.0+track_phase));
  float combustion = smoothstep(height*0.8+0.02,height*0.8+0.28,turbulence+(1.0-height)*0.35);
  alpha = silhouette * combustion * pow(1.0-height,0.32) * tongues * (cross_flame ? 0.42 : 0.75);
  pink = mix(vec3(1.0,0.015,0.42),vec3(1.0,0.62,0.88),pow(1.0-height,3.0));
 }
 // Explicit additive energy masking also removes the quad outside the flame.
 float energy = alpha * fade * strength;
 ALBEDO = pink * energy * 1.8;
 EMISSION = vec3(0.0);
 ALPHA = 1.0;
}

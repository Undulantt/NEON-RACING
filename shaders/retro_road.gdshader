shader_type spatial;
render_mode cull_disabled;
uniform vec4 segments[16];
uniform float widths[16];
uniform int segment_count = 0;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
 vec2 i=floor(p);vec2 u=fract(p);u=u*u*(3.0-2.0*u);
 return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
void fragment(){
 vec2 p=world_pos.xz; float distance_to_axis=10000.0; float half_width=10.0;
 for(int i=0;i<16;i++){
  if(i>=segment_count){break;}
  vec2 a=segments[i].xy;vec2 v=segments[i].zw-a;
  float t=clamp(dot(p-a,v)/max(dot(v,v),0.001),0.0,1.0);
  float d=length(p-a-v*t);
  if(d<distance_to_axis){distance_to_axis=d;half_width=widths[i]*0.5;}
 }
 float grain=mix(hash(floor(p*60.0)),0.5,clamp(length(fwidth(p))*40.0,0.0,1.0));
 float reflected=exp(-abs(distance_to_axis-half_width)*0.38)*(0.35+0.65*pow(max(sin(p.y*0.22+p.x*0.07),0.0),8.0));
 float center=(1.0-smoothstep(0.07,0.13,abs(distance_to_axis-0.13)));
 float dash=(1.0-smoothstep(0.06,0.13,abs(distance_to_axis-half_width*0.48)))*step(0.45,fract(p.y/8.0));
 float mask=(1.0-smoothstep(4.0,14.0,distance_to_axis-half_width));
 float pool=exp(-pow((distance_to_axis-half_width+2.0)/3.0,2.0))*pow(max(cos((p.y*0.93-p.x*0.36)*0.21),0.0),10.0);
 float fresnel=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
 float wet=smoothstep(0.30,0.78,noise(p*0.12));
 vec3 purple=vec3(0.065,0.045,0.11);
 ALBEDO=purple*(0.75+grain*0.25)*(0.9+wet*0.12);
 METALLIC=0.22;ROUGHNESS=mix(0.65,0.28,wet)+grain*0.08;SPECULAR=0.7;
 EMISSION=mask*(pool*(0.35+wet*0.65)*vec3(0.35,0.012,0.23)+fresnel*vec3(0.09,0.015,0.12)+vec3(0.025,0.035,0.10)+reflected*wet*vec3(0.24,0.018,0.19)+(center+dash)*vec3(0.44,0.49,0.57));
}

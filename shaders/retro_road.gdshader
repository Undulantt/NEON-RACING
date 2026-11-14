shader_type spatial;
render_mode cull_disabled;
uniform vec4 street_pools[4];
// SF.3 defaults are exactly off; all detail stays in world coordinates.
uniform vec3 sf3_anchor = vec3(0.0);
uniform float sf3_radius = 85.0;
uniform vec2 sf3_direction = vec2(0.0,-1.0);
uniform float sf3_asphalt = 0.0;
uniform float sf3_lamps = 0.0;
uniform float sf3_stretch = 2.5;
varying vec3 world_pos;
void vertex(){world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
float noise(vec2 p){
 vec2 i=floor(p);vec2 u=fract(p);u=u*u*(3.0-2.0*u);
 return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
void fragment(){
 vec2 p=world_pos.xz;
 float grain=mix(hash(floor(p*60.0)),0.5,clamp(length(fwidth(p))*40.0,0.0,1.0));
 float fresnel=pow(1.0-abs(dot(normalize(NORMAL),normalize(VIEW))),3.0);
 float wet=smoothstep(0.30,0.78,noise(p*0.12));
 vec3 purple=vec3(0.065,0.045,0.11);
 ALBEDO=purple*(0.75+grain*0.25)*(0.9+wet*0.12);
 METALLIC=0.22;ROUGHNESS=mix(0.65,0.28,wet)+grain*0.08;SPECULAR=0.7;
 float lamp_glow=0.0;
 float sf3_pool=0.0;
 float sf3_near=1.0-smoothstep(sf3_radius*0.55,sf3_radius,distance(p,sf3_anchor.xz));
 sf3_near*=1.0-smoothstep(4.0,10.0,abs(world_pos.y-sf3_anchor.y));
 for(int i=0;i<4;i++){
  vec2 delta=p-street_pools[i].xz;
  float level=1.0-smoothstep(6.0,12.0,abs(world_pos.y-(street_pools[i].y-6.8)));
  lamp_glow+=street_pools[i].w*exp(-dot(delta,delta)/55.0)*level;
  if(sf3_lamps>0.0001){
   float along=dot(delta,sf3_direction);
   float across=dot(delta,vec2(-sf3_direction.y,sf3_direction.x));
   float stretch=1.0+sf3_lamps*sf3_stretch;
   sf3_pool+=street_pools[i].w*exp(-along*along/(55.0*stretch*stretch)-across*across/12.0)*level/sqrt(stretch);
  }
 }
 // Paint is a baked mesh on the actual relief, independent of sector selection.
 EMISSION=lamp_glow*vec3(0.16,0.055,0.14)+vec3(0.025,0.035,0.10)+fresnel*vec3(0.09,0.015,0.12)+wet*noise(p*0.035)*vec3(0.035,0.008,0.045);
 // Metric-scale mottling is fixed to the asphalt. No TIME/UV conveyor motion.
 if(sf3_asphalt>0.0001){
  float resolved=1.0-smoothstep(0.35,0.9,length(fwidth(p))*0.85);
  float macro=noise(p*0.85)*resolved+0.5*(1.0-resolved);
  ALBEDO*=1.0+sf3_near*sf3_asphalt*(macro-0.5)*1.1;
  float aggregate=smoothstep(0.38,0.68,macro);
  EMISSION+=sf3_near*sf3_asphalt*(0.018+aggregate*0.11)*vec3(0.42,0.56,0.85);
  ROUGHNESS=max(0.2,ROUGHNESS-sf3_near*sf3_asphalt*wet*0.06);
 }
 EMISSION+=sf3_near*sf3_lamps*sf3_pool*vec3(0.16,0.045,0.13);
}

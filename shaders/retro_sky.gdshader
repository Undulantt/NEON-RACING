shader_type sky;
void sky(){
 float h=clamp(EYEDIR.y,0.0,1.0);
 vec3 horizon=vec3(0.55,0.16,0.55);
 vec3 zenith=vec3(0.025,0.045,0.20);
 vec3 c=mix(horizon,zenith,pow(h,0.38));
 vec3 sun_dir=normalize(vec3(0.35,-0.01,-0.94));
 float disc=smoothstep(0.9905,0.9915,dot(EYEDIR,sun_dir));
 float stripes=mix(smoothstep(0.12,0.24,fract(EYEDIR.y*45.0)),1.0,smoothstep(0.045,0.06,EYEDIR.y));
 c+=disc*mix(vec3(0.9,0.08,0.4),vec3(1.0,0.35,0.15),h*3.0)*stripes;
 float haze=sin(EYEDIR.x*8.0+EYEDIR.z*5.0+sin(EYEDIR.y*40.0))*0.5+0.5;
 c+=vec3(0.07,0.015,0.08)*haze*exp(-h*7.0);
 COLOR=c;
}

shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float turbo_blur : hint_range(0.0,1.0) = 0.0;
void fragment(){
 vec3 base=textureLod(screen_texture,SCREEN_UV,0.0).rgb;
 vec3 small=textureLod(screen_texture,SCREEN_UV,2.5).rgb;
 vec3 wide=textureLod(screen_texture,SCREEN_UV,4.2).rgb;
 vec3 glow=max(small-vec3(0.35),vec3(0.0))*0.60+max(wide-vec3(0.30),vec3(0.0))*0.35;
 vec2 p=SCREEN_UV*2.0-1.0;
 // Peripheral mip blur: center stays sharp; HUD is on a higher canvas layer.
 float peripheral=smoothstep(0.48,0.96,abs(p.x));
 float amount=peripheral*turbo_blur*0.55;
 vec3 softened=small; // Reuse bloom mip; no extra screen texture sample.
 vec3 result=mix(base,softened,amount)+glow;
 result*=1.0-0.12*dot(p,p);
 COLOR=vec4(result,1.0);
}

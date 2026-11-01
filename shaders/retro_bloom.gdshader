shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
void fragment(){
 vec3 base=textureLod(screen_texture,SCREEN_UV,0.0).rgb;
 vec3 small=textureLod(screen_texture,SCREEN_UV,2.5).rgb;
 vec3 wide=textureLod(screen_texture,SCREEN_UV,4.2).rgb;
 vec3 glow=max(small-vec3(0.35),vec3(0.0))*0.60+max(wide-vec3(0.30),vec3(0.0))*0.35;
 vec2 p=SCREEN_UV*2.0-1.0;
 vec3 result=base+glow;
 result*=1.0-0.12*dot(p,p);
 COLOR=vec4(result,1.0);
}

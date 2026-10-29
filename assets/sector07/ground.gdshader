shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform sampler2D sand_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D dirt_albedo : source_color, filter_linear_mipmap, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D wear_mask : filter_linear_mipmap, repeat_disable;
varying vec3 world_position;
void vertex() { world_position = (MODEL_MATRIX * vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 tile=world_position.xz*0.42;
 vec3 mask=texture(wear_mask,(world_position.xz+32.0)/64.0).rgb;
 vec3 sand=texture(sand_albedo,tile).rgb;
 vec3 dirt=texture(dirt_albedo,tile*0.87).rgb;
 ALBEDO=mix(sand,dirt,mask.r)*mix(0.76,1.08,mask.g);
 NORMAL_MAP=texture(sand_normal,tile).rgb;
 NORMAL_MAP_DEPTH=0.45;
 ROUGHNESS=mix(0.90,0.98,mask.r);
 METALLIC=0.0;
 SPECULAR=0.18;
}

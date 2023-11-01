#version 460
#extension GL_ARB_bindless_texture:require
#extension GL_ARB_gpu_shader_int64:require

layout(bindless_sampler) uniform sampler2D pixels;

in vec2 uv_frag;
out vec4 color;

void main(){
	color = texture(pixels, uv_frag);
	//color = vec4(uv_frag,0,1);
	//color=vec4(1,0,0,1);
}
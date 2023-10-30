#version 460
#extension GL_ARB_bindless_texture:require
#extension GL_ARB_gpu_shader_int64:require

layout(location=0)in vec3 position;
//layout(location=1)in vec3 normal;
layout(location=2)in vec2 uv;

layout(bindless_sampler) uniform sampler2D pixels;

out vec4 gl_Position;
out vec2 uv_frag;

void main(){
	gl_Position=vec4(position,1);
	uv_frag = uv;
}
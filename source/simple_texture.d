module simple_texture;

import bindbc.opengl;
import std.conv : to;
import std.exception : enforce;
import std.stdio;
import vertexd.core.mat;
import vertexd.misc : bitWidth;
import vertexd.shaders;

class BindlessTexture { // TextureHandle
	Texture base;
	Sampler sampler;
	GLuint64 handleID = 0; // no handle
	private bool loaded = false;

	// int texCoord;
	// float factor = 1;

	ubyte[] bufferBytes() {
		// ubyte[] bytes;
		// bytes ~= (cast(ubyte*)&handleID)[0 .. GLuint64.sizeof];
		// bytes ~= (cast(ubyte*)&texCoord)[0 .. int.sizeof];
		// bytes ~= (cast(ubyte*)&factor)[0 .. float.sizeof];
		// return bytes;
		return (cast(ubyte*)&handleID)[0 .. GLuint64.sizeof];
	}

	@disable this();

	this(Texture base, Sampler sampler) {
		this.base = base;
		this.sampler = sampler;
	}

	~this() {
		unload();
		write("TextureHandle removed (remains till base & sampler are removed): ");
		writeln(handleID);
	}

	void allocate() {
		if (this.handleID != 0) {
			writeln("TextureHandle cannot be re-initialized!");
			return;
		}

		this.handleID = glGetTextureSamplerHandleARB(base.id, sampler.id);
		enforce(handleID != 0, "An error occurred while creating a texture handle");

		writeln("TextureHandle created: " ~ handleID.to!string);
	}

	void load() {
		if (!loaded)
			glMakeTextureHandleResidentARB(handleID);
		this.loaded = true;
	}

	void unload() {
		if (loaded)
			glMakeTextureHandleNonResidentARB(handleID);
		this.loaded = false;
	}
}

class Texture {
	import imageformats;

	string name;
	uint id;
	ubyte[4][] pixels;
	uint width;
	uint height;

	bool srgb;
	bool mipmap;
	GLsizei levels;

	private this(string name) {
		this.name = name;
		glCreateTextures(GL_TEXTURE_2D, 1, &id);
		writeln("Texture created: " ~ id.to!string);
	}

	this(uint W, uint H, ubyte[4][] pixels = null, string name = "Texture") {
		this(name);
		this.width = W;
		this.height = H;

		this.pixels = pixels;
		if (pixels is null)
			this.pixels = new ubyte[4][W * H];

		assert(this.pixels.length == W * H);
	}

	this(IFImage img, string name = "Texture") {
		this(img.w, img.h, cast(ubyte[4][]) img.pixels, name);
	}

	this(string file, string name = "") {
		this(read_image(file, ColFmt.RGBA), name);
	}

	static IFImage readImage(string file) {
		return read_image(file, ColFmt.RGBA);
	}

	static IFImage readImage(ubyte[] content) {
		return read_image_from_mem(content, ColFmt.RGBA);
	}

	// enum Access {
	// 	READ = GL_READ_ONLY,
	// 	WRITE = GL_WRITE_ONLY,
	// 	READWRITE = GL_READ_WRITE
	// }

	// void bindImage(GLuint index, Access access, GLint level = 0) {
	// 	assert(!srgb); // Note srgb can't be used for image load/store operations
	// 	glBindImageTexture(index, id, level, false, 0, access, GL_RGBA8);
	// }

	// void bind() {
	// 	glBindTexture(GL_TEXTURE_2D, id);
	// }

	void saveImage(string path, GLint level = 0) { // TODO or = 1?
		glMemoryBarrier(GL_TEXTURE_FETCH_BARRIER_BIT); // TODO: check vs update bit

		glGetTextureImage(id, level, GL_RGBA, GL_UNSIGNED_BYTE,
			cast(int)(width * height * 4 * ubyte.sizeof), pixels.ptr);
		write_png(path, width, height, cast(ubyte[]) pixels, ColFmt.RGBA);
	}

	// Note mipmap map depend on sampler.usesMipMap()
	void allocate(bool srgb, bool mipmap) { // Can't realocate while using texture handle.
		this.srgb = srgb;
		this.levels = 1;
		if (mipmap) { //TODO: decide on default mipmap level or make it configurable. (minimum grootte van laagste level?)
			int maxImageSize = (width > height) ? width : height;
			this.levels = cast(GLsizei) bitWidth(maxImageSize);
		}
		glTextureStorage2D(id, levels, (srgb ? GL_SRGB8_ALPHA8 : GL_RGBA8), width, height);
	}

	void upload() { // (re)upload pixel data
		glTextureSubImage2D(id, 0, 0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels.ptr);
		if (mipmap)
			glGenerateTextureMipmap(id);
	}

	~this() {
		glDeleteTextures(1, &id);
		write("Texture removed: ");
		writeln(id);
	}
}

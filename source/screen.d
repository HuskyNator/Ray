module screen;
import vertexd.mesh;
import vertexd.core;
import vertexd.world;
import vertexd.shaders.shaderprogram;
import simple_texture;
import vertexd.shaders.sampler;
import bindbc.opengl : GLint;

class Quad : Mesh {
	this(float width, float height, ShaderProgram program) {
		super(program, "Quad");

		float w = width / 2;
		float h = height / 2;
		float[3][] positions = [
			[-w, -h, 0], [w, -h, 0], [-w, h, 0], [w, -h, 0], [w, h, 0], [-w, h, 0]
		];
		setAttribute(Mesh.Attribute(positions), 0);

		float[3][] normals = new float[3][](6);
		normals[] = [0, 0, 1];
		setAttribute(Mesh.Attribute(normals), 1);

		float[2][] uvs = [[0, 0], [1, 0], [0, 1], [1, 0], [1, 1], [0, 1]];
		setAttribute(Mesh.Attribute(uvs), 2);

		setIndexCount(6);
	}

	override void drawSetup(Node node) {
		shaderProgram.use();
		Screen screen = cast(Screen) node;
		screen.setup();
	}
}

final class Screen : Node {
	uint width;
	uint height;

	BindlessTexture handle;
	Texture texture;
	Sampler sampler;
	GLint pixelUniformLocation;

	private string[2] shaderFiles = ["vertex.vert", "fragment.frag"];
	private ShaderProgram shader;

	@disable this();

	this(uint width, uint height) {
		super();
		// this.width = width;
		// this.height = height;
		this.shader = new ShaderProgram(shaderFiles);
		this.meshes ~= new Quad(2, 2, shader);
		this.pixelUniformLocation = shader.getUniformLocation("pixels");
		setSize(width, height);
	}

	void setSize(uint width, uint height) { // Resets texture/sampler/handle.
		this.width = width;
		this.height = height;
		this.texture = new Texture(width, height);
		this.sampler = new Sampler(""); // Standard Sampler (neareast).
		this.handle = new BindlessTexture(texture, sampler);

		texture.allocate(false, false);
		handle.allocate();
		handle.load();
	}

	void setPixel(uint x, uint y, Vec!4 color) {
		import std.algorithm : clamp;

		ubyte[4] pixel;
		foreach (i; 0 .. 4)
			pixel[i] = cast(ubyte)(color[i].clamp(0.0f, 1.0f) * 255);
		texture.pixels[width * y + x] = pixel;
	}

	// TODO: verander drawSetup(Node) in compositie!!
	void setup() {
		texture.upload();
		shader.setUniformHandle(pixelUniformLocation, handle.handleID);
	}
}

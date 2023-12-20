import player;
import raycam;
import raytracer;
import screen;
import std.stdio;
import vertexd.core;
import vertexd.input.gltf_reader;
import vertexd.mesh;
import vertexd.misc : degreesToRadians;
import vertexd.world : World;

void main(string[] args) {
	uint width = 1920 / 2;
	uint height = 1080 / 2;

	const bool RENDER_IMAGE = (args.length > 1 && args[1] == "image");

	vdInit();
	if (RENDER_IMAGE)
		Window.setStandardVisible(false);
	Window window = new Window("Ray", width, height);
	window.setBackgroundColor(Vec!4(0, 0, 0.5, 1));
	GltfReader gltfReader = new GltfReader("cube.gltf");
	GltfMesh mesh = gltfReader.meshes[0][0];

	Screen screen = new Screen(width, height);
	RayTracer rayTracer = RayTracer(1);
	RayCamera camera = new RayCamera(&rayTracer,degreesToRadians(90.0f)); // Actual raytracing outside of framework.

	World world = new World();
	world.addNode(screen);
	world.cameras ~= camera;
	window.world = world;

	Speler speler = new Speler();
	world.addNode(speler);
	window.setMouseType(MouseType.CAPTURED);
	window.keyCallbacks ~= &speler.toetsinvoer;
	window.mousepositionCallbacks ~= &speler.muisinvoer;
	speler.location = Vec!3(0, 0, 4);
	speler.addAttribute(camera);

	rayTracer.scene.lights = [Light(Vec!3(2, 2, -2), Vec!3(1, 1, 1))];
	rayTracer.scene.indices = mesh.index.attr.getContent!3().dup;
	rayTracer.scene.positions = (cast(
			Vec!3*) mesh.attributeSet.position.content.ptr)[0 .. mesh
		.attributeSet.position.elementCount].dup;
	rayTracer.scene.computeTriangleNormals();
	rayTracer.scene.normals = (
		cast(
			Vec!3*) mesh.attributeSet.normal.content.ptr)[0 .. mesh
		.attributeSet.normal.elementCount].dup;
	rayTracer.scene.colors = (
		cast(Vec!4*) mesh.attributeSet.color[0].content.ptr)[0
		.. mesh.attributeSet.color[0].elementCount].dup;
	rayTracer.scene.backgroundColor = Vec!4(0, 0.8, 0, 1);

	vdStep(); // Needs to be done before render.
	if (RENDER_IMAGE) {
		rayTracer.trace(screen);
		screen.texture.saveImage("TEMP3.jpg");
	} else
		while (!vdShouldClose()) {
			rayTracer.trace(screen);
			vdStep();
		}
}

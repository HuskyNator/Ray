import std.stdio;
import vertexd.core;
import vertexd.world;
import vertexd.input.gltf_reader;
import screen;
import raycam;
import player;
import raytracer;

void main() {
	uint width = 1920/2;
	uint height = 1080/2;

	vdInit();
	Window window = new Window("Ray", width, height);
	window.setBackgroundColor(Vec!4(0, 0, 0.5, 1));
	// GltfReader reader = new GltfReader("world");


	Screen screen = new Screen(width, height);
	Camera camera = new RayCamera(); // Actual raytracing outside of framework.

	World world = new World();
	world.addNode(screen);
	world.cameras ~= camera;
	window.world = world;

	Speler speler = new Speler();
	world.addNode(speler);
	window.setMouseType(MouseType.CAPTURED);
	window.keyCallbacks ~= &speler.toetsinvoer;
	window.mousepositionCallbacks ~= &speler.muisinvoer;
	speler.location = Vec!3(0, 0, 2);
	speler.addAttribute(camera);

	while (!vdShouldClose()) {
		RayTracer.rayTrace(screen);
		vdStep();
	}
}

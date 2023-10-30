import std.stdio;
import vertexd.core;
import vertexd.world;
import vertexd.input.gltf_reader;
import screen;

void main() {
	vdInit();
	Window window = new Window("Ray");
	window.setBackgroundColor(Vec!4(0, 0, 0.5, 1));
	// GltfReader reader = new GltfReader("world");

	Screen screen = new Screen(1920 / 2, 1080 / 2);
	Camera noCam = new NoCamera();

	World world = new World();
	world.addNode(screen);
	world.cameras ~= noCam;
	window.world = world;

	while (!vdShouldClose()) {
		rayTrace(screen);
		vdStep();
	}
}

void rayTrace(Screen screen){
	
}

import gamut;
import player;
import raycam;
import raytracer;
import screen;
import std.conv;
import std.datetime.stopwatch;
import std.file;
import std.math.constants : PI;
import std.path;
import std.process;
import std.stdio;
import std.string;
import vertexd.core;
import vertexd.input.gltf_reader;
import vertexd.mesh;
import vertexd.misc : degreesToRadians;
import vertexd.world : Node, World;

void main(string[] args) {
	uint width = 1920 / 3;
	uint height = 1080 / 3;

	const bool RENDER_IMAGE = (args.length > 1 && args[1] == "image");
	const bool PROFILE = (args.length > 1 && args[1] == "profile");
	const uint PROFILE_COUNT = (PROFILE && args.length > 2) ? args[2].to!uint : 8;
	const bool GIF = (args.length > 1 && args[1] == "gif");
	const int GIF_COUNT = (args.length > 2) ? args[2].to!uint : 16;

	const bool INTERACTIVE = !(RENDER_IMAGE || PROFILE || GIF);

	vdInit();
	if (RENDER_IMAGE || PROFILE)
		Window.setStandardVisible(false);
	Window window = new Window("Ray", width, height);
	window.setBackgroundColor(Vec!4(0, 0, 0.5, 1));
	GltfReader gltfReader = new GltfReader("helmet/DamagedHelmet.gltf");
	// GltfReader gltfReader = new GltfReader("cube.gltf");
	GltfMesh mesh = gltfReader.meshes[0][0];

	World world = new World();
	window.world = world;

	Screen screen = new Screen(width, height);
	world.addNode(screen);

	RayCamera camera = new RayCamera(degreesToRadians(90.0f)); // Actual raytracing outside of framework.
	world.cameras ~= camera;

	//TODO: more AABB's on laptop???
	uint minInBox = 5;
	uint binCount = 2;
	bool useBVH = true;

	Scene scene = Scene(camera, [Light(Vec!3(2, 2, -2), Vec!3(1, 1, 1))], mesh, Vec!4(0, 0.8, 0,
			1), minInBox, binCount);

	RayTracer rayTracer = RayTracer(screen);

	Node root;
	if (INTERACTIVE) {
		Player player = new Player();
		root = player;
		window.setMouseType(MouseType.CAPTURED);
		window.keyCallbacks ~= &player.keyInput;
		window.mousepositionCallbacks ~= &player.mouseInput;
	} else {
		root = new Node();
	}
	world.addNode(root);
	root.location = Vec!3(0, 0, 2.5);
	root.addAttribute(camera);

	vdStep(); // Needs to be done before render.

	if (RENDER_IMAGE || PROFILE) {
		string logPath = ".." ~ dirSeparator ~ "logs" ~ dirSeparator;
		mkdirRecurse(logPath);
		auto shell = executeShell("git rev-parse --short HEAD");
		string commitName = (shell.status == 0) ? lineSplitter(shell.output).front : "Unknown";

		string performancePath = logPath ~ "performance.txt";
		if (!exists(performancePath))
			std.file.write(performancePath, "Previous commit : seconds/frame\n");

		if (RENDER_IMAGE) {
			StopWatch watch = StopWatch(AutoStart.yes);
			rayTracer.trace(scene, 1, useBVH);
			watch.stop();

			screen.texture.saveImage(logPath ~ commitName ~ ".png");
			copy(logPath ~ commitName ~ ".png", logPath ~ "image.png");

			float frameTime = (cast(float) watch.peek().total!"usecs") / 1_000_000.0f;
			append(performancePath, commitName ~ ':' ~ frameTime.to!string ~ '\n');
		}
		if (PROFILE) {
			Duration performanceDur = benchmark!(() { rayTracer.trace(scene, 1, useBVH); })(PROFILE_COUNT)[0];
			float performance = (cast(float) performanceDur.total!"usecs") / 1_000_000.0f / PROFILE_COUNT;
			append(performancePath, commitName ~ ':' ~ performance.to!string ~ '\n');
			writeln("Performance: ", performance, " sec");
		}
	} else if (GIF) {
		Vec!(4, ubyte)[] images;

		float angle = -2 * PI / (GIF_COUNT);
		Quat rotation = Quat.rotation(Vec!3(0, 1, 0), angle);
		Mat!3 rotationM = rotation.toMat;
		foreach (i; 0 .. GIF_COUNT) {
			rayTracer.trace(scene, 1, useBVH);
			images ~= screen.texture.pixels.dup;
			root.location = rotationM ^ root.location;
			root.rotation = rotation * root.rotation;
			vdStep();
		}
		Image image;
		image.createLayeredViewFromData(cast(void*) images.ptr, cast(int) width, cast(int) height,
			GIF_COUNT, PixelType.rgba8, cast(int)(width * 4 * ubyte.sizeof),
			cast(int)(width * height * Vec!(4, ubyte).sizeof));
		image.flipVertical();
		image.saveToFile("../logs/helmet.gif");
	} else {
		while (!vdShouldClose()) {
			rayTracer.trace(scene, 1, useBVH);
			vdStep();
			// writeln("FPS: " ~ vdFps().to!string);
		}
	}
}

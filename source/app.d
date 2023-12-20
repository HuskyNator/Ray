import player;
import raycam;
import raytracer;
import screen;
import std.conv;
import std.datetime.stopwatch;
import std.file;
import std.process;
import std.stdio;
import std.string;
import vertexd.core;
import std.path;
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
	GltfReader gltfReader = new GltfReader("teapot.gltf");
	GltfMesh mesh = gltfReader.meshes[0][0];

	World world = new World();
	window.world = world;

	Screen screen = new Screen(width, height);
	world.addNode(screen);

	RayCamera camera = new RayCamera(degreesToRadians(90.0f)); // Actual raytracing outside of framework.
	world.cameras ~= camera;

	Scene scene = {
		camera: camera, lights: [Light(Vec!3(2, 2, -2), Vec!3(1, 1, 1))], indices: mesh.index.attr.getContent!3()
			.dup, positions: (cast(Vec!3*) mesh.attributeSet.position.content.ptr)[0
				.. mesh.attributeSet.position.elementCount].dup, normals: (
				cast(Vec!3*) mesh.attributeSet.normal.content.ptr)[0 .. mesh.attributeSet.normal.elementCount].dup,
		colors: (cast(Vec!4*) mesh.attributeSet.color[0].content.ptr)[0 .. mesh.attributeSet.color[0].elementCount]
			.dup, backgroundColor: Vec!4(0, 0.8, 0, 1),
	};

	RayTracer rayTracer = RayTracer(scene, screen, true, 1);

	Speler speler = new Speler();
	world.addNode(speler);
	window.setMouseType(MouseType.CAPTURED);
	window.keyCallbacks ~= &speler.toetsinvoer;
	window.mousepositionCallbacks ~= &speler.muisinvoer;
	speler.location = Vec!3(0, 0, 4);
	speler.addAttribute(camera);

	vdStep(); // Needs to be done before render.
	if (RENDER_IMAGE) {
		string logPath = ".." ~ dirSeparator ~ "logs" ~ dirSeparator;
		mkdirRecurse(logPath);
		auto shell = executeShell("git rev-parse --short HEAD");
		string commitName = (shell.status == 0) ? lineSplitter(shell.output).front : "Unknown";

		rayTracer.trace();
		screen.texture.saveImage(logPath ~ commitName ~ ".jpg");

		string performancePath = logPath ~ "performance.txt";
		if (!exists(performancePath))
			File(performancePath, "w").writeln("Previous commit : seconds/frame");
		float frameTime = cast(float) benchmark!(() { rayTracer.trace(); })(10)[0].total!"usecs";
		frameTime = frameTime / (10.0f * 1.seconds.total!"usecs");
		File(performancePath, "a").writeln(commitName ~ ":" ~ frameTime.to!string);
	} else
		while (!vdShouldClose()) {
			rayTracer.trace();
			vdStep();
			// writeln("FPS: " ~ vdFps().to!string);
		}
	// import std.random : uniform;
	// import vertexd.misc;

	// enum RUNS = 300;
	// Vec!3[3][RUNS] verts;
	// Vec!3[RUNS] normal;
	// Vec!3[RUNS] bary;
	// Vec!3[RUNS] point;
	// foreach (k; 0 .. RUNS) {
	// 	foreach (i; 0 .. 3)
	// 		foreach (j; 0 .. 3)
	// 			verts[k][i][j] = uniform(-5.0, 5.0);
	// 	normal[k] = (verts[k][1] - verts[k][0]).cross(verts[k][2] - verts[k][0]).normalize();

	// 	bary[k][0] = uniform!"[]"(0.0, 1.0);
	// 	bary[k][1] = uniform!"[]"(0.0, 1.0);
	// 	bary[k][2] = 1.0 - bary[k][0] - bary[k][1];
	// 	assertAlmostEqual(bary[k].sum(), 1.0);

	// 	point[k] = Vec!3(0);
	// 	static foreach (i; 0 .. 3)
	// 		point[k] += verts[k][i] * bary[k][i];
	// }

	// Vec!3[RUNS] calculatedBary;
	// Vec!3[RUNS] calculatedProjectedBary;

	// import std.datetime.stopwatch;

	// StopWatch firstWatch = StopWatch(AutoStart.no);
	// StopWatch secondWatch = StopWatch(AutoStart.no);

	// firstWatch.start();
	// foreach (k; 0 .. RUNS)
	// 	calculatedBary[k] = RayTracer.calcBarycentric(verts[k], normal[k], point[k]);
	// firstWatch.stop();

	// secondWatch.start();
	// foreach (k; 0 .. RUNS)
	// 	calculatedProjectedBary[k] = RayTracer.calcProjectedBarycentric(verts[k], point[k]);
	// secondWatch.stop();

	// foreach (k; 0 .. RUNS) {
	// 	calculatedBary[k].assertAlmostEq(bary[k]);
	// 	calculatedProjectedBary[k].assertAlmostEq(bary[k]);
	// }

	// import std.stdio;
	// import std.conv;

	// writeln("First: " ~ std.conv.to!string(firstWatch.peek().total!"hnsecs"()));
	// writeln("Second: " ~ std.conv.to!string(secondWatch.peek().total!"hnsecs"()));
}

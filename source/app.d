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
import vertexd.world : World;

void main(string[] args) {
const int w = 16;
const int h = 16;
enum scale = 16;       // Fails > 4
const int frames = 255;
ubyte[4][] img = new ubyte[4][w * h];
foreach (ubyte x; 0 .. w)
	foreach (ubyte y; 0 .. h)
		img[cast(int)(y * w) + x] = [cast(ubyte)(scale * x), cast(ubyte)(scale * y), 0, 255];

ubyte[4][] gif;
foreach (i; 0 .. frames)
	{
		foreach(int j; 0..w*h){
			img[j][2] += 1;
		}
		gif ~= img.dup;}
Image image;
image.createLayeredViewFromData(cast(void*) gif.ptr, w, h, frames, PixelType.rgba8,
	cast(int)(w * 4 * ubyte.sizeof), cast(int)(w * h * 4 * ubyte.sizeof));
image.saveToFile("../logs/test.gif");
}
// 	uint width = 1920 / 3;
// 	uint height = 1080 / 3;

// 	const bool RENDER_IMAGE = (args.length > 1 && args[1] == "image");
// 	const bool PROFILE = (args.length > 1 && args[1] == "profile");
// 	const uint PROFILE_COUNT = (PROFILE && args.length > 2) ? args[2].to!uint : 8;
// 	const bool GIF = (args.length > 1 && args[1] == "gif");
// 	const uint GIF_COUNT = (args.length > 2) ? args[2].to!uint : 16;

// 	vdInit();
// 	if (RENDER_IMAGE || PROFILE)
// 		Window.setStandardVisible(false);
// 	Window window = new Window("Ray", width, height);
// 	window.setBackgroundColor(Vec!4(0, 0, 0.5, 1));
// 	GltfReader gltfReader = new GltfReader("helmet/DamagedHelmet.gltf");
// 	// GltfReader gltfReader = new GltfReader("cube.gltf");
// 	GltfMesh mesh = gltfReader.meshes[0][0];

// 	World world = new World();
// 	window.world = world;

// 	Screen screen = new Screen(width, height);
// 	world.addNode(screen);

// 	RayCamera camera = new RayCamera(degreesToRadians(90.0f)); // Actual raytracing outside of framework.
// 	world.cameras ~= camera;

// 	//TODO: more AABB's on laptop???
// 	uint minInBox = 5;
// 	uint binCount = 2;
// 	bool useBVH = true;

// 	Scene scene = Scene(camera, [Light(Vec!3(2, 2, -2), Vec!3(1, 1, 1))], mesh, Vec!4(0, 0.8, 0,
// 			1), minInBox, binCount);

// 	RayTracer rayTracer = RayTracer(screen);

// 	Speler speler = new Speler();
// 	world.addNode(speler);
// 	window.setMouseType(MouseType.CAPTURED);
// 	window.keyCallbacks ~= &speler.toetsinvoer;
// 	window.mousepositionCallbacks ~= &speler.muisinvoer;
// 	speler.location = Vec!3(0, 0, 2.5);
// 	speler.addAttribute(camera);

// 	vdStep(); // Needs to be done before render.

// 	if (RENDER_IMAGE || PROFILE) {
// 		string logPath = ".." ~ dirSeparator ~ "logs" ~ dirSeparator;
// 		mkdirRecurse(logPath);
// 		auto shell = executeShell("git rev-parse --short HEAD");
// 		string commitName = (shell.status == 0) ? lineSplitter(shell.output).front : "Unknown";

// 		string performancePath = logPath ~ "performance.txt";
// 		if (!exists(performancePath))
// 			std.file.write(performancePath, "Previous commit : seconds/frame\n");

// 		if (RENDER_IMAGE) {
// 			StopWatch watch = StopWatch(AutoStart.yes);
// 			rayTracer.trace(scene, 1, useBVH);
// 			watch.stop();

// 			screen.texture.saveImage(logPath ~ commitName ~ ".png");
// 			copy(logPath ~ commitName ~ ".png", logPath ~ "image.png");

// 			float frameTime = (cast(float) watch.peek().total!"usecs") / 1_000_000.0f;
// 			append(performancePath, commitName ~ ':' ~ frameTime.to!string ~ '\n');
// 		}
// 		if (PROFILE) {
// 			Duration performanceDur = benchmark!(() { rayTracer.trace(scene, 1, useBVH); })(PROFILE_COUNT)[0];
// 			float performance = (cast(float) performanceDur.total!"usecs") / 1_000_000.0f / PROFILE_COUNT;
// 			append(performancePath, commitName ~ ':' ~ performance.to!string ~ '\n');
// 			writeln("Performance: ", performance, " sec");
// 		}
// 	} else if (GIF) {
// 		Vec!(4, ubyte)[][] images;

// 		float angle = 2 * PI / (GIF_COUNT);
// 		Quat rotation = Quat.rotation(Vec!3(0, 1, 0), angle);
// 		Mat!3 rotationM = rotation.toMat;
// 		foreach (i; 0 .. GIF_COUNT) {
// 			rayTracer.trace(scene, 1, useBVH);
// 			images ~= screen.texture.pixels.dup;
// 			speler.location = rotationM ^ speler.location;
// 		}
// 		Image image;
// 		image.createLayeredViewFromData(cast(void*) images.ptr, cast(int) width, cast(int) height,
// 			cast(int) 4, PixelType.rgba8, cast(int)(width * 4 * ubyte.sizeof),
// 			cast(int)(width * height * Vec!(4, ubyte).sizeof));
// 		image.saveToFile("helmet.gif");
// 	} else {
// 		while (!vdShouldClose()) {
// 			rayTracer.trace(scene, 1, useBVH);
// 			vdStep();
// 			// writeln("FPS: " ~ vdFps().to!string);
// 		}
// 	}
// }

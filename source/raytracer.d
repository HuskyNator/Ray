module raytracer;
import vertexd.core;
import raycam;
import screen;

float u_occlusion = .1;
float u_diffuse = .7;
float u_specular = .2;
float u_specular_power = 50;

struct Scene {
	RayCamS cam;
	Light[] lights;

	Vec!3[] positions;
	Vec!3[] normals;
	Vec!4[] colors;
}

struct Light {
	Vec!3 pos;
	Vec!3 color;
}

struct RayTracer {
	@disable this();

static:
	Scene scene;
	void rayTrace(Screen screen) {
		float wFrac = 1.0f / screen.width;
		float hFrag = 1.0f / screen.height;
		foreach (x; 0 .. screen.width) {
			foreach (y; 0 .. screen.height) {
				Vec!2 delta = Vec!2(x * wFrac, y * hFrag) * 2 - Vec!2(1, 1);

				Vec!3 dir_cam = Vec!3(delta.x, delta.y, -scene.cam.focalLength).normalize();
				Vec!4 dir_world4 = scene.cam.camMatrix ^ Vec!4(dir_cam.x, dir_cam.y, dir_cam.z, 0);
				Vec!3 dir_world = Vec!3(dir_world4.x, dir_world4.y, dir_world4.z).normalize();

				Vec!4 color = trace(scene, dir_world);
				// Vec!4 color = Vec!4(dir_world.x, dir_world.y, 0, 1);
				color = Vec!4(delta.x, delta.y, 0, 1);
				screen.setPixel(x, y, color);
			}
		}
	}

	Vec!4 trace(Scene scene, Vec!3 dir) {
		return Vec!4(dir.x, dir.y, dir.z, 1); //TODO
	}

}

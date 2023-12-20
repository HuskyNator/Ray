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

	uint[3][] indices;
	Vec!3[] positions;
	Vec!3[] normals; // per vertex -> otherwise normalmap or parallex mapping et cetera
	Vec!3[] triangleNormals;
	Vec!4[] colors; // UV's to be + textures.
	Vec!4 backgroundColor; // environment map?

	void computeTriangleNormals() {
		this.triangleNormals = [];
		this.triangleNormals.reserve(indices.length);
		foreach (uint[3] triangle; indices) {
			Vec!3[3] pos = [positions[triangle[0]], positions[triangle[1]], positions[triangle[2]]];
			this.triangleNormals ~= (pos[1] - pos[0]).cross(pos[2] - pos[0]).normalize();
		}
	}
}

struct Light {
	Vec!3 pos;
	Vec!3 color;
}

struct Ray {
	Vec!3 org;
	Vec!3 dir;
}

struct RayTracer {
	uint maxDepth; // TODO
	Scene scene;

	@disable this();

	this(uint maxDepth) {
		this.maxDepth = maxDepth;
	}

	void trace(Screen screen) {
		float wFrac = 1.0f / screen.width;
		float hFrag = 1.0f / screen.height;

		foreach (x; 0 .. screen.width) {
			foreach (y; 0 .. screen.height) {
				Vec!2 delta = Vec!2(x * wFrac, y * hFrag) * 2 - Vec!2(1, 1);

				Vec!3 dir_cam = Vec!3(delta.x, delta.y, -scene.cam.focalLength).normalize();
				Vec!4 dir_world4 = scene.cam.camMatrix ^ Vec!4(dir_cam.x, dir_cam.y, dir_cam.z, 0);
				Vec!3 dir_world = Vec!3(dir_world4.x, dir_world4.y, dir_world4.z).normalize();

				Ray ray = Ray(scene.cam.pos, dir_world);
				Vec!4 color = trace(ray, 0);
				// Vec!4 color = Vec!4(dir_world.x,dir_world.y,0, 1);
				screen.setPixel(x, y, color);
			}
		}
	}

	Vec!4 trace(Ray ray, uint depth) {
		float closest = float.max;
		ulong hitID = 0;
		foreach (i; 0 .. scene.indices.length) {
			float dist = intersectTriangle(ray, i);
			if (dist < closest) {
				closest = dist;
				hitID = i;
			}
		}
		if (closest == float.max) // no hit
			return scene.backgroundColor;
		return scene.colors[scene.indices[hitID][0]]; // TODO
	}

	// Only positive distance hits.
	float intersectTriangle(ref Ray ray, ulong index) {
		float dist = intersectPlane(ray, index);
		if (dist < 0)
			return -1;
		Vec!3 point = ray.org + ray.dir * dist;
		uint[3] triangle = scene.indices[index];
		Vec!3[3] positions = [
			scene.positions[triangle[0]], scene.positions[triangle[1]], scene.positions[triangle[2]]
		];
		Vec!3 barycentric = calcBarycentric(positions, scene.triangleNormals[index], point);
		foreach (λ; barycentric)
			if (λ < 0)
				return -1;
		return dist;
	}

	// Only positive distance hits.
	float intersectPlane(ref Ray ray, ulong index) {
		Vec!3 normal = scene.triangleNormals[index];
		float rProject = ray.dir.dot(normal);
		if (rProject == 0)
			return -1; // parallel
		Vec!3 planePoint = scene.positions[scene.indices[index][0]];
		Vec!3 toPlane = planePoint - ray.org;
		float planeDistance = toPlane.dot(normal);
		float distance = planeDistance / rProject;
		return distance;
	}

	Vec!3 calcBarycentric(Vec!3[3] verteces, Vec!3 normal, Vec!3 point) {
		Vec!3 v0 = verteces[0];
		Vec!3 v1 = verteces[1];
		Vec!3 v2 = verteces[2];
		float area0 = (v1 - point).cross(v2 - point).dot(normal);
		float area1 = (v2 - point).cross(v0 - point).dot(normal);
		float area2 = (v0 - point).cross(v1 - point).dot(normal);
		float fullArea = (v1 - v0).cross(v2 - v0).dot(normal); // better precision
		// float fullArea = area0 + area1 + area2;

		debug import std.format;

		debug import std.math : abs;

		debug float fullArea2 = area0 + area1 + area2;
		assert((fullArea - fullArea2).abs < 0.1, "Expected area " ~ format("%.8f",
				fullArea) ~ " but got " ~ format("%.8f", fullArea2));
		return Vec!3(area0, area1, area2) / fullArea;
	}

}

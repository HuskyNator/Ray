module raytracer;
import bvh;
import raycam;
import screen;
import vertexd.core;

float u_occlusion = .1;
float u_diffuse = .7;
float u_specular = .2;
float u_specular_power = 50;

struct Scene {
	RayCamS cam;
	Light[] lights;

	BVH bvh;

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
			Vec!3[3] pos = [
				positions[triangle[0]], positions[triangle[1]],
				positions[triangle[2]]
			];
			this.triangleNormals ~= (pos[1] - pos[0]).cross(pos[2] - pos[0]).normalize();
		}
	}

	void computeBVH() {
		bvh = BVH(indices, positions);
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
		import std.math;
		import std.parallelism;

		float virtualPlaneZ = -1.0f / tan(scene.cam.fov / 2.0f);
		float verticalFrac = cast(float) screen.height / cast(float) screen.width;

		float widthFrac = 1.0f / cast(float) screen.width;
		float heightFrag = 1.0f / cast(float) screen.height;

		uint[] xs = new uint[screen.width];
		foreach (uint i; 0 .. screen.width)
			xs[i] = i;

		foreach (ref x; parallel(xs)) {
			foreach (y; 0 .. screen.height) {
				Vec!2 delta = Vec!2(x * widthFrac, y * heightFrag * verticalFrac) * 2 - Vec!2(1, verticalFrac);

				Vec!3 dir_cam = Vec!3(delta.x, delta.y, virtualPlaneZ).normalize();
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
			if (dist < closest && dist > 0) {
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
			scene.positions[triangle[0]], scene.positions[triangle[1]],
			scene.positions[triangle[2]]
		];
		// Vec!3 barycentric = calcBarycentric(positions, scene.triangleNormals[index], point);
		Vec!3 barycentric = calcProjectedBarycentric(positions, point);
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

	Vec!3 calcBarycentric(Vec!3[3] vertexes, Vec!3 normal, Vec!3 point) {
		Vec!3 pToV0 = vertexes[0] - point;
		Vec!3 pToV1 = vertexes[1] - point;
		Vec!3 pToV2 = vertexes[2] - point;
		float area0 = (pToV1).cross(pToV2).dot(normal);
		float area1 = (pToV2).cross(pToV0).dot(normal);
		float area2 = (pToV0).cross(pToV1).dot(normal);
		float fullArea = area0 + area1 + area2;

		// TODO
		// float fullArea = (v1 - v0).cross(v2 - v0).dot(normal); // very much not equal??
		// assert((fullArea - fullArea2).abs < 0.1, "Expected area " ~ format("%.8f",
		// 		fullArea) ~ " but got " ~ format("%.8f", fullArea2));
		return Vec!3(area0, area1, area2) / fullArea;
	}

	/// Alternative way projection onto 2d xyz planes.
	Vec!3 calcProjectedBarycentric(Vec!3[3] verts, Vec!3 point) {
		Vec!3 normal = (verts[1] - verts[0]).cross(verts[2] - verts[0]);
		import std.math : abs;

		// TODO Proof? source:https://ceng2.ktu.edu.tr/~cakir/files/grafikler/Texture_Mapping.pdf
		float xArea = abs(normal.x); // = * 2
		float yArea = abs(normal.y); // = * 2
		float zArea = abs(normal.z); // = * 2

		if (xArea >= yArea && xArea >= zArea) {
			float xAreaFrac = 1.0f / xArea;
			return calcProjectedBarycentric!("y", "z")(xArea, verts, point);
		} else if (yArea >= zArea) {
			return calcProjectedBarycentric!("x", "z")(yArea, verts, point);
		} else {
			return calcProjectedBarycentric!("x", "y")(zArea, verts, point);
		}
	}

	private Vec!3 calcProjectedBarycentric(string firstAxis, string secondAxis)(
		float fullArea, Vec!3[3] verts, Vec!3 point) {
		pragma(inline);
		float fullAreaFrac = 1.0f / fullArea;
		Vec!3 bary;
		bary[0] = triangleAreaDouble([
			Vec!2(mixin("point." ~ firstAxis), mixin("point." ~ secondAxis)),
			Vec!2(mixin("verts[1]." ~ firstAxis), mixin("verts[1]." ~ secondAxis)),
			Vec!2(mixin("verts[2]." ~ firstAxis), mixin("verts[2]." ~ secondAxis))
		]) * fullAreaFrac;
		bary[1] = triangleAreaDouble([
			Vec!2(mixin("point." ~ firstAxis), mixin("point." ~ secondAxis)),
			Vec!2(mixin("verts[2]." ~ firstAxis), mixin("verts[2]." ~ secondAxis)),
			Vec!2(mixin("verts[1]." ~ firstAxis), mixin("verts[1]." ~ secondAxis))
		]) * fullAreaFrac;
		bary[2] = 1.0f - bary[0] - bary[1];
		return bary;
	}

	private float triangleAreaDouble(Vec!2[3] verts) {
		pragma(inline);
		return (verts[0].x - verts[1].x) * (verts[1].y - verts[2].y) + (
			verts[1].x - verts[2].x) * (verts[1].y - verts[0].y);
	}

}

// (x2-x1)*(y3-y1) - (x3-x1)*(y3-y1)/2 - (x2-x1)*(y2-y1)/2 - (x2-x3)*(y3-y2)/2
// 		=
// 		x1(y1-y3+y3/2-y1/2+y2/2-y1/2)
// 		+x2(y3-y1-y2/2+y1/2-y3/2+y2/2)
// 		+x3(-y3/2+y1/2+y3/2-y2/2)
// 		=
// 		x1(y2/2-y3/2)
// 		+x2(-y1/2+y3/2)
// 		+x3(y1/2-y2/2)
// 		=
// 		((x1-x2)*(y2-y3)
// 		+(x2-x3)*(y2-y1))/2

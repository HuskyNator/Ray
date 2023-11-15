module raytracer;
import bvh;
import core.atomic;
import core.sync.semaphore;
import core.thread;
import raycam;
import screen;
import gate;
import std.algorithm : max, min;
import std.parallelism : totalCPUs;
import vertexd.core;
import vertexd.misc;

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

	void prepare(bool useBVH) {
		if (useBVH && !bvh.initialized)
			calculateBVH();
		else if (triangleNormals.length == 0)
			calculateNormals();
	}

	/// Creates BVH & Recalculates normals
	void calculateBVH() {
		this.bvh = BVH(indices, positions);
		calculateNormals();
	}

	void calculateNormals() {
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
	bool useBVH;
	Scene scene;
	Screen screen;

	private {
		Thread[] threads;
		uint[2][] threadParams;
		Gate threadGate;
		shared uint atomicInt = 0;

		float virtualPlaneZ;
		float verticalFrac;
		float widthFrac;
		float heightFrag;

		uint actualThreadNum;
		bool DIE = false;
	}

	~this() {
		while (threadGate.waiters < actualThreadNum)
			Thread.yield();
		atomicStore(DIE, true);
		threadGate.open();
		foreach (Thread t; threads)
			t.join();
	}

	/// Params:
	///   maxDepth = The max reflection depth
	this(uint maxDepth, bool useBVH, Screen screen) {
		this.maxDepth = maxDepth;
		this.useBVH = useBVH;
		this.screen = screen;

		immutable uint threadNum = max(1, totalCPUs - 1);
		immutable uint perThread = screen.height / threadNum;
		immutable uint loss = screen.height % threadNum;
		this.actualThreadNum = threadNum + ((loss > 0) ? 1 : 0); // TODO BUGREPORT ZONDER HAAKJES

		this.threads = new Thread[actualThreadNum];
		this.threadGate = new Gate();

		foreach (uint t; 0 .. threadNum) {
			threadParams ~= [t * perThread, (t + 1) * perThread];
			new Thread(&threadTrace).start();
		}

		if (loss > 0) {
			threadParams ~= [screen.height - loss, screen.height];
			new Thread(&threadTrace).start();
		}

		// Wait for threads to initialize & reach the gate.
		while (threadGate.waiters < actualThreadNum)
			Thread.yield();
	}

	void threadTrace() {
		uint id = atomicFetchAdd(atomicInt, 1);
		threads[id] = Thread.getThis();
		uint start = threadParams[id][0];
		uint end = threadParams[id][1];

		// TODO Figure out how to end thread without creating `shouldStop` boolean (aka: kill it)
		while (true) {
			threadGate.wait();
			if (atomicLoad(DIE))
				break;
			for (uint y = start; y < end; y++) {
				for (uint x = 0; x < screen.width; x++) {
					tracePixel(x, y);
				}
			}
		}
	}

	void tracePixel(uint x, uint y) {
		Vec!2 delta = Vec!2(x * widthFrac, y * heightFrag * verticalFrac) * 2 - Vec!2(1, verticalFrac);

		Vec!3 dir_cam = Vec!3(delta.x, delta.y, virtualPlaneZ).normalize();
		Vec!4 dir_world4 = scene.cam.camMatrix ^ Vec!4(dir_cam.x, dir_cam.y, dir_cam.z, 0);
		Vec!3 dir_world = Vec!3(dir_world4.x, dir_world4.y, dir_world4.z).normalize();

		Ray ray = Ray(scene.cam.pos, dir_world);
		Vec!4 color = trace(ray, 0);
		// Vec!4 color = Vec!4(dir_world.x,dir_world.y,0, 1);
		screen.setPixel(x, y, color);
	}

	void trace() {
		import std.math;
		import std.parallelism;

		scene.prepare(useBVH);

		this.virtualPlaneZ = -1.0f / tan(scene.cam.fov / 2.0f);
		this.verticalFrac = cast(float) screen.height / cast(float) screen.width;

		this.widthFrac = 1.0f / cast(float) screen.width;
		this.heightFrag = 1.0f / cast(float) screen.height;

		threadGate.open();
		while (threadGate.waiters < actualThreadNum)
			Thread.yield();
	}

	Vec!4 trace(Ray ray, uint depth) {
		float closest = float.max;
		ulong hitID = 0;

		if (useBVH) {
			BoundingBox[] testBoxes = [scene.bvh.tree[0]];

			while (testBoxes.length > 0) {
				BoundingBox box = testBoxes[0];
				testBoxes = testBoxes[1 .. $];

				if (hitsBoundingBox(ray, box)) {
					if (box.isLeaf) {
						for (uint i = box.firstIndexID; i < box.firstIndexID + box.indexCount; i++) {
							float dist = intersectTriangle(ray, i);
							if (dist < closest && dist > 0) {
								closest = dist;
								hitID = i;
							}
						}
					} else {
						testBoxes ~= scene.bvh.tree[box.leftChild];
						testBoxes ~= scene.bvh.tree[box.rightChild];
					}
				}
			}
		} else {
			foreach (i; 0 .. scene.indices.length) {
				float dist = intersectTriangle(ray, i);
				if (dist < closest && dist > 0) {
					closest = dist;
					hitID = i;
				}
			}
		}

		if (closest == float.max) // no hit
			return scene.backgroundColor;
		return scene.colors[scene.indices[hitID][0]]; // TODO
	}

	static bool hitsBoundingBox(const Ray ray, const BoundingBox box) {
		import std.algorithm;

		Vec!3 lowDistPerAxis = (box.low - ray.org) / ray.dir;
		Vec!3 highDistPerAxis = (box.high - ray.org) / ray.dir;
		Vec!3 inDistPerAxis;
		Vec!3 outDistPerAxis;
		foreach (i; 0 .. 3) {
			float low = lowDistPerAxis[i];
			float high = highDistPerAxis[i];
			if (low < high) {
				inDistPerAxis[i] = low;
				outDistPerAxis[i] = high;
			} else {
				inDistPerAxis[i] = high;
				outDistPerAxis[i] = low;
			}
		}

		float inDist = inDistPerAxis.max();
		float outDist = outDistPerAxis.min();
		return inDist > 0 && inDist < outDist;
	}

	unittest {
		BoundingBox box;
		box.low = Vec!3(0, 0, 0);
		box.high = Vec!3(1, 1, 1);
		Ray ray;
		ray.org = Vec!3(0.5, 0.5, -0.5);
		ray.dir = Vec!3(0, 0, 1);
		assert(hitsBoundingBox(ray, box));
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
		// Vec!3 barycentric = calcProjectedBarycentric(positions, point);
		static foreach (i; 0 .. 3)
			if (barycentric[i] < 0)
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

	static Vec!3 calcBarycentric(const Vec!3[3] verts, const Vec!3 normal, const Vec!3 point) {
		Vec!3 pToV0 = verts[0] - point;
		Vec!3 pToV1 = verts[1] - point;
		Vec!3 pToV2 = verts[2] - point;
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

	unittest {
		foreach (k; 0 .. 100) {
			import std.random : uniform;

			Vec!3[3] verts;
			Vec!3 normal;
			Vec!3 bary;
			Vec!3 point;
			foreach (i; 0 .. 3)
				foreach (j; 0 .. 3)
					verts[i][j] = uniform(-5.0, 5.0);
			normal = (verts[1] - verts[0]).cross(verts[2] - verts[0]).normalize();

			bary[0] = uniform!"[]"(0.0, 1.0);
			bary[1] = uniform!"[]"(0.0, 1.0);
			bary[2] = 1.0 - bary[0] - bary[1];
			assertAlmostEqual(bary.sum(), 1.0);

			point = Vec!3(0);
			static foreach (i; 0 .. 3)
				point += verts[i] * bary[i];

			Vec!3 calculatedBary = calcBarycentric(verts, normal, point);
			Vec!3 calculatedProjectedBary = calcProjectedBarycentric(verts, point);

			calculatedBary.assertAlmostEq(bary);
			calculatedProjectedBary.assertAlmostEq(bary);
		}
	}

	/// Alternative way projection onto 2d xyz planes.
	static Vec!3 calcProjectedBarycentric(const Vec!3[3] verts, const Vec!3 point) {
		const Vec!3 normal = (verts[1] - verts[0]).cross(verts[2] - verts[0]);
		import std.math : abs;

		// TODO Proof? source:https://ceng2.ktu.edu.tr/~cakir/files/grafikler/Texture_Mapping.pdf
		const float xAreaAbs = abs(normal.x); // = * 2
		const float yAreaAbs = abs(normal.y); // = * 2
		const float zAreaAbs = abs(normal.z); // = * 2

		if (xAreaAbs >= yAreaAbs && xAreaAbs >= zAreaAbs) {
			return calcProjectedBarycentric!("y", "z")(normal.x, verts, point);
		} else if (yAreaAbs >= zAreaAbs) {
			return calcProjectedBarycentric!("z", "x")(normal.y, verts, point);
		} else {
			return calcProjectedBarycentric!("x", "y")(normal.z, verts, point);
		}
	}

	static private Vec!3 calcProjectedBarycentric(string firstAxis, string secondAxis)(const float fullArea,
		const Vec!3[3] verts, const Vec!3 point) {
		pragma(inline, true);
		const float fullAreaFrac = 1.0f / fullArea;
		Vec!3 bary;
		bary[0] = triangleAreaDouble([
			Vec!2(mixin("point." ~ firstAxis), mixin("point." ~ secondAxis)),
			Vec!2(mixin("verts[1]." ~ firstAxis), mixin("verts[1]." ~ secondAxis)),
			Vec!2(mixin("verts[2]." ~ firstAxis), mixin("verts[2]." ~ secondAxis))
		]) * fullAreaFrac;
		bary[1] = triangleAreaDouble([
			Vec!2(mixin("point." ~ firstAxis), mixin("point." ~ secondAxis)),
			Vec!2(mixin("verts[2]." ~ firstAxis), mixin("verts[2]." ~ secondAxis)),
			Vec!2(mixin("verts[0]." ~ firstAxis), mixin("verts[0]." ~ secondAxis))
		]) * fullAreaFrac;
		bary[2] = 1.0f - bary[0] - bary[1];
		return bary;
	}

	static private float triangleAreaDouble(const Vec!2[3] verts) {
		pragma(inline, true);
		return (verts[0].x - verts[1].x) * (verts[1].y - verts[2].y) + (verts[1].x - verts[2].x) * (
			verts[1].y - verts[0].y);
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

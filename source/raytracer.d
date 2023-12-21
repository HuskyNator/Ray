module raytracer;
import arrayqueue;
import bvh;
import core.atomic;
import core.sync.semaphore;
import core.thread;
import gate;
import raycam;
import screen;
import std.algorithm : max, min;
import std.parallelism : totalCPUs;
import vertexd;

float u_occlusion = .1;
float u_diffuse = .7;
float u_specular = .2;
float u_specular_power = 50;

struct Scene {
	RayCamera camera;
	Light[] lights;

	uint[3][] indices;
	Vec!3[] positions;
	Vec!3[] normals; // per vertex -> otherwise normalmap or parallex mapping et cetera

	struct Colors {
		bool useMaterial;
		union {
			Vec!4[] vertexColors;
			struct {
				Vec!2[] uvs;
				Material material;
			}
		}
	}

	Colors colors;
	Vec!4 backgroundColor; // environment map?

	Vec!4 getColor(ulong triangleIndex, Vec!3 barycentric) {
		uint[3] triangle = indices[triangleIndex];
		if (colors.useMaterial) {
			Vec!2 uv = Vec!2(0);
			foreach (i; 0 .. 3) {
				uv += (colors.uvs[triangle[i]] % Vec!2(1, 1)) * barycentric[i];
			}
			return colors.material.baseColor_texture.base.sampleTexture(
				uv) * colors.material.baseColor_factor;
		} else {
			Vec!4 color = Vec!4(0);
			static foreach (i; 0 .. 3)
				color += colors.vertexColors[triangle[i]] * barycentric[i];
			return color;
		}
	}

	Vec!3[] triangleNormals;
	BVH bvh;

	this(RayCamera camera, Light[] lights, GltfMesh mesh, Vec!4 backgroundColor, uint minInBox, uint binCount) {
		Colors meshColors;
		meshColors.useMaterial = mesh.material.baseColor_texture !is null;
		if (!meshColors.useMaterial) {
			assert(mesh.attributeSet.color[0].present());
			meshColors.vertexColors = (cast(
					Vec!4*) mesh.attributeSet.color[0].content.ptr)[0
				.. mesh.attributeSet.color[0].elementCount].dup;
		} else {
			assert(mesh.material.baseColor_texture !is null);
			Mesh.Attribute uvs = mesh.attributeSet
				.texCoord[mesh.material.baseColor_texture.texCoord];
			assert(uvs.present());
			meshColors.uvs = (cast(Vec!2*) uvs.content.ptr)[0 .. uvs.elementCount].dup;
			meshColors.material = mesh.material;
		}

		this(camera, lights, mesh.index.attr.getContent!3(),
			(cast(Vec!3*) mesh.attributeSet.position.content.ptr)[0 .. mesh
				.attributeSet.position.elementCount],
			(cast(Vec!3*) mesh.attributeSet.normal.content.ptr)[0 .. mesh.attributeSet.normal.elementCount],
			meshColors, backgroundColor, minInBox, binCount);
	}

	this(RayCamera camera, Light[] lights, uint[3][] indices, Vec!3[] positions, Vec!3[] normals,
		Scene.Colors colors, Vec!4 backgroundColor, uint minInBox, uint binCount) {
		this.camera = camera;
		this.lights = lights;

		// duplicated as they may be changed.
		this.indices = indices.dup;
		this.positions = positions.dup;
		this.normals = normals.dup;

		this.colors = colors;
		this.backgroundColor = backgroundColor;

		calculateBVH(minInBox, binCount);
		calculateNormals();
	}

	void calculateBVH(uint minInBox, uint binCount) {
		this.bvh = BVH(indices, positions, minInBox, binCount);
	}

	void calculateNormals() {
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
	Screen screen;

	private {
		debug (single_thread) {
		} else {
			Thread[] threads;
			shared uint[2][] threadParams;

			shared uint actualThreadNum;
			Gate threadGate;

			shared uint threadCounter = 0;
			shared bool DIE = false;
		}

		float virtualPlaneZ;
		float verticalFrac;
		float widthFrac;
		float heightFrag;

		bool useBVH;
		uint maxDepth;
		Scene scene;

		static ArrayQueue!BoundingBox boxQueue;
	}

	debug (single_thread) {
	} else {
		~this() {
			atomicStore(DIE, true);
			threadGate.setAlwaysOpen(true);
			foreach (Thread t; threads)
				t.join();
		}
	}

	this(Screen screen) {
		this.screen = screen;

		debug (single_thread) {
		} else {
			immutable uint threadNum = max(1, totalCPUs - 1);
			immutable uint perThread = screen.height / threadNum;
			immutable uint loss = screen.height % threadNum;
			this.actualThreadNum = threadNum + ((loss > 0) ? 1 : 0); // TODO BUGREPORT ZONDER HAAKJES

			this.threads.reserve(actualThreadNum);
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
	}

	debug (single_thread) {
	} else {
		void threadTrace() {
			uint id = atomicFetchAdd(threadCounter, 1);
			threads[id] = Thread.getThis();
			uint start = threadParams[id][0];
			uint end = threadParams[id][1];
			boxQueue = ArrayQueue!BoundingBox(4);

			// TODO Figure out how to end thread without creating `shouldStop` boolean (aka: kill it)
			while (true) {
				threadGate.wait();
				if (atomicLoad(DIE))
					break;
				traceRows(start, end);
			}
		}
	}

	void traceRows(uint start, uint end) {
		for (uint y = start; y < end; y++) {
			for (uint x = 0; x < screen.width; x++) {
				tracePixel(x, y);
			}
		}
	}

	void tracePixel(uint x, uint y) {
		Vec!2 delta = Vec!2(x * widthFrac, y * heightFrag * verticalFrac) * 2 - Vec!2(1, verticalFrac);

		Vec!3 dir_cam = Vec!3(delta.x, delta.y, virtualPlaneZ).normalize();
		Vec!4 dir_world4 = scene.camera.cameraMatrix ^ Vec!4(dir_cam.x, dir_cam.y, dir_cam.z, 0);
		Vec!3 dir_world = Vec!3(dir_world4.x, dir_world4.y, dir_world4.z).normalize();

		Ray ray = Ray(scene.camera.location, dir_world);
		Vec!4 color = trace(ray, 0);
		// Vec!4 color = Vec!4(dir_world.x,dir_world.y,0, 1);
		screen.setPixel(x, y, color);
	}

	void trace(Scene scene, uint maxDepth, bool useBVH) {
		import std.math;
		import std.parallelism;

		this.scene = scene;
		this.maxDepth = maxDepth;
		this.useBVH = useBVH;

		this.virtualPlaneZ = -1.0f / tan(scene.camera.fov / 2.0f);
		this.verticalFrac = cast(float) screen.height / cast(float) screen.width;

		this.widthFrac = 1.0f / cast(float) screen.width;
		this.heightFrag = 1.0f / cast(float) screen.height;

		debug (single_thread) {
			traceRows(0, screen.height);
		} else {
			threadGate.open();
			while (threadGate.waiters < actualThreadNum)
				Thread.yield();
		}
	}

	Vec!4 trace(Ray ray, uint depth, float maxDist = float.max) {
		Hit closestIntersection;
		closestIntersection.distance = maxDist;

		if (useBVH) {
			boxQueue.clear();
			boxQueue.add(scene.bvh.tree[0]);

			while (boxQueue.length > 0) {
				BoundingBox box = boxQueue.pop();

				float boundDist = hitsBoundingBox(ray, box);
				if (boundDist > 0 && boundDist <= closestIntersection.distance) {
					// TODO: optimize skipping of boundingboxes (eg. when other intersections have been found)
					if (box.isLeaf) {
						for (uint i = box.firstIndexID; i < box.firstIndexID + box.indexCount;
							i++) {
							Hit intersect = intersectTriangle(ray, i);
							if (intersect.distance < closestIntersection.distance && intersect.distance > 0) {
								closestIntersection = intersect;
							}
						}
					} else {
						boxQueue.add(scene.bvh.tree[box.leftChild]);
						boxQueue.add(scene.bvh.tree[box.rightChild]);
					}
				}
			}
		} else {
			foreach (i; 0 .. scene.indices.length) {
				Hit intersect = intersectTriangle(ray, i);
				if (intersect.distance < closestIntersection.distance && intersect.distance > 0) {
					closestIntersection = intersect;
				}
			}
		}

		if (closestIntersection.distance == float.max) // no hit
			return scene.backgroundColor;

		Vec!4 hitColor = shade(closestIntersection);
		if (depth == maxDepth)
			return hitColor;

		//TODO: Ray transmissionRay
		//TODO Ray reflectedRay = ray.reflect(closestIntersection);
		//TODO: note both will calculate the mapped normal at position ^ (precalculate inside intersection?)
		// hitColor += <?> trace(reflectedRay, depth + 1);
		// temporary:
		return hitColor;
	}

	Vec!4 shade(Hit hit) {
		uint[3] triangle = scene.indices[hit.triangleIndex];
		Vec!3 normal;
		Vec!3 color;
		// Determine color & normal
		if (!scene.colors.useMaterial) {
			foreach (i; 0 .. 3) {
				normal += scene.normals[triangle[i]];
				color += scene.colors.vertexColors[triangle[i]];
			}
			normal *= hit.barycentric;
			color *= hit.barycentric;
			// diffuse = 0.7;
			// specular = 0.3;
			// TODO
			assert(0);
		} else {
			Material material = scene.colors.material;
			Vec!2 uv;
			foreach (i; 0 .. 3)
				uv += (scene.colors.uvs[triangle[i]] % Vec!2(1, 1));
			uv *= hit.barycentric;
			color = material.baseColor_texture.base.sampleTexture(
				uv) * colors.material.baseColor_factor;
			normal = material.normal_texture.base.sampleTexture(uv);
			Vec!4 mr = material.metal_roughness_texture.base.sampleTexture(uv);
			float roughness = mr[1] * material.roughnessFactor;
			float metalic = mr[2] * material.metalFactor;
			//TODO: more
			assert(0);
		}
		//TODO: temp model
		// float diffuse = scene.colors.material.roughnessFactor;
		// float specular = scene.colors.material.metal_roughness_texture
		// Loop over lights
		// foreach (Light l; scene.lights) {
		// 	Vec!3 toLight = (l.pos - hit.point).normalize();
		// 	Vec!3 halfway = (toLight - hit.ray.dir).normalize();

		// }
	}

	static float hitsBoundingBox(const Ray ray, const BoundingBox box) {
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
		if (inDist >= outDist)
			return -1;
		return inDist;
	}

	unittest {
		BoundingBox box;
		box.low = Vec!3(0, 0, 0);
		box.high = Vec!3(1, 1, 1);
		Ray ray;
		ray.org = Vec!3(0.5, 0.5, -0.5);
		ray.dir = Vec!3(0, 0, 1);
		assert(hitsBoundingBox(ray, box) > 0);
	}

	struct Hit {
		Ray ray;
		Vec!3 point;
		Vec!3 barycentric;
		float distance;
		ulong triangleIndex;

		T interpolate(T)(T[3] vals) {
			return (vals * barycentric).sum!T();
		}
	}

	// Only positive distance hits.
	Hit intersectTriangle(ref Ray ray, ulong index) {
		Vec!3 normal = scene.triangleNormals[index];
		uint[3] triangle = scene.indices[index];
		Vec!3 pos0 = scene.positions[triangle[0]];

		Hit intersection;
		intersection.ray = ray;

		float dist = intersectPlane(ray, normal, pos0);
		if (dist < 0) {
			intersection.distance = -1;
			return intersection;
		}
		Vec!3 point = ray.org + ray.dir * dist;
		Vec!3[3] positions = [
			pos0, scene.positions[triangle[1]], scene.positions[triangle[2]]
		];
		Vec!3 barycentric = calcBarycentric(positions, normal, point);
		// Vec!3 barycentric = calcProjectedBarycentric(positions, point); // TODO choose
		static foreach (i; 0 .. 3)
			if (barycentric[i] < 0) {
				intersection.distance = -1;
				return intersection;
			}

		return Hit(ray, point, barycentric, dist, index);
	}

	// Only positive distance hits.
	float intersectPlane(ref Ray ray, Vec!3 normal, Vec!3 planePoint) {
		float rProject = ray.dir.dot(normal);
		if (rProject == 0)
			return -1; // parallel
		Vec!3 toPlane = planePoint - ray.org;
		float planeDistance = toPlane.dot(normal);
		float distance = planeDistance / rProject;
		return distance;
	}

	static Vec!3 calcBarycentric(const Vec!3[3] verts, const Vec!3 point) {
		Vec!3 normal = verts[1].cross(verts[0]).normalize();
		return calcBarycentric(verts, normal, point);
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

	static private Vec!3 calcProjectedBarycentric(string firstAxis, string secondAxis)(
		const float fullArea,
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
		return (verts[0].x - verts[1].x) * (verts[1].y - verts[2].y) + (
			verts[1].x - verts[2].x) * (
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

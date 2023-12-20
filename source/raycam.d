module raycam;
import vertexd.world.camera;
import vertexd.core;
import raytracer;

struct RayCamS {
	Vec!3 pos;
	Mat!4 camMatrix;
	float fov;
}

class RayCamera : Camera {
	import vertexd.misc : degreesToRadians;

	RayTracer* rayTracer;
	float fov; // horizontal

	this(RayTracer* rayTracer, float fov = degreesToRadians(90.0f)) {
		super(Mat!4(1));
		this.rayTracer = rayTracer;
		this.fov = fov;
	}

	override void update() {
		this.location = Vec!3(owner.modelMatrix.col(3)[0 .. 3]);
		this.cameraMatrix = owner.modelMatrix;
	}

	override void use() {
		rayTracer.scene.cam = RayCamS(location, cameraMatrix, fov);
	}
}

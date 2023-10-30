module raycam;
import vertexd.world.camera;
import vertexd.core;
import raytracer;

struct RayCamS {
	Vec!3 pos;
	Mat!4 camMatrix;
	float focalLength = 1;
}

class RayCamera : Camera {
	float focalLength;

	this(float focalLength = 1.0f) {
		super(Mat!4(1));
		this.focalLength = focalLength;
	}

	override void update(){
		this.location = Vec!3(owner.modelMatrix.col(3)[0 .. 3]);
		this.cameraMatrix = owner.modelMatrix;
	}

	override void use() {
		RayTracer.scene.cam = RayCamS(location, cameraMatrix, focalLength);
	}
}

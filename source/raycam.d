module raycam;
import vertexd.world.camera;
import vertexd.core;
import raytracer;

class RayCamera : Camera {
	import vertexd.misc : degreesToRadians;

	float fov; // horizontal

	this(float fov = degreesToRadians(90.0f)) {
		super(Mat!4(1));
		this.fov = fov;
	}

	override void update() {
		this.location = Vec!3(owner.modelMatrix.col(3)[0 .. 3]);
		this.cameraMatrix = owner.modelMatrix;
	}
}

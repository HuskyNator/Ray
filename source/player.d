module player;
import vertexd;

class Player : Node {
	private Quat xRot;
	private Quat yRot;

	private Vec!3 _displacement;
	private Vec!2 _rotation;
	private Vec!2 _rotationDelta;
	private Vec!2 _old_rotation;
	precision speed = 1;
	precision rotationSpeed = 0.2;

	this() {
		super();
	}

	void keyInput(KeyInput input) nothrow {
		try {
			import bindbc.glfw;
			import bindbc.opengl;

			if (input.event != GLFW_PRESS && input.event != GLFW_RELEASE)
				return;

			int delta = (input.event == GLFW_PRESS) ? 1 : -1;
			switch (input.key) {
				case GLFW_KEY_A:
					_displacement.x -= delta;
					break;
				case GLFW_KEY_D:
					_displacement.x += delta;
					break;
				case GLFW_KEY_SPACE:
					_displacement.y += delta;
					break;
				case GLFW_KEY_LEFT_SHIFT:
					_displacement.y -= delta;
					break;
				case GLFW_KEY_S:
					_displacement.z -= delta;
					break;
				case GLFW_KEY_W:
					_displacement.z += delta;
					break;
				case GLFW_KEY_LEFT_CONTROL:
					_rotation = Vec!2(0);
					// location = Vec!3(0);
					break;
				default:
			}
		} catch (Exception e) {
		}
	}

	void mouseInput(MousepositionInput input) nothrow {
		_rotationDelta.y -= input.x - _old_rotation.x;
		_rotationDelta.x -= input.y - _old_rotation.y;
		_old_rotation.x = input.x;
		_old_rotation.y = input.y;
	}

	import std.datetime;

	override void logicStep(Duration deltaT) {
		import std.math;

		double deltaSec = deltaT.total!"hnsecs"() / 10_000_000.0;

		Vec!3 forward = yRot * Vec!3([0, 0, -1]);
		Vec!3 right = yRot * Vec!3([1, 0, 0]);

		Mat!3 displaceMat;
		displaceMat.setCol(0, right);
		displaceMat.setCol(1, Vec!3([0, 1, 0]));
		displaceMat.setCol(2, forward);

		this.location = this.location + cast(Vec!3)(displaceMat ^ (_displacement * cast(prec)(speed * deltaSec)));

		_rotationDelta = _rotationDelta * cast(prec)(rotationSpeed * deltaSec);
		_rotation = _rotation + _rotationDelta;
		if (abs(_rotation.x) > PI_2)
			_rotation.x = sgn(_rotation.x) * PI_2;
		if (abs(_rotation.y) > PI)
			_rotation.y -= sgn(_rotation.y) * 2 * PI;

		xRot = Quat.rotation(Vec!3([1, 0, 0]), _rotation.x);
		yRot = Quat.rotation(Vec!3([0, 1, 0]), _rotation.y);
		this.rotation = yRot * xRot;

		_rotationDelta = Vec!2(0);

		super.logicStep(deltaT);
	}
}

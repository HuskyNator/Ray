module player;
import vertexd;

class Speler : Node {
	private Quat xdraai;
	private Quat ydraai;

	private Vec!3 _verplaatsing;
	private Vec!2 _draai;
	private Vec!2 _draaiDelta;
	private Vec!2 _oude_draai;
	precision snelheid = 1;
	precision draaiSnelheid = 0.2;

	this() {
		super();
	}

	void toetsinvoer(KeyInput input) nothrow {
		try {
			import bindbc.glfw;
			import bindbc.opengl;

			if (input.event != GLFW_PRESS && input.event != GLFW_RELEASE)
				return;

			int delta = (input.event == GLFW_PRESS) ? 1 : -1;
			switch (input.key) {
				case GLFW_KEY_A:
					_verplaatsing.x -= delta;
					break;
				case GLFW_KEY_D:
					_verplaatsing.x += delta;
					break;
				case GLFW_KEY_SPACE:
					_verplaatsing.y += delta;
					break;
				case GLFW_KEY_LEFT_SHIFT:
					_verplaatsing.y -= delta;
					break;
				case GLFW_KEY_S:
					_verplaatsing.z -= delta;
					break;
				case GLFW_KEY_W:
					_verplaatsing.z += delta;
					break;
				case GLFW_KEY_LEFT_CONTROL:
					_draai = Vec!2(0);
					_verplaatsing = Vec!3(0);
					break;
				default:
			}
		} catch (Exception e) {
		}
	}

	void muisinvoer(MousepositionInput input) nothrow {
		_draaiDelta.y -= input.x - _oude_draai.x;
		_draaiDelta.x -= input.y - _oude_draai.y;
		_oude_draai.x = input.x;
		_oude_draai.y = input.y;
	}

	import std.datetime;

	override void logicStep(Duration deltaT) {
		import std.math;

		double deltaSec = deltaT.total!"hnsecs"() / 10_000_000.0;

		Vec!3 vooruit = ydraai * Vec!3([0, 0, -1]);
		Vec!3 rechts = ydraai * Vec!3([1, 0, 0]);

		Mat!3 verplaatsMat;
		verplaatsMat.setCol(0, rechts);
		verplaatsMat.setCol(1, Vec!3([0, 1, 0]));
		verplaatsMat.setCol(2, vooruit);

		this.location = this.location + cast(Vec!3)(verplaatsMat ^ (_verplaatsing * cast(prec)(snelheid * deltaSec)));

		_draaiDelta = _draaiDelta * cast(prec)(draaiSnelheid * deltaSec);
		_draai = _draai + _draaiDelta;
		if (abs(_draai.x) > PI_2)
			_draai.x = sgn(_draai.x) * PI_2;
		if (abs(_draai.y) > PI)
			_draai.y -= sgn(_draai.y) * 2 * PI;

		xdraai = Quat.rotation(Vec!3([1, 0, 0]), _draai.x);
		ydraai = Quat.rotation(Vec!3([0, 1, 0]), _draai.y);
		this.rotation = ydraai * xdraai;

		_draaiDelta = Vec!2(0);

		super.logicStep(deltaT);
	}
}

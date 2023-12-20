module bvh;
import vertexd.core.mat;
import std.algorithm.sorting : topN;

struct BoundingBox {
	Vec!3 low;
	Vec!3 high;
	uint leftChild = uint.max;
	uint rightChild = uint.max;

	this(const Vec!3[] content) {
		assert(content.length > 0);
		box.low = content[0];
		box.high = content[0];
		foreach (Vec!3 point; content) {
			static foreach (axis; 0 .. 3) {
				if (point[axis] < box.low[axis])
					box.low[axis] = point[axis];
				if (point[axis] > box.high[axis])
					box.high[axis] = point[axis];
			}
		}
	}

	bool hasChildren() {
		bool hasChild = leftChild != uint.max;
		assert(hasChild || rightChild == uint.max);
		return hasChild;
	}

	float area() {
		import std.algorithm.iteration : reduce;

		return (left.high - left.low).reduce!"a*b"();
	}
}

// Zou ook kunnen sorteren langs alle 3 de assen & vervolgens niet meer hoeven te sorteren.
struct BVH {
	BoundingBox[] tree;
	uint minInBox;

	this(uint[3][] indices, Vec!3[] positions, uint minInBox = 4) {
		this.minInBox = minInBox;
		Vec!3[] centroids = [];
		centroid.reserve(indices.length);
		foreach (uint[3] triangle; indices) {
			Vec!3[3] pos;
			static foreach (i; 0 .. 3)
				pos[i] = positions[triangle[i]];
			centroids ~= (pos[0] + pos[1] + pos[2]) * (1.0 / 3.0);
		}
		buildTree(centroids);
	}

	uint buildTree(Vec!3[] centroids) {
		BoundingBox box = BoundingBox(centroids);
		uint boxIndex = tree.length;
		tree ~= box;

		if (centroids.length > minInBox) {
			SplitBox boxes = splitBox(centroids, boxIndex);
			// Edge Case: no actual split (& no smaller area than original).
			if (boxes.area < box.size()) {
				// split
			}
			// dont split
		}
		return boxIndex;
	}

	import std.typecons : Tuple;

	private alias SplitBox = Tuple!(float, "area", BoundingBox, "left", BoundingBox, "right");
	SplitBox splitBox(ref Vec!3[] centroids, uint parentID) {
		SplitBox splitBox;
		Vec!3[] splitCentroids;
		splitBox.area = float.max;
		static foreach (i; 0 .. 3) {
			Vec!3[] centroidsI = centroids.dup;
			SplitBox splitBoxI = splitBoxAxis!i(centroidsI);
			if (splitBoxI.area < splitBox.area) {
				splitBox = splitBoxI;
				splitCentroids = centroidsI;
			}
		}
		centroids = splitCentroids;
		return splitBox;
	}

	SplitBox splitBoxAxis(ubyte axis)(Vec!3[] centroids) {
		assert(axisIndex >= 0 && axisIndex <= 2);

		string predicate = "a[" ~ axis.stringof ~ "]" ~ " < b[" ~ axis.stringof ~ "]";
		pragma(msg, predicate);
		topN!predicate(centroids, centroids.length / 2);

		SplitBox result;
		result.left = BoundingBox(centroids[0 .. centroids.length / 2]);
		result.right = BoundingBox(centroids[centroids.length / 2 .. $]);
		result.area = result.left.area() + result.right.area();
		return result;
	}
}

module bvh;
import std.algorithm.sorting : sort, topN;
import std.typecons : Tuple;
import vertexd.core.mat;

private struct Centroid {
	Vec!3[3] verts;
	Vec!3 center;
	uint indexID;
}

struct BoundingBox {
	Vec!3 low;
	Vec!3 high;

	bool isLeaf = true; // Start off as leaf.
	union {
		struct { // leaf
			uint leftChild;
			uint rightChild;
		}

		struct {
			uint firstIndexID;
			uint indexCount;
		}
	}

	invariant (isLeaf || rightChild == leftChild + 1); // TODO is this how to check?

	this(const Centroid[] centroids, uint firstIndexID) {
		if (centroids.length == 0)
			return;

		this.low = centroids[0].verts[0];
		this.high = centroids[0].verts[0];
		foreach (Centroid centroid; centroids)
			foreach (Vec!3 point; centroid.verts)
				static foreach (axis; 0 .. 3) {
					if (point[axis] < this.low[axis])
						this.low[axis] = point[axis];
					if (point[axis] > this.high[axis])
						this.high[axis] = point[axis];
				}

		this.firstIndexID = firstIndexID;
		this.indexCount = cast(uint) centroids.length;
	}

	float area() {
		Vec!3 delta = this.high - this.high;
		return delta[0] * delta[1] * delta[2];
	}

	T[] elements(T)(T[] source) const {
		return source[firstIndexID .. firstIndexID + indexCount];
	}

	string toString() {
		import std.conv;

		string str = (isLeaf ? "Leaf" : "Parent") ~ "Box([" ~ low.toString() ~ ":" ~ high.toString() ~ "], ";
		if (isLeaf) {
			str ~= "first:" ~ firstIndexID.to!string;
			str ~= ", count:" ~ indexCount.to!string;
		} else {
			str ~= "left:" ~ leftChild.to!string;
			str ~= ", right:" ~ rightChild.to!string;
		}
		return str ~ ")";
	}
}

// Zou ook kunnen sorteren langs alle 3 de assen & vervolgens niet meer hoeven te sorteren.
struct BVH {
	static const uint MIN_IN_BOX = 4;
	static const uint BINS = 1; // 1 = no binning: equal split.

	BoundingBox[] tree;

	string toString(bool nice = false) const {
		import std.conv;

		char[] str = "BVH(".dup;
		foreach (i, BoundingBox box; tree) {
			if (nice)
				str ~= "\n\t";
			str ~= i.to!string ~ ": " ~ box.toString() ~ ',';
		}
		str[$ - 1] = '\n';
		str ~= ')';
		return cast(string) str;
	}

	this(ref uint[3][] indices, const Vec!3[] positions) {
		assert(indices.length > 0);
		assert(indices.length < uint.max);
		Centroid[] centroids = [];
		centroids.reserve(indices.length);

		foreach (indexID, uint[3] triangle; indices) {
			Vec!3[3] pos;
			foreach (i; 0 .. 3)
				pos[i] = positions[triangle[i]];
			Vec!3 center = Vec!3(pos[0] + pos[1] + pos[2]) / 3.0f;
			centroids ~= Centroid(pos, center, cast(uint) indexID);
		}

		tree ~= BoundingBox(centroids, 0u);

		// Create a tri-duplicate list of centroids.
		// Eliminates allocations: can sort along axes in parallel.
		Centroid[][3] allCentroids = [centroids, centroids.dup, centroids.dup];
		buildTree(tree[0], allCentroids); // Build the tree

		import std.stdio;

		writeln(this.toString(true));

		// Create resorted indeces array to match up with BoundingBox ID's
		uint[3][] newIndices = [];
		newIndices.reserve(indices.length);
		foreach (Centroid centroid; centroids)
			newIndices ~= indices[centroid.indexID];

		// Replace indices in place
		indices[] = newIndices[];
	}

	void buildTree(ref BoundingBox box, Centroid[][3] allCentroids) {
		if (box.indexCount <= MIN_IN_BOX) // Don't split with too few elements
			return;

		SplitBox boxes = splitBox(box, allCentroids);
		// static if (BINS > 1)
		if (boxes.area >= box.area()) // Should only split when this creates improvement (when binning).
			return;

		// split
		assert(tree.length < (cast(ulong) uint.max) + 2);
		uint leftID = cast(uint) tree.length;
		box.leftChild = leftID;
		box.rightChild = leftID + 1;
		box.isLeaf = false;

		tree ~= boxes.left;
		tree ~= boxes.right;
		buildTree(tree[leftID], allCentroids);
		buildTree(tree[leftID + 1], allCentroids);
	}

	alias SplitBox = Tuple!(float, "area", BoundingBox, "left", BoundingBox, "right");

	/// Split Parent Box along most optimal axis.
	SplitBox splitBox(const BoundingBox parent, Centroid[][3] allCentroids) {
		SplitBox splitBox;
		splitBox.area = float.max;
		uint optimalAxis = 0;

		// Get tri-duplicate axis ranges of centroids to be split over.
		Centroid[][3] axisCentroids;
		static foreach (i; 0 .. 3)
			axisCentroids[i] = parent.elements(allCentroids[i]);

		// Find optimal axis
		SplitBox splitBoxI;
		static foreach (i; 0 .. 3) {
			splitBoxI = splitBoxAxis!i(parent, axisCentroids[i]);
			if (splitBoxI.area < splitBox.area) {
				splitBox = splitBoxI;
				optimalAxis = i;
			}
		}

		// Assign correct sorting to all axis ranges (in place)
		static foreach (i; 0 .. 3)
			if (i != optimalAxis)
				axisCentroids[i][] = axisCentroids[optimalAxis][];

		return splitBox;
	}

	private static string sortPredicate(ubyte axis)() {
		return "a.center[" ~ axis.stringof ~ "]" ~ " < b.center[" ~ axis.stringof ~ "]";
	}

	/// Split centroids along axis & determine bounding boxes.
	/// Splits into 2 ~equal parts, by number of contained centroids.
	SplitBox splitBoxAxis(ubyte axis)(const BoundingBox parent, Centroid[] centroids) if (BINS == 1) {
		static assert(axis >= 0 && axis <= 2);
		assert(centroids.length > MIN_IN_BOX);
		assert(centroids.length < uint.max);
		uint half = cast(uint) centroids.length / 2;

		topN!(sortPredicate!axis())(centroids, half); // partial sort in place.

		SplitBox result;
		result.left = BoundingBox(centroids[0 .. half], parent.firstIndexID);
		result.right = BoundingBox(centroids[half .. $], parent.firstIndexID + half);
		result.area = result.left.area() + result.right.area();
		return result;
	}

	/// Split centroids along axis & determine bounding boxes.
	/// Splits along bin-edge that minimizes bounding areas.
	SplitBox splitBoxAxis(ubyte axis)(const BoundingBox parent, Centroid[] centroids) if (BINS > 1) {
		sort!(sortPredicate!axis())(centroids); // full sort along axis. (may be able to do better using topN)

		SplitBox minSplit;
		minSplit.area = float.max;
		float binWidth = (parent.high[axis] - parent.low[axis]) / BINS;

		foreach (uint bin; 0 .. BINS - 1) { // skip last bin edge (corresponds to non-split)
			// Find centroid count of left split.
			float binEnd = parent.low[axis] + (bin + 1) * binWidth;
			uint leftCentroidCount = 0;
			foreach (centroid; centroids) {
				if (centroid.center[axis] > binEnd)
					break;
				leftCentroidCount += 1;
			}
			// Determine split
			SplitBox split;
			split.left = BoundingBox(centroids[0 .. leftCentroidCount], parent.firstIndexID);
			split.right = BoundingBox(centroids[leftCentroidCount .. $], parent.firstIndexID + leftCentroidCount);
			split.area = split.left.area() + split.right.area();

			// Choose most optimal split
			if (split.area < minSplit.area)
				minSplit = split;
		}
		return minSplit;
	}
}

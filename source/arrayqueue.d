module arrayqueue;
import std.exception;

/// Implements a Queue inside a dynamic _array.
/// Minimizes allocations by looping.
struct ArrayQueue(T) {
	private T[] _array;
	private size_t _head = 0; // Points to the start of the ArrayQueue.
	private size_t _length = 0;

	this(size_t capacity) {
		this._array = new T[capacity];
	}

	@property size_t length() {
		return _length;
	}

	size_t capacity() {
		return _array.capacity;
	}

	/// Points to the last element.
	private size_t tail() {
		assert(_length > 0, "Empty ArrayQueue has no tail.");
		return (_head + _length - 1) % _array.capacity;
	}

	T[] array() {
		if (_head + _length > _array.capacity)
			return _array[_head .. _array.capacity] ~ _array[0 .. _head + _length - _array.capacity];
		return _array[_head .. _head + _length];
	}

	void add(T element) {
		if (_array.capacity == 0)
			grow(4);
		else if (_array.capacity == _length)
			grow(2 * _array.capacity);
		this._length += 1;
		this._array[tail()] = element;
	}

	void reserve(size_t newCapacity) {
		if (newCapacity > _array.capacity)
			grow(newCapacity);
	}

	private void grow(size_t newCapacity) {
		T[] newArray = new T[newCapacity];
		newArray[0 .. _length] = array();
		this._head = 0;
		this._array = newArray;
	}

	T pop() {
		enforce(_length > 0, "No elements in ArrayQueue.");
		T element = _array[_head];
		if (_length == 1) // empty ArrayQueue
			this._head = 0;
		else // next element exists
			this._head += 1;
		this._length -= 1;
		return element;
	}

	void clear(bool freeArray = false) {
		this._length = 0;
		this._head = 0;
		if (freeArray)
			this._array = [];
	}
}

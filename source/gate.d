module gate;
import core.sync.condition;
import core.sync.mutex;

// An externally controlled arbitrary-waiter-size Barrier.
class Gate {
private:
	Condition _condition;
	Mutex _mutex;
	uint _waiters;
	uint _group;

public:
	@property uint waiters() {
		return _waiters;
	}

	this() {
		this._mutex = new Mutex();
		this._condition = new Condition(_mutex);
	}

	void wait() {
		synchronized (_mutex) {
			uint group = _group;
			_waiters += 1;
			while (group == _group)
				_condition.wait();
		}
	}

	void open() {
		synchronized (_mutex) {
			_group += 1;
			_waiters = 0;
			_condition.notifyAll();
		}
	}
}

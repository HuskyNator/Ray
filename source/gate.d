module gate;
import core.sync.condition;
import core.sync.mutex;
import core.atomic;

// An externally controlled arbitrary-waiter-size Barrier.
class Gate {
private:
	Condition _condition;
	Mutex _mutex;
	uint _waiters = 0;
	uint _group = 0;
	bool _alwaysOpen = false;

public:
	@property uint waiters() {
		return _waiters;
	}

	this() {
		this._mutex = new Mutex();
		this._condition = new Condition(_mutex);
	}

	void wait() {
		if (atomicLoad(_alwaysOpen))
			return;

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

	void setAlwaysOpen(bool val) {
		atomicStore(_alwaysOpen, val);
		open();
	}
}

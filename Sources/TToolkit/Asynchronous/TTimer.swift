import Foundation
import Dispatch

public enum TimerState {
	case activated
	case paused
	case canceled
}

fileprivate let nanosecondMultiplier = 1000000000
fileprivate let microsecondMultiplier = 1000000
fileprivate let millisecondMultiplier = 1000
fileprivate let maxInt = Int.max

extension Double {
	fileprivate func asDispatchTimeIntervalSeconds() -> DispatchTimeInterval {
		if Double(maxInt / nanosecondMultiplier) > self {
			return DispatchTimeInterval.nanoseconds(Int(self*Double(nanosecondMultiplier)))
		} else if Double(maxInt / microsecondMultiplier) > self {
			return DispatchTimeInterval.microseconds(Int(self*Double(microsecondMultiplier)))
		} else if Double(maxInt / millisecondMultiplier) > self {
			return DispatchTimeInterval.milliseconds(Int(self*Double(millisecondMultiplier)))
		} else {
			return DispatchTimeInterval.seconds(Int(self))
		}
	}
}

public class TTimer {
	public typealias TimerHandler = (TTimer) -> Void
		
	private var _timerTarget:DispatchQueue
	public var queue:DispatchQueue {
		get {
			return _internalSync.sync {
				return _timerTarget
			}
		}
		set {
			let valueToAssign = newValue
			_internalSync.sync {
				_timerTarget = valueToAssign
				_timerQueue.setTarget(queue:valueToAssign)
			}
		}
	}
	
	private let _timerQueue:DispatchQueue	//this is the queue that the timer sources are explicityly scheduled against. The target of this queue is assigned to `self._targetQueue`
	private let _priority:Priority			//this specifies the global concurrent priority of this timer
	private let _internalSync:DispatchQueue	//for internal thread safety
	
	private var _state:TimerState
	public var state:TimerState {
		get {
			return _internalSync.sync {
				return _state
			}
		}
	}
	
	private var _timerSource:DispatchSourceTimer? = nil
	private var _lastTriggerDate:DispatchWallTime? = nil
	
	private var _anchor:Date? = nil
	public var anchor:Date? {
		get {
			return _internalSync.sync {
				return _anchor
			}
		}
		set {
			_internalSync.sync {
				_anchor = newValue
			}
		}
	}

	private var _duration:Double? = nil
	public var duration:Double? {
		get {
			return _internalSync.sync {
				return _duration
			}
		}
		set {
			let valueToAssign = newValue
			_internalSync.sync {
				_duration = valueToAssign
			}
		}
	}
	
	private var _handler:TimerHandler? = nil
	public var handler:TimerHandler? {
		get {
			return _internalSync.sync {
				return _handler
			}
		}
		set {
			let valueToAssign = newValue
			_internalSync.sync {
				_handler = valueToAssign
			}
		}
	}
	
	private func _timerInterval() -> DispatchTimeInterval? {
		return _duration?.asDispatchTimeIntervalSeconds()
	}
	
	private func _anchorAdjustedNowTime() -> DispatchWallTime {
		let nowTime = DispatchWallTime.now()
		guard let hasAnchor = _anchor, let hasDuration = _duration else {
			return nowTime
		}
		let timeDelta = hasAnchor.timeIntervalSinceNow
		let intervalRemainder = abs(timeDelta.truncatingRemainder(dividingBy:hasDuration))
		let returnValue = (nowTime - intervalRemainder) + hasDuration
		return returnValue
	}

	/*
		Unschedules the timer so that it no longer fires.
		Return value: 	true if the timer was able to be unscheduled
						false if the there was no timer scheduled
	*/
	private func _unscheduleTimer() -> Bool {
		if let hasCurrentTimer = _timerSource {
			hasCurrentTimer.cancel()
			_state = .canceled
			return true
		}
		return false
	}
	
	/*
		Schedules a new timer with a valid duration and handler
		Assumption: This function is synchronized with internalSync via the calling function
	*/
	private func _rescheduleTimer(lastTrigger:DispatchWallTime?) {
		guard let hasDuration = _timerInterval(), let hasDoubleDuration = _duration, hasDoubleDuration > 0, let handlerToSchedule = _handler else {
			return
		}
		let newSource:DispatchSourceTimer
		newSource = DispatchSource.makeTimerSource(flags:[.strict], queue:_timerQueue)
		newSource.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			let triggerTime = DispatchWallTime.now()
			self._internalSync.async { [weak self] in
				guard let self = self else {
					return
				}
				self._lastTriggerDate = triggerTime
			}
			handlerToSchedule(self)
		}
		
		var baseTime:DispatchWallTime
		if let hasLastTriggerDate = lastTrigger {
			baseTime = hasLastTriggerDate + hasDuration
		} else {
			baseTime = _anchorAdjustedNowTime()
		}
		newSource.schedule(wallDeadline:baseTime, repeating:hasDuration, leeway:.nanoseconds(0))
		newSource.activate()
		_timerSource = newSource
		_state = .activated
	}
	
	/*
		Schedules a new timer (or possibly not) given optional durations, event handlers.
		This function must be called in a synchronized dispatch queue
	*/
	private func _scheduleTimerIfPossible(keepAnchor:Bool) {
		_ = _unscheduleTimer()
		
		guard _handler != nil, _duration != nil else {
			return
		}
		
		if keepAnchor {
			_rescheduleTimer(lastTrigger:_lastTriggerDate)
		} else {
			_rescheduleTimer(lastTrigger:nil)
		}
	}
	
    public init(priority:Priority = Priority.`default`) {
		let globalConcurrent = priority.globalConcurrentQueue
		self._timerTarget = globalConcurrent
		self._timerQueue = DispatchQueue(label:"com.tannersilva.instance.ttimer.fire", qos:priority.asDispatchQoS(), target:globalConcurrent)
		self._priority = priority
		self._internalSync = DispatchQueue(label:"com.tannersilva.instance.ttimer.internal-sync", qos:priority.asDispatchQoS(), target:globalConcurrent)
		self._state = .canceled
	}
	
	/*
		This is the function that will enable a newly initialized and configured TTimer.
	*/
	public func activate() -> Bool {
		return _internalSync.sync {
			guard _state == .canceled else {
				return false
			}
			_scheduleTimerIfPossible(keepAnchor:false)
			return true
		}
	}
	
	/*
		For timers that are already activated, pause will cause the timer to no longer fire its event handler
	*/	
	public func pause() -> Bool {
		_internalSync.sync {
			guard _state == .activated, let hasTimerSource = _timerSource else {
				return false
			}
			hasTimerSource.suspend()
			_state = .paused
			return true
		}
	}
	
	/*
		For timers that are already paused, resume() will cause the timer to resume firing its event handler
	*/
	public func resume() -> Bool {
		_internalSync.sync {
			guard _state == .paused, let hasTimerSource = _timerSource else {
				return false
			}
			hasTimerSource.resume()
			_state = .activated
			return true
		}
	}
	
	/*
		Fires the event handler asyncronously. Does not interrupt the timing of the timer or otherwise disrupt the timers cadence in any way
	*/
	public func fire() {
		_timerQueue.async { [weak self] in
			guard let self = self else {
				return
			}
			if let hasHandler = self.handler {
				hasHandler(self)
			}
		}
	}
	
	/*
		Unschedules a timer. The only way to make a timer functional after cancel() is to call activate() once again.
	*/
	public func cancel() {
		_internalSync.sync {
			_ = _unscheduleTimer()
		}
	}
	
	deinit {
		if state != .canceled {
			_ = _unscheduleTimer()
		}
	}
}


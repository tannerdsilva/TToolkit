import Foundation
import Dispatch

public enum TimerState {
	case activated
	case suspended
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
	
	private let priority:Priority
	private let queue:DispatchQueue
	
	public let soonMode:Bool
	public let strictMode:Bool
	public let autoRun:Bool
	
	private(set) public var state:TimerState
	
	private var timerSource:DispatchSourceTimer? = nil
	private var lastTriggerDate:DispatchWallTime? = nil
	
	private var _anchor:Date? = nil
	public var anchor:Date? {
		get {
			return queue.sync {
				return _anchor
			}
		}
		set {
			queue.sync {
				_anchor = newValue
				if autoRun {
					_scheduleTimerIfPossible()
				}
			}
		}
	}
	//always adjusts with the anchor date into the past
	private var _anchorAdjustedNowTime:DispatchWallTime {
		get {
			let nowTime = DispatchWallTime.now()
			guard let hasDuration = _duration else {
				return nowTime
			}
			guard let hasAnchor = _anchor, let hasDuration = _duration else {
				return nowTime
			}
			let timeDelta = hasAnchor.timeIntervalSinceNow
			let intervalRemainder = timeDelta.truncatingRemainder(dividingBy:hasDuration)
			print("Now: \(nowTime)\tInterval:\(intervalRemainder)")
			if soonMode {
				if intervalRemainder > 0 {
					return nowTime - intervalRemainder
				} else {
					return nowTime + intervalRemainder
				}
			} else {
				if intervalRemainder > 0 {
					return nowTime + (hasDuration - intervalRemainder)
				} else {
					return nowTime + hasDuration + intervalRemainder
				}
			}
		}
	}
	
	private var _timerInterval:DispatchTimeInterval? {
		get {
			return _duration?.asDispatchTimeIntervalSeconds()
		}
	}
	private var _duration:Double? = nil
	public var duration:Double? {
		get {
			return queue.sync {
				return _duration
			}
		}
		set {
			let valueToAssign = newValue
			queue.sync {
				_duration = valueToAssign
				if autoRun {
					_scheduleTimerIfPossible()
				}
			}
		}
	}
	
	private var _handler:TimerHandler? = nil
	public var handler:TimerHandler? {
		get {
			return queue.sync {
				return _handler
			}
		}
		set {
			let valueToAssign = newValue
			queue.sync {
				_handler = valueToAssign
				if autoRun {
					_scheduleTimerIfPossible()
				}
			}
		}
	}
	
	/*
		Unschedules the timer so that it no longer fires.
		Return value: 	true if the timer was able to be unscheduled
						false if the there was no timer scheduled
	*/
	private func _unscheduleTimer() -> Bool {
		if let hasCurrentTimer = timerSource {
			hasCurrentTimer.cancel()
			timerSource = nil
			state = .canceled
			return true
		}
		return false
	}
	
	/*
		Schedules a new timer with a valid duration and handler
		Assumptions: duration must not be 0
	*/
	private func _rescheduleTimer(lastTrigger:DispatchWallTime?, fireNow:Bool) {
		guard let hasDuration = _timerInterval, let hasDoubleDuration = _duration, hasDoubleDuration > 0 else {
			return
		}
		let newSource:DispatchSourceTimer
		if strictMode {
			newSource = DispatchSource.makeTimerSource(flags:[.strict], queue:priority.globalConcurrentQueue)
		} else {
			newSource = DispatchSource.makeTimerSource(flags:[], queue:priority.globalConcurrentQueue)
		}
		newSource.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			self._fire(markTime:true)
		}
		
		var baseTime:DispatchWallTime
		if let hasLastTriggerDate = lastTrigger {
			let newBaseTime = hasLastTriggerDate + hasDuration
			let nowTime = DispatchWallTime.now()
			if fireNow == true && nowTime > newBaseTime {
				baseTime = nowTime
			} else {
				baseTime = newBaseTime
			}
		} else {
			if fireNow {
				baseTime = _anchorAdjustedNowTime
			} else {
				baseTime = _anchorAdjustedNowTime + hasDuration
			}
		}
		newSource.schedule(wallDeadline:baseTime, repeating:hasDuration, leeway:.nanoseconds(0))
		newSource.activate()
		timerSource = newSource
		state = .activated
	}
	
	/*
		Schedules a new timer (or possibly not) given optional durations, event handlers.
		This function DOES NOT ASSUME that duration is not 0, therefore, this should be the function that is used when the duration and handler public variables are assigned
		This function must be called in a synchronized dispatch queue
	*/
	private func _scheduleTimerIfPossible() {
		_unscheduleTimer()
		
		guard _handler != nil, _duration != nil else {
			return
		}
		
		_rescheduleTimer(lastTrigger:lastTriggerDate, fireNow:false)
	}
	
	public init(strict:Bool, autoRun:Bool, soon:Bool) {
		let defaultPriority = Priority.`default`
		self.priority = defaultPriority
		self.queue = DispatchQueue(label:"com.tannersilva.instance.ttimer.sync", qos:defaultPriority.asDispatchQoS(), target:defaultPriority.globalConcurrentQueue)
		self.strictMode = strict
		self.soonMode = soon
		self.state = .canceled
		self.autoRun = autoRun
	}
	
	public func run() {
		queue.sync {
			_scheduleTimerIfPossible()
		}
	}
	
	fileprivate func _fire(markTime:Bool) {
		if markTime {
			lastTriggerDate = DispatchWallTime.now()
		}
		if let hasHandler = _handler {
			hasHandler(self)
		}
	}
	
	public func fire() {
		queue.sync {
			self._fire(markTime:false)
		}
	}
	
	public func play() {
		queue.sync {
			if state == .suspended, let hasTimer = timerSource {
				hasTimer.resume()
				state = .activated
			}
		}
	}
	
	public func pause() {
		queue.sync {
			if state == .activated, let hasTimer = timerSource {
				hasTimer.suspend()
				state = .suspended
			}
		}
	}
	
	public func cancel() {
		queue.sync {
			_unscheduleTimer()
		}
	}
	
	deinit {
		if state != .canceled {
			_unscheduleTimer()
		}
	}
}


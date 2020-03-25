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
		
	private(set) public var state:TimerState
	
	private var timerSource:DispatchSourceTimer? = nil
	private var lastTriggerDate:DispatchWallTime? = nil
	
	private var _timerInterval:DispatchTimeInterval? = nil
	
	private var _duration:Double? = nil
	public var duration:Double? {
		get {
			return _duration
		}
		set {
			let valueToAssign = newValue
			queue.sync {
				_duration = valueToAssign
				rescheduleTimer(duration:_duration, newHandle:_handler, fireNow:false)
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
				if _handler == nil {
					_handler = valueToAssign
					rescheduleTimer(duration:_duration, newHandle:_handler, fireNow:false)
				} else {
					_handler = valueToAssign
				}
				
			}
		}
	}
	
	/*
		Unschedules the timer so that it no longer fires.
		Return value: 	true if the timer was able to be unscheduled
						false if the there was no timer scheduled
	*/
	private func unscheduleTimer() -> Bool {
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
	private func scheduleTimer(duration:Double, handler:TimerHandler, fireNow:Bool) {
		let newSource = DispatchSource.makeTimerSource(queue:priority.globalConcurrentQueue)
		let newTimeInterval = duration.asDispatchTimeIntervalSeconds()
		_timerInterval = newTimeInterval
		newSource.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			self.fire()
		}
		if fireNow {
			newSource.schedule(deadline:.now(), repeating:newTimeInterval, leeway:.nanoseconds(0))
		} else {
			newSource.schedule(deadline:.now() + newTimeInterval, repeating:newTimeInterval, leeway:.nanoseconds(0))
		}
		newSource.activate()
		timerSource = newSource
		state = .activated
	}
	
	/*
		Schedules a new timer (or possibly not) given optional durations, event handlers.
		This function DOES NOT ASSUME that duration is not 0, therefore, this should be the function that is used when the duration and handler public variables are assigned
		This function must be called in a synchronized dispatch queue
	*/
	private func rescheduleTimer(duration:Double?, newHandle:TimerHandler?, fireNow:Bool) {
		unscheduleTimer()
		
		guard let validDuration = duration, validDuration != 0, let hasHandle = newHandle else {
			return
		}
		
		scheduleTimer(duration:validDuration, handler:hasHandle, fireNow:fireNow)
	}
	
	public init() {
		state = .canceled
		
		let defPri = Priority.`default`
		
		self.priority = defPri
		self.queue = DispatchQueue(label:"com.tannersilva.instance.ttimer.sync", qos:defPri.asDispatchQoS(), target:defPri.globalConcurrentQueue)
	}
	
	public func fire() {
		queue.sync {
			lastTriggerDate = DispatchWallTime.now()
			if let hasHandler = _handler {
				hasHandler(self)
			}
		}
	}
	
	public func resume() {
		queue.sync {
			if state == .suspended, let hasTimer = timerSource {
				hasTimer.resume()
				state = .activated
			}
		}
	}
	
	public func suspend() {
		queue.sync {
			if state == .activated, let hasTimer = timerSource {
				hasTimer.suspend()
				state = .suspended
			}
		}
	}
	
	public func cancel() {
		queue.sync {
			unscheduleTimer()
		}
	}
	
	deinit {
		if state != .canceled {
			unscheduleTimer()
		}
	}
}


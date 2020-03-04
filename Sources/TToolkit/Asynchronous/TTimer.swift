import Foundation
import Dispatch

fileprivate enum TimerState {
	case initialized
	case activated
	case suspended
	case canceled
}

public class TTimer {
	private let queue:DispatchQueue
	
	fileprivate var state:TimerState
	private var timer:DispatchSourceTimer
	
	public init(queue:DispatchQueue, seconds:Double, _ inputAction:@escaping(TTimer) -> Void) {
		state = .activated
		self.queue = queue
		timer = DispatchSource.makeTimerSource(queue:queue)
		let dtime = DispatchTimeInterval.nanoseconds(Int(seconds*1000000000))
		timer.schedule(deadline:.now() + dtime, repeating:dtime, leeway:.seconds(0))
		timer.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			inputAction(self)
		}
		timer.activate()
	}
	
	public init(priority:Priority, seconds:Double, _ inputAction:@escaping(TTimer) -> Void) {
		state = .activated
		queue = DispatchQueue.global(qos:priority.asDispatchQoS())
		timer = DispatchSource.makeTimerSource(queue:queue)
		let dtime = DispatchTimeInterval.nanoseconds(Int(seconds*1000000000))
		timer.schedule(deadline:.now() + dtime, repeating:dtime, leeway:.seconds(0))
		timer.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			inputAction(self)
		}
		timer.activate()
	}
	
	public init(seconds:Double, _ inputAction:@escaping(TTimer) -> Void) {
		state = .activated
		queue = DispatchQueue.global(qos:Priority.`default`.asDispatchQoS())
		timer = DispatchSource.makeTimerSource(queue:queue)
		let dtime = DispatchTimeInterval.nanoseconds(Int(seconds*1000000000))
		timer.schedule(deadline:.now() + dtime, repeating:dtime, leeway:.seconds(0))
		timer.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			inputAction(self)
		}
		timer.activate()
	}

	public func resume() {
		if state == .suspended {
			timer.resume()
			state = .activated
		}
	}
	
	public func suspend() {
		if state == .activated {
			timer.suspend()
			state = .suspended
		}
	}
	
	public func cancel() {
		if state != .canceled {
			timer.cancel()
			state = .canceled
		}
	}
	
	public func rescheduleInterval(_ newInterval:Double) {
		if state != .canceled {
			
		}
	}
}


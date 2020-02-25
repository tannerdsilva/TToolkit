import Foundation
import Dispatch

public class TTimer {
	private let queue:DispatchQueue
	private let timer:DispatchSourceTimer
	
//	public var isCanceled:Bool {
//		get {
//			return timer.isCanceled
//		}
//	}
	
	public init(label:String, seconds:DispatchTimeInterval, _ inputAction:@escaping(TTimer) -> Void) {
		queue = DispatchQueue(label:label)
		timer = DispatchSource.makeTimerSource(queue:queue)
		timer.schedule(deadline:.now(), repeating:seconds, leeway:.seconds(0))
		timer.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			inputAction(self)
		}
		timer.activate()
	}
	
	public init(priority:Priority, seconds:DispatchTimeInterval, _ inputAction:@escaping(TTimer) -> Void) {
		queue = DispatchQueue.global(qos:priority.asDispatchQoS())
		timer = DispatchSource.makeTimerSource(queue:queue)
		timer.schedule(deadline:.now(), repeating:seconds, leeway:.seconds(0))
		timer.setEventHandler { [weak self] in
			guard let self = self else {
				return
			}
			inputAction(self)
		}
		timer.activate()
	}
	
	public func activate() {
		timer.activate()
	}
		
	public func resume() {
		timer.resume()
	}
	
	public func suspend() {
		timer.suspend()
	}
}


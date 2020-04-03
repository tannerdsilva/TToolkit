import Foundation

/*
	The priority enum allows you to easily access relevant asynchronous computing threads based on the required priority.
*/

public enum Priority:UInt8 {
	case highest
	case high
	case `default`
	case low
	case lowest
	
	public var globalConcurrentQueue:DispatchQueue {
		return DispatchQueue.global(qos:asDispatchQoS())
	}
	
	public func asDispatchQoS() -> DispatchQoS.QoSClass {
		switch self {
			case .highest:
				return .userInteractive
			case .high:
				return .userInitiated
			case .`default`:
				return .`default`
			case .low:
				return .utility
			case .lowest:
				return .background
		}
	}
	
	public func asDispatchQoS(relative value:Int) -> DispatchQoS {
		let qosClass:DispatchQoS.QoSClass = self.asDispatchQoS()
		return DispatchQoS(qosClass:qosClass, relativePriority:value)
	}

	
	public func asDispatchQoS() -> DispatchQoS {
		switch self {
			case .highest:
				return .userInteractive
			case .high:
				return .userInitiated
			case .`default`:
				return .`default`
			case .low:
				return .utility
			case .lowest:
				return .background
		}
	}
	
	public func asProcessQualityOfService() -> QualityOfService {
		switch self {
			case .highest:
				return .userInteractive
			case .high:
				return .userInitiated
			case .`default`:
				return .`default`
			case .low:
				return .utility
			case .lowest:
				return .background
		}
	}
}

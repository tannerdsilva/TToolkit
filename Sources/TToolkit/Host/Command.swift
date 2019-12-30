import Foundation

public protocol Command {
	func stringRepresentation() -> String
}

extension String:Command {
	public func stringRepresentation() -> String {
		return self
	}
}

public struct CommandResult {
	public let exitCode:Int
	public let stdout:String
	public let stderr:String
}
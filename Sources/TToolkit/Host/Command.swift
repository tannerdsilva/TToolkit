import Foundation

//MARK: Shell Protocol
public protocol Shell {
	associatedtype CommandType:Command
	static var path:URL { get }
	static func buildCommand(_:String) -> CommandType
}

//MARK: Shell Implementations
public struct Bash:Shell {
	public typealias CommandType = BasicCommand
	public static let path = URL(fileURLWithPath:"/bin/bash")
	public static func buildCommand(_ thisCommand:String) -> CommandType {
		return BasicCommand(executable:Self.path, arguments:["-c", Self.terminate(thisCommand)])
	}
	
	fileprivate static func terminate(_ inlineCommand:String) -> String {
		return inlineCommand.replacingOccurrences(of:"'", with:"\'")
	}
}

//todo:ZSH?

//MARK: Command Protocol
public protocol Command {
	var executable:URL { get }
	var arguments:[String] { get }
}

public protocol CommandResult {
	associatedtype CommandType:Command
	
	var command:CommandType { get }
	
	var exitCode:Int { get }
	var stdout:String { get }
	var stderr:String { get }
}

public struct BasicCommand:Command {
	public let executable:URL
	public let arguments:[String]
	
	public init(executable:URL, arguments:[String]) {
		self.executable = executable
		self.arguments = arguments
	}
	
	public init<T>(shell:T.Type, command:String) where T:Shell, T.CommandType == BasicCommand {
		self = shell.buildCommand(command)
	}
}

//MARK: Context Protocol
public protocol Context {
	var workingDirectory:URL { get set }
	var currentUser:String { get }
	var environmentVars:[String:String] { get }
	func run<T, U>(_:T) throws -> U where T:Command, U:CommandResult, U.CommandType == T
}



private struct LocalContect {
	var path = CommandLine.safeArguments.first ?? ""
	var arguments = CommandLine.safeArguments.dropFirst()
	var currentDirectory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
}

//MARK: Host Protocol

public struct Host {
	static var local:Context {
		get {
			return Local(context:CustomContext(main))
		}
	}
	
	 static var current:Shell {
		get {
			return Local(context:main)
		}
	}
}
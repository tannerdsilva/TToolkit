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

public struct CommandResult {
	var exitCode:Int
	var stdout:[String]
	var stderr:[String]
    
    public init(exitCode:Int, stdout:[String], stderr:[String]) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
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
	var username:String { get }
	var hostname:String { get }
    var environment:[String:String] { get }
}

extension Context {
    public func run<T>(_ thisCommand: T) throws -> CommandResult where T:Command {
        let process = try LoggedProcess(thisCommand, workingDirectory:workingDirectory)
        process.runGroup.wait()
        let result = try process.exportResult()
        return result
    }
}

public struct HostContext:Context {
    public var workingDirectory:URL
    public var username:String
    public var hostname:String
    public var environment:[String:String]
    
    init<T>(_ someContext:T) where T:Context {
        workingDirectory = someContext.workingDirectory
        username = someContext.username
        hostname = someContext.hostname
        environment = someContext.environment
    }
}

private struct LocalContext:Context {
    public typealias ShellType = Bash
    
    public var workingDirectory: URL
	public let environment:[String:String]
	public let username:String
	public let hostname:String
	
	init() {
		workingDirectory = URL(fileURLWithPath:FileManager.default.currentDirectoryPath)
		let procInfo = ProcessInfo.processInfo
		environment = procInfo.environment
		username = procInfo.userName
		hostname = procInfo.hostName
	}
}

//MARK: Host Protocol
fileprivate let mainContext = LocalContext()

public struct Host {

    var current:Context {
        get {
            return mainContext as Context
        }
    }
    
    var local:HostContext {
        get {
            return HostContext(mainContext)
        }
    }
}

import Foundation

public enum CommandError:Error {
	case temporaryDirectoryNameConflict
}

public enum Priority:UInt8 {
	case highest
	case high
	case `default`
	case low
	case lowest
	
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

//MARK: Shell Protocol
public protocol Shell {
	static var path:URL { get }
    static func executableAndArguments(_:String) -> (executable:URL, arguments:[String])

}

//MARK: Shell Implementations
public struct Bash:Shell {
	public static let path = URL(fileURLWithPath:"/bin/bash")
    public static func executableAndArguments(_ thisCommand:String) -> (executable:URL, arguments:[String]) {
        return (executable:Self.path, arguments:["-c", Self.terminate(thisCommand)])
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
    var environment:[String:String] { get }
}

public struct CommandResult {
	public let exitCode:Int
	public let stdout:[Data]
	public let stderr:[Data]
    
    public init(exitCode:Int, stdout:[Data], stderr:[Data]) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct BasicCommand:Command {
	public let executable:URL
	public let arguments:[String]
    public let environment: [String : String]
	
    public init(executable:URL, arguments:[String], environment:[String:String]) {
		self.executable = executable
		self.arguments = arguments
        self.environment = environment
	}
}

//MARK: Context Protocol
public protocol Context {
    associatedtype ShellType:Shell
	var workingDirectory:URL { get set }
	var username:String { get }
	var hostname:String { get }
    var environment:[String:String] { get }
}

extension Context {
    public func runSync(_ thisCommand:String) throws -> CommandResult {
        let commandToRun = build(thisCommand)
        let process = try InteractiveProcess(command:commandToRun, workingDirectory:workingDirectory, run:false)
        try process.run()
        let exitCode = process.waitForExitCode()
        let stderrData = process.exportStdErr()
        let stdoutData = process.exportStdOut()
        let result = CommandResult(exitCode: exitCode, stdout: stdoutData.lineSlice(removeBOM: false), stderr: stderrData.lineSlice(removeBOM: false))
   		return result
    }
	    
    public func build(_ commandString: String) -> BasicCommand {
        let shellBuild = ShellType.executableAndArguments(commandString)
        let buildCommand = BasicCommand(executable: shellBuild.executable, arguments: shellBuild.arguments, environment: environment)
        return buildCommand
    }
}

public struct HostContext:Context {
    public typealias ShellType = Bash
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

    public static var current:HostContext {
        get {
            return HostContext(mainContext)
        }
    }
    
    public static var local:HostContext {
        get {
            return HostContext(mainContext)
        }
    }
}

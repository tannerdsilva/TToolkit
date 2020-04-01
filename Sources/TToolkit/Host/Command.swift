import Foundation

public enum CommandError:Error {
	case temporaryDirectoryNameConflict
}


//MARK: Shell Protocol
/* SHELL PROTOCOL 

	Shell protocol is used to help wrap user command strings into an executable path with arguments.
	path:URL - This is the executable path to the shell
	executableAndArguments(String) - This is a function that wraps the users command string into a executable+argument set that is ready to execute.
*/
public protocol Shell {
	static var path:URL { get }
    static func executableAndArguments(_:String) -> (executable:URL, arguments:[String])
}

//MARK: Shell Implementations
/* SHELL SUPPORT
	
	Right now Bash is the only shell that is being supported. 
*/
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
	public var succeeded:Bool {
		get {
			if exitCode == 0 {
				return true
			} else {
				return false
			}
		}
	}
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
        
        var errorLines = [Data]()
        var outputLines = [Data]()
        
        let process = try InteractiveProcess(command:commandToRun, run:false)
        process.proc.environment = environment
        process.stdoutHandler = { someData in
        	outputLines.append(someData)
        	print(Colors.magenta("."), terminator:"\n")
        }
        process.stderrHandler = { someData in
        	errorLines.append(someData)
        	print(Colors.cyan("."), terminator:"\n")
        }
        try process.run()
        let exitCode = process.waitForExitCode()
        let result = CommandResult(exitCode: exitCode, stdout:outputLines, stderr:errorLines)
   		return result
    }
    
    public func prepareAsync(priority:Priority = Priority.`default`, _ thisCommand:String) throws -> InteractiveProcess {
    	return try prepareAsync(priority:priority, callback:nil, thisCommand)
    }
    
    public func prepareAsync(priority:Priority = Priority.`default`, callback:DispatchQueue?, _ thisCommand:String) throws -> InteractiveProcess {
    	let commandToRun = build(thisCommand)
    	let processToReturn = try InteractiveProcess(command:commandToRun, priority:priority, run:false, callback:callback)
    	processToReturn.proc.environment = environment
    	return processToReturn
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

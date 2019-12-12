import Foundation
import SwiftShell
import Shout

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

public protocol Shell {
	var workingDirectory:URL { get set }
	var currentUser:String { get }
	
	func run(_ command:Command) throws -> CommandResult
	func readFile(_ fileURL:URL) throws -> Data
	func write(data:Data, to fileURL:URL) throws
}

fileprivate class Local:Shell {
	private var shellContext:CustomContext	
	public var workingDirectory:URL {
		get { 
			return URL(fileURLWithPath:shellContext.currentdirectory)
		}
		set {
			shellContext.currentdirectory = newValue.path
		}
	}
	public var currentUser:String {
		get {
			return shellContext.run(bash:"whoami").stdout
		}
	}
	init() {
		shellContext = CustomContext(main)
	}
	public func run(_ command:Command) throws -> CommandResult {
		let shellResult = shellContext.run(bash:command.stringRepresentation())
		
		let ec = shellResult.exitcode
		let stdout = shellResult.stdout
		let stderr = shellResult.stderror
		
		return CommandResult(exitCode:ec, stdout:stdout, stderr:stderr)
	}
	public func readFile(_ fileURL:URL) throws -> Data {
		return try Data(contentsOf:fileURL)
	}
	public func write(data:Data, to fileURL:URL) throws {
		try data.write(to:fileURL)
	}
}

enum ShellAuthentication {
	case password(String)
	case sshIdentity(URL)
}

//fileprivate class Remote:Shell {
//	private var sshConnection:SSH
//	private var port:Int32
//	private var address:String
//	
//	
//	init(address:String, port:UInt32 = 22, username:String, authentication:ShellAuthentication) throws {
//		
//	}
//}

//fileprivate class Remote:Shell {
//    var workingDirectory: URL
//    
//    var currentUser: String
//    
//    func run(_ command: Command) throws -> CommandResult {
//        
//    }
//    
//	
//	private var sshSession:SSH
//	
//	
//	init(address:Address, localIdentity:URL, port:Int32, username:String) throws {
//	
//	}
//	
//	init(address:Address, port:Int32, username:String, password:String) throws {
//	
//	}
//}


public struct Host {
	public static func local() -> Shell {
		return Local()
	}	
}

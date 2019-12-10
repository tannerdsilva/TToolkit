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
	var exitCode:Int
	var stdout:String
	var stderr:String
}

protocol Shell {
	var workingDirectory:URL { get set }
	var currentUser:String { get }
	
	func run(_ command:Command) throws -> CommandResult
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
}

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


struct Host {
	static func local() -> Shell {
		return Local()
	}	
}

import Foundation
import Shout
import SwiftShell


//internal class Local<T>:Shell where T: CommandRunning, T: Context {
//	private var shellContext:T	
//	public var workingDirectory:URL {
//		get { 
//			return URL(fileURLWithPath:shellContext.currentdirectory)
//		}
//		set {
//			shellContext.currentdirectory = newValue.path
//		}
//	}
//	public var currentUser:String {
//		get {
//			return shellContext.run(bash:"whoami").stdout
//		}
//	}
//	public var environmentVars:[String:String] {
//		get {
//			return shellContext.env
//		}
//	}
//	public init(context:T) {
//		shellContext = context
//	}
//	public func run(_ command:Command) throws -> CommandResult {
//		let shellResult = shellContext.run(bash:command.stringRepresentation())
//		
//		let ec = shellResult.exitcode
//		let stdout = shellResult.stdout
//		let stderr = shellResult.stderror
//		
//		return CommandResult(exitCode:ec, stdout:stdout, stderr:stderr)
//	}
//	public func read(file fileURL:URL) throws -> Data {
//		return try Data(contentsOf:fileURL)
//	}
//	public func write(data:Data, to fileURL:URL) throws {
//		try data.write(to:fileURL)
//	}
//}
//
//fileprivate let defaultPrivateKeyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory:true).appendingPathComponent("id_rsa", isDirectory:false)
//

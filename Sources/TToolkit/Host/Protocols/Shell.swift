import Foundation
import Shout
import SwiftShell

public protocol Shell {
	var workingDirectory:URL { get set }
	var currentUser:String { get }
	var environmentVars:[String:String] { get }
	func run(_:Command) throws -> CommandResult
	func read(file:URL) throws -> Data
	func write(data:Data, to fileURL:URL) throws
}

internal class Local<T>:Shell where T: CommandRunning, T: Context {
	private var shellContext:T	
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
	public var environmentVars:[String:String] {
		get {
			return shellContext.env
		}
	}
	public init(context:T) {
		shellContext = context
	}
	public func run(_ command:Command) throws -> CommandResult {
		let shellResult = shellContext.run(bash:command.stringRepresentation())
		
		let ec = shellResult.exitcode
		let stdout = shellResult.stdout
		let stderr = shellResult.stderror
		
		return CommandResult(exitCode:ec, stdout:stdout, stderr:stderr)
	}
	public func read(file fileURL:URL) throws -> Data {
		return try Data(contentsOf:fileURL)
	}
	public func write(data:Data, to fileURL:URL) throws {
		try data.write(to:fileURL)
	}
}

fileprivate let defaultPrivateKeyURL = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".ssh", isDirectory:true).appendingPathComponent("id_rsa", isDirectory:false)

//internal class Remote:Shell {
//	private var sshConnection:SSH
//	private var port:Int32
//	private var address:String
//	
//	private var _wd:URL = URL(fileURLWithPath:"/")
//	public var workingDirectory:URL {
//		get {
//			return URL(fileURLWithPath:self.run("pwd").stdout)
//		}
//		set {
//			_wd = newValue
//			self.run("cd '\(_wd.path)'")
//		}
//	}
//	
//	public var currrentUser:String { 
//		get {
//			return self.run("whoami").stdout
//		}
//	}
//	
//	init(address:String, port:Int32 = 22, username:String, authentication:ShellAuthentication = .privateKey(defaultPrivateKeyURL)) throws {
//		self.address = address
//		self.port = port
//		
//		//connect to the server at the given port and address
//		sshConnection = try SSH(host:address, port:port)
//		print(Colors.Green("[SSH] Connected to \(address):\(port)"))
//		
//		switch authentication {
//			case let .password(inputPassword):
//				try sshConnection.authenticate(username:username, password:inputPassword)
//			case let .privateKey(privateKeyURL):
//				try sshConnection.authenticate(username:username, privateKey:privateKeyURL.path)				
//		}
//		
//		print(Colors.Green("[SSH][\(address)] Authenticated as \(username)"))
//	}
//}

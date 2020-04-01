import Foundation
import CoreFoundation

fileprivate func _WSTATUS(_ status:Int32) -> Int32 {
	return status & 0x7f
}

fileprivate func WIFEXITED(_ status:Int32) -> Bool {
	return _WSTATUS(status) == 0
}
fileprivate func WIFSIGNALED(_ status:Int32) -> Bool {
	return (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7f)
}


fileprivate let concurrentExitQueue:DispatchQueue = DispatchQueue(label:"com.tannersilva.global.process-executing.exit-wait", qos:Priority.highest.asDispatchQoS(), attributes:[.concurrent])

/*
	ExecutingProcess is my interpretation of the Process object from the Swift Standard Library.
	This class looks to cut out most of legacy code from Process to create a much more streamlined data structure.
	
	ExecutingProcess is distinct from the traditional Process object in that ExecutingProcess does not conform to NSObject. This eliminates significant overhead when executing and handling many ExecutingProcesses simulaneously.
	Furthermore, the standard 
*/
internal class ExecutingProcess {
	//these are the types of errors that this class can throw
	public enum ProcessError:Error { 
		case unableToExecute
		case processAlreadyRunning
		case unableToCreatePipes
	}

	typealias TerminationHandler = (ExecutingProcess) -> Void
	enum TerminationReason:UInt8 {
		case exited
		case uncaughtSignal
	}

	let priority:Priority
			
	var executable:URL
	var arguments:[String]?
	var environment:[String:String]?
	
	var processIdentifier:Int32?
	var isRunning:Bool
	
	var stdin:ProcessPipes? = nil
	var stdout:ProcessPipes? = nil
	var stderr:ProcessPipes? = nil
	
	var terminationReason:TerminationReason? = nil
	var exitCode:Int32? = nil
	var terminationHandler:TerminationHandler? = nil
	
	//returns the launchURL as a string path if it is readable and executable
	//otherwise, returns nil
	fileprivate class func isLaunchURLExecutable(_ launchURL:URL) -> String? {
		let launchString = launchURL.path
		
		let fsRep = FileManager.default.fileSystemRepresentation(withPath:launchString)
		var statInfo = stat()
		guard stat(fsRep, &statInfo) == 0 else {
			return nil
		}
		
		let isRegFile:Bool = statInfo.st_mode & S_IFMT == S_IFREG
		guard isRegFile == true else {
			return nil
		}
		
		guard access(fsRep, X_OK) == 0 else {
			return nil
		}
		return launchString
	}
	
	init(priority:Priority, execute:URL, arguments:[String]?, environment:[String:String]?) {
		self.priority = priority
		self.executable = execute
		self.arguments = arguments
		self.environment = environment
		self.arguments = arguments
		self.processIdentifier = nil
		self.isRunning = false
	}
	
	func _run() throws {
		guard isRunning == false else {
			throw ProcessError.processAlreadyRunning
		}

		guard let launchPath = Self.isLaunchURLExecutable(executable) else {
			throw ProcessError.unableToExecute
		}
		var argBuild = [launchPath]
		if let args = self.arguments {
			argBuild.append(contentsOf:args)
		}

		//convert the arguments into C compatible variables
		let argC:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?> = argBuild.withUnsafeBufferPointer {
			let arr:UnsafeBufferPointer<String> = $0
			let buff = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity:arr.count + 1)
			buff.initialize(from:arr.map { $0.withCString(strdup) }, count:arr.count)
			buff[arr.count] = nil
			return buff
		}
		defer {
			for arg in argC ..< argC + argBuild.count {
				free(UnsafeMutableRawPointer(arg.pointee))
			}
			argC.deallocate()
		}

		//convert the environment variables to C compatible variables
		var env:[String:String]
		if let e = environment {
			env = e
		} else { 
			env = [String:String]()
		}
		let envCount = env.count
		let envC = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity:1 + envCount)
		envC.initialize(from:env.map { strdup("\($0)=\($1)") }, count: envCount)
		envC[envCount] = nil
		defer {
			for pair in envC ..< envC + envCount {
				free(UnsafeMutableRawPointer(pair.pointee))
			}
			envC.deallocate()
		}

		//bind the file handle descriptors to the pipes that we are associating with this process 
		var fHandles = [Int32:Int32]()
		if let hasStdin = stdin {
			fHandles[STDIN_FILENO] = hasStdin.reading.fileDescriptor
		}
		if let hasStdout = stdout {
			fHandles[STDOUT_FILENO] = hasStdout.writing.fileDescriptor
		}
		if let hasStderr = stderr {
			fHandles[STDERR_FILENO] = hasStderr.writing.fileDescriptor
		}


		//there are some weird differences between Linux and macOS in terms of their preference with optionals
		//here, the specific allocators and deallocators for each platform are specified
#if os(macOS)
		var fileActions:UnsafeMutablePointer<posix_spawn_file_actions_t?> = UnsafeMutablePointer<posix_spawn_file_actions_t?>.allocate(capacity:1)
#else
		var fileActions:UnsafeMutablePointer<posix_spawn_file_actions_t> = UnsafeMutablePointer<posix_spawn_file_actions_t>.allocate(capacity:1)
#endif
		posix_spawn_file_actions_init(fileActions)
		defer {
			posix_spawn_file_actions_destroy(fileActions)
			fileActions.deallocate()
		}

		for (destination, source) in fHandles {
			let result = posix_spawn_file_actions_adddup2(fileActions, source, destination)
		}
		
		var lpid = pid_t()
		let launchGroup = DispatchGroup()
		let timeAlignGroup = DispatchGroup()
		timeAlignGroup.enter()
		
		priority.globalConcurrentQueue.async { [weak self] in
			let flightTime = Date()
			timeAlignGroup.leave()
			launchGroup.wait()
			//wait for the process to exit and capture its exit code
			var waitResult:Int32 = 0
			var ec:Int32 = 0
			repeat {
				let launchTime = Date()
				print(Colors.Yellow("\(launchTime.timeIntervalSince(flightTime))"))
				waitResult = waitpid(lpid, &ec, 0)
			} while waitResult == -1 && errno == EINTR || WIFEXITED(ec) == false
			guard let self = self else {
				return
			}
			//close file handles if they exist
			self.stdin?.close()
			self.stdout?.close()
			self.stderr?.close()

			self.isRunning = false
			if WIFSIGNALED(ec) {
				self.terminationReason = TerminationReason.uncaughtSignal
			} else {
				self.terminationReason = TerminationReason.exited
			}
			self.exitCode = ec
			
			if let th = self.terminationHandler {
				th(self)
			}
		}
		launchGroup.enter()
		timeAlignGroup.wait()
		
		//launch the process
		guard posix_spawn(&lpid, launchPath, fileActions, nil, argC, envC) == 0 else {
			throw ProcessError.unableToExecute
		}
		launchGroup.leave()
		print(Colors.green("-> launched"))
		let launchDate = Date()
		
	
		processIdentifier = lpid
		isRunning = true
	}
	
	func _suspend() -> Bool? {
		guard let pid = processIdentifier else {
			return nil
		}
		if kill(pid, SIGSTOP) == 0 {
			return true
		} else {
			return false
		}
	}
	
	func _terminate() {
		guard let pid = processIdentifier else {
			return
		}
		kill(pid, SIGTERM)
	}
	
	func _forceKill() {
		guard let pid = processIdentifier else {
			return
		}
		kill(pid, SIGKILL)
	}
	
	func _resume() -> Bool? {
		guard let pid = processIdentifier else {
			return nil
		}
		if kill(pid, SIGCONT) == 0 {
			return true
		} else {
			return false
		}
	}
}
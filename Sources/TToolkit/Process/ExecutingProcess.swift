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

/*
	ExecutingProcess is my interpretation of the Process object from the Swift Standard Library.
	This class looks to cut out most of legacy code from Process to create a much more streamlined data structure.
	
	ExecutingProcess is distinct from the traditional Process object in that ExecutingProcess does not conform to NSObject. This eliminates significant overhead when executing and handling many ExecutingProcesses simulaneously.
	Furthermore, the standard 
*/

fileprivate let exitThreads = DispatchQueue(label:"com.tannersilva.global.process-executing.exit-wait", qos:Priority.highest.asDispatchQoS(), attributes:[.concurrent])
fileprivate let epLocks = DispatchQueue(label:"com.tannersilva.global.process-executing.sync", attributes:[.concurrent])
fileprivate let serialRun = DispatchQueue(label:"com.tannersilva.global.process-executing.run-serial")

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
	
	let internalCallback:DispatchQueue
	let internalSync:DispatchQueue
	let exitQueue:DispatchQueue
	
	var executable:URL
	var arguments:[String]?
	var environment:[String:String]?
	
	var processIdentifier:Int32?
	var isRunning:Bool
	
	var stdin:ProcessPipes? = nil
	var stdout:ProcessPipes? = nil
	var stderr:ProcessPipes? = nil
	
	private var _callbackQueue:DispatchQueue
	var terminationQueue:DispatchQueue {
		get {
			internalSync.sync {
				return _callbackQueue
			}
		}
		set {
			internalSync.sync {
				_callbackQueue = newValue
				internalCallback.setTarget(queue:_callbackQueue)
			}
		}
	}
	var terminationReason:TerminationReason? = nil
	var exitCode:Int32? = nil
	
	private var _terminationHandler:TerminationHandler? = nil
	var terminationHandler:TerminationHandler? {
		get {
			return internalSync.sync {
				return _terminationHandler
			}
		}
		set {
			internalSync.sync {
				_terminationHandler = newValue
			}
		}
	}
	
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
	
	init(execute:URL, arguments:[String]?, environment:[String:String]?, callback:DispatchQueue, _ terminationHandler:TerminationHandler? = nil) {
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.executing-process.sync", target:epLocks)
		let icb = DispatchQueue(label:"com.tannersilva.instance.executing-process.term-callback", target:callback)
		self.internalCallback = icb
		self._callbackQueue = callback
		
		let eq = DispatchQueue(label:"com.tannersilva.instance.executing.exit-wait", qos:Priority.highest.asDispatchQoS(), target:exitThreads)
		self.exitQueue = eq
		
		self.executable = execute
		self.arguments = arguments
		self.environment = environment
		self.arguments = arguments
		self.processIdentifier = nil
		self.isRunning = false
		self._terminationHandler = terminationHandler
	}
	
	func run() throws {
		let syncQueue = internalSync
		return try syncQueue.sync {
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

			//launch the process
			var lpid = pid_t()
			
			let queueGroup = DispatchGroup()
			let runGroup = DispatchGroup()
			
			runGroup.enter()
			queueGroup.enter()
			
			let startDate = Date()
			
			let exitWorkItem = DispatchWorkItem(qos:Priority.highest.asDispatchQoS(), flags:[.enforceQoS]) { [weak self] in
				var launchDate = Date()
				
				print(Colors.Yellow("launched exit thread in \(launchDate.timeIntervalSince(startDate)) seconds"))
				
				queueGroup.leave()
				runGroup.wait()
				var waitResult:Int32 = 0
				var ec:Int32 = 0
				repeat {
					waitResult = waitpid(lpid, &ec, 0)
				} while waitResult == -1 && errno == EINTR || WIFEXITED(ec) == false || lpid == 0
				launchDate = Date()
				guard let self = self else {
					return
				}
				let completionWorkItem = DispatchWorkItem(qos:Priority.highest.asDispatchQoS(), flags:[.enforceQoS]) { [weak self] in
					guard let self = self else {
						return
					}
					let runDate = Date()
					print(Colors.cyan("started running exit handler in \(launchDate.timeIntervalSince(runDate)) seconds"))
					self.isRunning = false
					if WIFSIGNALED(ec) {
						self.terminationReason = TerminationReason.uncaughtSignal
					} else {
						self.terminationReason = TerminationReason.exited
					}
					self.exitCode = ec
					self.stdin?.close()
					self.stdout?.close()
					self.stderr?.close()
				}
				if let hasTermHandle = self.terminationHandler {
					completionWorkItem.notify(qos:Priority.highest.asDispatchQoS(), flags:[.enforceQoS], queue:self.internalCallback) { [weak self] in
						guard let self = self else {
							return
						}
						let notifyDate = Date()
						print(Colors.magenta("exit notified \(notifyDate.timeIntervalSince(launchDate)) seconds after true exitT"))
						hasTermHandle(self)
					}
				}
				self.internalSync.async(execute:completionWorkItem)
			}
			exitQueue.async(execute:exitWorkItem)
			queueGroup.wait()
			try serialRun.sync {
				guard posix_spawn(&lpid, launchPath, fileActions, nil, argC, envC) == 0 else {
					throw ProcessError.unableToExecute
				}
			}
			runGroup.leave()
			
			processIdentifier = lpid
			isRunning = true
		}
	}
	
	func suspend() -> Bool? {
		return internalSync.sync {
			guard let pid = processIdentifier else {
				return nil
			}
			if kill(pid, SIGSTOP) == 0 {
				return true
			} else {
				return false
			}
		}
	}
	
	func terminate() {
		internalSync.sync {
			guard let pid = processIdentifier else {
				return
			}
			kill(pid, SIGTERM)
		}
	}
	
	func forceKill() {
		internalSync.sync {
			guard let pid = processIdentifier else {
				return
			}
			kill(pid, SIGKILL)
		}
	}
	
	func resume() -> Bool? {
		return internalSync.sync {
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
}
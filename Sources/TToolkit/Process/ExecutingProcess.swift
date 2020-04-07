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
	The ExitWatcher is a class that guarantees its availability to monitor an external process for exits.
	ExitWatcher is able to provide this functionality by launching an external thread on initialization, and sleeping the thread until a process is ready to be monitored.
	ExitWatcher is not reusable. After a process has exited and the handler is called, exithandler should be discarded.
*/
internal class ExitWatcher {
	typealias ExitHandler = (Int32, Date) -> Void
	enum ExitWatcherError:Error {
		case unableToLaunchThread
		case engagementError
	}
	
	private enum ExitWatcherState {
		case initialized
		case engaged
		case failed
		case exited
	}
	
	private let backgroundQueue:DispatchQueue
	private let internalSync:DispatchQueue
	
	private let flightGroup:DispatchGroup			//this group represents the external thread that is "in flight" 
	private let engageWaitGroup:DispatchGroup		//this is the group that instructs the external thread when it should be waiting to engage
	private let engageResponseGroup:DispatchGroup	//this is the group that the external thread uses to signal its engagement response
	private let didExitGroup:DispatchGroup			//this is the group that the external thread uses to signal that the external process has exited
	
	private var pid:pid_t
	private var state:ExitWatcherState
	
	private var _handler:ExitHandler? = nil
	
	init() throws {
		let bgThread = DispatchQueue(label:"com.tannersilva.instance.process-executing.exit-watch", qos:Priority.highest.asDispatchQoS(relative:10))
		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-executing.exit-watch.sync")
		self.backgroundQueue = bgThread
		self.internalSync = syncQueue
		
		let flight = DispatchGroup()
		let engageWait = DispatchGroup()
		let didExit = DispatchGroup()
		let engageResponse = DispatchGroup()
		engageWait.enter()
		
		self.flightGroup = flight
		self.engageWaitGroup = engageWait
		self.engageResponseGroup = engageResponse
		self.didExitGroup = didExit
		
		var internalFail:Bool = false
		
		self.pid = pid_t()
		self.state = ExitWatcherState.initialized
		
		let threadLaunchedGroup = DispatchGroup()
		threadLaunchedGroup.enter()
		let launchtime = Date()
		bgThread.async { [weak self] in
			print(Colors.Yellow("Exit watcher launched in \(launchtime.timeIntervalSinceNow) seconds"))
			//state 1: guarantee initialization of this async work
			flight.enter()
			defer {
				flight.leave()
			}
			guard let self = self else {
				syncQueue.sync {
					internalFail = true
				}
				threadLaunchedGroup.leave()
				return
			}
			didExit.enter()
			engageResponse.enter()
			threadLaunchedGroup.leave()
			
			//stage 2: wait for a pid to be assigned
			engageWait.wait()
			
			//stage 3: validate the state of self and start watching the pid if configured to do so (else, return from this thread)
			var pidCapture:Int32? = nil
			var stateCapture:ExitWatcherState? = nil
			var handleCapture:ExitHandler? = nil
			syncQueue.sync {
				pidCapture = self.pid
				stateCapture = self.state
				handleCapture = self._handler
			}
			guard var pidWatch = pidCapture, var validatedState = stateCapture, let validHandler = handleCapture, pidWatch != 0 && validatedState == .initialized else {
				syncQueue.sync {
					self.state = .failed
				}
				didExit.leave()
				engageResponse.leave()
				return
			}
			syncQueue.sync {
				self.state = .engaged
			}
			engageResponse.leave()
			var waitResult:Int32 = 0
			var exitCode:Int32 = 0
			repeat {
				waitResult = waitpid(pidWatch, &exitCode, 0)
			} while waitResult == -1 && errno == EINTR || WIFEXITED(exitCode) == false
			let exitTime = Date()
			validHandler(exitCode, exitTime)
			syncQueue.sync {
				self.state = .exited
			}
			didExit.leave()
		}
		threadLaunchedGroup.wait()
		try syncQueue.sync {
			guard internalFail == false else {
				engageWait.leave()
				throw ExitWatcherError.unableToLaunchThread
			}
		}
	}
	
	func engage(pid:pid_t, _ handler:@escaping(ExitHandler)) throws {
		try internalSync.sync {
			guard self.state == .initialized else {
				throw ExitWatcherError.engagementError
			}
			self.pid = pid
			self._handler = handler
		}
		engageWaitGroup.leave()
		engageResponseGroup.wait()
		try internalSync.sync {
			guard self.state == .engaged else {
				throw ExitWatcherError.engagementError
			}
		}
	}
	
	deinit {
		var capturedState = internalSync.sync {
			return self.state
		}
		switch capturedState {
			case .initialized:
				internalSync.sync {
					self.state = .failed
				}
				engageWaitGroup.leave()
				engageResponseGroup.wait()
				flightGroup.wait()
			case .engaged:
				didExitGroup.wait()
				flightGroup.wait()
			default:
				flightGroup.wait()
		}
		print(Colors.dim("Successfully deinitted ExitWatcher"))
	}
}

/*
	ExecutingProcess is my interpretation of the Process object from the Swift Standard Library.
	This class looks to cut out most of legacy code from Process to create a much more streamlined data structure.
	
	ExecutingProcess is distinct from the traditional Process object in that ExecutingProcess does not conform to NSObject. This eliminates significant overhead when executing and handling many ExecutingProcesses simulaneously.
	Furthermore, the standard 
*/
internal class ExecutingProcess {
	public enum ExecutingProcessError:Error {
		case processAlreadyRunning
		case unableToExecute
        case unableToCreatePipes
	}
	
	fileprivate static let globalLockQueue = DispatchQueue(label:"com.tannersilva.global.process.execute.sync", attributes:[.concurrent])
	fileprivate static let globalSerialRun = DispatchQueue(label:"com.tannersilva.global.process.execute.serial-launch.sync", target:globalLockQueue)

	/*
		These variables define what is going to be executed, and how it is going to be executed.
		- Executable File Path
		- Arguments
		- Environment Variables
	*/
	private let internalSync:DispatchQueue
	private var _executable:URL
	private var _arguments:[String]? = nil
	private var _environment:[String:String]? = nil
	var executable:URL {
		get {
			return internalSync.sync {
				return _executable
			}
		}
		set {
			internalSync.sync {
				_executable = newValue
			}
		}
	}
	var arguments:[String]? {
		get {
			return internalSync.sync {
				return _arguments
			}
		}
		set {
			internalSync.sync {
				_arguments = newValue
			}
		}
	}
	var environment:[String:String]? {
		get {
			return internalSync.sync {
				return _environment
			}
		}
		set {
			internalSync.sync {
				_environment = newValue
			}
		}
	}
	
	/*
		These variables are related to the execution state of the process.
		- Process Identifier
		- Exit code
		- Is running?
	*/
	private var _launchTime:Date? = nil
	private var _exitTime:Date? = nil
	private var _exitWatcher:ExitWatcher
	private var _exitCode:Int32? = nil
	private var _processId:Int32? = nil
	var processIdentifier:Int32? {
		get {
			return internalSync.sync {
				return _processId
			}
		}
	}
	
	var exitCode:Int32? {
		get {
			return internalSync.sync {
				return _exitCode
			}
		}
	}
	private var _isRunning:Bool {
		get {
			if _processId == nil {
				return false
			} else if _processId != nil && _exitCode != nil {
				return false
			}
			return true
		}
	}
	var isRunning:Bool {
		get {
			return internalSync.sync {
				return _isRunning
			}
		}
	}
	
	/*
		These variables are related to the I/O of the process in question
	*/
	private var _stderr:ProcessPipes? = nil
	private var _stdout:ProcessPipes? = nil
	private var _stdin:ProcessPipes? = nil
	
	var stdin:ProcessPipes? { 
		get {
			return internalSync.sync {
				return _stdin
			}
		}
		set {
			internalSync.sync {
				_stdin = newValue
			}
		}
	}
	var stdout:ProcessPipes? { 
		get {
			return internalSync.sync {
				return _stdout
			}
		}
		set {
			internalSync.sync {
				_stdout = newValue
			}
		}
	}
	var stderr:ProcessPipes? { 
		get {
			return internalSync.sync {
				return _stderr
			}
		}
		set {
			internalSync.sync {
				_stderr = newValue
			}
		}
	}
	
	//which queue will the termination handler be called?
	private var _terminationHandler:DispatchWorkItem? = nil
	private var _callbackQueue:DispatchQueue
	private var _callbackGroup:DispatchGroup? = nil
	
	var callbackGroup:DispatchGroup? {
		get {
			internalSync.sync {
				return _callbackGroup
			}
		}
		set {
			internalSync.sync {
				_callbackGroup = newValue
			}
		}
	}
	var callbackQueue:DispatchQueue {
		get {
			internalSync.sync {
				return _callbackQueue
			}
		}
		set {
			internalSync.sync {
				_callbackQueue = newValue
			}
		}
	}

	var terminationHandler:DispatchWorkItem? {
		get{
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
	
	init(execute:URL, arguments:[String]?, environment:[String:String]?, callback:DispatchQueue) throws {
		self._executable = execute
		self._arguments = arguments
		self._environment = environment
		
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.execute.sync")
		self._callbackQueue = callback
		self._exitWatcher = try ExitWatcher()
	}
	
	func run() throws {
		try internalSync.sync {
			guard _isRunning == false && _exitCode == nil else {
				throw ExecutingProcessError.processAlreadyRunning
			}			
			guard let launchPath = Self.isLaunchURLExecutable(_executable) else {
				throw ExecutingProcessError.unableToExecute
			}
			var argBuild = [launchPath]
			if let hasArguments = _arguments {
				argBuild.append(contentsOf:hasArguments)
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
			
			//convert the environment variables into c compatible variables
			var env:[String:String]
			if let e = _environment {
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

			var fHandles = [Int32:Int32]()
			if let hasStdin = _stdin {
				fHandles[STDIN_FILENO] = hasStdin.reading.fileDescriptor
			}
			if let hasStdout = _stdout {
				fHandles[STDOUT_FILENO] = hasStdout.writing.fileDescriptor
			}
			if let hasStderr = _stderr {
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
            try ExecutingProcess.globalSerialRun.sync {
				guard posix_spawn(&lpid, launchPath, fileActions, nil, argC, envC) == 0 && lpid != 0 else {
					throw ExecutingProcessError.unableToExecute
				}
			}
			
			_launchTime = Date()
			_processId = lpid

			do {
				try _exitWatcher.engage(pid:lpid) { [weak self] exitCode, exitDate in
					guard let self = self else {
						return
					}
					print(Colors.Red("Exit triggered"))
					self.internalSync.sync {
						self._exitCode = exitCode
						self._exitTime = exitDate
						   if let hasTerminationHandler = self._terminationHandler {
							if let hasAsyncGroup = self._callbackGroup {
								self._callbackQueue.async(group:hasAsyncGroup, execute:hasTerminationHandler)
							} else {
								self._callbackQueue.async(execute:hasTerminationHandler)
							}
						}
					}
				}
			} catch let error {
				kill(lpid, SIGKILL)
				throw error
			}
		}
	}
	
	func suspend() -> Bool? {
		return internalSync.sync {
			guard let pid = _processId else {
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
			guard let pid = _processId else {
				return
			}
			kill(pid, SIGTERM)
		}
	}
	
	func forceKill() {
		internalSync.sync {
			guard let pid = _processId else {
				return
			}
			kill(pid, SIGKILL)
		}
	}
	
	func resume() -> Bool? {
		return internalSync.sync {
			guard let pid = _processId else {
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

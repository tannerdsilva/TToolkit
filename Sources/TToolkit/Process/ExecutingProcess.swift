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
//internal class ExitWatcher {
//    let internalSync:DispatchQueue
//    
//	init() throws {
//		let bgThread = DispatchQueue(label:"com.tannersilva.instance.process-executing.exit-watch", qos:Priority.highest.asDispatchQoS(relative:10))
//		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-executing.exit-watch.sync")
//		self.backgroundQueue = bgThread
//		self.internalSync = syncQueue
//		
//		let flight = DispatchGroup()
//		let engageWait = DispatchGroup()
//		let didExit = DispatchGroup()
//		let engageResponse = DispatchGroup()
//		engageWait.enter()
//		
//		self.flightGroup = flight
//		self.engageWaitGroup = engageWait
//		self.engageResponseGroup = engageResponse
//		self.didExitGroup = didExit
//		
//		var internalFail:Bool = false
//		
//		self.pid = pid_t()
//		self.state = ExitWatcherState.initialized
//		
//		let threadLaunchedGroup = DispatchGroup()
//		threadLaunchedGroup.enter()
//		let launchtime = Date()
//		bgThread.async { [weak self] in
//			//state 1: guarantee initialization of this async work
//			flight.enter()
//			defer {
//				flight.leave()
//			}
//			guard let self = self else {
//				syncQueue.sync {
//					internalFail = true
//				}
//				threadLaunchedGroup.leave()
//				return
//			}
//			didExit.enter()
//			engageResponse.enter()
//			threadLaunchedGroup.leave()
//			
//			//stage 2: wait for a pid to be assigned
//			engageWait.wait()
//			
//			//stage 3: validate the state of self and start watching the pid if configured to do so (else, return from this thread)
//			var pidCapture:Int32? = nil
//			var stateCapture:ExitWatcherState? = nil
//			var handleCapture:ExitHandler? = nil
//			syncQueue.sync {
//				pidCapture = self.pid
//				stateCapture = self.state
//				handleCapture = self._handler
//			}
//			guard var pidWatch = pidCapture, var validatedState = stateCapture, let validHandler = handleCapture, pidWatch != 0 && validatedState == .initialized else {
//				syncQueue.sync {
//					self.state = .failed
//				}
//				didExit.leave()
//				engageResponse.leave()
//				return
//			}
//			syncQueue.sync {
//				self.state = .engaged
//			}
//			engageResponse.leave()
//			pmon.exiterEngaged(pidWatch)
//			var waitResult:Int32 = 0
//			var exitCode:Int32 = 0
//			var errNo:Int32 = 0
//			repeat {
//				waitResult = waitpid(pidWatch, &exitCode, 0)
//				errNo = errno
//				if waitResult == -1 && errNo == EINTR || WIFEXITED(exitCode) == false {
//					print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!\nEXIT ERROR RESULT \(waitResult) - \(errNo)\n!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
//				}
//				
//			} while waitResult == -1 && errNo == EINTR || WIFEXITED(exitCode) == false
//			let exitTime = Date()
//			pmon.exiterDisengaged(pidWatch)
//			validHandler(exitCode, exitTime)
//			syncQueue.sync {
//				self.state = .exited
//			}
//			didExit.leave()
//		}
//		threadLaunchedGroup.wait()
//		try syncQueue.sync {
//			guard internalFail == false else {
//				engageWait.leave()
//				throw ExitWatcherError.unableToLaunchThread
//			}
//		}
//	}
//	
//	func engage(pid:pid_t, _ handler:@escaping(ExitHandler)) throws {
//		try internalSync.sync {
//			guard self.state == .initialized else {
//				throw ExitWatcherError.engagementError
//			}
//			self.pid = pid
//			self._handler = handler
//		}
//		engageWaitGroup.leave()
//		engageResponseGroup.wait()
//		try internalSync.sync {
//			guard self.state == .engaged else {
//				throw ExitWatcherError.engagementError
//			}
//		}
//	}
//	
//	deinit {
//		var capturedState = internalSync.sync {
//			return self.state
//		}
//		switch capturedState {
//			case .initialized:
//				internalSync.sync {
//					self.state = .failed
//				}
//				engageWaitGroup.leave()
//				engageResponseGroup.wait()
//				flightGroup.wait()
//			case .engaged:
//				didExitGroup.wait()
//				flightGroup.wait()
//			default:
//				flightGroup.wait()
//		}
//		print(Colors.dim("Successfully deinitted ExitWatcher"))
//	}
//}


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
    private var _workingDirectory:URL
	private var _arguments:[String]? = nil
//	private var _environment:[String:String]? = nil
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
    var workingDirectory:URL {
        get {
            return internalSync.sync {
                return _workingDirectory
            }
        }
        set {
            internalSync.sync {
                _workingDirectory = newValue
            }
        }
    }

//	var environment:[String:String]? {
//		get {
//			return internalSync.sync {
//				return _environment
//			}
//		}
//		set {
//			internalSync.sync {
//				_environment = newValue
//			}
//		}
//	}
	
	/*
		These variables are related to the execution state of the process.
		- Process Identifier
		- Exit code
		- Is running?
	*/
	private var _launchTime:Date? = nil
	private var _exitTime:Date? = nil
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
	
    init(execute:URL, arguments:[String]?, workingDirectory:URL) throws {
		self._executable = execute
        
        var argBuild = arguments ?? [String]()
        argBuild.insert(_executable.path, at:0)
		self._arguments = argBuild
        
		self._workingDirectory = workingDirectory
		
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.execute.sync")
	}
	
    func run(sync:Bool) {
        try? self.internalSync.sync {
            guard self._isRunning == false && self._exitCode == nil else {
                throw ExecutingProcessError.processAlreadyRunning
            }
            guard var launchPath = Self.isLaunchURLExecutable(self._executable) else {
                throw ExecutingProcessError.unableToExecute
            }
            var argBuild = [launchPath]
            if let hasArguments = self._arguments {
                argBuild.append(contentsOf:hasArguments)
            }
            
            let stdinExport = self._stdin?.export()
            let stdoutExport = self._stdout?.export()
            let stderrExport = self._stderr?.export()
//
//            close(STDOUT_FILENO)
            
            let launchedPid = try launchPath.withCString({ cPath in
                try self._workingDirectory.path.withCString({ wdPath in
                    try self._arguments!.with_spawn_ready_arguments { argC in
                        return try tt_spawn(path:cPath, args:argC, wd:wdPath, stdin:stdinExport, stdout:stdoutExport, stderr:stderrExport)
                    }
                })
            })
//
            stdinExport?.configureOutbound()
            stderrExport?.configureInbound()
            stdoutExport?.configureInbound()
            
            
            print("Launched process \(launchedPid)")
            tt_wait_sync(pid:launchedPid)
//            try tt_spawn_watcher(pid: launchedPid, stdout: STDOUT_FILENO)
//            for (destination, source) in fHandles {
//                let result = posix_spawn_file_actions_adddup2(fileActions, source, destination)
//                if result != 0 {
//                    print("ERROR OHHHHHH FUCK!")
//                }
//            }
            
            self._launchTime = Date()
            self._processId = launchedPid
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

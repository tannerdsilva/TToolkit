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
internal class ExecutingProcess {
	typealias TerminationHandler = (ExecutingProcess) -> Void
	public enum ExecutingProcessError:Error {
		case processAlreadyRunning
		case unableToExecute
        case unableToCreatePipes
	}

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

	private var _stdout:ProcessPipes? = nil
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
	
	private var _stderr:ProcessPipes? = nil
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
	private var _terminationHandler:TerminationHandler? = nil
	var terminationHandler:TerminationHandler? {
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
		
    init(execute:URL, arguments:[String]?, workingDirectory:URL) throws {
		self._executable = execute
        
		self._arguments = arguments
        
		self._workingDirectory = workingDirectory
		
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.execute.sync")
	}
	
    func run(sync:Bool) throws {
        let waitSem = DispatchSemaphore(value:0)
        var failed:Bool = false
        try self.internalSync.sync {
            guard self._isRunning == false && self._exitCode == nil else {
                throw ExecutingProcessError.processAlreadyRunning
            }

            let launchPath = _executable.path
            
            var argBuild = [launchPath]
            if let hasArguments = self._arguments {
                argBuild.append(contentsOf:hasArguments)
            }
            
            let stdinExport = self._stdin?.export()
            let stdoutExport = self._stdout?.export()
            let stderrExport = self._stderr?.export()
            do {
                let (launchedPid, launchedDate) = try launchPath.withCString({ cPath in
                    try self._workingDirectory.path.withCString({ wdPath in
                        try argBuild.with_spawn_ready_arguments { argC in
                            return try globalProcessMonitor.launchProcessContainer({ notifyPipe in
                                return try tt_spawn(path:cPath, args:argC, wd:wdPath, stdin:stdinExport, stdout:stdoutExport, stderr:stderrExport, notify:notifyPipe)
                            }, onExit: { [weak self] exitCode in
                                let exitTime = Date()
                                guard let self = self else {
                                    return
                                }
                                self.exitHandle(exitCode, time:exitTime)
                                waitSem.signal()
                            })
                        }
                    })
                })
                self._processId = launchedPid
                self._launchTime = launchedDate
                print(Colors.Green("Launched process \(launchedPid)"))
            } catch _ {
                failed = true
            }
        }
        if failed == false {
            waitSem.wait()
        }
    }
    
    internal func exitHandle(_ exitCode:Int32, time:Date) {
        internalSync.sync {
            _exitCode = exitCode
            _exitTime = time
            if let hasHandler = _terminationHandler {
                hasHandler(self)
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

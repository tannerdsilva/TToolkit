import Foundation

//these are the system calls that are required to help facilitate the tt_spawn functions
#if canImport(Darwin)
	import Darwin
	internal let _read = Darwin.read(_:_:_:)
	internal let _write = Darwin.write(_:_:_:)
	internal let _close = Darwin.close(_:)
	internal let o_cloexec = Darwin.O_CLOEXEC
	internal let _pipe = Darwin.pipe(_:)
	internal let _dup2 = Darwin.dup2(_:_:)
	internal let _chdir = Darwin.chdir(_:)
#elseif canImport(Glibc)
	import Glibc
	internal let _read = Glibc.read(_:_:_:)
	internal let _write = Glibc.write(_:_:_:)
	internal let _close = Glibc.close(_:)
	internal let o_cloexec = Glibc.O_CLOEXEC
	internal let _pipe = Glibc.pipe(_:)
	internal let _dup2 = Glibc.dup2(_:_:)
	internal let _chdir = Glibc.chdir(_:)
#endif

fileprivate func _WSTATUS(_ status:Int32) -> Int32 {
    return status & 0x7f
}
fileprivate func WIFEXITED(_ status:Int32) -> Bool {
    return _WSTATUS(status) == 0
}
fileprivate func WIFSIGNALED(_ status:Int32) -> Bool {
    return (_WSTATUS(status) != 0) && (_WSTATUS(status) != 0x7f)
}

extension Array where Element == String {
	//will convert a swift array of execution arguments to a buffer pointer that tt_spawn can use at a lower levels
    internal func with_spawn_ready_arguments<R>(_ work:@escaping(UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>) throws -> R) rethrows -> R {
        let argC = self.withUnsafeBufferPointer { (pointer) -> UnsafeMutablePointer<UnsafeMutablePointer<Int8>?> in
            let arr:UnsafeBufferPointer<String> = pointer
            let buff = UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>.allocate(capacity:arr.count + 1)
            buff.initialize(from:arr.map { $0.withCString(strdup) }, count:arr.count)
            buff[arr.count] = nil
            return buff
        }
        defer {
            for arg in argC ..< argC + count {
                free(UnsafeMutableRawPointer(arg.pointee))
            }
            argC.deallocate()
        }
        return try work(argC)
    }
}

extension Dictionary where Key == String, Value == String {
    internal func with_spawn_ready_environment<R>(_ work:@escaping([UnsafeMutablePointer<Int8>]) throws -> R) rethrows -> R {
        let cEnv = self.compactMap { strdup("\($0)=\($1)") }
        defer {
            for (_, curPtr) in cEnv.enumerated() {
                free(UnsafeMutableRawPointer(curPtr))
            }
        }
        return try work(cEnv)
    }
}

//waits for a process to exit
internal func tt_wait_sync(pid:pid_t) -> Int32 {
    var waitResult:Int32 = 0
    var exitCode:Int32 = 0
    var errNo:Int32 = 0
    repeat {
        waitResult = waitpid(pid, &exitCode, 0)
        errNo = errno
    } while waitResult == -1 && errNo == EINTR || WIFEXITED(exitCode) == false
    return exitCode
}

//this is the structure that is used to capture all relevant information about a process that is in flight
internal struct tt_proc_signature:Hashable {
    var stdin:ExportedPipe? = nil
    var stdout:ExportedPipe? = nil
    var stderr:ExportedPipe? = nil
    
    var worker:pid_t
    var container:pid_t
    
    var launch_time:Date
    
    init(container:pid_t, work:pid_t) {
        worker = work
        self.container = container
        self.launch_time = Date()
    }
    
    static func == (lhs:tt_proc_signature, rhs:tt_proc_signature) -> Bool {
        return lhs.stderr == rhs.stderr && lhs.stdout == rhs.stdout && lhs.stdin == rhs.stdin && lhs.worker == rhs.worker
    }
    
    func hash(into hasher:inout Hasher) {
        if let haserr = stderr {
            hasher.combine(haserr.writing)
            hasher.combine(haserr.reading)
        }
        if let hasout = stdout {
            hasher.combine(hasout.writing)
            hasher.combine(hasout.reading)
        }
        if let hasin = stdin {
            hasher.combine(hasin.writing)
            hasher.combine(hasin.reading)
        }
        hasher.combine(worker)
    }
}

//extension of tt_spawns process signature structure to allow for convenient waiting of internal IO flushing before notifying the framework user that the process has exited
extension tt_proc_signature {
	func waitForExitAndFlush() -> (Int32, Date) {
		//wait for the containing process to exit. the containing process should exit after the working process has completed, and the global process monitor has been notified as such
        return try! ProcessMonitor.globalMonitor().waitForProcessExitAndFlush(mon:container)
	}
}

//this is the wrapping function for tt_spawn. this function can be used with swift objects rather than c pointers that are required for the base tt_spawn command
//before calling the base `tt_spawn` command, this function will prepare the global pipe readers for any spawns that are configured for stdout and stderr capture
let launchSem =  DispatchSemaphore(value:1)
internal func tt_spawn(path:URL, args:[String], wd:URL, env:[String:String], stdout:(InteractiveProcess.OutputHandler)?, stderr:(InteractiveProcess.OutputHandler)?, reading:DispatchQueue?, writing:DispatchQueue?) throws -> tt_proc_signature {
    var err_export:ExportedPipe? = nil
    var out_export:ExportedPipe? = nil
	launchSem.wait()
    if stderr != nil, reading != nil {
        err_export = try ExportedPipe.rw()
    }
    
    if stdout != nil, reading != nil {
        out_export = try ExportedPipe.rw()
    }
	defer {
		launchSem.signal()
		if err_export != nil {
			globalPR.scheduleForReading(err_export!.reading, queue:reading!, handler:stderr!)
		}
		if out_export != nil {
			globalPR.scheduleForReading(out_export!.reading, queue:reading!, handler:stdout!)
		}
	}
    
    let reutnVal = try path.path.withCString({ executablePathPointer -> tt_proc_signature in
        var argBuild = [path.path]
        argBuild.append(contentsOf:args)
        return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
            return try wd.path.withCString({ workingDirectoryPath in
                return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, stdin:nil, stdout:out_export, stderr:err_export)
            })
        })
    })
    let globalPM = try! ProcessMonitor.globalMonitor()
    globalPM.registerFlushPrerequisites(reutnVal)
    return reutnVal
}

internal enum tt_spawn_error:Error {
    case badAccess
    case internalError
    case systemForkErrorno(Int32)
}


//spawns two processes. first process is responsible for executing the actual command. second process is responsible for watching the executing process, and notifying the parent about the status of the executing process. This "monitor process" is also responsible for closing the standard inputs and outputs so that they do not get mixed in with the parents standard file descriptors
//the primary means of I/O for the monitor process is the file descriptor passed to this function `notify`. This file descriptor acts as the activity log for the monitor process.
//three types of monitor process events, launch event, exit event, and fatal event
fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], stdin:ExportedPipe?, stdout:ExportedPipe?, stderr:ExportedPipe?) throws -> tt_proc_signature {
    _ = try ProcessMonitor.globalMonitor() //test that the process monitor has been initialized before forking
    
    //used internally for this function to determine when the forked process has successfully initialized
    let internalNotify = try ExportedPipe.rw()

    let forkResult = fork()	//spawn the container process
    
    func executeProcessWork() {
        Glibc.execvp(path, args)
        _exit(0)
	}
	
	func notifyFatal(_ ph:IODescriptor) -> Never {
		try! ph.write("x\n\n")
		_exit(-1)
	}
	
	func notifyAccess(_ ph:IODescriptor) -> Never {
		try! ph.write("a\n\n")
		_exit(-1)
	}
	
    func processMonitor() throws -> Never {
        _close(internalNotify.reading)
        do {
            func bindingStdout() throws -> ExportedPipe {
                if stdout == nil {
                    return try ExportedPipe.nullPipe()
                } else {
                    return stdout!
                }
            }
            func bindingStderr() throws -> ExportedPipe {
                if stderr == nil {
                    return try ExportedPipe.nullPipe()
                } else {
                    return stderr!
                }
            }
            func bindingStdin() throws -> ExportedPipe {
                if stdin == nil {
                    return try ExportedPipe.nullPipe()
                } else {
                    return stdin!
                }
            }

            //assign stdout to the writing end of the file descriptor
            var hasStdout:ExportedPipe = try bindingStdout()
            guard _dup2(hasStdout.writing, STDOUT_FILENO) >= 0 else {
                notifyFatal(internalNotify.writing)
            }
            _ = _close(hasStdout.writing)
            _ = _close(hasStdout.reading)
            
            
            //assign stderr to the writing end of the file descriptor
            var hasStderr:ExportedPipe = try bindingStderr()
            guard _dup2(hasStderr.writing, STDERR_FILENO) >= 0 else {
                notifyFatal(internalNotify.writing)
            }
            _ = _close(hasStderr.writing)
            _ = _close(hasStderr.reading)

            //assign stdin to the writing end of the file descriptor
            var hasStdin:ExportedPipe = try bindingStdin()
            guard _dup2(hasStdin.reading, STDIN_FILENO) >= 0 else {
                notifyFatal(internalNotify.writing)
            }
            _ = _close(hasStdin.writing)
            _ = _close(hasStdin.reading)
        } catch _ {
            notifyFatal(internalNotify.writing)
        }
        
        //access checks
    	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true && chdir(wd) == 0 else {
    		notifyAccess(internalNotify.writing)
    	}
        
       	let processForkResult = fork()
        
		switch processForkResult {
			case -1:
				notifyFatal(internalNotify.writing)
				
			case 0:
				//in child: success
                executeProcessWork()
				
			default:
                try! internalNotify.writing.write("\(processForkResult)\n\n")
                _ = _close(internalNotify.writing)
                _ = _close(STDIN_FILENO)
                _ = _close(STDERR_FILENO)
                _ = _close(STDOUT_FILENO)
                
                let notifyHandle = try! ProcessMonitor.globalMonitor().newNotifyWriter()
                
				//detach from the executing process's standard inputs and outputs
				//notify the process monitor of the newly launched worker process
				let processIDEventMapping = "\(getpid()) -> \(processForkResult)"
				let launchEvent = "l" + processIDEventMapping + "\n\n"
				do {
					try notifyHandle.write(launchEvent)
				} catch _ {
                    notifyFatal(notifyHandle)
				}
                
                
                
				//wait for the worker process to exit
                let exitCode = tt_wait_sync(pid:processForkResult)
				
				//notify the process monitor about the exit of the executing process
				let exitEvent = "e" + processIDEventMapping + " -> \(exitCode)" + "\n\n"
				do {
					try notifyHandle.write(exitEvent)
				} catch _ {
                    notifyFatal(notifyHandle)
				}
                _exit(0)
        }
       _exit(0)
    }
    
    
    switch forkResult {
        case -1:
            //in parent, error
            throw tt_spawn_error.systemForkErrorno(errno)
        case 0:
            //in child: success
            try processMonitor()
        
        default:
            //in parent, success
            stdin?.closeReading()
            stderr?.closeWriting()
            stdout?.closeWriting()
            internalNotify.closeWriting()
            
            var incomingData:Data? = nil
            while incomingData == nil || incomingData!.count == 0 {
                incomingData = internalNotify.reading.availableData()
            }
            
            internalNotify.closeReading()
            if let message = String(data:incomingData!.lineSlice(removeBOM: false).first!, encoding:.utf8) {
                if let firstChar = message.first {
                    switch firstChar {
                    case "a":
                        throw tt_spawn_error.badAccess
                    case "x":
                        print("FATAL")
                        throw tt_spawn_error.internalError
                    default:
                        if let messagePid = pid_t(message) {
                            var sigToReturn = tt_proc_signature(container:forkResult, work:messagePid)
                            var idset = Set<Int32>()
                            if let hasIn = stdin {
                                idset.insert(hasIn.writing)
                            }
                            if let hasOut = stdout {
                                idset.insert(hasOut.reading)
                            }
                            if let hasErr = stderr {
                                idset.insert(hasErr.reading)
                            }
                            sigToReturn.stdin = stdin
                            sigToReturn.stdout = stdout
                            sigToReturn.stderr = stderr
                            return sigToReturn
                        }
                    }
                }
            }
            throw tt_spawn_error.internalError
    }
}


//MARK: Small Helpers
//check if a path is executable
internal func tt_execute_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_execute_check(ptr:cstrBuff)
	}
}

//check if a path is a directory
internal func tt_directory_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_directory_check(ptr:cstrBuff)
	}
}

//check if a directory can be accessed
internal func tt_directory_check(ptr:UnsafePointer<Int8>) -> Bool {
	var statInfo = stat()
	guard stat(ptr, &statInfo) == 0, statInfo.st_mode & S_IFMT == S_IFDIR else {
		return false
	}
	guard access(ptr, X_OK) == 0 else {
		return false
	}
	return true
}

//check if a path can be executed
internal func tt_execute_check(ptr:UnsafePointer<Int8>) -> Bool {
	var statInfo = stat()
	guard stat(ptr, &statInfo) == 0, statInfo.st_mode & S_IFMT == S_IFREG else {
		return false
	}
	guard access(ptr, X_OK) == 0 else {
		return false
	}
	return true
}

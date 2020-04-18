import Foundation

#if canImport(Darwin)
    import Darwin
    fileprivate let _read = Darwin.read(_:_:_:)
    fileprivate let _write = Darwin.write(_:_:_:)
    fileprivate let _close = Darwin.close(_:)
    fileprivate let _pipe = Darwin.pipe(_:)
    fileprivate let _dup2 = Darwin.dup2(_:_:)
//    fileprivate let _clearenv = Darwin.clearenv()
//    fileprivate let _execle = Darwin.execle(_:_:_:)
#elseif canImport(Glibc)
    import Glibc
    fileprivate let _read = Glibc.read(_:_:_:)
    fileprivate let _write = Glibc.write(_:_:_:)
    fileprivate let _close = Glibc.close(_:)
    fileprivate let _pipe = Glibc.pipe(_:)
    fileprivate let _dup2 = Glibc.dup2(_:_:)
    fileprivate let _clearenv = Glibc.clearenv()
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
        //convert the environment variables to C compatible variables
        let cEnv = self.compactMap { strdup("\($0)=\($1)") }
        defer {
            for (_, curPtr) in cEnv.enumerated() {
                free(UnsafeMutableRawPointer(curPtr))
            }
        }
        return try work(cEnv)
    }
}

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

internal struct tt_proc_signature:Hashable {
    var stdin:ExportedPipe? = nil
    var stdout:ExportedPipe? = nil
    var stderr:ExportedPipe? = nil
    
    var worker:pid_t
    
    init(_ pid:pid_t) {
        worker = pid
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

internal func tt_spawn(path:URL, args:[String], wd:URL, env:[String:String], stdin:Bool, stdout:Bool, stderr:Bool) throws -> tt_proc_signature {
    return try path.path.withCString({ executablePathPointer in
        var argBuild = [path.path]
        argBuild.append(contentsOf:args)
        return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
            return try wd.path.withCString({ workingDirectoryPath in
                return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, stdin:stdin, stdout:stdout, stderr:stderr)
            })
        })
    })
}

internal enum tt_spawn_error:Error {
    case badAccess
    case internalError
    case systemForkErrorno(Int32)
}

//spawns two processes. first process is responsible for executing the actual command. second process is responsible for watching the executing process, and notifying the parent about the status of the executing process. This "monitor process" is also responsible for closing the standard inputs and outputs so that they do not get mixed in with the parents standard file descriptors
//the primary means of I/O for the monitor process is the file descriptor passed to this function `notify`. This file descriptor acts as the activity log for the monitor process.
//three types of monitor process events, launch event, exit event, and fatal event
fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], stdin:Bool, stdout:Bool, stderr:Bool) throws -> tt_proc_signature {
    
    let internalNotify = try ExportedPipe.rw()

    var stdin_export:ExportedPipe? = nil
    var stdout_export:ExportedPipe? = nil
    var stderr_export:ExportedPipe? = nil
    
    if stdin {
        stdin_export = try ExportedPipe.rw()
    }
    if stdout {
        stdout_export = try ExportedPipe.rw()
    }
    if stderr {
        stderr_export = try ExportedPipe.rw()
    }
    
    let forkResult = fork()
    
    func executeProcessWork() {
        Glibc.execvp(path, args)
        _exit(0)
	}
	
	func notifyFatal(_ ph:ProcessHandle) -> Never {
		try! ph.write("x\n\n")
		_exit(-1)
	}
	
	func notifyAccess(_ ph:ProcessHandle) -> Never {
		try! ph.write("a\n\n")
		_exit(-1)
	}
	
    func processMonitor() -> Never {
        let launchWriter = ProcessHandle(fd:internalNotify.writing)
        internalNotify.closeReading()
        
        stdin_export?.closeWriting()
        stdout_export?.closeReading()
        stderr_export?.closeReading()
        
        if let hasStdout = stdout_export {
            let dupVal = _dup2(hasStdout.writing, STDOUT_FILENO)
            guard dupVal >= 0 else {
                notifyFatal(launchWriter)
            }
            _ = _close(hasStdout.writing)
            _ = _close(hasStdout.reading)
        }
        
        if let hasStderr = stderr_export {
            let dupVal = _dup2(hasStderr.writing, STDERR_FILENO)
            guard dupVal >= 0 else {
                notifyFatal(launchWriter)
            }
            _ = _close(hasStderr.writing)
            _ = _close(hasStderr.reading)
        }

        if let hasStdin = stdin_export {
            let dupVal = _dup2(hasStdin.reading, STDIN_FILENO)
            guard dupVal >= 0 else {
                notifyFatal(launchWriter)
            }
            _ = _close(hasStdin.writing)
            _ = _close(hasStdin.reading)
        }
        
        //access checks
    	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
    		notifyAccess(launchWriter)
    	}
        
       	let processForkResult = fork()
        
		switch processForkResult {
			case -1:
				notifyFatal(launchWriter)
				
			case 0:
				//in child: success
                executeProcessWork()
				
			default:
                try! launchWriter.write("\(processForkResult)\n\n")
                _close(launchWriter.fileDescriptor)
                
//                let notifyHandle = try! ProcessMonitor.global.newNotifyWriter()
                
				//detach from the executing process's standard inputs and outputs
				//notify the process monitor of the newly launched worker process
				let processIDEventMapping = "\(getpid()) -> \(processForkResult)"
				let launchEvent = "l" + processIDEventMapping + "\n\n"
				do {
//					try notifyHandle.write(launchEvent)
				} catch _ {
//                    notifyFatal(notifyHandle)
				}
                
				//wait for the worker process to exit
                let exitCode = tt_wait_sync(pid:processForkResult)
				
				//notify the process monitor about the exit of the executing process
				let exitEvent = "e" + processIDEventMapping + " -> \(exitCode)" + "\n\n"
				do {
//					try notifyHandle.write(exitEvent)
				} catch _ {
//                    notifyFatal(notifyHandle)
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
            processMonitor()
        
        default:
            //in parent, success
            stdin_export?.closeReading()
            stdout_export?.closeWriting()
            stderr_export?.closeWriting()
            internalNotify.closeWriting()
            
            let launchReader = ProcessHandle(fd:internalNotify.reading)
            var incomingData:Data? = nil
            while incomingData == nil || incomingData!.count == 0 {
                incomingData = launchReader.availableData()
            }
            
            _ = _close(internalNotify.reading)
            if let message = String(data:incomingData!.lineSlice(removeBOM: false).first!, encoding:.utf8) {
                if let firstChar = message.first {
                    switch firstChar {
                    case "a":
                        throw tt_spawn_error.badAccess
                    case "x":
                        throw tt_spawn_error.internalError
                    default:
                        if let messagePid = pid_t(message) {
                            var sigToReturn = tt_proc_signature(messagePid)
                            sigToReturn.stdin = stdin_export
                            sigToReturn.stdout = stdout_export
                            sigToReturn.stderr = stderr_export
                            return sigToReturn
                        }
                    }
                }
            }
            throw tt_spawn_error.internalError
                        
    }
}

internal func tt_execute_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_execute_check(ptr:cstrBuff)
	}
}

internal func tt_directory_check(url:URL) -> Bool {
	let urlPath = url.path
	return urlPath.withCString { cstrBuff in
		return tt_directory_check(ptr:cstrBuff)
	}
}

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

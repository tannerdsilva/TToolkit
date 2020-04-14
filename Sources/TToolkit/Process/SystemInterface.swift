import Foundation

#if canImport(Darwin)
    import Darwin
    fileprivate let _read = Darwin.read(_:_:_:)
    fileprivate let _write = Darwin.write(_:_:_:)
    fileprivate let _close = Darwin.close(_:)
    fileprivate let _pipe = Darwin.pipe(_:)
    fileprivate let _dup2 = Darwin.dup2(_:_:)
//    fileprivate let _execle = Darwin.execle(_:_:_:)
#elseif canImport(Glibc)
    import Glibc
    fileprivate let _read = Glibc.read(_:_:_:)
    fileprivate let _write = Glibc.write(_:_:_:)
    fileprivate let _close = Glibc.close(_:)
    fileprivate let _pipe = Glibc.pipe(_:)
    fileprivate let _dup = Glibc.dup(_:)
    fileprivate let _dup2 = Glibc.dup2(_:_:)
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

internal enum tt_spawn_error:Error {
    case systemForkErrorno(Int32)
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


//spawns two processes. first process is responsible for executing the actual command. second process is responsible for watching the executing process, and notifying the parent about the status of the executing process. This "monitor process" is also responsible for closing the standard inputs and outputs so that they do not get mixed in with the parents standard file descriptors
//the primary means of I/O for the monitor process is the file descriptor passed to this function `notify`. This file descriptor acts as the activity log for the monitor process.
//three types of monitor process events, launch event, exit event, and fatal event
internal func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, stdin:ExportedPipe?, stdout:ExportedPipe?, stderr:ExportedPipe?, notify:Int32) throws -> ProcessMonitor.ProcessKey {    
    let forkResult = fork()

	func executeProcessWork() {
		_close(notify)

        
        _exit(Glibc.execvp(path, args))
	}
	
	func notifyFatal(_ ph:ProcessHandle) -> Never {
		try! ph.write("x\(getpid())\n\n")
		ph.close()
		_exit(-1)
	}
	
	func notifyAccess(_ ph:ProcessHandle) -> Never {
		try! ph.write("a\(getpid())\n\n")
		ph.close()
		_exit(-1)
	}
	
    func processMonitor() -> Never {
    	let notifyHandle = ProcessHandle(fd:notify)
        
        //access checks
    	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
    		notifyAccess(notifyHandle)
    	}
    	
    	//change working directory
		guard chdir(wd) == 0 else {
			notifyFatal(notifyHandle)
        }
        if let hasStdin = stdin {
            guard _dup2(hasStdin.reading, STDIN_FILENO) == 0 else {
                _exit(-1)
            }
//            hasStdin.close()
        }
        if let hasStdout = stdout {
            guard _dup2(hasStdout.writing, STDOUT_FILENO) == 0 else {
                _exit(-1)
            }
//            hasStdout.close()
        }
        if let hasStderr = stderr {
            guard _dup2(hasStderr.writing, STDERR_FILENO) == 0 else {
                _exit(-1)
            }
//            hasStderr.close()
        }
        for i in 0..<10000 {
            write(hasStdout.writing, "fuck you\n", "fuck you\n".count)
        }
        
       	let processForkResult = fork()
		switch processForkResult {
			case -1:
				notifyFatal(notifyHandle)
				
			case 0:
				//in child: success
				executeProcessWork()
				
			default:
				//in monitor process, success
                //detach from parents standard inputs and outputs
//                _close(STDIN_FILENO)
//                _close(STDOUT_FILENO)
//                _close(STDERR_FILENO)
                
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
				_close(notify)
                _exit(0)
        }
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
            return forkResult
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

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
    var stdin:PosixPipe
    var stdout:PosixPipe
    var stderr:PosixPipe
    
    var worker:pid_t
    
    var launch_time:Date
    
    init(work:pid_t) {
        worker = work
        self.launch_time = Date()
    }
    
    static func == (lhs:tt_proc_signature, rhs:tt_proc_signature) -> Bool {
        return lhs.stderr == rhs.stderr && lhs.stdout == rhs.stdout && lhs.stdin == rhs.stdin && lhs.worker == rhs.worker
    }
    
    func hash(into hasher:inout Hasher) {
    	//standard input channel is always going to be utilized
		hasher.combine(hasin.writing)
		hasher.combine(hasin.reading)
		
        if stdout.isNullValued == false  {
            hasher.combine(hasout.writing)
            hasher.combine(hasout.reading)
        }
        if stderr.isNullValued == false {
            hasher.combine(haserr.writing)
            hasher.combine(haserr.reading)
        }
        
        hasher.combine(worker)
        hasher.combine(launch_time)
    }
}

//this is the wrapping function for tt_spawn. this function can be used with swift objects rather than c pointers that are required for the base tt_spawn command
//before calling the base `tt_spawn` command, this function will prepare the global pipe readers for any spawns that are configured for stdout and stderr capture
internal func tt_spawn(path:URL, args:[String], wd:URL, env:[String:String], stdout:@escaping(DataChannelMonitor.InboundDataHandler)?, stderr:@escaping(DataChannelMonitor.InboundDataHandler)?, exitHandler:@escaping(Int32) -> Void) throws -> tt_proc_signature {
	let stdoutPipe:PosixPipe
	let stderrPipe:PosixPipe
	var handlesOfInterest = Set<Int32>()
	let stdinPipe = PosixPipe(nonblockingReads:true, nonblockingWrites:true)
	
	//configure for a standard output handler if the user passed a handler block
	if stdout != nil {
		stdoutPipe = PosixPipe(nonblockingReads:true, nonblockingWrites:true)
		guard stdoutPipe.isNullValued == false else {
			throw tt_spawn_error.pipeError
		}
		handlesOfInterest.update(with:stdoutPipe.reading)
		try globalChannelMonitor.registerInboundDataChannel(fh:stdoutPipe.reading, mode:.lineBreaks, dataHandler:stdout!, terminationHandler:{ return })
	} else {
		stdoutPipe = PosixPipe(reading:-1, writing:-1)
	}
	
	//configure for a standard error handler if the user passed a handler block
	if stderr != nil {
		stderrPipe = PosixPipe(nonblockingReads:true, nonblockingWrites:true)
		guard stderrPipe.isNullValued == false else {
			throw tt_spawn_error.pipeError
		}
		handlesOfInterest.update(with:stderrPipe.reading)
		try globalChannelMonitor.registerInboundDataChannel(fh:stderrPipe.reading, mode:.lineBreaks, dataHandler:stderr!, terminationHandler:{ return })
	} else {
		stderrPipe = PosixPipe(reading:-1, writing:-1)
	}
	
	//bind the standard input handler. this is always configured because it is our primary means of determining when a process exits
	guard stdinPipe.reading != -1 && stdinPipe.writing != -1 else {
		throw tt_spawn_error.pipeError
	}
	handlesOfInterest.update(with:stdinPipe.writing)
	try globalChannelMonitor.registerOutboundDataChannel(fh:stdinPipe.writing, initialData:nil, terminationhandler: { return })

	//create a termination group that can be associated with the launched pid
	let terminationGroup = globalChannelMonitor.registerTerminationGroup(fhs:handlesOfInterest, handler: { [exitHandler] exitPid in
		exitHandler(tt_wait_sync(pid:exitPid))
	})
    
    //launch the process
    let returnVal = try path.path.withCString({ executablePathPointer -> tt_proc_signature in
        var argBuild = [path.path]
        argBuild.append(contentsOf:args)
        return try argBuild.with_spawn_ready_arguments({ argumentsToSpawn in
            return try wd.path.withCString({ workingDirectoryPath in
                return try tt_spawn(path:executablePathPointer, args:argumentsToSpawn, wd:workingDirectoryPath, env:env, stdin:nil, stdout:out_export, stderr:err_export)
            })
        })
    })
    
    //associate the launched pid with the newly created termination group
    terminationGroup.setAssociatedPid(returnVal.worker)
    return reutnVal
}

internal enum tt_spawn_error:Error {
    case badAccess
    case internalError
    case systemForkErrorno(Int32)
    case pipeError
}
//spawns two processes. first process is responsible for executing the actual command. second process is responsible for watching the executing process, and notifying the parent about the status of the executing process. This "monitor process" is also responsible for closing the standard inputs and outputs so that they do not get mixed in with the parents standard file descriptors
//the primary means of I/O for the monitor process is the file descriptor passed to this function `notify`. This file descriptor acts as the activity log for the monitor process.
//three types of monitor process events, launch event, exit event, and fatal event
//BEHAVIOR UNDEFINED if a null valued standard input pipe is passed to this function
fileprivate func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, env:[String:String], stdin:PosixPipe, stdout:PosixPipe, stderr:PosixPipe) throws -> tt_proc_signature {
    //used internally for this function to determine when the forked process has successfully initialized
    let internalNotify = PosixPipe(nonblockingReads:false, nonblockingWrites:true)
	guard internalNotify.isNullValued == false else {
		throw tt_spawn_error.pipeError
	}
	
	guard tt_directory_check(ptr:wd) == true && tt_execute_check(ptr:path) == true else {
		throw tt_spawn_error.badAccess
	}
	
    let forkResult = fork()	//spawn the container process
    
    func executeProcessWork() -> Never {
        Glibc.execvp(path, args)
        _exit(0)
	}
		
    func processMonitor() -> Never {
    	//close the reading end of the pipe immediately
        _ = _close(internalNotify.reading)
        
        //bind the IO to the standard inputs and outputs.
        do {
            func bindingStdout() throws -> PosixPipe {
                if stdout.isNullValued == true {
                    return try PosixPipe.createNullPipe()
                } else {
                    return stdout
                }
            }
            func bindingStderr() throws -> PosixPipe {
                if stderr.isNullValued == true {
                    return try PosixPipe.createNullPipe()
                } else {
                    return stderr
                }
            }

            //assign stdout to the writing end of the file descriptor
            var hasStdout:PosixPipe = try bindingStdout()
            defer {
            	if (hasStdout.isNullValued == false) {
					_ = _close(hasStdout.writing)
					_ = _close(hasStdout.reading)
            	}
            }
            guard _dup2(hasStdout.writing, STDOUT_FILENO) >= 0 else {
                exit(-1)
            }
            
            //assign stderr to the writing end of the file descriptor
            var hasStderr:PosixPipe = try bindingStderr()
            defer {
            	if (hasStderr.isNullValued == false) {
					_ = _close(hasStderr.writing)
					_ = _close(hasStderr.reading)
            	}
            }
            guard _dup2(hasStderr.writing, STDERR_FILENO) >= 0 else {
                exit(-1)
            }

            //assign stdin to the writing end of the file descriptor
            let hasStdin:PosixPipe = stdin
            defer {
				_ = _close(hasStdin.writing)
				_ = _close(hasStdin.reading)
            }
            guard _dup2(stdin.reading, STDIN_FILENO) >= 0 else {
                exit(-1)
            }
        } catch _ {
            _exit(-1)
        }
        
        //change the active directory
		guard chdir(wd) == 0 else {
			_exit(-1)
		}
        
       	let processForkResult = fork()
        
		switch processForkResult {
			case -1:
				exit(-3)
				
			case 0:
				//in child: success
                executeProcessWork()
				
			default:
				_ = _close(STDIN_FILENO)
                _ = _close(STDERR_FILENO)
                _ = _close(STDOUT_FILENO)
				do {
					try internalNotify.writing.writeFileHandle("\(processForkResult)\n")
				} catch _ {
					exit(-2)
				}
                _ = _close(internalNotify.writing)
                _exit(0)
        }
    }
    
    //handle the result of the first fork call
    switch forkResult {
        case -1:
            //in parent, error
            throw tt_spawn_error.systemForkErrorno(errno)
        case 0:
            //in child: success
            processMonitor()
        
        default:
            //in parent, success
            
            //configure the file handles for the context of the parent process synchronously
            self.fileHandleQueue.sync {
				close(internalNotify.writing)
            	close(stdin.reading)
            	close(stderr.writing)
            	close(stdout.writing)
            }
			
			//wait for the container process to exit
			let containerExitCode = tt_wait_sync(pid:forkResult) 
			guard containerExitCode == 0 else {
				print("ERROR: CONTAINER PROCESS EXITED WITH NONZERO RESULT. \(containerExitCode)")
				throw tt_spawn_error.internalError
			}
			
            //wait for data to appear in the internalNotify pipe
            var shouldLoop = false
            var triggerData = Data()
            repeat {
            	do {
            		try triggerData.append(contentsOf:internalNotify.reading.readFileHandle())
            		shouldLoop = false
            	} catch FileHandleError.error_again {
            		shouldLoop = true
            	} catch FileHandleError.error_wouldblock {
            		shouldLoop = true
            	} catch _ {
            		shouldLoop = false
            	}
            } while shouldLoop == true
            //close the internal notify switch in the background
            fileHandleQueue.async { [closeHandle = internalNotify.reading] in
            	close(closeHandle)
            }
            
            //parse the data that was received in the internalNotify pipe
            guard triggerData.count > 0 else {
            	print("ERROR: Internal notify handle didn't get any data")
            	throw tt_spawn_error.internalError
            }
            guard let notifyString = String(data:triggerData, encoding:.utf8), let messagePid = pid_t(notifyString) {
            	throw tt_spawn_error.internalError
            }
            var sigToReturn = tt_proc_signature(work:messagePid)
            sigToReturn.stdin = stdin
            sigToReturn.stdout = stdout
            sigToReturn.stderr = stderr
            
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

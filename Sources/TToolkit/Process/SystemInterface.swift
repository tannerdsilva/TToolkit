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

//stdin: needs the write end
//stdou
internal func tt_spawn(path:UnsafePointer<Int8>, args:UnsafeMutablePointer<UnsafeMutablePointer<Int8>?>, wd:UnsafePointer<Int8>, stdin:ExportedPipe?, stdout:ExportedPipe?, stderr:ExportedPipe?) throws -> pid_t {
    
    let forkResult = fork()
    
    
    func forkedWork() -> Never {
        chdir(wd)
        
//         let dupedIn = _dup(STDIN_FILENO)
//         let dupedOut = _dup(STDOUT_FILENO)
//         let dupedErr = _dup(STDERR_FILENO)

		if let hasStdin = stdin {
            guard _dup2(hasStdin.reading, STDIN_FILENO) == 0 else {
				fatalError("COULD NOT DUPE")
			}
            _close(hasStdin.reading)
        }
        
        if let hasStdout = stdout {
            guard _dup2(hasStdout.writing, STDOUT_FILENO) == 0 else {
            	fatalError("COULD NOT DUPE")
            }
            _close(hasStdout.writing)
        }
            
        if let hasStderr = stderr {
            guard _dup2(hasStderr.writing, STDERR_FILENO) == 0 else {
            	fatalError("COULD NOT DUPE")
            }
            _close(hasStderr.writing)
        }
        
        
        _exit(Glibc.execvp(path, args))
        
    }
    
    switch forkResult {
        case -1:
            //in parent, error
            throw tt_spawn_error.systemForkErrorno(errno)
        case 0:
            //in child: success
            forkedWork()
        default:
            //in parent, success
            return forkResult
    }
}

internal func tt_wait_sync(pid:pid_t) {
    var waitResult:Int32 = 0
    var exitCode:Int32 = 0
    var errNo:Int32 = 0
    repeat {
        waitResult = waitpid(pid, &exitCode, 0)
        errNo = errno
    } while waitResult == -1 && errNo == EINTR || WIFEXITED(exitCode) == false
}

//this forked process simply watches
internal func tt_spawn_watcher(pid:pid_t, stdout:Int32?) throws -> pid_t {
    
    let forkResult = fork()
    
    func forkedWork() -> Never {
//        if let hasStdin = stdin {
//            _dup2(hasStdin, STDIN_FILENO)
//            _close(STDIN_FILENO)
//        }
//
        if let hasStdout = stdout {
            _dup2(hasStdout, STDOUT_FILENO)
            _close(STDOUT_FILENO)
        }
        _close(STDERR_FILENO)
        
        let newTimer = TTimer()
        newTimer.handler = { _ in
            print("engaged")
        }
        newTimer.duration = 10
        newTimer.activate()
        
        var waitResult:Int32 = 0
        var exitCode:Int32 = 0
        var errNo:Int32 = 0
        repeat {
            waitResult = waitpid(pid, &exitCode, 0)
            errNo = errno
        } while waitResult == -1 && errNo == EINTR || WIFEXITED(exitCode) == false
        newTimer.cancel()
        print("exited")
        _exit(0)
    }
    
    switch forkResult {
        case -1:
            //in parent, error
            throw tt_spawn_error.systemForkErrorno(errno)
        case 0:
            //in child: success
            forkedWork()
        default:
            //in parent, success
            return forkResult
    }
}

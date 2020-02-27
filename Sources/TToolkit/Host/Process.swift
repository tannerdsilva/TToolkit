import Foundation

enum ProcessError:Error {
    case processStillRunning
}

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

private let safeInit = DispatchSemaphore(value:1)
public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    
    let processQueue:DispatchQueue
    
	public enum State:UInt8 {
		case initialized = 0
		case running = 1
		case suspended = 2
		case exited = 4
		case failed = 5
	}
    
	public var env:[String:String]
	public var stdin:FileHandle
	public var stdout:FileHandle
	public var stderr:FileHandle
	public var workingDirectory:URL
	internal var proc = Process()
	public var state:State = .initialized
    
    private var _stdoutHandler:OutputHandler? = nil
    public var stdoutHandler:OutputHandler? {
        get {
            return _stdoutHandler
        }
        set {
            processQueue.sync {
                _stdoutHandler = newValue
            }
        }
    }
    
    private var _stderrHandler:OutputHandler? = nil
    public var stderrHandler:OutputHandler? {
        get {
            return _stderrHandler
        }
        set {
            processQueue.sync {
                _stderrHandler = newValue
            }
        }
    }

    public init<C>(command:C, qos:Priority = .`default`, workingDirectory wd:URL, run:Bool) throws where C:Command {
		print(Colors.dim("Initializing pipe..."))
		processQueue = DispatchQueue(label:"com.tannersilva.process-interactive.sync", qos:qos.asDispatchQoS())
		env = command.environment
		let inPipe = Pipe()
		let outPipe = Pipe()
		let errPipe = Pipe()
		stdin = inPipe.fileHandleForWriting
		stdout = outPipe.fileHandleForReading
		stderr = errPipe.fileHandleForReading
		workingDirectory = wd
		proc.arguments = command.arguments
		proc.executableURL = command.executable
		proc.currentDirectoryURL = wd
		proc.standardInput = inPipe
		proc.standardOutput = outPipe
		proc.standardError = errPipe
//		proc.qualityOfService = qos.asProcessQualityOfService()
		proc.terminationHandler = { [weak self] someItem in
			guard let self = self else {
				return
			}
			self.processQueue.sync {
				self.state = .exited
			
				if #available(macOS 10.15, *) {
					try? self.stdin.close()
					try? self.stdout.close()
					try? self.stderr.close()
				}
			}
		}
        
        stdout.readabilityHandler = { [weak self] _ in
            guard let self = self, self.state == .running || self.state == .suspended else {
                return
            }
            var dataRead:Data? = nil
            self.processQueue.sync {
                let readData = self.stdout.availableData
                let bytesCount = readData.count
                if bytesCount > 0 {
                    dataRead = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
                }
            }
            if let hasHandler = self.stdoutHandler {
                hasHandler(dataRead!)
            }
        }
        
        stderr.readabilityHandler = { [weak self] _ in
            guard let self = self, self.state == .running || self.state == .suspended else {
                return
            }
            var dataRead:Data? = nil
            self.processQueue.sync {
                let readData = self.stderr.availableData
                let bytesCount = readData.count
                if bytesCount > 0 {
                    dataRead = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
                }
            }
            if let hasHandler = self.stderrHandler {
            	hasHandler(dataRead!)
            }
        }

		print(Colors.Green("[PIPE]\tInitialization successful."))

		if run {
            do {
                try self.run()
            } catch let error {
                throw error
            }
		}
    }
    
    public func run() throws {
        try processQueue.sync {
            do {
            	print("Running...")
                try proc.run()
                state = .running
            } catch let error {
                state = .failed
                print(Colors.Red("FAILED"))
                throw error
            }

        }
    }
	
	public func suspend() -> Bool? {
        processQueue.sync {
            if state == .running {
                if proc.suspend() == true {
                    state = .suspended
                    return true
                } else {
                    state = .running
                    return false
                }
            } else {
                return nil
            }
        }
    }
	
	public func resume() -> Bool? {
        processQueue.sync {
            if state == .suspended {
                if proc.resume() == true {
                    state = .running
                    return true
                } else {
                    state = .suspended
                    return false
                }
            } else {
                return nil
            }
        }
	}
    
    public func waitForExitCode() -> Int {
    	if state == .suspended || state == .running {
			proc.waitUntilExit()
    	}
        let returnCode = proc.terminationStatus
        return Int(returnCode)
    }
	
	deinit {
		if #available(macOS 10.15, *) {
			try? stdin.close()
			try? stdout.close()
			try? stderr.close()
		}
	}

    //MARK: Reading Output Streams As Lines
//    public func readStdErr() -> [String] {
//        var lineToReturn:[String]? = nil
//        while lineToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stderr.availableData
//            if bytes.count > 0 {
//                _ = stderrGuard.processData(bytes)
//                lineToReturn = stderrGuard.flushLines()
//            }
//            suspendGroup.wait()
//        }
//        return lineToReturn ?? [String]()
//    }
//    public func readStdOut() -> [String] {
//        var lineToReturn:[String]? = nil
//        while lineToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stdout.availableData
//            if bytes.count > 0 {
//                _ = stdoutGuard.processData(bytes)
//                lineToReturn = stdoutGuard.flushLines()
//            }
//            suspendGroup.wait()
//        }
//        return lineToReturn ?? [String]()
//    }
//
//
//    //MARK: Reading Output Streams as Data
//    public func readStdOut() -> Data {
//        var dataToReturn:Data? = nil
//        while dataToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stdout.availableData
//            if bytes.count > 0 {
//                dataToReturn = bytes
//            }
//            suspendGroup.wait()
//        }
//        return dataToReturn ?? Data()
//    }
//
//    public func readStdErr() -> Data {
//        var dataToReturn:Data? = nil
//        while dataToReturn == nil && proc.isRunning == true && state == .running {
//            let bytes = stderr.availableData
//            if bytes.count > 0 {
//                dataToReturn = bytes
//            }
//            suspendGroup.wait()
//        }
//        return dataToReturn ?? Data()
//    }
}

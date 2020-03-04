import Foundation

enum ProcessError:Error {
    case processStillRunning
}

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

let processLaunch = DispatchQueue(label:"com.tannersilva.process-interactive.launch", qos:Priority.highest.asDispatchQoS())

struct OutstandingExits {
	let dq = DispatchQueue(label:"com.tannersilva.exitcounter")
	var running = [String:Date]()
	
	mutating func began(_ command:String) {
		dq.sync {
			running[command] = Date()
		}
	}
	
	mutating func exited(_ command:String) {
		dq.sync {
			running[command] = nil
		}
	}
	
	func report() {
		dq.sync {
			let sorted = running.sorted(by: { $0.value > $1.value })
			let sortCount = sorted.count
			print(Colors.Blue("\(sortCount) processes in flight"))
			for (n, curProcess) in sorted.enumerated() {
				print(Colors.cyan(curProcess.key))
			}
		}
	}
}

var exitObserver = OutstandingExits()

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    
    public let runningGroup = DispatchGroup()
    
    public let processQueue:DispatchQueue
    private let callbackQueue:DispatchQueue
    
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
	
	public var stdoutBuff = Data()
	public var stderrBuff = Data()

	public var workingDirectory:URL
	internal var proc = Process()
	public var state:State = .initialized
    
    public var runningTimer:TTimer? = nil
    
    private var _stdoutHandler:OutputHandler? = nil
    public var stdoutHandler:OutputHandler? {
        get {
        	return processQueue.sync {
        		return _stdoutHandler
        	}
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
        	return processQueue.sync {
				return _stderrHandler
        	}   
        }
        set {
            processQueue.sync {
                _stderrHandler = newValue
            }
        }
    }
    
    

    public init<C>(command:C, qos:Priority = .`default`, workingDirectory wd:URL, run:Bool) throws where C:Command {
		processQueue = DispatchQueue(label:"com.tannersilva.process-interactive.sync", qos:qos.asDispatchQoS())
		callbackQueue = DispatchQueue.global(qos:qos.asDispatchQoS())
		
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
		proc.qualityOfService = qos.asProcessQualityOfService()
		proc.terminationHandler = { [weak self] someItem in
			guard let self = self else {
				return
			}
			self.runningGroup.enter()
			self.processQueue.sync {
				self.state = .exited
				if #available(macOS 10.15, *) {
					try? self.stdin.close()
					try? self.stdout.close()
					try? self.stderr.close()
				}
			}
			self.runningGroup.leave()
		}
        
        stdout.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.runningGroup.enter()
            let readData = self.stdout.availableData
            let bytesCount = readData.count
            let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
            self.appendStdoutData(bytesCopy)
            self.runningGroup.leave()
        }
        
        stderr.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.runningGroup.enter()
            let readData = self.stderr.availableData
            let bytesCount = readData.count
            let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
            self.appendStderrData(bytesCopy)            
            self.runningGroup.leave()
        }
        
        runningTimer = TTimer(seconds:30) { [weak self] _ in
			guard let self = self else {
				return
			}
			exitObserver.report()
			if self.proc.isRunning == true {
				print("\(self.proc.processIdentifier) is running")
			}
		}

		if run {
            do {
                try self.run()
            } catch let error {
                throw error
            }
		}
    }
    
    fileprivate func appendStdoutData(_ inputData:Data) {
    	processQueue.sync {
    		self.stdoutBuff.append(inputData)
    	}
    }
    
    fileprivate func appendStderrData(_ inputData:Data) {
    	processQueue.sync {
    		self.stderrBuff.append(inputData)
    	}
    }
    
    public func run() throws {
        try processQueue.sync {
            do {
            	try processLaunch.sync {
            		try proc.run()
            	}
				exitObserver.began(String(proc.processIdentifier))
                state = .running
            } catch let error {
                state = .failed
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
	
	public func exportStdOut() -> Data {
		return processQueue.sync {
			let stdoutToReturn = stdoutBuff
			stdoutBuff.removeAll(keepingCapacity:true)
			return stdoutToReturn
		}
	}
	
	public func exportStdErr() -> Data {
		return processQueue.sync {
			let stdoutToReturn = stderrBuff
			stderrBuff.removeAll(keepingCapacity:true)
			return stdoutToReturn
		}
	}

    
    public func waitForExitCode() -> Int {
//    	var shouldWait:Bool = false
//    	processQueue.sync {
//    		if state == .suspended || state == .running {
//    			shouldWait = true
//    		}
//    	}
//    	if shouldWait {
			proc.waitUntilExit()
//    	}
    	exitObserver.exited(String(proc.processIdentifier))
    	runningGroup.wait()
        let returnCode = proc.terminationStatus
        return Int(returnCode)
    }
}

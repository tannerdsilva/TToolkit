import Foundation

enum ProcessError:Error {
    case processStillRunning
}

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

let processLaunch = DispatchQueue(label:"com.tannersilva.process-interactive.launch", qos:Priority.highest.asDispatchQoS())

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    
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
            guard let self = self else {
                return
            }
            self.processQueue.sync {
            	guard self.state == .running || self.state == .suspended else {
            		return
            	}
                let readData = self.stdout.availableData
                let bytesCount = readData.count
                if bytesCount > 0 {
					let dataCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
					self.stdoutBuff.append(dataCopy)
//					if let hasHandler = self._stdoutHandler {
//						self.callbackQueue.async {
//							hasHandler(dataCopy)
//						}
//					} 
                }
            }
        }
        
        stderr.readabilityHandler = { [weak self] _ in
            guard let self = self else {
                return
            }
            self.processQueue.sync {
				guard self.state == .running || self.state == .suspended else {
            		return
            	}
            	let readData = self.stdout.availableData
            	let bytesCount = readData.count
            	if bytesCount > 0 {
					let dataCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
					self.stderrBuff.append(dataCopy)
//					if let hasHandler = self._stderrHandler {
//						self.callbackQueue.async {
//							hasHandler(dataCopy)
//						}
//					}
            	}
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
    
    public func run() throws {
        try processQueue.sync {
            do {
            	try processLaunch.sync {
            		try proc.run()
            	}	
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
			let stdoutToReturn = stdoutBuff
			stdoutBuff.removeAll(keepingCapacity:true)
			return stdoutToReturn
		}
	}

    
    public func waitForExitCode() -> Int {
    	var shouldWait:Bool = false
    	processQueue.sync {
    		if state == .suspended || state == .running {
    			shouldWait = true
    		}
    	}
    	if shouldWait {
			proc.waitUntilExit()
    	}
    	
        let returnCode = proc.terminationStatus
        return Int(returnCode)
    }
}

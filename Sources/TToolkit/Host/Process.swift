import Foundation

fileprivate func bashEscape(string:String) -> String {
	return "'" + string.replacingOccurrences(of:"'", with:"\'") + "'"
}

//InteractiveProcess must be launched and destroyed on a serial thread for stability.
//This is the internal run thread that TToolkit uses to launch new InteractiveProcess instances
fileprivate let serialProcess = DispatchQueue(label:"com.tannersilva.global.process-interactive.launch", qos:Priority.highest.asDispatchQoS())

//InteractiveProcess calls on this function to serially initialize the pipes and process objects that it needs to operate
fileprivate typealias ProcessAndPipes = (stdin:Pipe, stdout:Pipe, stderr:Pipe, process:Process)

extension Process {
	fileprivate func signal(_ sign:Int32) -> Int32 {
		return kill(processIdentifier, sign)
	}
}

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = (InteractiveProcess) -> Void
    
    public let processQueue:DispatchQueue		//what serial thread is going to be used to process the data for each class instance?
    public let callbackQueue:DispatchQueue		//what global concurrent thread is going to be used to call back the handlers
    
    private let runGroup:DispatchGroup			//used to signify that the object is still "working"
    private let dataGroup:DispatchGroup			//used to signify that there is data that has been passed to a handler function that hasn't been appended to the internal buffers yet
    
	public enum State:UInt8 {
		case initialized = 0
		case running = 1
		case suspended = 2
		case exited = 4
		case failed = 5
	}
	
	internal var stdin:ProcessPipes
	internal var stdout:ProcessPipes
	internal var stderr:ProcessPipes
	
	public var stdoutBuff = Data()
	public var stderrBuff = Data()

	internal let proc:ExecutingProcess
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
    
    private var _stdinHandler:InputHandler? = nil
    public var stdinHandler:InputHandler? {
    	get {
    		return processQueue.sync {
    			return _stdinHandler
    		}
    	}
    	set {
    		return processQueue.sync {
    			_stdinHandler = newValue
    		}
    	}
    }

    public init<C>(command:C, priority:Priority = .`default`, run:Bool) throws where C:Command {
    	print(Colors.cyan("Executing process initialized"))
		processQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", qos:priority.asDispatchQoS())
		callbackQueue = priority.globalConcurrentQueue
		
		runGroup = DispatchGroup()
		dataGroup = DispatchGroup()
				
		//create the ProcessHandles that we need to read the data from this process as it runs
		let standardIn = ProcessPipes(priority:priority, queue:processQueue)
		let standardOut = ProcessPipes(priority:priority, queue:processQueue)
		let standardErr = ProcessPipes(priority:priority, queue:processQueue)
		stdin = standardIn
		stdout = standardOut
		stderr = standardErr
		
		//create the ExecutingProcess
		proc = ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, priority:priority)
		print("Initialized executing process...not running")
		
		proc.stdin = standardIn
		proc.stdout = standardOut
		proc.stderr = standardErr
		
		proc.terminationHandler = { [weak self] _ in
			guard let self = self else {
				return
			}
			self.dataGroup.wait()
			self.processQueue.sync {
				self.state = .exited
			}
			self.runGroup.leave()
		}
        
		stdout.readHandler = { [weak self] _ in
			guard let self = self else {
				return
			}
			print(Colors.cyan("stdout read handler"))
			self.dataGroup.enter()
			if let readData = self.stdout.reading.availableData() {
				print(Colors.yellow("\t-> GOT DATA"))
				let bytesCount = readData.count
				if bytesCount > 0 {
					let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
					self.appendStdoutData(bytesCopy)
				}
			} else {
				print("DID NOT GET DATA")
			}
			self.dataGroup.leave()
		}
	
		stderr.readHandler = { [weak self] _ in
			guard let self = self else {
				return
			}
			print(Colors.magenta("stderr read handler"))
			self.dataGroup.enter()
			if let readData = self.stderr.reading.availableData() {
				print(Colors.yellow("\t-> GOT DATA"))
				let bytesCount = readData.count
				if bytesCount > 0 {
					let bytesCopy = readData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
					self.appendStderrData(bytesCopy)
				}
			} else {
				print("DID NOT GET DATA")
			}
			self.dataGroup.leave()         
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
    	dataGroup.enter()
    	processQueue.async { [weak self] in
			guard let self = self else {
				return
			}
    		self.stdoutBuff.append(inputData)
    		self.dataGroup.leave()
    	}
    }
    
    fileprivate func appendStderrData(_ inputData:Data) {
    	dataGroup.enter()
    	processQueue.async { [weak self] in
    		guard let self = self else {
    			return
    		}
    		self.stderrBuff.append(inputData)
    		self.dataGroup.leave()
    	}
    }
    
    public func run() throws {
        try processQueue.sync {
            do {
            	runGroup.enter()
            	
            	//framework must launch processes serially for complete thread safety
            	try serialProcess.sync {
					try proc.run()
            	}
            	
                state = .running
            } catch let error {
            	runGroup.leave()
                state = .failed
                throw error
            }
        }
    }
	
	public func suspend() -> Bool? {
        return processQueue.sync {
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
        return processQueue.sync {
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
		return stdoutBuff
	}
	
	public func exportStdErr() -> Data {
		return stderrBuff
	}

    public func waitForExitCode() -> Int {
		runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

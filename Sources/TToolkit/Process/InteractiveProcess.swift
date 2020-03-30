import Foundation

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = (InteractiveProcess) -> Void
    
    public let priority:Priority				//what is the priority of this interactive process. most (if not all) of the asyncronous work for this process and others will be based on this Priority
    public let queue:DispatchQueue				//what serial thread is going to be used to process the data for each class instance?
    
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
        	return queue.sync {
        		return _stdoutHandler
        	}
        }
        set {
            queue.sync {
                _stdoutHandler = newValue
            }
        }
    }
    
    private var _stderrHandler:OutputHandler? = nil
    public var stderrHandler:OutputHandler? {
        get {
        	return queue.sync {
				return _stderrHandler
        	}   
        }
        set {
            queue.sync {
                _stderrHandler = newValue
            }
        }
    }
    
    private var _stdinHandler:InputHandler? = nil
    public var stdinHandler:InputHandler? {
    	get {
    		return queue.sync {
    			return _stdinHandler
    		}
    	}
    	set {
    		return queue.sync {
    			_stdinHandler = newValue
    		}
    	}
    }

    public init<C>(command:C, priority:Priority = .`default`, run:Bool) throws where C:Command {
    	self.priority = priority
		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", qos:priority.asDispatchQoS(), target:priority.globalConcurrentQueue)
		self.queue = syncQueue
		
		let dg = DispatchGroup()
		let rg = DispatchGroup()
		
		runGroup = rg
		dataGroup = dg
				
		//create the ProcessHandles that we need to read the data from this process as it runs
		let standardIn = try ProcessPipes(priority:priority)
		let standardOut = try ProcessPipes(priority:priority)
		let standardErr = try ProcessPipes(priority:priority)
		stdin = standardIn
		stdout = standardOut
		stderr = standardErr
		
		//create the ExecutingProcess
		proc = ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, priority:priority)
		
		proc.stdin = standardIn
		proc.stdout = standardOut
		proc.stderr = standardErr
		
		proc.terminationHandler = { [weak self] _ in
			defer {
				rg.leave()
			}
			dg.wait()
			guard let self = self else {
				return
			}
			syncQueue.sync {
				self.state = .exited
			}
		}
        
		stdout.readHandler = { [weak self] handleToRead in
			dg.enter()
			defer {
				dg.leave()
			}

			guard let self = self else {
				return
			}
			syncQueue.sync {
				let startBlock = StringStopwatch()
				if let newData = handleToRead.availableData() {
					print("stdout read was blocked for \(startBlock.click(5)) seconds")
					let bytesCount = newData.count
					if bytesCount > 0 {
						let bytesCopy = newData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
						self.stdoutBuff.append(bytesCopy)
					}
				}
			}
		}
	
		stderr.readHandler = { [weak self] handleToRead in
			dg.enter()
			defer {
				dg.leave()
			}
			
			guard let self = self else {
				return
			}
			syncQueue.sync {
				if let newData = handleToRead.availableData() {
					let bytesCount = newData.count
					if bytesCount > 0 {
						let bytesCopy = newData.withUnsafeBytes({ return Data(bytes:$0, count:bytesCount) })
						self.stderrBuff.append(bytesCopy)
					}
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
        try queue.sync {
            do {
            	runGroup.enter()
				try proc.run()
                state = .running
            } catch let error {
            	runGroup.leave()
                state = .failed
                throw error
            }
        }
    }
	
	public func suspend() -> Bool? {
        return queue.sync {
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
        return queue.sync {
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
		return queue.sync {
			return stdoutBuff
		}
	}
	
	public func exportStdErr() -> Data {
		return queue.sync {
			return stderrBuff
		}
	}

    public func waitForExitCode() -> Int {
		runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

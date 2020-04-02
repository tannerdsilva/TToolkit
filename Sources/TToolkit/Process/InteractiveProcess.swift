import Foundation


fileprivate let ipSync = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = (InteractiveProcess) -> Void
    
	private let internalSync:DispatchQueue				//what serial thread is going to be used to process the data for each class instance?
	private let internalCallback:DispatchQueue
	
    public let priority:Priority				//what is the priority of this interactive process. most (if not all) of the asyncronous work for this process and others will be based on this Priority
    
    private let runGroup:DispatchGroup			//used to signify that the object is still "working"
    
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
        	return internalSync.sync {
        		return _stdoutHandler
        	}
        }
        set {
            internalSync.sync {
                _stdoutHandler = newValue
            }
        }
    }
    
    private var _stderrHandler:OutputHandler? = nil
    public var stderrHandler:OutputHandler? {
        get {
        	return internalSync.sync {
				return _stderrHandler
        	}   
        }
        set {
            internalSync.sync {
                _stderrHandler = newValue
            }
        }
    }
    
    private var _stdinHandler:InputHandler? = nil
    public var stdinHandler:InputHandler? {
    	get {
    		return internalSync.sync {
    			return _stdinHandler
    		}
    	}
    	set {
    		return internalSync.sync {
    			_stdinHandler = newValue
    		}
    	}
    }

    public init<C>(command:C, priority:Priority = .`default`, run:Bool) throws where C:Command {
    	self.priority = priority

		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", qos:priority.asDispatchQoS(), target:ipSync)
		let callbackQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.callback", qos:priority.asDispatchQoS(), target:priority.globalConcurrentQueue)

		self.internalSync = syncQueue
		self.internalCallback = callbackQueue
		
		let rg = DispatchGroup()
		
		runGroup = rg
				
		//create the ProcessHandles that we need to read the data from this process as it runs
		let standardIn = try ProcessPipes(priority:priority, callback:syncQueue)
		let standardOut = try ProcessPipes(priority:priority, callback:syncQueue)
		let standardErr = try ProcessPipes(priority:priority, callback:syncQueue)
		stdin = standardIn
		stdout = standardOut
		stderr = standardErr
		
		//create the ExecutingProcess
		proc = ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, priority:priority, callback:syncQueue)
		
		proc.stdin = standardIn
		proc.stdout = standardOut
		proc.stderr = standardErr
		print("th")

		proc.terminationHandler = { [weak self] _ in
			guard let self = self else {
				return
			}
			self.state = .exited
		}
        
		print("rh")
		stdout.readHandler = { [weak self] newData in
			var newLine = false
			print("attempting to read")
			newData.withUnsafeBytes({ byteBuff in
				if let hasBase = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
					for i in 0..<newData.count {
						switch hasBase.advanced(by:i).pointee {
							case 10, 13:
								newLine = true
							default:
							break;
						}
					}
				}
			})
			guard let self = self else {
				return
			}
			self.stdoutBuff.append(newData)
			if newLine == true, var parsedLines = self.stdoutBuff.lineSlice(removeBOM:false) {
				let tailData = parsedLines.removeLast()
				self.stdoutBuff.removeAll(keepingCapacity:true)
				self.stdoutBuff.append(tailData)
				self._scheduleOutCallback(lines:parsedLines)
			}
		}
	
		print("errh")
		stderr.readHandler = { [weak self] newData in
			var newLine = false
			print("attempting to read")
			newData.withUnsafeBytes({ byteBuff in
				if let hasBase = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
					for i in 0..<newData.count {
						switch hasBase.advanced(by:i).pointee {
							case 10, 13:
								newLine = true
							default:
							break;
						}
					}
				}
			})
			guard let self = self else {
				return
			}
			self.stderrBuff.append(newData)
			if newLine == true, var parsedLines = self.stderrBuff.lineSlice(removeBOM:false) {
				let tailData = parsedLines.removeLast()
				self.stderrBuff.removeAll(keepingCapacity:true)
				self.stderrBuff.append(tailData)
				self._scheduleErrCallback(lines:parsedLines)
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
    
    fileprivate func _scheduleOutCallback(lines:[Data]) {
    	guard let outHandle = _stdoutHandler else {
    		return
    	}
    	internalCallback.async { [weak self] in
    		guard let self = self else {
    			return
    		}
    		for (_, curLine) in lines.enumerated() {
    			outHandle(curLine)
    		}
    	}
    }
    
	fileprivate func _scheduleErrCallback(lines:[Data]) {
    	guard let errHandle = _stderrHandler else {
    		return
    	}
    	internalCallback.async { [weak self] in
    		guard let self = self else {
    			return
    		}
    		for (_, curLine) in lines.enumerated() {
    			errHandle(curLine)
    		}
    	}
    }

    
    public func run() throws {
        try internalSync.sync(flags:[.inheritQoS]) {
            print("trying to run")
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
        return internalSync.sync(flags:[.inheritQoS]) {
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
        return internalSync.sync(flags:[.inheritQoS]) {
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
		return internalSync.sync(flags:[.inheritQoS]) {
			return stdoutBuff
		}
	}
	
	public func exportStdErr() -> Data {
		return internalSync.sync(flags:[.inheritQoS]) {
			return stderrBuff
		}
	}

    public func waitForExitCode() -> Int {
    	runGroup.enter()
		runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

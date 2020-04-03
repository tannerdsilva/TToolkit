import Foundation


fileprivate let ipSync = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = (InteractiveProcess) -> Void
    
    private let masterQueue:DispatchQueue
    
	private let internalSync:DispatchQueue				//what serial thread is going to be used to process the data for each class instance?
	private let internalCallback:DispatchQueue
	    
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

    public init<C>(command:C, run:Bool) throws where C:Command {
print("init yay")
		let masterQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.master", attributes:[.concurrent], target:ipSync)
		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", target:masterQueue)
		let callbackQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.callback", target:masterQueue)
		
		self.masterQueue = masterQueue
		
		self.internalSync = syncQueue
		self.internalCallback = callbackQueue
		
		let rg = DispatchGroup()
		
		runGroup = rg
				
		//create the ProcessHandles that we need to read the data from this process as it runs
		let standardIn = try ProcessPipes(callback:syncQueue)
		let standardOut = try ProcessPipes(callback:syncQueue)
		let standardErr = try ProcessPipes(callback:syncQueue)
		stdin = standardIn
		stdout = standardOut
		stderr = standardErr
		
		//create the ExecutingProcess
		proc = ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, callback:syncQueue)
		
		proc.stdin = standardIn
		proc.stdout = standardOut
		proc.stderr = standardErr

		proc.terminationHandler = { [weak self] _ in
			guard let self = self else {
				return
			}
			
			let barrierWork = DispatchWorkItem(qos:Priority.high.asDispatchQoS(), flags:[.barrier, .enforceQoS], block: { [weak self] in
				guard let self = self else {
					return
				}
				self.state = .exited
				rg.leave()
			})
			self.masterQueue.async(execute:barrierWork)
		}
        print("?")
		stdout.readHandler = { [weak self] newData in
			print("rh")
			var newLine = false
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
		print("??")
		stderr.readHandler = { [weak self] newData in
			print("errh")
			var newLine = false
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
		print("????")
		        
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
    	print("trying to run")
    	try internalSync.sync {
			runGroup.enter()
			do {
				print("Running")
				try proc.run()
				state = .running
			} catch let error {
				runGroup.leave()
				state = .failed
			}
		}
    }
	
	public func suspend() -> Bool? {
        return internalSync.sync {
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
        return internalSync.sync {
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
		return internalSync.sync {
			return stdoutBuff
		}
	}
	
	public func exportStdErr() -> Data {
		return internalSync.sync {
			return stderrBuff
		}
	}

    public func waitForExitCode() -> Int {
		runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

import Foundation

fileprivate let ioQueue:DispatchQueue = DispatchQueue(label:"com.tannersilva.global.process-interactive.pipe-io-proc", qos:Priority.highest.asDispatchQoS(), attributes:[.concurrent])

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = (InteractiveProcess) -> Void
    
    private let masterQueue:DispatchQueue
    
    public let priority:Priority				//what is the priority of this interactive process. most (if not all) of the asyncronous work for this process and others will be based on this Priority
    private let internalSync:DispatchQueue		//what serial thread is going to be used to process the data for each class instance?
    private let internalCallback:DispatchQueue	//this is the queue that calls the handlers that the user assigned
    
    private let runGroup:DispatchGroup
    
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
	
	internal var stdoutBuff = Data()
	internal var stderrBuff = Data()

	internal let proc:ExecutingProcess
	public var state:State = .initialized
    
    private var _callbackQueue:DispatchQueue
    public var callbackQueue:DispatchQueue {
    	get {
    		return internalSync.sync {
    			return _callbackQueue
    		}
    	}
    	set {
    		internalSync.sync {
    			_callbackQueue = newValue
    			internalCallback.setTarget(queue:_callbackQueue)
    		}
    	}
    }
    
    /*
    	The stdout handler is called every time a new line is detected 
    */
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

    public init<C>(command:C, priority:Priority = .`default`) throws where C:Command {
    	self.priority = priority
    	let master = DispatchQueue(label:"com.tannersilva.instance.process-interactive.master", qos:priority.asDispatchQoS(), attributes:[.concurrent])
    	self.masterQueue = master
    	
    	let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", qos:priority.asDispatchQoS(), target:master)
    	let callbackQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.callback", qos:priority.asDispatchQoS(), target:master)
    	let ioInternal = DispatchQueue(label:"com.tannersilva.instance.process-interactive.io", target:ioQueue)
    	let rg = DispatchGroup()
    	
		self.internalSync = syncQueue
		self.internalCallback = callbackQueue
		self._callbackQueue = callbackQueue
		
		self.runGroup = rg
		
		//create the ProcessHandles that we need to read the data from this process as it runs
		let standardIn = try ProcessPipes(queue:ioInternal)
		let standardOut = try ProcessPipes(queue:ioInternal)
		let standardErr = try ProcessPipes(queue:ioInternal)
		stdin = standardIn
		stdout = standardOut
		stderr = standardErr
		
		//create the ExecutingProcess
		proc = ExecutingProcess(priority:priority, execute:command.executable, arguments:command.arguments, environment:command.environment)
		
		proc.stdin = standardIn
		proc.stdout = standardOut
		proc.stderr = standardErr
		
		proc.terminationHandler = { [weak self] _ in
			ioInternal.async { [weak self] in
				guard let self = self else {
					return
				}
				//close file handles if they exist
				self.stdin.close()
				self.stdout.close()
				self.stderr.close()
				syncQueue.async { [weak self] in
					guard let self = self else {
						return
					}
					self._finishStdoutLines()
					self._finishStderrLines()
					self.state = .exited
					let rg = self.runGroup
					self.internalCallback.async {
						rg.leave()
					}
				}
			}
		}
        
		stdout.readHandler = { [weak self] handleToRead in
			//try to read the data. do we get something?
			if let newData = handleToRead.availableData() {
				let bytesCount = newData.count
				
				//do we have bytes to take action on?
				if bytesCount > 0 {				
					//parse the buffer of unsafe bytes for an endline
					var shouldLineSlice = false
					newData.withUnsafeBytes({ byteBuff -> Void in
						if let hasBaseAddress = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
							for i in 0..<bytesCount {
								switch hasBaseAddress.advanced(by:i).pointee {
									case 10, 13:
										shouldLineSlice = true
									default:
									break;
								}
							}
						}
					})

					syncQueue.async { [weak self] in
						guard let self = self else {
							return
						}
						self._buildStdout(data:newData, lineSlice:shouldLineSlice)
					}
				}
			}
		}
	
		stderr.readHandler = { [weak self] handleToRead in
			//try to read the data. do we get something?
			if let newData = handleToRead.availableData() {
				let bytesCount = newData.count
				
				//does this data have bytes that we can take action on?
				if bytesCount > 0 {
					//parse the buffer of unsafe bytes for an endline
					var shouldLineSlice = false
					newData.withUnsafeBytes({ byteBuff -> Void in
						if let hasBaseAddress = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
							for i in 0..<bytesCount {
								switch hasBaseAddress.advanced(by:i).pointee {
									case 10, 13:
										shouldLineSlice = true
									default:
									break;
								}
							}
						}
					})

					syncQueue.async { [weak self] in
						guard let self = self else {
							return
						}
						self._buildStderr(data:newData, lineSlice:shouldLineSlice)
					}
				}
			}
		}
    }
    
    public func run() throws {
    	try internalSync.sync {
			do {
				runGroup.enter()
				try proc._run()
				state = .running
			} catch let error {
				runGroup.leave()
				state = .failed
				throw error
			}
		}
    }
	
	public func suspend() -> Bool? {
        return internalSync.sync {
            if state == .running {
                if proc._suspend() == true {
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
                if proc._resume() == true {
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
	
	private func callbackStdout(lines:[Data]) {
		internalCallback.async { [weak self] in
			guard let self = self, let outHandler = self.stdoutHandler else {
				return
			}
			for (_, curLine) in lines.enumerated() {
				outHandler(curLine)
			}
		}
	}
	
	private func callbackStderr(lines:[Data]) {
		internalCallback.async { [weak self] in
			guard let self = self, let errHandler = self.stderrHandler else {
				return
			}
			for (_, curLine) in lines.enumerated() {
				errHandler(curLine)
			}
		}
	}
	
	private func _buildStdout(data:Data, lineSlice:Bool) {
		stdoutBuff.append(data)
		if lineSlice == true, var slicedLines = stdoutBuff.lineSlice(removeBOM:false) {
			let lastDataLine = slicedLines.removeLast()
			stdoutBuff.removeAll(keepingCapacity:true)
			stdoutBuff.append(lastDataLine)
			callbackStdout(lines:slicedLines)
		}
	}
	
	private func _buildStderr(data:Data, lineSlice:Bool) {
		stderrBuff.append(data)
		if lineSlice == true, var slicedLines = stderrBuff.lineSlice(removeBOM:false) {
			let lastDataLine = slicedLines.removeLast()
			stderrBuff.removeAll(keepingCapacity:true)
			stderrBuff.append(lastDataLine)
			callbackStderr(lines:slicedLines)
		}
	}
	
	private func _finishStdoutLines() {
		if var slicedLines = stdoutBuff.lineSlice(removeBOM:false), let outHandler = _stdoutHandler {
			callbackStdout(lines:slicedLines)
			stdoutBuff.removeAll(keepingCapacity:false)
			callbackQueue.async {
				for (_, curLine) in slicedLines.enumerated() {
					outHandler(curLine)
				}
			}
		}
	}
	
	private func _finishStderrLines() {
		if var slicedLines = stderrBuff.lineSlice(removeBOM:false), let errHandler = _stderrHandler {
			callbackStderr(lines:slicedLines)
			stderrBuff.removeAll(keepingCapacity:false)
			callbackQueue.async {
				for (_, curLine) in slicedLines.enumerated() {
					errHandler(curLine)
				}
			}
		}
	}
		
    public func waitForExitCode() -> Int {
		runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

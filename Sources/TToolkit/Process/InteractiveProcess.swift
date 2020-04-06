import Foundation

public class InteractiveProcess {
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = () -> Void

    fileprivate static let globalQueue = DispatchQueue(label:"com.tannersilva.global.process", qos:maximumPriority, attributes:[.concurrent])
	
	/*
	I/O events for the interactive process are handled in an asyncronous queue that calls into two secondary syncronous queues (one for internal handling, the other for callback handling
	*/
 	private let internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync", target:globalQueue)
	private let ioQueue:DispatchQueue	//not initialized here because it is qos dependent (qos passed to initializer)
	private let ioGroup:DispatchGroup
	private let callbackSync = DispatchQueue(label:"com.tannersilva.instance.process.callback.sync", target:globalQueue)
	private let runGroup:DispatchGroup
	
	public enum InteractiveProcessState:UInt8 {
		case initialized
		case running
		case suspended
		case exited
		case failed
	}
	private var _state:InteractiveProcessState
	public var state:InteractiveProcessState {
		get {
			return internalSync.sync {
				return _state
			}
		}
	}
	
	internal var stdin:ProcessPipes
	internal var stdout:ProcessPipes
	internal var stderr:ProcessPipes
	
	internal var _stdoutBuffer = Data()
	public var stdoutBuffer:Data {
		get {
			return internalSync.sync {
				return _stdoutBuffer
			}
		}
	}
	
	internal var _stderrBuffer = Data()
	public var stderrBuffer:Data {
		get {
			return internalSync.sync {
				return _stderrBuffer
			}
		}
	}
	
	internal let proc:ExecutingProcess
	
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
			internalSync.sync {
				_stdinHandler = newValue
			}
		}
	}
	
	public init<C>(command:C, priority:Priority, run:Bool) throws where C:Command {
		let ioq = DispatchQueue(label:"com.tannersilva.instance.process.interactive.io", qos:priority.asDispatchQoS(relative:300), attributes:[.concurrent], target:Self.globalQueue)
		let iog = DispatchGroup()
		
		self.ioQueue = ioq
		self.ioGroup = iog
		self._state = .initialized
		
		let input = try ProcessPipes(callback:ioq, group:iog)
		let output = try ProcessPipes(callback:ioq, group:iog)
		let err = try ProcessPipes(callback:ioq, group:iog)
		
		self.stdin = input
		self.stdout = output
		self.stderr = err
		
		let externalProcess = try ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, callback:ioQueue)
		self.proc = externalProcess
        self.runGroup = DispatchGroup()
        
		externalProcess.stdin = input
		externalProcess.stdout = output
		externalProcess.stderr = err
		
		let termHandle = DispatchWorkItem(flags:[.barrier, .inheritQoS]) { [weak self] in
			guard let self = self else {
				return
			}
			print("yay term totally called")
			input.close()
			output.close()
			err.close()
			
			iog.wait()
			
			self.internalSync.sync {
				self._state = .exited
				self.runGroup.leave()
			}
		}
		externalProcess.terminationHandler = termHandle
		
		output.readHandler = { [weak self] someData in
			guard let self = self else {
				return
			}
			if let hasLines = self.incomingStdout(someData) {
				self.callbackStdout(lines:hasLines)
			}
		}
		
		err.readHandler = { [weak self] someData in
			guard let self = self else {
				return
			}
			if let hasLines = self.incomingStderr(someData) {
				self.callbackStderr(lines:hasLines)
			}
		}
	}
	
	fileprivate func callbackStderr(lines:[Data]) {
		if let hasCallback = stderrHandler {
			callbackSync.sync {
				for (_, curLine) in lines.enumerated() {
					hasCallback(curLine)
				}
			}
		}
	}
	
	fileprivate func callbackStdout(lines:[Data]) {
		if let hasCallback = stdoutHandler {
			callbackSync.sync {
				for (_, curLine) in lines.enumerated() {
					hasCallback(curLine)
				}
			}
		}
	}
	
	fileprivate func incomingStdout(_ inputData:Data) -> [Data]? {
		return inputData.withUnsafeBytes { unsafeRawBufferPointer in
			let boundBuffer = unsafeRawBufferPointer.bindMemory(to:UInt8.self)
			let hasEndline = boundBuffer.contains(where: { $0 == 10 || $0 == 13 })
			var completeLines:[Data]? = internalSync.sync {
				_stdoutBuffer.append(boundBuffer)
				if hasEndline == true, var parsedLines = self._stdoutBuffer.lineSlice(removeBOM:false) {
					let tailData = parsedLines.removeLast()
					self._stdoutBuffer.removeAll(keepingCapacity:true)
					self._stdoutBuffer.append(tailData)
					return parsedLines
				} else {
					return nil
				}
			}
			return completeLines
		}
	}
	
	fileprivate func incomingStderr(_ inputData:Data) -> [Data]? {
		return inputData.withUnsafeBytes { unsafeRawBufferPointer in
			let boundBuffer = unsafeRawBufferPointer.bindMemory(to:UInt8.self)
			let hasEndline = boundBuffer.contains(where: { $0 == 10 || $0 == 13 })
			var completeLines:[Data]? = internalSync.sync {
				_stderrBuffer.append(boundBuffer)
				if hasEndline == true, var parsedLines = self.stderrBuffer.lineSlice(removeBOM:false) {
					let tailData = parsedLines.removeLast()
					self._stderrBuffer.removeAll(keepingCapacity:true)
					self._stderrBuffer.append(tailData)
					return parsedLines
				} else {
					return nil
				}
			}
            return completeLines
		}
	}
    
    public func run() throws {
        try internalSync.sync {
            runGroup.enter()
            do {
                try proc.run()
                _state = .running
            } catch let error {
                runGroup.leave()
                _state = .failed
            }
        }
    }
    
    public func waitForExitCode() -> Int {
        runGroup.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
}

//public class InteractiveProcess {
//    public typealias OutputHandler = (Data) -> Void
//    public typealias InputHandler = (InteractiveProcess) -> Void
//
//    fileprivate static let globalQueue = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", qos:maximumPriority, attributes:[.concurrent])
//
//    private let masterQueue:DispatchQueue
//
//    private var ioEvents:DispatchQueue
//    private var internalSync:DispatchQueue
//
//	private let internalSync:DispatchQueue				//what serial thread is going to be used to process the data for each class instance?
//	private let internalCallback:DispatchQueue
//
//    private let runGroup:DispatchGroup			//used to signify that the object is still "working"
//
//	public enum State:UInt8 {
//		case initialized = 0
//		case running = 1
//		case suspended = 2
//		case exited = 4
//		case failed = 5
//	}
//
//	internal var stdin:ProcessPipes
//	internal var stdout:ProcessPipes
//	internal var stderr:ProcessPipes
//
//	public var stdoutBuff = Data()
//	public var stderrBuff = Data()
//
//	internal let proc:ExecutingProcess
//	public var state:State = .initialized
//
//    private var _stdoutHandler:OutputHandler? = nil
//    public var stdoutHandler:OutputHandler? {
//        get {
//        	return internalSync.sync {
//        		return _stdoutHandler
//        	}
//        }
//        set {
//            internalSync.sync {
//                _stdoutHandler = newValue
//            }
//        }
//    }
//
//    private var _stderrHandler:OutputHandler? = nil
//    public var stderrHandler:OutputHandler? {
//        get {
//        	return internalSync.sync {
//				return _stderrHandler
//        	}
//        }
//        set {
//            internalSync.sync {
//                _stderrHandler = newValue
//            }
//        }
//    }
//
//    private var _stdinHandler:InputHandler? = nil
//    public var stdinHandler:InputHandler? {
//    	get {
//    		return internalSync.sync {
//    			return _stdinHandler
//    		}
//    	}
//    	set {
//    		return internalSync.sync {
//    			_stdinHandler = newValue
//    		}
//    	}
//    }
//
//    public init<C>(command:C, run:Bool) throws where C:Command {
//
//    	let masterQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.master", attributes:[.concurrent], target:ipSync)
////		print("init yay")
////		let masterQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.master", attributes:[.concurrent], target:ipSync)
////		let syncQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.sync", target:masterQueue)
////		let callbackQueue = DispatchQueue(label:"com.tannersilva.instance.process-interactive.callback", target:masterQueue)
////
////		self.masterQueue = masterQueue
////
////		self.internalSync = syncQueue
////		self.internalCallback = callbackQueue
////
////		let rg = DispatchGroup()
////
////		runGroup = rg
////
//		//create the ProcessHandles that we need to read the data from this process as it runs
//		let standardIn = try ProcessPipes(callback:syncQueue)
//		let standardOut = try ProcessPipes(callback:syncQueue)
//		let standardErr = try ProcessPipes(callback:syncQueue)
//		stdin = standardIn
//		stdout = standardOut
//		stderr = standardErr
//
//		//create the ExecutingProcess
//		proc = ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment, callback:syncQueue)
//
//		proc.callbackQueue =
//		proc.stdin = standardIn
//		proc.stdout = standardOut
//		proc.stderr = standardErr
//
//		let terminationWorkItem = DispatchWorkItem(
//		proc.terminationHandler = { [weak self] _ in
//			guard let self = self else {
//				return
//			}
//			print(Colors.red("term handle"))
//			let barrierWork = DispatchWorkItem(flags:[.barrier, .enforceQoS], block: { [weak self] in
//				guard let self = self else {
//					return
//				}
//				self.state = .exited
//				rg.leave()
//			})
//			self.masterQueue.sync(execute:barrierWork)
//		}
//		stdout.readHandler = { [weak self] newData in
//			var newLine = false
//			newData.withUnsafeBytes({ byteBuff in
//				if let hasBase = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
//					for i in 0..<newData.count {
//						switch hasBase.advanced(by:i).pointee {
//							case 10, 13:
//								newLine = true
//							default:
//							break;
//						}
//					}
//				}
//			})
//			guard let self = self else {
//				return
//			}
//			self.stdoutBuff.append(newData)
//			if newLine == true, var parsedLines = self.stdoutBuff.lineSlice(removeBOM:false) {
//				let tailData = parsedLines.removeLast()
//				self.stdoutBuff.removeAll(keepingCapacity:true)
//				self.stdoutBuff.append(tailData)
//				self._scheduleOutCallback(lines:parsedLines)
//			}
//		}
//		print("??")
//		stderr.readHandler = { [weak self] newData in
//			print("errh")
//			var newLine = false
//			newData.withUnsafeBytes({ byteBuff in
//				if let hasBase = byteBuff.baseAddress?.assumingMemoryBound(to:UInt8.self) {
//					for i in 0..<newData.count {
//						switch hasBase.advanced(by:i).pointee {
//							case 10, 13:
//								newLine = true
//							default:
//							break;
//						}
//					}
//				}
//			})
//			guard let self = self else {
//				return
//			}
//			self.stderrBuff.append(newData)
//			if newLine == true, var parsedLines = self.stderrBuff.lineSlice(removeBOM:false) {
//				let tailData = parsedLines.removeLast()
//				self.stderrBuff.removeAll(keepingCapacity:true)
//				self.stderrBuff.append(tailData)
//				self._scheduleErrCallback(lines:parsedLines)
//			}
//		}
//		print("????")
//
//		if run {
//            do {
//                try self.run()
//            } catch let error {
//                throw error
//            }
//		}
//    }
//
//    fileprivate func _scheduleOutCallback(lines:[Data]) {
//    	guard let outHandle = _stdoutHandler else {
//    		return
//    	}
//    	internalCallback.async { [weak self] in
//    		guard let self = self else {
//    			return
//    		}
//    		for (_, curLine) in lines.enumerated() {
//    			outHandle(curLine)
//    		}
//    	}
//    }
//
//	fileprivate func _scheduleErrCallback(lines:[Data]) {
//    	guard let errHandle = _stderrHandler else {
//    		return
//    	}
//    	internalCallback.async { [weak self] in
//    		guard let self = self else {
//    			return
//    		}
//    		for (_, curLine) in lines.enumerated() {
//    			errHandle(curLine)
//    		}
//    	}
//    }
//
//    public func run() throws {
//    	print("trying to run")
//    	try internalSync.sync {
//			runGroup.enter()
//			do {
//				print("Running")
//				try proc.run()
//				state = .running
//			} catch let error {
//				runGroup.leave()
//				state = .failed
//			}
//		}
//    }
//
//	public func suspend() -> Bool? {
//        return internalSync.sync {
//            if state == .running {
//                if proc.suspend() == true {
//                    state = .suspended
//                    return true
//                } else {
//                    state = .running
//                    return false
//                }
//            } else {
//                return nil
//            }
//        }
//    }
//
//	public func resume() -> Bool? {
//        return internalSync.sync {
//            if state == .suspended {
//                if proc.resume() == true {
//                    state = .running
//                    return true
//                } else {
//                    state = .suspended
//                    return false
//                }
//            } else {
//                return nil
//            }
//        }
//	}
//
//	public func exportStdOut() -> Data {
//		return internalSync.sync {
//			return stdoutBuff
//		}
//	}
//
//	public func exportStdErr() -> Data {
//		return internalSync.sync {
//			return stderrBuff
//		}
//	}
//
//    public func waitForExitCode() -> Int {
//		runGroup.wait()
//        let returnCode = proc.exitCode!
//        return Int(returnCode)
//    }
//}

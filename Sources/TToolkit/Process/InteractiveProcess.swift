import Foundation

internal class DebugProcessMonitor {
	
//    let eventPipe:ProcessPipes
    
	let internalSync = DispatchQueue(label:"com.tannersilva.process.monitor.sync")
	
	var announceTimer:TTimer
	var processHashes = [InteractiveProcess:Int]()
	
	var engagements = Set<Int32>()
	var disengagements = Set<Int32>()
	
    var processBytes = [InteractiveProcess:Int]()
    
	var processes = [InteractiveProcess:Date]()
	var sortedProcesses:[(key:InteractiveProcess, value:Date)] {
		get {
			return processes.sorted(by: { $0.value > $1.value })
		}
	}
	
	init() {
		announceTimer = TTimer()
		announceTimer.duration = 5
		announceTimer.handler = { [weak self] _ in
			guard let self = self else {
				return
			}
			self.internalSync.sync {
				let sortedProcs = self.sortedProcesses
				for (_, curProcess) in sortedProcs.enumerated() {
					print(Colors.Cyan("\(curProcess.key._uniqueID)\t\t"), terminator:"")
					print(Colors.blue("\(curProcess.key.processIdentifier)\t\t"), terminator:"")
					print(Colors.yellow("\(curProcess.value.timeIntervalSinceNow)\t"), terminator:"")
					let hash = curProcess.key.dhash
					if let hasHash = self.processHashes[curProcess.key] {
						if hasHash != hash {
							print(Colors.green("\(curProcess.key.dhash)\t"), terminator:"")
						} else {
							print(Colors.dim("\(curProcess.key.dhash)\t"), terminator:"")
						}
						self.processHashes[curProcess.key] = hash
					} else {
						print(Colors.red("\(curProcess.key.dhash)\t"), terminator:"")
						self.processHashes[curProcess.key] = hash					
					}
					let pid = curProcess.key.processIdentifier
					if (self.engagements.contains(pid)) {
						print(Colors.Magenta("E\t"), terminator:"")
					} else if self.disengagements.contains(pid) {
						print(Colors.Red("D!\t"), terminator:"")
					}
                    print(Colors.green("\(curProcess.key.lines.count)\t"), terminator:"")
                    print(Colors.yellow("\(self.processBytes[curProcess.key])\t"), terminator:"\n")
				}
				print(Colors.Blue("There are \(self.processes.count) processes in flight"))
			}
		}
		announceTimer.activate()
	}
	
	func exiterEngaged(_ p:Int32) {
		internalSync.sync {
			engagements.update(with:p)
		}
	}
	
	func exiterDisengaged(_ p:Int32) {
		internalSync.sync {
			engagements.remove(p)
			disengagements.update(with:p)
		}
	}
	
    func processGotBytes(_ p:InteractiveProcess, bytes:Int) {
        internalSync.sync {
            if let hasExistingBytes = processBytes[p] {
                processBytes[p] = hasExistingBytes + bytes
            } else {
                processBytes[p] = bytes
            }
        }
        
    }
    
	func processLaunched(_ p:InteractiveProcess) {
		internalSync.sync {
			processes[p] = Date()
            processBytes[p] = 0
		}
	}
	
	func processEnded(_ p:InteractiveProcess) {
		internalSync.sync {
			processes[p] = nil
            processBytes[p] = nil
		}
	}
}

internal let pmon = DebugProcessMonitor()

public class InteractiveProcess:Hashable {
    private var _priority:Priority
    
	private var _id = UUID()
	internal var _uniqueID:String {
		get {
			return _id.uuidString
		}
	}
	internal var processIdentifier:Int32 {
		get {
			return internalSync.sync {
				return proc?.processIdentifier ?? -1
			}
		}
	}
	
	internal var dhash:Int = 0
	
	public func hash(into hasher:inout Hasher) {
		hasher.combine(_uniqueID)
	}
	
	public static func == (lhs:InteractiveProcess, rhs:InteractiveProcess) -> Bool {
		return lhs._id == rhs._id
	}
	
    public typealias OutputHandler = (Data) -> Void
    public typealias InputHandler = () -> Void

	/*
	I/O events for the interactive process are handled in an asyncronous queue that calls into two secondary syncronous queues (one for internal handling, the other for callback handling
	*/
    private let internalSync:DispatchQueue
    
    private let runSemaphore:DispatchSemaphore
    private var signalUp:Bool = false
    
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
	
	private var _status:String = ""
	internal var status:String {
		get {
			return internalSync.sync {
				return _status
			}
		}
	}
	
    internal var ioGroup:DispatchGroup = DispatchGroup()
    
	internal var stdin:ProcessPipes? = nil
	internal var stdout:ProcessPipes? = nil
	internal var stderr:ProcessPipes? = nil
	
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
	
	internal var proc:ExecutingProcess? = nil
	
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
    
    var lines = [Data]() 
	
    public init<C>(command:C, priority:Priority, run:Bool, workingDirectory:URL) throws where C:Command {
        self._priority = priority
        self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync")
        let rs = DispatchSemaphore(value:0)
        let inputSerial = DispatchQueue(label:"footest", qos:priority.asDispatchQoS())
        
		self.runSemaphore = rs
		self._state = .initialized
                
        let externalProcess = try ExecutingProcess(execute:command.executable, arguments:command.arguments, workingDirectory: workingDirectory)

        let input = try ProcessPipes(read:inputSerial)
        let output = try ProcessPipes(read:inputSerial)
        let err = try ProcessPipes(read:inputSerial)
        
		self.internalSync.sync {
            self.proc = externalProcess
            self.stdin = input
            self.stdout = output
            self.stderr = err
        }

        externalProcess.stdin = input
        externalProcess.stdout = output
        externalProcess.stderr = err
        externalProcess.terminationHandler = { [weak self] exitedProcess in
            inputSerial.async { [weak self] in
				guard let self = self else {
					return
				}
				print(Colors.Red("Exit handler ran"))
				pmon.processEnded(self)
				self.runSemaphore.signal()
			}
        }
        
        output.readHandler = { [weak self] someData in
            guard let self = self else {
                return
            }
            self.internalSync.sync {
                self.lines.append(someData)
            }
            if let hasReadHandler = self.stdoutHandler {
                hasReadHandler(someData)
            }
        }
    
       err.readHandler = { [weak self] someData in
           guard let self = self else {
               return
           }
            self.internalSync.sync {
                self.lines.append(someData)
            }
           if let hasReadHandler = self.stderrHandler {
               hasReadHandler(someData)
           }
       }
    }
    
    public func run() throws {
        let runWait = DispatchSemaphore(value:0)
        let runItem = DispatchWorkItem(qos:_priority.process_launch_priority, flags:[.enforceQoS]) { [weak self] in
            defer {
                runWait.signal()
            }
            guard let self = self else {
                return
            }
            do {
                pmon.processLaunched(self)
                try self.proc!.run(sync:false)
                self.internalSync.sync {
                    self._state = .running
                }
            } catch let error {
                self.internalSync.sync {
                    self.signalUp = false
                    self._state = .failed
                }
                self.runSemaphore.signal()
            }
        }
        process_launch_async_fast.async(execute:runItem)
        runWait.wait()
    }
    
    public func waitForExitCode() -> Int {
        runSemaphore.wait()
        let returnCode = proc!.exitCode!
        return Int(returnCode)
    }
    
    deinit {
        let signalSafeCheck = self.internalSync.sync(execute: { return self.signalUp })
    	print(Colors.yellow("ip was deinit"))
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

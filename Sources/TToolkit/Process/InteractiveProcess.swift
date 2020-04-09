import Foundation


internal class ProcessMonitor {
	
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

internal let pmon = ProcessMonitor()

public class InteractiveProcess:Hashable {
	private var _id = UUID()
	internal var _uniqueID:String {
		get {
			return _id.uuidString
		}
	}
	internal var processIdentifier:Int32 {
		get {
			return internalSync.sync {
				return proc.processIdentifier ?? 0
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
    private let process_launch_queue:DispatchQueue
    private let process_read_queue:DispatchQueue
    private let process_write_queue:DispatchQueue
    private let process_callback_queue:DispatchQueue

    private let runSemaphore:DispatchSemaphore
    private var signalUp:Bool = true
    
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
    
    var lines = [Data]() 
	
	public init<C>(command:C, priority:Priority, run:Bool) throws where C:Command {
        internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync", target:global_lock_queue)
//        let localMaster = DispatchQueue(label:"com.tannersilva.instance.process", qos:maximumPriority, attributes:[.concurrent], target:process_master_queue)
        process_launch_queue = DispatchQueue(label:"com.tannersilva.instance.process.launch", qos:priority.process_launch_priority, target:process_launch_async_fast)
        let eventStream = DispatchQueue(label:"com.tannersilva.instance.process.io", target:process_master_queue)
        process_read_queue = DispatchQueue(label:"com.tannersilva.instance.process.read", qos:priority.process_reading_priority, target:eventStream)
        process_write_queue = DispatchQueue(label:"com.tannersilva.instance.process.write", qos:priority.process_writing_priority, target:eventStream)
        process_callback_queue = DispatchQueue(label:"com.tannersilva.instance.process.callback", qos:priority.process_callback_priority, target:eventStream)
		
        let rs = DispatchSemaphore(value:1)
		
		self.runSemaphore = rs
		self._state = .initialized
		
		let input = try ProcessPipes()
		let output = try ProcessPipes()
		let err = try ProcessPipes()
		
		self.stdin = input
		self.stdout = output
		self.stderr = err
		let externalProcess = try ExecutingProcess(execute:command.executable, arguments:command.arguments, environment:command.environment)
		self.proc = externalProcess
		externalProcess.stdin = input
		externalProcess.stdout = output
		externalProcess.stderr = err
		
		let termHandle = DispatchWorkItem(flags:[.inheritQoS]) { [weak self] in
			guard let self = self else {
				return
			}
            print(Colors.red("EXIT"))
			input.close()
			output.close()
			err.close()
        }
        
        termHandle.notify(qos:priority.process_terminate_priority, flags:[.enforceQoS, .barrier], queue: eventStream, execute: { [weak self] in
            guard let self = self else {
                return
            }
            print(Colors.red("exit no"))
            
            let errLines = self.internalSync.sync { return self._finishStderr() }
            let outLines = self.internalSync.sync { return self._finishStdout() }
            
            if let hasErrLines = errLines, let hasCallback = self.stderrHandler {
                    for (_, curLine) in hasErrLines.enumerated() {
                        hasCallback(curLine)
                    }
            }
            
            if let hasOutLines = outLines, let hasCallback = self.stdoutHandler {
                for (_, curLine) in hasOutLines.enumerated() {
                    hasCallback(curLine)
                }
            }
            pmon.processEnded(self)
            self.runSemaphore.signal()
        })

		externalProcess.terminationHandler = termHandle

		let stderrWorkItem = DispatchWorkItem(flags:[.inheritQoS]) { [weak self] in
			guard let self = self else {
				return
			}
			var newLines:[Data]? = self.internalSync.sync {
				if var parsedLines = self._stderrBuffer.lineSlice(removeBOM:false) {
					let tailData = parsedLines.removeLast()
					self._stderrBuffer.removeAll(keepingCapacity:true)
					self._stderrBuffer.append(tailData)
					if parsedLines.count > 0 {
                        self.lines.append(contentsOf:parsedLines)
						return parsedLines
					} else {
						return nil
					}
				}
				return nil
			}
			if let hasNewLines = newLines, let hasCallback = self.stderrHandler {
				self.process_callback_queue.async {
					for (_, curLine) in hasNewLines.enumerated() {
						hasCallback(curLine)
					}
				}
			}
		}
		
		let stdoutWorkItem = DispatchWorkItem(flags:[.inheritQoS]) { [weak self] in
			guard let self = self else {
				return
			}
			var newLines:[Data]? = self.internalSync.sync {
				if var parsedLines = self._stdoutBuffer.lineSlice(removeBOM:false) {
					let tailData = parsedLines.removeLast()
					self._stdoutBuffer.removeAll(keepingCapacity:true)
					self._stdoutBuffer.append(tailData)
					if parsedLines.count > 0 {
                        self.lines.append(contentsOf:parsedLines)
						return parsedLines
					} else {
						return nil
					}
				}
				return nil
			}
			if let hasNewLines = newLines, let hasCallback = self.stdoutHandler {
				self.process_callback_queue.async {
					for (_, curLine) in hasNewLines.enumerated() {
						hasCallback(curLine)
					}
				}
			}
		}
		
		output.readHandler = { [weak self] someData in
			guard let self = self else {
				return
			}
            let count = someData.count
            pmon.processGotBytes(self, bytes: count)
			var hasher = Hasher()
			let currentHash = self.internalSync.sync { return self.dhash }
			let isNewLine = someData.withUnsafeBytes({ usRawBuffPoint -> Bool in
				hasher.combine(bytes:usRawBuffPoint)
				if usRawBuffPoint.contains(where: { $0 == 10 || $0 == 13 }) {
					return true
				}
				return false
			})
			hasher.combine(currentHash)
			self.internalSync.sync {
				self.dhash = hasher.finalize()
				self._stdoutBuffer.append(someData)
			}
			if isNewLine == true {
				self.process_read_queue.async(execute:stdoutWorkItem)
			}
		}

		err.readHandler = { [weak self] someData in
			guard let self = self else {
				return
			}
			var hasher = Hasher()
			let currentHash = self.internalSync.sync { return self.dhash }
			let isNewLine = someData.withUnsafeBytes({ usRawBuffPoint -> Bool in
				hasher.combine(bytes:usRawBuffPoint)
				if usRawBuffPoint.contains(where: { $0 == 10 || $0 == 13 }) {
					return true
				}
				return false
			})
			hasher.combine(currentHash)
			self.internalSync.sync {
				self.dhash = hasher.finalize()
				self._stderrBuffer.append(someData)
			}
			if isNewLine == true {
				self.process_read_queue.async(execute:stderrWorkItem)
			}
		}
	}
	
//	fileprivate func callbackStderr(lines:[Data]) {
//		if let hasCallback = stderrHandler {
//			callbackSync.async {
//				for (_, curLine) in lines.enumerated() {
//					hasCallback(curLine)
//				}
//			}
//		}
//	}
	
	
	fileprivate func _finishStdout() -> [Data]? {
		if var parsedLines = _stdoutBuffer.lineSlice(removeBOM:false) {
			self._stdoutBuffer.removeAll(keepingCapacity:false)
			if parsedLines.count > 0 {
				return parsedLines
			}
		}
		return nil
	}
	
	fileprivate func _finishStderr() -> [Data]? {
		if var parsedLines = _stderrBuffer.lineSlice(removeBOM:false) {
			self._stderrBuffer.removeAll(keepingCapacity:false)
			if parsedLines.count > 0 { 
				return parsedLines
			}
		}
		return nil
	}
    
    public func run() throws {
        runSemaphore.wait()
        process_launch_queue.async { [weak self] in
            guard let self = self else {
                return
            }
            self.internalSync.sync {
                do {
                    self.signalUp = false
                    self._status = "running"
                    pmon.processLaunched(self)
                    try? self.proc.run()
                    self._state = .running
                } catch let error {
                    self.signalUp = true
                    self.runSemaphore.signal()
                    self._state = .failed
                }
            }
        }
    }
    
    public func waitForExitCode() -> Int {
        runSemaphore.wait()
        let returnCode = proc.exitCode!
        return Int(returnCode)
    }
    
    deinit {
        let signalSafeCheck = self.internalSync.sync(execute: { return self.signalUp })
        if signalSafeCheck == true {
            self.runSemaphore.wait()
        }
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

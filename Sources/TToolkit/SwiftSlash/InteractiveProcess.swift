import Foundation

fileprivate let tt_spawn_sem = DispatchSemaphore(value:1)

//this class is only to be used when in debug mode. this will periodically output any processes that are in-flight and any relevant information about the process. relevant information include lines captured by the global readers and elapsed runtime thus far.
#if DEBUG
internal class DebugProcessMonitor {
    let internalSync = DispatchQueue(label:"com.tannersilva.process.monitor.sync", target:process_master_queue)
	
	var firstTime:Date? = nil
	var cumulativeTime:Double = 0
	
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
//					print(Colors.Cyan("\(curProcess.key._uniqueID)\t\t"), terminator:"")
					print(Colors.blue("\(curProcess.key.processIdentifier)\t\t"), terminator:"")
					print(Colors.yellow("\(curProcess.value.timeIntervalSinceNow)\t"), terminator:"")
					let hash = 0
					if let hasHash = self.processHashes[curProcess.key] {
						if hasHash != hash {
//							print(Colors.green("\(curProcess.key.dhash)\t"), terminator:"")
						} else {
//							print(Colors.dim("\(curProcess.key.dhash)\t"), terminator:"")
						}
						self.processHashes[curProcess.key] = hash
					} else {
//						print(Colors.red("\(curProcess.key.dhash)\t"), terminator:"")
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
				print(Colors.bgBlue("Speedup for \(self.processes.count) = \(self.cumulativeTime) -> \(self.firstTime?.timeIntervalSinceNow)"))
			}
		}
		announceTimer.activate()
	}
    
	func processLaunched(_ p:InteractiveProcess) {
		internalSync.sync {
			if processes.count == 0 {
				firstTime = Date()
			}
			processes[p] = Date()
            processBytes[p] = 0
		}
	}
	
	func processEnded(_ p:InteractiveProcess, runtime:Double) {
		internalSync.sync {
			cumulativeTime += runtime
			processes[p] = nil
            processBytes[p] = nil
		}
	}
}
internal let pmon = DebugProcessMonitor()
#endif

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
				return sig!.worker
			}
		}
	}

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

	//what are the standard inputs and outputs that are being used to capture this process?
	internal var stdin:Int32? = nil
	internal var stdout:Int32? = nil
	internal var stderr:Int32? = nil
	
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
	
	public var launchDate:Date? {
		get {
			return sig?.launch_time
		}
	}
	public var exitTime:Date? = nil
	
    
    internal var commandToRun:Command
    internal var wd:URL
    internal var sig:tt_proc_signature? = nil
    
    var lines = [Data]() 
    
    let runGroup = DispatchGroup()
    var exitCode:Int32 = 0
	
    public init<C>(command:C, workingDirectory:URL) throws where C:Command {
        self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync", target:process_master_queue)
        commandToRun = command
        wd = workingDirectory

		self._state = .initialized
    }
    
    public func run() throws {
    	do {
			runGroup.enter()
			try self.internalSync.sync {
				let launchedProcess = try tt_spawn(path:self.commandToRun.executable, args: self.commandToRun.arguments, wd:self.wd, env: self.commandToRun.environment, stdout:{ someData in
					self.lines.append(someData)
					self._stdoutHandler?(someData)
				}, stderr: { someData in
					self.lines.append(someData)
					self._stderrHandler?(someData)
				}, exitHandler: { exitCode in
					self.internalSync.async { [weak self, exitCode] in
						guard let self = self else {
							return
						}
						self.exitCode = exitCode
					}
					print("The process has exited with exit code \(exitCode)")
					self.runGroup.leave()
				})

	#if DEBUG
				pmon.processLaunched(self)
	#endif
				self._state = .running
				self.sig = launchedProcess
			}
		} catch let error {
			//assign state failed
			runGroup.leave()
			self.internalSync.async { [weak self] in
				guard let self = self else {
					return
				}
				self._state = .failed
			}
			throw error
		}
    }
    
    public func waitForExitCode() -> Int32 {
		self.runGroup.wait()
		return self.internalSync.sync {
			return self.exitCode
		}
    }
}

import Foundation

fileprivate let tt_spawn_sem = DispatchSemaphore(value:1)

internal class DebugProcessMonitor {
    let internalSync = DispatchQueue(label:"com.tannersilva.process.monitor.sync", target:process_master_queue)
	
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
				return sig!.worker
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
    private let internalAsync:DispatchQueue
    
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
    
    internal var commandToRun:Command
    internal var wd:URL
    internal var sig:tt_proc_signature? = nil
    
    var lines = [Data]() 
	
    public init<C>(command:C, priority:Priority, workingDirectory:URL) throws where C:Command {
        self._priority = priority
        self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync", target:process_master_queue)
        let rs = DispatchSemaphore(value:0)
        commandToRun = command
        wd = workingDirectory
        let inputSerial = DispatchQueue(label:"footest", qos:priority.process_async_priority, target:process_master_queue)
        self.internalAsync = inputSerial

		self._state = .initialized
    }
    
    public func run() throws {
		try self.internalSync.sync {
			let launchedProcess = try tt_spawn(path:self.commandToRun.executable, args: self.commandToRun.arguments, wd:self.wd, env: self.commandToRun.environment, stdout:{ someData in
				self.lines.append(someData)
				self._stdoutHandler?(someData)
			}, stderr: { someData in
				self.lines.append(someData)
				self._stderrHandler?(someData)
			}, reading:internalSync, writing:nil)
			pmon.processLaunched(self)
			print(Colors.Green("launched \(launchedProcess.worker)"))
			self.sig = launchedProcess
		}
    }
    
    public func waitForExitCode() -> Int {
        let ec = tt_wait_sync(pid: sig!.container)
        defer {
            pmon.processEnded(self)
        }
        return internalAsync.sync { Int(ec) }
    }
    
    deinit {
    	print(Colors.yellow("ip was deinit"))
    }
}

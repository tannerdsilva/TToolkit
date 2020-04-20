import Foundation

fileprivate let tt_spawn_sem = DispatchSemaphore(value:1)

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
        self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process.sync")
        let rs = DispatchSemaphore(value:0)
        commandToRun = command
        wd = workingDirectory
        let inputSerial = DispatchQueue(label:"footest", qos:priority.process_async_priority, target:process_master_queue)
        self.internalAsync = inputSerial

        self.runSemaphore = rs
		self._state = .initialized
    }
    
    public func run() throws {
        try self.internalSync.sync {
            let launchedProcess = try tt_spawn(path:self.commandToRun.executable, args: self.commandToRun.arguments, wd:self.wd, env: self.commandToRun.environment, stdin: true, stdout:true, stderr: true)
            if let hasOut = launchedProcess.stdout {
                self.stdout = ProcessPipes(hasOut, readQueue: internalAsync)
                self.stdout!.readGroup = self.ioGroup
                self.stdout!.readHandler = { [weak self] someData in
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
            }
            if let hasErr = launchedProcess.stderr {
                self.stderr = ProcessPipes(hasErr, readQueue: internalAsync)
                self.stderr!.readGroup = self.ioGroup
                self.stderr!.readHandler = { [weak self] someData in
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
            if let hasIn = launchedProcess.stdin {
                self.stdin = ProcessPipes(hasIn, readQueue: nil)
            }
            pmon.processLaunched(self)
            print(Colors.Green("launched \(launchedProcess.worker)"))
            self.sig = launchedProcess
        }
    }
    
    public func waitForExitCode() -> Int {
        let ec = tt_wait_sync(pid: sig!.container)
		if let hasOut = stdout {
            close(hasOut.reading.fileDescriptor)
            hasOut.readHandler = nil
        }
        if let hasErr = stderr {
            close(hasErr.reading.fileDescriptor)
            hasErr.readHandler = nil
        }
        if let hasIn = stdin {
            close(hasIn.writing.fileDescriptor)
            hasIn.readHandler = nil
        }

        ioGroup.wait()
        defer {
        	print(Colors.red("exit \(sig!.worker)"))
        	pmon.processEnded(self)
        }
        return internalAsync.sync { Int(ec) }
    }
    
    deinit {
    	print(Colors.yellow("ip was deinit"))
    }
}

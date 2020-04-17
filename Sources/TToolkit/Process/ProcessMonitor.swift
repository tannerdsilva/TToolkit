import Foundation

internal enum ProcessLaunchedError:Error {
	case badAccess
	case internalError
}

internal var globalProcessMonitor:ProcessMonitor = ProcessMonitor()
internal class ProcessMonitor {
	internal typealias ProcessKey = pid_t
	internal typealias ExitHandler = (Int32) -> Void
	
	private var masterPipe:ProcessPipes? = nil
	private let internalSync:DispatchQueue
    private let dataProcess:DispatchQueue

	var monitorWorkLaunchWaiters:[ProcessKey:DispatchSemaphore]
	
	var monitorWorkLaunchTimes:[ProcessKey:Date]	//maps a monitor process with the time that its worker process started executing
	var monitorWorkMapping:[ProcessKey:Int32]	//maps the monitor process's id with the worker process's id
	
	var accessErrors = Set<ProcessKey>()
	var exitHandlers:[Int32:ExitHandler]
	
	private var dataBuffer = Data()
	private var dataLines = [Data]()
	
	init() {
        let isync = DispatchQueue(label:"com.tannersilva.com.instance.process.monitor.sync", target:global_lock_queue)
        let dataIntake = DispatchQueue(label:"com.tannersilva.instance.process.monitor.events", target:global_pipe_read)
        self.dataProcess = dataIntake
        self.internalSync = isync
		self.monitorWorkLaunchWaiters = [ProcessKey:DispatchSemaphore]()
		self.monitorWorkMapping = [ProcessKey:Int32]()
		self.monitorWorkLaunchTimes = [ProcessKey:Date]()
		self.exitHandlers = [Int32:ExitHandler]()
	}
	
	private func loadPipes() throws {
        let mainPipe = try ProcessPipes(read:dataProcess)
		mainPipe.readHandler = { [weak self] someData in
            guard let self = self, let asString = String(data:someData, encoding:.utf8) else {
				return
			}
			self.eventHandle(asString)
		}
        mainPipe.readQueue = dataProcess
		self.masterPipe = mainPipe
	}
	
	//when data is built to the point of becoming a valid event, it is passed here for parsing
	internal func eventHandle(_ newEvent:String) {
		guard let eventMode = newEvent.first else {
			return
		}
		let nextIndex = newEvent.index(after:newEvent.startIndex)
		let endIndex = newEvent.endIndex
		switch eventMode {
			case "e":
			let body = newEvent[nextIndex..<endIndex]
			let bodyElements = body.components(separatedBy:" -> ")
			guard bodyElements.count == 3 else {
				print("error interpreting exit event mode")
				return
			}
			guard let monitorProcessId = Int32(bodyElements[0]), let workerProcessId = Int32(bodyElements[1]), let exitCode = Int32(bodyElements[2]) else {
				print("error trying to parse the body elements in the exit event")
				return
			}
			processExited(mon:monitorProcessId, work:workerProcessId, code:exitCode)
			
			case "l":
			let markDate = Date()
			let body = newEvent[nextIndex..<endIndex]
			let bodyElements = body.components(separatedBy:" -> ")
			guard bodyElements.count == 2 else {
				print("error interpreting exit event mode")
				return
			}
			guard let monitorProcessId = Int32(bodyElements[0]), let workerProcessId = Int32(bodyElements[1]) else {
				print("error trying to parse the body elements in the launch event")
				return
			}
			processLaunched(mon:monitorProcessId, work:workerProcessId, time:markDate)
			
			case "x":
                print(Colors.red("event fatal"))
			let body = newEvent[nextIndex..<endIndex]
			guard let monitorId = Int32(body) else {
				print("error trying to parse the fatal error event")
				return
			}
			fatalEventOccurred(mon:monitorId)
			
			case "a":
            print(Colors.red("event access"))
			let body = newEvent[nextIndex..<endIndex]
			guard let monitorId = Int32(body) else {
				print("error trying to parse the fatal error event")
				return
			}
			accessErrorOccurred(mon:monitorId)
			
			default:
			print("unknown process event occurred")
			return
		}
	}
	
	fileprivate func fatalEventOccurred(mon:Int32) {
        internalSync.sync {
            if let hasWaiter = monitorWorkLaunchWaiters[mon] {
                hasWaiter.signal()
                monitorWorkLaunchWaiters[mon] = nil
            }
            monitorWorkMapping[mon] = nil
        }
	}
		
	fileprivate func accessErrorOccurred(mon:Int32) {
        internalSync.sync {
            monitorWorkMapping[mon] = nil
            _ = accessErrors.update(with:mon)
            if let hasWaiter = monitorWorkLaunchWaiters[mon] {
                hasWaiter.signal()
                monitorWorkLaunchWaiters[mon] = nil
            }
        }
	}
	
	fileprivate func processLaunched(mon:Int32, work:Int32, time:Date) {
         internalSync.sync {
            guard let hasWaiter = monitorWorkLaunchWaiters[mon] else {
                print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
                return
            }
            monitorWorkMapping[mon] = work
            monitorWorkLaunchTimes[mon] = time
            hasWaiter.signal()
            monitorWorkLaunchWaiters[mon] = nil
        }
	}
	
	fileprivate func processExited(mon:Int32, work:Int32, code:Int32) {
        internalSync.sync {
            guard let hasExitHandler = exitHandlers[work] else {
                print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
                return
            }
            print("exit thing")
            monitorWorkMapping[mon] = nil
            monitorWorkLaunchTimes[mon] = nil
            hasExitHandler(code)
        }
	}
		
	func launchProcessContainer(_ workToRegister:@escaping(ExportedPipe) throws -> ProcessMonitor.ProcessKey, onExit:@escaping(ExitHandler)) throws -> (Int32, Date) {
        let newSem = DispatchSemaphore(value:0)
        let notifyPipe:ExportedPipe = try self.internalSync.sync {
			if masterPipe == nil {
				try loadPipes()
                return masterPipe!.export()
            } else {
                return masterPipe!.export()
            }
		}

        let launchProc:ProcessKey = try internalSync.sync {
            let launchedProcess = try workToRegister(notifyPipe)
            monitorWorkLaunchWaiters[launchedProcess] = newSem
            return launchedProcess
        }
		newSem.wait()
        
        let launchVars:(Int32, Date) = try internalSync.sync {
			//guard that there was a worker pid launched (guard that there was no error launching the worker process
			guard let hasWorkIdentifier = monitorWorkMapping[launchProc], let launchTime = monitorWorkLaunchTimes[launchProc] else {
				//shoot, there was an error
				if accessErrors.contains(launchProc) == true {
					accessErrors.remove(launchProc)
					throw ProcessLaunchedError.badAccess
				} else {
                    print("throwing internal error")
					throw ProcessLaunchedError.internalError
				}
			}
			exitHandlers[launchProc] = onExit
			return (hasWorkIdentifier, launchTime)
		}
        return launchVars
	}
}

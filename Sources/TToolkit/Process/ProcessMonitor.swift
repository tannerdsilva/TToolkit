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

	var monitorWorkLaunchWaiters:[ProcessKey:DispatchSemaphore]
	
	var monitorWorkLaunchTimes:[ProcessKey:Date]	//maps a monitor process with the time that its worker process started executing
	var monitorWorkMapping:[ProcessKey:Int32]	//maps the monitor process's id with the worker process's id
	
	var accessErrors = Set<ProcessKey>()
	var exitHandlers:[Int32:ExitHandler]
	
	private var dataBuffer = Data()
	private var dataLines = [Data]()
	
	init() {
		let isync = DispatchQueue(label:"com.tannersilva.com.instance.process.monitor.sync", target:global_lock_queue)
		
		self.internalSync = isync
		self.monitorWorkLaunchWaiters = [ProcessKey:DispatchSemaphore]()
		self.monitorWorkMapping = [ProcessKey:Int32]()
		self.monitorWorkLaunchTimes = [ProcessKey:Date]()
		self.exitHandlers = [Int32:ExitHandler]()
	}
	
	private func loadPipes() throws {
		let mainPipe = try ProcessPipes()
		mainPipe.readHandler = { [weak self] someData in
			guard let self = self else {
				return
			}
			self.processData(someData)
		}
		self.masterPipe = mainPipe
	}
	
	//put the data in the buffer, return true if it contains a new line
	private func inputData(_ someData:Data) -> Bool {
        let hasNewLine = someData.withUnsafeBytes { unsafeBuffer -> Bool in
			if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
				return true
			}
			return false
		}
        self.dataBuffer.append(someData)
		return hasNewLine
	}
	
	//parses the data buffer for potential new lines, returns any of those lines
	private func extractNewLines() -> [Data]? {
        if var parsedLines = self.dataBuffer.lineSlice(removeBOM:false) {
            let tailData = parsedLines.removeLast()
            self.dataBuffer.removeAll(keepingCapacity:true)
            self.dataBuffer.append(tailData)
            if parsedLines.count > 0 {
                return parsedLines
            } else {
                return nil
            }
        }
        return nil
	}
	
	//when data comes off the file descriptor, it is passed here to be processed into an instance
	private func processData(_ incomingData:Data) {
        self.internalSync.sync {
            print(Colors.cyan("Process data is being called ------------------------------------------------------------"))
            let hasNewLine = self.inputData(incomingData)
            if hasNewLine, let newLines = extractNewLines() {
                for (_, curNewLine) in newLines.enumerated() {
                    print(Colors.red("enumerating"))
                    if let canLineBeString = String(data:curNewLine, encoding:.utf8) {
                        eventHandle(canLineBeString)
                    }
                }
            }
        }
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
			let body = newEvent[nextIndex..<endIndex]
			guard let monitorId = Int32(body) else {
				print("error trying to parse the fatal error event")
				return
			}
			fatalEventOccurred(mon:monitorId)
			
			case "a":
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
        if let hasWaiter = monitorWorkLaunchWaiters[mon] {
            hasWaiter.signal()
            monitorWorkLaunchWaiters[mon] = nil
        }
        monitorWorkMapping[mon] = nil
	}
		
	fileprivate func accessErrorOccurred(mon:Int32) {
        monitorWorkMapping[mon] = nil
        _ = accessErrors.update(with:mon)
        if let hasWaiter = monitorWorkLaunchWaiters[mon] {
            hasWaiter.signal()
            monitorWorkLaunchWaiters[mon] = nil
        }
	}
	
	fileprivate func processLaunched(mon:Int32, work:Int32, time:Date) {
        guard let hasWaiter = monitorWorkLaunchWaiters[mon] else {
            print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
            return
        }
        monitorWorkMapping[mon] = work
        monitorWorkLaunchTimes[mon] = time
        hasWaiter.signal()
        monitorWorkLaunchWaiters[mon] = nil
	}
	
	fileprivate func processExited(mon:Int32, work:Int32, code:Int32) {
        guard let hasExitHandler = exitHandlers[work] else {
            print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
            return
        }
        monitorWorkMapping[mon] = nil
        monitorWorkLaunchTimes[mon] = nil
        hasExitHandler(code)
	}
		
	func launchProcessContainer(_ workToRegister:@escaping(Int32) throws -> ProcessMonitor.ProcessKey, onExit:@escaping(ExitHandler)) throws -> (Int32, Date) {
        let newSem = DispatchSemaphore(value:0)
        let writeFD:Int32 = try self.internalSync.sync {
			if masterPipe == nil {
				try loadPipes()
                return masterPipe!.writing.fileDescriptor
            } else {
                return masterPipe!.writing.fileDescriptor
            }
		}
        
        let launchedMonitor:ProcessMonitor.ProcessKey = try internalSync.sync {
            let newWorkId = try workToRegister(writeFD)
			monitorWorkLaunchWaiters[newWorkId] = newSem
			return newWorkId
		}
        
		newSem.wait()
        
        let launchVars:(Int32, Date) = try internalSync.sync {
			//guard that there was a worker pid launched (guard that there was no error launching the worker process
			guard let hasWorkIdentifier = monitorWorkMapping[launchedMonitor], let launchTime = monitorWorkLaunchTimes[launchedMonitor] else {
				//shoot, there was an error
				if accessErrors.contains(launchedMonitor) == true {
					accessErrors.remove(launchedMonitor)
					throw ProcessLaunchedError.badAccess
				} else {
					throw ProcessLaunchedError.internalError
				}
			}
			exitHandlers[hasWorkIdentifier] = onExit
			return (hasWorkIdentifier, launchTime)
		}
        return launchVars
	}
}

import Foundation


fileprivate let globalProcessMonitorSync = DispatchQueue(label:"com.tannersilva.global.process.monitor.instance.sync", target:global_lock_queue)
fileprivate var globalProcessMonitor:ProcessMonitor? = nil
internal class ProcessMonitor {
    class func globalMonitor() throws -> ProcessMonitor {
        return try globalProcessMonitorSync.sync {
            if globalProcessMonitor == nil {
                globalProcessMonitor = try ProcessMonitor()
            }
            return globalProcessMonitor!
        }
    }

    let mainPipe:ExportedPipe

    let internalSync:DispatchQueue
        
    var waitSemaphores = [pid_t:DispatchSemaphore]()
    var flushReqs = [pid_t:tt_proc_signature]()

	private var dataBuffer = Data()
	private var dataLines = [Data]()

	init() throws {
        let isync = DispatchQueue(label:"com.tannersilva.instance.process.monitor.sync", target:global_lock_queue)
        let dataIntake = DispatchQueue(label:"com.tannersilva.instance.process.monitor.events", target:process_master_queue)
        self.internalSync = isync
        mainPipe = try ExportedPipe.rw(nonblock:true)
        globalPR.scheduleForReading(mainPipe.reading, queue: dataIntake, handler: { [weak self] someData in
            if let asString = String(data:someData, encoding: .utf8) {
                self!.eventHandle(asString)
            }
        })
	}

    func newNotifyWriter() throws -> ProcessHandle {
        return ProcessHandle(fd:mainPipe.writing.fileDescriptor)
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
            default:
            return
		}
	}
    
    fileprivate func processLaunched(mon:pid_t, work:pid_t, time:Date) {
        print("process monitor confirmed launch of monitor \(mon) and process \(work) at \(time)")
	}

	fileprivate func processExited(mon:pid_t, work:pid_t, code:Int32) {
        internalSync.sync {
			print("process monitor confirmed exit of monitor \(mon) and process \(work) with code \(code) \(flushReqs[mon])")
			if let hasSig = flushReqs[mon] {
				let signalSem = waitSemaphores[mon]
				if let hasOut = hasSig.stdout {
					globalPR.unschedule(hasOut.reading, { [self] in
						file_handle_guard.async {
							_ = _close(hasOut.reading)
						}
                        if signalSem != nil {
                            signalSem!.signal()
                            print(Colors.bgGreen("Signaled semaphore for stdout"))
                        }
					})
				}
				if let hasErr = hasSig.stderr {
					globalPR.unschedule(hasErr.reading, { [self] in 
						file_handle_guard.async {
							_ = _close(hasErr.reading)
						}
                        if signalSem != nil {
                            signalSem!.signal()
                            print(Colors.bgGreen("Signaled semaphore for stderr"))
                        }
					})
				}
                internalSync.async {
                    self.waitSemaphores[mon] = nil
                    self.flushReqs[mon] = nil
                }
			}
        }
	}
	
	internal func waitForProcessExitAndFlush(mon:pid_t) {
		let waitSemaphore:DispatchSemaphore? = internalSync.sync {
			if let hasSemaphore = self.waitSemaphores[mon] {
				print("Has a semaphore")
				return hasSemaphore
			} else {
				print("Does not have a semaphore")
				return nil
			}
		}
		
		if let shouldWait = waitSemaphore {
			print(Colors.bgYellow("awaiting flush..."))
			shouldWait.wait()
		}
	}
	
	internal func registerFlushPrerequisites(_ sig:tt_proc_signature) {
		internalSync.sync {
			print(Colors.bgWhite("Registered flush prerequisite for monitor process \(sig.container)"))
			let monitorID = sig.container
			flushReqs[monitorID] = sig
			
			var valueTarget:Int? = nil
			if sig.stdout != nil && sig.stderr != nil {
				print(Colors.dim("Using flush prereq value of 0"))
				valueTarget = -1
			} else if sig.stdout != nil {
				valueTarget = 0
				print(Colors.dim("Using flush prereq value of 0"))
			} else if sig.stderr != nil {
				valueTarget = 0
				print(Colors.dim("Using flush prereq value of 0"))
			}
			
			if valueTarget != nil {
				self.waitSemaphores[monitorID] = DispatchSemaphore(value:valueTarget!)
			}
		}
	}
}

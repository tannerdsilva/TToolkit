import Foundation

fileprivate let globalProcessMonitorSync = DispatchQueue(label:"com.tannersilva.global.process.monitor.instance.sync", target:global_lock_queue)
fileprivate var globalProcessMonitor:ProcessMonitor? = nil

//this is an internal class tha monitors the state of processes that are in flight
internal class ProcessMonitor {
    class func globalMonitor() throws -> ProcessMonitor {
        return try globalProcessMonitorSync.sync {
            if globalProcessMonitor == nil {
                globalProcessMonitor = try ProcessMonitor()
            }
            return globalProcessMonitor!
        }
    }

	//this is the primary pipe that the spawned processes will use to channel data to the global process monitor
    let mainPipe:ExportedPipe

    let internalSync:DispatchQueue
    
    var waitGroups = [pid_t:DispatchGroup]()
    var flushReqs = [pid_t:tt_proc_signature]()
    
    //runtime durations for every executed process. keys are based on monitor process, not working process
    var processStarts = [pid_t:Date]()
    var processEnds = [pid_t:Date]()

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

	//created a new processHandle that is ready to write into the reading end of self's internal pipe
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
    	//record the launch time of the process
    	let captureDate = Date()
    	internalSync.async { [self, captureDate] in
    		self.processStarts[mon] = captureDate
			self.processEnds[mon] = nil
    	}
	}

	fileprivate func processExited(mon:pid_t, work:pid_t, code:Int32) {
		let captureDate = Date()
        internalSync.sync { [weak self, captureDate] in
        	processEnds[mon] = captureDate	//record the end time of the process
			if let hasSig = flushReqs[mon] {
				let waitGroup = waitGroups[mon]
				if let hasOut = hasSig.stdout {
					globalPR.unschedule(hasOut.reading, { [self] in
						file_handle_guard.async {
							_ = _close(hasOut.reading)
						}
                        if waitGroup != nil {
                          	waitGroup!.leave()
                        }
					})
				}
				if let hasErr = hasSig.stderr {
					globalPR.unschedule(hasErr.reading, { [self] in 
						file_handle_guard.async {
							_ = _close(hasErr.reading)
						}
                        if waitGroup != nil {
							waitGroup!.leave()
                        }
					})
				}
                internalSync.async {
                	guard let self = self else {
                		return
                	}
                    self.waitGroups[mon] = nil
                    self.flushReqs[mon] = nil
                }
			}
        }
	}
	
	internal func waitForProcessExitAndFlush(mon:pid_t) -> (Int32, Date) {
        let ec = tt_wait_sync(pid: mon)
        let exitTime = Date()
		let waitGroup:DispatchGroup? = internalSync.sync {
			if let hasGroup = self.waitGroups[mon] {
				return hasGroup
			} else {
				return nil
			}
		}
		
		if let shouldWait = waitGroup {
			shouldWait.wait()
		}
        
        return (ec, exitTime)
	}
	
	internal func registerFlushPrerequisites(_ sig:tt_proc_signature) {
		internalSync.async { [sig, weak self] in
			guard let self = self else {
				return
			}
			let monitorID = sig.container
            self.flushReqs[monitorID] = sig
			
			let newGroup = DispatchGroup()
            if sig.stdout != nil, sig.stdout?.reading != nil {
				newGroup.enter()
			}
			if sig.stderr != nil, sig.stderr?.reading != nil {
				newGroup.enter()
			}

			self.waitGroups[monitorID] = newGroup
		}
	}
}

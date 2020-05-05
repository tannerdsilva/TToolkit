import Foundation

//
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
    
    var needsClose = [pid_t:Set<Int32>]()

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
    
    func closeHandles(container:pid_t, handles:Set<Int32>) {
        internalSync.async { [weak self] in
            self!.needsClose[container] = handles
        }
    }

    fileprivate func processLaunched(mon:pid_t, work:pid_t, time:Date) {
        print("process monitor confirmed launch of monitor \(mon) and process \(work) at \(time)")
	}

	fileprivate func processExited(mon:pid_t, work:pid_t, code:Int32) {
        internalSync.sync {
            if let closeHandles = needsClose[mon] {
                for (_, curHandle) in closeHandles.enumerated() {
                    globalPR.unschedule(curHandle, { [closeHandles] in
                        file_handle_guard.async { [closeHandles] in
                            var enumerator = closeHandles.makeIterator()
                            while let curHandle = enumerator.next() {
                                _ = _close(curHandle)
                            }
                        }
                    })
                }
                needsClose[mon] = nil
            }
        }
	}
}

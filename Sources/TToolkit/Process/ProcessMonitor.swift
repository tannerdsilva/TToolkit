import Foundation

//
//internal var globalProcessMonitor:ProcessMonitor = ProcessMonitor()
//internal class ProcessMonitor {
//    class var global:ProcessMonitor {
//        get {
//            return globalProcessMonitor
//        }
//    }
//
//    internal enum ProcessStatus {
//        
//    }
//	internal typealias ProcessKey = pid_t
//	internal typealias ExitHandler = (Int32) -> Void
//
//	private var masterPipe:ProcessPipes? = nil
//	private let internalSync:DispatchQueue
//    private let dataProcess:DispatchQueue
//
//	var processStatus = [ProcessKey:ProcessStatus]()
//
//	var accessErrors = Set<ProcessKey>()
//	var exitHandlers:[Int32:ExitHandler]
//
//	private var dataBuffer = Data()
//	private var dataLines = [Data]()
//
//	init() {
//        let isync = DispatchQueue(label:"com.tannersilva.instance.process.monitor.sync", target:global_lock_queue)
//        let dataIntake = DispatchQueue(label:"com.tannersilva.instance.process.monitor.events", target:global_pipe_read)
//        self.dataProcess = dataIntake
//        self.internalSync = isync
//		self.monitorWorkLaunchWaiters = [ProcessKey:DispatchSemaphore]()
//		self.exitHandlers = [Int32:ExitHandler]()
//	}
//
//    func newNotifyWriter() throws -> ProcessHandle {
//        if masterPipe == nil {
//            try loadPipes()
//        }
//        return ProcessHandle(fd:masterPipe!.writing.fileDescriptor)
//    }
//
//	private func loadPipes() throws {
//        let mainPipe = try ProcessPipes(read:dataProcess)
//		mainPipe.readHandler = { [weak self] someData in
//            guard let self = self, let asString = String(data:someData, encoding:.utf8) else {
//				return
//			}
//			self.eventHandle(asString)
//		}
//        mainPipe.readQueue = dataProcess
//		self.masterPipe = mainPipe
//	}
//
//	//when data is built to the point of becoming a valid event, it is passed here for parsing
//	internal func eventHandle(_ newEvent:String) {
//		guard let eventMode = newEvent.first else {
//			return
//		}
//		let nextIndex = newEvent.index(after:newEvent.startIndex)
//		let endIndex = newEvent.endIndex
//		switch eventMode {
//			case "e":
//			let body = newEvent[nextIndex..<endIndex]
//			let bodyElements = body.components(separatedBy:" -> ")
//			guard bodyElements.count == 3 else {
//				print("error interpreting exit event mode")
//				return
//			}
//			guard let monitorProcessId = Int32(bodyElements[0]), let workerProcessId = Int32(bodyElements[1]), let exitCode = Int32(bodyElements[2]) else {
//				print("error trying to parse the body elements in the exit event")
//				return
//			}
//			processExited(mon:monitorProcessId, work:workerProcessId, code:exitCode)
//
//			case "l":
//			let markDate = Date()
//			let body = newEvent[nextIndex..<endIndex]
//			let bodyElements = body.components(separatedBy:" -> ")
//			guard bodyElements.count == 2 else {
//				print("error interpreting exit event mode")
//				return
//			}
//			guard let monitorProcessId = Int32(bodyElements[0]), let workerProcessId = Int32(bodyElements[1]) else {
//				print("error trying to parse the body elements in the launch event")
//				return
//			}
//			processLaunched(mon:monitorProcessId, work:workerProcessId, time:markDate)
//
//			case "x":
//                print(Colors.red("event fatal"))
//			let body = newEvent[nextIndex..<endIndex]
//			guard let monitorId = Int32(body) else {
//				print("error trying to parse the fatal error event")
//				return
//			}
//			fatalEventOccurred(mon:monitorId)
//
//			case "a":
//            print(Colors.red("event access"))
//			let body = newEvent[nextIndex..<endIndex]
//			guard let monitorId = Int32(body) else {
//				print("error trying to parse the fatal error event")
//				return
//			}
//			accessErrorOccurred(mon:monitorId)
//
//			default:
//			print("unknown process event occurred")
//			return
//		}
//	}
//
//	fileprivate func fatalEventOccurred(mon:Int32) {
//        internalSync.sync {
//            if let hasWaiter = monitorWorkLaunchWaiters[mon] {
//                hasWaiter.signal()
//                monitorWorkLaunchWaiters[mon] = nil
//            }
//        }
//	}
//
//	fileprivate func accessErrorOccurred(mon:Int32) {
//        internalSync.sync {
//            _ = accessErrors.update(with:mon)
//            if let hasWaiter = monitorWorkLaunchWaiters[mon] {
//                hasWaiter.signal()
//                monitorWorkLaunchWaiters[mon] = nil
//            }
//        }
//	}
//
//	fileprivate func processLaunched(mon:Int32, work:Int32, time:Date) {
//         internalSync.sync {
//            guard let hasWaiter = monitorWorkLaunchWaiters[mon] else {
//                print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
//                return
//            }
//            hasWaiter.signal()
//            monitorWorkLaunchWaiters[mon] = nil
//        }
//	}
//
//	fileprivate func processExited(mon:Int32, work:Int32, code:Int32) {
//        internalSync.sync {
//            guard let hasExitHandler = exitHandlers[work] else {
//                print("unable to find the waiting semaphore for monitor \(mon) and pid \(work)")
//                return
//            }
//            print("exit thing")
//            hasExitHandler(code)
//        }
//	}
//
//    func validateCompletedLaunch(_ sig:tt_proc_signature) {
//        let newSemaphore = DispatchSemaphore(value:0) //this is probably the most expensive line in this function, so it is done outside of the internal sync block to reduce consumed syncronized time (better performance with concurrent callers)
//        let storedSemaphore:DispatchSemaphore = self.internalSync.sync {
//            if let hasSemaphore = monitorWorkLaunchWaiters[sig.container] {
//                return hasSemaphore
//            } else {
//                monitorWorkLaunchWaiters[sig.container] = newSemaphore
//                return newSemaphore
//            }
//        }
//        storedSemaphore.wait()
//        self.internalSync.sync {
//            monitorWorkLaunchWaiters[sig.container] = nil
//        }
//    }
//
//	func launchProcessContainer(_ workToRegister:@escaping(ExportedPipe) throws -> ProcessMonitor.ProcessKey, onExit:@escaping(ExitHandler)) throws -> (Int32, Date) {
//        let launchedProcess = try workToRegister(notifyPipe)
//        internalSync.sync {
//            monitorWorkLaunchWaiters[launchedProcess] = newSem
//        }
//		newSem.wait()
//
//        let launchVars:(Int32, Date) = try internalSync.sync {
//			//guard that there was a worker pid launched (guard that there was no error launching the worker process
//			guard let hasWorkIdentifier = monitorWorkMapping[launchedProcess], let launchTime = monitorWorkLaunchTimes[launchedProcess] else {
//				//shoot, there was an error
//				if accessErrors.contains(launchedProcess) == true {
//					accessErrors.remove(launchedProcess)
//					throw ProcessLaunchedError.badAccess
//				} else {
//                    print("throwing internal error")
//					throw ProcessLaunchedError.internalError
//				}
//			}
//			exitHandlers[hasWorkIdentifier] = onExit
//			return (hasWorkIdentifier, launchTime)
//		}
//        return launchVars
//	}
//}

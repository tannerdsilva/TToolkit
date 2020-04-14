import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
	fileprivate let _read = Darwin.read(_:_:_:)
	fileprivate let _write = Darwin.write(_:_:_:)
	fileprivate let _close = Darwin.close(_:)
	fileprivate let o_cloexec = Darwin.O_CLOEXEC
	fileprivate let _pipe = Darwin.pipe(_:)
#elseif canImport(Glibc)
	import Glibc
	fileprivate let _read = Glibc.read(_:_:_:)
	fileprivate let _write = Glibc.write(_:_:_:)
	fileprivate let _close = Glibc.close(_:)
	fileprivate let o_cloexec = Glibc.O_CLOEXEC
	fileprivate let _pipe = Glibc.pipe(_:)
#endif

internal typealias ReadHandler = (Data) -> Void
internal typealias WriteHandler = () -> Void

fileprivate let ioThreads = DispatchQueue(label:"com.tannersilva.global.process-handle.io", attributes:[.concurrent])
fileprivate let ppLocks = DispatchQueue(label:"com.tannersilva.global.process-pipe.sync", attributes:[.concurrent])
internal let pp_make_destroy_queue = DispatchQueue(label:"com.tannersilva.global.process-pipe.init-serial")

/*
	When external processes are launched, there is no way of influencing the rate of which that processess will output data.
	The PipeReader class is used to immediately read data from available file descriptors. after a Data object is captured, Pipereader will call the completion handler at a specified dispatch queue while respecting that queues QoS
	This internal class allows data to be captured from the pipe handles immediately while potentially diverting the actual handling of that data for a later time based on the destination queue's QoS
*/
internal class PipeReader {
	let internalSync:DispatchQueue
	var handleQueue:[ProcessHandle:DispatchSourceProtocol]
	init() {
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-pipe.reader.sync")
		self.handleQueue = [ProcessHandle:DispatchSourceProtocol]()
	}
    func scheduleForReading(_ handle:ProcessHandle, work:@escaping(ReadHandler), queue:DispatchQueue) {
        print("scheduling \(handle._fd)")
        let newSource = DispatchSource.makeReadSource(fileDescriptor:handle.fileDescriptor, queue:Priority.highest.globalConcurrentQueue)
		newSource.setEventHandler {
			if let newData = handle.availableData() {
                queue.async { work(newData) }
			}
		}
		internalSync.sync {
			handleQueue[handle] = newSource
        }
		newSource.activate()
	}
	func unschedule(_ handle:ProcessHandle) {
		internalSync.sync {
			if let hasExisting = handleQueue[handle] {
				hasExisting.cancel()
				handleQueue[handle] = nil
			}
		}
	}
}
internal let globalPR = PipeReader()

//internal class WriteWatcher {
//	fileprivate static let whThreads = DispatchQueue(label:"com.tannerdsilva.global.process.pipe.write-handler", qos:maximumPriority, attributes:[.concurrent])
//	let internalSync = DispatchQueue(label:"com.tannersilva.instance.process.pipe.write-handler.sync", target:whThreads)
//
//	var handleQueue:[ProcessHandle:DispatchSourceProtocol]
//
//	init() {
//		self.handleQueue = [ProcessHandle:DispatchSourceProtocol]()
//	}
//
//	func scheduleWriteAvailability(_ handle:ProcessHandle, queue:DispatchQueue, group:DispatchGroup, work:@escaping(WriteHandler)) {
//		let newSource = DispatchSource.makeReadSource(fileDescriptor:handle.fileDescriptor, queue:queue)
//		group.enter()
//		newSource.setEventHandler {
//			group.enter()
//			work()
//			group.leave()
//		}
//		newSource.setCancelHandler {
//            print("cancel!!!!!!!!!!!!!!!!!!!!!!!!!")
//			group.leave()
//		}
//		internalSync.sync {
//			if let hasExisting = handleQueue[handle] {
//				hasExisting.cancel()
//			}
//			handleQueue[handle] = newSource
//			newSource.activate()
//		}
//		print(Colors.magenta("[\(handle.fileDescriptor)] scheduled for writing."))
//	}
//
//	func unschedule(_ handle:ProcessHandle) {
//		internalSync.sync {
//			if let hasExisting = handleQueue[handle] {
//				hasExisting.cancel()
//				handleQueue[handle] = nil
//			}
//		}
//		print(Colors.magenta("[\(handle.fileDescriptor)] unscheduled from writing"))
//	}
//}
//internal let globalWH = WriteWatcher()

//the exported pipe is passed to forked child processes. would rather pass structured data to forking
internal struct ExportedPipe {
    let reading:Int32
    let writing:Int32
    
    func configureOutbound() {
        _close(reading)
    }
    func configureInbound() {
        _close(writing)
    }
    func close() {
        _ = _close(writing)
        _ = _close(reading)
    }
}

internal class ProcessPipes {
	private let internalSync:DispatchQueue

	let reading:ProcessHandle
	let writing:ProcessHandle
    
    //related to data intake
    private var _readBuffer = Data()
    private var _readLines = [Data]()
    private var _readQoS:DispatchQoS = Priority.default.asDispatchQoS()
    var readQoS:DispatchQoS {
        get {
            return internalSync.sync {
                return _readQoS
            }
        }
        set {
            internalSync.sync {
                _readQoS = newValue
            }
        }
    }
    
    private var _readQueue:DispatchQueue
    var readQueue:DispatchQueue {
        get {
            return internalSync.sync {
                return _readQueue
            }
        }
        set {
            return internalSync.sync {
                _readQueue = newValue
                if _readQueue != nil && _readLines.count > 0 {
                    _scheduleReadCallback(_readLines.count)
                }
            }
        }
    }

	private var _readHandler:ReadHandler? = nil
	var readHandler:ReadHandler? {
		get {
			return internalSync.sync {
				return _readHandler
			}
		}
		set {
			internalSync.sync {
				if let hasNewHandler = newValue {
					_readHandler = hasNewHandler
					globalPR.scheduleForReading(reading, work:{ [weak self] someData in
                        guard let self = self else {
                            return
                        }
                        self.intake(someData)
                    }, queue:_readQueue)
				} else {
					if _readHandler != nil {
						globalPR.unschedule(reading)
					}
					_readHandler = nil
				}
			}
		}
	}
    
    func intake(_ dataIn:Data) {
        let hasNewLine = dataIn.withUnsafeBytes { unsafeBuffer -> Bool in
            if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
                return true
            }
            return false
        }
        let linesToSchedule:Int = self.internalSync.sync {
            print("data intake syncronized with buffer size of \(_readBuffer.count) bytes")
            _readBuffer.append(dataIn)
            if hasNewLine {
                print("has line")
                let sliceResult = _readBuffer.lineSlice(removeBOM:false, completeLinesOnly: true)
                if var parsedLines = sliceResult.lines {
                    let foundLines = parsedLines.map { String(data:$0, encoding:.utf8) }
                    print("FOUND \(foundLines)")
                    _readBuffer.removeAll(keepingCapacity:true)
                    if let hasRemainder = sliceResult.remain, hasRemainder.count > 0 {
                        let remain = String(data:hasRemainder, encoding:.utf8)
                        print("REMAIN \(remain?.count)")
                        _readBuffer.append(hasRemainder)
                    }
                    if parsedLines.count > 0 {
                        _scheduleReadCallback(parsedLines.count)
                        self._readLines.append(contentsOf:parsedLines)
                        return parsedLines.count
                    }
                } else {
                    print("nope")
                }
            }
            return 0
        }
        print("returned")
//        if linesToSchedule != 0 {
//            _scheduleReadCallback(linesToSchedule)
//        }
    }
    
    private func popIntakeLineAndHandler() -> (Data?, ReadHandler?) {
        return self.internalSync.sync {
            if self._readLines.count > 0 {
                return (self._readLines.remove(at:0), _readHandler)
            }
            return (nil, _readHandler)
        }
    }
    
    func _scheduleReadCallback(_ nTimes:Int) {
        print("calling back \(nTimes) lines")
        let useQos = _readQoS ?? DispatchQoS.unspecified
        print("qos picked")
        let asyncCallbackHandler = DispatchWorkItem() { [weak self] in
            guard let self = self else {
                return
            }
            print("attempting to pop")
            let (newDataLine, handlerToCall) = self.popIntakeLineAndHandler()
            print("callback popped")
            if let hasNewDataLine = newDataLine, let hasHandler = handlerToCall {
                print(Colors.BgBlue("CALLING CALLBAK"))
                hasHandler(hasNewDataLine)
            } else {
                
            }
        }
    
        print("not sure why this line is interesting but whatever")
        for _ in 0..<nTimes {
            print(">")
            _readQueue.async(execute:asyncCallbackHandler)
        }
    }
	
    init(read:DispatchQueue) throws {
		let readWrite = try Self.forReadingAndWriting()
		self.reading = readWrite.r
		self.writing = readWrite.w
		
		let ints = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", target:global_lock_queue)
		self.internalSync = ints
        self._readQueue = read
	}
	
    init(_ export:ExportedPipe, readQueue:DispatchQueue) {
		self.reading = ProcessHandle(fd:export.reading)
		self.writing = ProcessHandle(fd:export.writing)
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", target:global_lock_queue)
        self._readQueue = readQueue
	}
	
	fileprivate static func forReadingAndWriting() throws -> (r:ProcessHandle, w:ProcessHandle) {
        let fds = UnsafeMutablePointer<Int32>.allocate(capacity:2)
		defer {
			fds.deallocate()
		}
		
        let rwfds = global_pipe_lock.sync {
            return _pipe(fds)
		}
		
        switch rwfds {
            case 0:
                let readFD = fds.pointee
                let writeFD = fds.successor().pointee
                print(Colors.magenta("created for reading: \(readFD)"))
                print(Colors.Magenta("created for writing: \(writeFD)"))
                return (r:ProcessHandle(fd:readFD), w:ProcessHandle(fd:writeFD))
            default:
            throw ExecutingProcess.ExecutingProcessError.unableToCreatePipes
        }
	}
		
	func close() {
		readHandler = nil
		reading.close()
		writing.close()
	}
    
    func export() -> ExportedPipe {
        return ExportedPipe(reading: reading.fileDescriptor, writing: writing.fileDescriptor)
    }
}



internal class ProcessHandle:Hashable {
	enum ProcessHandleError:Error {
		case handleClosed
	}
	
	fileprivate let internalSync:DispatchQueue
	
	private var _isClosed:Bool
	var isClosed:Bool {
		get {
			return internalSync.sync {
				return _isClosed
			}
		}
	}
	
	fileprivate let _fd:Int32
	var fileDescriptor:Int32 {
		get {
			internalSync.sync {
				return _fd
			}
		}
	}
	
	init(fd:Int32) {
		self._fd = fd
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-handle.sync", target:global_lock_queue)
		self._isClosed = false
	}
	
	func write(_ stringObj:String) throws {
		let stringData = try stringObj.safeData(using:.utf8)
		try self.write(stringData)
	}
	
	func write(_ dataObj:Data) throws {
		try internalSync.sync {
			guard _isClosed != true else {
				throw ProcessHandleError.handleClosed
			}
			try dataObj.withUnsafeBytes({
				if let hasBaseAddress = $0.baseAddress {
					try write(buf:hasBaseAddress, length:dataObj.count)
				}
			})
		}
	}
	
	fileprivate func write(buf:UnsafeRawPointer, length:Int) throws {
		var bytesRemaining = length
		while bytesRemaining > 0 {
			var bytesWritten = 0
			repeat {
				bytesWritten = _write(_fd, buf.advanced(by:length - bytesRemaining), bytesRemaining)
			} while (bytesWritten < 0 && errno == EINTR)
			bytesRemaining -= bytesWritten
		}
	}
	
	func availableData() -> Data? {
		return try? internalSync.sync {
			guard _isClosed != true else {
				throw ProcessHandleError.handleClosed
			}
			var statbuf = stat()
			if fstat(_fd, &statbuf) < 0 {
				return nil
			}
		
			let readBlockSize:Int
			if statbuf.st_mode & S_IFMT == S_IFREG && statbuf.st_blksize > 0 {
				readBlockSize = Int(clamping:statbuf.st_blksize)
			} else {
				readBlockSize = 1024 * 8
			}
		
			guard var dynamicBuffer = malloc(readBlockSize + 1) else {
				return nil
			}
			defer {
				free(dynamicBuffer)
			}
		
			let amountRead = read(_fd, dynamicBuffer, readBlockSize)
			guard amountRead > 0 else {
				return nil
			}
			let bytesBound = dynamicBuffer.bindMemory(to:UInt8.self, capacity:amountRead)
			return Data(bytes:bytesBound, count:amountRead)
		}
	}
	
	func close() {
		internalSync.sync {
			guard _isClosed != true, _close(_fd) >= 0 else {
				return
			}
		
			_isClosed = true
		}
	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(_fd)
	}
	
	static func == (lhs:ProcessHandle, rhs:ProcessHandle) -> Bool {
		return lhs._fd == rhs._fd
	}
	
	deinit {
		if isClosed == false {
			close()
		}
	}

}

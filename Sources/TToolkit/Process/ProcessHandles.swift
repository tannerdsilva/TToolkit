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
    func scheduleForReading(_ handle:ProcessHandle, work:@escaping(ReadHandler), queue:DispatchQueue?) {
        let inFD = handle.fileDescriptor
        let newSource = DispatchSource.makeReadSource(fileDescriptor:inFD, queue:Priority.highest.globalConcurrentQueue)
        if let hasQueue = queue {
            newSource.setEventHandler {
                if let newData = handle.availableData() {
                    hasQueue.async { work(newData) }
                }
            }
        } else {
            newSource.setEventHandler {
                if let newData = handle.availableData() {
                    work(newData)
                }
            }
        }
		newSource.setCancelHandler {
			print(Colors.bgBlue("AUTO CANCEL ENABLED"))
            self.internalSync.sync {
                self.handleQueue[handle] = nil
            }
		}
		internalSync.sync {
            handleQueue[handle] = newSource
            newSource.activate()
        }
	}
//	func unschedule(_ handle:ProcessHandle) {
//		internalSync.sync {
//			if let hasExisting = handleQueue[handle] {
////				hasExisting.cancel()
//				handleQueue[handle] = nil
//			}
//		}
//	}
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
internal enum pipe_errors:Error {
    case unableToCreatePipes
}
internal struct ExportedPipe:Hashable {
    let reading:Int32
    let writing:Int32
    
    internal static func rw() throws -> ExportedPipe {
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
                return ExportedPipe(r:readFD, w:writeFD)
            default:
                throw pipe_errors.unableToCreatePipes
        }
    }

    init(reading:Int32, writing:Int32) {
        self.reading = reading
        self.writing = writing
    }
    
    init(r:Int32, w:Int32) {
        self.writing = w
        self.reading = r
    }
    
    func closeReading() {
        _ = _close(reading)
    }
    
    func closeWriting() {
        _ = _close(writing)
    }

    func close() {
        _ = _close(writing)
        _ = _close(reading)
    }
    
    func hash(into hasher:inout Hasher) {
        hasher.combine(reading)
        hasher.combine(writing)
    }
    
    static func == (lhs:ExportedPipe, rhs:ExportedPipe) -> Bool {
        return lhs.reading == rhs.reading && lhs.writing == rhs.writing
    }
}

internal class ProcessPipes {
	private let internalSync:DispatchQueue

	let reading:ProcessHandle
	let writing:ProcessHandle
    
    //related to data intake
    private var _readBuffer = Data()
    private var _readLines = [Data]()
    private var _readGroup:DispatchGroup? = nil
    var readGroup:DispatchGroup? {
        get {
            internalSync.sync {
                return _readGroup
            }
        }
        set {
            internalSync.sync {
                _readGroup = newValue
            }
        }
    }
    
    private var _readQueue:DispatchQueue?
    var readQueue:DispatchQueue? {
        get {
            return internalSync.sync {
                return _readQueue
            }
        }
        set {
            return internalSync.sync {
                _readQueue = newValue
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
//						globalPR.unschedule(reading)
					}
					_readHandler = nil
				}
			}
		}
	}
    
    func intake(_ dataIn:Data) {
        readGroup?.enter()
        defer {
            readGroup?.leave()
        }
        let hasNewLine = dataIn.withUnsafeBytes { unsafeBuffer -> Bool in
            if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
                return true
            }
            return false
        }
        self.internalSync.sync {
            _readBuffer.append(dataIn)
            if hasNewLine {
                let sliceResult = _readBuffer.lineSlice(removeBOM:false, completeLinesOnly:true)
                if let parsedLines = sliceResult.lines {
                    _readBuffer.removeAll(keepingCapacity:true)
                    if let hasRemainder = sliceResult.remain, hasRemainder.count > 0 {
                        _readBuffer.append(hasRemainder)
                    }
                    if parsedLines.count > 0 {
                        let existingCount = _readLines.count
                        self._readLines.append(contentsOf:parsedLines)
                        if (existingCount == 0) {
                            _scheduleReadCallback()
                        }
                    }
                }
            }
        }
    }
    
    private func popPendingCallbackLines() -> ([Data]?, ReadHandler?) {
        return internalSync.sync {
            if self._readLines.count > 0 {
                let readLinesCopy = self._readLines
                self._readLines.removeAll(keepingCapacity: true)
                return (readLinesCopy, _readHandler)
            }
            return (nil, nil)
        }
    }
    
    private func _scheduleReadCallback() {
        if let hasHandler = _readHandler {
            for (_, curLine) in self._readLines.enumerated() {
                hasHandler(curLine)
            }
            self._readLines.removeAll(keepingCapacity: true)
        }
    }
	
    convenience init(read:DispatchQueue?) throws {
        self.init(try ExportedPipe.rw(), readQueue:read)
	}
	
    init(_ export:ExportedPipe, readQueue:DispatchQueue?) {
		self.reading = ProcessHandle(fd:export.reading)
		self.writing = ProcessHandle(fd:export.writing)
		self.internalSync = DispatchQueue(label:"com.tannersilva.instance.process-pipe.sync", target:global_lock_queue)
        self._readQueue = readQueue
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
	
//	func close() {
//		internalSync.sync {
//			guard _isClosed != true, _close(_fd) >= 0 else {
//				return
//			}
//
//			_isClosed = true
//		}
//	}
	
	func hash(into hasher:inout Hasher) {
		hasher.combine(_fd)
	}
	
	static func == (lhs:ProcessHandle, rhs:ProcessHandle) -> Bool {
		return lhs._fd == rhs._fd
	}
	
//	deinit {
//		if isClosed == false {
//			close()
//		}
//	}
}

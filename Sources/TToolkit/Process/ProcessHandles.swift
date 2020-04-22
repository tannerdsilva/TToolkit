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

internal protocol IODescriptor {
    var _fd:Int32 { get }
}

extension IODescriptor {
    func availableData() -> Data? {
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

internal protocol IOPipe {
    var reading:IODescriptor { get }
    var writing:IODescriptor { get }
}

extension Int32:IODescriptor {
    var _fd:Int32 {
        get {
            return self
        }
    }
    var fileDescriptor: Int32 {
        get {
            return self
        }
    }
}

internal class PipeReader {
	var master:DispatchQueue
	var internalSync:DispatchQueue

	//helps prevent duplicate schedules for line breakup events
	var pendingLineHandleSync:DispatchQueue	//concurrent
	var pendingLineBreaks = Set<Int32>()
	internal func needsLineBreak(_ handle:Int32) {
        //concurrent read of the handles already scheduled for a line dump
		let isScheduled:Bool = pendingLineHandleSync.sync {
            return pendingLineBreaks.contains(handle)
        }
		if isScheduled == false {
            //dispatch an async barrier to assign the existing file handle to the pending line breaks
            pendingLineHandleSync.async(flags:[.barrier, .noQoS]) { [weak self] in
                self!.pendingLineBreaks.update(with: handle)
            }
			handlerSync.sync {
				outboundQueues[handle]!.async(flags:[.inheritQoS]) { [weak self] in
					let intakeHandle = self!.handlerSync.sync {
						return self!.handlers[handle]!
					}
					if let clearedLines = self!.flushLines(handle) {
						for (_, curLine) in clearedLines.enumerated() {
							intakeHandle(curLine)
						}
					}
				}
			}
		}
	}
    
	internal func clearLineBreak(_ handle:Int32) {
        pendingLineHandleSync.async(flags:[.barrier, .noQoS]) { [weak self] in
			_ = self!.pendingLineBreaks.remove(handle)
		}
	}
	
	//line cache is accessable atomicallly through lineSync
	var handlerSync:DispatchQueue   //concurrent
    var handlers = [Int32:InteractiveProcess.OutputHandler]()
	var outboundQueues = [Int32:DispatchQueue]()  //these target intake or external queues
	
	//hot file handles are stored and buffered here
	var bufferSync:DispatchQueue
	var bufferLocks = [Int32:DispatchQueue]()
	var sources = [Int32:DispatchSourceProtocol]()
	var buffers = [Int32:Data]()
	internal func bufferSync<R>(_ handle:Int32, _ work:() throws -> R) rethrows -> R {
		return try bufferSync.sync {
			return try bufferLocks[handle]!.sync {
				return try work()
			}
		}
	}
	
	init() {
		self.master = DispatchQueue(label:"com.tannersilva.global.pipe.read.master", attributes:[.concurrent], target:process_master_queue)
		self.internalSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.sync", attributes:[.concurrent], target:self.master)
		
		//serial queues for marking file handles with pending line breaks and callback events scheduled in an asynchronous workload
        self.pendingLineHandleSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.linebreak.sync", attributes:[.concurrent], target:self.internalSync)

        self.handlerSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.buffer.line.sync", target:self.internalSync)
		self.bufferSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.buffer.raw.sync", attributes:[.concurrent], target:self.internalSync)
	}
		
	internal func readHandle(_ handle:Int32) {
		if let newData = handle.availableData(), newData.count > 0 {
			bufferSync(handle) {
				buffers[handle]!.append(newData)
				newData.withUnsafeBytes({ unsafeBuffer in
					if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
						needsLineBreak(handle)
					}
				})
			}
		}
	}
	
	internal func flushLines(_ handle:Int32) -> [Data]? {
		return bufferSync(handle) {
			let parseResult = buffers[handle]!.lineSlice(removeBOM:false, completeLinesOnly:true)
			buffers[handle]!.removeAll(keepingCapacity:true)
			if parseResult.remain != nil && parseResult.remain!.count > 0 {
				buffers[handle]!.append(parseResult.remain!)
			}
			clearLineBreak(handle)
			return parseResult.lines
		}
	}
	
	let launchSignaler = DispatchSemaphore(value:1)
	func scheduleForReading(_ handle:Int32, queue:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler)) {
		bufferSync.sync(flags:[.barrier]) {
			self.bufferLocks[handle] = DispatchQueue(label:"com.tannersilva.global.pipe.read.buffer.raw.sync", target:self.master)
			self.sources[handle] = DispatchSource.makeReadSource(fileDescriptor:handle, queue:Priority.highest.globalConcurrentQueue)
			self.sources[handle]!.setEventHandler(handler: { [weak self] in
                self?.readHandle(handle)
            })
			self.buffers[handle] = Data()
			self.handlerSync.async(flags:[.barrier, .noQoS]) {
                self.handlers[handle] = handler
                self.outboundQueues[handle] = queue
			}
			sources[handle]!.activate()
		}
	}
}
internal let globalPR = PipeReader()

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

internal class ProcessHandle:Hashable, IODescriptor {
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
	
	internal let _fd:Int32
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

	func hash(into hasher:inout Hasher) {
		hasher.combine(_fd)
	}
	
	static func == (lhs:ProcessHandle, rhs:ProcessHandle) -> Bool {
		return lhs._fd == rhs._fd
	}
}

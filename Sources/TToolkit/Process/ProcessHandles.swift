import Dispatch
import Foundation

#if canImport(Darwin)
	import Darwin
	internal let _read = Darwin.read(_:_:_:)
	internal let _write = Darwin.write(_:_:_:)
	internal let _close = Darwin.close(_:)
	internal let o_cloexec = Darwin.O_CLOEXEC
	internal let _pipe = Darwin.pipe(_:)
#elseif canImport(Glibc)
	import Glibc
	internal let _read = Glibc.read(_:_:_:)
	internal let _write = Glibc.write(_:_:_:)
	internal let _close = Glibc.close(_:)
	internal let o_cloexec = Glibc.O_CLOEXEC
	internal let _pipe = Glibc.pipe(_:)
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
            readBlockSize = 10240
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
    
    func availableDataLoop(_ outputFunction:(Data?) -> Void) {
        while let curData = self.availableData(), curData.count > 0 {
            outputFunction(curData)
        }
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
    private class HandleState {
        let handle:Int32
        let source:DispatchSourceProtocol
        
        private let callbackQueue:DispatchQueue
        
        private let internalSync:DispatchQueue
        
        //pending new lines
        private var _pnl:Bool = false
        var pendingNewLines:Bool {
            get {
                return _pnl
            }
            set {
                if _pnl == false && newValue == true {
                    _pnl = true
                    scheduleLineCallback()
                } else if _pnl == true && newValue == false {
                    _pnl = false
                }
            }
        }
        
        private var buffer = Data()
        
        private var handler:InteractiveProcess.OutputHandler
        
        init(handle:Int32, callback:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler), source:DispatchSourceProtocol, capture:DispatchQueue) {
            self.handle = handle
            internalSync = DispatchQueue(label:"com.tannersilva.instance.pipe.read.internal.sync")
            callbackQueue = DispatchQueue(label:"com.tannersilva.instance.pipe.read.callback-target.serial", target:callback)
            self.handler = handler
            self.source = source
        }
        
        
        internal func intakeData(_ data:Data) {
            internalSync.sync {
                buffer.append(data)
                data.withUnsafeBytes({ unsafeBuffer in
                    if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) && pendingNewLines == false {
                        pendingNewLines = true
                    }
                })
        	}
        }
        
        func scheduleLineCallback() {
            callbackQueue.async {
                self.internalSync.async {
                    self.pendingNewLines = false
                }
                if let linesToCallback = self.extractLines() {
                    for (_, curLine) in linesToCallback.enumerated() {
                        self.handler(curLine)
                    }
                }
            }
        }

        func extractLines() -> [Data]? {
        	return internalSync.sync {
        		let parseResult = buffer.lineSlice(removeBOM:false, completeLinesOnly:true)
                buffer.removeAll(keepingCapacity: true)
                if parseResult.remain != nil && parseResult.remain!.count > 0 {
                    buffer.append(parseResult.remain!)
                }
                return parseResult.lines
        	}
        }
    }
    
    var flightGroup = DispatchGroup()
    
	var master:DispatchQueue
	var internalSync:DispatchQueue
    
    var instanceMaster:DispatchQueue

    var accessSync:DispatchQueue
    private var handles = [Int32:PipeReader.HandleState]()
    private func access(_ handle:Int32, _ work:(PipeReader.HandleState) -> Void) {
        flightGroup.enter()
        defer {
            flightGroup.leave()
        }
        accessSync.sync {
            return { [bufState = self.handles[handle]!] in
                work(bufState)
            }()
        }
    }
    private func accessModify(_ work:() -> Void) {
        flightGroup.enter()
        defer {
            flightGroup.leave()
        }
        accessSync.sync(flags:[.barrier]) {
            work()
        }
    }
	
	init() {
		self.master = DispatchQueue(label:"com.tannersilva.global.pipe.read.master", attributes:[.concurrent], target:process_master_queue)
		self.internalSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.sync", attributes:[.concurrent], target:self.master)
        
        self.instanceMaster = DispatchQueue(label:"com.tannersilva.instance.pipe.read.master", attributes:[.concurrent], target:self.master)
    
        self.accessSync = DispatchQueue(label:"com.tannersilva.global.pipe.handle.access.sync", attributes:[.concurrent], target:self.master)
	}
    
	
    let launchSem = DispatchSemaphore(value:1)
	func scheduleForReading(_ handle:Int32, queue:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler)) {
        let intakeQueue = DispatchQueue(label:"com.tannersilva.instance.pipe.handle.read.capture", target:global_pipe_read)
        let newSource = DispatchSource.makeReadSource(fileDescriptor:handle, queue:global_pipe_read)
        let newHandleState = PipeReader.HandleState(handle:handle, callback: queue, handler:handler, source: newSource, capture: intakeQueue)
        newSource.setEventHandler(handler: { [handle, newHandleState] in
            handle.availableDataLoop({ [newHandleState] (someData) in
//                print(Colors.dim(" \(handle) -> \(someData?.count) bytes"))
                if let validateData = someData {
                    newHandleState.intakeData(validateData)
                }
            })
        })
        accessModify({
            self.handles[handle] = newHandleState
            print(Colors.green("SUCCESSFULLY INSERTED WITH BARRIER \(handle)"))
            newSource.activate()
        })
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
        
        let rwfds = file_handle_guard.sync {
            return _pipe(fds)
        }
        
        switch rwfds {
            case 0:
                let readFD = fds.pointee
                let writeFD = fds.successor().pointee
				fcntl(readFD, F_SETFL, O_NONBLOCK)
                print(Colors.magenta("created for reading [NONBLOCK]: \(readFD)"))
                print(Colors.magenta("created for writing: \(writeFD)"))
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
        file_handle_guard.async { [reading = self.reading] in
            _ = _close(reading)
        }
    }
    
    func closeWriting() {
        file_handle_guard.async { [writing = self.writing] in
            _ = _close(writing)
        }
    }

    func close() {
        file_handle_guard.async { [reading = self.reading, writing = self.writing] in
            _ = _close(writing)
            _ = _close(reading)
        }
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

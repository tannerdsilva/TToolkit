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
    private class HandleState {
        let handle:Int32
        
        private let callbackQueue:DispatchQueue
        private let internalSync:DispatchQueue
        private var _pnl:Bool = false
        var pendingNewLines:Bool {
            get {
                return internalSync.sync {
                    return _pnl
                }
            }
        }
        
        private var buffer = Data()
        private let bufferSync:DispatchQueue
        
        private var handler:InteractiveProcess.OutputHandler
        
        init(handle:Int32, syncMaster:DispatchQueue, callback:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler), source:DispatchSourceProtocol) {
            self.handle = handle
            internalSync = DispatchQueue(label:"com.tannersilva.instance.pipe.read.internal.sync", target:syncMaster)
        	bufferSync = DispatchQueue(label:"com.tannersilva.instance.pipe.read.buffer.sync", target:syncMaster)
            callbackQueue = DispatchQueue(label:"com.tannersilva.instance.pipe.read.callback-target.serial", target:callback)
            self.handler = handler
        }
        
        internal func _intake(_ data:Data) -> Bool {
        	return bufferSync.sync {
                buffer.append(data)
                return data.withUnsafeBytes({ unsafeBuffer in
                    if unsafeBuffer.contains(where: { $0 == 10 || $0 == 13 }) {
                        return internalSync.sync {
                            defer { _pnl = true }
                            if _pnl == false {
                                return true
                            }
                            return true
                        }
                    }
                    return false
                })
        	}
        }
        
        func intake(_ data:Data?) {
            if data != nil && data!.count > 0 && _intake(data!) {
                callbackQueue.async(flags:[.inheritQoS]) { [weak self, handlerToCall = self.handler] in
                    let lineExtract = self!.extractLines()
                    if lineExtract != nil {
                        for (_, curLine) in lineExtract!.enumerated() {
                            handlerToCall(curLine)
                        }
                    }
                }
            }
        }
        func extractLines() -> [Data]? {
            internalSync.async { [weak self] in
                self!._pnl = false
            }
            
        	return bufferSync.sync {
        		let parseResult = buffer.lineSlice(removeBOM:false, completeLinesOnly:true)
                buffer.removeAll(keepingCapacity: true)
                if parseResult.remain != nil && parseResult.remain!.count > 0 {
                    buffer.append(parseResult.remain!)
                }
                return parseResult.lines
        	}
        }
    }
    
	var master:DispatchQueue
	var internalSync:DispatchQueue
    
    var instanceMaster:DispatchQueue

    var accessSync:DispatchQueue
    private var handles = [Int32:PipeReader.HandleState]()
    private func access<R>(_ handle:Int32, _ work:(PipeReader.HandleState) throws -> R) rethrows -> R {
    	return try accessSync.sync {
            return try { [weak bufState = self.handles[handle]!] in
                return try work(bufState!)
            }()
    	}
    }
    private func accessBlock<R>(_ work:() throws -> R) rethrows -> R {
        return try accessSync.sync(flags:[.barrier]) {
            return try work()
        }
    }
	
	init() {
		self.master = DispatchQueue(label:"com.tannersilva.global.pipe.read.master", attributes:[.concurrent], target:process_master_queue)
		self.internalSync = DispatchQueue(label:"com.tannersilva.global.pipe.read.sync", attributes:[.concurrent], target:self.master)
        
        self.instanceMaster = DispatchQueue(label:"com.tannersilva.instance.pipe.read.master", attributes:[.concurrent], target:self.master)
    
        self.accessSync = DispatchQueue(label:"com.tannersilva.global.pipe.handle.access.sync", attributes:[.concurrent], target:self.master)
	}
    
	internal func readHandle(_ handle:Int32) {
        access(handle) { handleState in
            handleState.intake(handle.availableData())
        }
        print(Colors.dim("Successfully captured \(handle)"))
	}
	
	func scheduleForReading(_ handle:Int32, queue:DispatchQueue, handler:@escaping(InteractiveProcess.OutputHandler)) {
        accessBlock({
            let newSource = DispatchSource.makeReadSource(fileDescriptor:handle, queue:Priority.highest.globalConcurrentQueue)
            handles[handle] = PipeReader.HandleState(handle:handle, syncMaster:instanceMaster, callback: queue, handler:handler, source: newSource)
            newSource.setEventHandler(handler: { [weak self] in
                self?.readHandle(handle)
            })
            newSource.activate()
            print(Colors.BgRed("! ACTIVATED ! \(handle)"))
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

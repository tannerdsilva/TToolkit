//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping
fileprivate let _explodeGlobal = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])

extension Collection {
    fileprivate func sequenceBuffer<R>(_ work:@escaping(UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
		let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: self.count)
        _ = buffer.initialize(from: self)
		defer {
			buffer.deallocate()
		}
		return try work(UnsafeBufferPointer(buffer))
	}

	public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
		self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			unsafeBuff._explode_v(using:thisFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?, merge mergeFunction:@escaping (Int, T) -> Void) {
		self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			unsafeBuff._explode_v_merge(using:thisFunction, merge:mergeFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?) -> Set<T> where T:Hashable {
		return self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)")
			return unsafeBuff._explode_r_set(using:thisFunction)
		} ?? Set<T>()
	}
	
	public func explode<T, U>(using thisFunction:@escaping (Int, Element) -> (key:T, value:U)) -> [T:U] where T:Hashable {
		return self.sequenceBuffer { unsafeBuff in
			print("O? \(unsafeBuff.count)" )
			return unsafeBuff._explode_r_dict(using:thisFunction)
		} ?? [T:U]()
	}
}


extension UnsafeBufferPointer {
	//explode - no return values	
	fileprivate func _explode_v(using thisFunction:@escaping (Int, Element) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
        print("GO?")
        let launchSem = DispatchSemaphore(value:ProcessInfo.processInfo.activeProcessorCount)
       Priority.`default`.globalConcurrentQueue.sync {
            DispatchQueue.concurrentPerform(iterations:count) { n in
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
                print("\(n) - \(count)")

                try? thisFunction(n, startIndex.advanced(by:n).pointee)
           }
	 print("fin?")
        }
	}

	//explode a collection - allows the user to handle the merging of data themselves.
	//return values of the primary `explode` block are passed to a serial thread where the user can handle the data as necessary
	fileprivate func _explode_v_merge<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
        
        let launchSem = DispatchSemaphore(value:ProcessInfo.processInfo.activeProcessorCount)
		let mergeQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
       Priority.`default`.globalConcurrentQueue.sync {
            DispatchQueue.concurrentPerform(iterations:count) { n in
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
                print("\(n) - \(count)")

                if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
                    mergeQueue.async {
                        try? mergeFunction(n, returnedValue)
                    }
                }
            }
       }
         print("fin?")
		return mergeQueue.sync { return }
	}

	//explode a collection - returns a set of hashable objects
	fileprivate func _explode_r_set<T>(using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
		guard let startIndex = baseAddress else {
			return Set<T>()
		}
        let launchSem = DispatchSemaphore(value:ProcessInfo.processInfo.activeProcessorCount)
		var buildData = Set<T>()
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
       Priority.`default`.globalConcurrentQueue.sync {
            DispatchQueue.concurrentPerform(iterations:count) { n in

//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
                print("\(n) - \(count)")

                if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
                    callbackQueue.async {
                        buildData.update(with:returnedValue)
                    }
                }
           }
        }
         print("fin?")
		return callbackQueue.sync { return buildData }
	}

	//explode a collection - returns a dictionary
	fileprivate func _explode_r_dict<T, U>(using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
		guard let startIndex = baseAddress else {
			return [T:U]()
		}
        let launchSem = DispatchSemaphore(value:ProcessInfo.processInfo.activeProcessorCount)
        var buildData = [T:U]()
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge")
       Priority.`default`.globalConcurrentQueue.sync {
            DispatchQueue.concurrentPerform(iterations:count) { n in
                print("\(n) - \(count)")
//               launchSem.wait()
//               defer {
//                   launchSem.signal()
//               }
                if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
                    if returnedValue.value != nil {
                        callbackQueue.async {
                            buildData[returnedValue.key] = returnedValue.value
                        }
                    }
                }
            }
	        print("fin?")
		}
		return callbackQueue.sync { return buildData }
	}
}

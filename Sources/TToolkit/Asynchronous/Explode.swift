//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping
fileprivate let _explodeGlobal = DispatchQueue(label:"com.tannersilva.function.explode.merge", attributes:[.concurrent])

extension Sequence {
	public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
		self.withContiguousStorageIfAvailable { unsafeBuff in
			unsafeBuff._explode(using:thisFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?, merge mergeFunction:@escaping (Int, T) -> Void) {
		self.withContiguousStorageIfAvailable { unsafeBuff in
			unsafeBuff._explode(using:thisFunction, merge:mergeFunction)
		}
	}
	
	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?) -> Set<T> where T:Hashable {
		return self.withContiguousStorageIfAvailable { unsafeBuff in
			return unsafeBuff.explode(using:thisFunction)
		} ?? Set<T>()
	}
	
	public func explode<T, U>(using thisFunction:@escaping (Int, Element) -> (key:T, value:U)) -> [T:U] where T:Hashable {
		return self.withContiguousStorageIfAvailable { unsafeBuff in
			return unsafeBuff.explode(using:thisFunction)
		} ?? [T:U]()
	}
}

extension UnsafeBufferPointer {
	//explode - no return values	
	fileprivate func _explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
		DispatchQueue.concurrentPerform(iterations:count) { n in
			try? thisFunction(n, startIndex.advanced(by:n).pointee)
		}
	}

	//explode a collection - allows the user to handle the merging of data themselves.
	//return values of the primary `explode` block are passed to a serial thread where the user can handle the data as necessary
	fileprivate func _explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
		guard let startIndex = baseAddress else {
			return
		}
		let mergeQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:_explodeGlobal)
		DispatchQueue.concurrentPerform(iterations:count) { n in
			if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
				mergeQueue.async {
				 	try? mergeFunction(n, returnedValue)
				}
			}
		}
		return mergeQueue.sync { return }
	}

	//explode a collection - returns a set of hashable objects
	fileprivate func _explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
		guard let startIndex = baseAddress else {
			return Set<T>()
		}
		var buildData = Set<T>()
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:_explodeGlobal)
		DispatchQueue.concurrentPerform(iterations:count) { n in
			if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
				callbackQueue.async {
				 	buildData.update(with:returnedValue)
				}
			}
		}
		return callbackQueue.sync { return buildData }
	}

	//explode a collection - returns a dictionary
	fileprivate func _explode<T, U>(using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
		guard let startIndex = baseAddress else {
			return [T:U]()
		}
		var buildData = [T:U]()
		let callbackQueue = DispatchQueue(label:"com.tannersilva.function.explode.merge", target:_explodeGlobal)
		DispatchQueue.concurrentPerform(iterations:count) { n in
			if let returnedValue = try? thisFunction(n, startIndex.advanced(by:n).pointee) {
				if returnedValue.value != nil {
					callbackQueue.async {
						buildData[returnedValue.key] = returnedValue.value
					}
				}
			}
		}
		return callbackQueue.sync { return buildData }
	}
}
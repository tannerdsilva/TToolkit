//
//  ExplodeExtensions.swift
//  Cryptor
//
//  Created by Tanner Silva on 10/17/19.
//

import Foundation

//explosions allow for multi-threaded collection mapping
fileprivate let _explodeGlobal = DispatchQueue(label:"com.tannerdsilva.global.function.explode", attributes:[.concurrent])

//extension Collection {
//    fileprivate func sequenceBuffer<R>(_ work:@escaping(UnsafeBufferPointer<Element>) throws -> R) rethrows -> R {
//		let buffer = UnsafeMutableBufferPointer<Element>.allocate(capacity: self.count)
//        _ = buffer.initialize(from: self)
//		defer {
//			buffer.deallocate()
//		}
//		return try work(UnsafeBufferPointer(buffer))
//	}
//
//	public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
//		self.sequenceBuffer { unsafeBuff in
//			print("O? \(unsafeBuff.count)")
//			unsafeBuff._explode_v(using:thisFunction)
//		}
//	}
//	
//	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?, merge mergeFunction:@escaping (Int, T) -> Void) {
//		self.sequenceBuffer { unsafeBuff in
//			print("O? \(unsafeBuff.count)")
//			unsafeBuff._explode_v_merge(using:thisFunction, merge:mergeFunction)
//		}
//	}
//	
//	public func explode<T>(using thisFunction:@escaping (Int, Element) -> T?) -> Set<T> where T:Hashable {
//		return self.sequenceBuffer { unsafeBuff in
//			print("O? \(unsafeBuff.count)")
//			return unsafeBuff._explode_r_set(using:thisFunction)
//		} ?? Set<T>()
//	}
//	
//	public func explode<T, U>(using thisFunction:@escaping (Int, Element) -> (key:T, value:U)) -> [T:U] where T:Hashable {
//		return self.sequenceBuffer { unsafeBuff in
//			print("O? \(unsafeBuff.count)" )
//			return unsafeBuff._explode_r_dict(using:thisFunction)
//		} ?? [T:U]()
//	}
//}

extension Collection {
	//explode a collection - no return values
    public func explode(using thisFunction:@escaping (Int, Element) throws -> Void) {
        guard count > 0 else {
        	return
        }
        
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        let iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	try? thisFunction(n, thisItem)
        }
    }
    
    //explode a collection - allows the user to handle the merging of data themselves
    public func explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?, merge mergeFunction:@escaping (Int, T) throws -> Void) {
        guard count > 0 else {
        	return
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        let iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let returnQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	if let returnedValue = try? thisFunction(n, thisItem) {
        		returnQueue.sync {
        			try? mergeFunction(n, returnedValue)
        		}
        	}
        }
    }
    
    //explode a collection - returns a set of hashable objects
    public func explode<T>(using thisFunction:@escaping (Int, Element) throws -> T?) -> Set<T> where T:Hashable {
        guard count > 0 else {
        	return
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        let iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let buildQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var buildData = Set<T>()
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	if let returnedValue = try? thisFunction(n, thisItem) {
        		returnQueue.sync {
        			buildData.update(with:returnedValue)
        		}
        	}
        }
        
        return buildData
    }
    
    //explode a collection - returns a dictionary
    public func explode<T, U>(using thisFunction:@escaping (Int, Element) throws -> (key:T, value:U)) -> [T:U] where T:Hashable {
        guard count > 0 else {
        	return
        }
        
        //pre-processing access
        let enumerateQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        let iterator = self.makeIterator()
        func getNext() -> Self.Element? {
        	return enumerateQueue.sync {
        		return iterator.next()
        	}
        }
        
        //post-process merging
        let buildQueue = DispatchQueue(label:"com.tannersilva.function.explode.enumerate", target:_explodeGlobal)
        var buildData = Set<T>()
        
        //process
        DispatchQueue.concurrentPerform(iterations:count) { n in
        	guard let thisItem = getNext() else {
        		return
        	}
        	if let returnedValue = try? thisFunction(n, thisItem) {
        		returnQueue.sync {
        			buildData.update(with:returnedValue)
        		}
        	}
        }
        
        return buildData
    }
}

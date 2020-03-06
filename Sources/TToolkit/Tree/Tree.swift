import Foundation

enum Child:UInt8 {
	case left
	case right
}

class Tree<T> where T:Comparable {
	private var val:T? = nil
	
	private var childCount:Int = 0
	
	private var left:Tree<T>? = nil
	private var right:Tree<T>? = nil

	//build a tree with a collection of objects
	public init<U>(_ input:U) where U:Collection, U.Element == T {
		childCount = input.count
		for (n, curVal) in input.enumerated() {
			switch n {
				case 0:
					val = curVal
				default:
					if val! > curVal {
						if left != nil {
							left!.insert(curVal)
						} else {
							left = Tree(curVal)
						}
					} else {
						if right != nil {
							right!.insert(curVal)
						} else {
							right = Tree(curVal)
						}
					}
			}
		}
	}
	
	public init(_ input:T?) {
		val = input
		childCount = 1
	}
	
	public func forEveryValue(_ doThisWork:@escaping(T) throws -> Void) rethrows {
		if val != nil {
			try doThisWork(val!)
		}
		if left != nil {
			try left!.forEveryValue(doThisWork)
		}
		if right != nil {
			try right!.forEveryValue(doThisWork)
		}
	}
	
	//return the side that has a higher number of children
	private var imbalance:Child? {
		get {
			let leftCount = left?.childCount ?? 0
			let rightCount = right?.childCount ?? 0
			
			let absoluteDelta = Int(abs(leftCount - rightCount))
			
			if leftCount == rightCount || absoluteDelta < 2 {
				return nil
			} else if leftCount < rightCount {
				return .right
			} else if rightCount < leftCount {
				return .left
			}
			return nil
		}
	}
	
	public func insert(_ newValue:T) {
		if val == nil { 
			val = newValue
		} else if val! > newValue {
			if left != nil {
				left!.insert(newValue)
			} else {
				left = Tree<T>(newValue)
			}
		} else {
			if right != nil {
				right!.insert(newValue)
			} else {
				right = Tree<T>(newValue)
			}
		}
		childCount += 1
	}
		
	//build the child values of the tree into the given array pointer
	internal func childValues(_ buildArray:inout Array<T>) {
		if val != nil {
			buildArray.append(val!)
		}

		if left != nil {
			left!.childValues(&buildArray)
		}
		
		if right != nil {
			right!.childValues(&buildArray)
		}
	}
	
	//what are the child values of the tree
	public var childValues:[T] {
		get {
			var buildChildValues = [T]()
			
			if let hasLeft = left { 
				hasLeft.childValues(&buildChildValues)
			}
			
			if val != nil {
				buildChildValues.append(val!)
			}
			
			if let hasRight = right {
				hasRight.childValues(&buildChildValues)
			}

			return buildChildValues 
		}
	}
		
	//how deep is this tree?
	public var depth:Int {
		get {
			var leftDepth:Int? = nil
			if left != nil {
				leftDepth = left!.depth
			}

			var rightDepth:Int? = nil
			if right != nil {
				rightDepth = right!.depth
			}

			if leftDepth != nil && rightDepth != nil {
				if leftDepth! > rightDepth! {
					return leftDepth! + 1
				} else {
					return rightDepth! + 1
				}
			} else if leftDepth != nil {
				return leftDepth! + 1
			} else if rightDepth != nil {
				return rightDepth! + 1
			} else {
				return 0
			}
		}
	}
}
import Foundation

enum Child:UInt8 {
	case left
	case right
}

fileprivate let tree_master_queue = DispatchQueue(label:"com.tannersilva.global.tree.access", attributes:[.concurrent])
fileprivate let tree_master_lock = DispatchQueue(label:"com.tannersilva.global.tree.instance", attributes:[.concurrent])

class Tree<T> where T:Comparable {
    fileprivate let _instanceSync = DispatchQueue(label:"com.tannersilva.instance.tree.sync", target:tree_master_lock)
    fileprivate var _queue = DispatchQueue(label:"com.tannersilva.instance.tree.node.access", attributes: [.concurrent], target:tree_master_queue)
    fileprivate var queue:DispatchQueue {
        get {
            _instanceSync.sync {
                return _queue
            }
        }
    }
    fileprivate var _parent:Tree<T>? = nil
    internal var parent:Tree<T>? {
        get {
            queue.sync {
                return _parent
            }
        }
        set {
            _instanceSync.async { [weak self, newValue] in
                self?._queue.async(flags:[.barrier]) { [weak self, newValue] in
                    self?._parent = newValue
                }
                
            }
        }
    }
    
	fileprivate var _val:T? = nil
    internal var val:T? {
        get {
            queue.sync {
                return _val
            }
        }
        set {
            queue.async(flags:[.barrier]) { [weak self, newValue] in
                self?._val = newValue
            }
        }
    }
    fileprivate var val_:T? {
            get {
               _queue.sync(flags:[.barrier]) {
                   return _val
               }
           }
           set {
               _queue.async(flags:[.barrier]) { [weak self, newValue] in
                    self?._val = newValue
               }
           }
    }
    
    fileprivate var _left:Tree<T>? = nil
    internal var left:Tree<T>? {
        get {
            queue.sync {
                return _left
            }
        }
        set {
            queue.async(flags:[.barrier]) { [weak self, newValue] in
                self?._left = newValue
            }
        }
    }
    fileprivate var left_:Tree<T>? {
        get {
            _queue.sync(flags:[.barrier]) {
                return _left
            }
        }
        set {
            _queue.async(flags:[.barrier]) { [weak self, newValue] in
                self?._left = newValue
            }
        }
    }

    
	fileprivate var _right:Tree<T>? = nil
    internal var right:Tree<T>? {
        get {
            queue.sync {
                return _right
            }
        }
        set {
            queue.async(flags:[.barrier]) { [weak self, newValue] in
                self?._right = newValue
            }
        }
    }
    fileprivate var right_:Tree<T>? {
        get {
            _queue.sync(flags:[.barrier]) {
                return _right
            }
        }
        set {
            _queue.async(flags:[.barrier]) { [weak self, newValue] in
                self?._right = newValue
            }
        }
    }


	public func insert(_ newValue:T) {
        _instanceSync.async { [newValue] in
            if self.val_ == nil {
                self.val_ = newValue
            } else if self.val_! > newValue {
                if self.left_ != nil {
                    self.left_!.insert(newValue)
                } else {
                    let newTree = Tree<T>(newValue)
                    newTree.parent = self
                    self.left_ = newTree
                }
            } else {
                if self.right_ != nil {
                    self.right_!.insert(newValue)
                } else {
                    let newTree = Tree<T>(newValue)
                    newTree.parent = self
                    self.right_ = Tree<T>(newValue)
                    self.right_!.parent = self
                }
            }
        }
    }
    
    init(_ inVal:T?) {
        val = inVal
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

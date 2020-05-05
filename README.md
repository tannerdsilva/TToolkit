# TToolkit

*tl;dr*: A library of low-level functions for developing *very* fast backend automations in Swift.

Import this into your Swift package with the following dependency declaration

`.package(url: "https://github.com/tannerdsilva/TToolkit.git", .branch("swiftslash"))`

# What does TToolkit do?

## 🔥 SwiftSlash 🔥
### High-Performance Concurrent Shell Framework

**Concurrent shell functionality in TToolkit will soon be forked as an independent framework - to be named SwiftSlash. In its current form [this repository], SwiftSlash represents a fully developed internal core but a minimal external API.**

TToolkit's `SwiftSlash` classes were born from a need for interface with large sets of concurrently executed processes with complete instructional safety. Furthermore, `SwiftSlash` was built with an uncompromising desire for time efficiency.

Swift's own `Foundation` framework offers classes that theoretically deliver shell-like functionality, however, in practice, these classes do not hold together well under intense, prolonged workloads. From this unfortunate discovery came the need to reimplement Foundation frameworks `Process`, `Pipe` and `FileHandle` classes from scratch to achieve a more robust shell/process framework - one that can operate in an time-sensitive, concurrent environment.

When comparing TToolkits `SwiftSlash` with Foundation's `Process` class (used by the popular *SwiftShell* framework), the performance improvements of `SwiftSlash` speak for themselves.

- Foundation's `Process` class **will leak memory** as many class instances are created. This means that `Process` classes can not be treated as transactional objects, *despite transactional use being the intended lifecycle*! By comparison, `SwiftSlash` instances need an **order of magnitude** less memory, and do not leak their contents after use. `SwiftSlash` classes are transactional by nature, and the internal resource management reflects this pattern.

- `SwiftSlash` is completely safe to use concurrently and asynchronously, unlike `Process` class, which takes neither of these features into consideration. By allowing shell commands to be run concurrently rather than serially, `SwiftSlash` can complete complex multi-command workloads in **fractions** of their expected time.

- `SwiftSlash` can initialize and launch an external command with significantly greater computational and memory efficiency than Foundation's `Process` class. Similar performance improvements are seen in reading data from the `stdin`, `stdout`, and `stderr` streams. For industrial workloads, better performance means a faster time to completion. For mobile workloads, better performance means better battery life.

- `SwiftSlash` has the necessary infrastructure to **ensure a secure execution environment**. `Process` class has many security vulnerabilities, including file handle sharing with the executing process and improper changing of the specified *current directory*.

- `SwiftSlash` **can scale to massive workloads without consuming equally massive resources or time**. 

By executing shell commands concurrently rather than serially, one could see speedup multiples of *up to* 250x - *workload dependent*

The functional internal core of SwiftSlash can be found at the following subpath of this repository: `./Sources/TToolkit/SwiftSlash`

## Other Asynchronous/Concurrent Utilities

### Explosions! :D

Explosions allow for *very* high performance concurrent collection remapping. Just as a standard `map` function will transform a collection with a single thread, `explode` will do the same with multiple concurrent worker threads.

Explosions are also useful for expanding large sets of data quickly. For example, a collection of URL's might be exploded to allow for multiple URL's to be fetched asyncronously.

Every variant of the `explode` functions has a leading argument: `lanes:Int` in which the numer of actively working threads can be defined. When a lane count is not provided, TToolkit will assign the appropriate lane count based on your hardware.

```
//Explode - Example 1: Reverse a collection of strings using 2 concurrent workers

let myCollection:[String] = ["Item1", "Item2", "Item3", ...]

let reversedCollection:[String] = myCollection.explode(lanes:2, using: { (n, curItem) -> String in

	return curItem.reversed()
	
})

```

Explode has a variant that returns void, allowing the user to handle the processed data manually using a separate serial block. _(See example 2)_

```
//Explode - Example 2: Pass the results of concurrent work to a serial queue for manual processing

let manyImages = ["https://wikipedia.com/img.jpg", "https://tesla.com/img.jpg", ...]

manyImages.explode(using: { (n, curImageURL) -> Data in

	//this block is where the async work takes place
	return try internet.download(curImageURL)
	
}, merge: { (n, thisData) in

	//return values from async blocks are passed into this serial block for processing
	myPrinterObject.printImageData(thisData)
	
})
```

### Time Control

`TTimer` allows for precise control of code execution in relation to time. `TTimer` can be (optionally) recurring, delayed, and anchored to precise moments in system time.


## Data Manipulation
### High Performance Line Parsing

Given any `Data` variable, TToolkit's `Data` extension `lineSlice()` automatically detects the three common types of line breaks used in a data variable and returns an array of lines.

Supports linebreaks in CR, LF, and CRLF.

The data line slicing functions also have the ability to detect and stip the byte order mark from the beginning of a data sequence. Default behavior is to strip any known BOM sequence from the beginning of a Data variable, however, this behavior can be overridden.

### CSV encoding and decoding

TToolkit defines a protocol `CSVEncodable` for making any structure or class codable to a CSV format.

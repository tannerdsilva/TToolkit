# TToolkit

A library of convenience functions that use when developing applications in Swift on Linux.

Import this into your Swift package with the following dependency declaration

`.package(url: "https://github.com/tannerdsilva/TToolkit.git", .branch("master"))`

## What does TToolkit do?

### Asynchronous Explosions! :D

Explosions allow for very high performance multithreaded collection remapping. Just as a standard `map` function will transform a collection with a single thread, `explode` will do the same with multiple concurrent worker threads.

Explosions are also useful for explanding large sets of data quicly. For example, a collection of URL's might be exploded to allow for multiple URL's to be fetched asyncronously.

Every variant of the `explode` functions has a leading argument: `lanes:Int` in which the numer of actively working threads can be defined.  Lanes can be though of as the maximum number of threads that will be executed at any given time. When one lane is finished executing, another lane _(if available)_ will begin executing in its place.

### CSV encoding and decoding

TToolkit defines a protocol `CSVEncodable` for making any structure or class codable to a CSV format.

### Data Line Slicing

Automatically detects the three common types of line breaks used in a data variable and splits accordingly.

Supports linebreaks in CR, LF, and CRLF.

The data line slicing functions also have the ability to detect and stip the byte order mark from the beginning of a data sequence. Default behavior is to strip any known BOM sequence from the beginning of a Data variable, however, this behavior can be overridden.

### Interactive Process Interface

Do you need to write a process that can launch and interact with other processes safely? The `InteractiveProcess` class has you covered! With this object (and the help of `explode`), you can easily spin up thousands of processes to import, process, and build data very quickly.

With the `InteractiveProcess` class, you can not only read stderr and stdout from a process in real time. Unlike other shell interfaces, `InteractiveProcess` allows you to write to a process while also reading from it. This makes it very helpful for executing against interactive shells and processes.
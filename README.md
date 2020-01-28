# TToolkit

A library of convenience functions that use when developing applications in Swift on Linux.

Import this into your Swift package with the following dependency declaration

`.package(url: "https://github.com/tannerdsilva/TToolkit.git", from: "1.0.0")`

## What does TToolkit do?

### Explosions!! :D

Explosions allow for very high performance multithreaded collection enumeration. The performance benefits of multi-threaded enumeration can really be seen with high-count collections (typically with 100,000 items or more).

Exploding collections are also useful for explanding data. For example, a collection of URL's might be exploded to allow for multiple URL's to be fetched asyncronously.

Every variant of the `explode` functions has a leading argument: `lanes:Int` in which the numer of actively working threads can be defined.  Lanes can be though of as  the maximum number of threads that will be executed at any given time. When one lane is finished executing, another lane _(if available)_ will begin executing in its place.

### CSV encoding and decoding

TToolkit defines a protocol for making any structure or class codable to a CSV format.

### Data Line Slicing

Automatically detects the three common types of line breaks used in a data variable and splits accordingly.

Supports linebreaks in CR, LF, and CRLF.

The data line slicing functions also have the ability to detect and stip the byte order mark from the beginning of a data sequence. Default behavior is to strip any known BOM sequence from the beginning of a Data variable.


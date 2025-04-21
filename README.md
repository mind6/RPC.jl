# RPC

A Julia package providing Remote Procedure Call (RPC) functionality.

## Features

- Simple RPC server and client implementation
- Supports various data types through Julia's serialization
- HTTP/WebSockets communication

## Installation

```julia
using Pkg
Pkg.add(url="https://github.com/YourUsername/RPC.jl")
```

## Usage

See the examples directory for detailed usage instructions:
- `rpc_example.jl`: Basic RPC usage
- `integration_example.jl`: Integration example

## Testing

Run the tests with:

```julia
using Pkg
Pkg.test("RPC")
``` 
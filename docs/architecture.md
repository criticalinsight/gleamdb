# AaronDB Architecture

> "Simplicity is not about making things easy. It is about untangling complexity."
> — Rich Hickey

AaronDB is a BEAM-native database engine that fully de-complects storage from
computation and processing from identity. It represents a unified architecture
combining a high-performance temporal Datalog engine with an associative
Cognitive Memory inspired by human learning processes.

## Core Architectural Principles

1. **The Database is a Value**
   We treat the database not as a mutating place, but as a succession of
   immutable values. Every transaction creates a new root state (value),
   preserving the entire history. This guarantees consistency without locking
   during query execution.

2. **Sovereign Actors**
   Using Erlang/OTP, every Datalog query executes as a sovereign process. This
   enables fine-grained timeouts, complete isolation, and multi-core
   distribution without shared-state contention.

3. **Data Over Objects**
   There are no ORMs or complex object graphs. Data is represented as atomic,
   5-arity tuples (Datoms): `[Entity_ID, Attribute, Value, Transaction_ID,
   Operation_Type]`. This generic shape allows indices to be built generically.

4. **Silicon Saturation (Indices)**
   Read operations are de-complected from writes. While writes serialize via a
   Raft-based consensus or simple Transaction Log, reads are distributed across
   lock-free, concurrent ETS (Erlang Term Storage) tables.

## The Cognitive Engine (Integration)

AaronDB integrates cognitive capabilities previously isolated in the MuninnDB Go
project directly into the Gleam codebase:

### Engram Record Format (ERF)

The cognitive engine defines memory as "Engrams" (Concepts) and "Traces"
(Contexts). These semantic nodes contain Base-Level Learning scores (ACT-R Log
Decay).

### The `Cognitive` Datalog Predicate

Unlike traditional relational engines that require separate external ML matching
services (complection), AaronDB evaluates semantic relevance natively within the
logical executor.

The Datalog clause `Cognitive(concept, context, threshold, bind_var)` computes
semantic association weight dynamically and only joins rows that pass the
Hebbian association threshold.

## Storage Adapters

The engine logic is decoupled from persistence protocols:

- **In-Memory:** For ephemeral what-if analysis (`aarondb.with_facts`)
- **SQLite:** Write-Ahead Log optimized standard persistence.
- **Mnesia:** Distributed, durable persistence for the BEAM fabric.

## MCP Connectivity

AaronDB exposes an integrated Model Context Protocol (MCP) server over `stdio`
via JSON-RPC, exposing 35 intrinsic developer and agentic tools for structural
database modification and querying.

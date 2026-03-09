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

## AaronDB Edge: The Sovereign Stack

Unlike the traditional BEAM-native engine, AaronDB Edge is a
memory-first Transactional Datalog Engine optimized for Cloudflare Workers.

### 1. Memory-First Durable Objects

The Edge engine resides within a **Cloudflare Durable Object**. Every instance
represents a "Sovereign Brain" for an agent, maintaining its entire EAVT
index as an immutable Gleam-generated data structure in memory. This
eliminates database latency, allowing joins to execute in the same
millisecond as the query arrival.

### 2. Polyglot Persistence & Durability

1. **D1 (Write-Ahead Log)**: Every transaction is asynchronously persisted
   to Cloudflare D1 (SQLite). This provides the durability layer required
   to rehydrate the memory state if the Durable Object is evicted.
2. **R2 (Archive)**: Periodic snapshots of the entire memory-resident
   database are archived to R2 as JSON blobs, providing long-term
   point-in-time recovery.

### 3. Edge-Native AI Integration

The stack integrates directly with **Cloudflare Workers AI** and **Vectorize**:

- **Automatic Embeddings**: New facts trigger background embedding
  generation (`bge-small-en-v1.5`).
- **Semantic Joins**: Hybrid search combines global top-k lookups from
  Vectorize with local Datalog filtering to provide context-aware,
  temporally-constrained reasoning.

This architecture de-complects computation from the network, providing a
stateful, reasoning-capable foundation for autonomous agents.

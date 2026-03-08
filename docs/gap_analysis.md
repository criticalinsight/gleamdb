# AaronDB Gap Analysis

## Introduction

This document tracks the gap between the current state of **AaronDB** and the
ultimate vision of a fully autonomous, sovereign intelligent database system.
It outlines current capabilities, missing components, and architectural
challenges.

## 1. Datalog Expressiveness

**Current State:**

Supports core Datalog logic: pattern matching, `Bind`, graph algorithms
(`ShortestPath`, `PageRank`, etc.), aggregation, temporal filtering (`as_of`,
`since`), and unified `Cognitive` queries for semantic retrieval.

**Gaps:**

- Datalog rules are now durable across node restarts, persisted via binary serialization.
- Recursive queries using `pull_recursive` are functional but highly
  memory-intensive on deep graphs and could benefit from query-planner
  optimizations or lazy stream evaluation.

## 2. Distributed Operation & Raft

**Current State:**

Native Sharding (v1.7) partitions facts across logical shards effectively. Raft
term-based election provides basic HA capability for individual shards.

**Gaps:**

- Re-balancing of shards is completely manual. Dynamic re-sharding when nodes
  crash or scale up is not yet implemented.
- The `Distributed Sovereign` telemetry uses raw Erlang distribution (Global)
  which does not scale beyond ~60-100 nodes. Transitioning to a Hash Ring
  (e.g., Riak Core) is needed for massive scale.

## 3. Cognitive Engine (MuninnDB Integration)

**Current State:**

Ported successfully to pure Gleam. `Engram` decay functions (ACT-R) and Hebbian
learning are implemented and reachable dynamically via Datalog queries. 35 MCP
tools have been translated and JSON-RPC stubs created.

**Gaps:**

- Core MCP tools (`remember`, `recall`, `read`) are explicitly mapped; the 
  remaining ~30 tools are currently stubbed.
- Adaptive active decay (ACT-R) is now applied periodically to the engram pool 
  via background database ticks.

## 4. Security and Isolation

**Current State:**

No user authentication. Complete trust is assumed on the BEAM distribution
network.

**Gaps:**

- If exposed to external MCP agents directly over HTTP/SSE (currently stdio
  only), a Vault or capability-based security model must be implemented to
  prevent agents from corrupting the core transaction log.

## Immediate Action Items

1. Map the 35 tools in `server.gleam` to their respective database operations.
2. Implement dynamic shard rebalancing.
3. Optimize graph recursion bounds.

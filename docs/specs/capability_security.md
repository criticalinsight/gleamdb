# PRD: Capability-Based Security Gateway 🧙🏾‍♂️

**Role:** Lead Product Manager
**Persona:** Rich Hickey (Focus on un-complected design and explicit authorization as a value)

## User Story
"As an AI Agent or external client, I want to securely access AaronDB through capability-based tokens (like UCANs or Macaroons) so that I only have access to the specific resources and actions I am explicitly authorized for, without poisoning the core transaction log."

## Acceptance Criteria
- **Given** an external request containing an authorization token (capability string) and a query AST,
- **When** the `auth.gleam` gateway processes the request,
- **Then** it validates the token's cryptographic signatures or inherent capability scopes against the requested AST.
- **And** if authorized, passes the pure AST to the transactor. If unauthorized, returns an `Unauthorized(Reason)` error without interacting with the transactor or state.

## Technical Constraints
- The security model must not be built into the core transactor or storage engine. It must remain a pure-functional API Gateway layer (`auth.gleam`).
- The identity and authority must be decoupled. We will implement a lightweight, token-based verification system rather than a stateful session registry.
- Token validation must have `O(1)` or `O(length_of_token)` time complexity.

## UI/UX Notes
- For the LLM Agent, this is purely an API header or message wrapper constraint. The agent must pass a capability token alongside JSON-RPC requests.
- Failures should return verbose, developer-friendly messages indicating exactly which capability was missing (e.g., `Missing capability: Write(Shard: 3)`).

## Note
PRD Generated. Run `/implement` (or `[/proceed]`) to hand off to the Developer Agent to begin implementation according to the Rich Hickey quality standards.

🚀 Enhancement: OpenRPC Integration Layer

## Core Concept
Transition from a "Code-First" only approach to a "Contract-First" workflow. Use an OpenRPC specification file as the
source of truth for routing, documentation, and validation.

## Key Features
Spec-Driven Routing: Use load_openrpc_spec(path) to automatically populate the rpc_registry. If a method isn't in the
spec, it doesn't exist to the handler.

Discovery Endpoint: Implement system.discover to return the full JSON specification, allowing for instant compatibility
with external tools (Playgrounds, SDK generators).

Automatic GET Support: Update the Rack handler to return the OpenRPC spec when hit with a GET request, providing "
Instant Docs" for browsers.

## Implementation Strategy (The "POLS" Way)
Explicit Mapping: Use OpenRPC Specification Extensions (x-ruby-method) within the JSON to explicitly map an external
method name (e.g., user.getProfile) to an internal Ruby symbol (e.g., :find_user).

Fallback Logic: If no extension is present, apply a "Principle of Least Surprise" (POLS) translation:

camelCase ➔ snake_case
dot.notation ➔ under_score

Validation Hook: (Future) Use the schema definitions in the spec to validate incoming params before they reach the Ruby
method.
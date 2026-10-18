# Design Methodology — Sailing Channel Dashboard

<!--
  Carried verbatim between projects: this is the house design method, kept
  opinionated on purpose. Only project-specific artifact paths (docs/uml/...)
  may need adjusting per repo.
-->

## Design Process (Phase Order)

Never skip these phases — never reverse the order.

### Phase 1 — Requirements
- Capture user stories as plain language use cases
- Identify actors and system boundaries
- Produce: Use Case diagram in `docs/uml/domain/use_cases.puml`

### Phase 2 — Behavior First
- Model the 3-5 most critical system interactions as sequence diagrams
- Identify responsibilities that emerge from the interactions
- Do NOT create class diagrams yet
- Produce: Sequence diagrams in `docs/uml/sequences/`

### Phase 3 — Domain Model
- Let the class model emerge from Phase 2 responsibilities
- Model entities, relationships, and domain services
- No infrastructure or framework types in the domain model
- Produce: Class diagram in `docs/uml/domain/domain_model.puml`

### Phase 4 — Architecture
- Map domain objects to the four-layer architecture
- Define repository interfaces in `domain/repositories/`
- Define service interfaces in `domain/services/`
- Produce: Component diagram in `docs/uml/components/architecture.puml`

### Phase 5 — Iterative Build
- Build in vertical slices (one feature end-to-end per iteration)
- Each iteration: domain → application → infrastructure → presentation
- Each iteration must be independently shippable
- Review architecture rules at the end of every iteration

### Design Principle
> Understand behavior first. Let structure emerge.
> Protect the domain from everything external.

## UML Conventions

### General
- Use `!theme plain` on all diagrams
- Use `skinparam linetype ortho` on class diagrams
- Store as `.puml` files in `docs/uml/`
- Commit diagrams alongside code — they are living documents

### Class Diagrams
- Show layer as a `package` block
- Show only domain-relevant attributes and methods
- Use `*--` for composition, `o--` for aggregation, `-->` for association
- Use `..>` for dependency (e.g. generates, uses)

### Sequence Diagrams
- Label participants with both name and layer in brackets
- Use `activate` / `deactivate` to show lifetimes
- Always show the `alt` / `else` path for validation failures
- Show infrastructure participants (DB, Queue) at the far right

## Design Patterns in Use

| Pattern | Layer | Purpose |
|---|---|---|
| Repository | infrastructure/ | Abstracts all storage behind domain interfaces |
| Observer | presentation/ | UI reacts to domain state changes |
| Command | optional | Use only where undo, queue, or replay is required — not every mutation |
| Factory | application/ | Constructs complex domain objects |
| Facade | application/ | Simplifies domain interactions for the presentation layer |
| Strategy | infrastructure/ | Swappable implementations (e.g. sync, export) |
| Visitor | application/ | Separate rendering/export logic from domain objects |
| Presentation models + application mappers | both | Knotlog v2 style — `presentation/models/`, `application/mappers/` |

## Working Agreements

### At session start
1. Update Current Iteration section in AGENTS.md
2. Agent reads current AGENTS.md before any action
3. Confirm understanding of iteration goal
4. Ask questions before taking action

### Before writing code
1. Agree on the sequence diagram for the feature
2. Agree on any new domain entities required
3. Confirm which layer the new code belongs in

### Post-generation checklist
- [ ] Domain layer has zero framework dependencies
- [ ] New classes have corresponding abstract interfaces
- [ ] Repository pattern used for all storage access
- [ ] Command pattern only if undo/queue/replay is required
- [ ] Unit tests scaffolded alongside new domain classes
- [ ] PlantUML diagrams updated to reflect changes
- [ ] Comments follow `class_comment_specification.md` format

### Resolving disagreement
- Both sides explain reasoning
- Discuss tradeoffs before proceeding
- Record the decision and rationale in decisions.md

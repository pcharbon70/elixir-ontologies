# Elixir Shapes Guide

**File**: `elixir-shapes.ttl`
**Namespace**: `https://w3id.org/elixir-code/shapes#`
**Prefix**: `shapes:` (in the file, uses `:` as default)

## Overview

SHACL (Shapes Constraint Language) provides closed-world validation for the ontology. While OWL operates under the open-world assumption (unknown facts might be true), SHACL validates that data conforms to expected constraints.

This module validates:
- Required properties are present
- Values conform to expected patterns
- Cardinalities are correct
- Cross-entity consistency holds

## Why SHACL?

### OWL vs SHACL

| Aspect | OWL | SHACL |
|--------|-----|-------|
| Assumption | Open world | Closed world |
| Purpose | Inference & reasoning | Validation |
| Missing data | Could exist | Error |
| Use case | "What can we infer?" | "Is this valid?" |

Example: OWL `owl:cardinality 1` means "exactly one exists (possibly unknown)". SHACL `sh:minCount 1` means "at least one must be present in the data."

### When to Use SHACL

- Validating imported data
- Ensuring data quality before querying
- Enforcing naming conventions
- Checking referential integrity

## Shape Structure

Each shape targets a class and defines property constraints:

```turtle
:ModuleShape a sh:NodeShape ;
    sh:targetClass struct:Module ;  # What class this validates
    sh:property [                    # Property constraint
        sh:path struct:moduleName ;  # Which property
        sh:minCount 1 ;              # At least one value
        sh:maxCount 1 ;              # At most one value
        sh:datatype xsd:string ;     # Must be string
        sh:pattern "^[A-Z]..." ;     # Must match regex
        sh:message "Error message"@en
    ] .
```

## Module Shapes

### ModuleShape

```turtle
:ModuleShape a sh:NodeShape ;
    sh:targetClass struct:Module ;
    sh:property [
        sh:path struct:moduleName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[A-Z][A-Za-z0-9_]*(\\.[A-Z][A-Za-z0-9_]*)*$" ;
        sh:message "Module name must be valid Elixir module name (UpperCamelCase with optional dots)"@en
    ] .
```

Validates:
- Module has exactly one name
- Name follows Elixir conventions: `MyApp`, `MyApp.Users.Admin`

Additional constraints:
- `containsFunction` must reference `Function` instances
- `containsMacro` must reference `Macro` instances
- `implementsBehaviour` must reference `Behaviour` instances

### NestedModuleShape

```turtle
:NestedModuleShape a sh:NodeShape ;
    sh:targetClass struct:NestedModule ;
    sh:property [
        sh:path struct:parentModule ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class struct:Module ;
        sh:message "Nested module must have exactly one parent module"@en
    ] .
```

## Function Shapes

### FunctionShape

The most critical shape—validates Elixir's function identity model:

```turtle
:FunctionShape a sh:NodeShape ;
    sh:targetClass struct:Function ;
    sh:property [
        sh:path struct:functionName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-z_][a-z0-9_]*[!?]?$" ;
        sh:message "Function name must be valid Elixir identifier (snake_case, optional ! or ?)"@en
    ] ;
    sh:property [
        sh:path struct:arity ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:nonNegativeInteger ;
        sh:maxInclusive 255 ;
        sh:message "Function arity must be between 0 and 255"@en
    ] ;
    sh:property [
        sh:path struct:belongsTo ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class struct:Module ;
        sh:message "Function must belong to exactly one module"@en
    ] ;
    sh:property [
        sh:path struct:hasClause ;
        sh:minCount 1 ;
        sh:class struct:FunctionClause ;
        sh:message "Function must have at least one clause"@en
    ] .
```

Validates:
- Function name is snake_case, may end with `!` or `?`
- Arity is 0-255 (BEAM limit)
- Belongs to exactly one module
- Has at least one clause

### FunctionClauseShape

```turtle
:FunctionClauseShape a sh:NodeShape ;
    sh:targetClass struct:FunctionClause ;
    sh:property [
        sh:path struct:clauseOrder ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:positiveInteger ;
        sh:message "Function clause must have a clause order (1-indexed)"@en
    ] ;
    sh:property [
        sh:path struct:hasHead ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class struct:FunctionHead
    ] ;
    sh:property [
        sh:path struct:hasBody ;
        sh:maxCount 1 ;  # Optional for protocol definitions
        sh:class struct:FunctionBody
    ] .
```

### ParameterShape

```turtle
:ParameterShape a sh:NodeShape ;
    sh:targetClass struct:Parameter ;
    sh:property [
        sh:path struct:parameterPosition ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:nonNegativeInteger
    ] .

:DefaultParameterShape a sh:NodeShape ;
    sh:targetClass struct:DefaultParameter ;
    sh:property [
        sh:path struct:hasDefaultValue ;
        sh:minCount 1 ;
        sh:maxCount 1
    ] .
```

## Macro Shapes

```turtle
:MacroShape a sh:NodeShape ;
    sh:targetClass struct:Macro ;
    sh:property [
        sh:path struct:macroName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string
    ] ;
    sh:property [
        sh:path struct:macroArity ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:nonNegativeInteger
    ] .
```

## Protocol Shapes

### ProtocolShape

```turtle
:ProtocolShape a sh:NodeShape ;
    sh:targetClass struct:Protocol ;
    sh:property [
        sh:path struct:protocolName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string
    ] ;
    sh:property [
        sh:path struct:definesProtocolFunction ;
        sh:minCount 1 ;  # Must define at least one function
        sh:class struct:ProtocolFunction
    ] ;
    sh:property [
        sh:path struct:fallbackToAny ;
        sh:maxCount 1 ;
        sh:datatype xsd:boolean
    ] .
```

### ProtocolImplementationShape

```turtle
:ProtocolImplementationShape a sh:NodeShape ;
    sh:targetClass struct:ProtocolImplementation ;
    sh:property [
        sh:path struct:implementsProtocol ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class struct:Protocol
    ] ;
    sh:property [
        sh:path struct:forDataType ;
        sh:minCount 1 ;
        sh:maxCount 1
    ] .
```

## Behaviour Shapes

```turtle
:BehaviourShape a sh:NodeShape ;
    sh:targetClass struct:Behaviour ;
    sh:property [
        sh:path struct:definesCallback ;
        sh:minCount 1 ;  # Must define at least one callback
        sh:class struct:CallbackFunction
    ] .
```

## Type System Shapes

### TypeSpecShape

```turtle
:TypeSpecShape a sh:NodeShape ;
    sh:targetClass struct:TypeSpec ;
    sh:property [
        sh:path struct:typeName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-z_][a-z0-9_]*$"  # snake_case
    ] ;
    sh:property [
        sh:path struct:typeArity ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:nonNegativeInteger
    ] .
```

### FunctionSpecShape

```turtle
:FunctionSpecShape a sh:NodeShape ;
    sh:targetClass struct:FunctionSpec ;
    sh:property [
        sh:path struct:hasReturnType ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class struct:TypeExpression
    ] .
```

## Struct Shapes

```turtle
:StructShape a sh:NodeShape ;
    sh:targetClass struct:Struct ;
    sh:property [
        sh:path struct:hasField ;
        sh:class struct:StructField
    ] .

:StructFieldShape a sh:NodeShape ;
    sh:targetClass struct:StructField ;
    sh:property [
        sh:path struct:fieldName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-z_][a-z0-9_]*$"  # Atom, snake_case
    ] .
```

## Source Location Shape

```turtle
:SourceLocationShape a sh:NodeShape ;
    sh:targetClass core:SourceLocation ;
    sh:property [
        sh:path core:startLine ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:positiveInteger
    ] ;
    sh:property [
        sh:path core:endLine ;
        sh:maxCount 1 ;
        sh:datatype xsd:positiveInteger
    ] .
```

### SPARQL Constraint: Line Order

```turtle
sh:sparql [
    sh:message "End line must be >= start line" ;
    sh:select """
        SELECT $this ?startLine ?endLine
        WHERE {
            $this core:startLine ?startLine .
            $this core:endLine ?endLine .
            FILTER (?endLine < ?startLine)
        }
    """
] .
```

SPARQL-based constraints enable complex validation beyond simple property checks.

## OTP Shapes

### SupervisorShape

```turtle
:SupervisorShape a sh:NodeShape ;
    sh:targetClass otp:Supervisor ;
    sh:property [
        sh:path otp:hasStrategy ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:in ( otp:OneForOne otp:OneForAll otp:RestForOne )
    ] ;
    sh:property [
        sh:path otp:maxRestarts ;
        sh:maxCount 1 ;
        sh:datatype xsd:nonNegativeInteger
    ] ;
    sh:property [
        sh:path otp:maxSeconds ;
        sh:maxCount 1 ;
        sh:datatype xsd:positiveInteger
    ] .
```

### DynamicSupervisorShape

Enforces the constraint that DynamicSupervisor only uses `:one_for_one`:

```turtle
:DynamicSupervisorShape a sh:NodeShape ;
    sh:targetClass otp:DynamicSupervisor ;
    sh:property [
        sh:path otp:hasStrategy ;
        sh:hasValue otp:OneForOne  # Must be exactly this value
    ] .
```

### ChildSpecShape

```turtle
:ChildSpecShape a sh:NodeShape ;
    sh:targetClass otp:ChildSpec ;
    sh:property [
        sh:path otp:childId ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string
    ] ;
    sh:property [
        sh:path otp:hasRestartStrategy ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:in ( otp:Permanent otp:Temporary otp:Transient )
    ] ;
    sh:property [
        sh:path otp:hasChildType ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:in ( otp:WorkerType otp:SupervisorType )
    ] ;
    sh:property [
        sh:path otp:startModule ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string
    ] .
```

### GenServerImplementationShape

Uses qualified value shapes for callback validation:

```turtle
:GenServerImplementationShape a sh:NodeShape ;
    sh:targetClass otp:GenServerImplementation ;
    sh:property [
        sh:path otp:hasGenServerCallback ;
        sh:qualifiedValueShape [
            sh:class otp:InitCallback
        ] ;
        sh:qualifiedMinCount 1 ;
        sh:message "GenServer implementation should have init/1 callback"@en
    ] .
```

### ETSTableShape

```turtle
:ETSTableShape a sh:NodeShape ;
    sh:targetClass otp:ETSTable ;
    sh:property [
        sh:path otp:ownedByProcess ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:class otp:Process
    ] ;
    sh:property [
        sh:path otp:hasTableType ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:in ( otp:SetTable otp:OrderedSetTable otp:BagTable otp:DuplicateBagTable )
    ] ;
    sh:property [
        sh:path otp:hasAccessType ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:in ( otp:PublicTable otp:ProtectedTable otp:PrivateTable )
    ] .
```

## Evolution Shapes

### CommitShape

```turtle
:CommitShape a sh:NodeShape ;
    sh:targetClass evo:Commit ;
    sh:property [
        sh:path evo:commitHash ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-f0-9]{40}$"  # 40-character hex
    ] ;
    sh:property [
        sh:path evo:commitMessage ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:minLength 1  # Non-empty
    ] ;
    sh:property [
        sh:path evo:authoredAt ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:dateTime
    ] ;
    sh:property [
        sh:path evo:wasAssociatedWith ;
        sh:minCount 1 ;
        sh:class evo:DevelopmentAgent
    ] ;
    sh:property [
        sh:path evo:containsChange ;
        sh:minCount 1 ;
        sh:class evo:ChangeSet
    ] .
```

### DeveloperShape

```turtle
:DeveloperShape a sh:NodeShape ;
    sh:targetClass evo:Developer ;
    sh:property [
        sh:path evo:developerName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string
    ] ;
    sh:property [
        sh:path evo:developerEmail ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}$"
    ] .
```

### BranchShape

```turtle
:BranchShape a sh:NodeShape ;
    sh:targetClass evo:Branch ;
    sh:property [
        sh:path evo:branchName ;
        sh:minCount 1 ;
        sh:maxCount 1 ;
        sh:datatype xsd:string ;
        sh:pattern "^[a-zA-Z0-9/_-]+$"  # Valid branch characters
    ] .
```

## Cross-Cutting Constraints

### Arity-Parameter Match

Validates that function arity matches parameter count:

```turtle
:FunctionArityMatchShape a sh:NodeShape ;
    sh:targetClass struct:Function ;
    sh:sparql [
        sh:message "Function arity should match parameter count in first clause" ;
        sh:select """
            SELECT $this ?arity ?paramCount
            WHERE {
                $this struct:arity ?arity .
                $this struct:hasClause ?clause .
                ?clause struct:clauseOrder 1 .
                ?clause struct:hasHead ?head .
                {
                    SELECT ?head (COUNT(?param) AS ?paramCount)
                    WHERE {
                        ?head struct:hasParameter ?param .
                    }
                    GROUP BY ?head
                }
                FILTER (?arity != ?paramCount)
            }
        """
    ] .
```

### Protocol Compliance

Validates that protocol implementations implement all required functions:

```turtle
:ProtocolComplianceShape a sh:NodeShape ;
    sh:targetClass struct:ProtocolImplementation ;
    sh:sparql [
        sh:message "Protocol implementation should implement all protocol functions" ;
        sh:select """
            SELECT $this ?protocol ?missingFunc
            WHERE {
                $this struct:implementsProtocol ?protocol .
                ?protocol struct:definesProtocolFunction ?missingFunc .
                FILTER NOT EXISTS {
                    $this struct:containsFunction ?implFunc .
                    ?implFunc struct:functionName ?name .
                    ?missingFunc struct:functionName ?name .
                }
            }
        """
    ] .
```

## Using SHACL Validators

### Apache Jena SHACL

```bash
# Validate data against shapes
shacl validate --shapes elixir-shapes.ttl --data my-code-graph.ttl
```

### Python (pyshacl)

```python
from pyshacl import validate

r = validate(
    data_graph='my-code-graph.ttl',
    shacl_graph='elixir-shapes.ttl',
    inference='rdfs'
)
conforms, results_graph, results_text = r
print(results_text)
```

### TopBraid SHACL

```java
Model dataModel = ...;
Model shapesModel = ...;
Resource report = ValidationUtil.validateModel(dataModel, shapesModel, true);
```

## Validation Report

SHACL produces validation reports:

```turtle
ex:report a sh:ValidationReport ;
    sh:conforms false ;
    sh:result [
        a sh:ValidationResult ;
        sh:focusNode ex:myFunction ;
        sh:resultPath struct:arity ;
        sh:resultMessage "Function arity must be between 0 and 255" ;
        sh:resultSeverity sh:Violation ;
        sh:sourceShape :FunctionShape ;
        sh:value 300
    ] .
```

## Severity Levels

SHACL supports three severity levels:

```turtle
sh:resultSeverity sh:Violation .  # Error - must fix
sh:resultSeverity sh:Warning .    # Should fix
sh:resultSeverity sh:Info .       # Informational
```

You can specify severity per constraint:

```turtle
sh:property [
    sh:path struct:docstring ;
    sh:minCount 1 ;
    sh:severity sh:Warning ;  # Missing docs is warning, not error
    sh:message "Function should have documentation"@en
] .
```

## Design Rationale

1. **Complement OWL**: OWL for inference, SHACL for validation
2. **Elixir conventions**: Regex patterns enforce naming rules
3. **Referential integrity**: Class constraints ensure valid references
4. **SPARQL for complex rules**: Cross-entity validation via SPARQL
5. **Actionable messages**: Clear error messages for each constraint

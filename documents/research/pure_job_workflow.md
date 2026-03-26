# File: documents/research/pure_job_workflow.md
# Pure Job Workflow Architecture

**Status**: Reference only
**Supersedes**: N/A
**Referenced by**: [README.md](README.md), [../README.md](../README.md#studiomcp-documentation-index)

> **Purpose**: Capture exploratory workflow-architecture ideas that may inform later execution-system work without defining the current implemented architecture. Treat this as source material, not a repository contract.
> **📖 Authoritative Reference**: [Documentation Standards](../documentation_standards.md#4-required-header-metadata)

## Overview

This document describes a **pure functional workflow architecture**
centered around a Haskell `Job` type.

The system is designed for **distributed workflows**, using: - Pure
Haskell types for orchestration logic - Pulsar for messaging -
Kubernetes (EKS) for execution - S3 for storage

We use **audio source separation** as the primary example.

------------------------------------------------------------------------

## Core Philosophy

> Separate **what** from **how**

-   `Job` = pure description (DAG)
-   Orchestrator = interpreter
-   Workers = stateless executors

------------------------------------------------------------------------

## High-Level Architecture

``` mermaid
flowchart TD
    A[Client] --> B[Pulsar Job Topic]
    B --> C[Haskell Orchestrator]
    C --> D[EKS / Kubernetes]
    C --> E[AWS APIs]
    C --> F[Pulsar Task Topics]
    D --> G[Worker Pods]
    G --> F
    G --> H[S3 Artifacts]
    C --> I[Summary Output]
```

------------------------------------------------------------------------

## Pure Job Type

``` haskell
data Job = Job
  { jobId        :: JobId
  , workflow     :: Workflow JobNode
  , input        :: InputSpec
  , instructions :: SeparationInstructions
  , outputs      :: OutputSpec
  }
```

------------------------------------------------------------------------

## Workflow DAG

``` mermaid
flowchart LR
    A[Fetch Audio] --> B[Separate Audio]
    B --> C[Persist Results]
    C --> D[Summary]
```

``` haskell
data Workflow n = Workflow
  { nodes :: Map NodeId n
  , edges :: Set Edge
  }
```

------------------------------------------------------------------------

## Node Types

``` haskell
data JobNode
  = FetchInput FetchSpec
  | SeparateAudio SeparationSpec
  | PersistArtifacts PersistSpec
  | PublishSummary SummarySpec
  | ProvisionCompute ResourceIntent
  | DeployService DeploymentIntent
```

------------------------------------------------------------------------

## Runtime Model

``` mermaid
stateDiagram-v2
    [*] --> Pending
    Pending --> Running
    Running --> Success
    Running --> Failed
```

------------------------------------------------------------------------

## Pulsar Messaging

``` mermaid
sequenceDiagram
    participant O as Orchestrator
    participant P as Pulsar
    participant W as Worker

    O->>P: Task Message
    P->>W: Deliver Task
    W->>P: Result Message
    P->>O: Consume Result
```

------------------------------------------------------------------------

## Audio Source Separation Example

### Workflow

``` mermaid
flowchart TD
    A[S3 Input] --> B[Demucs Separation]
    B --> C[Postprocess]
    C --> D[S3 Output]
```

### Open-weight Models

| Model | Use Case |
|-------|----------|
| Demucs | Music separation |
| Open-Unmix | Baseline music |
| Asteroid | Research pipelines |
| SpeechBrain | Speech separation |
| pyannote.audio | Diarization |

------------------------------------------------------------------------

## Separation Instructions

``` haskell
data SeparationInstructions = SeparationInstructions
  { model        :: ModelFamily
  , stems        :: [Stem]
  , sampleRate   :: Int
  }
```

------------------------------------------------------------------------

## Resource Intent

``` haskell
data ResourceIntent = ResourceIntent
  { cpu :: Int
  , memory :: Int
  , gpu :: Maybe Int
  }
```

------------------------------------------------------------------------

## Summary Type

``` haskell
data Summary = Summary
  { status    :: Status
  , artifacts :: [ArtifactRef]
  , errors    :: [Text]
  }
```

------------------------------------------------------------------------

## Deployment Flow

``` mermaid
flowchart TD
    A[Job Received] --> B[Plan DAG]
    B --> C[Provision Resources]
    C --> D[Deploy Workers]
    D --> E[Execute Tasks]
    E --> F[Collect Results]
    F --> G[Cleanup]
```

------------------------------------------------------------------------

## Generalization

This architecture works for:

-   ML pipelines
-   ETL workflows
-   Video processing
-   Data science pipelines

------------------------------------------------------------------------

## Key Benefits

-   Pure functional core
-   Deterministic planning
-   Strong typing
-   Cloud-native scalability

------------------------------------------------------------------------

# Advanced Topics: Pure Parallelism and Distributed Execution

The following sections detail how to leverage Haskell's type system and
category-theoretic foundations to express parallelizable compute graphs,
lift pure job representations to distributed execution, and coordinate
resource provisioning.

------------------------------------------------------------------------

## Section 1: Category Theory Foundations

This section grounds the parallel execution model in category theory,
then shows practical Haskell patterns for expressing parallelism at the
type level.

### 1.1 The Functor → Applicative → Monad Hierarchy

These three typeclasses form a hierarchy of increasing power. Each level
adds capabilities but also adds constraints that affect what optimizations
are possible.

``` mermaid
flowchart TD
    F["Functor<br/>Transform contents"]
    A["Applicative<br/>Combine independent effects"]
    M["Monad<br/>Chain dependent effects"]

    F --> |"adds pure + (<*>)"| A
    A --> |"adds (>>=)"| M

    F -.-> |"fmap"| TRANSFORM["Transform: (a → b) → f a → f b"]
    A -.-> |"(<*>)"| COMBINE["Combine: f (a → b) → f a → f b"]
    M -.-> |"(>>=)"| CHAIN["Chain: m a → (a → m b) → m b"]

    style F fill:#e3f2fd
    style A fill:#fff3e0
    style M fill:#fce4ec
```

#### 1.1.1 Functor: Structure-Preserving Transformation

A **Functor** lets you transform the contents of a structure without
changing the structure itself.

``` haskell
class Functor f where
  fmap :: (a -> b) -> f a -> f b
```

**Laws** (these must hold for any valid Functor):

``` haskell
-- Identity: mapping id changes nothing
fmap id = id

-- Composition: mapping f then g = mapping (g . f)
fmap (g . f) = fmap g . fmap f
```

**Intuition**: A Functor is a "container" or "context" that you can
peek inside and transform, but you can't change the shape of the container.

``` haskell
-- Examples
fmap (+1) [1, 2, 3]           -- [2, 3, 4]     (List functor)
fmap (+1) (Just 5)            -- Just 6        (Maybe functor)
fmap (+1) (Right 5)           -- Right 6       (Either functor)
fmap length getLine           -- IO Int        (IO functor)
```

``` mermaid
flowchart LR
    subgraph Before["f a"]
        A1["a"]
    end
    subgraph After["f b"]
        B1["b"]
    end

    Before --> |"fmap (a → b)"| After

    style Before fill:#e3f2fd
    style After fill:#c8e6c9
```

**Limitation**: With just Functor, you can only transform one value at a time.
You cannot combine multiple `f a` values.

#### 1.1.2 Applicative: Independent Combination

An **Applicative** functor lets you combine multiple independent effectful
computations. This is the key abstraction for parallelism.

``` haskell
class Functor f => Applicative f where
  pure  :: a -> f a                   -- Lift a pure value into the context
  (<*>) :: f (a -> b) -> f a -> f b   -- Apply a function in context to a value in context
```

**Laws**:

``` haskell
-- Identity
pure id <*> v = v

-- Composition
pure (.) <*> u <*> v <*> w = u <*> (v <*> w)

-- Homomorphism
pure f <*> pure x = pure (f x)

-- Interchange
u <*> pure y = pure ($ y) <*> u
```

**Intuition**: Applicative lets you apply a function to multiple arguments,
each wrapped in the same context. Crucially, **both arguments are fully
determined before `(<*>)` is called**.

``` haskell
-- Combining two independent computations
(,) <$> readFile "a.txt" <*> readFile "b.txt"
-- Both files can be read in parallel! Neither depends on the other.

-- Equivalent using liftA2
liftA2 (,) (readFile "a.txt") (readFile "b.txt")
```

``` mermaid
flowchart TD
    subgraph Inputs["Independent Inputs"]
        FA["f a"]
        FB["f b"]
        FC["f c"]
    end

    COMBINE["(<*>)<br/>liftA3 combine"]

    FA --> COMBINE
    FB --> COMBINE
    FC --> COMBINE

    COMBINE --> RESULT["f (a, b, c)"]

    style FA fill:#e3f2fd
    style FB fill:#e3f2fd
    style FC fill:#e3f2fd
    style RESULT fill:#c8e6c9
```

**Why Applicative Enables Parallelism**: Look at the type of `(<*>)`:

``` haskell
(<*>) :: f (a -> b) -> f a -> f b
```

Both `f (a -> b)` and `f a` are **already constructed** before `(<*>)` runs.
The second argument doesn't depend on the result of the first. An execution
engine can run them simultaneously.

#### 1.1.3 Monad: Dependent Sequencing

A **Monad** lets you chain computations where later computations depend
on the results of earlier ones. This is strictly more powerful than
Applicative, but that power comes at a cost.

``` haskell
class Applicative m => Monad m where
  (>>=) :: m a -> (a -> m b) -> m b   -- "bind"
  -- Also: return = pure, (>>) for sequencing without using result
```

**Laws**:

``` haskell
-- Left identity
return a >>= f = f a

-- Right identity
m >>= return = m

-- Associativity
(m >>= f) >>= g = m >>= (\x -> f x >>= g)
```

**Intuition**: The second argument to `(>>=)` is a **function** `(a -> m b)`.
You need the `a` value from the first computation before you can even
**construct** the second computation.

``` haskell
-- This CANNOT be parallelized:
do
  x <- computation1           -- Get x
  y <- computation2 x         -- computation2 depends on x!
  pure (x + y)

-- The second computation literally doesn't exist until x is known
```

``` mermaid
flowchart TD
    MA["m a"] --> |"run, get a"| A["a"]
    A --> |"a → m b"| MB["m b"]
    MB --> |"run, get b"| B["b"]

    style MA fill:#fce4ec
    style A fill:#fff3e0
    style MB fill:#fce4ec
    style B fill:#c8e6c9
```

**Why Monad Prevents Parallelism**: Look at the type of `(>>=)`:

``` haskell
(>>=) :: m a -> (a -> m b) -> m b
```

The second argument is `(a -> m b)`, not `m b`. You need the runtime value
`a` to construct the second computation. The execution engine **cannot know**
what the second computation will be until the first completes.

#### 1.1.4 The Critical Distinction

``` haskell
-- APPLICATIVE: Both computations are known statically
(<*>) :: f (a -> b) -> f a -> f b
--       ^^^^^^^^^^    ^^^^
--       Known         Known
--       Can run in parallel!

-- MONAD: Second computation depends on first result
(>>=) :: m a -> (a -> m b) -> m b
--       ^^^^   ^^^^^^^^^^
--       Known  FUNCTION - needs 'a' to produce 'm b'
--       Must run sequentially!
```

``` mermaid
flowchart LR
    subgraph Applicative["Applicative: Static Structure"]
        A1["Action A"]
        A2["Action B"]
        A3["Action C"]
        A1 --> R1["Result"]
        A2 --> R1
        A3 --> R1
    end

    subgraph Monad["Monad: Dynamic Structure"]
        M1["Action A"] --> M2["??? <br/> (depends on A)"]
        M2 --> M3["??? <br/> (depends on B)"]
    end

    style A1 fill:#c8e6c9
    style A2 fill:#c8e6c9
    style A3 fill:#c8e6c9
    style M2 fill:#ffcdd2
    style M3 fill:#ffcdd2
```

#### 1.1.5 The Fish Operator and Kleisli Composition

The **fish operator** `(>=>)` provides another way to understand monads that
many find more intuitive than `(>>=)`. It's the composition operator for
**Kleisli arrows**.

##### What is a Kleisli Arrow?

A **Kleisli arrow** is a function of type `a -> m b` — a function that takes
a pure value and produces an effectful result. These are the building blocks
of monadic computation.

``` haskell
-- Regular function composition
(.)   :: (b -> c) -> (a -> b) -> (a -> c)

-- Kleisli composition (the "fish" operator)
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)

-- Also: "backwards fish"
(<=<) :: Monad m => (b -> m c) -> (a -> m b) -> (a -> m c)
```

**Reading the fish**: `f >=> g` means "first do `f`, then take its result
and feed it to `g`". It's like `(.)` but for functions that return monadic values.

``` haskell
-- Implementation
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
(f >=> g) a = f a >>= g
-- Or equivalently:
(f >=> g) a = do
  b <- f a
  g b
```

##### Why "Fish"?

The name comes from the ASCII art: `>=>` looks like a fish swimming to the right.
The backwards version `<=<` is a fish swimming left.

```
  >=>     <=<
  ^^^     ^^^
 fish!   fish!
```

##### Fish vs Bind: Two Views of the Same Thing

`(>>=)` and `(>=>)` are interdefinable — you can implement either from the other:

``` haskell
-- Fish in terms of bind (the natural definition)
(>=>) :: Monad m => (a -> m b) -> (b -> m c) -> (a -> m c)
(f >=> g) a = f a >>= g

-- Bind in terms of fish (conceptual derivation)
-- We need to turn `m a` into `() -> m a` to use with (>=>):
(>>=) :: Monad m => m a -> (a -> m b) -> m b
ma >>= f = (const ma >=> f) ()
-- Expanding: (const ma >=> f) () = const ma () >>= f = ma >>= f ✓
```

**The difference in perspective**:
- `(>>=)` focuses on "I have a value in a context, transform it"
- `(>=>)` focuses on "I have two transformations, compose them"

``` mermaid
flowchart LR
    subgraph Bind["(>>=) perspective: Value-focused"]
        MA["m a"] --> |">>= f"| MB["m b"]
        MB --> |">>= g"| MC["m c"]
    end

    subgraph Fish["(>=>) perspective: Arrow-focused"]
        F["a → m b"]
        G["b → m c"]
        FG["a → m c"]
        F --> |">=>"| FG
        G --> |">=>"| FG
    end
```

##### The Monad Laws (Fish Version)

The monad laws look much cleaner when expressed with `(>=>)`:

``` haskell
-- Using bind (>>=):
return a >>= f      =  f a                    -- Left identity
m >>= return        =  m                      -- Right identity
(m >>= f) >>= g     =  m >>= (\x -> f x >>= g) -- Associativity

-- Using fish (>=>):
return >=> f        =  f                      -- Left identity
f >=> return        =  f                      -- Right identity
(f >=> g) >=> h     =  f >=> (g >=> h)        -- Associativity
```

The fish version makes it obvious that **monads form a category** (the Kleisli
category) where:
- Objects are types
- Morphisms are Kleisli arrows `a -> m b`
- Identity is `return` (or `pure`)
- Composition is `(>=>)`

``` mermaid
flowchart LR
    subgraph Kleisli["Kleisli Category"]
        A["Type A"]
        B["Type B"]
        C["Type C"]

        A --> |"f :: a → m b"| B
        B --> |"g :: b → m c"| C
        A --> |"f >=> g :: a → m c"| C
    end
```

##### Practical Example: Pipeline Composition

The fish operator shines when composing processing pipelines:

``` haskell
-- Individual steps (Kleisli arrows)
fetchUser    :: UserId -> IO User
fetchOrders  :: User -> IO [Order]
summarize    :: [Order] -> IO Summary

-- Without fish: nested binds
processUser :: UserId -> IO Summary
processUser userId = do
  user <- fetchUser userId
  orders <- fetchOrders user
  summarize orders

-- With fish: clean composition
processUser :: UserId -> IO Summary
processUser = fetchUser >=> fetchOrders >=> summarize
```

The fish version reads like a pipeline: fetch user, then fetch orders, then
summarize. No intermediate variable names needed.

##### Fish in Workflow Systems

For our workflow system, Kleisli composition helps express node pipelines:

``` haskell
-- Each workflow node is a Kleisli arrow
type WorkflowStep a b = a -> Workflow b

fetchAudio    :: InputSpec -> Workflow AudioData
separateStems :: AudioData -> Workflow StemData
persistStems  :: StemData -> Workflow ArtifactRef

-- Compose the pipeline
audioWorkflow :: InputSpec -> Workflow ArtifactRef
audioWorkflow = fetchAudio >=> separateStems >=> persistStems
```

``` mermaid
flowchart LR
    INPUT["InputSpec"]
    FETCH["fetchAudio"]
    AUDIO["AudioData"]
    SEP["separateStems"]
    STEMS["StemData"]
    PERSIST["persistStems"]
    OUTPUT["ArtifactRef"]

    INPUT --> FETCH
    FETCH --> AUDIO
    AUDIO --> SEP
    SEP --> STEMS
    STEMS --> PERSIST
    PERSIST --> OUTPUT

    subgraph Pipeline["audioWorkflow = fetchAudio >=> separateStems >=> persistStems"]
        FETCH
        SEP
        PERSIST
    end
```

##### Fish and Parallelism

Important: the fish operator `(>=>)` is **inherently sequential**, just like
`(>>=)`. The second function needs the output of the first.

``` haskell
(>=>) :: (a -> m b) -> (b -> m c) -> (a -> m c)
--                      ^
--                      |
--                 needs this 'b' from the first computation
```

This is why we need Applicative for parallelism — there's no "parallel fish"
for Monad. But there *could* be for Applicative or Arrow:

``` haskell
-- Hypothetical "parallel fish" for independent computations
(***) :: Arrow arr => arr a b -> arr c d -> arr (a, c) (b, d)
-- Both arrows run on their respective inputs
```

##### The Kleisli Newtype

Haskell has a newtype that makes Kleisli arrows first-class:

``` haskell
newtype Kleisli m a b = Kleisli { runKleisli :: a -> m b }

instance Monad m => Category (Kleisli m) where
  id = Kleisli return
  (Kleisli g) . (Kleisli f) = Kleisli (f >=> g)
  -- Why f >=> g, not g >=> f?
  -- Category (.) has type: (b -> c) -> (a -> b) -> (a -> c)
  -- So (g . f) x = g (f x) — "apply f first, then g"
  -- This matches (f >=> g) which is also "first f, then g"

instance Monad m => Arrow (Kleisli m) where
  arr f = Kleisli (return . f)
  first (Kleisli f) = Kleisli (\(a, c) -> do b <- f a; return (b, c))
```

This lets you use Kleisli arrows with the `Arrow` machinery, including
arrow notation and combinators like `(***)` and `(&&&)`.

##### Summary: Why Fish Matters

| Aspect | `(>>=)` | `(>=>)` |
|--------|---------|---------|
| Type | `m a -> (a -> m b) -> m b` | `(a -> m b) -> (b -> m c) -> (a -> m c)` |
| Focus | Values in context | Function composition |
| Use | Working with effectful values | Building pipelines |
| Laws | Harder to remember | Clean category laws |
| Intuition | "Unwrap, transform, rewrap" | "Compose transformations" |

------------------------------------------------------------------------

### 1.2 What Makes a Free Structure "Free"?

The term "free" in mathematics has a precise meaning: a **free structure**
is the most general structure that satisfies certain laws, with no additional
equations or constraints.

#### 1.2.1 The Universal Property

A **Free Monad** over a functor `f` is:
- A monad
- That embeds `f` operations
- With **no additional equations** beyond the monad laws

This means: any way of interpreting `f` into a monad `m` can be extended
to interpret the entire Free Monad.

``` mermaid
flowchart TD
    subgraph Free["Free f"]
        F["f"]
        FM["Free f (Monad)"]
    end

    subgraph Target["Any Monad m"]
        M["m"]
    end

    F --> |"embed (liftF)"| FM
    F --> |"interpret (f ~> m)"| M
    FM --> |"unique extension (foldFree)"| M

    style FM fill:#e3f2fd
    style M fill:#c8e6c9
```

``` haskell
-- The universal property in code:
-- Given any natural transformation f ~> m (where m is a Monad),
-- we get a unique monad morphism Free f ~> m

foldFree :: Monad m => (forall x. f x -> m x) -> Free f a -> m a
```

#### 1.2.2 Free Monad: Syntax Trees for Sequential DSLs

The Free Monad is a way to build an **abstract syntax tree** that can later
be interpreted. It's "free" because it represents the structure of monadic
computation with no commitment to what the operations actually do.

``` haskell
data Free f a
  = Pure a                    -- Return a value (no more operations)
  | Free (f (Free f a))       -- One operation, then continue
```

**Building the tree**:

``` haskell
-- Lift a single operation into Free
liftF :: Functor f => f a -> Free f a
liftF fa = Free (fmap Pure fa)

-- Example: A simple DSL for console I/O
data ConsoleF a
  = PrintLine String a        -- Print, then continue with 'a'
  | ReadLine (String -> a)    -- Read, continue with function of result

type Console = Free ConsoleF

printLine :: String -> Console ()
printLine s = liftF (PrintLine s ())

readLine :: Console String
readLine = liftF (ReadLine id)

-- Build a program (this is just data, no I/O happens!)
program :: Console String
program = do
  printLine "What's your name?"
  name <- readLine                  -- This creates a *function* in the tree
  printLine ("Hello, " ++ name)
  pure name
```

**The structure of this program**:

``` mermaid
flowchart TD
    P1["PrintLine 'What is your name?'"]
    R1["ReadLine"]
    P2["PrintLine 'Hello, ...'"]
    PURE["Pure name"]

    P1 --> R1
    R1 --> |"λname →"| P2
    P2 --> PURE

    style R1 fill:#ffcdd2
```

**Interpreting the tree**:

``` haskell
-- Interpret into IO
runConsoleIO :: Console a -> IO a
runConsoleIO (Pure a) = pure a
runConsoleIO (Free (PrintLine s next)) = do
  putStrLn s
  runConsoleIO next
runConsoleIO (Free (ReadLine cont)) = do
  input <- getLine
  runConsoleIO (cont input)   -- Apply the continuation!

-- Interpret into a test mock
runConsolePure :: [String] -> Console a -> (a, [String])
runConsolePure inputs (Pure a) = (a, [])
runConsolePure inputs (Free (PrintLine s next)) =
  let (result, outputs) = runConsolePure inputs next
  in (result, s : outputs)
runConsolePure (i:is) (Free (ReadLine cont)) =
  runConsolePure is (cont i)
```

**Why Free Monad loses parallelism**: Notice that `ReadLine` contains a
**function** `(String -> a)`. The next step of the computation is determined
by runtime input. The interpreter cannot see past a `ReadLine` until it
actually reads.

#### 1.2.3 Free Applicative: Syntax Trees That Preserve Independence

The **Free Applicative** is the free structure over Applicative, not Monad.
It preserves the static structure of applicative composition.

``` haskell
data Ap f a where
  Pure :: a -> Ap f a
  Ap   :: f a -> Ap f (a -> b) -> Ap f b
```

**Key difference**: In `Ap`, both the operation (`f a`) and the continuation
(`Ap f (a -> b)`) are **values**, not functions. The entire structure is
known statically.

``` haskell
-- Smart constructor
liftAp :: f a -> Ap f a
liftAp fa = Ap fa (Pure id)

-- Example: Parallel fetches using a GADT
--
-- In a GADT, each constructor specifies its own return type. Here, the
-- Fetch constructor always returns FetchF ByteString, regardless of what
-- 'a' might be in the general type. This is different from regular ADTs
-- where all constructors share the same type parameter.
data FetchF a where
  Fetch :: URL -> FetchF ByteString  -- Result type is fixed to ByteString

type Fetcher = Ap FetchF

fetch :: URL -> Fetcher ByteString
fetch url = liftAp (Fetch url)

-- Build a parallel fetch program
fetchBoth :: Fetcher (ByteString, ByteString)
fetchBoth = (,) <$> fetch urlA <*> fetch urlB
-- Structure is: Ap (Fetch urlA) (Ap (Fetch urlB) (Pure (,)))
```

**The structure of this program**:

``` mermaid
flowchart TD
    subgraph Static["Entire structure visible statically"]
        F1["Fetch urlA"]
        F2["Fetch urlB"]
        COMBINE["Pure (,)"]
    end

    F1 --> COMBINE
    F2 --> COMBINE
    COMBINE --> RESULT["(ByteString, ByteString)"]

    style F1 fill:#c8e6c9
    style F2 fill:#c8e6c9
```

**Interpreting with parallelism**:

``` haskell
-- Run all fetches in parallel!
runFetcherParallel :: Fetcher a -> IO a
runFetcherParallel (Pure a) = pure a
runFetcherParallel (Ap (Fetch url) rest) = do
  -- Collect ALL fetches first (traverse the structure)
  let urls = collectUrls (Ap (Fetch url) rest)
  -- Fetch all in parallel
  results <- mapConcurrently httpGet urls
  -- Apply results to the structure
  applyResults results (Ap (Fetch url) rest)

-- Or use the standard runAp with Concurrently applicative
runFetcherParallel' :: Fetcher a -> IO a
runFetcherParallel' = runAp (Concurrently . httpGet)
```

#### 1.2.4 Free Monad vs Free Applicative: The Key Insight

``` mermaid
flowchart TD
    subgraph FreeMonad["Free Monad"]
        FM1["Operation 1"]
        FM2["λresult → Operation 2"]
        FM3["λresult → Operation 3"]
        FM1 --> FM2
        FM2 --> FM3
    end

    subgraph FreeApp["Free Applicative"]
        FA1["Operation 1"]
        FA2["Operation 2"]
        FA3["Operation 3"]
        FAC["Combine"]
        FA1 --> FAC
        FA2 --> FAC
        FA3 --> FAC
    end

    FreeMonad --> |"Sequential only"| SEQ["One path through the tree"]
    FreeApp --> |"Parallel possible"| PAR["All operations visible"]

    style FM2 fill:#ffcdd2
    style FM3 fill:#ffcdd2
    style FA1 fill:#c8e6c9
    style FA2 fill:#c8e6c9
    style FA3 fill:#c8e6c9
```

| Aspect | Free Monad | Free Applicative |
|--------|-----------|------------------|
| Structure | Sequential chain with functions | Static tree of operations |
| Dependencies | Runtime-determined | Statically known |
| Parallelism | Not possible (need each result) | Fully possible |
| Power | Can express conditionals, loops | Only static combinations |
| Use case | Interactive DSLs, parsers | Batch operations, validation |

#### 1.2.5 Why "Free" Matters for Workflows

For workflow systems, "free" gives us:

1. **Separation of concerns**: Define workflow structure without committing
   to execution strategy

2. **Multiple interpreters**: Same workflow → different backends
   - Local sequential (debugging)
   - Local parallel (single machine)
   - Distributed (Kubernetes cluster)

3. **Static analysis**: Before running, we can:
   - Count operations
   - Estimate resources
   - Detect parallelism opportunities
   - Validate structure

``` haskell
-- Analyze a Free Applicative workflow
countOperations :: Ap f a -> Int
countOperations (Pure _) = 0
countOperations (Ap _ rest) = 1 + countOperations rest

-- Find all parallel groups
parallelGroups :: Ap f a -> [[SomeOp f]]
parallelGroups = ... -- Traverse and group independent operations
```

#### 1.2.6 Compile-Time vs Runtime: When Does Optimization Happen?

A critical distinction that's often unclear: **when** do these abstractions
enable optimization? Some happen at compile time (before your program runs),
others at runtime (while your program executes). Understanding this helps
you choose the right abstraction.

##### Compile-Time Optimizations (Static)

These optimizations are performed by GHC during compilation. The resulting
binary already has the optimization "baked in."

**1. Type-Level Guarantees (DataKinds, TypeFamilies)**

``` haskell
{-# LANGUAGE DataKinds, GADTs, TypeFamilies #-}

-- Dependency tracked at type level
data Node (deps :: [Symbol]) result where
  MkNode :: NodeSpec -> Node deps result

-- Compiler rejects invalid DAGs!
-- This is a compile-time guarantee, not runtime
invalidDAG :: Node '["B"] Int -> Node '["A"] Int -> Node '["A", "B"] Int
invalidDAG = ...  -- Won't compile if dependencies are wrong
```

**2. ApplicativeDo Desugaring**

GHC rewrites `do`-notation at compile time:

``` haskell
{-# LANGUAGE ApplicativeDo #-}

-- GHC analyzes dependencies at compile time
program = do
  a <- action1
  b <- action2  -- GHC sees: doesn't depend on 'a'
  pure (a, b)

-- Desugared at COMPILE TIME to:
program = (,) <$> action1 <*> action2
```

The parallelism opportunity is discovered by GHC, not at runtime.

**3. Fusion and Rewrite Rules**

``` haskell
-- GHC's rewrite rules fire at compile time
{-# RULES "map/map" forall f g xs. map f (map g xs) = map (f . g) xs #-}

-- This code:
result = map show (map (+1) [1,2,3])

-- Becomes (at compile time):
result = map (show . (+1)) [1,2,3]  -- Single traversal
```

**4. Inlining and Specialization**

``` haskell
{-# INLINE fmap #-}  -- GHC inlines at compile time

-- Polymorphic code gets specialized at compile time
-- for specific types, enabling further optimization
```

##### Runtime Optimizations (Dynamic)

These optimizations happen while your program runs. The program inspects
data structures and makes decisions based on their contents.

**1. Free Structure Inspection**

Free Monads and Free Applicatives create **data structures** that exist
at runtime and can be analyzed:

``` haskell
-- This creates actual data at runtime
myWorkflow :: Ap WorkflowF Result
myWorkflow = liftAp (Fetch urlA) *> liftAp (Fetch urlB) *> liftAp (Process)

-- At RUNTIME, an interpreter can inspect this structure
optimizeWorkflow :: Ap WorkflowF a -> Ap WorkflowF a
optimizeWorkflow workflow =
  let ops = collectOperations workflow      -- Runtime inspection
      grouped = groupParallelOps ops        -- Runtime analysis
      optimized = batchSimilarOps grouped   -- Runtime transformation
  in rebuildWorkflow optimized
```

**2. Interpreter Selection**

The choice of how to execute can be made at runtime:

``` haskell
runWorkflow :: RuntimeConfig -> Ap WorkflowF a -> IO a
runWorkflow config workflow = case environment config of
  Development -> runSequential workflow       -- Runtime choice
  Production  -> runDistributed config workflow
```

**3. Dynamic Scheduling**

``` haskell
-- Scheduler examines DAG structure at runtime
scheduleDAG :: DagSpec -> IO ExecutionPlan
scheduleDAG dag = do
  resources <- queryAvailableResources        -- Runtime query
  let parallelism = min (maxParallel dag) (availableCores resources)
  pure (makeExecutionPlan parallelism dag)    -- Runtime decision
```

**4. Yoneda/Codensity Transformations**

These wrap and unwrap at runtime:

``` haskell
-- At runtime: lift into Yoneda
optimized = lowerYoneda (fmap h (fmap g (fmap f (liftYoneda structure))))
-- The function composition happens at runtime
-- The single traversal happens at runtime
```

##### The Key Distinction Visualized

``` mermaid
flowchart TD
    subgraph CompileTime["Compile Time (GHC)"]
        CT1["Type checking"]
        CT2["ApplicativeDo rewriting"]
        CT3["Fusion rules"]
        CT4["Inlining"]
        CT5["Specialization"]
    end

    subgraph Runtime["Runtime (Your Program)"]
        RT1["Free structure inspection"]
        RT2["Interpreter selection"]
        RT3["Dynamic scheduling"]
        RT4["Resource-based decisions"]
        RT5["Yoneda wrapping/unwrapping"]
    end

    SOURCE["Source Code"] --> CompileTime
    CompileTime --> BINARY["Compiled Binary"]
    BINARY --> Runtime
    Runtime --> RESULT["Execution Result"]

    style CompileTime fill:#e3f2fd
    style Runtime fill:#c8e6c9
```

##### What Each Abstraction Provides

| Abstraction | Compile-Time | Runtime | Notes |
|-------------|--------------|---------|-------|
| **Type-level deps** | ✅ Validation | ❌ | Errors caught before running |
| **ApplicativeDo** | ✅ Rewriting | ❌ | GHC finds parallelism |
| **Fusion rules** | ✅ Optimization | ❌ | Must be statically visible |
| **Free Applicative** | ✅ Type safety | ✅ Inspection & optimization | Best of both worlds |
| **Free Monad** | ✅ Type safety | ✅ Inspection | Limited by continuations |
| **Yoneda** | ❌ | ✅ fmap fusion | Runtime transformation |
| **Interpreters** | ❌ | ✅ Backend selection | Full flexibility |

##### Why Free Structures Enable Runtime Optimization

The key insight: **Free structures are data, not functions**.

``` haskell
-- This is DATA (can be inspected at runtime):
data Ap f a where
  Pure :: a -> Ap f a
  Ap   :: f a -> Ap f (a -> b) -> Ap f b

-- Compare to direct monadic code (cannot be inspected):
directCode :: IO Result
directCode = do
  a <- fetchA
  b <- fetchB
  process a b
-- This is already "running" - no structure to analyze
```

With Free structures:
1. **Build phase**: Construct the data structure (pure, no effects)
2. **Analysis phase**: Inspect, optimize, transform (still pure)
3. **Execution phase**: Interpret into actual effects

``` mermaid
flowchart LR
    subgraph Build["Build Phase (Pure)"]
        B1["Construct Free structure"]
    end

    subgraph Analyze["Analysis Phase (Pure, Runtime)"]
        A1["Count operations"]
        A2["Find parallel groups"]
        A3["Estimate resources"]
        A4["Optimize structure"]
    end

    subgraph Execute["Execution Phase (Effects)"]
        E1["Choose interpreter"]
        E2["Run with chosen backend"]
    end

    Build --> Analyze
    Analyze --> Execute

    style Build fill:#e3f2fd
    style Analyze fill:#fff3e0
    style Execute fill:#c8e6c9
```

#### 1.2.7 Choosing Between Compile-Time and Runtime Optimization

When should you rely on compile-time guarantees vs runtime flexibility?

##### Choose Compile-Time When:

**1. Correctness is paramount**

Type-level guarantees catch errors before deployment:

``` haskell
-- If your DAG can be validated at compile time, do it!
-- Runtime errors in production are costly
validPipeline :: Pipeline '["fetch", "process", "store"]
validPipeline = ...  -- Compiler ensures structure is correct
```

**2. Structure is fully known statically**

If you know the exact workflow at compile time, let GHC optimize:

``` haskell
-- Fixed pipeline - ApplicativeDo can optimize
knownWorkflow :: Workflow Result
knownWorkflow = do
  a <- stepA   -- GHC sees independence at compile time
  b <- stepB
  c <- stepC
  pure (combine a b c)
```

**3. Performance is critical and structure is fixed**

Compile-time optimization produces faster code:

``` haskell
-- Fusion rules eliminate intermediate structures
-- This is faster than runtime optimization
fastPipeline = map f . map g . map h  -- Fuses at compile time
```

##### Choose Runtime When:

**1. Structure depends on input data**

When the workflow shape isn't known until runtime:

``` haskell
-- DAG structure comes from user input or configuration
buildWorkflow :: Config -> IO (Ap WorkflowF Result)
buildWorkflow config = do
  dagSpec <- loadDagSpec (configPath config)
  pure (dagSpecToWorkflow dagSpec)  -- Structure determined at runtime
```

**2. Multiple execution strategies needed**

When the same workflow runs differently in different contexts:

``` haskell
runWorkflow :: Environment -> Ap WorkflowF a -> IO a
runWorkflow env workflow = case env of
  Testing    -> runMocked workflow
  LocalDev   -> runSequential workflow
  Staging    -> runParallel workflow
  Production -> runDistributed workflow
```

**3. Optimization requires external information**

When optimal execution depends on runtime state:

``` haskell
optimizeExecution :: Ap WorkflowF a -> IO (Ap WorkflowF a)
optimizeExecution workflow = do
  -- These are only known at runtime!
  availableCPUs <- getNumCapabilities
  availableGPUs <- queryGPUs
  spotPrices <- fetchSpotPrices

  pure (optimizeFor availableCPUs availableGPUs spotPrices workflow)
```

**4. Hot-reloading or dynamic updates**

When workflows change without recompilation:

``` haskell
-- Watch for config changes, rebuild workflow at runtime
watchAndRun :: IO ()
watchAndRun = do
  workflowRef <- newIORef =<< buildInitialWorkflow
  forkIO $ watchConfig $ \newConfig -> do
    newWorkflow <- buildWorkflow newConfig
    writeIORef workflowRef newWorkflow
  forever $ do
    workflow <- readIORef workflowRef
    runWorkflow workflow
```

##### The Hybrid Approach (Recommended)

In practice, **combine both** for maximum benefit:

``` haskell
-- 1. Type-level: Ensure node types are compatible (compile-time)
data TypedNode (input :: Type) (output :: Type) where
  MkNode :: NodeSpec -> TypedNode i o

-- 2. Free structure: Enable runtime analysis and optimization
type TypedWorkflow = Ap TypedNodeF

-- 3. Compile-time: Use ApplicativeDo for static workflows
buildStaticPart :: TypedWorkflow PartialResult
buildStaticPart = do  -- ApplicativeDo finds parallelism at compile time
  a <- typedNodeA
  b <- typedNodeB
  pure (a, b)

-- 4. Runtime: Combine with dynamic parts and optimize
fullWorkflow :: Config -> IO (TypedWorkflow Result)
fullWorkflow config = do
  dynamicPart <- buildDynamicNodes config
  let combined = combineWorkflows buildStaticPart dynamicPart
  optimizeWorkflow combined  -- Runtime optimization
```

##### Decision Framework

``` mermaid
flowchart TD
    Q1{"Is workflow structure<br/>known at compile time?"}
    Q2{"Do you need multiple<br/>execution strategies?"}
    Q3{"Does optimization need<br/>runtime information?"}
    Q4{"Is hot-reload or<br/>dynamic config needed?"}

    Q1 -->|"Yes, always fixed"| COMPILE["Prefer Compile-Time<br/>• Type-level validation<br/>• ApplicativeDo<br/>• Fusion rules"]
    Q1 -->|"No, varies"| RUNTIME["Need Runtime Analysis<br/>• Free structures<br/>• Interpreter selection"]

    Q2 -->|"Yes"| RUNTIME
    Q2 -->|"No, single strategy"| Q3

    Q3 -->|"Yes"| RUNTIME
    Q3 -->|"No"| Q4

    Q4 -->|"Yes"| RUNTIME
    Q4 -->|"No"| COMPILE

    COMPILE --> HYBRID["Consider Hybrid:<br/>Compile-time guarantees +<br/>Runtime flexibility"]
    RUNTIME --> HYBRID

    style COMPILE fill:#e3f2fd
    style RUNTIME fill:#c8e6c9
    style HYBRID fill:#fff3e0
```

##### Summary Table

| Question | Compile-Time | Runtime | Hybrid |
|----------|--------------|---------|--------|
| When is structure known? | Fully at compile | At execution | Mix |
| When are errors caught? | Before deploy | During testing/execution | Both |
| Optimization quality | Often better (GHC) | More flexible | Balanced |
| Code complexity | Lower | Higher | Medium |
| Flexibility | Low | High | High |
| Example use | Fixed ETL pipeline | User-defined workflows | Production systems |

For workflow systems like ours, the **hybrid approach** is typically best:
- Use types to enforce correctness (compile-time)
- Use Free Applicative for structure (enables runtime analysis)
- Use interpreters for flexibility (runtime backend selection)
- Use ApplicativeDo where structure is static (compile-time parallelism)

------------------------------------------------------------------------

### 1.3 Natural Transformations and Interpreters

A **natural transformation** is a structure-preserving map between functors.
It's how we translate from our pure DSL to actual effects.

``` haskell
-- Natural transformation type
type (~>) f g = forall a. f a -> g a
```

**Intuition**: A natural transformation says "for every type `a`, I can turn
an `f a` into a `g a`" in a way that respects the structure.

``` mermaid
flowchart LR
    subgraph Source["Source Functor f"]
        FA["f a"]
        FB["f b"]
    end

    subgraph Target["Target Functor g"]
        GA["g a"]
        GB["g b"]
    end

    FA --> |"η_a"| GA
    FB --> |"η_b"| GB
    FA --> |"fmap h"| FB
    GA --> |"fmap h"| GB

    style FA fill:#e3f2fd
    style FB fill:#e3f2fd
    style GA fill:#c8e6c9
    style GB fill:#c8e6c9
```

**The naturality condition** ensures the square commutes:

``` haskell
-- For any h :: a -> b
fmap h . eta = eta . fmap h
```

**For interpreters**, this means our translation respects the structure:

``` haskell
-- Interpret our workflow functor into IO
interpret :: WorkflowF ~> IO
interpret (LiftPure spec) = executePure spec
interpret (LiftBoundary spec inputs) = executeBoundary spec inputs
interpret (LiftSummary outcomes) = buildSummary outcomes

-- Interpret into Async for parallelism
interpretAsync :: WorkflowF ~> Async
interpretAsync (LiftPure spec) = Async (executePure spec)
interpretAsync (LiftBoundary spec inputs) = Async (executeBoundary spec inputs)
interpretAsync (LiftSummary outcomes) = Async (buildSummary outcomes)

-- Run entire Free Applicative with chosen interpreter
runWorkflow :: Applicative g => (WorkflowF ~> g) -> Ap WorkflowF a -> g a
runWorkflow interp = runAp interp
```

``` mermaid
flowchart TD
    DSL["Workflow DSL<br/>(Pure, no IO)"]

    DSL --> SEQ["runSequential<br/>IO Monad"]
    DSL --> PAR["runParallel<br/>Async"]
    DSL --> DIST["runDistributed<br/>PulsarTask"]

    SEQ --> |"~>"| IO["IO a"]
    PAR --> |"~>"| ASYNC["Async a"]
    DIST --> |"~>"| PULSAR["PulsarTask a"]

    subgraph Backends["Execution Backends"]
        IO
        ASYNC
        PULSAR
    end

    style DSL fill:#fff3e0
    style IO fill:#e3f2fd
    style ASYNC fill:#c8e6c9
    style PULSAR fill:#f3e5f5
```

### 1.4 Selective Functors: Between Applicative and Monad

We've seen that Applicative allows parallelism but can't express conditionals,
while Monad can express conditionals but forces sequencing. **Selective Functors**
sit exactly between them, allowing conditional execution while preserving
some static analysis capability.

#### 1.4.1 The Problem: Conditionals in Applicative

With pure Applicative, you cannot express "if this succeeds, do that":

``` haskell
-- This does NOT short-circuit with Applicative!
validateBoth :: Applicative f => f Bool -> f Bool -> f Bool
validateBoth check1 check2 = (&&) <$> check1 <*> check2
-- Both check1 AND check2 always run, even if check1 returns False
```

With Monad, you can short-circuit, but lose static analysis:

``` haskell
-- This short-circuits, but we can't see the structure
validateBoth :: Monad m => m Bool -> m Bool -> m Bool
validateBoth check1 check2 = do
  result1 <- check1
  if result1 then check2 else pure False
-- check2 is hidden behind a lambda - can't analyze statically
```

#### 1.4.2 The Selective Typeclass

Selective adds one operation that sits between `(<*>)` and `(>>=)`:

``` haskell
class Applicative f => Selective f where
  select :: f (Either a b) -> f (a -> b) -> f b
```

**Reading the type**:
- `f (Either a b)`: A computation that produces either `Left a` or `Right b`
- `f (a -> b)`: A handler for the `Left` case
- `f b`: The final result

**Key insight**: If the first computation returns `Right b`, we **might not need**
the second computation at all. But both computations are **structurally visible**
before we run anything.

``` mermaid
flowchart TD
    subgraph Select["select :: f (Either a b) → f (a → b) → f b"]
        CHECK["f (Either a b)"]
        HANDLER["f (a → b)"]
    end

    CHECK --> |"Right b"| RESULT["f b<br/>(skip handler)"]
    CHECK --> |"Left a"| APPLY["Apply handler"]
    HANDLER --> APPLY
    APPLY --> RESULT

    style CHECK fill:#fff3e0
    style HANDLER fill:#e3f2fd
    style RESULT fill:#c8e6c9
```

#### 1.4.3 Selective Laws

``` haskell
-- Identity: selecting with identity does nothing
select (Right <$> x) _ = x

-- Selection: applying a pure identity to a Left unwraps the value
select (Left <$> x) (pure id) = x

-- Associativity: nested selects associate
select x (select y z) = select (reassoc <$> x <*> y) z
  where
    reassoc (Left a)  (Left b)  = Left (Left a, b)
    reassoc (Left a)  (Right f) = Left (Right (f a))
    reassoc (Right b) _         = Right b
```

#### 1.4.4 Building Conditionals from Select

``` haskell
-- "If" built from branch (a two-way select)
-- branch :: Selective f => f (Either a b) -> f (a -> c) -> f (b -> c) -> f c
ifS :: Selective f => f Bool -> f a -> f a -> f a
ifS cond then_ else_ = branch
  (bool (Right ()) (Left ()) <$> cond)  -- True → Left (), False → Right ()
  (const <$> then_)                      -- Left case: use then_
  (const <$> else_)                      -- Right case: use else_

-- "When" - conditional execution
whenS :: Selective f => f Bool -> f () -> f ()
whenS cond action = ifS cond action (pure ())

-- Example: validate with short-circuit
validateAge :: Selective f => f Int -> f Bool
validateAge getAge = ifS ((<= 0) <$> getAge)
  (pure False)       -- Invalid: negative age
  ((< 150) <$> getAge) -- Check upper bound only if positive
```

#### 1.4.5 Why Selective Enables Conditional Parallelism

The key is that both branches of `ifS` are **values**, not functions:

``` haskell
ifS :: f Bool -> f a -> f a -> f a
--     ^^^^^^    ^^^^    ^^^^
--     Known     Known   Known!
--
-- Both branches exist as values BEFORE the condition is evaluated.
-- An interpreter can choose to run both speculatively and pick the result.

-- Compare to Monad's if:
monadicIf :: Monad m => m Bool -> m a -> m a -> m a
monadicIf cond then_ else_ = do
  b <- cond
  if b then then_ else else_
--
-- Here, only ONE branch will ever execute. The interpreter MUST wait
-- for 'cond' to complete before it knows which branch to take.
-- Even though both branches are visible in source code, only one runs.
```

The difference becomes clear with the **speculative execution** strategy:

``` haskell
-- Selective allows speculation: run both branches, pick result
runSelectiveSpeculative :: Selective f => f a -> IO a

-- Or static analysis: determine which branch is needed
analyzeSelectiveBranches :: Selective f => f a -> BranchInfo
```

``` mermaid
flowchart LR
    subgraph Monad["Monad: Sequential"]
        M1["check"] --> |"if True"| M2["thenBranch"]
        M1 --> |"if False"| M3["elseBranch"]
    end

    subgraph Selective["Selective: Optional Parallelism"]
        S1["check"]
        S2["thenBranch"]
        S3["elseBranch"]
        S1 --> PICK["Pick based on result"]
        S2 -.-> |"speculative"| PICK
        S3 -.-> |"speculative"| PICK
    end

    style M2 fill:#ffcdd2
    style M3 fill:#ffcdd2
    style S2 fill:#c8e6c9
    style S3 fill:#c8e6c9
```

#### 1.4.6 Selective in Workflow Systems

For our workflow system, Selective allows expressing:

``` haskell
-- Skip expensive processing if input is too small
processIfLarge :: Selective Workflow => Workflow ()
processIfLarge = whenS (isLargeInput <$> getInputSize)
                       expensiveProcessing

-- The structure reveals: expensiveProcessing may or may not run,
-- but we can statically see it's part of the workflow
```

#### 1.4.7 The Typeclass Hierarchy (Complete Picture)

``` mermaid
flowchart TD
    F["Functor<br/>fmap :: (a → b) → f a → f b"]
    A["Applicative<br/>(<*>) :: f (a → b) → f a → f b"]
    S["Selective<br/>select :: f (Either a b) → f (a → b) → f b"]
    M["Monad<br/>(>>=) :: m a → (a → m b) → m b"]

    F --> |"adds pure, (<*>)"| A
    A --> |"adds select"| S
    S --> |"adds (>>=)"| M

    F -.-> |"Transform contents"| FP["No combination"]
    A -.-> |"Combine independent"| AP["Full parallelism"]
    S -.-> |"Conditional combination"| SP["Conditional parallelism"]
    M -.-> |"Dependent chaining"| MP["No parallelism"]

    style F fill:#e3f2fd
    style A fill:#c8e6c9
    style S fill:#fff3e0
    style M fill:#fce4ec
```

| Typeclass | What it adds | Parallelism | Static analysis |
|-----------|--------------|-------------|-----------------|
| Functor | Transform values | N/A (single value) | Full |
| Applicative | Combine independent effects | Full | Full |
| Selective | Conditional effects | Partial (speculative) | Partial |
| Monad | Dependent effects | None | None |

------------------------------------------------------------------------

### 1.5 Traversable: The Bridge to Parallel Collection Processing

**Traversable** is a typeclass that describes data structures whose elements
can be visited in order, applying an effectful function to each. It's the
key to parallelizing operations over collections.

#### 1.5.1 The Traversable Typeclass

``` haskell
class (Functor t, Foldable t) => Traversable t where
  traverse :: Applicative f => (a -> f b) -> t a -> f (t b)
  -- Also: sequenceA :: Applicative f => t (f a) -> f (t a)
  -- Where: sequenceA = traverse id
```

**Reading the type of `traverse`**:
- `(a -> f b)`: A function that does something effectful to each element
- `t a`: A structure containing `a` values (like `[a]`, `Maybe a`, `Tree a`)
- `f (t b)`: The effects collected, structure preserved with transformed values

``` haskell
-- Examples
traverse print [1, 2, 3]           -- IO [()]  : prints 1, 2, 3
traverse readFile ["a.txt", "b.txt"] -- IO [String] : reads both files
traverse validate userInputs       -- Either Error [ValidInput]
```

#### 1.5.2 Why Traverse Uses Applicative (Not Monad)

Notice that `traverse` requires only `Applicative f`, not `Monad f`. This is
crucial: it means the effects are **independent** and can be parallelized!

``` haskell
traverse :: Applicative f => (a -> f b) -> t a -> f (t b)
--          ^^^^^^^^^^^
--          Not Monad! Effects are independent.
```

Compare with a hypothetical monadic version:

``` haskell
-- Hypothetical monadic traverse (NOT the real signature)
traverseM :: Monad m => (a -> m b) -> t a -> m (t b)
-- This would force sequential execution
```

#### 1.5.3 Parallel Traverse with Concurrently

The `Concurrently` newtype from `async` is an Applicative where `(<*>)`
runs both computations in parallel:

``` haskell
newtype Concurrently a = Concurrently { runConcurrently :: IO a }

instance Applicative Concurrently where
  pure = Concurrently . pure
  Concurrently a <*> Concurrently b = Concurrently $ do
    (f, x) <- concurrently a b  -- Run in parallel!
    pure (f x)
```

Now, `traverse` with `Concurrently` automatically parallelizes:

``` haskell
-- Sequential: one at a time
sequentialFetch :: [URL] -> IO [Response]
sequentialFetch urls = traverse httpGet urls

-- Parallel: all at once!
parallelFetch :: [URL] -> IO [Response]
parallelFetch urls = runConcurrently $ traverse (Concurrently . httpGet) urls
```

``` mermaid
flowchart TD
    subgraph Sequential["traverse httpGet [url1, url2, url3]"]
        S1["httpGet url1"] --> S2["httpGet url2"]
        S2 --> S3["httpGet url3"]
        S3 --> SR["[resp1, resp2, resp3]"]
    end

    subgraph Parallel["traverse (Concurrently . httpGet) [...]"]
        P1["httpGet url1"]
        P2["httpGet url2"]
        P3["httpGet url3"]
        P1 --> PR["[resp1, resp2, resp3]"]
        P2 --> PR
        P3 --> PR
    end

    style S1 fill:#ffcdd2
    style S2 fill:#ffcdd2
    style S3 fill:#ffcdd2
    style P1 fill:#c8e6c9
    style P2 fill:#c8e6c9
    style P3 fill:#c8e6c9
```

#### 1.5.4 Traversable Laws

``` haskell
-- Identity: traversing with Identity does nothing
traverse Identity = Identity

-- Composition: traversing with composed applicatives
traverse (Compose . fmap g . f) = Compose . fmap (traverse g) . traverse f

-- Naturality: natural transformations distribute over traverse
t . traverse f = traverse (t . f)  -- for appropriate t
```

#### 1.5.5 Common Traversable Instances

``` haskell
-- List: visit each element left-to-right
instance Traversable [] where
  traverse f = foldr (\x acc -> (:) <$> f x <*> acc) (pure [])

-- Maybe: visit the element if present
instance Traversable Maybe where
  traverse _ Nothing  = pure Nothing
  traverse f (Just x) = Just <$> f x

-- Either: traverse the Right value only
instance Traversable (Either e) where
  traverse _ (Left e)  = pure (Left e)
  traverse f (Right x) = Right <$> f x

-- Trees, Maps, custom data structures...
instance Traversable Tree where
  traverse f (Leaf x) = Leaf <$> f x
  traverse f (Node l r) = Node <$> traverse f l <*> traverse f r
```

#### 1.5.6 Traversable for DAG Nodes

In our workflow system, we can traverse DAG nodes in parallel:

``` haskell
-- A batch of nodes to execute
data NodeBatch = NodeBatch { batchNodes :: [NodeSpec] }

-- Execute all nodes in a batch in parallel
executeBatch :: NodeBatch -> IO [NodeOutcome]
executeBatch batch = runConcurrently $
  traverse (Concurrently . executeNode) (batchNodes batch)

-- Process all parallel batches sequentially
-- (because batches have dependencies between them)
executeAllBatches :: [NodeBatch] -> IO [[NodeOutcome]]
executeAllBatches batches = traverse executeBatch batches
```

``` mermaid
flowchart TD
    subgraph Batch1["Batch 1 (parallel within)"]
        B1N1["Node A"]
    end

    subgraph Batch2["Batch 2 (parallel within)"]
        B2N1["Node B"]
        B2N2["Node C"]
        B2N3["Node D"]
    end

    subgraph Batch3["Batch 3 (parallel within)"]
        B3N1["Node E"]
    end

    Batch1 --> Batch2
    Batch2 --> Batch3

    style B2N1 fill:#c8e6c9
    style B2N2 fill:#c8e6c9
    style B2N3 fill:#c8e6c9
```

#### 1.5.7 Traverse vs FoldMap

It's worth contrasting `traverse` with `foldMap`:

``` haskell
foldMap  :: (Foldable t, Monoid m) =>    (a -> m)   -> t a -> m
traverse :: (Traversable t, Applicative f) => (a -> f b) -> t a -> f (t b)
```

- `foldMap`: Combines results, discards structure
- `traverse`: Preserves structure, collects effects

``` haskell
-- foldMap: sum all the numbers (loses structure)
foldMap Sum [1, 2, 3] = Sum 6

-- traverse: transform each, keep structure
traverse (\x -> Just (x * 2)) [1, 2, 3] = Just [2, 4, 6]
```

For workflows, this means `traverse` can process a batch and give back
results in the same order they went in—essential for matching outputs
to inputs.

------------------------------------------------------------------------

### 1.6 The Yoneda Lemma: Optimization Through Abstraction

The **Yoneda lemma** is one of the most powerful results in category theory.
For Haskell programmers, it provides a technique for **optimizing repeated
`fmap` operations** and enables elegant solutions to certain problems.

#### 1.6.1 The Problem: Repeated fmap

Consider this code:

``` haskell
result = fmap h (fmap g (fmap f structure))
-- This traverses 'structure' THREE times!
```

For large structures, this is wasteful. We'd rather compose the functions
first and traverse once:

``` haskell
result = fmap (h . g . f) structure
-- Traverse once with composed function
```

The Yoneda lemma provides a systematic way to achieve this optimization,
even when the `fmap` calls are spread across different parts of the code.

#### 1.6.2 The Yoneda Type

``` haskell
newtype Yoneda f a = Yoneda { runYoneda :: forall b. (a -> b) -> f b }
```

**Reading the type**:
- `Yoneda f a` wraps an `f a`
- But instead of storing `f a` directly, it stores a **function**
- The function says: "give me any transformation `a -> b`, and I'll give you `f b`"

**Key insight**: The `forall b` means the function must work for **any** `b`.
The only way to do that is to have an `a` inside somewhere.

``` mermaid
flowchart LR
    subgraph Standard["Normal: f a"]
        FA["f a"]
    end

    subgraph YonedaView["Yoneda: ∀b. (a → b) → f b"]
        FN["λ(a → b) → f b"]
    end

    FA --> |"liftYoneda"| FN
    FN --> |"runYoneda id"| FA

    style FA fill:#e3f2fd
    style FN fill:#c8e6c9
```

#### 1.6.3 Yoneda is a Functor (with Free fmap!)

Here's the magic: `fmap` on `Yoneda` is **free** (O(1)):

``` haskell
instance Functor (Yoneda f) where
  fmap f (Yoneda g) = Yoneda (\k -> g (k . f))
  -- Just compose the functions! No traversal needed.
```

Compare with `fmap` on a list:

``` haskell
instance Functor [] where
  fmap f xs = [f x | x <- xs]  -- O(n) - must traverse the list
```

#### 1.6.4 Converting To and From Yoneda

``` haskell
-- Lift any functor into Yoneda (O(1))
liftYoneda :: Functor f => f a -> Yoneda f a
liftYoneda fa = Yoneda (\f -> fmap f fa)

-- Lower back to the original functor (does the actual fmap)
lowerYoneda :: Yoneda f a -> f a
lowerYoneda (Yoneda f) = f id
```

**The optimization strategy**:

1. Lift into Yoneda at the start
2. Do all your `fmap` operations (they just compose functions, O(1) each)
3. Lower at the end (does one traversal with the composed function)

``` haskell
-- Before: three traversals
slow = fmap h (fmap g (fmap f structure))

-- After: one traversal
fast = lowerYoneda (fmap h (fmap g (fmap f (liftYoneda structure))))
-- The fmaps just compose: h . g . f
-- lowerYoneda does fmap (h . g . f) structure - one traversal
```

#### 1.6.5 The Yoneda Lemma (Formally)

The Yoneda lemma states an **isomorphism**:

``` haskell
-- For any functor f and type a:
Yoneda f a  ≅  f a

-- The isomorphism is witnessed by:
liftYoneda  :: Functor f => f a -> Yoneda f a
lowerYoneda :: Yoneda f a -> f a

-- These are inverses:
lowerYoneda . liftYoneda = id
liftYoneda . lowerYoneda = id
```

**What this means**: `Yoneda f a` and `f a` contain exactly the same
information, just represented differently. You can freely convert between
them.

``` mermaid
flowchart LR
    FA["f a"] --> |"liftYoneda"| YFA["Yoneda f a"]
    YFA --> |"lowerYoneda"| FA

    YFA --> |"fmap f"| YFB["Yoneda f b<br/>(just compose)"]
    FA --> |"fmap f"| FB["f b<br/>(traverse structure)"]

    style YFA fill:#c8e6c9
    style YFB fill:#c8e6c9
```

#### 1.6.6 Practical Example: Optimizing Tree Transformations

``` haskell
data Tree a = Leaf a | Branch (Tree a) (Tree a)
  deriving (Functor)

-- A series of transformations
transformTree :: Tree Int -> Tree String
transformTree = fmap show . fmap (* 2) . fmap (+ 1)
-- Three traversals of the tree!

-- Optimized version
transformTreeFast :: Tree Int -> Tree String
transformTreeFast tree =
  lowerYoneda $
    fmap show $
      fmap (* 2) $
        fmap (+ 1) $
          liftYoneda tree
-- One traversal with (show . (* 2) . (+ 1))
```

#### 1.6.7 Yoneda in Workflow Systems

For workflow systems, Yoneda can optimize repeated transformations of results:

``` haskell
-- Processing a result through multiple stages
processResult :: Result -> FinalResult
processResult = format . validate . parse . normalize

-- If Result is wrapped in a functor (like IO or Workflow):
processResultM :: Workflow Result -> Workflow FinalResult
processResultM wr = fmap format (fmap validate (fmap parse (fmap normalize wr)))
-- Four traversals of the workflow structure!

-- Optimized:
processResultMFast :: Workflow Result -> Workflow FinalResult
processResultMFast wr = lowerYoneda $
  fmap format $ fmap validate $ fmap parse $ fmap normalize $ liftYoneda wr
-- One traversal
```

#### 1.6.8 Codensity: Yoneda for Monads

There's an analogous construction for Monads called **Codensity**:

``` haskell
newtype Codensity m a = Codensity { runCodensity :: forall b. (a -> m b) -> m b }
```

Just as Yoneda optimizes `fmap`, Codensity optimizes `(>>=)`:

``` haskell
instance Monad (Codensity m) where
  return a = Codensity (\k -> k a)
  Codensity m >>= f = Codensity (\k -> m (\a -> runCodensity (f a) k))
  -- This is "continuation-passing style" - avoids building intermediate structures
```

**Use case**: Optimizing deeply nested binds, especially in free monads:

``` haskell
-- Free monad can have O(n²) bind due to left-associated binds.
-- Codensity transformation makes it O(n) by converting to CPS.
--
-- Note: Functor f suffices as the constraint because Free f automatically
-- has a Monad instance when f is a Functor. The liftCodensity and
-- lowerCodensity functions require Monad, but that's satisfied by Free f.
--
-- This uses Codensity from the kan-extensions package.
improve :: Functor f => Free f a -> Free f a
improve = lowerCodensity . liftCodensity
```

#### 1.6.9 Summary: Why Yoneda Matters

| Concept | Optimizes | How |
|---------|-----------|-----|
| Yoneda | `fmap` | Delays traversal, composes functions |
| Codensity | `(>>=)` | Continuation-passing, avoids intermediate structures |

``` mermaid
flowchart TD
    subgraph Before["Before: Multiple Traversals"]
        S1["Structure"] --> F1["fmap f"]
        F1 --> F2["fmap g"]
        F2 --> F3["fmap h"]
        F3 --> R1["Result"]
    end

    subgraph After["After: Yoneda Optimization"]
        S2["liftYoneda"] --> C1["fmap f (compose)"]
        C1 --> C2["fmap g (compose)"]
        C2 --> C3["fmap h (compose)"]
        C3 --> L1["lowerYoneda"]
        L1 --> R2["Result"]
    end

    style F1 fill:#ffcdd2
    style F2 fill:#ffcdd2
    style F3 fill:#ffcdd2
    style C1 fill:#c8e6c9
    style C2 fill:#c8e6c9
    style C3 fill:#c8e6c9
```

------------------------------------------------------------------------

### 1.7 Mapping to NodeKind

The existing `NodeKind` types in the codebase map directly to these
category-theoretic concepts:

| NodeKind | Category Concept | Parallelism |
|----------|------------------|-------------|
| `PureNode` | Free Applicative effect | Full parallel within layer |
| `BoundaryNode` | Free Applicative at IO boundary | Parallel if independent |
| `SummaryNode` | Monadic bind (data dependency) | Sequential barrier |

``` mermaid
stateDiagram-v2
    [*] --> PureNode: Applicative
    [*] --> BoundaryNode: Applicative + IO

    PureNode --> PureNode: Parallel within layer
    BoundaryNode --> BoundaryNode: Parallel if independent

    PureNode --> SummaryNode: Monadic barrier
    BoundaryNode --> SummaryNode: Monadic barrier

    SummaryNode --> [*]: Terminal aggregation
```

### 1.8 ApplicativeDo Extension

GHC's `-XApplicativeDo` extension automatically rewrites `do`-notation
to use `Applicative` when dependencies allow:

``` haskell
{-# LANGUAGE ApplicativeDo #-}

-- GHC automatically parallelizes independent bindings:
separateAudio :: Workflow (Vocals, Drums, Bass)
separateAudio = do
  vocals <- separate "vocals" input
  drums  <- separate "drums" input   -- Independent of vocals
  bass   <- separate "bass" input    -- Independent of both
  pure (vocals, drums, bass)

-- Desugars to Applicative (parallel), not Monad (sequential):
-- (,,) <$> separate "vocals" input
--      <*> separate "drums" input
--      <*> separate "bass" input
```

### 1.9 Workflow DSL Definition

Combining these concepts, we define a workflow DSL:

``` haskell
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}

module StudioMCP.Workflow.DSL where

import Control.Applicative.Free (Ap, liftAp, runAp)
import Data.Text (Text)
import StudioMCP.DAG.Types (NodeId, NodeSpec, NodeKind(..))

-- Assumed types (defined elsewhere in the codebase):
type NodeOutcome = ...  -- Result of node execution
type Summary = ...      -- Final workflow summary

-- Workflow operation functor
-- Each constructor specifies its concrete result type
data WorkflowF a where
  LiftPure     :: NodeSpec -> WorkflowF NodeOutcome
  LiftBoundary :: NodeSpec -> [Text] -> WorkflowF NodeOutcome
  LiftSummary  :: [NodeOutcome] -> WorkflowF Summary

-- Free Applicative over WorkflowF preserves parallelism
type Workflow = Ap WorkflowF

-- Smart constructors
pureStep :: NodeSpec -> Workflow NodeOutcome
pureStep spec = liftAp (LiftPure spec)

boundaryStep :: NodeSpec -> [Text] -> Workflow NodeOutcome
boundaryStep spec inputs = liftAp (LiftBoundary spec inputs)

summaryStep :: [NodeOutcome] -> Workflow Summary
summaryStep outcomes = liftAp (LiftSummary outcomes)
```

### 1.10 Haskell Libraries Reference

| Library | Purpose | Hackage |
|---------|---------|---------|
| `free` | Free Monad and Free Applicative | [free](https://hackage.haskell.org/package/free) |
| `selective` | Selective functors for conditional parallelism | [selective](https://hackage.haskell.org/package/selective) |
| `async` | Parallel/concurrent IO, `Concurrently` Applicative | [async](https://hackage.haskell.org/package/async) |
| `kan-extensions` | Yoneda, Codensity, and other category theory | [kan-extensions](https://hackage.haskell.org/package/kan-extensions) |
| `operational` | Alternative to Free Monad | [operational](https://hackage.haskell.org/package/operational) |
| `mtl` | Monad transformers | [mtl](https://hackage.haskell.org/package/mtl) |
| `comonad` | Comonads for context-dependent computation | [comonad](https://hackage.haskell.org/package/comonad) |

### 1.11 GHC Extensions Required

``` haskell
{-# LANGUAGE ApplicativeDo #-}    -- Auto-parallelize do-notation
{-# LANGUAGE GADTs #-}            -- Typed DSL constructors
{-# LANGUAGE DataKinds #-}        -- Type-level dependency tracking
{-# LANGUAGE TypeOperators #-}    -- Type-level list operations
{-# LANGUAGE RankNTypes #-}       -- Natural transformations
```

------------------------------------------------------------------------

## Section 2: The Lift Pattern - Pure DAG to Distributed Execution

This section describes how pure job representations get "lifted" at
execution time to the distributed system running on the cluster.

### 2.1 Interpreter Architecture

The core idea is that a pure `Workflow` value can be interpreted into
different execution backends via natural transformations:

``` haskell
-- Interpreter selection based on runtime environment
data RuntimeMode
  = LocalDev        -- Sequential IO for debugging
  | SingleNode      -- Parallel Async on one machine
  | Cluster         -- Distributed via Pulsar/K8s
  deriving (Eq, Show)

-- Polymorphic interpreter
runWorkflow :: RuntimeMode -> RuntimeConfig -> Workflow a -> IO a
runWorkflow LocalDev   _   wf = runSequential wf
runWorkflow SingleNode _   wf = runParallel wf
runWorkflow Cluster    cfg wf = runDistributed cfg wf
```

``` mermaid
flowchart LR
    subgraph Pure["Pure Workflow"]
        W["Workflow a"]
    end

    W --> |"LocalDev"| SEQ["Sequential<br/>runSequential"]
    W --> |"SingleNode"| PAR["Parallel<br/>runParallel"]
    W --> |"Cluster"| DIST["Distributed<br/>runDistributed"]

    SEQ --> IO["IO a"]
    PAR --> ASYNC["Async a"]
    DIST --> K8S["K8s Jobs"]
```

### 2.2 Lifting Pipeline Stages

The full pipeline from pure `DagSpec` to running Kubernetes jobs:

``` haskell
-- Pipeline stage types
newtype ValidatedDag = ValidatedDag { unValidatedDag :: DagSpec }
  deriving (Eq, Show)

data DagResourceEstimate = DagResourceEstimate
  { estimateNodes        :: [NodeResourceEstimate]
  , estimatePeakParallel :: Natural
  , estimatePeakResources :: ResourceRequirements
  , estimateCriticalPath :: [NodeId]
  , estimateWallClock    :: DurationEstimate
  }
  deriving (Eq, Show, Generic)

data ChunkedDagPlan = ChunkedDagPlan
  { planOriginalDag      :: ValidatedDag
  , planExpandedNodes    :: [ExpandedNodeSpec]
  , planTopologicalOrder :: [NodeId]
  , planCriticalPath     :: [NodeId]
  }
  deriving (Eq, Show)

data ProvisioningPlan = ProvisioningPlan
  { provisionSpotRequests    :: [SpotInstanceRequest]
  , provisionOnDemandFallback :: [OnDemandRequest]
  , provisionNodePools       :: [NodePoolConfig]
  , provisionEstimatedCost   :: CostEstimate
  }
  deriving (Eq, Show)

data ScheduledExecution = ScheduledExecution
  { execRunId          :: RunId
  , execDagPlan        :: ChunkedDagPlan
  , execProvisionPlan  :: ProvisioningPlan
  , execKubeJobs       :: [KubeJobSpec]
  , execEstimatedStart :: UTCTime
  }
  deriving (Eq, Show)
```

``` mermaid
flowchart TD
    A["Pure DagSpec"] --> B{"Validate"}
    B -->|Valid| C["ValidatedDag"]
    B -->|Invalid| ERR1["ValidationError"]

    C --> D["Estimate Resources"]
    D --> E["DagResourceEstimate"]

    E --> F["Plan Chunking"]
    F --> G["ChunkedDagPlan"]

    G --> H["Query Spot Pricing"]
    H --> I["ProvisioningPlan"]

    I --> J{"Request Capacity"}
    J -->|"Spot Available"| K["Generate K8s Jobs"]
    J -->|"Spot Unavailable"| L["Fallback On-Demand"]
    L --> K

    K --> M["ScheduledExecution"]
    M --> N["Submit to K8s"]
    N --> O["RunId + Tracking"]

    style A fill:#e1f5fe
    style O fill:#c8e6c9
```

### 2.3 Lifting Pipeline Implementation

``` haskell
import Data.List.NonEmpty (NonEmpty(..))

-- Complete lifting pipeline
--
-- We use NonEmpty FailureDetail rather than [FailureDetail] to guarantee
-- at compile time that failures always include at least one error detail.
-- This prevents the impossible state of "failed with no explanation."
data LiftingPipeline = LiftingPipeline
  { liftValidate   :: DagSpec -> Either (NonEmpty FailureDetail) ValidatedDag
  , liftEstimate   :: ValidatedDag -> IO (Either (NonEmpty FailureDetail) DagResourceEstimate)
  , liftChunk      :: DagResourceEstimate -> IO ChunkedDagPlan
  , liftProvision  :: ChunkedDagPlan -> IO (Either (NonEmpty FailureDetail) ProvisioningPlan)
  , liftSchedule   :: ProvisioningPlan -> IO (Either (NonEmpty FailureDetail) ScheduledExecution)
  , liftDispatch   :: ScheduledExecution -> IO (Either (NonEmpty FailureDetail) RunId)
  }

-- Execute the full pipeline
runLiftingPipeline :: LiftingPipeline -> DagSpec -> IO (Either (NonEmpty FailureDetail) RunId)
runLiftingPipeline pipeline dagSpec = runExceptT $ do
  validated   <- ExceptT $ pure $ liftValidate pipeline dagSpec
  estimated   <- ExceptT $ liftEstimate pipeline validated
  chunked     <- lift $ liftChunk pipeline estimated
  provisioned <- ExceptT $ liftProvision pipeline chunked
  scheduled   <- ExceptT $ liftSchedule pipeline provisioned
  ExceptT $ liftDispatch pipeline scheduled
```

### 2.4 Kubernetes Job Generation

``` haskell
-- Generate K8s Job from node spec
data KubeJobSpec = KubeJobSpec
  { kubeJobName        :: Text
  , kubeJobNamespace   :: Text
  , kubeJobNodeId      :: NodeId
  , kubeJobImage       :: Text
  , kubeJobCommand     :: [Text]
  , kubeJobResources   :: KubeResourceSpec
  , kubeJobAffinity    :: Maybe NodeAffinity
  , kubeJobTolerations :: [Toleration]
  , kubeJobDependsOn   :: [NodeId]
  , kubeJobTimeout     :: Natural
  }
  deriving (Eq, Show, Generic)

data KubeResourceSpec = KubeResourceSpec
  { kubeReqCpu      :: Text      -- "500m"
  , kubeReqMemory   :: Text      -- "512Mi"
  , kubeLimitCpu    :: Text
  , kubeLimitMemory :: Text
  , kubeGpuLimit    :: Maybe (Text, Natural)  -- ("nvidia.com/gpu", 1)
  }
  deriving (Eq, Show, Generic)

-- Transform NodeResourceEstimate to KubeJobSpec
generateKubeJob
  :: RunId
  -> NodeResourceEstimate
  -> ProvisioningPlan
  -> KubeJobSpec
generateKubeJob runId estimate plan = KubeJobSpec
  { kubeJobName = mconcat
      [ "studiomcp-"
      , unRunId runId
      , "-"
      , unNodeId (estimateNodeId estimate)
      ]
  , kubeJobNamespace = "studiomcp"
  , kubeJobNodeId = estimateNodeId estimate
  , kubeJobImage = toolToImage (estimateTool estimate)
  , kubeJobCommand = toolToCommand (estimateTool estimate)
  , kubeJobResources = toKubeResources (estimateResources estimate)
  , kubeJobAffinity = selectAffinity plan estimate
  , kubeJobTolerations = spotTolerations
  , kubeJobDependsOn = [] -- Filled by scheduler
  , kubeJobTimeout = durationP95Seconds (estimateDuration estimate)
  }
```

------------------------------------------------------------------------

## Section 3: Task Partitioning Algebra

This section defines pure types for scatter/gather transformation,
enabling a single logical node to be "exploded" into parallel sub-tasks.

### 3.1 Partition Strategy Types

``` haskell
-- Partition strategy describes how to split input data
data PartitionStrategy
  = ChunkByBytes Natural          -- Split into N-byte chunks
  | ChunkByCount Natural          -- Split into N equal parts
  | ChunkByDuration Natural       -- For temporal media: split by milliseconds
  | ChunkByMarkers [Marker]       -- Split at semantic boundaries
  deriving (Eq, Show, Generic)

-- Partition specification for a node
data PartitionSpec = PartitionSpec
  { partitionSourceNode  :: NodeId
  , partitionStrategy    :: PartitionStrategy
  , partitionMinChunks   :: Natural
  , partitionMaxChunks   :: Natural
  , partitionOverlapMs   :: Maybe Natural  -- Overlap for audio crossfade
  }
  deriving (Eq, Show, Generic)

-- Chunk identifier within a partitioned job
data ChunkId = ChunkId
  { chunkParentNode :: NodeId
  , chunkIndex      :: Natural
  , chunkTotal      :: Natural
  }
  deriving (Eq, Ord, Show, Generic)

-- Reference to a portion of an artifact
data ChunkRef = ChunkRef
  { chunkArtifact   :: ArtifactRef
  , chunkByteOffset :: Natural
  , chunkByteLength :: Natural
  }
  deriving (Eq, Show, Generic)
```

### 3.2 Gather Strategy Types

``` haskell
-- Symbolic identifier for merge strategies
-- The interpreter resolves these to actual merge functions at runtime
data MergeStrategyId
  = MergeConcat           -- Simple byte concatenation
  | MergeCrossfade        -- Audio crossfade merge
  | MergeCustom Text      -- Named custom strategy (looked up in registry)
  deriving (Eq, Show, Generic)

-- Symbolic identifier for reduce strategies
-- The interpreter resolves these to actual reduce functions at runtime
data ReduceStrategyId
  = ReduceSum             -- Sum reduction
  | ReduceMax             -- Maximum reduction
  | ReduceMin             -- Minimum reduction
  | ReduceCustom Text     -- Named custom strategy (looked up in registry)
  deriving (Eq, Show, Generic)

-- Gather strategy: how parallel results merge back
data GatherStrategy
  = Concatenate                    -- Sequential concatenation
  | Merge MergeStrategyId          -- Symbolic merge reference
  | Reduce ReduceStrategyId        -- Symbolic reduce reference
  | CrossfadeAudio Natural         -- Audio crossfade with overlap in ms
  deriving (Eq, Show, Generic)

data GatherSpec = GatherSpec
  { gatherTargetNode    :: NodeId
  , gatherSourceChunks  :: [ChunkId]
  , gatherStrategy      :: GatherStrategy
  , gatherOutputType    :: OutputType
  }
  deriving (Eq, Show, Generic)
```

### 3.3 Exploded Sub-DAG

The explosion transformation takes a single `NodeSpec` with partition/gather
specs and produces a sub-DAG of parallel workers plus scatter/gather nodes.

``` haskell
-- Result of node explosion
data ExplodedSubDag = ExplodedSubDag
  { explodedScatterNode   :: NodeSpec      -- Partitioner node
  , explodedWorkerNodes   :: [NodeSpec]    -- Parallel worker nodes
  , explodedGatherNode    :: NodeSpec      -- Aggregator node
  , explodedInternalEdges :: [Edge]        -- Scatter -> Workers -> Gather
  }
  deriving (Eq, Show, Generic)

-- Pure transformation: one node becomes many parallel nodes + gather
explodeNode :: NodeSpec -> PartitionSpec -> GatherSpec -> ExplodedSubDag
explodeNode originalNode partitionSpec gatherSpec = ExplodedSubDag
  { explodedScatterNode = mkScatterNode originalNode partitionSpec
  , explodedWorkerNodes = mkWorkerNodes originalNode partitionSpec
  , explodedGatherNode = mkGatherNode originalNode gatherSpec
  , explodedInternalEdges = mkInternalEdges partitionSpec gatherSpec
  }
```

``` mermaid
flowchart LR
    subgraph Before["Original DAG"]
        F1[Fetch] --> S1[Separate]
        S1 --> P1[Persist]
    end

    subgraph After["Exploded DAG"]
        F2[Fetch] --> SC[Scatter]
        SC --> W1[Worker 0]
        SC --> W2[Worker 1]
        SC --> W3[Worker N]
        W1 --> G[Gather]
        W2 --> G
        W3 --> G
        G --> P2[Persist]
    end

    Before --> |"explodeNode"| After

    style SC fill:#ffecb3
    style G fill:#ffecb3
    style W1 fill:#c8e6c9
    style W2 fill:#c8e6c9
    style W3 fill:#c8e6c9
```

### 3.4 Audio Separation Example with Scatter/Gather

``` mermaid
flowchart TD
    INPUT["Input Audio<br/>5 min file"] --> SCATTER["Scatter Node"]

    SCATTER --> C0["Chunk 0<br/>0:00-0:30"]
    SCATTER --> C1["Chunk 1<br/>0:30-1:00"]
    SCATTER --> C2["Chunk 2<br/>1:00-1:30"]
    SCATTER --> CN["Chunk N<br/>..."]

    C0 --> D0["Demucs<br/>Worker 0"]
    C1 --> D1["Demucs<br/>Worker 1"]
    C2 --> D2["Demucs<br/>Worker 2"]
    CN --> DN["Demucs<br/>Worker N"]

    D0 --> GATHER["Gather Node<br/>(Crossfade)"]
    D1 --> GATHER
    D2 --> GATHER
    DN --> GATHER

    GATHER --> OUTPUT["Merged Stems<br/>vocals, drums, bass, other"]

    style SCATTER fill:#ffecb3
    style GATHER fill:#ffecb3
    style D0 fill:#c8e6c9
    style D1 fill:#c8e6c9
    style D2 fill:#c8e6c9
    style DN fill:#c8e6c9
```

### 3.5 Chunk Overlap for Audio Crossfade

For audio workflows, chunks must overlap to enable seamless crossfade
merging:

``` mermaid
gantt
    title Audio Chunk Overlap (500ms crossfade)
    dateFormat X
    axisFormat %s

    section Chunk 0
    Audio 0:00-30:00    :c0, 0, 30000
    Overlap             :o0, 29500, 30500

    section Chunk 1
    Overlap             :o1a, 29500, 30500
    Audio 30:00-60:00   :c1, 30000, 60000
    Overlap             :o1b, 59500, 60500

    section Chunk 2
    Overlap             :o2a, 59500, 60500
    Audio 60:00-90:00   :c2, 60000, 90000
```

### 3.6 Type-Safe Gather Invariant

The gather function must produce the same `OutputType` as the original node:

``` haskell
-- Type-level invariant: gather output matches original node output
gatherInvariant :: NodeSpec -> GatherSpec -> Bool
gatherInvariant originalNode gatherSpec =
  nodeOutputType originalNode == gatherOutputType gatherSpec

-- Content-addressed validation: gathered result must match deterministic derivation
verifyGatherIntegrity :: GatherInput -> GatherResult -> Either FailureDetail ()
verifyGatherIntegrity input result =
  let expectedHash = deriveContentAddress
        (map workerResultHash (gatherChunkResults input))
  in if expectedHash == gatherMergedHash result
     then Right ()
     else Left (validationFailure "gather-hash-mismatch"
                "Gathered result hash does not match chunk derivation")
```

### 3.7 Expanded Node Types

``` haskell
-- A node that may have been partitioned
data ExpandedNodeSpec
  = OriginalNode NodeSpec           -- Unchanged node
  | ChunkedNode ChunkedNodeSpec     -- Partitioned node
  deriving (Eq, Show, Generic)

data ChunkedNodeSpec = ChunkedNodeSpec
  { chunkedOriginal   :: NodeSpec
  , chunkedPartitions :: [ChunkPartition]
  , chunkedMergeNode  :: NodeSpec
  }
  deriving (Eq, Show, Generic)

data ChunkPartition = ChunkPartition
  { partitionIndex     :: Natural
  , partitionByteRange :: (Natural, Natural)  -- Start, end offset
  , partitionNodeSpec  :: NodeSpec            -- Per-chunk node
  }
  deriving (Eq, Show, Generic)
```

------------------------------------------------------------------------

## Section 4: Content-Addressed Memoization with S3/MinIO

Large intermediate objects (audio files, ML model outputs, video frames)
are expensive to recompute. This section describes how to use S3/MinIO
as a **content-addressed cache** for memoizing workflow intermediates.

### 4.1 Why Memoization Matters for Distributed Workflows

In a distributed system, memoization provides:

1. **Fault tolerance**: If a worker crashes, restarting doesn't recompute completed steps
2. **Cost savings**: Avoid redundant computation (especially for GPU-intensive tasks)
3. **Incremental execution**: Re-running a modified workflow skips unchanged nodes
4. **Debugging**: Inspect intermediate results without re-running entire pipeline

``` mermaid
flowchart TD
    subgraph WithoutMemo["Without Memoization"]
        A1["Fetch Audio"] --> B1["Separate (GPU, 10 min)"]
        B1 --> C1["Process"]
        C1 --> D1["Output"]

        CRASH["💥 Crash"] -.-> B1
        RESTART["Restart"] --> A1
    end

    subgraph WithMemo["With S3 Memoization"]
        A2["Fetch Audio"] --> CHECK{"Check S3<br/>for cached result"}
        CHECK -->|"Cache miss"| B2["Separate (GPU, 10 min)"]
        CHECK -->|"Cache hit"| SKIP["Skip computation"]
        B2 --> STORE["Store in S3"]
        STORE --> C2["Process"]
        SKIP --> C2
        C2 --> D2["Output"]
    end

    style B1 fill:#ffcdd2
    style B2 fill:#c8e6c9
    style SKIP fill:#c8e6c9
```

### 4.2 Content-Addressed Storage

Content-addressed storage uses the **hash of the content** as the storage key.
This provides automatic deduplication and deterministic cache keys.

``` haskell
-- Content address is a cryptographic hash
newtype ContentAddress = ContentAddress { unContentAddress :: ByteString }
  deriving (Eq, Ord, Show)

-- Compute content address from data
computeContentAddress :: ByteString -> ContentAddress
computeContentAddress = ContentAddress . SHA256.hash

-- S3 key derived from content address
toS3Key :: ContentAddress -> S3.ObjectKey
toS3Key (ContentAddress hash) = S3.ObjectKey $
  "artifacts/" <> Base16.encode hash
```

**Key insight**: If two computations produce the same output, they have the
same content address. We only store one copy.

### 4.3 Deriving Cache Keys from Pure Node Specs

Because our workflow is **pure**, we can derive deterministic cache keys
from the node specification itself. The cache key depends on:

1. The node's operation (what tool, what parameters)
2. The content addresses of all inputs
3. Any configuration that affects output

``` haskell
-- Everything needed to compute a cache key
data MemoKey = MemoKey
  { memoNodeId     :: NodeId
  , memoTool       :: Maybe ToolName
  , memoInputs     :: [ContentAddress]  -- Hashes of input artifacts
  , memoParams     :: Map Text Text     -- Tool parameters
  , memoVersion    :: ToolVersion       -- Tool version (affects output)
  }
  deriving (Eq, Show, Generic)

-- Derive cache key (content address of the MemoKey itself)
deriveCacheKey :: MemoKey -> ContentAddress
deriveCacheKey = computeContentAddress . Aeson.encode

-- Build MemoKey from node spec and resolved inputs
buildMemoKey :: NodeSpec -> [ContentAddress] -> MemoKey
buildMemoKey spec inputAddresses = MemoKey
  { memoNodeId = nodeId spec
  , memoTool = nodeTool spec
  , memoInputs = sort inputAddresses  -- Sort for determinism
  , memoParams = nodeParams spec
  , memoVersion = toolVersion (nodeTool spec)
  }
```

**Why this works**: Pure functions always produce the same output for the
same input. If the `MemoKey` is identical, the output will be identical.

``` mermaid
flowchart LR
    subgraph Inputs["Inputs to Cache Key"]
        NODE["NodeSpec<br/>(tool, params)"]
        INP1["Input 1<br/>ContentAddress"]
        INP2["Input 2<br/>ContentAddress"]
        VER["Tool Version"]
    end

    COMBINE["Combine & Hash"]
    KEY["MemoKey<br/>(ContentAddress)"]
    S3["S3 Lookup"]

    NODE --> COMBINE
    INP1 --> COMBINE
    INP2 --> COMBINE
    VER --> COMBINE
    COMBINE --> KEY
    KEY --> S3
```

### 4.4 The Memoization Lookup Flow

Before executing any node, check if the result already exists:

``` haskell
-- S3 memoization adapter
data MemoStore = MemoStore
  { memoLookup  :: ContentAddress -> IO (Maybe ArtifactRef)
  , memoStore   :: ContentAddress -> ByteString -> IO ArtifactRef
  , memoExists  :: ContentAddress -> IO Bool
  }

-- Execute with memoization
executeWithMemo
  :: MemoStore
  -> NodeSpec
  -> [ArtifactRef]           -- Input artifacts
  -> (NodeSpec -> IO ByteString)  -- Actual execution
  -> IO ArtifactRef
executeWithMemo store spec inputs execute = do
  -- 1. Resolve input content addresses
  inputAddresses <- mapM (resolveContentAddress store) inputs

  -- 2. Derive cache key
  let memoKey = buildMemoKey spec inputAddresses
      cacheKey = deriveCacheKey memoKey

  -- 3. Check cache
  cached <- memoLookup store cacheKey
  case cached of
    Just artifactRef -> do
      logInfo $ "Cache hit for " <> show (nodeId spec)
      pure artifactRef

    Nothing -> do
      logInfo $ "Cache miss for " <> show (nodeId spec)
      -- 4. Execute and store result
      result <- execute spec
      artifactRef <- memoStore store cacheKey result
      pure artifactRef
```

``` mermaid
sequenceDiagram
    participant Worker
    participant MemoStore as Memo Store
    participant S3 as S3/MinIO
    participant Executor

    Worker->>MemoStore: buildMemoKey(spec, inputs)
    MemoStore->>MemoStore: deriveCacheKey(memoKey)
    MemoStore->>S3: HEAD object (check exists)

    alt Cache Hit
        S3-->>MemoStore: 200 OK
        MemoStore-->>Worker: ArtifactRef (cached)
    else Cache Miss
        S3-->>MemoStore: 404 Not Found
        Worker->>Executor: execute(spec)
        Executor-->>Worker: result bytes
        Worker->>S3: PUT object
        S3-->>Worker: ArtifactRef (new)
    end
```

### 4.5 S3 Storage Layout

Organize artifacts for efficient access and garbage collection:

``` haskell
-- S3 bucket layout
data S3Layout = S3Layout
  { layoutBucket     :: BucketName
  , layoutPrefix     :: Text
  }

-- Object key structure:
-- {prefix}/artifacts/{content-hash}           -- The actual artifact
-- {prefix}/meta/{content-hash}.json           -- Metadata (size, type, created)
-- {prefix}/runs/{run-id}/{node-id}            -- Symlink to artifact for debugging
-- {prefix}/cache-keys/{cache-key}             -- Maps cache key → content address

toArtifactKey :: S3Layout -> ContentAddress -> S3.ObjectKey
toArtifactKey layout addr = S3.ObjectKey $
  layoutPrefix layout <> "/artifacts/" <> Base16.encode (unContentAddress addr)

toMetadataKey :: S3Layout -> ContentAddress -> S3.ObjectKey
toMetadataKey layout addr = S3.ObjectKey $
  layoutPrefix layout <> "/meta/" <> Base16.encode (unContentAddress addr) <> ".json"

toCacheKeyMapping :: S3Layout -> ContentAddress -> S3.ObjectKey
toCacheKeyMapping layout cacheKey = S3.ObjectKey $
  layoutPrefix layout <> "/cache-keys/" <> Base16.encode (unContentAddress cacheKey)
```

**Directory structure example**:

```
s3://workflow-artifacts/
├── artifacts/
│   ├── a1b2c3d4...    # Raw artifact bytes (content-addressed)
│   ├── e5f6g7h8...
│   └── ...
├── meta/
│   ├── a1b2c3d4....json   # {"size": 1048576, "type": "audio/wav", "created": "..."}
│   └── ...
├── cache-keys/
│   ├── x1y2z3...      # Contains content address of result
│   └── ...
└── runs/
    └── run-20240115-001/
        ├── fetch -> ../artifacts/a1b2c3d4...
        ├── separate -> ../artifacts/e5f6g7h8...
        └── ...
```

### 4.6 Handling Large Objects Efficiently

For large intermediates (multi-GB audio/video files), we need efficient streaming:

``` haskell
-- Stream large objects without loading into memory
data StreamingMemoStore = StreamingMemoStore
  { streamLookup :: ContentAddress -> IO (Maybe (ConduitT () ByteString IO ()))
  , streamStore  :: ContentAddress -> ConduitT () ByteString IO () -> IO ArtifactRef
  , multipartUpload :: ContentAddress -> Natural -> IO MultipartUploadHandle
  }

-- Execute with streaming I/O
executeWithStreamingMemo
  :: StreamingMemoStore
  -> NodeSpec
  -> [ArtifactRef]
  -> (NodeSpec -> ConduitT () ByteString IO ())  -- Streaming execution
  -> IO ArtifactRef
executeWithStreamingMemo store spec inputs execute = do
  inputAddresses <- mapM resolveAddress inputs
  let cacheKey = deriveCacheKey (buildMemoKey spec inputAddresses)

  cached <- streamLookup store cacheKey
  case cached of
    Just stream -> do
      -- Stream exists, return reference without downloading
      pure (ArtifactRef cacheKey)
    Nothing -> do
      -- Stream result directly to S3
      streamStore store cacheKey (execute spec)
```

**Multipart upload for very large files**:

``` haskell
-- Upload large artifacts in chunks (S3 multipart)
uploadLargeArtifact
  :: S3Layout
  -> ContentAddress
  -> FilePath          -- Local temp file
  -> IO ArtifactRef
uploadLargeArtifact layout addr localPath = do
  let key = toArtifactKey layout addr
      chunkSize = 100 * 1024 * 1024  -- 100 MB chunks

  -- Initiate multipart upload
  uploadId <- S3.createMultipartUpload bucket key

  -- Upload chunks in parallel
  chunks <- chunkFile localPath chunkSize
  parts <- forConcurrently (zip [1..] chunks) $ \(partNum, chunk) ->
    S3.uploadPart bucket key uploadId partNum chunk

  -- Complete upload
  S3.completeMultipartUpload bucket key uploadId parts
  pure (ArtifactRef addr)
```

``` mermaid
flowchart TD
    subgraph SmallObject["Small Object (< 100MB)"]
        S1["Read into memory"]
        S2["Single PUT request"]
        S3["Done"]
        S1 --> S2 --> S3
    end

    subgraph LargeObject["Large Object (> 100MB)"]
        L1["Chunk file (100MB parts)"]
        L2["Parallel upload chunks"]
        L3["Complete multipart"]
        L4["Done"]
        L1 --> L2 --> L3 --> L4
    end

    style S2 fill:#e3f2fd
    style L2 fill:#c8e6c9
```

### 4.7 Cache Invalidation and Garbage Collection

Content-addressed storage simplifies cache invalidation:

``` haskell
-- Invalidation strategies
data InvalidationStrategy
  = InvalidateByAge Natural          -- Delete artifacts older than N days
  | InvalidateByRun RunId            -- Delete all artifacts for a run
  | InvalidateByNode NodeId          -- Invalidate specific node's cache
  | InvalidateAll                    -- Clear entire cache
  deriving (Eq, Show)

-- Garbage collection: find unreferenced artifacts
garbageCollect :: S3Layout -> [RunId] -> IO [ContentAddress]
garbageCollect layout activeRuns = do
  -- 1. List all artifacts
  allArtifacts <- S3.listObjects bucket (layoutPrefix layout <> "/artifacts/")

  -- 2. Find referenced artifacts (from active runs)
  referencedAddrs <- foldMap (getRunReferences layout) activeRuns

  -- 3. Delete unreferenced
  let unreferenced = Set.difference allArtifacts referencedAddrs
  mapM_ (S3.deleteObject bucket . toArtifactKey layout) unreferenced
  pure (Set.toList unreferenced)
```

**Why content-addressing helps**:
- No explicit invalidation needed when inputs change (different key)
- Deduplication is automatic (same content = same key)
- GC just removes unreferenced objects

### 4.8 Integration with Free Applicative Workflows

Memoization integrates naturally with our Free structure approach:

``` haskell
-- Workflow interpreter with memoization
runWithMemo :: MemoStore -> Ap WorkflowF a -> IO a
runWithMemo store = runAp interpret
  where
    interpret :: WorkflowF x -> IO x
    interpret (LiftPure spec inputs) =
      executeWithMemo store spec inputs executePure
    interpret (LiftBoundary spec inputs) =
      executeWithMemo store spec inputs executeBoundary
    interpret (LiftSummary outcomes) =
      pure (buildSummary outcomes)  -- Summaries typically not memoized

-- Analyze workflow for cache hits before execution
analyzeCacheStatus :: MemoStore -> Ap WorkflowF a -> IO CacheAnalysis
analyzeCacheStatus store workflow = do
  let nodes = collectNodes workflow
  statuses <- forM nodes $ \(spec, inputs) -> do
    inputAddrs <- mapM resolveAddress inputs
    let key = deriveCacheKey (buildMemoKey spec inputAddrs)
    exists <- memoExists store key
    pure (nodeId spec, exists)
  pure CacheAnalysis
    { cachedNodes = filter snd statuses
    , uncachedNodes = filter (not . snd) statuses
    , estimatedSavings = computeSavings (filter snd statuses)
    }
```

``` mermaid
flowchart TD
    WF["Free Applicative<br/>Workflow"]

    ANALYZE["analyzeCacheStatus"]
    REPORT["CacheAnalysis<br/>• 3 nodes cached<br/>• 2 nodes to compute"]

    WF --> ANALYZE
    ANALYZE --> REPORT

    RUN["runWithMemo"]
    INTERP["Interpreter"]

    WF --> RUN
    RUN --> INTERP

    subgraph Execution["Per-Node Execution"]
        CHECK{"Cache hit?"}
        SKIP["Return cached"]
        EXEC["Execute & store"]
    end

    INTERP --> CHECK
    CHECK -->|Yes| SKIP
    CHECK -->|No| EXEC

    style SKIP fill:#c8e6c9
    style EXEC fill:#fff3e0
```

### 4.9 Chunked Memoization for Partitioned Workflows

When workflows use scatter/gather (Section 3), each chunk is memoized independently:

``` haskell
-- Chunk-aware memoization
data ChunkMemoKey = ChunkMemoKey
  { chunkMemoBase  :: MemoKey          -- Base node's memo key
  , chunkMemoIndex :: Natural          -- Chunk index
  , chunkMemoRange :: (Natural, Natural) -- Byte range
  }
  deriving (Eq, Show, Generic)

-- Derive chunk-specific cache key
deriveChunkCacheKey :: ChunkMemoKey -> ContentAddress
deriveChunkCacheKey = computeContentAddress . Aeson.encode

-- Benefits:
-- 1. If only one chunk changes, others are cached
-- 2. Failed chunks can be retried without recomputing siblings
-- 3. Parallel chunk uploads maximize throughput
```

**Example**: Processing a 1-hour audio file in 30-second chunks:

```
Input: audio.wav (1 hour, 120 chunks)

Cache keys generated:
  chunk-0:  hash(separate, hash(audio.wav), 0, 0-30s)
  chunk-1:  hash(separate, hash(audio.wav), 1, 30s-60s)
  ...
  chunk-119: hash(separate, hash(audio.wav), 119, 59m30s-60m)

On re-run with same input:
  → All 120 chunks hit cache
  → Zero GPU computation

On re-run with modified input (first 30s edited):
  → chunk-0: MISS (chunk content changed)
  → chunks 1-119: MISS (whole-file hash changed, invalidating all chunk keys)

  Note: Because the cache key includes hash(audio.wav) - the hash of the
  entire input file - ANY edit to the file invalidates ALL chunk caches.
  This is a trade-off: simpler key derivation vs. finer-grained caching.

On re-run with appended audio (61 minutes):
  → chunks 0-119: Still valid if using byte-range addressing
  → chunks 120-121: New computation needed
```

### 4.10 Summary: Memoization Architecture

``` mermaid
flowchart TD
    subgraph Input["Workflow Input"]
        SPEC["NodeSpec"]
        INPUTS["Input Artifacts"]
    end

    subgraph KeyDerivation["Cache Key Derivation (Pure)"]
        RESOLVE["Resolve input<br/>content addresses"]
        BUILD["Build MemoKey"]
        HASH["Hash to<br/>ContentAddress"]
    end

    subgraph Storage["S3/MinIO Storage"]
        LOOKUP["Check cache-keys/"]
        ARTIFACT["Get artifacts/"]
        STORE["Store result"]
    end

    subgraph Execution["Conditional Execution"]
        HIT["Cache Hit:<br/>Return reference"]
        MISS["Cache Miss:<br/>Execute node"]
    end

    SPEC --> BUILD
    INPUTS --> RESOLVE
    RESOLVE --> BUILD
    BUILD --> HASH
    HASH --> LOOKUP

    LOOKUP -->|Found| HIT
    LOOKUP -->|Not found| MISS
    MISS --> STORE
    STORE --> ARTIFACT
    HIT --> ARTIFACT

    style HIT fill:#c8e6c9
    style MISS fill:#fff3e0
```

| Component | Purpose |
|-----------|---------|
| `ContentAddress` | Hash-based identifier for artifacts |
| `MemoKey` | Deterministic cache key from pure NodeSpec |
| `MemoStore` | S3 adapter for lookup/store operations |
| `StreamingMemoStore` | Efficient handling of large objects |
| Multipart upload | Parallel upload of GB-scale artifacts |
| Chunk memoization | Independent caching of partitioned work |

------------------------------------------------------------------------

## Section 5: Artifact Lifecycle and Retention Policies

This section defines **when** artifacts are deleted from S3, and how the
pure Job type explicitly specifies what to keep. We distinguish between
**results** (final outputs), **intermediates** (temporary), and **memoized
values** (cacheable across runs).

### 5.1 The Core Principle: Pure Inputs → Pure Outputs

Content-addressed storage means: **same inputs always produce same outputs**.
This has a powerful implication:

``` haskell
-- This is ALWAYS safe:
lookupOrCompute :: MemoStore -> MemoKey -> IO a -> IO a
lookupOrCompute store key compute = do
  existing <- memoLookup store (deriveCacheKey key)
  case existing of
    Just ref -> pure ref     -- Found! Skip computation.
    Nothing  -> compute >>= memoStore store key

-- Why? Because pure functions are deterministic.
-- If the MemoKey matches, the result WILL be identical.
-- There's no "stale cache" problem.
```

**Cross-run memoization "just works"**:

``` mermaid
flowchart LR
    subgraph Run1["Run 1 (Monday)"]
        R1A["Fetch"] --> R1B["Process (10 min)"]
        R1B --> R1C["Output"]
        R1B -.->|"Store"| S3
    end

    subgraph Run2["Run 2 (Tuesday, same input)"]
        R2A["Fetch"] --> R2B{"Check S3"}
        R2B -->|"Hit!"| R2C["Output"]
    end

    S3[("S3<br/>Content-Addressed")]
    S3 -.->|"Lookup"| R2B

    style R1B fill:#fff3e0
    style R2B fill:#c8e6c9
```

No explicit "cache warming" or "invalidation" logic needed. The content
address **is** the cache key. Different inputs → different key → cache miss.

### 5.2 Artifact Categories: A Type-Safe Distinction

We define three distinct artifact categories at the **type level**:

``` haskell
-- Phantom type for artifact category
data ArtifactCategory
  = Result        -- Final output, always persisted
  | Intermediate  -- Temporary, deleted after run (unless promoted)
  | Memoized      -- Cached for future runs, subject to retention policy

-- Type-safe artifact references
newtype Artifact (cat :: ArtifactCategory) = Artifact
  { artifactAddress :: ContentAddress
  }
  deriving (Eq, Show)

-- Smart constructors enforce categorization
mkResult :: ContentAddress -> Artifact 'Result
mkResult = Artifact

mkIntermediate :: ContentAddress -> Artifact 'Intermediate
mkIntermediate = Artifact

mkMemoized :: ContentAddress -> Artifact 'Memoized
mkMemoized = Artifact
```

**Why phantom types?** The compiler ensures you can't accidentally treat
an intermediate as a result:

``` haskell
-- This WON'T compile:
saveAsResult :: Artifact 'Result -> IO ()
saveAsResult = ...

intermediate :: Artifact 'Intermediate
intermediate = ...

-- Type error! Can't pass 'Intermediate to function expecting 'Result
saveAsResult intermediate  -- ✗ Compile error
```

### 5.3 Node-Level Retention Annotations

Each node explicitly declares what its output is:

``` haskell
-- Retention policy for a node's output
data OutputRetention
  = RetainAsResult        -- Final output: never auto-delete
  | RetainMemoized TTL    -- Cache for future runs, with TTL
  | Ephemeral             -- Delete as soon as downstream nodes complete
  deriving (Eq, Show, Generic)

-- Time-to-live for memoized artifacts
data TTL
  = TTLForever            -- Keep until explicit GC
  | TTLDays Natural       -- Keep for N days
  | TTLRuns Natural       -- Keep for N subsequent runs
  | TTLUntil UTCTime      -- Keep until specific time
  deriving (Eq, Show, Generic)

-- Extended NodeSpec with retention
-- NOTE: This extends the current implementation in src/StudioMCP/DAG/Types.hs
-- with the nodeRetention field. This represents a proposed enhancement.
data NodeSpec = NodeSpec
  { nodeId         :: NodeId
  , nodeKind       :: NodeKind
  , nodeTool       :: Maybe ToolName
  , nodeInputs     :: [NodeId]
  , nodeOutputType :: OutputType
  , nodeTimeout    :: TimeoutPolicy
  , nodeRetention  :: OutputRetention  -- NEW: explicit retention policy
  }
  deriving (Eq, Show, Generic)
```

**Example workflow with explicit retention**:

``` haskell
audioSeparationJob :: DagSpec
audioSeparationJob = DagSpec
  { dagName = "audio-separation"
  , dagNodes =
      [ NodeSpec
          { nodeId = "fetch"
          , nodeKind = BoundaryNode
          , nodeTool = Just "s3-fetch"
          , nodeRetention = Ephemeral  -- Delete after 'separate' completes
          , ...
          }
      , NodeSpec
          { nodeId = "separate"
          , nodeKind = PureNode
          , nodeTool = Just "demucs"
          , nodeRetention = RetainMemoized (TTLDays 30)  -- Cache for 30 days
          , ...
          }
      , NodeSpec
          { nodeId = "vocals"
          , nodeKind = PureNode
          , nodeTool = Just "extract-stem"
          , nodeRetention = RetainAsResult  -- Final output, keep forever
          , ...
          }
      ]
  }
```

### 5.4 Execution Modes: Controlling Memoization Behavior

The pure Job can be executed in different modes:

``` haskell
-- Execution mode controls memoization behavior
data ExecutionMode
  = MemoizeAll
      -- Default: memoize everything per retention policy
      -- Cross-run caching enabled
      -- Ephemeral artifacts deleted after run

  | MemoizeForRun
      -- Memoize within this run only
      -- All artifacts deleted after run completes
      -- Useful for: one-off jobs, privacy-sensitive data

  | DeleteAsYouGo
      -- Aggressive cleanup: delete intermediates immediately
      -- Only keep what downstream nodes currently need
      -- Useful for: memory/storage constrained environments

  | DryRun
      -- Don't execute, just analyze cache status
      -- Reports what would be computed vs cached
  deriving (Eq, Show, Generic)

-- Interpreter respects execution mode
runWorkflow :: ExecutionMode -> MemoStore -> Ap WorkflowF a -> IO (RunResult a)
runWorkflow mode store workflow = case mode of
  MemoizeAll    -> runWithFullMemo store workflow
  MemoizeForRun -> runWithRunScopedMemo store workflow
  DeleteAsYouGo -> runWithEagerCleanup store workflow
  DryRun        -> analyzeOnly store workflow
```

``` mermaid
flowchart TD
    subgraph MemoizeAll["MemoizeAll (Default)"]
        MA1["Node A"] --> MA2["Node B"] --> MA3["Node C"]
        MA1 -.->|"Store"| S3A[("S3")]
        MA2 -.->|"Store"| S3A
        MA3 -.->|"Store"| S3A
        S3A -.->|"Persists for<br/>future runs"| FUTURE["Future Runs"]
    end

    subgraph DeleteAsYouGo["DeleteAsYouGo"]
        DG1["Node A"] --> DG2["Node B"]
        DG2 --> DG3["Node C"]
        DG1 -.->|"Store"| S3D[("S3")]
        DG2 -->|"A no longer<br/>needed"| DEL1["Delete A"]
        DG3 -->|"B no longer<br/>needed"| DEL2["Delete B"]
    end

    style MA1 fill:#c8e6c9
    style MA2 fill:#c8e6c9
    style MA3 fill:#c8e6c9
    style DEL1 fill:#ffcdd2
    style DEL2 fill:#ffcdd2
```

### 5.5 The RunResult Type: Clear Artifact Accounting

After execution, the result clearly categorizes all artifacts:

``` haskell
-- Complete result of a workflow run
data RunResult a = RunResult
  { runValue         :: a                          -- The computed value
  , runId            :: RunId
  , runArtifacts     :: ArtifactManifest           -- All artifacts produced
  , runCacheStats    :: CacheStatistics            -- Cache hit/miss stats
  , runCleanupPlan   :: CleanupPlan                -- What will be deleted when
  }
  deriving (Eq, Show, Generic)

-- Categorized artifact manifest
data ArtifactManifest = ArtifactManifest
  { manifestResults       :: [Artifact 'Result]      -- Final outputs (kept)
  , manifestMemoized      :: [MemoizedArtifact]      -- Cached (with TTL)
  , manifestIntermediates :: [Artifact 'Intermediate] -- Ephemeral (deleted)
  , manifestTotal         :: StorageStats
  }
  deriving (Eq, Show, Generic)

data MemoizedArtifact = MemoizedArtifact
  { memoArtifact  :: Artifact 'Memoized
  , memoKey       :: MemoKey
  , memoTTL       :: TTL
  , memoExpiresAt :: Maybe UTCTime  -- When it will be eligible for GC
  }
  deriving (Eq, Show, Generic)

-- What's scheduled for deletion
data CleanupPlan = CleanupPlan
  { cleanupImmediate :: [ContentAddress]   -- Delete now (Ephemeral)
  , cleanupScheduled :: [(ContentAddress, UTCTime)]  -- Delete at time
  , cleanupRetained  :: [ContentAddress]   -- Never auto-delete (Results)
  }
  deriving (Eq, Show, Generic)

-- Statistics about what was cached vs computed
data CacheStatistics = CacheStatistics
  { cacheHits        :: Natural
  , cacheMisses      :: Natural
  , cacheHitBytes    :: Natural    -- Bytes we didn't have to compute
  , cacheMissBytes   :: Natural    -- Bytes we computed fresh
  , cacheHitTime     :: NominalDiffTime  -- Estimated time saved
  }
  deriving (Eq, Show, Generic)
```

**Example RunResult**:

``` haskell
-- After running audio separation:
exampleResult :: RunResult Summary
exampleResult = RunResult
  { runValue = Summary { status = Succeeded, ... }
  , runId = RunId "run-2024-01-15-001"
  , runArtifacts = ArtifactManifest
      { manifestResults =
          [ Artifact @'Result addr1   -- vocals.wav
          , Artifact @'Result addr2   -- drums.wav
          , Artifact @'Result addr3   -- bass.wav
          ]
      , manifestMemoized =
          [ MemoizedArtifact
              { memoArtifact = Artifact @'Memoized addr4  -- separated-stems
              , memoTTL = TTLDays 30
              , memoExpiresAt = Just (UTCTime ...)
              }
          ]
      , manifestIntermediates =
          [ Artifact @'Intermediate addr5   -- fetched-audio (deleted)
          ]
      , manifestTotal = StorageStats
          { totalBytes = 524288000  -- 500 MB
          , resultBytes = 471859200  -- 450 MB (kept)
          , memoizedBytes = 52428800  -- 50 MB (cached 30 days)
          , intermediateBytes = 0  -- 0 (already deleted)
          }
      }
  , runCacheStats = CacheStatistics
      { cacheHits = 0
      , cacheMisses = 3
      , cacheHitBytes = 0
      , cacheMissBytes = 524288000
      , cacheHitTime = 0
      }
  , runCleanupPlan = CleanupPlan
      { cleanupImmediate = [addr5]  -- fetch output
      , cleanupScheduled = [(addr4, expiryTime)]  -- memo expires in 30 days
      , cleanupRetained = [addr1, addr2, addr3]  -- results kept forever
      }
  }
```

### 5.6 Delete-As-You-Go: Aggressive Cleanup Mode

For memory/storage constrained environments, delete intermediates as soon
as they're no longer needed:

``` haskell
-- Track which nodes still need each artifact
data LivenessState = LivenessState
  { liveArtifacts   :: Map ContentAddress (Set NodeId)  -- Who needs this?
  , completedNodes  :: Set NodeId
  }

-- Execute with eager cleanup
runWithEagerCleanup :: MemoStore -> Ap WorkflowF a -> IO (RunResult a)
runWithEagerCleanup store workflow = do
  -- Analyze DAG to determine artifact lifetimes
  let lifetimes = analyzeLifetimes workflow

  -- Execute with cleanup callback
  evalStateT (runWithCallback onNodeComplete workflow) initState
  where
    onNodeComplete :: NodeId -> StateT LivenessState IO ()
    onNodeComplete completed = do
      modify' $ \s -> s { completedNodes = Set.insert completed (completedNodes s) }

      -- Check each artifact: is it still needed?
      liveness <- gets liveArtifacts
      forM_ (Map.toList liveness) $ \(addr, neededBy) -> do
        let stillNeeded = neededBy `Set.difference` completedNodes
        if Set.null stillNeeded
          then do
            -- No one needs this anymore, delete it!
            liftIO $ memoDelete store addr
            modify' $ \s -> s { liveArtifacts = Map.delete addr (liveArtifacts s) }
          else
            modify' $ \s -> s { liveArtifacts = Map.insert addr stillNeeded (liveArtifacts s) }

-- Analyze which nodes need which artifacts
analyzeLifetimes :: Ap WorkflowF a -> Map ContentAddress (Set NodeId)
analyzeLifetimes workflow =
  let nodes = collectNodes workflow
      edges = buildDependencyEdges nodes
  in computeLastUse edges
```

``` mermaid
sequenceDiagram
    participant A as Node A
    participant B as Node B (needs A)
    participant C as Node C (needs B)
    participant S3 as S3 Storage

    A->>S3: Store output (addr_a)
    Note over S3: addr_a live, needed by [B]

    A->>B: Complete, trigger B
    B->>S3: Read addr_a
    B->>S3: Store output (addr_b)
    Note over S3: addr_a live []; addr_b live [C]

    B->>S3: Delete addr_a (no longer needed!)
    Note over S3: addr_a DELETED

    B->>C: Complete, trigger C
    C->>S3: Read addr_b
    C->>S3: Store output (addr_c) [Result]

    C->>S3: Delete addr_b (no longer needed!)
    Note over S3: addr_b DELETED, addr_c RETAINED
```

### 5.7 Cross-Run Memoization: It Just Works

Because cache keys are derived from content addresses, cross-run memoization
requires no special logic:

``` haskell
-- The same MemoKey in different runs produces the same cache lookup
-- No "run ID" in the cache key!

data MemoKey = MemoKey
  { memoNodeId     :: NodeId
  , memoTool       :: Maybe ToolName
  , memoInputs     :: [ContentAddress]  -- Content addresses, not run-specific!
  , memoParams     :: Map Text Text
  , memoVersion    :: ToolVersion
  }

-- Monday's run:
-- memoKey = MemoKey "separate" "demucs" [hash("song.wav")] {...} "v4.0"
-- cacheKey = hash(memoKey) = "abc123..."
-- → Cache miss, compute, store at "abc123..."

-- Tuesday's run (same input):
-- memoKey = MemoKey "separate" "demucs" [hash("song.wav")] {...} "v4.0"
-- cacheKey = hash(memoKey) = "abc123..."  -- SAME!
-- → Cache hit, return stored result

-- Tuesday's run (different input):
-- memoKey = MemoKey "separate" "demucs" [hash("other.wav")] {...} "v4.0"
-- cacheKey = hash(memoKey) = "xyz789..."  -- Different!
-- → Cache miss, compute fresh
```

**Automatic invalidation on tool upgrade**:

``` haskell
-- Tool version is part of the key
-- Upgrading demucs from v4.0 to v4.1 automatically invalidates cache

-- Before upgrade:
-- cacheKey = hash(MemoKey ... "v4.0") = "abc123..."

-- After upgrade:
-- cacheKey = hash(MemoKey ... "v4.1") = "def456..."  -- Different!
-- → Cache miss, recompute with new version
```

### 5.8 Retention Policy DSL: Expressive and Composable

For complex retention rules, we provide a composable DSL:

``` haskell
-- Retention policy algebra
data RetentionPolicy
  = KeepForever                        -- Never delete
  | KeepFor TTL                        -- Keep for duration
  | KeepWhile Condition                -- Keep while condition holds
  | KeepUntilGC                        -- Keep until explicit GC
  | DeleteImmediately                  -- Delete after dependents complete
  | RetentionPolicy :||: RetentionPolicy  -- Either policy satisfied
  | RetentionPolicy :&&: RetentionPolicy  -- Both policies must be satisfied
  deriving (Eq, Show, Generic)

infixr 2 :||:
infixr 3 :&&:

-- Conditions for conditional retention
data Condition
  = RunCountBelow Natural       -- Keep if fewer than N runs reference it
  | StorageBelow Natural        -- Keep if total memoized storage < N bytes
  | AgeBelow NominalDiffTime    -- Keep if younger than duration
  | ReferencedByRun RunId       -- Keep if specific run references it
  | Always                       -- Always true
  | Never                        -- Always false
  deriving (Eq, Show, Generic)

-- Examples of complex policies
examplePolicies :: [(Text, RetentionPolicy)]
examplePolicies =
  [ ("Keep results forever", KeepForever)

  , ("Cache for 7 days or until storage exceeds 10GB",
     KeepFor (TTLDays 7) :&&: KeepWhile (StorageBelow (10 * 1024^3)))

  , ("Keep for 30 days OR if referenced by active run",
     KeepFor (TTLDays 30) :||: KeepWhile (RunCountBelow 1 :||: Always))

  , ("Ephemeral: delete as soon as no longer needed",
     DeleteImmediately)
  ]

-- Evaluate policy to decide if artifact should be kept
shouldRetain :: RetentionPolicy -> ArtifactMetadata -> IO Bool
shouldRetain KeepForever _ = pure True
shouldRetain DeleteImmediately _ = pure False
shouldRetain (KeepFor ttl) meta = checkTTL ttl (metaCreatedAt meta)
shouldRetain (KeepWhile cond) meta = evaluateCondition cond meta
shouldRetain (p1 :||: p2) meta = (||) <$> shouldRetain p1 meta <*> shouldRetain p2 meta
shouldRetain (p1 :&&: p2) meta = (&&) <$> shouldRetain p1 meta <*> shouldRetain p2 meta
```

### 5.9 Garbage Collection: Principled Cleanup

GC respects retention policies and only deletes eligible artifacts:

``` haskell
-- Garbage collection configuration
data GCConfig = GCConfig
  { gcDryRun          :: Bool               -- Just report, don't delete
  , gcVerbose         :: Bool               -- Log each deletion
  , gcProtectRuns     :: [RunId]            -- Don't delete artifacts from these runs
  , gcProtectRecent   :: NominalDiffTime    -- Don't delete artifacts newer than this
  , gcMaxDelete       :: Maybe Natural      -- Limit deletions per GC run
  }
  deriving (Eq, Show, Generic)

-- GC result
data GCResult = GCResult
  { gcDeleted     :: [ContentAddress]
  , gcRetained    :: [ContentAddress]
  , gcProtected   :: [ContentAddress]   -- Would delete but protected
  , gcBytesFreed  :: Natural
  , gcErrors      :: [GCError]
  }
  deriving (Eq, Show, Generic)

-- Run garbage collection
runGC :: GCConfig -> MemoStore -> IO GCResult
runGC config store = do
  -- 1. List all artifacts with metadata
  artifacts <- listAllArtifacts store

  -- 2. Evaluate retention policy for each
  decisions <- forM artifacts $ \(addr, meta) -> do
    shouldKeep <- shouldRetain (metaRetention meta) meta
    let protected = isProtected config meta
    pure (addr, meta, shouldKeep, protected)

  -- 3. Delete eligible artifacts
  let toDelete = [ addr | (addr, _, False, False) <- decisions ]
      limited = maybe toDelete (`take` toDelete) (gcMaxDelete config)

  deleted <- if gcDryRun config
    then pure []
    else mapM (deleteArtifact store) limited

  pure GCResult
    { gcDeleted = deleted
    , gcRetained = [ addr | (addr, _, True, _) <- decisions ]
    , gcProtected = [ addr | (addr, _, False, True) <- decisions ]
    , gcBytesFreed = sum [ metaSize meta | (_, meta, False, False) <- decisions ]
    , gcErrors = []
    }
```

``` mermaid
flowchart TD
    START["GC Start"] --> LIST["List all artifacts<br/>with metadata"]
    LIST --> EVAL["Evaluate retention<br/>policy for each"]

    EVAL --> DECIDE{"Should retain?"}

    DECIDE -->|"KeepForever"| RETAIN["Retain"]
    DECIDE -->|"TTL not expired"| RETAIN
    DECIDE -->|"Referenced by active run"| RETAIN
    DECIDE -->|"TTL expired"| CHECK_PROT{"Protected?"}

    CHECK_PROT -->|"Yes (recent, protected run)"| PROTECTED["Protected<br/>(skip this GC)"]
    CHECK_PROT -->|"No"| DELETE["Delete"]

    RETAIN --> RESULT["GC Result"]
    PROTECTED --> RESULT
    DELETE --> RESULT

    style RETAIN fill:#c8e6c9
    style PROTECTED fill:#fff3e0
    style DELETE fill:#ffcdd2
```

### 5.10 Putting It All Together: Complete Example

``` haskell
-- Define a job with explicit retention policies
audioProcessingJob :: Job
audioProcessingJob = Job
  { jobId = JobId "audio-process-001"
  , jobWorkflow = workflow
  , jobDefaultRetention = RetainMemoized (TTLDays 7)  -- Default for nodes
  , jobExecutionMode = MemoizeAll                      -- Use cross-run cache
  }
  where
    workflow = dagSpec
      [ node "fetch"
          [ nodeTool "s3-fetch"
          , nodeRetention DeleteImmediately  -- Don't cache raw input
          ]
      , node "normalize"
          [ nodeTool "ffmpeg"
          , nodeInputs ["fetch"]
          , nodeRetention (RetainMemoized (TTLDays 30))  -- Cache normalization
          ]
      , node "separate"
          [ nodeTool "demucs"
          , nodeInputs ["normalize"]
          , nodeRetention (RetainMemoized TTLForever)  -- Expensive! Cache forever
          ]
      , node "vocals"
          [ nodeTool "extract-stem"
          , nodeInputs ["separate"]
          , nodeRetention RetainAsResult  -- Final output
          ]
      , node "instrumental"
          [ nodeTool "extract-stem"
          , nodeInputs ["separate"]
          , nodeRetention RetainAsResult  -- Final output
          ]
      ]

-- Run the job
main :: IO ()
main = do
  store <- connectMemoStore s3Config

  -- First run: everything computes fresh
  result1 <- runJob MemoizeAll store audioProcessingJob
  print $ runCacheStats result1
  -- CacheStatistics { cacheHits = 0, cacheMisses = 5, ... }

  -- Second run (same input): cache hits!
  result2 <- runJob MemoizeAll store audioProcessingJob
  print $ runCacheStats result2
  -- CacheStatistics { cacheHits = 4, cacheMisses = 1, ... }
  --                               ^ fetch still runs (DeleteImmediately)

  -- Check what's in S3
  print $ runArtifacts result2
  -- ArtifactManifest
  --   { manifestResults = [vocals.wav, instrumental.wav]  -- Kept forever
  --   , manifestMemoized = [normalize, separate]          -- Cached with TTL
  --   , manifestIntermediates = []                        -- Already deleted
  --   }

  -- Run GC to clean expired artifacts
  gcResult <- runGC defaultGCConfig store
  print gcResult
  -- GCResult { gcDeleted = [...], gcRetained = [...], ... }
```

### 5.11 Summary: Artifact Lifecycle

``` mermaid
stateDiagram-v2
    [*] --> Computing: Node executes

    Computing --> Storing: Computation complete
    Storing --> Stored: Upload to S3

    Stored --> Result: RetainAsResult
    Stored --> Memoized: RetainMemoized
    Stored --> Ephemeral: Ephemeral/DeleteImmediately

    Result --> [*]: Never deleted

    Memoized --> GCEligible: TTL expires
    GCEligible --> Deleted: GC runs
    GCEligible --> Memoized: GC skips (protected)

    Ephemeral --> Deleted: Dependents complete

    Deleted --> [*]
```

| Category | When Deleted | Cross-Run Cache | Use Case |
|----------|--------------|-----------------|----------|
| `Result` | Never (explicit delete only) | N/A | Final outputs |
| `Memoized` | TTL expires + GC | Yes | Expensive computations |
| `Ephemeral` | After dependents complete | No | Large intermediates |

| Execution Mode | Behavior | Use Case |
|----------------|----------|----------|
| `MemoizeAll` | Full cross-run caching | Production, repeated jobs |
| `MemoizeForRun` | Cache within run only | One-off jobs, privacy |
| `DeleteAsYouGo` | Aggressive cleanup | Storage constrained |
| `DryRun` | Analysis only | Cost estimation |

------------------------------------------------------------------------

## Section 6: Resource Estimation from Pure Representation

This section describes how the orchestrator estimates resources needed
from the pure `DagSpec` representation.

### 6.1 Resource Requirement Types

``` haskell
-- Core resource requirements
data ResourceRequirements = ResourceRequirements
  { reqCpuMillicores :: Natural        -- CPU in millicores (e.g., 500 = 0.5 CPU)
  , reqMemoryMiB     :: Natural        -- Memory in MiB
  , reqGpuCount      :: Maybe Natural  -- Optional GPU count
  , reqGpuType       :: Maybe GpuType  -- NVIDIA T4, A10G, etc.
  , reqStorageGiB    :: Natural        -- Ephemeral storage estimate
  , reqNetworkMbps   :: Maybe Natural  -- Network bandwidth requirement
  }
  deriving (Eq, Show, Generic)

data GpuType
  = NvidiaT4
  | NvidiaA10G
  | NvidiaA100
  | NvidiaL4
  deriving (Eq, Show, Ord, Generic)

-- Duration estimate with confidence bounds
data DurationEstimate = DurationEstimate
  { durationMinSeconds :: Natural      -- Optimistic bound
  , durationP50Seconds :: Natural      -- Median expectation
  , durationP95Seconds :: Natural      -- Pessimistic bound
  }
  deriving (Eq, Show, Generic)

-- Per-node resource estimate
data NodeResourceEstimate = NodeResourceEstimate
  { estimateNodeId     :: NodeId
  , estimateTool       :: Maybe Text
  , estimateResources  :: ResourceRequirements
  , estimateDuration   :: DurationEstimate
  , estimateConfidence :: ConfidenceLevel
  }
  deriving (Eq, Show, Generic)

data ConfidenceLevel
  = HighConfidence    -- Historical data available
  | MediumConfidence  -- Model-based estimate
  | LowConfidence     -- Default fallback
  deriving (Eq, Show, Ord, Generic)
```

### 6.2 Tool Profiles

Tools are registered with resource profiles that scale based on input size:

``` haskell
-- Tool resource profile with scaling factors
data ToolProfile = ToolProfile
  { profileToolName        :: ToolName
  , profileBaseResources   :: ResourceRequirements
  , profileScalingFactor   :: ScalingFactor
  , profileGpuRequired     :: Bool
  , profileSupportsChunking :: Bool
  }
  deriving (Eq, Show, Generic)

data ScalingFactor = ScalingFactor
  { scaleCpuPerMiB    :: Double   -- CPU millicores per MiB input
  , scaleMemoryPerMiB :: Double   -- Memory MiB per MiB input
  , scaleTimePerMiB   :: Double   -- Seconds per MiB input
  }
  deriving (Eq, Show, Generic)

-- Example: Demucs profile
demucsProfile :: ToolProfile
demucsProfile = ToolProfile
  { profileToolName = ToolName "demucs"
  , profileBaseResources = ResourceRequirements
      { reqCpuMillicores = 2000
      , reqMemoryMiB = 4096
      , reqGpuCount = Just 1
      , reqGpuType = Just NvidiaT4
      , reqStorageGiB = 20
      , reqNetworkMbps = Nothing
      }
  , profileScalingFactor = ScalingFactor
      { scaleCpuPerMiB = 2.0
      , scaleMemoryPerMiB = 1.5
      , scaleTimePerMiB = 0.5
      }
  , profileGpuRequired = True
  , profileSupportsChunking = True
  }

-- Example: FFmpeg profile
ffmpegProfile :: ToolProfile
ffmpegProfile = ToolProfile
  { profileToolName = ToolName "ffmpeg"
  , profileBaseResources = ResourceRequirements
      { reqCpuMillicores = 500
      , reqMemoryMiB = 512
      , reqGpuCount = Nothing
      , reqGpuType = Nothing
      , reqStorageGiB = 10
      , reqNetworkMbps = Nothing
      }
  , profileScalingFactor = ScalingFactor
      { scaleCpuPerMiB = 0.5
      , scaleMemoryPerMiB = 0.2
      , scaleTimePerMiB = 0.1
      }
  , profileGpuRequired = False
  , profileSupportsChunking = True
  }
```

### 6.3 Resource Estimation Flow

``` mermaid
flowchart TD
    DAG["DagSpec"] --> TOOLS["Extract Tool References"]
    TOOLS --> LOOKUP["Lookup ToolProfile"]

    subgraph Profiles["Tool Registry"]
        DEMUCS["Demucs Profile<br/>GPU: 1, CPU: 2000m, Mem: 4Gi"]
        FFMPEG["FFmpeg Profile<br/>GPU: 0, CPU: 500m, Mem: 512Mi"]
    end

    LOOKUP --> Profiles
    Profiles --> SCALE["Apply Scaling Factor<br/>Input Size → Resources"]
    SCALE --> EST["NodeResourceEstimate"]
    EST --> AGG["Aggregate Peak Parallelism"]
    AGG --> FINAL["DagResourceEstimate"]

    style FINAL fill:#c8e6c9
```

### 6.4 Estimation Algorithm

``` haskell
-- Estimate resources for entire DAG
estimateDagResources
  :: Map ToolName ToolProfile
  -> DagSpec
  -> IO (Either FailureDetail DagResourceEstimate)
estimateDagResources profiles dagSpec = do
  -- Estimate each node
  nodeEstimates <- mapM (estimateNode profiles) (dagNodes dagSpec)

  -- Compute parallel batches
  let batches = scheduleParallelBatches dagSpec
      peakParallel = maximum (map length batches)

  -- Peak resources = sum of max concurrent batch
  let peakBatch = maximumBy (comparing aggregateBatch) batches
      peakResources = aggregateParallelResources peakBatch

  -- Critical path for wall-clock estimate
  let criticalPath = computeCriticalPath dagSpec nodeEstimates
      wallClock = sumDurations criticalPath

  pure $ Right DagResourceEstimate
    { estimateNodes = nodeEstimates
    , estimatePeakParallel = peakParallel
    , estimatePeakResources = peakResources
    , estimateCriticalPath = map estimateNodeId criticalPath
    , estimateWallClock = wallClock
    }

-- Aggregate resources for parallel execution
aggregateParallelResources :: [NodeResourceEstimate] -> ResourceRequirements
aggregateParallelResources estimates = ResourceRequirements
  { reqCpuMillicores = sum (map (reqCpuMillicores . estimateResources) estimates)
  , reqMemoryMiB = sum (map (reqMemoryMiB . estimateResources) estimates)
  , reqGpuCount = sumMaybes (map (reqGpuCount . estimateResources) estimates)
  , reqGpuType = listToMaybe $ mapMaybe (reqGpuType . estimateResources) estimates
  , reqStorageGiB = sum (map (reqStorageGiB . estimateResources) estimates)
  , reqNetworkMbps = sumMaybes (map (reqNetworkMbps . estimateResources) estimates)
  }
```

### 6.5 Worker Pool Sizing

``` mermaid
flowchart LR
    subgraph Analysis
        PAR["Peak Parallelism: 8"]
        RES["Resource Buckets"]
    end

    PAR --> MIN["Min Workers: 2"]
    PAR --> MAX["Max Workers: 16"]
    RES --> POOLS["Instance Pools"]

    subgraph Pools["Recommended Pools"]
        GPU["GPU Pool<br/>g4dn.xlarge × 4"]
        CPU["CPU Pool<br/>c5.large × 8"]
    end

    POOLS --> GPU
    POOLS --> CPU

    style GPU fill:#fff3e0
    style CPU fill:#e3f2fd
```

``` haskell
-- Worker pool sizing analysis
data PoolSizingAnalysis = PoolSizingAnalysis
  { analysisMaxParallelism   :: Natural
  , analysisResourceBuckets  :: [ResourceBucket]
  , analysisRecommendedPools :: [RecommendedPool]
  , analysisHpaConfiguration :: HpaConfig
  }
  deriving (Eq, Show, Generic)

data RecommendedPool = RecommendedPool
  { poolBucket       :: ResourceBucket
  , poolInstanceType :: InstanceType
  , poolMinWorkers   :: Natural
  , poolMaxWorkers   :: Natural
  , poolSpotMix      :: Percentage  -- % spot vs on-demand
  }
  deriving (Eq, Show, Generic)

-- Compute optimal pool sizing from DAG structure
computePoolSizing
  :: DagResourceEstimate
  -> SpotPricingAdapter
  -> IO PoolSizingAnalysis
```

------------------------------------------------------------------------

## Section 7: Cloud-Agnostic Spot Pricing Coordination

This section documents a cloud-agnostic interface for preemptible/spot
instance provisioning.

### 7.1 Spot Pricing Provider Interface

``` haskell
-- Cloud-agnostic spot pricing interface
class SpotPricingProvider p where
  queryPrices     :: p -> ResourceRequirements -> IO (Either ProviderError [PriceInfo])
  queryCapacity   :: p -> [InstanceSpec] -> IO (Either ProviderError (Map InstanceSpec CapacityScore))
  selectOptimal   :: p -> ResourceRequirements -> SpotStrategy -> IO (Either ProviderError InstanceSelection)
  requestCapacity :: p -> CapacityRequest -> IO (Either ProviderError CapacityGrant)

-- Provider implementations
data AwsSpotProvider = AwsSpotProvider
  { awsRegion :: Region
  , awsCredentials :: Credentials
  }

data GcpPreemptibleProvider = GcpPreemptibleProvider
  { gcpProject :: ProjectId
  , gcpZone :: Zone
  }

data AzureSpotProvider = AzureSpotProvider
  { azureSubscription :: SubscriptionId
  , azureResourceGroup :: ResourceGroup
  }
```

### 7.2 Pricing and Strategy Types

``` haskell
-- Unified price info across providers
data PriceInfo = PriceInfo
  { priceInstanceSpec      :: InstanceSpec
  , pricePerHour           :: Money
  , priceAvailabilityZone  :: Text
  , priceCapacityScore     :: Maybe CapacityScore  -- 1-10, higher = more available
  , priceInterruptionRate  :: Maybe Percentage     -- Historical interruption probability
  }
  deriving (Eq, Show, Generic)

-- Capacity score from cloud APIs (1-10, higher = more available)
newtype CapacityScore = CapacityScore { unCapacityScore :: Natural }
  deriving (Eq, Ord, Show, Num)

-- Instance selection strategies
data SpotStrategy
  = LowestPrice                    -- Minimize cost, accept interruption risk
  | CapacityOptimized              -- Minimize interruption probability
  | BalancedCostCapacity           -- Trade-off between cost and availability
  | Diversified Natural            -- Spread across N instance pools
  deriving (Eq, Show, Generic)

-- Result of instance selection
data InstanceSelection = InstanceSelection
  { selectedInstance     :: InstanceType
  , selectedAZ           :: AvailabilityZone
  , selectedPricePerHour :: Money
  , selectedCapacity     :: CapacityScore
  , fallbackOnDemand     :: InstanceType
  , fallbackPricePerHour :: Money
  }
  deriving (Eq, Show, Generic)
```

### 7.3 Cloud-Agnostic Spot Flow

``` mermaid
flowchart TD
    REQ["ResourceRequirements"] --> PROVIDER{"Provider Selection"}

    PROVIDER --> AWS["AwsSpotProvider"]
    PROVIDER --> GCP["GcpPreemptibleProvider"]
    PROVIDER --> AZURE["AzureSpotProvider"]

    AWS --> QUERY["queryPrices"]
    GCP --> QUERY
    AZURE --> QUERY

    QUERY --> PRICES["PriceInfo List"]
    PRICES --> STRATEGY{"SpotStrategy"}

    STRATEGY --> |"LowestPrice"| SELECT1["Select Cheapest"]
    STRATEGY --> |"CapacityOptimized"| SELECT2["Select Most Available"]
    STRATEGY --> |"Diversified"| SELECT3["Spread Across Pools"]

    SELECT1 & SELECT2 & SELECT3 --> GRANT["CapacityGrant"]

    style AWS fill:#ff9800
    style GCP fill:#4285f4
    style AZURE fill:#0078d4
```

### 7.4 Preemption Handling

``` haskell
-- Cloud-agnostic preemption notification
data PreemptionNotice = PreemptionNotice
  { noticeInstanceId      :: Text
  , noticeAction          :: PreemptionAction
  , noticeWarningTime     :: UTCTime
  , noticeTerminationTime :: UTCTime
  }
  deriving (Eq, Show, Generic)

data PreemptionAction
  = Terminate    -- Instance will be terminated
  | Stop         -- Instance will be stopped (can restart)
  | Hibernate    -- Instance will be hibernated
  deriving (Eq, Show, Generic)

-- Handler interface
class PreemptionHandler h where
  onPreemptionWarning :: h -> PreemptionNotice -> [JobId] -> IO ()
  checkpointJobs      :: h -> [JobId] -> IO [CheckpointRef]
  migrateJobs         :: h -> [JobId] -> InstanceSelection -> IO [JobId]

-- Checkpoint for resumable execution
data Checkpoint = Checkpoint
  { checkpointJobId        :: JobId
  , checkpointNodeId       :: NodeId
  , checkpointTimestamp    :: UTCTime
  , checkpointProgress     :: Natural
  , checkpointStateRef     :: ObjectKey
  , checkpointPartialOutput :: Maybe ObjectKey
  }
  deriving (Eq, Show, Generic)
```

### 7.5 Preemption Sequence

``` mermaid
sequenceDiagram
    participant Cloud as Cloud Provider
    participant Handler as PreemptionHandler
    participant Worker as Worker Pod
    participant Storage as MinIO

    Cloud->>Handler: PreemptionNotice (2 min warning)
    Handler->>Worker: Initiate Checkpoint
    Worker->>Storage: Save Checkpoint State
    Storage-->>Worker: CheckpointRef
    Worker-->>Handler: Checkpoint Complete

    Handler->>Handler: Select New Instance
    Handler->>Cloud: Request Replacement Capacity
    Cloud-->>Handler: New Instance Ready

    Handler->>Worker: Migrate Job
    Worker->>Storage: Resume from CheckpointRef
    Worker-->>Handler: Execution Resumed
```

### 7.6 Cost Estimation

``` haskell
-- Cost estimation for DAG execution
data CostEstimate = CostEstimate
  { estimatedSpotCost      :: Money
  , estimatedOnDemandCost  :: Money
  , estimatedStorageCost   :: Money
  , estimatedDataTransfer  :: Money
  , totalEstimate          :: Money
  , confidenceInterval     :: (Money, Money)  -- 90% CI
  }
  deriving (Eq, Show, Generic)

-- Budget enforcement
data BudgetPolicy = BudgetPolicy
  { budgetMaxPerRun          :: Maybe Money
  , budgetMaxPerHour         :: Maybe Money
  , budgetAlertThreshold     :: Maybe Percentage
  , budgetFallbackToOnDemand :: Bool
  }
  deriving (Eq, Show, Generic)

-- Estimate cost for DAG
estimateDagCost
  :: SpotPricingProvider p
  => p
  -> DagResourceEstimate
  -> SpotStrategy
  -> IO (Either ProviderError CostEstimate)
```

------------------------------------------------------------------------

## Section 8: Parallel Scheduler Extension

This section documents the extension to the existing scheduler for
parallel batch emission.

### 8.1 Scheduler Modes

``` haskell
data SchedulerMode
  = TopologicalSequential    -- Existing mode: [a, b, c, d]
  | TopologicalParallel      -- NEW: [[a], [b, c], [d]]
  | PartitionedParallel      -- NEW: with scatter/gather expansion
  deriving (Eq, Show, Generic)

-- Current: flattens to list
scheduleTopologically :: DagSpec -> Either FailureDetail [NodeSpec]

-- Proposed: preserves parallel batches
scheduleParallelBatches :: DagSpec -> Either FailureDetail [[NodeSpec]]
```

### 8.2 Parallel Batch Output

``` mermaid
flowchart TD
    subgraph batches["scheduleParallelBatches Output"]
        B1["Batch 1: [Fetch]"]
        B2["Batch 2: [Scatter]"]
        B3["Batch 3: [Worker0, Worker1, Worker2, WorkerN]"]
        B4["Batch 4: [Gather]"]
        B5["Batch 5: [Persist]"]
        B6["Batch 6: [Summary]"]
    end

    B1 --> B2
    B2 --> B3
    B3 --> B4
    B4 --> B5
    B5 --> B6

    style B3 fill:#c8e6c9
```

### 8.3 Scheduling Algorithm

``` haskell
-- Schedule DAG into parallel batches using Kahn's algorithm variant
scheduleParallelBatches :: DagSpec -> Either FailureDetail [[NodeSpec]]
scheduleParallelBatches dagSpec = do
  -- Validate DAG structure
  validateDag dagSpec

  -- Build adjacency and in-degree maps
  let adjMap = buildAdjacencyMap dagSpec
      inDegree = buildInDegreeMap dagSpec

  -- Kahn's algorithm producing batches instead of linear order
  go inDegree [] (nodesWithZeroInDegree inDegree)
  where
    go :: Map NodeId Int -> [[NodeSpec]] -> [NodeSpec] -> Either FailureDetail [[NodeSpec]]
    go degrees batches []
      | all (== 0) (Map.elems degrees) = Right (reverse batches)
      | otherwise = Left (cycleDetected dagSpec)
    go degrees batches currentBatch = do
      -- Current batch is all nodes with zero in-degree
      let batch = sortBy (comparing (unNodeId . nodeId)) currentBatch
          newDegrees = foldl' decrementSuccessors degrees batch
          nextBatch = nodesWithZeroInDegree newDegrees
      go newDegrees (batch : batches) nextBatch
```

### 8.4 Execution Timeline Comparison

``` mermaid
gantt
    title Parallel vs Sequential Execution
    dateFormat s
    axisFormat %S

    section Sequential
    Fetch           :seq1, 0, 10s
    Demucs Chunk 0  :seq2, after seq1, 30s
    Demucs Chunk 1  :seq3, after seq2, 30s
    Demucs Chunk 2  :seq4, after seq3, 30s
    Persist         :seq5, after seq4, 10s

    section Parallel
    Fetch           :par1, 0, 10s
    Demucs Chunk 0  :par2, after par1, 30s
    Demucs Chunk 1  :par3, after par1, 30s
    Demucs Chunk 2  :par4, after par1, 30s
    Gather          :par5, after par2 par3 par4, 5s
    Persist         :par6, after par5, 10s
```

### 8.5 Guarantees

Per the existing `parallel_scheduling.md` architectural contract:

- **Dependency Ordering**: Only nodes with completed dependencies become runnable
- **Deterministic Order**: Stable tie-breaker via normalized `NodeId` for reproducibility
- **Failure Propagation**: Failed nodes prevent downstream execution
- **Summary Barrier**: Summary nodes remain terminal aggregation points
- **No Speculation**: No execution of nodes with unresolved dependencies

### 8.6 Integration with Existing Scheduler

``` haskell
-- Extended scheduler interface
data SchedulerConfig = SchedulerConfig
  { schedulerMode        :: SchedulerMode
  , schedulerPartitions  :: Map NodeId PartitionSpec
  , schedulerGatherSpecs :: Map NodeId GatherSpec
  }
  deriving (Eq, Show, Generic)

-- Schedule with partition expansion
scheduleWithPartitioning
  :: SchedulerConfig
  -> DagSpec
  -> Either FailureDetail ScheduledDag

data ScheduledDag = ScheduledDag
  { scheduledLayers   :: [[NodeSpec]]
  , scheduledExpanded :: Map NodeId ExplodedSubDag
  , scheduledOrder    :: [NodeId]  -- Deterministic total order for lineage
  }
  deriving (Eq, Show, Generic)
```

------------------------------------------------------------------------

## Cross-References

- [Architecture Overview](../architecture/overview.md)
- [Parallel Scheduling](../architecture/parallel_scheduling.md)
- [Server Mode](../architecture/server_mode.md)
- [DAG Types](../../src/StudioMCP/DAG/Types.hs)
- [DAG Scheduler](../../src/StudioMCP/DAG/Scheduler.hs)
- [DAG Executor](../../src/StudioMCP/DAG/Executor.hs)

------------------------------------------------------------------------

## Conclusion

The **pure Job type** acts as a universal workflow language, while the
orchestrator interprets it into real-world distributed execution.

The category-theoretic foundations—Free Applicatives, natural transformations,
and the Applicative/Monad distinction—provide a principled way to express
parallelizable computation at the type level. The lifting pipeline transforms
these pure representations through validation, resource estimation, chunking,
provisioning, and scheduling into actual Kubernetes jobs.

Key architectural benefits:

- **Pure functional core**: Workflows are deterministic, testable values
- **Parallelism discovery**: Type structure reveals independence statically
- **Multiple backends**: Same DSL interprets to sequential, parallel, or distributed
- **Cost optimization**: Resource estimation enables spot pricing coordination
- **Graceful degradation**: Preemption handling with checkpointing and fallback

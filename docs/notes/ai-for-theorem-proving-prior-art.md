

# **From Intuition to Implementation: A Strategic Report on Leveraging AI for Automated Theorem Proving in Agda, Drawing from DeepMind's Advances with Lean**

## **Part I: The State of the Art in AI-Driven Mathematical Discovery**

The application of artificial intelligence to the abstract and rigorous domain of mathematics has entered a new era, moving from niche experiments to systems capable of competing at the highest levels of human reasoning. Spearheading this charge is Google DeepMind, whose recent breakthroughs have not only solved long-standing open problems but have also provided a portfolio of architectural blueprints for how neural models and symbolic systems can collaborate. This analysis dissects these landmark achievements to extract the core strategies and technical innovations that underpin their success, laying the groundwork for adapting these methods to new formal systems.

### **Section 1: DeepMind's Foray into Formal Mathematics**

DeepMind's recent contributions to mathematics are characterized by a sophisticated interplay between the pattern-matching prowess of large language models (LLMs) and the logical rigor of symbolic engines. By examining their key projects—AlphaGeometry, FunSearch, and the lineage leading to Gemini Deep Think—we can identify a set of powerful, complementary strategies for tackling mathematical discovery.

#### **1.1 AlphaGeometry: Cracking Olympiad Geometry**

AlphaGeometry represents a significant milestone in AI's ability to reason logically, demonstrating performance on par with human gold medalists in International Mathematical Olympiad (IMO) geometry problems.1 Its success is rooted in a meticulously designed neuro-symbolic architecture and, crucially, a novel solution to the problem of data scarcity in formal mathematics.

**Core Architecture:** The system embodies a neuro-symbolic approach, analogized to the "thinking, fast and slow" model of human cognition.1 It comprises two distinct but collaborative components:

* **The Neural Language Model (System 1):** This component functions as an "intuition pump." It is a specialized LLM, a fine-tuned version of Gemini in its later iteration, trained to navigate the infinite space of possible geometric constructions.3 Given a geometry problem's state, the language model does not attempt to solve the proof directly but instead predicts potentially useful auxiliary constructions, such as adding a specific point or line, that could lead to a solution.1 This provides fast, pattern-based, intuitive guidance.  
* **The Symbolic Deduction Engine (System 2):** This component, known as the Deductive Database Arithmetic Reasoner (DDAR), is a rule-bound engine grounded in formal logic.3 It takes the high-potential suggestions from the language model and rigorously applies classical geometry rules to deduce new facts about the diagram. This process is deliberate, logically sound, and produces explainable proof steps, ensuring the correctness of the final solution.1

**The Synthetic Data Generation Pipeline:** Perhaps the most critical innovation of AlphaGeometry was its method for overcoming the data bottleneck. High-quality formalized proofs at the Olympiad level are exceedingly rare, making it impossible to train a powerful supervised model on human-generated data alone. DeepMind's solution was to create a vast synthetic dataset of 100 million unique examples.1 This process began with a set of fundamental theorems and premises and algorithmically applied deduction rules in a forward-chaining manner. This generated an enormous graph of geometric facts and their proofs. By working backward from these facts, the system could generate a massive number of problem-solution pairs, effectively creating its own training curriculum. This synthetic data was then used to train the language model to recognize which constructions are most likely to be fruitful, a task it could not have learned from the sparse human-written corpus.

**Performance and Evolution:** The system's performance dramatically outstripped previous state-of-the-art methods like "Wu's method," which solved only 10 of 30 benchmark problems.1 The first version of AlphaGeometry solved 25 of 30 problems from the IMO-AG-30 benchmark, approaching the average human gold medalist score of 25.9.1 The successor, AlphaGeometry 2, further improved on this, leveraging the more powerful Gemini model, enhanced search algorithms, and an expanded formal language to cover a wider range of problem types, ultimately solving 84% of all IMO geometry problems from 2000-2024.4 The code and model for AlphaGeometry have been open-sourced, providing a valuable resource for the research community.1

The success of AlphaGeometry was not primarily due to a revolutionary neural architecture but rather a breakthrough in data engineering. The scarcity of formalized mathematical proofs is a fundamental obstacle for any supervised learning approach. Instead of relying on existing data, the project reframed the problem to one of data generation. By algorithmically exploring the space of provable theorems from a set of axioms, a curriculum was created to teach the neural network the "shape" of valid geometric reasoning. This demonstrates that for any project aiming for similar performance in a formal system like Agda, which also has a limited corpus of formalized proofs compared to natural language text, the development of a synthetic data generation pipeline is not an optional extra but a central and necessary component.

#### **1.2 FunSearch: Discovering Novel Mathematics through Evolutionary Search**

FunSearch introduces a different paradigm, shifting the focus from finding proofs directly to discovering the underlying algorithms or functions that solve mathematical problems. It successfully combines the creative power of LLMs with the directed pressure of evolutionary search to make novel discoveries in open problems.7

**Core Architecture:** FunSearch operates through an evolutionary loop that pairs a pre-trained LLM, such as Google's PaLM 2, with an automated evaluator.7

* **The Search Space:** The system's key distinction is that it searches for *functions* written in computer code, not for declarative proofs.7 A user provides the problem specification, which includes an evaluation metric (a function to score solutions) and a "seed" program to initialize the search.7  
* **The Evolutionary Loop:** FunSearch maintains a "Program Database" of the highest-scoring, correct programs found so far. In each iteration, it samples programs from this database and uses them as few-shot examples in a prompt to an LLM. The LLM's task is to generate creative variations or "mutations" of these programs. These new programs are then automatically run and scored by the evaluator. The best-performing new programs are added back to the database, creating a self-improving loop that iteratively discovers better solutions.7

**Key Discoveries and The Interpretability Advantage:** FunSearch has demonstrated its power in both pure and applied mathematics.

* It made a genuine discovery for the **Cap Set Problem**, a long-standing open problem in combinatorics. The system found larger cap sets than were previously known by discovering a novel construction method expressed as a computer program.7 This shows its capacity to generate knowledge beyond the existing human frontier.  
* For the practical **Bin-Packing Problem**, FunSearch discovered more effective algorithms than established heuristics, showcasing its utility for real-world optimization challenges.7

A crucial feature of FunSearch is that its output is not an opaque answer but a human-readable program that transparently reveals *how* the solution is constructed.7 This allows researchers to understand the novel strategy, gain deeper conceptual insights, and verify the approach. The system is designed to favor solutions with low Kolmogorov complexity—that is, short, elegant programs that are easier for humans to comprehend.7

This approach offers a powerful alternative to direct proof search. Navigating a formal proof space can be exceptionally complex. By reframing the task as "find the best program f according to evaluator e," FunSearch leverages an LLM's proven strength in code generation and modification. The evolutionary framework provides the necessary search pressure to guide this creativity towards a desired goal. This suggests a compelling strategy for Agda: instead of using an AI to fill a proof hole with a term, a FunSearch-like method could be used to evolve Agda *metaprograms* (tactics). The objective would be to discover the most effective tactic for a given class of theorems, with the evaluator scoring tactics based on their success rate on a benchmark set.

#### **1.3 AlphaProof and Gemini Deep Think: Towards IMO Gold and General Mathematical Reasoning**

The trajectory of DeepMind's work shows a clear progression towards more general and powerful mathematical reasoning, culminating in a system that achieved a gold-medal standard at the IMO. This evolution involved grounding the AI's reasoning in a formal proof assistant and developing more sophisticated, human-like reasoning strategies.

**AlphaProof: The Lean Verifier:** A key step in this journey was AlphaProof, a system that achieved a silver medal level at the IMO.9 Its defining feature was the use of the

**Lean proof assistant** as its symbolic verifier. When presented with a problem, AlphaProof would generate potential solution candidates and then attempt to formally prove or disprove them by searching over possible proof steps *within the Lean environment*.9 Any proof that was successfully verified by Lean's trusted kernel was then used as positive feedback to reinforce the language model, creating a tight loop between generation and formal verification.

**Gemini with Deep Think: Achieving the Gold Standard:** The system that officially reached the IMO gold-medal standard is an advanced version of the Gemini model equipped with a reasoning architecture called "Deep Think".11 This system represents a significant leap in capability.

* **"Parallel Thinking":** This is more than just a faster or wider search. Deep Think is designed to explore multiple, diverse lines of reasoning simultaneously. It can generate different hypotheses, weigh potential solutions, and refine or combine these distinct thought processes over an extended period before producing a final answer.13 This mirrors the workflow of a human mathematician who explores various angles and strategies before committing to a single line of proof.  
* **Reinforcement Learning and Tool Use:** The system employs novel reinforcement learning techniques that explicitly encourage the model to utilize these extended, parallel reasoning paths, thereby improving its problem-solving intuition over time.13 Furthermore, it is integrated with external tools, such as a code interpreter and Google Search, allowing it to perform calculations, test hypotheses, and ground its reasoning in external knowledge.13

The evolution from AlphaGeometry's next-step prediction to Deep Think's parallel reasoning marks a clear progression from a tool that assists with a single, discrete task to a system that emulates a complete, multi-faceted reasoning process. AlphaGeometry's LLM answers the question, "What is a single good thing to do now?" AlphaProof elevates this by situating the entire process within the rich, formal environment of the Lean proof assistant. Deep Think abstracts this further, managing a portfolio of entire potential solution paths and asking, "What are several promising strategies to try, and how can they be evaluated, pruned, and combined?" This sets a compelling long-term vision for an AI developed for Agda: the ultimate goal should not be a simple "hole-filler" but a system that can manage multiple proof attempts, strategically allocate resources, and collaborate with the user at the level of proof strategy.

#### **Table 1: Comparison of DeepMind's Mathematical AI Systems**

| AI System | AI Paradigm | Problem Type | Key Innovation | Output Format |
| :---- | :---- | :---- | :---- | :---- |
| **AlphaGeometry** | Neuro-Symbolic (LLM \+ Deduction Engine) | Geometric Proof Search | Massive-scale synthetic data generation to overcome data scarcity. | Formal Proof in DDAR language 1 |
| **FunSearch** | Evolutionary Search \+ LLM | Combinatorial Optimization / Algorithm Discovery | LLM used as a "creative mutator" in an evolutionary search loop. | Human-readable computer code (Python) 7 |
| **AlphaProof / Deep Think** | Neuro-Symbolic (LLM \+ Lean Verifier) \+ RL | General Mathematical Problem Solving (IMO) | "Parallel Thinking" reasoning; formal verification loop with a proof assistant. | Formal Proof in Lean 9 |

---

## **Part II: Foundational Technologies and Comparative Analysis**

To successfully adapt DeepMind's strategies, one must understand the foundational technologies they employ and the specific characteristics of the target environment. This section examines the neuro-symbolic paradigm that underpins these systems and then provides a critical comparative analysis of Lean and Agda, the two proof assistants at the heart of this project.

### **Section 2: The Neuro-Symbolic Paradigm**

The successes of AlphaGeometry and AlphaProof are prime examples of the neuro-symbolic AI paradigm, a hybrid approach that seeks to combine the strengths of two historically distinct schools of artificial intelligence.14

#### **2.1 Bridging Intuition and Rigor**

Neuro-symbolic AI synthesizes the capabilities of neural networks and symbolic AI to create more robust and capable systems.2

* **Symbolic AI (Good Old-Fashioned AI \- GOFAI):** This tradition is based on formal logic and rule-based manipulation of symbols. It excels at tasks requiring structured knowledge, explicit reasoning, and logical deduction, but it can be brittle when faced with novel situations and computationally slow when the search space is large.2  
* **Neural Networks (Connectionism):** This approach, which includes modern deep learning, is inspired by the brain's structure. It excels at learning patterns from vast amounts of unstructured data, making it powerful for tasks like image recognition and natural language processing. However, neural networks often function as "black boxes," lacking rigorous reasoning abilities and struggling to provide logical explanations for their outputs.2

The process of mathematical discovery is a natural fit for this hybrid model, as it inherently requires both creative intuition to conjecture a new theorem or find a clever proof strategy, and meticulous deductive rigor to verify that every step in the proof is logically sound.1

#### **2.2 A Taxonomy of Integration**

The integration of neural and symbolic components can take many forms. Using Henry Kautz's taxonomy of neuro-symbolic architectures provides a structured way to understand DeepMind's designs 2:

* **Neural | Symbolic:** In this architecture, a neural system interprets perceptual data to produce symbols and relationships that are then processed by a symbolic reasoner. **AlphaGeometry** fits this model perfectly: its language model perceives the geometric state and suggests symbolic constructs (new points and lines) for the DDAR symbolic engine to reason about.1  
* **Symbolic\[Neural\]:** Here, a symbolic process invokes a neural network as a subroutine. **FunSearch** can be viewed as an instance of this, where the high-level symbolic evolutionary algorithm calls upon an LLM to perform the "mutation" step of generating new programs.7  
* **Neural:** This model involves a neural system that can directly call a symbolic reasoning engine as a tool or oracle. **AlphaProof**, which uses its language model to generate proof steps that are then verified by the Lean theorem prover, is a clear example.9 The popular example of ChatGPT using a plugin to query Wolfram Alpha also falls into this category.2

A clear pattern emerges from this analysis. While a custom-built symbolic engine like AlphaGeometry's DDAR is powerful, it is inherently domain-specific and limited in its logical expressiveness. The most advanced and general systems, like AlphaProof and Gemini Deep Think, use a full-fledged interactive theorem prover (Lean) as their symbolic component. A general-purpose proof assistant like Lean or Agda is a far more powerful and versatile symbolic engine. It provides a highly expressive logical foundation (dependent type theory), a trusted kernel that guarantees correctness, and access to a vast, pre-existing library of mathematical definitions and theorems. By targeting a proof assistant, an AI system can leverage decades of research in formal methods and operate within a much richer and more general mathematical universe. This validates the direction of this project: using Agda as the symbolic backend is the most promising path toward general-purpose AI-assisted theorem proving, with the primary challenge lying in the design of the interface between the neural and symbolic worlds.

### **Section 3: A Tale of Two Provers: Lean vs. Agda**

While both Lean and Agda are powerful proof assistants based on dependent type theory, they are not interchangeable. Methods developed for Lean cannot be naively transferred to Agda due to profound differences in their underlying foundations, proof styles, and community philosophies. Understanding these differences is critical for designing an effective AI for Agda.

#### **3.1 Foundational Differences: CIC vs. MLTT**

The core distinction between Lean and Agda lies in their foundational type theories.

* **Lean** is based on the **Calculus of Inductive Constructions (CIC)**, a type theory it shares with the Coq proof assistant.17 A key feature of CIC is its  
  **impredicative universe of propositions, Prop**.19 This allows for quantification over all propositions, a powerful feature that enables the formalization of concepts from classical mathematics that are difficult to express in other systems. Furthermore, Lean's primary mathematical library,  
  mathlib, embraces classical reasoning by assuming axioms such as the law of the excluded middle and the axiom of choice.21  
* **Agda** is based on **Per Martin-Löf's intuitionistic Type Theory (MLTT)**.22 MLTT is fundamentally  
  **predicative and constructive**.19 In a predicative system, one cannot define a type by quantifying over a collection of types that includes the very type being defined. Constructivism demands that a proof of existence for a mathematical object must provide a method for constructing that object. This "proofs as programs" philosophy, also known as the Curry-Howard correspondence, is central to Agda.22

This foundational choice is not merely a technical detail; it reflects a deep philosophical and cultural divide that shapes each language's ecosystem and intended use. Lean's classical, impredicative foundation makes it exceptionally well-suited for formalizing the existing body of mainstream, non-constructive mathematics in fields like algebra, analysis, and number theory.25 In contrast, Agda's constructive, predicative foundation makes it a preferred tool for research in programming language theory, constructive mathematics, and homotopy type theory, where the computational content and structure of proofs are of primary importance.24 Consequently, an AI for Agda must respect this constructive nature. An AI that merely proves a theorem's truth without producing a clean, understandable, and computationally meaningful proof term would likely be considered inadequate by the Agda community. The quality of the generated proof-as-a-program is a first-class concern.

#### **3.2 Proof Styles: Tactics vs. Terms**

The foundational differences manifest directly in how users write proofs.

* **Lean's Tactic-Based Proofs:** Writing a proof in Lean is an imperative, interactive process. The user begins with a goal and applies a sequence of **tactics**—commands that transform the proof state—to progressively simplify the goal until it is solved.28 This style is powerful for automation, as complex reasoning steps can be packaged into a single tactic, but the resulting proof script can be difficult for a human to read and understand, as it describes the  
  *process* of finding the proof rather than the proof object itself.24  
* **Agda's Term-Based Proofs:** Writing a proof in Agda is a declarative, programmatic process. A theorem is a type, and a proof is a well-typed program (or term) that inhabits that type.22 The user constructs this proof term directly, typically using an interactive  
  **"hole-and-refine"** workflow. They leave a placeholder (? or { }?) in the code, and the type checker reports the type of the hole (the current subgoal) and the variables in context. The user then fills this hole with code, creating new sub-holes as needed, until the entire term is complete.32 The final proof is a single, self-contained, and readable piece of code.24

This divergence in proof style dictates a fundamentally different role for an AI assistant. For Lean, the AI's task is primarily **tactic recommendation**: given the current proof state, suggest the most promising tactic to apply next. This is a classification or sequence generation problem over the language of tactics. For Agda, the AI's task is **type-directed program synthesis**: given the type of a hole and its context, generate a well-typed Agda expression to fill it. This is a structured code generation problem, heavily constrained by Agda's powerful type system, and it cannot be solved by simply adapting a tactic-prediction model from Lean.

#### **3.3 Metaprogramming and Automation: A Comparative Analysis**

The ability to extend a prover with custom automation is crucial for large-scale formalization, and here again, the two systems differ significantly.

* **Lean's Tactic Framework:** Lean 4 features a mature, performant metaprogramming framework written in Lean itself, designed specifically for users to create new, powerful tactics.34 This integrated, first-class support for automation makes it convenient to extend the prover's capabilities and was likely a key factor in DeepMind's choice of Lean for its research.25  
* **Agda's Reflection:** Agda provides metaprogramming capabilities through **reflection**. This is a lower-level mechanism that allows Agda code to inspect and generate the abstract syntax trees (ASTs) of Agda terms, goals, and contexts.34 While extremely powerful, it is less of a ready-made "tactic language" and more of a fundamental building block. Libraries like  
  agda-stdlib-meta have been built on top of reflection to provide tactic-like functionality, but the ecosystem for high-level automation is less developed than in Lean.36

This creates an "automation infrastructure gap." DeepMind's work relies on being able to programmatically control the prover at a high level, a feature Lean's tactic framework provides out of the box. For an Agda-based project, a significant portion of the engineering effort may need to be dedicated to building a more robust metaprogramming library that can serve as the bridge between the AI model and the Agda type checker.

#### **3.4 Ecosystems and Libraries**

The communities and their collective work reflect their differing philosophies.

* **Lean's mathlib** is a massive, monolithic library focused on classical mathematics.26 Its single, interconnected structure provides a large and consistent dataset, which is highly advantageous for training AI models.25  
* **Agda's libraries** are more fragmented, with major, distinct projects like agda-stdlib (standard library), agda-unimath (for univalent/homotopy type theory), and agda-categories.37 These libraries often embody different foundational assumptions (e.g., with or without the univalence axiom) and cater to different sub-communities.21  
* **Tooling and Interaction:** Both languages have excellent editor support, particularly within Emacs and VS Code.33 Critically for this project, Agda's interactive mode is built on a persistent background process that communicates with the editor via a well-defined protocol, which now supports JSON (  
  \--interaction-json).32 This protocol is precisely the kind of interface an external AI tool would need to hook into to receive context and provide suggestions.

#### **Table 2: Comparative Analysis of Lean and Agda**

| Feature | Lean | Agda |
| :---- | :---- | :---- |
| **Underlying Type Theory** | Calculus of Inductive Constructions (CIC) 17 | Martin-Löf Type Theory (MLTT) 22 |
| **Core Philosophy** | Formalization of Classical Mathematics 25 | Proofs as Programs (Constructivism) 23 |
| **Proof Style** | Imperative, Tactic-based 28 | Declarative, Term Construction (Hole-and-Refine) 24 |
| **Metaprogramming** | Mature, integrated Tactic Framework 34 | Reflection (Lower-level AST manipulation) 36 |
| **Key Library** | mathlib (Monolithic, Classical) 25 | agda-stdlib, unimath (Fragmented, Constructive Focus) 37 |
| **Community Focus** | Formal Mathematics, esp. Algebra & Analysis 25 | Programming Language Theory, Constructive Math, HoTT 24 |
| **AI Assistant's Role** | Tactic Recommender | Type-Directed Program Synthesizer |

---

## **Part III: A Strategic Framework for AI-Assisted Theorem Proving in Agda**

Synthesizing the analysis of DeepMind's successes and the fundamental differences between Lean and Agda, this section proposes a concrete, actionable framework for developing a powerful AI assistant for Agda. The strategy involves tackling the problem in layers, starting with established techniques and building towards more ambitious, fully autonomous reasoning.

### **Section 4: Adapting DeepMind's Methods for Agda**

A direct port of DeepMind's Lean-based methods is infeasible. Instead, a successful project must adapt the underlying *principles*—neuro-symbolic architecture, synthetic data generation, and leveraging the prover's own metaprogramming features—to Agda's unique environment.

#### **4.1 The Premise Selection Problem: A Solved Frontier**

Before an AI can suggest a complex proof step, it must first solve a simpler problem: identifying which existing definitions and lemmas from a vast library are relevant to the current goal. This task, known as premise selection, can be considered a largely solved problem for Agda, thanks to recent research that provides both the necessary data and effective models.

* **The MLFMF Dataset:** The Machine Learning for Mathematical Formalization (MLFMF) project has produced a comprehensive dataset derived from major Agda libraries, including agda-stdlib, agda-unimath, and TypeTopology.38 Each library is represented in two machine-learning-friendly formats:  
  1. A **heterogeneous graph** where nodes are definitions and modules, and edges represent dependencies and references.  
  2. A collection of s-expressions representing the full Abstract Syntax Trees (ASTs) of every definition.  
     This provides a rich, multi-modal dataset ready for training machine learning models on the structure of Agda code.38  
* **The QUILL Architecture:** The paper "A Neural Architecture for Program-proofs" (arXiv:2402.02104) introduces QUILL, a novel Transformer-based architecture specifically designed to represent dependently-typed programs like those in Agda.41 It uses structure-aware attention mechanisms and a name-agnostic representation of variables (via de Bruijn indexing) to effectively model the complex syntax of Agda. When applied to the premise selection task on the MLFMF dataset, QUILL achieved strong results, significantly outperforming baseline methods and demonstrating the viability of applying deep learning to these intricate structures.41

The existence of this work is a significant advantage. A human prover, when stuck, instinctively searches the library for relevant theorems. An AI assistant must do the same. The QUILL research provides a proven blueprint for an effective premise selection component in Agda. Therefore, any larger AI system should incorporate a premise selector based on this work as a foundational layer. It can be used as a standalone tool or, more powerfully, as a filter to provide a smaller, more relevant context to a more complex proof synthesis model.

#### **4.2 Beyond Premise Selection: AI for Interactive Proof Construction**

With premise selection as a foundation, the next step is to build an AI co-pilot that directly assists with Agda's primary workflow: interactive proof construction. This requires a model designed to be a "hole-filler."

* **Model Architecture and Interaction Loop:** The AI would be a type-aware program synthesizer. A Transformer-based sequence-to-sequence architecture is a natural fit.  
  1. The user, working in an editor, places their cursor inside an Agda hole ({ }?n).  
  2. A custom editor plugin uses Agda's JSON interaction protocol (--interaction-json) to query the running Agda process for the hole's full context: its goal type and the types of all local variables in scope.32  
  3. This context, represented as a sequence of ASTs, is fed into the AI model's encoder.  
  4. The model's decoder then autoregressively generates the AST of a candidate proof term to fill the hole.  
  5. The plugin presents one or more of these suggestions to the user, who can then select one to insert into the code, potentially creating new sub-goals to be solved in the next iteration of the loop.

This approach directly targets Agda's unique proof style and leverages its existing tooling for external interaction.

#### **Table 3: Existing and Proposed AI Approaches for Agda**

| Task | Approach | Required Data | Key Challenges |
| :---- | :---- | :---- | :---- |
| **Premise Selection (Existing)** | Graph Neural Network (node2vec) or Structure-Aware Transformer (QUILL) on library dependency graph/ASTs.38 | MLFMF dataset.38 | Scaling to the entire Agda ecosystem; real-time inference. |
| **Interactive Hole-Filling (Proposed)** | Type-aware sequence-to-sequence Transformer for structured code generation. | Large-scale dataset of (context, hole-type, fill-term) triples. | Generating the required dataset; handling the complexity of dependent types during generation; ensuring low-latency suggestions. |
| **Full Proof Search (Future)** | Neuro-symbolic loop with Monte Carlo Tree Search over proof terms, or FunSearch-style evolution of metaprograms. | Massive synthetic dataset of problem-proof pairs. | Defining a valid "action space" of proof-term refinements; managing the enormous computational cost; designing an effective evaluation function. |

#### **4.3 The Data Generation Challenge in Agda**

The "hole-filler" model, like AlphaGeometry's LLM, requires a massive dataset that does not currently exist. The strategy for creating it must be inspired by AlphaGeometry's synthetic data pipeline, but adapted for Agda's term-based structure.

1. **Seed Generation:** Begin with the axioms and fundamental definitions from a core library, such as parts of agda-stdlib.  
2. **Forward Chaining via Metaprogramming:** Develop an Agda metaprogram using its reflection capabilities. This program would act as a "theorem generator" by randomly applying valid inference rules (e.g., applying a function to a valid argument, instantiating a polymorphic theorem, performing a case split) to the set of known theorems. This process generates a vast number of new, simple, and provably correct theorems and their corresponding proof terms.  
3. **Data Extraction:** For each synthetically generated proof, another metaprogram would traverse its AST. At every sub-expression, it would extract a training example consisting of the triple: (context, type of sub-expression, sub-expression itself). This transforms a single complex proof into many smaller training examples for the hole-filler.  
4. **Curriculum Learning:** The training process should follow the generation process. The AI model would first be trained on the simplest proofs and gradually be exposed to more complex ones, allowing it to learn the fundamentals of Agda's type theory before tackling more intricate reasoning.

### **Section 5: Project Roadmap and Recommendations**

This project can be structured as a multi-phase research and development effort, with each phase delivering valuable tools while building towards the ultimate goal of a highly capable AI reasoning assistant for Agda.

#### **5.1 Phase 1: Foundational Tooling and Data Curation (Months 1-6)**

The initial phase should focus on replicating existing work and building the essential infrastructure for communication and data handling.

* **Action:** Establish a data extraction pipeline for existing Agda libraries (e.g., agda-stdlib, unimath) using the methodologies and tools from the MLFMF project.38  
* **Action:** Implement and benchmark premise selection models based on the published results for node2vec and the QUILL architecture. This will yield a valuable standalone tool for Agda users early in the project.41  
* **Action:** Develop a client application that can reliably communicate with the Agda compiler via its \--interaction-json protocol. This client will be the core of the interactive co-pilot, responsible for extracting proof contexts from holes in real-time.40

#### **5.2 Phase 2: Developing the Interactive Co-pilot (Months 7-18)**

This phase focuses on building the core AI model for interactive assistance.

* **Action:** Begin the parallel research track of developing the synthetic data generation pipeline using Agda's reflection capabilities, as outlined in Section 4.3. This is a significant research challenge in its own right.  
* **Action:** Design and implement the "hole-filler" neural architecture. Train an initial version on the non-synthetic data extracted from existing Agda libraries in Phase 1\. While this dataset is smaller, it will be sufficient to create a proof-of-concept model.  
* **Action:** Integrate the trained model with the interaction client from Phase 1 to create a working prototype of an interactive co-pilot for Agda. Benchmark its performance and gather user feedback.

#### **5.3 Phase 3: Advanced Reasoning and Full Proof Synthesis (Months 19+)**

The final phase aims to move beyond assistance towards autonomous reasoning, tackling more complex problems.

* **Action:** Scale up the synthetic data generation pipeline to produce hundreds of millions or billions of training examples. Retrain the hole-filler model on this massive dataset to achieve a step-change in performance.  
* **Action:** Explore more advanced architectures inspired by Deep Think's parallel reasoning. This could involve the AI generating and maintaining multiple candidate proof terms for a single hole, or even managing multiple parallel proof strategies for an entire theorem.  
* **Action:** Investigate a FunSearch-like approach to evolve Agda metaprograms. Instead of generating proof terms directly, the AI would generate reflection-based tactics designed to solve specific classes of problems (e.g., a tactic for solving ring equality problems). This represents a shift from assisting the user with low-level steps to automating entire sub-proofs.

#### **Works cited**

1. AlphaGeometry: An Olympiad-level AI system for geometry \- Google ..., accessed August 11, 2025, [https://deepmind.google/discover/blog/alphageometry-an-olympiad-level-ai-system-for-geometry/](https://deepmind.google/discover/blog/alphageometry-an-olympiad-level-ai-system-for-geometry/)  
2. Neuro-symbolic AI \- Wikipedia, accessed August 11, 2025, [https://en.wikipedia.org/wiki/Neuro-symbolic\_AI](https://en.wikipedia.org/wiki/Neuro-symbolic_AI)  
3. AlphaGeometry \- Wikipedia, accessed August 11, 2025, [https://en.wikipedia.org/wiki/AlphaGeometry](https://en.wikipedia.org/wiki/AlphaGeometry)  
4. Gold-medalist Performance in Solving Olympiad Geometry with AlphaGeometry2 \- arXiv, accessed August 11, 2025, [https://arxiv.org/abs/2502.03544](https://arxiv.org/abs/2502.03544)  
5. Google's AI just solved 84% of the International Math Olympiad (IMO) problems from 2000-24 with Alpha Geometry 2\! : r/Bard \- Reddit, accessed August 11, 2025, [https://www.reddit.com/r/Bard/comments/1ijr8lo/googles\_ai\_just\_solved\_84\_of\_the\_international/](https://www.reddit.com/r/Bard/comments/1ijr8lo/googles_ai_just_solved_84_of_the_international/)  
6. google-deepmind/alphageometry \- GitHub, accessed August 11, 2025, [https://github.com/google-deepmind/alphageometry](https://github.com/google-deepmind/alphageometry)  
7. FunSearch: Making new discoveries in mathematical sciences using ..., accessed August 11, 2025, [https://deepmind.google/discover/blog/funsearch-making-new-discoveries-in-mathematical-sciences-using-large-language-models/](https://deepmind.google/discover/blog/funsearch-making-new-discoveries-in-mathematical-sciences-using-large-language-models/)  
8. FunSearch — How Deepmind uses LLM to solve a Mathematic problem that has never been solved \- Fisher Lok, accessed August 11, 2025, [https://fisherlok.medium.com/funsearch-how-deepmind-uses-llm-to-solve-a-mathematic-problem-that-has-never-been-solved-17a9f705f771](https://fisherlok.medium.com/funsearch-how-deepmind-uses-llm-to-solve-a-mathematic-problem-that-has-never-been-solved-17a9f705f771)  
9. \[N\] AI achieves silver-medal standard solving International Mathematical Olympiad problems : r/MachineLearning \- Reddit, accessed August 11, 2025, [https://www.reddit.com/r/MachineLearning/comments/1ebyx03/n\_ai\_achieves\_silvermedal\_standard\_solving/](https://www.reddit.com/r/MachineLearning/comments/1ebyx03/n_ai_achieves_silvermedal_standard_solving/)  
10. DeepMind's AI Achieves Breakthrough in Solving International Mathematical Olympiad Problems \- UKMT, accessed August 11, 2025, [https://ukmt.org.uk/deepminds-ai-achieves-breakthrough-in-solving-international-mathematical-olympiad-problems](https://ukmt.org.uk/deepminds-ai-achieves-breakthrough-in-solving-international-mathematical-olympiad-problems)  
11. Google DeepMind, accessed August 11, 2025, [https://deepmind.google/](https://deepmind.google/)  
12. Research \- Google DeepMind, accessed August 11, 2025, [https://deepmind.google/research/](https://deepmind.google/research/)  
13. Gemini 2.5: Deep Think is now rolling out \- Google Blog, accessed August 11, 2025, [https://blog.google/products/gemini/gemini-2-5-deep-think/](https://blog.google/products/gemini/gemini-2-5-deep-think/)  
14. Decoding Neuro-Symbolic AI \- Phaneendra Kumar Namala \- Medium, accessed August 11, 2025, [https://phaneendrakn.medium.com/decoding-neuro-symbolic-ai-64385310f030](https://phaneendrakn.medium.com/decoding-neuro-symbolic-ai-64385310f030)  
15. Why Neurosymbolic AI is a Big Leap in Artificial Intelligence \- Emeritus, accessed August 11, 2025, [https://emeritus.org/in/learn/neurosymbolic-ai/](https://emeritus.org/in/learn/neurosymbolic-ai/)  
16. DeepMind's AI for Mathematics Breakthrough Explained \- YouTube, accessed August 11, 2025, [https://www.youtube.com/watch?v=UPCI1-ZvwOg](https://www.youtube.com/watch?v=UPCI1-ZvwOg)  
17. Use and Abuse of Instance Parameters in the Lean Mathematical Library \- DROPS, accessed August 11, 2025, [https://drops.dagstuhl.de/storage/00lipics/lipics-vol237-itp2022/LIPIcs.ITP.2022.4/LIPIcs.ITP.2022.4.pdf](https://drops.dagstuhl.de/storage/00lipics/lipics-vol237-itp2022/LIPIcs.ITP.2022.4/LIPIcs.ITP.2022.4.pdf)  
18. calculus of constructions in nLab, accessed August 11, 2025, [https://ncatlab.org/nlab/show/calculus+of+constructions](https://ncatlab.org/nlab/show/calculus+of+constructions)  
19. agda \- What are the differences between MLTT and CIC? \- Proof ..., accessed August 11, 2025, [https://proofassistants.stackexchange.com/questions/267/what-are-the-differences-between-mltt-and-cic](https://proofassistants.stackexchange.com/questions/267/what-are-the-differences-between-mltt-and-cic)  
20. Proof-theoretic comparison table? \- Proof Assistants Stack Exchange, accessed August 11, 2025, [https://proofassistants.stackexchange.com/questions/1201/proof-theoretic-comparison-table](https://proofassistants.stackexchange.com/questions/1201/proof-theoretic-comparison-table)  
21. What language should I use to write proofs about category theory : r/haskell \- Reddit, accessed August 11, 2025, [https://www.reddit.com/r/haskell/comments/17xz2sv/what\_language\_should\_i\_use\_to\_write\_proofs\_about/](https://www.reddit.com/r/haskell/comments/17xz2sv/what_language_should_i_use_to_write_proofs_about/)  
22. What is Agda? — Agda 2.9.0 documentation, accessed August 11, 2025, [https://agda.readthedocs.io/en/latest/getting-started/what-is-agda.html](https://agda.readthedocs.io/en/latest/getting-started/what-is-agda.html)  
23. Type theory \- Wikipedia, accessed August 11, 2025, [https://en.wikipedia.org/wiki/Type\_theory](https://en.wikipedia.org/wiki/Type_theory)  
24. Why Agda? \- Zulip Chat Archive \- Lean community, accessed August 11, 2025, [https://leanprover-community.github.io/archive/stream/113489-new-members/topic/Why.20Agda.3F.html](https://leanprover-community.github.io/archive/stream/113489-new-members/topic/Why.20Agda.3F.html)  
25. Topic: Comparison with Coq \- Zulip Chat Archive, accessed August 11, 2025, [https://leanprover-community.github.io/archive/stream/236446-Type-theory/topic/Comparison.20with.20Coq.html](https://leanprover-community.github.io/archive/stream/236446-Type-theory/topic/Comparison.20with.20Coq.html)  
26. Coq vs Lean \- What are your opinions? : r/math \- Reddit, accessed August 11, 2025, [https://www.reddit.com/r/math/comments/vmzuot/coq\_vs\_lean\_what\_are\_your\_opinions/](https://www.reddit.com/r/math/comments/vmzuot/coq_vs_lean_what_are_your_opinions/)  
27. Agda vs. Coq vs. Idris | Meta-cedille blog, accessed August 11, 2025, [https://whatisrt.github.io/dependent-types/2020/02/18/agda-vs-coq-vs-idris.html](https://whatisrt.github.io/dependent-types/2020/02/18/agda-vs-coq-vs-idris.html)  
28. Compiling Haskell into Lean: A Common Abstract Syntax for Haskell and Interactive Theorem Provers \- Chapman University Digital Commons, accessed August 11, 2025, [https://digitalcommons.chapman.edu/cgi/viewcontent.cgi?article=1003\&context=eecs\_theses](https://digitalcommons.chapman.edu/cgi/viewcontent.cgi?article=1003&context=eecs_theses)  
29. Lean-auto: An Interface between Lean 4 and Automated Theorem Provers \- arXiv, accessed August 11, 2025, [https://arxiv.org/html/2505.14929v1](https://arxiv.org/html/2505.14929v1)  
30. Talking Tactics in LeanProver vs Understanding Proofs in Agda with Conal Elliott \- YouTube, accessed August 11, 2025, [https://www.youtube.com/watch?v=OoKNpfUNpfU](https://www.youtube.com/watch?v=OoKNpfUNpfU)  
31. Dependent types \- Agda's documentation\!, accessed August 11, 2025, [https://agda.readthedocs.io/en/v2.6.0.1/getting-started/what-is-agda.html](https://agda.readthedocs.io/en/v2.6.0.1/getting-started/what-is-agda.html)  
32. Features needed for Agda \- Sublime Forum, accessed August 11, 2025, [https://forum.sublimetext.com/t/features-needed-for-agda/3216](https://forum.sublimetext.com/t/features-needed-for-agda/3216)  
33. A Taste of Agda — Agda 2.6.2 documentation, accessed August 11, 2025, [https://agda.readthedocs.io/en/v2.6.2/getting-started/a-taste-of-agda.html](https://agda.readthedocs.io/en/v2.6.2/getting-started/a-taste-of-agda.html)  
34. A Metaprogramming Framework for Formal Verification \- Gabriel Ebner, accessed August 11, 2025, [https://gebner.org/pdfs/2017-08-18\_tactic.pdf](https://gebner.org/pdfs/2017-08-18_tactic.pdf)  
35. What are the thoughts about the Lean4 language by the haskellers? \- Reddit, accessed August 11, 2025, [https://www.reddit.com/r/haskell/comments/1e9mezr/what\_are\_the\_thoughts\_about\_the\_lean4\_language\_by/](https://www.reddit.com/r/haskell/comments/1e9mezr/what_are_the_thoughts_about_the_lean4_language_by/)  
36. What's the difference between reflection and tactics? \- Proof ..., accessed August 11, 2025, [https://proofassistants.stackexchange.com/questions/1103/whats-the-difference-between-reflection-and-tactics](https://proofassistants.stackexchange.com/questions/1103/whats-the-difference-between-reflection-and-tactics)  
37. Agda Github Community, accessed August 11, 2025, [https://github.com/agda](https://github.com/agda)  
38. MLFMF: Data Sets for Machine Learning for Mathematical ..., accessed August 11, 2025, [https://arxiv.org/abs/2310.16005](https://arxiv.org/abs/2310.16005)  
39. Agda layer \- Spacemacs, accessed August 11, 2025, [https://www.spacemacs.org/layers/+lang/agda/README.html](https://www.spacemacs.org/layers/+lang/agda/README.html)  
40. Command-line options — Agda 2.6.4.1 documentation, accessed August 11, 2025, [https://agda.readthedocs.io/en/v2.6.4.1/tools/command-line-options.html](https://agda.readthedocs.io/en/v2.6.4.1/tools/command-line-options.html)  
41. Learning Structure-Aware Representations of Dependent ... \- arXiv, accessed August 11, 2025, [https://arxiv.org/abs/2402.02104](https://arxiv.org/abs/2402.02104)
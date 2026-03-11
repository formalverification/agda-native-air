# agda-dojang Python code

## Layout

```
agda-dojang/python/
├── README.md                        # (this file)
├── tests
│   ├── test_agent_bridge.py         # tests agent bridge utilities in tools/agent_bridge.py
│   ├── test_eval_fixture_policy_request.py
│   │                                # tests policy request from eval_fixtures.py has expected shape
│   ├── test_parse_request.py        # tests for parse_request_json function in policy_contract.py
│   ├── test_policy_contract.py      # tests for policy contract defined in policy_contract.py
│   ├── test_policy_fixture.py       # tests for policy fixture defined in tools/policy_fixture.py
│   ├── test_rendering.py            # tests for rendering.py utilities
│   └── test_report_parser.py        # tests for log parser that reads AgdaDojang's reporting macros output
├── tools
│   ├── agent_bridge.py              # a tiny, deterministic "report → policy → patch → check" loop
│   ├── dojang_extract.py            # agda-dojang trace extractor (v0, safe CLI)
│   ├── dojang_try.py                # agda-dojang probe & tactics runner; slim, orchestration only code
│   ├── eval_fixtures.py             # deterministic Agda-check evaluator + fixtures scoreboard
│   ├── policy_contract.py           # request/response contract for policy backends used by agda-dojang
│   ├── policy_fixture.py            # deterministic oracle policy backend for testing proof completion
│   ├── prompt_baseline.py           # tiny "prompting baseline"; turns tasks into (context, goal, completion) attempts
│   ├── report_parser.py             # parse Agda's stderr for subgoal reports (marked by AGDADOJANG_SUBGOALS_BEGIN/END)
│   └── search.py                    # simple BFS/beam search driver for AgdaDojang, v0.3
└── utils
    ├── command_runner.py            # returns Result[CommandResult, PipelineError]
    ├── file_ops.py                  # pure helpers for dirs/files/tmp handling
    ├── rendering.py                 # utilities to render Agda code snippets for tmp scratch modules
    ├── result.py                    # tiny Result monad
    ├── run_unittests.py             # pretty-ish unittest runner
    └── types.py                     # dataclasses/aliases/enums for "shared types"
```


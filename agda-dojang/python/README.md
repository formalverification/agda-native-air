# agda-dojang Python code

## Layout

```
agda-dojang/python/
├── README.md                        # (this file)
├── tests
│   ├── test_agda_probe.py           # tests the Agda-probing primitives in utils/agda_probe.py
│   ├── test_eval_fixture_policy_request.py
│   │                                # tests policy request from eval_fixtures.py has expected shape
│   ├── test_goal_report.py          # tests the marker-block parser in utils/goal_report.py
│   ├── test_parse_request.py        # tests for parse_request_json function in policy_contract.py
│   ├── test_policy_contract.py      # tests for policy contract defined in policy_contract.py
│   ├── test_policy_fixture.py       # tests for policy fixture defined in tools/policy_fixture.py
│   └── test_rendering.py            # tests for rendering.py utilities
├── tools
│   ├── dojang_extract.py            # agda-dojang trace extractor (v0, safe CLI)
│   ├── eval_fixtures.py             # deterministic Agda-check evaluator + fixtures scoreboard
│   ├── policy_contract.py           # request/response contract for policy backends used by agda-dojang
│   ├── policy_fixture.py            # deterministic oracle policy backend for testing proof completion
│   ├── prompt_baseline.py           # tiny "prompting baseline"; turns tasks into (context, goal, completion) attempts
│   └── search.py                    # simple BFS/beam search driver for AgdaDojang, v0.3
└── utils
    ├── agda_probe.py                # probe Agda about one hole: source surgery, invocation, verdict
    ├── command_runner.py            # returns Result[CommandResult, PipelineError]
    ├── file_ops.py                  # pure helpers for dirs/files/tmp handling
    ├── goal_report.py               # parse the AGDADOJANG_REQ marker block into {goal, context}
    ├── rendering.py                 # utilities to render Agda code snippets for tmp scratch modules
    ├── result.py                    # tiny Result monad
    ├── run_unittests.py             # pretty-ish unittest runner
    └── types.py                     # dataclasses/aliases/enums for "shared types"
```

The deterministic "report → policy → patch → check" bridge that used to live in
`tools/` (`agent_bridge.py`, the marker parser `report_parser.py`, and the
`dojang_try.py` CLI front) retired in issue #109;
[`agda-mcp`](../../agda-mcp/README.md) is its successor and the agent-facing
route into Agda.  The primitives `eval_fixtures.py` still needs are the two
`utils/` modules above, and their tests run in the pure lane.

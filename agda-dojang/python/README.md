# agda-jang Python code

## Layout

```
agda-jang/python/
├── tools/
│   ├── jang_try.py          # slim, orchestration only code
│   ├── report_parser.py
│   └── search.py
└── utils/
    ├── __init__.py
    ├── types.py             # dataclasses/aliases/enums for “shared types”
    ├── result.py            # tiny Result monad
    ├── command_runner.py    # returns Result[CommandResult, PipelineError]
    └── file_ops.py          # pure helpers for dirs/files/tmp handling
```

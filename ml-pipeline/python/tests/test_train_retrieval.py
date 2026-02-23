#!/usr/bin/env python3

"""
test_train_retrieval.py

File: ml-pipeline/python/tests/test_train_retrieval.py

Description:
  Tests for train_retrieval.py, ensuring that the retrieval model artifact is
  deterministic across runs and adheres to expected invariants (e.g. sorted vocab
  keys, sorted postings, normalized vectors).  Uses inline JSONL fixtures for
  simplicity/determinism.

  Test the determinism + artifact invariants:

  + given tiny JSONL dataset, `train_retrieval` produces same pickle bytes across runs;
  + vocab is sorted; postings are sorted (inverted index construction is sorted/grouped);
  + schema key is exactly `"agda-ai-prover/retrieval-policy@v0"`.
"""

from __future__ import annotations

import json
import pickle
import tempfile
import unittest
from pathlib import Path

from model import train_retrieval as tr


def _write_jsonl(path: Path, rows: list[dict]) -> None:
    lines = [json.dumps(r, ensure_ascii=False) for r in rows]
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


class TestTrainRetrieval(unittest.TestCase):
    def test_pickle_roundtrip_and_deterministic_bytes(self) -> None:
        # Inline JSONL fixture intentionally out-of-order to test deterministic sorting.
        rows = [
            {
                "goal": "x ≡ z",
                "context": [{"name": "x", "type": "A"}, {"name": "z", "type": "A"}],
                "target": "p-x≡z",
                "meta": {"prettyQname": "C", "module": "M", "name": "c"},
            },
            {
                "goal": "x ≡ x",
                "context": [{"name": "x", "type": "A"}],
                "target": "refl",
                "meta": {"prettyQname": "A", "module": "M", "name": "a"},
            },
            {
                "goal": "x ≡ y",
                "context": [{"name": "x", "type": "A"}, {"name": "y", "type": "A"}],
                "target": "p-x≡y",
                "meta": {"prettyQname": "B", "module": "M", "name": "b"},
            },
        ]

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            in_path = td_path / "fixture.jsonl"
            out1 = td_path / "retrieval1.pkl"
            out2 = td_path / "retrieval2.pkl"
            _write_jsonl(in_path, rows)

            rc1 = tr.main(["--in", str(in_path), "--out", str(out1)])
            self.assertEqual(rc1, 0)
            b1 = out1.read_bytes()

            # Train again to a different output path; bytes must match exactly.
            rc2 = tr.main(["--in", str(in_path), "--out", str(out2)])
            self.assertEqual(rc2, 0)
            b2 = out2.read_bytes()

            self.assertEqual(b1, b2, "artifact must be byte-for-byte deterministic across runs")

            # Pickle roundtrip + basic invariants.
            artifact = pickle.loads(b1)
            self.assertIsInstance(artifact, dict)
            self.assertEqual(artifact.get("schema"), tr.RETRIEVAL_MODEL_SCHEMA_V0)

            vocab = artifact.get("vocab")
            idf = artifact.get("idf")
            docs = artifact.get("docs")
            doc_vecs = artifact.get("doc_vecs")
            inverted = artifact.get("inverted")

            self.assertIsInstance(vocab, dict)
            self.assertIsInstance(idf, list)
            self.assertIsInstance(docs, list)
            self.assertIsInstance(doc_vecs, list)
            self.assertIsInstance(inverted, dict)
            self.assertEqual(len(docs), len(doc_vecs))

            # Docs must be in deterministic sorted order by doc_key:
            # prettyQname: A, B, C  => targets: refl, p-x≡y, p-x≡z
            got_targets = [d.get("target") for d in docs]
            self.assertEqual(got_targets, ["refl", "p-x≡y", "p-x≡z"])

    def test_vocab_sorted_postings_sorted_and_vectors_normalized(self) -> None:
        rows = [
            {
                "goal": "¬ x → x",
                "context": [{"name": "x", "type": "Bool"}],
                "target": "λ x → x",
                "meta": {"prettyQname": "A", "module": "M", "name": "a"},
            },
            {
                "goal": "x ≡ x",
                "context": [{"name": "x", "type": "A"}],
                "target": "refl",
                "meta": {"prettyQname": "B", "module": "M", "name": "b"},
            },
        ]

        with tempfile.TemporaryDirectory() as td:
            td_path = Path(td)
            in_path = td_path / "fixture.jsonl"
            out_path = td_path / "retrieval.pkl"
            _write_jsonl(in_path, rows)

            rc = tr.main(["--in", str(in_path), "--out", str(out_path)])
            self.assertEqual(rc, 0)
            artifact = pickle.loads(out_path.read_bytes())

            vocab = artifact["vocab"]
            doc_vecs = artifact["doc_vecs"]
            inverted = artifact["inverted"]

            # Vocab keys are inserted in sorted token order.
            vocab_keys = list(vocab.keys())
            self.assertEqual(vocab_keys, sorted(vocab_keys))

            # Each sparse vector has sorted integer keys and is L2-normalized (when non-empty).
            for vec in doc_vecs:
                self.assertIsInstance(vec, dict)
                ks = list(vec.keys())
                self.assertEqual(ks, sorted(ks))
                n = tr.l2_norm(vec)
                self.assertTrue(abs(n - 1.0) < 1e-6 or n == 0.0)

            # Inverted postings must be sorted by doc_id ascending.
            for postings in inverted.values():
                self.assertIsInstance(postings, list)
                doc_ids = [doc_id for (doc_id, _w) in postings]
                self.assertEqual(doc_ids, sorted(doc_ids))


if __name__ == "__main__":
    unittest.main()

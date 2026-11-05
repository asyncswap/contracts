"""Offline failure checks: never import the broadcasting CLI or contact an RPC."""

import ast
from pathlib import Path
from types import SimpleNamespace
import unittest


class SubmissionSafetyTests(unittest.TestCase):
    def run_send(self, failure=None):
        # Extract only send(): loading the CLI module would parse broadcast arguments.
        tree = ast.parse(Path(__file__).with_name("public_soak.py").read_text())
        chain = next(
            n for n in tree.body if isinstance(n, ast.ClassDef) and n.name == "Chain"
        )
        method = next(
            n for n in chain.body if isinstance(n, ast.FunctionDef) and n.name == "send"
        )
        journal = {"transactions": []}
        calls = []
        tx_hash = "0x" + "ab" * 32

        def cast(*args):
            calls.append(args)
            if args[0] == "calldata":
                return "0x1234"
            if args[0] == "mktx":
                self.assertEqual(
                    args[1:5], ("token", "approve(address,uint256)", "router", 0)
                )
                return "signed-transaction"
            if args[0] == "keccak":
                return tx_hash
            if args[0] == "publish":
                self.assertEqual(journal["transactions"][0]["hash"], tx_hash)
                if failure == "publish":
                    raise TimeoutError("submission response lost")
                return tx_hash
            self.fail(f"Unexpected command {args[0]}")

        def rpc(method, params):
            if method == "eth_gasPrice":
                return "0x1"
            if method == "eth_call":
                return "0x"
            if method == "eth_getTransactionReceipt":
                if failure == "receipt":
                    raise TimeoutError("receipt lookup failed")
                return {
                    "blockNumber": "0x1",
                    "status": "0x1",
                    "gasUsed": "0x100",
                    "effectiveGasPrice": "0x1",
                    "logs": [],
                }
            self.fail(f"Unexpected RPC {method}")

        scope = {
            "cast": cast,
            "monitor_ok": lambda: None,
            "save": lambda: None,
            "evidence": journal,
            "MAX_FEE": 20000000,
            "GAS": 1000000,
            "OWNER": "maker",
            "time": SimpleNamespace(time=lambda: 1, sleep=lambda _: None),
        }
        exec(
            compile(ast.Module(body=[method], type_ignores=[]), "send-only", "exec"),
            scope,
        )
        instance = SimpleNamespace(
            uncertain=False, n=0, nonce=1, c=1301, url="unused", rpc=rpc
        )
        if failure:
            with self.assertRaises(TimeoutError):
                scope["send"](
                    instance,
                    "approve",
                    "token",
                    "approve(address,uint256)",
                    "router",
                    0,
                )
            self.assertTrue(instance.uncertain)
            self.assertNotIn("status", journal["transactions"][0])
        else:
            scope["send"](
                instance, "approve", "token", "approve(address,uint256)", "router", 0
            )
            self.assertFalse(instance.uncertain)
            self.assertEqual(journal["transactions"][0]["status"], 1)
        self.assertEqual(sum(c[0] == "publish" for c in calls), 1)

    def test_submission_timeout_retains_known_hash_and_blocks_cleanup(self):
        self.run_send("publish")

    def test_receipt_timeout_keeps_cleanup_blocked(self):
        self.run_send("receipt")

    def test_confirmation_clears_uncertainty(self):
        self.run_send()


if __name__ == "__main__":
    unittest.main()

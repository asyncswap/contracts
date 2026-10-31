#!/usr/bin/env bun
/** Route an Olive signer to HyperEVM testnet's big or small blocks. */
import { keccak256, recoverTypedDataAddress, type Hex } from "viem";

const rpc = "https://rpc.hyperliquid-testnet.xyz/evm";
const api = "https://api.hyperliquid-testnet.xyz";
const zero = "0x0000000000000000000000000000000000000000" as const;
const [mode, flag] = process.argv.slice(2);
if (!["enable", "disable"].includes(mode) || flag !== "--broadcast") {
  throw new Error("Usage: olive exec <account> -- bun script/hyperevm-big-blocks.ts enable|disable --broadcast");
}
const deployEnv = await Bun.file(new URL("../.env.deploy", import.meta.url)).text().catch(() => "");
function setting(name: string): string | undefined {
  const line = deployEnv.split(/\r?\n/).find(line => line.startsWith(`${name}=`));
  return process.env[name] ?? line?.slice(name.length + 1).replace(/^['"]|['"]$/g, "");
}
const account = setting("DEPLOYER_ACCOUNT");
if (!account) throw new Error("Set DEPLOYER_ACCOUNT to the Olive signer name");

async function runCast(args: string[]): Promise<string> {
  const child = Bun.spawn(["cast", ...args], { stdout: "pipe", stderr: "pipe" });
  const [stdout, stderr, exitCode] = await Promise.all([
    new Response(child.stdout).text(), new Response(child.stderr).text(), child.exited,
  ]);
  if (exitCode !== 0) throw new Error(`cast failed: ${stderr.trim()}`);
  return stdout.trim();
}

const signer = await runCast(["wallet", "address", "--account", account]);
if (!/^0x[0-9a-fA-F]{40}$/.test(signer)) throw new Error("Invalid Olive signer address");
if (setting("DEPLOY_OWNER")?.toLowerCase() !== signer.toLowerCase()) {
  throw new Error("DEPLOY_OWNER must match the Olive signer");
}

const roleResponse = await fetch(`${api}/info`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ type: "userRole", user: signer }),
});
if (!roleResponse.ok || (await roleResponse.json() as { role?: string }).role !== "user") {
  throw new Error(`HyperCore testnet account ${signer} is not active; receive a Core testnet asset first`);
}

const enable = mode === "enable";
const nonce = BigInt(Date.now());
const action = { type: "evmUserModify", usingBigBlocks: enable } as const;
const nonceBytes = new Uint8Array(8);
new DataView(nonceBytes.buffer).setBigUint64(0, nonce, false);
// Hyperliquid signs keccak(msgpack(action) || nonce:uint64be || 0x00 for no vault).
// The action has a fixed two-field map; preserve field order exactly as above.
const bytes = Uint8Array.from([
  0x82, 0xa4, ...new TextEncoder().encode("type"),
  0xad, ...new TextEncoder().encode("evmUserModify"),
  0xae, ...new TextEncoder().encode("usingBigBlocks"), enable ? 0xc3 : 0xc2,
  ...nonceBytes, 0x00,
]);
const connectionId = keccak256(bytes);
const typedData = {
  domain: { name: "Exchange", version: "1", chainId: 1337, verifyingContract: zero },
  types: {
    Agent: [{ name: "source", type: "string" }, { name: "connectionId", type: "bytes32" }],
    EIP712Domain: [
      { name: "name", type: "string" }, { name: "version", type: "string" },
      { name: "chainId", type: "uint256" }, { name: "verifyingContract", type: "address" },
    ],
  },
  primaryType: "Agent",
  message: { source: "b", connectionId },
} as const;
const signatureOutput = await runCast(["wallet", "sign", "--account", account, "--data", JSON.stringify(typedData)]);
const signature = signatureOutput.match(/0x[0-9a-fA-F]{130}/)?.[0] as Hex | undefined;
if (!signature) throw new Error("cast did not return a 65-byte signature");
const recovered = await recoverTypedDataAddress({ ...typedData, signature });
if (recovered.toLowerCase() !== signer.toLowerCase()) throw new Error("Olive signature did not recover to the deployer");
const v = parseInt(signature.slice(130, 132), 16);
const signed = {
  r: signature.slice(0, 66), s: `0x${signature.slice(66, 130)}`,
  v: v < 27 ? v + 27 : v,
};
const response = await fetch(`${api}/exchange`, {
  method: "POST",
  headers: { "content-type": "application/json" },
  body: JSON.stringify({ action, nonce: Number(nonce), signature: signed, vaultAddress: null, expiresAfter: null }),
});
const result = await response.json() as { status?: string; response?: unknown };
if (!response.ok || result.status !== "ok") throw new Error(`HyperCore rejected big-block change: ${JSON.stringify(result)}`);
let reflected = false;
for (let attempt = 0; attempt < 10; attempt++) {
  const state = await fetch(rpc, {
    method: "POST", headers: { "content-type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", id: 1, method: "eth_usingBigBlocks", params: [signer] }),
  }).then(r => r.json() as Promise<{ result?: boolean }>);
  if (state.result === enable) { reflected = true; break; }
  await Bun.sleep(1_000);
}
if (!reflected) throw new Error("HyperCore accepted the action, but RPC has not reflected the setting yet; query eth_usingBigBlocks before deployment");
console.log(`${signer} usingBigBlocks=${enable}`);

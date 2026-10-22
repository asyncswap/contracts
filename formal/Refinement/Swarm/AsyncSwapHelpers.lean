import Mathlib
import Generated.AsyncSwap
import Refinement.Monad

/-!
# AsyncSwap: small internal helpers

Characterizations of internal helpers that the AsyncSwap model inlines from libraries:
`CustomRevert.bubbleUpAndRevertWith`, `Address.{_revert, verifyCallResultFromTarget,
functionCallWithValue, functionCall}`, `SafeERC20.{_callOptionalReturn, safeTransferFrom}`,
`ShortStrings.byteLength`, `EIP712._EIP712Name/_EIP712Version`, `Math.unsignedRoundsUp`,
`Math.mulDiv` (rounding variant), `AsyncFiller._priorityKey`, `AsyncMatching._crosses`,
`AsyncMatching._priceKey`, `RadixPriceTree._bitSet`, `RadixPriceTree._freeNode`.
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.Helpers

variable {σ : Type} (ext : Ext σ)

/-! ## CustomRevert.bubbleUpAndRevertWith -/

/-- It always reverts (the assembly `revert` with the wrapped error), never touching state. -/
theorem bubbleUpAndRevertWith_reverts (c s x : Nat) (env : Env) (w : σ) :
    CustomRevert.bubbleUpAndRevertWith ext c s x env w = .error ⟨"revert"⟩ := rfl

/-! ## Address -/

/-- `_revert` always reverts: it bubbles the return data when there is some, otherwise
`FailedInnerCall`. -/
theorem address_revert_run (rd : List Nat) (env : Env) (w : σ) :
    Address.«_revert» ext rd env w
      = .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Address.«_revert»
  by_cases h : rd.length > 0 <;> simp [h]

/-- A failed call reverts exactly like `_revert`. -/
theorem verifyCallResult_fail (t : Nat) (rd : List Nat) (env : Env) (w : σ) :
    Address.verifyCallResultFromTarget ext t false rd env w
      = .error (if rd.length > 0 then ⟨"revert"⟩ else ⟨"FailedInnerCall"⟩) := by
  unfold Address.verifyCallResultFromTarget
  by_cases h : rd.length > 0 <;> simp [Address.«_revert», h]

/-- A successful call returns its data unchanged, unless it returned nothing from an address
without code (`AddressEmptyCode`). The world is untouched. -/
theorem verifyCallResult_ok (t : Nat) (rd : List Nat) (env : Env) (w : σ) :
    Address.verifyCallResultFromTarget ext t true rd env w
      = if rd.length = 0 ∧ ext.codeLength t = 0 then .error ⟨"AddressEmptyCode"⟩ else .ok (rd, w) := by
  unfold Address.verifyCallResultFromTarget
  by_cases h1 : rd.length = 0 <;> by_cases h2 : ext.codeLength t = 0 <;> simp [h1, h2]

/-- `functionCallWithValue` reverts `AddressInsufficientBalance` when the contract holds less
than `value`. -/
theorem functionCallWithValue_insufficient (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (h : env.balance < v) :
    Address.functionCallWithValue ext t d v env w = .error ⟨"AddressInsufficientBalance"⟩ := by
  simp [Address.functionCallWithValue, h]

/-- Otherwise it is exactly the low-level call followed by `verifyCallResultFromTarget`. -/
theorem functionCallWithValue_eq (t : Nat) (d : List Nat) (v : Nat) (env : Env) (w : σ)
    (h : ¬ env.balance < v) :
    Address.functionCallWithValue ext t d v env w
      = (do let r ← ext.lowCall t v d; Address.verifyCallResultFromTarget ext t r.1 r.2) env w := by
  simp [Address.functionCallWithValue, h]

/-- `functionCall` is `functionCallWithValue` with value `0` (so the balance check never fires). -/
theorem functionCall_eq (t : Nat) (d : List Nat) (env : Env) (w : σ) :
    Address.functionCall ext t d env w
      = (do let r ← ext.lowCall t 0 d; Address.verifyCallResultFromTarget ext t r.1 r.2) env w := by
  have : Address.functionCall ext t d env w = Address.functionCallWithValue ext t d 0 env w := by
    simp [Address.functionCall]
  rw [this, functionCallWithValue_eq ext t d 0 env w (Nat.not_lt_zero _)]

/-! ## SafeERC20 -/

/-- `_callOptionalReturn`: after the call returns data `rd` in world `w'`, it succeeds (writing
nothing more) iff `rd` is empty or its first word decodes to `true`; a non-empty answer that is
`false` reverts `SafeERC20FailedOperation`. -/
theorem callOptionalReturn_after (tok : Nat) (d rd : List Nat) (env : Env) (w w' : σ)
    (hc : Address.functionCall ext tok d env w = .ok (rd, w')) :
    SafeERC20.«_callOptionalReturn» ext tok d env w
      = (if rd.length != 0 then
          (do let x ← abiWordAt rd 0; let b ← abiBool x
              if !b then throw ⟨"SafeERC20FailedOperation"⟩ else pure () : M σ Unit) env w'
        else .ok ((), w')) := by
  unfold SafeERC20.«_callOptionalReturn»
  simp only [run_bind, hc]
  by_cases h : rd.length != 0
  · simp only [h, ite_true]
    simp only [run_bind]
    cases abiWordAt (σ := σ) rd 0 env w' with
    | error e => rfl
    | ok p =>
      obtain ⟨x, w''⟩ := p
      simp only
      cases abiBool (σ := σ) x env w'' with
      | error e => rfl
      | ok q =>
        obtain ⟨b, w3⟩ := q
        cases b <;> simp
  · simp [h]

/-- When the inner call reverts, `_callOptionalReturn` reverts with the same error. -/
theorem callOptionalReturn_call_reverts (tok : Nat) (d : List Nat) (env : Env) (w : σ) (e : Revert)
    (hc : Address.functionCall ext tok d env w = .error e) :
    SafeERC20.«_callOptionalReturn» ext tok d env w = .error e := by
  unfold SafeERC20.«_callOptionalReturn»
  simp [hc]

/-- `safeTransferFrom` is `_callOptionalReturn` on the `transferFrom(from, to, value)` calldata
(selector `0x23b872dd`). -/
theorem safeTransferFrom_eq (tok f t v : Nat) (env : Env) (w : σ) :
    SafeERC20.safeTransferFrom ext tok f t v env w
      = SafeERC20.«_callOptionalReturn» ext tok
          ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [f, t, v]) env w := by
  simp only [SafeERC20.safeTransferFrom, run_bind]
  cases SafeERC20.«_callOptionalReturn» ext tok
          ((wordBytes (0x23b872dd * 2 ^ 224)).take 4 ++ abiEncode [f, t, v]) env w with
  | error e => rfl
  | ok p => rfl

/-! ## ShortStrings / EIP712 -/

/-- `byteLength` returns the low byte when it is at most 31, otherwise reverts
`InvalidShortString`; it never writes. -/
theorem byteLength_run (s : Nat) (env : Env) (w : σ) :
    ShortStrings.byteLength ext s env w
      = if s &&& 0xFF > 31 then .error ⟨"InvalidShortString"⟩ else .ok (s &&& 0xFF, w) := by
  unfold ShortStrings.byteLength
  by_cases h : s &&& 0xFF > 31 <;> simp [h]

theorem byteLength_le (s : Nat) (env : Env) (w w' : σ) (r : Nat)
    (h : ShortStrings.byteLength ext s env w = .ok (r, w')) : r ≤ 31 ∧ w' = w := by
  rw [byteLength_run] at h
  split at h
  · cases h
  · cases h; exact ⟨by omega, rfl⟩

/-- `_EIP712Name` is `toStringWithFallback(_name, _nameFallback)`: it only reads/writes the
`_nameFallback` slot through the opaque library call. -/
theorem eip712Name_eq (env : Env) (w : σ) :
    EIP712.«_EIP712Name» ext env w
      = ext.fn_ShortStrings_toStringWithFallback_9627 (ext.«_name»)
          (do return (ext.get (← get)).«_nameFallback»)
          (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_nameFallback» := x }))
          env w := by
  simp only [EIP712.«_EIP712Name»]

/-- `_EIP712Version` is `toStringWithFallback(_version, _versionFallback)`. -/
theorem eip712Version_eq (env : Env) (w : σ) :
    EIP712.«_EIP712Version» ext env w
      = ext.fn_ShortStrings_toStringWithFallback_9627 (ext.«_version»)
          (do return (ext.get (← get)).«_versionFallback»)
          (fun x => modify fun w => ext.set w (let s := ext.get w; { s with «_versionFallback» := x }))
          env w := by
  simp only [EIP712.«_EIP712Version»]

/-! ## Math -/

/-- `unsignedRoundsUp(r)` is `r % 2 == 1` (Ceil and Expand), never reverts, writes nothing. -/
theorem unsignedRoundsUp_run (r : Nat) (env : Env) (w : σ) :
    Math.unsignedRoundsUp ext r env w = .ok (r % 2 == 1, w) := by
  simp [Math.unsignedRoundsUp, modc]

/-- The rounding `mulDiv` agrees with the shared `mulDivRnd` semantics (floor, plus one when
rounding up and there is a remainder, checked). -/
theorem mulDiv_rounding_eq (x y d r : Nat) (env : Env) (w : σ) :
    Math.mulDiv_11410 ext x y d r env w = mulDivRnd (σ := σ) x y d r env w := by
  unfold Math.mulDiv_11410 mulDivRnd mulDivCeil
  by_cases hd : d = 0
  · simp [mulDivFloor, hd]
  by_cases ho : x * y / d < 2 ^ 256
  · have ho' := ho; norm_num at ho'
    by_cases hr : r % 2 = 1
    · by_cases hm : x * y % d = 0
      · simp [mulDivFloor, hd, ho', hr, hm, Math.unsignedRoundsUp, modc, ymulmod]
      · have : 0 < x * y % d := Nat.pos_of_ne_zero hm
        simp [mulDivFloor, hd, ho', hr, hm, Math.unsignedRoundsUp, modc, ymulmod, this]
    · simp [mulDivFloor, hd, ho', hr, Math.unsignedRoundsUp, modc]
  · have ho' := ho; norm_num at ho'
    simp [mulDivFloor, hd, Nat.not_lt.mpr ho']

/-- The shared floor `mulDiv` never writes. -/
theorem mulDivFloor_frame (x y d : Nat) (env : Env) (w w' : σ) (p : Nat)
    (h : mulDivFloor (σ := σ) x y d env w = .ok (p, w')) : w' = w := by
  unfold mulDivFloor at h
  split_ifs at h <;> cases h; rfl

/-! ## AsyncFiller._priorityKey -/

/-- `_priorityKey(fee, seq) = (uint128(fee) << 64) | (type(uint64).max - seq)`; it panics only
when `seq` exceeds `2^64 - 1`. Never writes. -/
theorem priorityKey_run (f s : Nat) (env : Env) (w : σ) :
    AsyncFiller.«_priorityKey» ext f s env w
      = if s ≤ 2 ^ 64 - 1 then .ok ((shlw 128 f 64) ||| (2 ^ 64 - 1 - s), w)
        else .error (panic "0x11") := by
  unfold AsyncFiller.«_priorityKey» subc
  by_cases h : s ≤ 2 ^ 64 - 1
  · have h' := h; norm_num at h'; simp [h']
  · have h' := h; norm_num at h'; simp [Nat.not_le.mpr h']

/-- For 64-bit fee and sequence the key is `fee * 2^64 + (2^64 - 1 - seq)`. -/
theorem priorityKey_value (f s : Nat) (hf : f < 2 ^ 64) (hs : s ≤ 2 ^ 64 - 1) :
    (shlw 128 f 64) ||| (2 ^ 64 - 1 - s) = f * 2 ^ 64 + (2 ^ 64 - 1 - s) := by
  have hlt : f <<< 64 < 2 ^ 128 := by
    rw [Nat.shiftLeft_eq]
    calc f * 2 ^ 64 < 2 ^ 64 * 2 ^ 64 := Nat.mul_lt_mul_of_pos_right hf (by positivity)
      _ = 2 ^ 128 := by norm_num
  have hb : 2 ^ 64 - 1 - s < 2 ^ 64 := by omega
  unfold shlw
  rw [Nat.mod_eq_of_lt hlt, ← Nat.shiftLeft_add_eq_or_of_lt hb, Nat.shiftLeft_eq]

/-- Priority ordering: with 64-bit fees and sequences, a higher fee always gives a higher key,
and at equal fees the earlier sequence gives the higher key (FIFO). -/
theorem priorityKey_lt_iff (f₁ s₁ f₂ s₂ : Nat) (hf₁ : f₁ < 2 ^ 64) (hf₂ : f₂ < 2 ^ 64)
    (hs₁ : s₁ ≤ 2 ^ 64 - 1) (hs₂ : s₂ ≤ 2 ^ 64 - 1) :
    (shlw 128 f₁ 64) ||| (2 ^ 64 - 1 - s₁) < (shlw 128 f₂ 64) ||| (2 ^ 64 - 1 - s₂)
      ↔ f₁ < f₂ ∨ (f₁ = f₂ ∧ s₂ < s₁) := by
  rw [priorityKey_value f₁ s₁ hf₁ hs₁, priorityKey_value f₂ s₂ hf₂ hs₂]
  generalize hK : (2 : Nat) ^ 64 = K at *
  have hK1 : 0 < K := by subst hK; positivity
  constructor
  · intro h
    rcases lt_trichotomy f₁ f₂ with hlt | heq | hgt
    · exact Or.inl hlt
    · subst heq; right; refine ⟨rfl, ?_⟩; omega
    · exfalso
      have : f₂ * K + K ≤ f₁ * K := by
        have := Nat.mul_le_mul_right K (Nat.succ_le_of_lt hgt); simpa [Nat.succ_mul] using this
      omega
  · rintro (hlt | ⟨rfl, hs⟩)
    · have : f₁ * K + K ≤ f₂ * K := by
        have := Nat.mul_le_mul_right K (Nat.succ_le_of_lt hlt); simpa [Nat.succ_mul] using this
      omega
    · omega

/-! ## AsyncMatching._crosses -/

/-- Different price keys: the buy crosses the sell iff its key is higher; no reads, no writes. -/
theorem crosses_ne (bk sk : Nat) (bg : M σ AsyncFiller.OrderInfo) (bs : AsyncFiller.OrderInfo → M σ Unit)
    (sg : M σ AsyncFiller.OrderInfo) (ss : AsyncFiller.OrderInfo → M σ Unit) (env : Env) (w : σ)
    (h : bk ≠ sk) :
    AsyncMatching.«_crosses» ext bk sk bg bs sg ss env w = .ok (decide (bk > sk), w) := by
  simp [AsyncMatching.«_crosses», h]

/-- Equal price keys: with pure readers returning `b` and `s`, the buy crosses iff
`b.amountIn * s.amountIn / s.amountOutMin ≥ b.amountOutMin` (the `mulDiv` guards aside). -/
theorem crosses_eq (k : Nat) (b s : AsyncFiller.OrderInfo) (bs : AsyncFiller.OrderInfo → M σ Unit)
    (ss : AsyncFiller.OrderInfo → M σ Unit) (env : Env) (w : σ)
    (hd : s.amountOutMin ≠ 0) (ho : b.amountIn * s.amountIn / s.amountOutMin < 2 ^ 256) :
    AsyncMatching.«_crosses» ext k k (pure b) bs (pure s) ss env w
      = .ok (decide (b.amountIn * s.amountIn / s.amountOutMin ≥ b.amountOutMin), w) := by
  have ho' := ho; norm_num at ho'
  simp [AsyncMatching.«_crosses», mulDivFloor, hd, ho']

/-! ## AsyncMatching._priceKey -/

/-- `_priceKey` is the floored `mulDiv` price clamped into `[1, 2^128 - 1]`. -/
theorem priceKey_eq (isBuy : Bool) (a o : Nat) (env : Env) (w : σ) :
    AsyncMatching.«_priceKey» ext isBuy a o env w
      = match mulDivFloor (σ := σ) (if isBuy then a else o) AsyncMatching.PRICE_SCALE
                (if isBuy then o else a) env w with
        | .ok (p, w') => .ok (if p = 0 then 1 else if p > 2 ^ 128 - 1 then 2 ^ 128 - 1 else p % 2 ^ 128, w')
        | .error e => .error e := by
  unfold AsyncMatching.«_priceKey»
  cases isBuy <;> simp only [run_bind, Bool.false_eq_true, ite_false, ite_true] <;>
  · rcases mulDivFloor (σ := σ) _ _ _ env w with e | ⟨p, w'⟩
    · rfl
    · simp only
      split_ifs <;> simp_all <;> omega

/-- The key is always in `[1, 2^128 - 1]`, and `_priceKey` writes nothing. -/
theorem priceKey_range (isBuy : Bool) (a o : Nat) (env : Env) (w w' : σ) (k : Nat)
    (h : AsyncMatching.«_priceKey» ext isBuy a o env w = .ok (k, w')) :
    1 ≤ k ∧ k ≤ 2 ^ 128 - 1 ∧ w' = w := by
  rw [priceKey_eq] at h
  rcases hm : mulDivFloor (σ := σ) (if isBuy then a else o) AsyncMatching.PRICE_SCALE
                (if isBuy then o else a) env w with e | ⟨p, w''⟩
  · rw [hm] at h; cases h
  · rw [hm] at h
    have hw := mulDivFloor_frame _ _ _ env w w'' p hm
    simp only [Except.ok.injEq, Prod.mk.injEq] at h
    obtain ⟨hk, rfl⟩ := h
    refine ⟨?_, ?_, hw⟩ <;> subst hk <;> split_ifs <;> omega

/-! ## RadixPriceTree._bitSet -/

/-- `_bitSet(value, bit)` tests bit `bit` of `value` (for `bit < 128`, the `uint8` range used). -/
theorem bitSet_run (v b : Nat) (hb : b < 128) (env : Env) (w : σ) :
    RadixPriceTree.«_bitSet» ext v b env w = .ok (v.testBit b, w) := by
  have h1 : shlw 128 1 b = 2 ^ b := by
    unfold shlw
    rw [Nat.one_shiftLeft, Nat.mod_eq_of_lt (Nat.pow_lt_pow_right (by norm_num) hb)]
  simp only [RadixPriceTree.«_bitSet», h1, Nat.and_two_pow, run_pure]
  cases v.testBit b <;> simp

/-! ## RadixPriceTree._freeNode -/

/-- Over a storage lens (`get`, `set` with the usual lens laws), `_freeNode(id)` clears node `id`
and pushes `id` onto `freeIds`; nothing else in the tree changes. -/
theorem freeNode_run (get' : σ → RadixPriceTree.Tree) (set' : σ → RadixPriceTree.Tree → σ)
    (hgs : ∀ w t, get' (set' w t) = t) (hss : ∀ w t t', set' (set' w t) t' = set' w t')
    (id : Nat) (env : Env) (w : σ) :
    RadixPriceTree.«_freeNode» ext (do return get' (← get)) (fun x => modify fun w => set' w x) id env w
      = .ok ((), set' w { get' w with nodes := upd (get' w).nodes id default,
                                      freeIds := (get' w).freeIds ++ [id] }) := by
  simp [RadixPriceTree.«_freeNode», hgs, hss]

end AsyncSwap.Swarm.Helpers

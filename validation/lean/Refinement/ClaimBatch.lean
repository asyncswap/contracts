import Mathlib
namespace AsyncSwap.ClaimBatch
/-- Eight pairs, at most four maker credits per pair, and one shared FeeVault key.
The caller must establish the per-pair credit bound and single-numeraire premise. -/
theorem capacity (matchedCount credits : Nat) (hm : matchedCount ≤ 8)
    (hc : credits ≤ 4 * matchedCount + 1) : credits ≤ 33 := by omega

/-- Combining two credits to the same recipient/currency conserves their combined balance.
Distinct sender/recipient and sufficient escrow are explicit premises of this arithmetic model. -/
theorem combined_credit_conserves (escrow recipient first second : Nat)
    (h : first + second ≤ escrow) :
    escrow - (first + second) + (recipient + (first + second)) = escrow + recipient := by omega

/-- A self-credit is net zero individually and need not be accumulated. -/
theorem self_credit (balance amount : Nat) (h : amount ≤ balance) :
    balance - amount + amount = balance := Nat.sub_add_cancel h
end AsyncSwap.ClaimBatch

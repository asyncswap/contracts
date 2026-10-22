import Generated.AsyncSwap
import Refinement.Monad
import Refinement.Swarm.AsyncFillerRemoveQueue
import Refinement.Swarm.AsyncSwapReduceAfterMatch
import Refinement.Swarm.AsyncSwapBestOrder

/-!
# Named specs for the order book's opaque library functions

formal-ast can't write through a conditional storage pointer
(`PriceLevel storage priceLevel = isBuy ? book.bidLevels[p] : book.askLevels[p]`), so it leaves four
`AsyncFiller` functions (src/libraries/AsyncFiller.sol) opaque:

* `_remove(self, book, id)` — `ext.fn_AsyncFiller_remove_6902`
* `_append(self, book, id)` — `ext.fn_AsyncFiller_append_6737`
* `bestAtPrice(book, isBuy, price)` — `ext.fn_AsyncFiller_bestAtPrice_6051`
* `level(book, isBuy, price)` — `ext.fn_AsyncFiller_level_6002`

Each gets one named assumption here (`RemoveSpec`, `AppendSpec`, `BestAtPriceSpec`, `LevelSpec`),
stated over any storage pointers that are plain reads and writes of two disjoint parts of the world
(`ReduceAfterMatch.Lawful` for `self`/`book`, `ReadsBook` for a read-only `book`), which is how every
caller passes them (`lawful_canonical`). The specs say what the bytecode does, field by field, and
`test/formal/SpecBook.t.sol` checks every field on the compiled library (`AsyncFillerBookHarness`).

* **`_remove`** behaves as the hand-written `unlinkOrders`/`unlinkLevel` of
  `AsyncFillerRemoveQueue.lean` in FIFO mode (`removeState`/`removeBook`): it reverts exactly when
  `RemoveOk` fails (with `removeErr`), and otherwise writes only through the two pointers
  (`Writes`), unlinks `id` (FIFO) or drops its priority key (priority mode, `removeTree` and
  `priorityOrderIds[key] := 0`), decrements the level and book counters, and when the level
  empties removes the price from its side's tree and clears the level (`clearLevel`: Solidity's
  `delete` of a struct zeroes its value fields and the `freeIds` array, not its mappings). So
  `queue_unlink` applies to the opaque function: `remove_queue`.
* **`_append`** links `id` at the tail of its level (FIFO: `appendOrders`/`appendLevel`) or keys it
  by `prioKey` in the level's priority tree, inserts the price into its side's tree when the level
  was empty (`TreeInserted`), and bumps both counters; `append_queue` is the FIFO queue result.
* **`bestAtPrice`** / **`level`** are read-only and return `bestAtPriceOf` / `levelOf`
  (FIFO: the level's `head`/`tail`/`orderCount`; priority mode: the ids stored under the tree's
  highest/lowest key, found by the same walk as `RadixPriceTree.best`, `BestOrder.firstLeaf`).

`orderingMode` is an enum: a stored value ≥ 2 makes every one of these panic `0x21` when it is
read (the model's `orderingMode` is an unbounded `Nat`). Loops are bounded by `loopBound` as in the
model (the bytecode's stand-in is gas).
-/

open FormalAst Refinement

namespace AsyncSwap.Swarm.SpecBook

open AsyncSwap.Swarm.ReduceAfterMatch (Lawful)
open AsyncSwap.Swarm.FillerRemove (unlinkOrders unlinkLevel Queue Seg)

variable {σ : Type}

/-! ## The book through an order's side and price -/

/-- `isBuy ? book.bidLevels : book.askLevels`. -/
def levels (B : AsyncFiller.Book) (isBuy : Bool) : Nat → AsyncFiller.PriceLevel :=
  if isBuy then B.bidLevels else B.askLevels

/-- `isBuy ? book.bids : book.asks`. -/
def side (B : AsyncFiller.Book) (isBuy : Bool) : RadixPriceTree.Tree :=
  if isBuy then B.bids else B.asks

def setLevel (B : AsyncFiller.Book) (isBuy : Bool) (p : Nat) (L : AsyncFiller.PriceLevel) :
    AsyncFiller.Book :=
  if isBuy then { B with bidLevels := upd B.bidLevels p L }
  else { B with askLevels := upd B.askLevels p L }

def setSide (B : AsyncFiller.Book) (isBuy : Bool) (T : RadixPriceTree.Tree) : AsyncFiller.Book :=
  if isBuy then { B with bids := T } else { B with asks := T }

/-- The order's own level. -/
def levelOfOrder (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : AsyncFiller.PriceLevel :=
  levels B (S.orders id).isBuy (S.orders id).price

@[simp] theorem levels_setLevel (B : AsyncFiller.Book) (b : Bool) (p : Nat) (L : AsyncFiller.PriceLevel)
    (q : Nat) : levels (setLevel B b p L) b q = if q = p then L else levels B b q := by
  cases b <;> simp [levels, setLevel, upd]

@[simp] theorem levels_setSide (B : AsyncFiller.Book) (b c : Bool) (T : RadixPriceTree.Tree) :
    levels (setSide B b T) c = levels B c := by
  cases b <;> cases c <;> rfl

@[simp] theorem levels_openOrderCount (B : AsyncFiller.Book) (b : Bool) (n : Nat) :
    levels { B with openOrderCount := n } b = levels B b := by
  cases b <;> rfl

/-! ## Storage pointers -/

/-- The read-only `Book storage book` pointer of a view: its getter reads `bg w` and leaves the
world alone (the setter is never called). -/
def ReadsBook (book_get : M σ AsyncFiller.Book) (bg : σ → AsyncFiller.Book) : Prop :=
  ∀ env w, book_get env w = .ok (bg w, w)

/-- `w'` is `w` after a sequence of writes through the `self` (`ss`) and `book` (`bs`) pointers,
and nothing else: the opaque function writes no other storage. -/
inductive Writes (ss : σ → AsyncFiller.State_ → σ) (bs : σ → AsyncFiller.Book → σ) : σ → σ → Prop
  | refl (w : σ) : Writes ss bs w w
  | self {w w1 : σ} (x : AsyncFiller.State_) : Writes ss bs w w1 → Writes ss bs w (ss w1 x)
  | book {w w1 : σ} (b : AsyncFiller.Book) : Writes ss bs w w1 → Writes ss bs w (bs w1 b)

/-- A pure result, run in world `w` without changing it. -/
def liftR {α : Type} (r : Except Revert α) (w : σ) : Except Revert (α × σ) :=
  match r with
  | .ok a => .ok (a, w)
  | .error e => .error e

theorem liftR_ok {α : Type} {r : Except Revert α} {w w' : σ} {a : α}
    (h : liftR r w = .ok (a, w')) : r = .ok a ∧ w' = w := by
  cases r with
  | error e => cases h
  | ok b => simp only [liftR, Except.ok.injEq, Prod.mk.injEq] at h; exact ⟨by rw [h.1], h.2.symm⟩

/-! ### The pointers every caller passes: `asyncOrders[pid]` and `priceBooks[pid]` -/

def cg (ext : Ext σ) (pid : Nat) (w : σ) : AsyncFiller.State_ := (ext.get w).asyncOrders pid
def css (ext : Ext σ) (pid : Nat) (w : σ) (x : AsyncFiller.State_) : σ :=
  ext.set w { ext.get w with asyncOrders := upd (ext.get w).asyncOrders pid x }
def cbg (ext : Ext σ) (pid : Nat) (w : σ) : AsyncFiller.Book := (ext.get w).priceBooks pid
def cbs (ext : Ext σ) (pid : Nat) (w : σ) (x : AsyncFiller.Book) : σ :=
  ext.set w { ext.get w with priceBooks := upd (ext.get w).priceBooks pid x }

/-- Any accessors that run as plain reads/writes of `asyncOrders[pid]`/`priceBooks[pid]` (every
caller's `selfGet`/`selfSet`/`bookGet`/`bookSet`, each provable by `rfl`) are `Lawful` for the
canonical lenses, given `get ∘ set = id`. -/
theorem lawful_canonical (ext : Ext σ) (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat)
    {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
    {bg : M σ AsyncFiller.Book} {bs : AsyncFiller.Book → M σ Unit}
    (h1 : ∀ env w, sg env w = .ok (cg ext pid w, w))
    (h2 : ∀ x env w, ss x env w = .ok ((), css ext pid w x))
    (h3 : ∀ env w, bg env w = .ok (cbg ext pid w, w))
    (h4 : ∀ x env w, bs x env w = .ok ((), cbs ext pid w x)) :
    Lawful sg ss bg bs (cg ext pid) (css ext pid) (cbg ext pid) (cbs ext pid) where
  hsg := h1
  hss := h2
  hbg := h3
  hbs := h4
  hgss := by intro w x; simp [cg, css, hget, upd_same]
  hbgbs := by intro w b; simp [cbg, cbs, hget, upd_same]
  hgbs := by intro w b; simp [cg, cbs, hget]
  hbgss := by intro w x; simp [cbg, css, hget]

/-- **Frame of the canonical pointers.** Writes through `asyncOrders[pid]`/`priceBooks[pid]` keep
every other pool, the nonces, the owners, the transient slots and the EIP-712 fallbacks. -/
theorem writes_frame (ext : Ext σ) (hget : ∀ w s, ext.get (ext.set w s) = s) (pid : Nat) {w w' : σ}
    (h : Writes (css ext pid) (cbs ext pid) w w') :
    (ext.get w').nonceUsed = (ext.get w).nonceUsed ∧ (ext.get w').owner = (ext.get w).owner ∧
    (ext.get w').pendingOwner = (ext.get w).pendingOwner ∧
    (ext.get w').transient = (ext.get w).transient ∧
    (ext.get w').«_nameFallback» = (ext.get w).«_nameFallback» ∧
    (ext.get w').«_versionFallback» = (ext.get w).«_versionFallback» ∧
    (∀ q, q ≠ pid → (ext.get w').asyncOrders q = (ext.get w).asyncOrders q ∧
      (ext.get w').priceBooks q = (ext.get w).priceBooks q) := by
  induction h with
  | refl => exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, fun _ _ => ⟨rfl, rfl⟩⟩
  | self x _ ih =>
    obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := ih
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, fun q hq => ?_⟩ <;> simp only [css, hget] <;> try assumption
    simp only [upd, hq, ite_false]; exact h7 q hq
  | book b _ ih =>
    obtain ⟨h1, h2, h3, h4, h5, h6, h7⟩ := ih
    refine ⟨?_, ?_, ?_, ?_, ?_, ?_, fun q hq => ?_⟩ <;> simp only [cbs, hget] <;> try assumption
    simp only [upd, hq, ite_false]; exact h7 q hq

/-! ## Reads: `bestAtPrice` and `level` -/

/-- `RadixPriceTree.best(highest)` as a pure function: `(false, 0)` on an empty tree, else the
price of the first leaf on the walk from the root (right for `highest`, left otherwise). -/
def bestOf (T : RadixPriceTree.Tree) (highest : Bool) : Except Revert (Bool × Nat) :=
  if T.root = 0 then .ok (false, 0)
  else match BestOrder.firstLeaf T highest loopBound T.root with
    | some c => .ok (true, (T.nodes c).price)
    | none => .error ⟨"loop bound"⟩

/-- What `bestAtPrice(book, isBuy, price)` returns: FIFO, the level's `head`; priority mode, the
id stored under the level tree's highest key (`priorityOrderIds[0]` when the tree is empty). -/
def bestAtPriceOf (B : AsyncFiller.Book) (isBuy : Bool) (price : Nat) : Except Revert Nat :=
  let L := levels B isBuy price
  if B.orderingMode = 0 then .ok L.head
  else if B.orderingMode = 1 then
    match bestOf L.priorityOrders true with
    | .ok r => .ok (L.priorityOrderIds r.2)
    | .error e => .error e
  else .error (panic "0x21")

/-- `level` in priority mode: the ids under the highest and lowest keys (`0` for an empty tree),
and the count. -/
def levelPrio (L : AsyncFiller.PriceLevel) : Except Revert (Nat × Nat × Nat) :=
  match bestOf L.priorityOrders true, bestOf L.priorityOrders false with
  | .ok (hh, hk), .ok (ht, tk) =>
    .ok (if hh then L.priorityOrderIds hk else 0, if ht then L.priorityOrderIds tk else 0,
      L.orderCount)
  | .error e, _ => .error e
  | .ok _, .error e => .error e

/-- What `level(book, isBuy, price)` returns. -/
def levelOf (B : AsyncFiller.Book) (isBuy : Bool) (price : Nat) : Except Revert (Nat × Nat × Nat) :=
  let L := levels B isBuy price
  if B.orderingMode = 0 then .ok (L.head, L.tail, L.orderCount)
  else if B.orderingMode = 1 then levelPrio L
  else .error (panic "0x21")

/-- **Named assumption for `AsyncFiller.bestAtPrice`** (`ext.fn_AsyncFiller_bestAtPrice_6051`), a
`view`: for any read-only book pointer, in FIFO mode it returns the level's head, in priority mode
the id under the level tree's highest key, and an out-of-range mode byte panics `0x21`; in no case
does it write. -/
structure BestAtPriceSpec (ext : Ext σ) : Prop where
  fifo : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      (bg w).orderingMode = 0 →
      ext.fn_AsyncFiller_bestAtPrice_6051 bget bset isBuy price env w =
        .ok ((levels (bg w) isBuy price).head, w)
  priority : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      (bg w).orderingMode = 1 →
      ext.fn_AsyncFiller_bestAtPrice_6051 bget bset isBuy price env w =
        liftR (match bestOf (levels (bg w) isBuy price).priorityOrders true with
          | .ok r => .ok ((levels (bg w) isBuy price).priorityOrderIds r.2)
          | .error e => .error e) w
  badMode : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      2 ≤ (bg w).orderingMode →
      ext.fn_AsyncFiller_bestAtPrice_6051 bget bset isBuy price env w = .error (panic "0x21")

/-- **Named assumption for `AsyncFiller.level`** (`ext.fn_AsyncFiller_level_6002`), a `view`. -/
structure LevelSpec (ext : Ext σ) : Prop where
  fifo : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      (bg w).orderingMode = 0 →
      ext.fn_AsyncFiller_level_6002 bget bset isBuy price env w =
        .ok (((levels (bg w) isBuy price).head, (levels (bg w) isBuy price).tail,
          (levels (bg w) isBuy price).orderCount), w)
  priority : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      (bg w).orderingMode = 1 →
      ext.fn_AsyncFiller_level_6002 bget bset isBuy price env w =
        liftR (levelPrio (levels (bg w) isBuy price)) w
  badMode : ∀ {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {bg : σ → AsyncFiller.Book}, ReadsBook bget bg → ∀ (isBuy : Bool) (price : Nat) env w,
      2 ≤ (bg w).orderingMode →
      ext.fn_AsyncFiller_level_6002 bget bset isBuy price env w = .error (panic "0x21")

section reads
variable {ext : Ext σ} {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
  {bg : σ → AsyncFiller.Book}

/-- `bestAtPrice` is exactly `bestAtPriceOf` on the book its pointer reads, run without writing. -/
theorem BestAtPriceSpec.run (h : BestAtPriceSpec ext) (hb : ReadsBook bget bg) (isBuy : Bool)
    (price : Nat) (env : Env) (w : σ) :
    ext.fn_AsyncFiller_bestAtPrice_6051 bget bset isBuy price env w =
      liftR (bestAtPriceOf (bg w) isBuy price) w := by
  by_cases h0 : (bg w).orderingMode = 0
  · rw [h.fifo hb isBuy price env w h0]; simp [bestAtPriceOf, h0, liftR]
  · by_cases h1 : (bg w).orderingMode = 1
    · rw [h.priority hb isBuy price env w h1]; simp [bestAtPriceOf, h1]
    · rw [h.badMode hb isBuy price env w (by omega)]; simp [bestAtPriceOf, h0, h1, liftR]

/-- **Read-only.** A successful `bestAtPrice` leaves the world unchanged. -/
theorem BestAtPriceSpec.readOnly (h : BestAtPriceSpec ext) (hb : ReadsBook bget bg) {isBuy : Bool}
    {price : Nat} {env : Env} {w w' : σ} {id : Nat}
    (hr : ext.fn_AsyncFiller_bestAtPrice_6051 bget bset isBuy price env w = .ok (id, w')) :
    w' = w := by
  rw [h.run hb] at hr; exact (liftR_ok hr).2

/-- `level` is exactly `levelOf` on the book its pointer reads, run without writing. -/
theorem LevelSpec.run (h : LevelSpec ext) (hb : ReadsBook bget bg) (isBuy : Bool) (price : Nat)
    (env : Env) (w : σ) :
    ext.fn_AsyncFiller_level_6002 bget bset isBuy price env w =
      liftR (levelOf (bg w) isBuy price) w := by
  by_cases h0 : (bg w).orderingMode = 0
  · rw [h.fifo hb isBuy price env w h0]; simp [levelOf, h0, liftR]
  · by_cases h1 : (bg w).orderingMode = 1
    · rw [h.priority hb isBuy price env w h1]; simp [levelOf, h1]
    · rw [h.badMode hb isBuy price env w (by omega)]; simp [levelOf, h0, h1, liftR]

/-- **Read-only.** A successful `level` leaves the world unchanged. -/
theorem LevelSpec.readOnly (h : LevelSpec ext) (hb : ReadsBook bget bg) {isBuy : Bool}
    {price : Nat} {env : Env} {w w' : σ} {r : Nat × Nat × Nat}
    (hr : ext.fn_AsyncFiller_level_6002 bget bset isBuy price env w = .ok (r, w')) : w' = w := by
  rw [h.run hb] at hr; exact (liftR_ok hr).2

end reads

/-! ## `_remove` -/

/-- When `_remove(id)` succeeds: a valid mode byte; in priority mode the order's key is in its
level's tree; both counters are nonzero; and when the level empties its price is in the side's
tree. -/
def RemoveOk (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : Prop :=
  let o := S.orders id
  let L := levels B o.isBuy o.price
  B.orderingMode < 2 ∧ (B.orderingMode = 1 → L.priorityOrders.leaves o.priorityKey ≠ 0) ∧
    L.orderCount ≠ 0 ∧ B.openOrderCount ≠ 0 ∧
    (L.orderCount = 1 → (side B o.isBuy).leaves o.price ≠ 0)

instance (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : Decidable (RemoveOk S B id) := by
  unfold RemoveOk; infer_instance

/-- The revert of a failing `_remove`, the first failing check in code order. -/
def removeErr (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : Revert :=
  let o := S.orders id
  let L := levels B o.isBuy o.price
  if 2 ≤ B.orderingMode then panic "0x21"
  else if B.orderingMode = 1 ∧ L.priorityOrders.leaves o.priorityKey = 0 then ⟨"PriceLevelMissing"⟩
  else if L.orderCount = 0 then panic "0x11"
  else if B.openOrderCount = 0 then panic "0x11"
  else ⟨"PriceLevelMissing"⟩

/-- Solidity's `delete` of a `PriceLevel`: value fields and the tree's `root`/`nextNodeId`/`freeIds`
zeroed; the `nodes`/`leaves`/`priorityOrderIds` mappings are left as they are. -/
def clearLevel (L : AsyncFiller.PriceLevel) : AsyncFiller.PriceLevel :=
  { L with head := 0, tail := 0, orderCount := 0,
           priorityOrders := { L.priorityOrders with root := 0, nextNodeId := 0, freeIds := [] } }

/-- The order's level after the unlink (FIFO) or key removal (priority) and the decrement. -/
def remLevel (B : AsyncFiller.Book) (o : AsyncFiller.OrderInfo) : AsyncFiller.PriceLevel :=
  let L := levels B o.isBuy o.price
  let L1 := if B.orderingMode = 1 then
      { L with priorityOrders := Remove.removeTree L.priorityOrders o.priorityKey,
               priorityOrderIds := upd L.priorityOrderIds o.priorityKey 0 }
    else unlinkLevel L o
  { L1 with orderCount := L.orderCount - 1 }

/-- `self` after `_remove(id)`: FIFO unlinks `id` from its neighbours; priority mode writes no order. -/
def removeState (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : AsyncFiller.State_ :=
  if B.orderingMode = 1 then S else { S with orders := unlinkOrders S.orders id }

/-- `book` after `_remove(id)`. -/
def removeBook (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : AsyncFiller.Book :=
  let o := S.orders id
  let L1 := remLevel B o
  let B1 := { B with openOrderCount := B.openOrderCount - 1 }
  if L1.orderCount = 0 then
    setLevel (setSide B1 o.isBuy (Remove.removeTree (side B o.isBuy) o.price)) o.isBuy o.price
      (clearLevel L1)
  else setLevel B1 o.isBuy o.price L1

/-- **Named assumption for `AsyncFiller._remove`** (`ext.fn_AsyncFiller_remove_6902`), for any
lawful `self`/`book` pointers:
* `reverts`: it reverts exactly when `RemoveOk` fails, with `removeErr`;
* `progress`: otherwise it succeeds;
* `post`: a success wrote only through the two pointers and left `removeState`/`removeBook`. -/
structure RemoveSpec (ext : Ext σ) : Prop where
  reverts : ∀ {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
      {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
      {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ},
      Lawful sg ss bget bset g s bg bs → ∀ (id : Nat) env w, ¬ RemoveOk (g w) (bg w) id →
      ext.fn_AsyncFiller_remove_6902 sg ss bget bset id env w = .error (removeErr (g w) (bg w) id)
  progress : ∀ {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
      {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
      {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ},
      Lawful sg ss bget bset g s bg bs → ∀ (id : Nat) env w, RemoveOk (g w) (bg w) id →
      ∃ w', ext.fn_AsyncFiller_remove_6902 sg ss bget bset id env w = .ok ((), w')
  post : ∀ {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
      {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
      {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ},
      Lawful sg ss bget bset g s bg bs → ∀ (id : Nat) env w w',
      ext.fn_AsyncFiller_remove_6902 sg ss bget bset id env w = .ok ((), w') →
      Writes s bs w w' ∧ g w' = removeState (g w) (bg w) id ∧ bg w' = removeBook (g w) (bg w) id

/-! ## `_append` -/

/-- `_priorityKey(uint64(paidPriorityFee(order)), order.sequence)`: the paid bid in the high 64
bits, `2^64 − 1 − sequence` in the low 64. -/
def prioKey (o : AsyncFiller.OrderInfo) : Nat :=
  (if o.priorityFeeEscrowed then o.priorityFee else 0) % 2 ^ 64 * 2 ^ 64 + (2 ^ 64 - 1 - o.sequence)

/-- `RadixPriceTree.insert(k)`'s footprint on `leaves`: nothing changes if `k` was present; every
other key's leaf is kept; and `k` gets a nonzero leaf unless a `0` sits on the free list. -/
structure TreeInserted (t t' : RadixPriceTree.Tree) (k : Nat) : Prop where
  present : t.leaves k ≠ 0 → t' = t
  others : ∀ p, p ≠ k → t'.leaves p = t.leaves p
  added : 0 ∉ t.freeIds → t'.leaves k ≠ 0

/-- FIFO `_append(id)` on the orders: `id` joins behind the old tail with no successor, and the
old tail (if any) points at it. -/
def appendOrders (os : Nat → AsyncFiller.OrderInfo) (L : AsyncFiller.PriceLevel) (id : Nat) :
    Nat → AsyncFiller.OrderInfo :=
  let os1 := upd os id { os id with previous := L.tail, next := 0 }
  if L.tail = 0 then os1 else upd os1 L.tail { os1 L.tail with next := id }

/-- FIFO `_append(id)` on the level: `id` becomes the tail (and the head of an empty queue). -/
def appendLevel (L : AsyncFiller.PriceLevel) (id : Nat) : AsyncFiller.PriceLevel :=
  { L with head := if L.tail = 0 then id else L.head, tail := id, orderCount := L.orderCount + 1 }

/-- Priority `_append(id)` on the level: key `k` in the tree `T2`, `priorityOrderIds[k] := id`. -/
def appendPrioLevel (L : AsyncFiller.PriceLevel) (T2 : RadixPriceTree.Tree) (k id : Nat) :
    AsyncFiller.PriceLevel :=
  { L with priorityOrders := T2, priorityOrderIds := upd L.priorityOrderIds k id,
           orderCount := L.orderCount + 1 }

/-- `self` after `_append(id)`. -/
def appendState (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) : AsyncFiller.State_ :=
  let o := S.orders id
  if B.orderingMode = 1 then { S with orders := upd S.orders id { o with priorityKey := prioKey o } }
  else { S with orders := appendOrders S.orders (levels B o.isBuy o.price) id }

/-- `book` after `_append(id)`, with the side's tree `T1` and the level's priority tree `T2`. -/
def appendBook (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat)
    (T1 T2 : RadixPriceTree.Tree) : AsyncFiller.Book :=
  let o := S.orders id
  let L := levels B o.isBuy o.price
  setLevel (setSide { B with openOrderCount := B.openOrderCount + 1 } o.isBuy T1) o.isBuy o.price
    (if B.orderingMode = 1 then appendPrioLevel L T2 (prioKey o) id else appendLevel L id)

/-- **Named assumption for `AsyncFiller._append`** (`ext.fn_AsyncFiller_append_6737`), for any
lawful `self`/`book` pointers:
* `post`: a success had a valid mode byte and room in both counters (uint32/uint64), wrote only
  through the two pointers, and left `appendState`/`appendBook`, where the side's tree got the
  price inserted when the level was empty (`T1`) and, in priority mode, the level's tree got the
  order's key (`T2`);
* `progress`: in FIFO mode, appending to a non-empty level with room in both counters succeeds. -/
structure AppendSpec (ext : Ext σ) : Prop where
  post : ∀ {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
      {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
      {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ},
      Lawful sg ss bget bset g s bg bs → ∀ (id : Nat) env w w',
      ext.fn_AsyncFiller_append_6737 sg ss bget bset id env w = .ok ((), w') →
      let S := g w
      let B := bg w
      let o := S.orders id
      let L := levels B o.isBuy o.price
      B.orderingMode < 2 ∧ L.orderCount + 1 < 2 ^ 32 ∧ B.openOrderCount + 1 < 2 ^ 64 ∧
      Writes s bs w w' ∧
      ∃ T1 T2,
        (if L.orderCount = 0 then TreeInserted (side B o.isBuy) T1 o.price
         else T1 = side B o.isBuy) ∧
        (if B.orderingMode = 1 then TreeInserted L.priorityOrders T2 (prioKey o)
         else T2 = L.priorityOrders) ∧
        g w' = appendState S B id ∧ bg w' = appendBook S B id T1 T2
  progress : ∀ {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
      {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
      {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
      {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ},
      Lawful sg ss bget bset g s bg bs → ∀ (id : Nat) env w,
      let o := (g w).orders id
      let L := levels (bg w) o.isBuy o.price
      (bg w).orderingMode = 0 → L.orderCount ≠ 0 → L.orderCount + 1 < 2 ^ 32 →
      (bg w).openOrderCount + 1 < 2 ^ 64 →
      ∃ w', ext.fn_AsyncFiller_append_6737 sg ss bget bset id env w = .ok ((), w')

/-! ## Bridge lemmas -/

section bridge
variable {ext : Ext σ} {sg : M σ AsyncFiller.State_} {ss : AsyncFiller.State_ → M σ Unit}
  {bget : M σ AsyncFiller.Book} {bset : AsyncFiller.Book → M σ Unit}
  {g : σ → AsyncFiller.State_} {s : σ → AsyncFiller.State_ → σ}
  {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}

/-- `_remove` succeeds exactly when `RemoveOk` holds. -/
theorem RemoveSpec.ok_iff (h : RemoveSpec ext) (L : Lawful sg ss bget bset g s bg bs) (id : Nat)
    (env : Env) (w : σ) :
    (∃ w', ext.fn_AsyncFiller_remove_6902 sg ss bget bset id env w = .ok ((), w')) ↔
      RemoveOk (g w) (bg w) id := by
  constructor
  · rintro ⟨w', hw⟩
    by_contra hn
    rw [h.reverts L id env w hn] at hw; cases hw
  · exact h.progress L id env w

/-- In priority mode `_remove` writes no order record. -/
theorem removeState_prio (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat)
    (hm : B.orderingMode = 1) : removeState S B id = S := by simp [removeState, hm]

/-- `_remove` keeps every field of every order except `previous`/`next`. -/
theorem removeState_linksOnly (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id : Nat) :
    FillerRemove.LinksOnly S.orders (removeState S B id).orders ∧
      (removeState S B id).poolManager = S.poolManager ∧
      (removeState S B id).numeraire = S.numeraire ∧ (removeState S B id).feeVault = S.feeVault ∧
      (removeState S B id).isExecutor = S.isExecutor := by
  unfold removeState
  split
  · exact ⟨FillerRemove.linksOnly_refl _, rfl, rfl, rfl, rfl⟩
  · exact ⟨FillerRemove.unlink_linksOnly _ _, rfl, rfl, rfl, rfl⟩

/-- FIFO `_append` writes only `previous`/`next`. -/
theorem appendOrders_linksOnly (os : Nat → AsyncFiller.OrderInfo) (L : AsyncFiller.PriceLevel)
    (id : Nat) : FillerRemove.LinksOnly os (appendOrders os L id) := by
  unfold appendOrders
  split
  · exact FillerRemove.linksOnly_upd (FillerRemove.linksOnly_refl os) _ _ _
  · exact FillerRemove.linksOnly_upd
      (FillerRemove.linksOnly_upd (FillerRemove.linksOnly_refl os) _ _ _) _ _ _

/-- `_append` keeps every field of every order except `previous`/`next`/`priorityKey`; in particular
the escrow flag, amounts, owner, price and sequence. -/
theorem appendState_keeps (S : AsyncFiller.State_) (B : AsyncFiller.Book) (id x : Nat) :
    let o' := (appendState S B id).orders x
    let o := S.orders x
    o'.owner = o.owner ∧ o'.amountIn = o.amountIn ∧ o'.amountOutMin = o.amountOutMin ∧
      o'.price = o.price ∧ o'.isBuy = o.isBuy ∧ o'.zeroForOne = o.zeroForOne ∧
      o'.sequence = o.sequence ∧ o'.priorityFee = o.priorityFee ∧
      o'.priorityFeeEscrowed = o.priorityFeeEscrowed := by
  intro o' o
  simp only [o', o]
  unfold appendState
  split
  · by_cases hx : x = id
    · subst hx; simp [upd]
    · simp [upd, hx]
  · simp only
    rw [appendOrders_linksOnly S.orders _ id x]
    exact ⟨rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl, rfl⟩

end bridge

/-! ## The FIFO queue through the opaque functions -/

/-- **`_remove` unlinks exactly that id from its queue (FIFO).** If the order's level holds the
queue `xs ∋ id`, a successful `_remove` leaves the level (cleared when it held only `id`) holding
`xs.erase id`. `queue_unlink` of `AsyncFillerRemoveQueue.lean`, now about the opaque function. -/
theorem remove_queue {ext : Ext σ} (h : RemoveSpec ext) {sg : M σ AsyncFiller.State_}
    {ss : AsyncFiller.State_ → M σ Unit} {bget : M σ AsyncFiller.Book}
    {bset : AsyncFiller.Book → M σ Unit} {g : σ → AsyncFiller.State_}
    {s : σ → AsyncFiller.State_ → σ} {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}
    (L : Lawful sg ss bget bset g s bg bs) (id : Nat) (env : Env) (w w' : σ) {xs : List Nat}
    (hm : (bg w).orderingMode = 0)
    (hq : Queue (g w).orders (levelOfOrder (g w) (bg w) id) xs) (hid : id ∈ xs)
    (hr : ext.fn_AsyncFiller_remove_6902 sg ss bget bset id env w = .ok ((), w')) :
    Queue (g w').orders
      (levels (bg w') ((g w).orders id).isBuy ((g w).orders id).price) (xs.erase id) := by
  obtain ⟨-, hS, hB⟩ := h.post L id env w w' hr
  simp only [levelOfOrder] at hq
  have hu := FillerRemove.queue_unlink hq hid
  have hm1 : (bg w).orderingMode ≠ 1 := by omega
  rw [hS, hB]
  simp only [removeState, hm1, ite_false]
  simp only [removeBook, remLevel, hm1, ite_false]
  split
  · rename_i h0
    simp only [levels_setLevel, levels_setSide, levels_openOrderCount, ite_true]
    have hlen : (xs.erase id).length = 0 := by
      rw [← hu.count]; simpa using h0
    have he : xs.erase id = [] := List.eq_nil_of_length_eq_zero hlen
    rw [he]
    exact ⟨List.nodup_nil, by simp, rfl, rfl, rfl, trivial⟩
  · simp only [levels_setLevel, levels_openOrderCount, ite_true]
    exact hu

theorem seg_upd_out (os : Nat → AsyncFiller.OrderInfo) (k : Nat) (v : AsyncFiller.OrderInfo) :
    ∀ (p : Nat) (xs : List Nat) (q : Nat), k ∉ xs → Seg os p xs q → Seg (upd os k v) p xs q
  | _, [], _, _, _ => trivial
  | p, x :: r, q, hk, hs => by
      simp only [Seg] at hs ⊢
      have hx : x ≠ k := fun e => hk (by simp [e])
      refine ⟨by rw [upd_other _ _ _ _ hx]; exact hs.1, by rw [upd_other _ _ _ _ hx]; exact hs.2.1,
        seg_upd_out os k v x r q (fun h => hk (List.mem_cons_of_mem _ h)) hs.2.2⟩

/-- Writing an order outside the queue keeps the queue. -/
theorem queue_upd_out {os : Nat → AsyncFiller.OrderInfo} {L : AsyncFiller.PriceLevel}
    {xs : List Nat} (hq : Queue os L xs) {k : Nat} (hk : k ∉ xs) (v : AsyncFiller.OrderInfo) :
    Queue (upd os k v) L xs :=
  ⟨hq.nodup, hq.nz, hq.head, hq.tail, hq.count, seg_upd_out os k v 0 xs 0 hk hq.seg⟩

/-- **FIFO `_append` puts the id at the back of the queue** (pure form). -/
theorem queue_append {os : Nat → AsyncFiller.OrderInfo} {L : AsyncFiller.PriceLevel}
    {xs : List Nat} {id : Nat} (hq : Queue os L xs) (hid : id ∉ xs) (h0 : id ≠ 0) :
    Queue (appendOrders os L id) (appendLevel L id) (xs ++ [id]) := by
  obtain ⟨hnd, hnz, hhd, htl, hct, hseg⟩ := hq
  have htail : L.tail = 0 ∨ L.tail ∈ xs := by
    rw [htl]; rcases FillerRemove.getLastD_cases xs with h | h
    · left; subst h; rfl
    · right; exact h
  have hti : L.tail ≠ id := by
    rcases htail with h | h
    · rw [h]; exact Ne.symm h0
    · intro e; rw [e] at h; exact hid h
  have hnext : ∀ x, (appendOrders os L id x).next =
      if x = id then (if L.tail = id then id else 0)
      else if L.tail ≠ 0 ∧ x = L.tail then id else (os x).next := by
    intro x
    simp only [appendOrders]
    by_cases ht0 : L.tail = 0
    · by_cases hx : x = id <;> simp [ht0, upd, hx, hti]
    · by_cases hx : x = id
      · subst hx; simp [ht0, upd, Ne.symm hti, hti]
      · by_cases hxt : x = L.tail <;> simp [ht0, upd, hx, hxt, hti]
  have hprev : ∀ x, (appendOrders os L id x).previous =
      if x = id then L.tail else (os x).previous := by
    intro x
    simp only [appendOrders]
    by_cases ht0 : L.tail = 0
    · by_cases hx : x = id <;> simp [ht0, upd, hx]
    · by_cases hx : x = id
      · subst hx; simp [ht0, upd, Ne.symm hti]
      · by_cases hxt : x = L.tail <;> simp [ht0, upd, hx, hxt, hti]
  have hxid : ∀ x ∈ xs, x ≠ id := fun x hx e => hid (e ▸ hx)
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · rw [List.nodup_append]
    refine ⟨hnd, List.nodup_singleton _, ?_⟩
    intro a ha b hb
    simp only [List.mem_singleton] at hb
    subst hb
    exact hxid a ha
  · simp only [List.mem_append, List.mem_singleton, not_or]; exact ⟨hnz, Ne.symm h0⟩
  · simp only [appendLevel]
    cases xs with
    | nil => simp [htl]
    | cons a r =>
      have : L.tail ≠ 0 := by
        rw [htl]; intro e
        rcases FillerRemove.getLastD_cases (a :: r) with hm | hm
        · cases hm
        · rw [e] at hm; exact hnz hm
      simp [this, hhd]
  · simp [appendLevel]
  · simp [appendLevel, hct]
  · rw [FillerRemove.seg_append]
    refine ⟨?_, ?_⟩
    · simp only [List.headD_cons]
      refine FillerRemove.seg_congr os _ 0 xs 0 0 id hseg ?_ ?_ ?_ ?_
      · intro x hx
        have hxx := List.mem_of_mem_dropLast hx
        rw [hnext, if_neg (hxid x hxx), if_neg]
        rintro ⟨-, e⟩
        exact FillerRemove.dropLast_ne hnd hx (e.trans htl)
      · intro x hx
        rw [hprev, if_neg (hxid x (List.mem_of_mem_tail hx))]
      · intro x hx
        rw [hprev, if_neg (hxid x (List.mem_of_mem_head? hx))]
        exact FillerRemove.seg_head hseg hx
      · intro x hx
        have hxx := List.mem_of_mem_getLast? hx
        have hlx : xs.getLastD 0 = x := by simp [List.getLastD_eq_getLast?, hx]
        rw [hnext, if_neg (hxid x hxx), if_pos]
        refine ⟨?_, ?_⟩
        · rw [htl, hlx]; intro e; exact hnz (e ▸ hxx)
        · rw [htl, hlx]
    · simp only [Seg, List.headD_nil, and_true]
      refine ⟨?_, ?_⟩
      · rw [hprev, if_pos rfl, htl]
      · rw [hnext, if_pos rfl, if_neg hti]

/-- **`_append` links id at the tail of its level (FIFO).** If the order's level holds the queue
`xs ∌ id` (`id ≠ 0`), a successful `_append` leaves it holding `xs ++ [id]`. -/
theorem append_queue {ext : Ext σ} (h : AppendSpec ext) {sg : M σ AsyncFiller.State_}
    {ss : AsyncFiller.State_ → M σ Unit} {bget : M σ AsyncFiller.Book}
    {bset : AsyncFiller.Book → M σ Unit} {g : σ → AsyncFiller.State_}
    {s : σ → AsyncFiller.State_ → σ} {bg : σ → AsyncFiller.Book} {bs : σ → AsyncFiller.Book → σ}
    (L : Lawful sg ss bget bset g s bg bs) (id : Nat) (env : Env) (w w' : σ) {xs : List Nat}
    (hm : (bg w).orderingMode = 0)
    (hq : Queue (g w).orders (levelOfOrder (g w) (bg w) id) xs) (hid : id ∉ xs) (h0 : id ≠ 0)
    (hr : ext.fn_AsyncFiller_append_6737 sg ss bget bset id env w = .ok ((), w')) :
    Queue (g w').orders
      (levels (bg w') ((g w).orders id).isBuy ((g w).orders id).price) (xs ++ [id]) := by
  obtain ⟨-, -, -, -, T1, T2, -, -, hS, hB⟩ := h.post L id env w w' hr
  have hm1 : (bg w).orderingMode ≠ 1 := by omega
  rw [hS, hB]
  simp only [appendState, appendBook, hm1, ite_false, levels_setLevel, levels_setSide,
    levels_openOrderCount, ite_true]
  exact queue_append hq hid h0

end AsyncSwap.Swarm.SpecBook

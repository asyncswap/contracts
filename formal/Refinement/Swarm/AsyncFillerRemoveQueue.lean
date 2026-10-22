import Refinement.Swarm.AsyncFillerRemove

open FormalAst Refinement

namespace AsyncSwap.Swarm.FillerRemove

theorem seg_head {os : Nat → AsyncFiller.OrderInfo} {p q x : Nat} :
    ∀ {xs : List Nat}, Seg os p xs q → xs.head? = some x → (os x).previous = p
  | [], _, h => by simp at h
  | y :: r, hs, h => by simp at h; subst h; exact hs.1

theorem seg_last {os : Nat → AsyncFiller.OrderInfo} {q x : Nat} :
    ∀ {p : Nat} {xs : List Nat}, Seg os p xs q → xs.getLast? = some x → (os x).next = q
  | _, [], _, h => by simp at h
  | _, [y], hs, h => by simp at h; subst h; simpa [Seg] using hs.2.1
  | _, y :: z :: r, hs, h => by
      simp only [Seg] at hs
      exact seg_last (xs := z :: r) hs.2.2 (by simpa [List.getLast?_cons_cons] using h)

/-- `_remove`'s FIFO branch on the orders: `orders[previous].next = next` (when `previous ≠ 0`),
then `orders[next].previous = previous` (when `next ≠ 0`). -/
def unlinkOrders (os : Nat → AsyncFiller.OrderInfo) (id : Nat) : Nat → AsyncFiller.OrderInfo :=
  let o := os id
  let os1 := if o.previous = 0 then os else upd os o.previous { os o.previous with next := o.next }
  if o.next = 0 then os1 else upd os1 o.next { os1 o.next with previous := o.previous }

/-- `_remove`'s FIFO branch on the level: `head = next` (when `previous = 0`), `tail = previous`
(when `next = 0`). -/
def unlinkLevel (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) : AsyncFiller.PriceLevel :=
  let L1 := if o.previous = 0 then { L with head := o.next } else L
  if o.next = 0 then { L1 with tail := o.previous } else L1

theorem upd_next (f : Nat → AsyncFiller.OrderInfo) (k x : Nat) (v : AsyncFiller.OrderInfo) :
    (upd f k v x).next = if x = k then v.next else (f x).next := by
  simp only [upd]; split_ifs <;> rfl

theorem upd_previous (f : Nat → AsyncFiller.OrderInfo) (k x : Nat) (v : AsyncFiller.OrderInfo) :
    (upd f k v x).previous = if x = k then v.previous else (f x).previous := by
  simp only [upd]; split_ifs <;> rfl

theorem unlink_next (os : Nat → AsyncFiller.OrderInfo) (id x : Nat) :
    (unlinkOrders os id x).next =
      if (os id).previous ≠ 0 ∧ x = (os id).previous then (os id).next else (os x).next := by
  unfold unlinkOrders
  by_cases h1 : (os id).previous = 0 <;> by_cases h2 : (os id).next = 0 <;>
    simp only [h1, h2, ite_true, ite_false, upd_next] <;> split_ifs <;> simp_all

theorem unlink_prev (os : Nat → AsyncFiller.OrderInfo) (id x : Nat) :
    (unlinkOrders os id x).previous =
      if (os id).next ≠ 0 ∧ x = (os id).next then (os id).previous else (os x).previous := by
  unfold unlinkOrders
  by_cases h1 : (os id).previous = 0 <;> by_cases h2 : (os id).next = 0 <;>
    simp only [h1, h2, ite_true, ite_false, upd_next, upd_previous] <;> split_ifs <;> simp_all

/-- Orders other than the two neighbours are untouched. -/
theorem unlink_other (os : Nat → AsyncFiller.OrderInfo) (id x : Nat)
    (hp : x ≠ (os id).previous) (hn : x ≠ (os id).next) : unlinkOrders os id x = os x := by
  unfold unlinkOrders
  by_cases h1 : (os id).previous = 0 <;> by_cases h2 : (os id).next = 0 <;>
    simp only [h1, h2, ite_true, ite_false, upd, hp, hn]

/-- `os'` differs from `os` at most in the `previous`/`next` fields of each order. -/
def LinksOnly (os os' : Nat → AsyncFiller.OrderInfo) : Prop :=
  ∀ x, os' x = { os x with previous := (os' x).previous, next := (os' x).next }

theorem linksOnly_refl (os : Nat → AsyncFiller.OrderInfo) : LinksOnly os os := fun _ => rfl

theorem linksOnly_upd {os f : Nat → AsyncFiller.OrderInfo} (hf : LinksOnly os f) (k : Nat)
    (a b : Nat) : LinksOnly os (upd f k { f k with previous := a, next := b }) := by
  intro x
  by_cases hx : x = k
  · subst hx
    rw [upd_same, hf x]
  · rw [upd_other _ _ _ _ hx]; exact hf x

/-- Only `previous`/`next` are written: owner, amounts, price, side, sequence and priority
fields of every order are kept. -/
theorem unlink_linksOnly (os : Nat → AsyncFiller.OrderInfo) (id : Nat) :
    LinksOnly os (unlinkOrders os id) := by
  unfold unlinkOrders
  dsimp only
  split_ifs <;> first
    | exact linksOnly_refl os
    | exact linksOnly_upd (linksOnly_refl os) _ _ _
    | exact linksOnly_upd (linksOnly_upd (linksOnly_refl os) _ _ _) _ _ _

@[simp] theorem unlinkLevel_head (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) :
    (unlinkLevel L o).head = if o.previous = 0 then o.next else L.head := by
  unfold unlinkLevel; split_ifs <;> rfl
@[simp] theorem unlinkLevel_tail (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) :
    (unlinkLevel L o).tail = if o.next = 0 then o.previous else L.tail := by
  unfold unlinkLevel; split_ifs <;> rfl
@[simp] theorem unlinkLevel_orderCount (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) :
    (unlinkLevel L o).orderCount = L.orderCount := by
  unfold unlinkLevel; split_ifs <;> rfl
@[simp] theorem unlinkLevel_priorityOrders (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) :
    (unlinkLevel L o).priorityOrders = L.priorityOrders := by
  unfold unlinkLevel; split_ifs <;> rfl
@[simp] theorem unlinkLevel_priorityOrderIds (L : AsyncFiller.PriceLevel) (o : AsyncFiller.OrderInfo) :
    (unlinkLevel L o).priorityOrderIds = L.priorityOrderIds := by
  unfold unlinkLevel; split_ifs <;> rfl

/-- A price level's FIFO queue holds exactly the orders `xs`, in order: no duplicates, no null id,
`head`/`tail` are the first/last (`0` when empty), `orderCount` is the length, and the
`previous`/`next` pointers link them with `0` at both ends. -/
structure Queue (os : Nat → AsyncFiller.OrderInfo) (L : AsyncFiller.PriceLevel) (xs : List Nat) :
    Prop where
  nodup : xs.Nodup
  nz : 0 ∉ xs
  head : L.head = xs.headD 0
  tail : L.tail = xs.getLastD 0
  count : L.orderCount = xs.length
  seg : Seg os 0 xs 0

theorem queue_default (os : Nat → AsyncFiller.OrderInfo) : Queue os default [] :=
  ⟨List.nodup_nil, by simp, rfl, rfl, rfl, trivial⟩

theorem dropLast_ne {l : List Nat} (hnd : l.Nodup) {x : Nat} (hx : x ∈ l.dropLast) :
    x ≠ l.getLastD 0 := by
  rcases l.eq_nil_or_concat with rfl | ⟨l', a, rfl⟩
  · simp at hx
  · simp only [List.concat_eq_append] at hnd hx ⊢
    rw [List.nodup_append] at hnd
    simp at hx ⊢
    exact hnd.2.2 x hx a (by simp)

theorem tail_ne {l : List Nat} (hnd : l.Nodup) {x : Nat} (hx : x ∈ l.tail) :
    x ≠ l.headD 0 := by
  cases l with
  | nil => simp at hx
  | cons b r =>
    simp only [List.tail_cons] at hx
    simp only [List.headD_cons]
    rw [List.nodup_cons] at hnd
    rintro rfl; exact hnd.1 hx

theorem getLastD_cases (l : List Nat) : l = [] ∨ l.getLastD 0 ∈ l := by
  rcases l.eq_nil_or_concat with rfl | ⟨l', a, rfl⟩
  · exact Or.inl rfl
  · right; simp

theorem headD_cases (l : List Nat) : l = [] ∨ l.headD 0 ∈ l := by
  cases l with
  | nil => exact Or.inl rfl
  | cons b r => right; simp

/-- **`_remove` unlinks exactly one order (FIFO book).** If the level's queue is `xs` and `id ∈ xs`,
the pointer surgery plus `--orderCount` leaves the queue `xs.erase id`. -/
theorem queue_unlink {os : Nat → AsyncFiller.OrderInfo} {L : AsyncFiller.PriceLevel} {xs : List Nat}
    {id : Nat} (hq : Queue os L xs) (hid : id ∈ xs) :
    Queue (unlinkOrders os id) { unlinkLevel L (os id) with orderCount := L.orderCount - 1 }
      (xs.erase id) := by
  obtain ⟨as, bs, rfl⟩ := List.append_of_mem hid
  obtain ⟨hnd, hnz, hhd, htl, hct, hseg⟩ := hq
  have hnd2 := List.nodup_middle.mp hnd
  rw [List.nodup_cons] at hnd2
  obtain ⟨hidAB, hndE⟩ := hnd2
  have hidA : id ∉ as := fun h => hidAB (List.mem_append_left _ h)
  have hndA : as.Nodup := hndE.sublist (List.sublist_append_left _ _)
  have hndB : bs.Nodup := hndE.sublist (List.sublist_append_right _ _)
  have hdisj : ∀ x ∈ as, ∀ y ∈ bs, x ≠ y := (List.nodup_append.mp hndE).2.2
  have hzA : ∀ x ∈ as, x ≠ 0 := fun x hx h => hnz (by subst h; simp [hx])
  have hzB : ∀ x ∈ bs, x ≠ 0 := fun x hx h => hnz (by subst h; simp [hx])
  have herase : (as ++ id :: bs).erase id = as ++ bs := by
    rw [List.erase_append_right _ hidA, List.erase_cons_head]
  rw [herase]
  rw [seg_append] at hseg
  obtain ⟨hsA, hsB⟩ := hseg
  simp only [Seg, List.headD_cons] at hsA hsB
  obtain ⟨hP, hN, hsB⟩ := hsB
  have F1 : ∀ x ∈ as, x ≠ bs.headD 0 := by
    intro x hx
    rcases headD_cases bs with h | h
    · subst h; exact hzA x hx
    · exact hdisj x hx _ h
  have F2 : ∀ x ∈ bs, x ≠ as.getLastD 0 := by
    intro x hx
    rcases getLastD_cases as with h | h
    · subst h; exact hzB x hx
    · exact fun e => hdisj _ h x hx e.symm
  have hA : Seg (unlinkOrders os id) 0 as (bs.headD 0) := by
    refine seg_congr os _ 0 as id 0 _ hsA ?_ ?_ ?_ ?_
    · intro x hx
      rw [unlink_next, hP, if_neg]
      rintro ⟨_, h⟩; exact dropLast_ne hndA hx h
    · intro x hx
      rw [unlink_prev, hN, if_neg]
      rintro ⟨_, h⟩; exact F1 x (List.mem_of_mem_tail hx) h
    · intro x hx
      have hxA := List.mem_of_mem_head? hx
      rw [unlink_prev, hN, if_neg (fun h => F1 x hxA h.2)]
      exact seg_head hsA hx
    · intro x hx
      have hxA := List.mem_of_mem_getLast? hx
      have hpx : as.getLastD 0 = x := by simp [List.getLastD_eq_getLast?, hx]
      rw [unlink_next, hP, if_pos ⟨by rw [hpx]; exact hzA x hxA, hpx.symm⟩]
      exact hN
  have hB : Seg (unlinkOrders os id) (as.getLastD 0) bs 0 := by
    refine seg_congr os _ id bs 0 _ 0 hsB ?_ ?_ ?_ ?_
    · intro x hx
      have hxB := List.mem_of_mem_dropLast hx
      rw [unlink_next, hP, if_neg (fun h => F2 x hxB h.2)]
    · intro x hx
      rw [unlink_prev, hN, if_neg]
      rintro ⟨_, h⟩; exact tail_ne hndB hx h
    · intro x hx
      have hxB := List.mem_of_mem_head? hx
      have hnx : bs.headD 0 = x := by simp [List.headD_eq_head?_getD, hx]
      rw [unlink_prev, hN, if_pos ⟨by rw [hnx]; exact hzB x hxB, hnx.symm⟩]
      exact hP
    · intro x hx
      have hxB := List.mem_of_mem_getLast? hx
      rw [unlink_next, hP, if_neg (fun h => F2 x hxB h.2)]
      exact seg_last hsB hx
  refine ⟨hndE, ?_, ?_, ?_, ?_, (seg_append _ 0 as bs 0).2 ⟨hA, hB⟩⟩
  · intro h
    rcases List.mem_append.mp h with h | h
    · exact hzA 0 h rfl
    · exact hzB 0 h rfl
  · show (unlinkLevel L (os id)).head = _
    rw [unlinkLevel_head, hP, hN, hhd]
    rcases getLastD_cases as with h | h
    · subst h; simp
    · rw [if_neg (hzA _ h)]
      cases as with
      | nil => simp at h
      | cons a r => simp
  · show (unlinkLevel L (os id)).tail = _
    rw [unlinkLevel_tail, hN, hP, htl]
    cases bs with
    | nil => simp
    | cons b r =>
      rw [List.headD_cons, if_neg (hzB b (by simp))]
      simp [List.getLastD_eq_getLast?, List.getLast?_append]
  · show L.orderCount - 1 = _
    rw [hct]; simp

end AsyncSwap.Swarm.FillerRemove

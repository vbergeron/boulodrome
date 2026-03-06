(* Example Coq/Rocq file for testing boulodrome *)

From Stdlib Require Import Arith.

Theorem addnC : forall n m : nat, n + m = m + n.
Proof. intros n m. apply Nat.add_comm. Qed.

Theorem mult_comm : forall n m : nat, n * m = m * n.
Proof. intros n m. apply Nat.mul_comm. Qed.

Theorem plus_assoc_example : forall n m p : nat, n + (m + p) = (n + m) + p.
Proof. intros n m p. apply Nat.add_assoc. Qed.

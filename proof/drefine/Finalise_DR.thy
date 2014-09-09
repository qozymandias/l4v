(*
 * Copyright 2014, NICTA
 *
 * This software may be distributed and modified according to the terms of
 * the GNU General Public License version 2. Note that NO WARRANTY is provided.
 * See "LICENSE_GPLv2.txt" for details.
 *
 * @TAG(NICTA_GPL)
 *)

theory Finalise_DR
imports
  KHeap_DR
  "../invariant-abstract/PDPTEntries_AI"
  "../../lib/Apply_Trace"
begin

declare dxo_wp_weak[wp del]

lemma trancl_image:
  assumes inj: "inj_on f (Domain S \<union> Range S)"
  shows "trancl ((\<lambda>(x, y). (f x, f y)) ` S) = (\<lambda>(x, y). (f x, f y)) ` trancl S"
  (is "?lhs = ?rhs")
  apply safe
   apply (erule trancl.induct)
    apply clarsimp
    apply (erule image_eqI[rotated, OF r_into_trancl])
    apply simp
   apply (clarsimp simp: inj_on_iff[OF inj]
                         RangeI[THEN eqset_imp_iff[OF trancl_range, THEN iffD1]]
                         DomainI)
   apply (erule(1) image_eqI[rotated, OF trancl_into_trancl])
   apply simp
  apply (erule trancl.induct)
   apply (rule r_into_trancl, erule image_eqI[rotated])
   apply simp
  apply (erule trancl_into_trancl)
  apply (erule image_eqI[rotated])
  apply simp
  done

lemma descendants_of_eqv:
  assumes cte_at: "mdb_cte_at (swp (cte_wp_at P) s) (cdt s)"
    and cte_at_p: "cte_at p s"
  shows "KHeap_D.descendants_of (transform_cslot_ptr p) (transform s)
           = transform_cslot_ptr ` CSpaceAcc_A.descendants_of p (cdt s)"
proof -
  note inj = transform_cdt_slot_inj_on_mdb_cte_at[OF cte_at]
  have P: "{(x, y). KHeap_D.is_cdt_parent (transform s) x y}
              = (\<lambda>(x, y). (transform_cslot_ptr x, transform_cslot_ptr y))
                      ` {(x, y). CSpaceAcc_A.is_cdt_parent (cdt s) x y}"
    apply (simp add: KHeap_D.is_cdt_parent_def CSpaceAcc_A.is_cdt_parent_def)
    apply (simp add: transform_def transform_cdt_def map_lift_over_eq_Some
                     inj)
    apply auto
    done
  have inj': "inj_on transform_cslot_ptr ({p} \<union> dom (cdt s) \<union> ran (cdt s))"
    using cte_at_p mdb_cte_atD[OF _ cte_at]
    apply -
    apply (rule transform_cdt_slot_inj_on_cte_at[where P=\<top> and s=s])
    apply (fastforce simp: cte_wp_at_caps_of_state elim!: ranE)
    done
  show ?thesis
    apply (simp add: KHeap_D.descendants_of_def CSpaceAcc_A.descendants_of_def
                     KHeap_D.cdt_parent_rel_def CSpaceAcc_A.cdt_parent_rel_def)
    apply (simp add: P)
    apply (subst trancl_image)
     apply (rule subset_inj_on[OF inj])
     apply (auto simp: KHeap_D.is_cdt_parent_def CSpaceAcc_A.is_cdt_parent_def)[1]
    apply safe
     apply (subst(asm) inj_on_iff[OF inj'], simp_all)
     apply (drule DomainI[THEN eqset_imp_iff[OF trancl_domain, THEN iffD1]])
     apply (auto simp: CSpaceAcc_A.is_cdt_parent_def)
    done
qed



(* Fast finalise is done in TCB_DR, this file only deals with finalise *)
lemma dcorres_unmap_page_empty:
  "dcorres dc \<top> \<top> (PageTableUnmap_D.unmap_page x) (return a)"
  apply (simp add:PageTableUnmap_D.unmap_page_def)
  apply (rule corres_symb_exec_l)
    apply (rule corres_guard_imp)
    apply (rule_tac x = "[]" in select_pick_corres)
      apply (clarsimp simp:mapM_x_def sequence_x_def del:hoare_post_taut)
prefer 4
  apply (rule hoare_post_taut)
  apply simp_all
  apply (simp add:exs_valid_def slots_with_def gets_def has_slots_def get_def bind_def return_def )
done

lemma dcorres_revoke_cap_no_descendants:
  "slot' = transform_cslot_ptr slot \<Longrightarrow> dcorres dc \<top> (\<lambda>s. valid_mdb s \<and> cte_at slot s \<and>  CSpaceAcc_A.descendants_of slot (cdt s) = {})
    (revoke_cap_simple slot')
    (return x)"
  apply (rule dcorres_revoke_cap_simple_helper)
  apply (simp add:gets_def)
  apply (rule dcorres_absorb_get_l)
  apply (subgoal_tac "(KHeap_D.descendants_of slot' (transform s')) = {}")
   apply clarsimp
   apply (rule dcorres_absorb_get_l)
   apply clarsimp
  apply (clarsimp simp:descendants_of_eqv valid_mdb_def)
  done

lemma dcorres_revoke_cap_unnecessary:
  "dcorres dc \<top> (valid_reply_caps and valid_objs and only_idle and valid_mdb and st_tcb_at (Not \<circ> awaiting_reply) ptr
    and cte_at (ptr,tcb_cnode_index 2) and not_idle_thread ptr and valid_idle)
    (revoke_cap_simple (ptr, tcb_replycap_slot))
    (return x)"
  apply (subst transform_tcb_slot_simp[symmetric])
  apply (rule corres_guard_imp)
  apply (rule dcorres_revoke_cap_no_descendants)
  apply (simp add:transform_tcb_slot_simp[symmetric])+
  apply (rule not_waiting_reply_slot_no_descendants)
    apply simp_all
done

lemma descendants_exist_in_cdt:
  "\<lbrakk> a \<in> descendants_of p (cdt s) \<rbrakk>
        \<Longrightarrow> cdt s a \<noteq> None"
  apply (simp add: descendants_of_def cdt_parent_rel_def)
  apply (frule RangeI[THEN eqset_imp_iff[OF trancl_range, THEN iffD1]])
  apply (clarsimp simp: is_cdt_parent_def)
  done

lemma descendants_exist_in_cdl_cdt:
  "\<lbrakk> a \<in> KHeap_D.descendants_of p (transform s) \<rbrakk>
        \<Longrightarrow> cdl_cdt (transform s) a \<noteq> None"
  apply (simp add: KHeap_D.descendants_of_def KHeap_D.cdt_parent_rel_def)
  apply (frule RangeI)
  apply (frule DomainI)
  apply (clarsimp simp: KHeap_D.is_cdt_parent_def)
done

lemma cdl_cdt_parent_cte_at_lift:
  "\<lbrakk> mdb_cte_at (swp (cte_wp_at P) s) (cdt s) ; a \<in> KHeap_D.descendants_of p (transform s) \<rbrakk>
    \<Longrightarrow> (\<exists>slot. cte_at slot s \<and>  p = transform_cslot_ptr slot)"
  apply (simp add:KHeap_D.descendants_of_def KHeap_D.cdt_parent_rel_def)
  apply (frule DomainI)
  apply (clarsimp simp:KHeap_D.is_cdt_parent_def)
  apply (simp add:transform_def transform_cdt_def)
  apply (clarsimp simp:transform_cdt_slot_inj_on_mdb_cte_at map_lift_over_eq_Some split:if_splits)
  apply (rule_tac x = ab in exI,rule_tac x = bb in exI)
    apply (drule(1) mdb_cte_atD)
  apply (clarsimp simp :cte_wp_at_cte_at)
done

lemma descendants_not_null_cap:
  "\<lbrakk> a \<in> descendants_of p (cdt s); mdb_cte_at (swp (cte_wp_at P) s) (cdt s) \<rbrakk>
        \<Longrightarrow> cte_wp_at P a s"
  apply (drule descendants_exist_in_cdt)
  apply clarsimp
  apply (drule(1) mdb_cte_atD)
  apply simp
  done

lemma descendants_in_cte_wp_set:
  "mdb_cte_at (swp (cte_wp_at P ) s) (cdt s)
  \<Longrightarrow> CSpaceAcc_A.descendants_of p (cdt s) \<subseteq> Collect (\<lambda>x. cte_wp_at (P) x s)"
  by (auto simp:descendants_not_null_cap)

lemma ex_in_none_empty_set:
  "a\<noteq>{} \<Longrightarrow> \<exists>x. x\<in>a"
  by auto

lemma finite_descendants_if_from_transform:
  " mdb_cte_at (swp (cte_wp_at P) s) (cdt s) \<Longrightarrow> finite (KHeap_D.descendants_of x (transform s))"
  apply (case_tac "KHeap_D.descendants_of x (transform s) = {}")
   apply simp
  apply (drule ex_in_none_empty_set)
  apply clarsimp
  apply (frule(1) cdl_cdt_parent_cte_at_lift)
  apply clarsimp
  apply (frule(1) descendants_of_eqv)
  apply clarsimp
  apply (rule finite_imageI)
  apply (rule finite_subset)
  apply (rule descendants_in_cte_wp_set)
    apply simp
  apply (simp add:cte_wp_at_set_finite)
done


lemma delete_cdt_slot_shrink_descendants:
  "\<lbrace>\<lambda>s. valid_mdb s \<and> x = cdt s \<and> slot \<in> CSpaceAcc_A.descendants_of p x \<and> x = y \<rbrace>
    set_cdt ((\<lambda>p. if x p = Some slot then x slot else x p)(slot := None))
    \<lbrace>\<lambda>r s. slot \<notin> CSpaceAcc_A.descendants_of p (cdt s) \<and>
    CSpaceAcc_A.descendants_of p (cdt s) \<subseteq> CSpaceAcc_A.descendants_of p y \<rbrace>"
  apply (clarsimp simp:set_cdt_def get_def put_def bind_def valid_def)
  apply (rule conjI)
    apply (subgoal_tac "mdb_empty_abs s")
    apply (clarsimp simp:mdb_empty_abs.descendants mdb_empty_abs_def vmdb_abs_def)+
done

lemma delete_cap_one_shrink_descendants:

  "\<lbrace>\<lambda>s. s = pres \<and> invs s \<and> slot \<in> CSpaceAcc_A.descendants_of p (cdt pres) \<rbrace> cap_delete_one slot
    \<lbrace>\<lambda>r s. slot \<notin> CSpaceAcc_A.descendants_of p (cdt s) \<and>
    CSpaceAcc_A.descendants_of p (cdt s) \<subseteq> CSpaceAcc_A.descendants_of p (cdt pres) \<rbrace>"
  apply (simp add:cap_delete_one_def unless_def)
  apply wp
     apply (clarsimp simp add:empty_slot_def)
     apply (wp dxo_wp_weak)
         apply simp
        apply (rule_tac P="\<lambda>s. valid_mdb s \<and> cdt s = xa \<and> cdt pres = xa \<and> slot \<in> CSpaceAcc_A.descendants_of p (cdt s)
          \<and> mdb_cte_at (swp (cte_wp_at (op\<noteq> cap.NullCap)) s) (cdt s)"
          in hoare_vcg_precond_imp)
         apply (rule_tac Q ="\<lambda>r s. (?Q r s) \<and>  (mdb_cte_at (swp (cte_wp_at (op\<noteq> cap.NullCap)) s) (cdt s))" in hoare_strengthen_post)
          apply (rule hoare_vcg_conj_lift)
           apply (rule delete_cdt_slot_shrink_descendants[where y= "cdt pres" and p = p])
          apply (rule_tac Q="\<lambda>s. mdb_cte_at (swp (cte_wp_at (op\<noteq>cap.NullCap)) s ) xa" in hoare_vcg_precond_imp)
           apply (case_tac slot)
           apply (clarsimp simp:set_cdt_def get_def put_def bind_def valid_def mdb_cte_at_def | rule conjI)+
            apply (fastforce,clarsimp,fastforce)
          apply (assumption)
         apply clarsimp+
       apply (assumption)
      apply wp
     apply (rule hoare_vcg_conj_lift[where P="\<lambda>s. cdt s = cdt pres \<and> mdb_cte_at (swp (cte_wp_at (op\<noteq>cap.NullCap)) s) (cdt s)"])
      prefer 2
      apply (rule hoare_drop_imp)
      apply wp
     apply (clarsimp simp:valid_def in_get_cap_cte_wp_at)
     apply (drule sym)
     apply clarsimp
     apply (drule descendants_not_null_cap)
      apply simp
     apply (simp add:cte_wp_at_def)
    apply (wp|simp)+
    apply (rule hoare_vcg_conj_lift)
     apply (rule hoare_strengthen_post[OF invs_mdb_fast_finalise])
     apply (clarsimp simp:valid_mdb_def swp_def)
    apply wp
    apply (rule hoare_strengthen_post[OF invs_mdb_fast_finalise])
    apply (clarsimp simp:valid_mdb_def swp_def)
   apply wp
  apply (clarsimp simp:valid_def in_get_cap_cte_wp_at)
  apply (clarsimp simp:invs_def valid_mdb_def valid_state_def)
  apply (drule descendants_not_null_cap)
   apply simp
  apply (clarsimp simp:cte_wp_at_def)
done

lemma invs_emptyable_descendants:
  "\<lbrakk>invs s;CSpaceAcc_A.descendants_of slot (cdt s) = {(a, b)}\<rbrakk>
              \<Longrightarrow> emptyable (a, b) s"
  apply (clarsimp simp:emptyable_def)
  apply (frule reply_slot_not_descendant)
    apply simp
  apply fastforce
done

lemma cap_delete_one_cte_at:
  "\<lbrace>invs and emptyable sl and cte_at x\<rbrace> cap_delete_one sl \<lbrace>\<lambda>_. cte_at x\<rbrace>"
  apply (simp add:cap_delete_one_def)
    apply wp
    apply (clarsimp simp:unless_def when_def | rule conjI)+
    apply (wp|clarsimp)+
done

lemma nat_to_bl_zero_zero:
  "(nat_to_bl 0 0) = (Some [])"
  by (clarsimp simp: nat_to_bl_def)

lemma caps_of_state_transform_opt_cap_no_idle:
  "\<lbrakk>caps_of_state s p = Some cap; valid_etcbs s\<rbrakk>
   \<Longrightarrow> opt_cap (transform_cslot_ptr p) (transform s)
          = Some (transform_cap cap) \<or>
      opt_cap (transform_cslot_ptr p) (transform s)
          = None"
  apply (frule caps_of_state_cteD)
  apply (cases p)
  apply (erule cte_wp_atE)
   apply (clarsimp simp: opt_cap_def transform_cslot_ptr_def object_slots_def
                         slots_of_def opt_object_def transform_def transform_objects_def
                         transform_cnode_contents_def well_formed_cnode_n_def
                         restrict_map_def
                   split: option.splits split_if_asm nat.splits)
    apply (frule(1) eqset_imp_iff[THEN iffD1, OF _ domI])
    apply (simp add: nat_to_bl_zero_zero option_map_join_def)
   apply clarsimp
   apply (frule(1) eqset_imp_iff[THEN iffD1, OF _ domI])
   apply (simp add: option_map_join_def nat_to_bl_dest)
   apply (clarsimp simp: cap_installed_at_irq_def valid_irq_node_def
                         obj_at_def is_cap_table_def well_formed_cnode_n_def
                         length_set_helper word_bl.Abs_inverse
                         object_slots_def nat_bl_to_bin_lt2p)
  apply (frule(1) valid_etcbs_tcb_etcb)
  apply (clarsimp simp: opt_cap_def transform_cslot_ptr_def
                        slots_of_def opt_object_def restrict_map_def
                        transform_def object_slots_def transform_objects_def
                        valid_irq_node_def obj_at_def is_cap_table_def
                        transform_tcb_def tcb_slot_defs
                        tcb_pending_op_slot_def tcb_cap_cases_def
                        bl_to_bin_tcb_cnode_index bl_to_bin_tcb_cnode_index_le0
                 split: split_if_asm option.splits)
  done

lemma transform_cap_Null [simp]:
  "(transform_cap cap = cdl_cap.NullCap) = (cap = cap.NullCap)"
  apply (cases cap, simp_all)
  apply (case_tac arch_cap, simp_all)
  done

lemma dcorres_revoke_the_cap_corres:
  "dcorres dc \<top>
    (invs and cte_at slot and valid_etcbs)
    (revoke_cap_simple (transform_cslot_ptr slot))
    (do descs \<leftarrow> gets (CSpaceAcc_A.descendants_of slot \<circ> cdt);
        when (descs \<noteq> {}) (do y \<leftarrow> assert (\<exists>a b. descs = {(a, b)});
                          select descs >>= cap_delete_one
                          od)
    od)"
  apply (rule dcorres_revoke_cap_simple_helper)
  apply (simp add:gets_def)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (subgoal_tac "finite (KHeap_D.descendants_of (transform_cslot_ptr slot) (transform s'))")
   apply (clarsimp simp: finite_descendants_if_from_transform valid_mdb_def
                         invs_def valid_state_def descendants_of_eqv)
   apply (rule dcorres_absorb_get_l)
   apply (clarsimp simp: when_def assert_def corres_free_fail)
   apply (subgoal_tac "cte_wp_at (op \<noteq> cap.NullCap) (a,b) s'")
    prefer 2
    apply (erule descendants_not_null_cap [rotated])
    apply fastforce
   apply (rule conjI)
    prefer 2
    apply (clarsimp simp: cte_wp_at_caps_of_state)
    apply (subgoal_tac "a \<noteq> idle_thread s'")
     apply (drule_tac p="(a,b)" in caps_of_state_transform_opt_cap)
      apply clarsimp
     apply clarsimp
    apply clarsimp
   apply clarsimp
    apply (erule notE, rule sym)
    apply (erule (4) valid_idle_has_null_cap)
   apply clarsimp
    apply (rule corres_dummy_return_r)
    apply (rule corres_guard_imp)
      apply (rule corres_split[OF dcorres_revoke_cap_no_descendants])
        apply simp
        apply (rule delete_cap_simple_corres)
        apply (wp cap_delete_one_cte_at)
      apply (rule_tac pres1 = s' and  p1 = slot in hoare_strengthen_post[OF delete_cap_one_shrink_descendants])
    apply (simp_all add:invs_def valid_state_def valid_mdb_def)
    apply fastforce
    apply (rule conjI)
      apply (rule ccontr)
      apply (subgoal_tac "cte_wp_at (op\<noteq>cap.NullCap) (a,b) s")
        apply (clarsimp simp: cte_wp_at_caps_of_state)
        apply (drule valid_idle_has_null_cap)
        apply (simp add:not_idle_thread_def)+
     apply (rule invs_emptyable_descendants)
    apply (simp add:invs_def valid_state_def valid_mdb_def)+
  apply (clarsimp simp:finite_descendants_if_from_transform)
  done

lemma valid_aep_after_reomve_slot:
  "valid_aep (async_ep.WaitingAEP list) s'\<Longrightarrow>
  valid_aep (case remove1 ptr list of [] \<Rightarrow> async_ep.IdleAEP | a # lista \<Rightarrow> async_ep.WaitingAEP (remove1 ptr list)) s'"
  by (clarsimp simp:valid_aep_def split:async_ep.splits list.split_asm)

lemma finalise_ipc_cancel:
  "dcorres dc \<top> (not_idle_thread ptr and invs and valid_etcbs)
    (CSpace_D.ipc_cancel ptr)
    (ipc_cancel ptr)"
  apply (simp add:CSpace_D.ipc_cancel_def ipc_cancel_def get_thread_state_def thread_get_def)
  apply (rule dcorres_gets_the)
  apply (simp add:opt_object_tcb not_idle_thread_def transform_tcb_def, clarsimp)
  apply (frule(1) valid_etcbs_get_tcb_get_etcb)
  apply (clarsimp simp: opt_cap_tcb tcb_pending_op_slot_def
                        tcb_caller_slot_def tcb_cspace_slot_def tcb_ipcbuffer_slot_def
                        tcb_replycap_slot_def tcb_vspace_slot_def assert_opt_def)
  apply (case_tac "tcb_state obj'")
    apply (simp_all add:not_idle_thread_def infer_tcb_pending_op_def
      tcb_pending_op_slot_def[symmetric] tcb_replycap_slot_def[symmetric])
      apply (simp add:blocked_ipc_cancel_def)
      apply (rule corres_guard_imp)
        apply (rule corres_symb_exec_r)
          apply (rule corres_symb_exec_r)
            apply (rule corres_symb_exec_r)
              apply (rule corres_dummy_return_pl)
              apply (rule corres_split[ OF _ corres_dummy_set_sync_ep])
              apply clarsimp
              apply (rule corres_dummy_return_pr)
              apply (rule corres_split [OF _ dcorres_revoke_cap_unnecessary])
                apply (simp add:K_bind_def when_def dc_def[symmetric])
                apply (rule set_thread_state_corres)
           apply (wp sts_only_idle sts_st_tcb_at' valid_ep_queue_subset |  clarsimp simp:not_idle_thread_def)+
           apply (simp add:get_blocking_ipc_endpoint_def | wp)+
         apply (clarsimp dest!:get_tcb_rev simp:invs_def )
         apply (frule(1) valid_tcb_if_valid_state)
         apply (clarsimp simp:valid_tcb_def valid_tcb_state_def
          valid_state_def valid_pspace_def infer_tcb_pending_op_def
          st_tcb_at_def generates_pending_def obj_at_def dest!:get_tcb_SomeD)
         apply (rule tcb_at_cte_at_2,clarsimp simp:tcb_at_def dest!:get_tcb_rev,simp)
     apply (simp add:blocked_ipc_cancel_def)
     apply (rule corres_guard_imp)
       apply (rule corres_symb_exec_r)
          apply (rule corres_symb_exec_r)
             apply (rule corres_symb_exec_r)
                apply (rule corres_dummy_return_pl)
                apply (rule corres_split[ OF _ corres_dummy_set_sync_ep])
                  apply clarsimp
                  apply (rule corres_dummy_return_pr)
                  apply (rule corres_split [OF _ dcorres_revoke_cap_unnecessary])
                    unfolding K_bind_def
                    apply (rule set_thread_state_corres)
                   apply (wp sts_only_idle sts_st_tcb_at' valid_ep_queue_subset
                     | clarsimp simp:not_idle_thread_def)+
         apply (simp add:get_blocking_ipc_endpoint_def | wp)+
    apply (clarsimp dest!:get_tcb_rev simp:invs_def)
    apply (frule(1) valid_tcb_if_valid_state)
    apply (clarsimp simp:valid_tcb_def valid_tcb_state_def
          valid_state_def valid_pspace_def infer_tcb_pending_op_def
          st_tcb_at_def generates_pending_def obj_at_def dest!:get_tcb_SomeD)
    apply (rule tcb_at_cte_at_2,clarsimp simp:tcb_at_def dest!:get_tcb_rev,simp)
   apply (simp add:reply_ipc_cancel_def)
   apply (rule corres_guard_imp)
     apply (rule corres_split[OF _ thread_set_fault_corres])
        apply (rule corres_symb_exec_r)
        apply (simp add:when_False revoke_cap_simple.simps )
        apply (subst transform_tcb_slot_simp[symmetric])
        apply (rule dcorres_revoke_the_cap_corres)
        apply (wp thread_set_invs_trivial[OF ball_tcb_cap_casesI]
                  thread_set_cte_at|clarsimp)+
        apply (clarsimp simp: not_idle_thread_def
          tcb_at_cte_at_2[unfolded tcb_at_def])
   apply (simp add:async_ipc_cancel_def)
     apply (rule corres_guard_imp)
       apply (rule_tac Q'="\<lambda>r. valid_aep r and op=s'" in corres_symb_exec_r)
         apply (rule corres_symb_exec_r)
           apply (rule corres_dummy_return_pl)
             apply (rule corres_split[ OF _ corres_dummy_set_async_ep])
               unfolding K_bind_def
             apply (rule corres_dummy_return_pr)
             apply (rule corres_split[OF _ dcorres_revoke_cap_unnecessary])
               unfolding K_bind_def
           apply (rule set_thread_state_corres)
         apply (wp set_aep_valid_objs | clarsimp simp:not_idle_thread_def)+
         apply (clarsimp simp:valid_def fail_def return_def split:async_ep.splits)+
      apply (clarsimp simp:invs_def)
      apply (frule(1) valid_tcb_if_valid_state)
      apply (clarsimp simp:valid_tcb_def tcb_at_cte_at_2
        valid_tcb_state_def invs_def valid_state_def valid_pspace_def
        st_tcb_at_def generates_pending_def obj_at_def infer_tcb_pending_op_def
        dest!:get_tcb_SomeD)
      apply (simp add:valid_aep_after_reomve_slot)
    apply (wp | clarsimp split:async_ep.splits)+
    apply (clarsimp simp:invs_def, frule(1) valid_tcb_if_valid_state)
    apply (clarsimp simp:valid_tcb_def tcb_at_cte_at_2 valid_tcb_state_def invs_def valid_state_def valid_pspace_def
         st_tcb_at_def generates_pending_def obj_at_def dest!:get_tcb_SomeD)
   apply (clarsimp, frule(1) valid_etcbs_get_tcb_get_etcb)
   apply (clarsimp simp:opt_object_tcb opt_cap_tcb)
done

lemma dcorres_get_irq_slot:
  "dcorres (\<lambda>r r'. r = transform_cslot_ptr r') \<top> \<top> (gets (CSpace_D.get_irq_slot x)) (KHeap_A.get_irq_slot x)"
  apply (simp add:gets_def CSpace_D.get_irq_slot_def KHeap_A.get_irq_slot_def)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp: return_def transform_def corres_underlying_def transform_cslot_ptr_def)
done

lemma dcorres_deleting_irq_handler:
  "dcorres dc \<top> (invs and valid_etcbs)
     (CSpace_D.deleting_irq_handler word)
     (CSpace_A.deleting_irq_handler word)"
  apply (simp add:CSpace_D.deleting_irq_handler_def CSpace_A.deleting_irq_handler_def)
  apply (rule corres_guard_imp)
  apply (rule corres_split[OF _ dcorres_get_irq_slot])
    apply (simp, rule delete_cap_simple_corres,simp)
    apply (rule hoare_vcg_precond_imp [where Q="invs and valid_etcbs"])
    apply (wp |clarsimp simp:get_irq_slot_def)+
    apply (rule irq_node_image_not_idle)
    apply (simp add:invs_def valid_state_def)+
done

lemma do_machine_op_wp:
  "\<forall>m. \<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> mop \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>
    \<Longrightarrow> \<lbrace>\<lambda>ps. transform ps = cs\<rbrace> do_machine_op mop \<lbrace>\<lambda>r ps. transform ps = cs\<rbrace>"
  apply (clarsimp simp:do_machine_op_def gets_def get_def return_def bind_def select_f_def simpler_modify_def)
  apply (clarsimp simp:valid_def)
  apply (drule_tac x = "(machine_state s)" in spec)
  apply (drule_tac x = "(a,b)" in bspec)
    apply simp
  apply clarsimp
  apply (clarsimp simp:transform_def transform_current_thread_def)
  apply (simp add: transform_objects_def2)
  done

lemmas dmo_dwp = do_machine_op_wp [OF allI]

lemma machine_op_lift[wp]:
  "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> machine_op_lift x \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  apply (clarsimp simp:machine_rest_lift_def ignore_failure_def machine_op_lift_def)
  apply wp
  apply (clarsimp simp:simpler_modify_def valid_def)
  apply (assumption)
  apply wp
  apply clarsimp
done

lemma invalidateTLB_ASID_underlying_memory[wp]:
  "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> invalidateTLB_ASID a \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
   apply (clarsimp simp: invalidateTLB_ASID_def, wp)
done

lemma dsb_underlying_memory[wp]: "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> dsb \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  apply (clarsimp simp: dsb_def, wp)
done

lemma invalidate_I_PoU_underlying_memory[wp]: "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> invalidate_I_PoU \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  apply (clarsimp simp: invalidate_I_PoU_def , wp)
done

lemma clean_D_PoU_underlying_memory[wp]: "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace>clean_D_PoU \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  apply (clarsimp simp: clean_D_PoU_def , wp)
done

lemma cleanCachesPoU_underlying_memory[wp]:
  "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> cleanCaches_PoU \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
   apply (clarsimp simp: cleanCaches_PoU_def, wp)
done

lemma flush_space_dwp[wp]:
  "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> flush_space x \<lbrace>\<lambda>r ps. transform ps = cs\<rbrace>"
  apply (clarsimp simp:flush_space_def)
  apply (wp|wpc)+
  apply (clarsimp split:option.splits)
  apply (rule do_machine_op_wp)
  apply clarsimp
  apply (wp static_imp_wp)
  apply (rule do_machine_op_wp)
  apply clarsimp
  apply wp
  apply (rule hoare_allI)
  apply (rule hoare_drop_imp)
  apply (rule do_machine_op_wp)
  apply clarsimp
  apply wp
  apply (rule hoare_conjI)
    apply (rule hoare_drop_imp)
      apply (clarsimp simp:load_hw_asid_def)
    apply wp
      apply (clarsimp simp:load_hw_asid_def)
    apply wp
done


lemma invalidate_asid_dwp[wp]:
  "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> invalidate_asid (the (hw_asid_table next_asid)) \<lbrace>\<lambda>x ps. transform ps = cs\<rbrace>"
  apply (clarsimp simp:invalidate_asid_def)
  apply wp
  apply (clarsimp simp:transform_def transform_objects_def2 transform_current_thread_def transform_cdt_def transform_asid_table_def)
done

lemma invalidate_asid_entry_dwp[wp]:
  "\<lbrace>\<lambda>ps. transform ps = cs\<rbrace> invalidate_asid_entry x \<lbrace>\<lambda>r ps. transform ps = cs\<rbrace>"
  apply (clarsimp simp:invalidate_asid_entry_def)
  apply wp
    apply (clarsimp simp:invalidate_asid_def)
    apply wp
    apply (clarsimp simp:invalidate_hw_asid_entry_def)
    apply wp
  apply (subgoal_tac "transform s = cs")
  prefer 2
    apply (assumption)
  apply (clarsimp simp:transform_def transform_objects_def2 transform_current_thread_def transform_cdt_def transform_asid_table_def)
  apply (clarsimp simp:load_hw_asid_def)
  apply wp
  apply (clarsimp simp:transform_def transform_objects_def2 transform_current_thread_def transform_cdt_def transform_asid_table_def)
done

lemma invalidate_hw_asid_entry_dwp[wp]:
  "\<lbrace>\<lambda>s. transform s = cs\<rbrace> invalidate_hw_asid_entry next_asid \<lbrace>\<lambda>xb a. transform a = cs\<rbrace>"
  apply (clarsimp simp:invalidate_hw_asid_entry_def)
  apply wp
  apply (clarsimp simp:transform_def transform_objects_def2 transform_current_thread_def transform_cdt_def transform_asid_table_def)
done

lemma set_current_pd_dwp[wp]:
  " \<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> setCurrentPD (Platform.addrFromPPtr x) \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  by (clarsimp simp:setCurrentPD_def,wp)

lemma set_hardware_asid_dwp[wp]:
  " \<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> setHardwareASID hw_asid \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
  by (clarsimp simp:setHardwareASID_def,wp)

lemma store_hardware_asid_dwp[wp]:
  "\<lbrace>\<lambda>s. transform s = cs\<rbrace> store_hw_asid a xa \<lbrace>\<lambda>xb a. transform a = cs\<rbrace>"
  apply (clarsimp simp:store_hw_asid_def)
  apply wp
  apply (simp add:find_pd_for_asid_assert_def)
  apply wp
  apply (simp add:find_pd_for_asid_def)
  apply (wp|wpc)+
  apply (clarsimp simp:transform_def transform_objects_def2 transform_current_thread_def transform_cdt_def transform_asid_table_def)
done

lemma  transform_arch_state:
  "\<lbrakk> arm_globals_frame (arch_state a) = arm_globals_frame x;
       arm_asid_table (arch_state a) = arm_asid_table x \<rbrakk>
    \<Longrightarrow> transform (a\<lparr>arch_state := x \<rparr>) = transform a"
  by (clarsimp simp:transform_def transform_objects_def2 transform_cdt_def
    transform_current_thread_def transform_asid_table_def)

lemma find_free_hw_asid_dwp[wp]:
  "\<lbrace>\<lambda>s. transform s = cs\<rbrace> find_free_hw_asid \<lbrace>\<lambda>xa s. transform s = cs\<rbrace>"
  apply (clarsimp simp:find_free_hw_asid_def)
  apply (wp|wpc)+
  apply (clarsimp simp:transform_arch_state)
  apply (wp do_machine_op_wp |clarsimp simp:)+
done

lemma arch_obj_not_idle:
  "\<lbrakk>valid_idle s;kheap s ptr = Some (ArchObj x )\<rbrakk> \<Longrightarrow> not_idle_thread ptr s"
  by (clarsimp simp:not_idle_thread_def valid_idle_def obj_at_def st_tcb_at_def)

lemma asid_pool_at_rev:
  "\<lbrakk> kheap s a = Some (ArchObj (arch_kernel_obj.ASIDPool fun)) \<rbrakk> \<Longrightarrow> asid_pool_at a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma asid_pool_not_idle:
  "\<lbrakk> valid_idle s; asid_pool_at a s \<rbrakk> \<Longrightarrow> not_idle_thread a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def not_idle_thread_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma opt_object_asid_pool:
  "\<lbrakk> valid_idle s; kheap s a = Some (ArchObj (arch_kernel_obj.ASIDPool fun)) \<rbrakk> \<Longrightarrow>
     opt_object a (transform s) = Some (cdl_object.AsidPool \<lparr>cdl_asid_pool_caps = transform_asid_pool_contents fun\<rparr>)"
  apply (frule asid_pool_at_rev)
  apply (frule(1) asid_pool_not_idle)
  apply (clarsimp simp:transform_objects_def opt_object_def transform_def
    not_idle_thread_def restrict_map_def)
done

lemma transform_asid_pool_contents_upd:
  "transform_asid_pool_contents (pool(ucast asid := pd)) =
   transform_asid_pool_contents pool(snd (transform_asid asid) \<mapsto> transform_asid_pool_entry pd)"
  apply (clarsimp simp:transform_asid_pool_contents_def transform_asid_def)
  apply (rule ext)
  apply (case_tac x)
   apply (clarsimp simp:unat_eq_0 unat_map_def)
  apply (safe | clarsimp)+
  apply (safe | clarsimp simp:unat_map_def)+
  apply (subst (asm) of_nat_Suc[symmetric])
  apply (rule_tac P="Suc nat = unat (ucast asid)" in notE, simp)
  apply (cut_tac x="Suc nat" and y="unat (ucast asid :: 10 word)" in word_unat.Abs_inject[symmetric, where 'a=10])
    apply (simp add:unats_def)+
   apply (rule unat_lt2p[where x="ucast asid :: 10 word", simplified])
  apply simp
  done

lemma dcorres_set_asid_pool:
  "\<lbrakk> pool' = pool (ucast asid := pd); slot = snd (transform_asid asid);
     cap = transform_asid_pool_entry pd \<rbrakk> \<Longrightarrow>
    dcorres dc \<top> (valid_idle and ko_at (ArchObj (arch_kernel_obj.ASIDPool pool)) a)
    (KHeap_D.set_cap (a, slot) cap)
    (set_asid_pool a pool')"
  apply (simp add:KHeap_D.set_cap_def set_asid_pool_def get_object_def gets_the_def
                  gets_def bind_assoc)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp:obj_at_def opt_object_asid_pool assert_opt_def has_slots_def)
  apply (clarsimp simp:KHeap_D.set_object_def simpler_modify_def put_def bind_def
                       corres_underlying_def update_slots_def return_def object_slots_def)
  apply (clarsimp simp:KHeap_A.set_object_def get_def put_def bind_def return_def)
  apply (clarsimp simp:transform_def transform_current_thread_def)
  apply (drule(1) arch_obj_not_idle)
  apply (rule ext)
  apply (clarsimp simp:not_idle_thread_def transform_objects_def restrict_map_def map_add_def)
  apply (rule transform_asid_pool_contents_upd)
  done

lemma dcorres_set_vm_root:
  "dcorres dc \<top> \<top> (return x) (set_vm_root rvd)"
  apply (clarsimp simp: set_vm_root_def)
  apply (rule dcorres_symb_exec_r)+
  apply (clarsimp simp:catch_def throwError_def)
    apply (rule corres_dummy_return_r)
    apply (rule dcorres_symb_exec_r[OF corres_free_return[where P=\<top> and P'=\<top>]])+
      apply wp
      apply wpc
      apply (wp do_machine_op_wp | clarsimp)+
      apply (rule_tac Q = "\<lambda>_ s. transform s = cs" in hoare_post_imp)
      apply simp
    apply (rule hoare_pre)
    apply (wp hoare_whenE_wp do_machine_op_wp [OF allI] hoare_drop_imps find_pd_for_asid_inv
      | wpc | simp add: set_current_asid_def get_hw_asid_def load_hw_asid_def if_apply_def2)+
   done

lemma dcorres_delete_asid_pool:
  "dcorres dc \<top> \<top>
    (CSpace_D.delete_asid_pool (transform_asid asid) oid)
    (ArchVSpace_A.delete_asid_pool asid oid)"
  apply (simp add:CSpace_D.delete_asid_pool_def ArchVSpace_A.delete_asid_pool_def)
  apply (rule dcorres_symb_exec_r[where Q'="\<lambda>rv. \<top>", simplified])
   apply (clarsimp simp:gets_def)
   apply (rule dcorres_absorb_get_r)
   apply (clarsimp simp:when_def)
   apply (rule conjI)
    prefer 2
    apply (clarsimp, rule corres_alternate2)
    apply (clarsimp simp: corres_return)
   apply clarsimp
   apply (rule corres_alternate1)
   apply (rule dcorres_absorb_get_l)
   apply (rule dcorres_symb_exec_r[where Q'="\<lambda>rv. \<top>", simplified])
    apply (rule dcorres_symb_exec_r[where Q'="\<lambda>rv. \<top>", simplified])
     apply (rule corres_dummy_return_l)
     apply (rule corres_underlying_split[where r'=dc and P="\<lambda>rv. \<top>" and P'="\<lambda>rv. \<top>", simplified])
      prefer 2
      apply clarsimp
      apply (rule dcorres_absorb_get_r)
      apply (rule corres_guard_imp)
        apply (rule dcorres_set_vm_root)
       apply clarsimp+
     apply (rule corres_guard_imp[where Q=\<top> and Q'=\<top>, simplified])
     apply (clarsimp simp:simpler_modify_def put_def bind_def corres_underlying_def)
     apply (clarsimp simp:transform_def transform_objects_def transform_cdt_def
                          transform_current_thread_def)
     apply (clarsimp simp:transform_asid_table_def)
     apply (rule ext)
     apply (clarsimp simp:unat_map_def asid_high_bits_of_def
                          transform_asid_table_entry_def transform_asid_def)
     apply safe
       apply (drule unat_cong)
       apply (subst (asm) word_unat.Abs_inverse)
        apply (clarsimp simp:unats_def unat_ucast)+
    apply (rule mapM_wp)
     apply clarsimp
     apply wp
    apply fastforce
   apply wp
  apply simp
done

lemma descendants_of_page:
  "\<lbrakk>valid_mdb s;page_table_at oid s\<rbrakk>\<Longrightarrow> KHeap_D.descendants_of (oid, 0) (transform s) = {}"
  apply (clarsimp simp:pspace_aligned_def obj_at_def a_type_def)
  apply (clarsimp split:arch_kernel_obj.split_asm Structures_A.kernel_object.split_asm if_splits)
  apply (rule ccontr)
  apply (clarsimp simp:valid_mdb_def dest!:not_emptyI)
  apply (frule(1) cdl_cdt_parent_cte_at_lift)
  apply clarsimp
  apply (simp add:descendants_of_eqv cte_at_cases)
  apply (clarsimp simp:transform_cslot_ptr_def)
done

lemma page_table_aligned:
  "\<lbrakk>pspace_aligned s;page_table_at oid s\<rbrakk> \<Longrightarrow>
         (oid && ~~ mask pt_bits) = oid"
  apply (clarsimp simp:pspace_aligned_def obj_at_def a_type_def)
  apply (clarsimp split:arch_kernel_obj.split_asm Structures_A.kernel_object.split_asm if_splits)
  apply (drule_tac x = oid in bspec)
    apply clarsimp
  apply (clarsimp simp:obj_bits_def arch_kobj_size_def pt_bits_def pageBits_def)
  apply (simp add:is_aligned_neg_mask_eq)
done

lemma invalidateTLB_VAASID_underlying_memory[wp]:
    "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace> invalidateTLB_VAASID word \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
    apply (clarsimp simp: invalidateTLB_VAASID_def, wp)
done

lemma dcorres_flush_page:
  "dcorres dc \<top> \<top>  (return x) (flush_page aa a b word)"
  apply (rule corres_dummy_return_r)
  apply (rule dcorres_symb_exec_r[OF corres_free_return[where P=\<top> and P'=\<top>]])
   apply wp
  apply (simp add:flush_page_def)
  apply wp
  apply (rule dcorres_to_wp[OF dcorres_set_vm_root])
  apply wp
  apply clarsimp
  apply (wp do_machine_op_wp, clarsimp)
   apply (wp)
  apply (simp add:load_hw_asid_def)
  apply wp
  apply (clarsimp simp:set_vm_root_for_flush_def)
    apply (wp do_machine_op_wp|clarsimp simp:set_current_asid_def get_hw_asid_def)+
    apply (wpc)
    apply wp
    apply (rule hoare_conjI,rule hoare_drop_imp)
      apply (wp do_machine_op_wp|clarsimp simp:load_hw_asid_def)+
    apply (wpc|wp)+
  apply (rule_tac Q="\<lambda>rv s. transform s = cs" in hoare_strengthen_post)
    apply (wp|clarsimp)+
done

lemma dcorres_flush_table:
  "dcorres dc \<top> \<top>  (return x) (flush_table aa a b word)"
  apply (rule corres_dummy_return_r)
  apply (rule dcorres_symb_exec_r[OF corres_free_return[where P=\<top> and P'=\<top>]])
   apply wp
  apply (simp add:flush_table_def)
  apply wp
       apply (rule dcorres_to_wp[OF dcorres_set_vm_root])
      apply wp
     apply clarsimp
     apply (wp do_machine_op_wp|clarsimp)+
    apply (clarsimp simp:load_hw_asid_def)
    apply wp
   apply (clarsimp simp:set_vm_root_for_flush_def)
   apply (wp do_machine_op_wp|clarsimp simp:set_current_asid_def get_hw_asid_def)+
         apply wpc
          apply wp
        apply (rule hoare_conjI,rule hoare_drop_imp)
         apply (wp do_machine_op_wp|clarsimp simp:load_hw_asid_def)+
     apply (wpc|wp)+
    apply (rule_tac Q="\<lambda>rv s. transform s = cs" in hoare_strengthen_post)
     apply (wp|clarsimp)+
done

lemma flush_table_exec:
  "\<lbrakk>dcorres dc R (Q rv) h (g rv); \<lbrace>P\<rbrace> flush_table aa a b word \<lbrace>Q\<rbrace>\<rbrakk>\<Longrightarrow>dcorres dc R P h ((flush_table aa a b word) >>= g)"
  apply (rule corres_dummy_return_pl)
  apply (rule corres_guard_imp)
  apply (rule corres_split[OF _ dcorres_flush_table])
  apply (simp|wp)+
  done


lemma transform_cap_not_new_invented:
  "transform_cap z \<noteq> cdl_cap.PageTableCap word Fake asid"
  by (auto simp:transform_cap_def split:arch_cap.splits cap.splits)

lemma page_table_not_idle:
  "\<lbrakk>valid_idle s;page_table_at a s\<rbrakk> \<Longrightarrow> not_idle_thread a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def not_idle_thread_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma page_directory_not_idle:
  "\<lbrakk>valid_idle s;page_directory_at a s\<rbrakk> \<Longrightarrow> not_idle_thread a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def not_idle_thread_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma page_table_at_rev:
  "\<lbrakk>kheap s a = Some (ArchObj (arch_kernel_obj.PageTable fun))\<rbrakk> \<Longrightarrow> page_table_at a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma page_directory_at_rev:
  "\<lbrakk>kheap s a = Some (ArchObj (arch_kernel_obj.PageDirectory fun))\<rbrakk> \<Longrightarrow> page_directory_at a s"
  apply (clarsimp simp:obj_at_def valid_idle_def st_tcb_at_def)
  apply (clarsimp simp:a_type_def
    split:arch_kernel_obj.splits Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits)
done

lemma mask_pd_bits_less':
  "uint ((ptr::word32) && mask pd_bits >> (2\<Colon>nat)) < (4096\<Colon>int)"
  apply (clarsimp simp:pd_bits_def pageBits_def)
  using shiftr_less_t2n'[where m = 12 and x ="(ptr && mask 14)" and n =2 ,simplified,THEN iffD1[OF word_less_alt]]
  apply (clarsimp simp:mask_twice )
done

lemma mask_pd_bits_less:
  "nat (uint ((y::word32) && mask pd_bits >> 2)) < 4096"
  apply (clarsimp simp:pd_bits_def pageBits_def)
  apply (rule iffD2[OF nat_less_eq_zless[where z = 4096,simplified]])
  apply (simp)
  using shiftr_less_t2n'[where m = 12 and x ="(y && mask 14)" and n =2 ,simplified,THEN iffD1[OF word_less_alt]]
  apply (clarsimp simp:mask_twice)
done

lemma mask_pt_bits_less':
  "uint (((ptr::word32) && mask pt_bits) >> 2)< 256"
  apply (clarsimp simp:pt_bits_def pageBits_def)
  using shiftr_less_t2n'[where m = 8 and x ="(ptr && mask 10)" and n =2 ,simplified,THEN iffD1[OF word_less_alt]]
  apply (clarsimp simp:mask_twice )
done

lemma mask_pt_bits_less:
  "nat (uint ((y::word32) && mask pt_bits >> 2)) < 256"
  apply (clarsimp simp:pt_bits_def pageBits_def)
  apply (rule iffD2[OF nat_less_eq_zless[where z = 256,simplified]])
  apply (simp)
  using shiftr_less_t2n'[where m = 8 and x ="(y && mask 10)" and n =2 ,simplified,THEN iffD1[OF word_less_alt]]
  apply (clarsimp simp:mask_twice)
done

definition pd_pt_relation :: "word32\<Rightarrow>word32\<Rightarrow>word32\<Rightarrow>'z::state_ext state\<Rightarrow>bool"
where "pd_pt_relation pd pt offset s \<equiv>
  \<exists>fun u v ref. ( kheap s pd = Some (ArchObj (arch_kernel_obj.PageDirectory fun))
  \<and> page_table_at pt s \<and> fun (ucast (offset && mask pd_bits >> 2)) = ARM_Structs_A.pde.PageTablePDE ref u v
  \<and> pt = Platform.ptrFromPAddr ref )"

definition pd_section_relation :: "word32\<Rightarrow>word32\<Rightarrow>word32\<Rightarrow>'z::state_ext state\<Rightarrow>bool"
where "pd_section_relation pd pt offset s \<equiv>
  \<exists>fun u v ref1 ref2. ( kheap s pd = Some (ArchObj (arch_kernel_obj.PageDirectory fun))
  \<and> fun (ucast (offset && mask pd_bits >> 2)) = ARM_Structs_A.pde.SectionPDE ref1 u ref2 v
  \<and> pt = Platform.ptrFromPAddr ref1 )"

definition pd_super_section_relation :: "word32\<Rightarrow>word32\<Rightarrow>word32\<Rightarrow>'z::state_ext state\<Rightarrow>bool"
where "pd_super_section_relation pd pt offset s \<equiv>
  \<exists>fun u v ref1. ( kheap s pd = Some (ArchObj (arch_kernel_obj.PageDirectory fun))
  \<and> fun (ucast (offset && mask pd_bits >> 2)) = ARM_Structs_A.pde.SuperSectionPDE ref1 u v
  \<and> pt = Platform.ptrFromPAddr ref1 )"


definition pt_page_relation :: "word32\<Rightarrow>word32\<Rightarrow>word32\<Rightarrow>vmpage_size set\<Rightarrow>'z::state_ext state\<Rightarrow>bool"
where "pt_page_relation pt page offset S s \<equiv>
  \<exists>fun. (kheap s pt = Some (ArchObj (arch_kernel_obj.PageTable fun)))
  \<and> (case fun (ucast (offset && mask pt_bits >> 2)) of
    ARM_Structs_A.pte.LargePagePTE ref fun1 fun2 \<Rightarrow>
        page = Platform.ptrFromPAddr ref \<and> ARMLargePage \<in> S
  | ARM_Structs_A.pte.SmallPagePTE ref fun1 fun2 \<Rightarrow>
        page = Platform.ptrFromPAddr ref \<and> ARMSmallPage \<in> S
  | _ \<Rightarrow> False)"

lemma slot_with_pt_frame_relation:
  "\<lbrakk>valid_idle s;pt_page_relation a oid y S s\<rbrakk>\<Longrightarrow>
    (a, nat (uint (y && mask pt_bits >> 2))) \<in>
    ((slots_with (\<lambda>x. \<exists>rights sz asid. x = FrameCap oid rights sz Fake asid)) (transform s))"
  apply (clarsimp simp:pt_page_relation_def)
  apply (frule page_table_at_rev)
  apply (frule(1) page_table_not_idle)
  apply (clarsimp simp:slots_with_def transform_def transform_objects_def restrict_map_def)
  apply (clarsimp simp:not_idle_thread_def has_slots_def object_slots_def)
  apply (clarsimp simp:transform_page_table_contents_def transform_pte_def unat_map_def ucast_def)
  apply (simp add:word_of_int_nat[OF uint_ge_0,simplified] )
  apply (clarsimp simp:mask_pt_bits_less split:ARM_Structs_A.pte.split_asm)
done

lemma below_kernel_base:
  "ucast (y && mask pd_bits >> 2) \<notin> kernel_mapping_slots
    \<Longrightarrow> kernel_pde_mask f (of_nat (unat (y && mask pd_bits >> 2)))
    = f (of_nat (unat (y && mask pd_bits >> 2)))"
  apply (clarsimp simp:kernel_pde_mask_def kernel_mapping_slots_def )
  apply (simp add:ucast_nat_def[symmetric] unat_def)
done

lemma slot_with_pd_pt_relation:
  "\<lbrakk>valid_idle s; pd_pt_relation a b y s; ucast (y && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk> \<Longrightarrow>
  (a, unat (y && mask pd_bits >> 2)) \<in>
    (slots_with (\<lambda>x. \<exists>asid. x = cdl_cap.PageTableCap b Fake asid)) (transform s)"
  apply (clarsimp simp :pd_pt_relation_def)
  apply (frule page_directory_at_rev)
  apply (frule(1) page_directory_not_idle)
  apply (clarsimp simp:transform_def slots_with_def transform_objects_def obj_at_def)
  apply (clarsimp simp:restrict_map_def a_type_def page_table_not_idle not_idle_thread_def pt_bits_def
    split:Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits arch_kernel_obj.splits)
  apply (clarsimp simp:has_slots_def object_slots_def)
  apply (clarsimp simp:transform_page_directory_contents_def transform_pde_def unat_map_def below_kernel_base)
  apply (clarsimp simp:ucast_def)
  apply (simp add: word_of_int_nat[OF uint_ge_0,simplified] unat_def below_kernel_base)
  apply (simp add:mask_pd_bits_less)
done

lemma slot_with_pd_section_relation:
  "\<lbrakk>valid_idle s; pd_super_section_relation a b y s \<or> pd_section_relation a b y s;
    ucast (y && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk> \<Longrightarrow>
  (a, unat (y && mask pd_bits >> 2)) \<in>
    (slots_with (\<lambda>x. \<exists>rights sz asid. x = cdl_cap.FrameCap b rights sz Fake asid)) (transform s)"
  apply (erule disjE)
    apply (clarsimp simp :pd_super_section_relation_def)
    apply (frule page_directory_at_rev)
    apply (frule(1) page_directory_not_idle)
    apply (clarsimp simp:transform_def slots_with_def transform_objects_def obj_at_def)
    apply (clarsimp simp:restrict_map_def a_type_def page_table_not_idle not_idle_thread_def pt_bits_def
    split:Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits arch_kernel_obj.splits)
     apply (clarsimp simp:has_slots_def object_slots_def)
    apply (clarsimp simp:transform_page_directory_contents_def transform_pde_def unat_map_def below_kernel_base)
    apply (clarsimp simp:ucast_def)
    apply (simp add: word_of_int_nat[OF uint_ge_0,simplified] unat_def mask_pd_bits_less)
  apply (clarsimp simp :pd_section_relation_def)
  apply (frule page_directory_at_rev)
  apply (frule(1) page_directory_not_idle)
  apply (clarsimp simp:transform_def slots_with_def transform_objects_def obj_at_def)
  apply (clarsimp simp:restrict_map_def a_type_def page_table_not_idle not_idle_thread_def pt_bits_def
    split:Structures_A.kernel_object.split_asm if_splits arch_kernel_object.splits arch_kernel_obj.splits)
  apply (clarsimp simp:has_slots_def object_slots_def)
  apply (clarsimp simp:transform_page_directory_contents_def transform_pde_def unat_map_def below_kernel_base)
  apply (clarsimp simp:ucast_def)
  apply (simp add: word_of_int_nat[OF uint_ge_0,simplified] unat_def)
  apply (simp add:mask_pd_bits_less)
done

lemma opt_cap_page_table:"\<lbrakk>valid_idle s;pd_pt_relation a pt_id x s;ucast (x && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk>\<Longrightarrow>
(opt_cap (a, unat (x && mask pd_bits >> 2) ) (transform s))
  = Some (cdl_cap.PageTableCap pt_id Fake None)"
  apply (clarsimp simp:pd_pt_relation_def opt_cap_def transform_def unat_def slots_of_def opt_object_def)
  apply (frule page_directory_at_rev)
  apply (frule(1) page_directory_not_idle)
  apply (clarsimp simp:transform_objects_def not_idle_thread_def page_directory_not_idle
    restrict_map_def object_slots_def)
  apply (clarsimp simp:transform_page_directory_contents_def unat_def[symmetric] unat_map_def | rule conjI )+
    apply (clarsimp simp:transform_page_directory_contents_def unat_map_def transform_pde_def)
  apply (clarsimp simp:below_kernel_base)
    apply (simp add:word_of_int_nat[OF uint_ge_0,simplified] unat_def ucast_def)
  apply (simp add:mask_pd_bits_less unat_def)
done

lemma opt_cap_page:"\<lbrakk>valid_idle s;pt_page_relation a pg x S s \<rbrakk>\<Longrightarrow>
\<exists>f sz. (opt_cap (a, unat (x && mask pt_bits >> 2) ) (transform s))
  = Some (cdl_cap.FrameCap pg f sz Fake None)"
  apply (clarsimp simp:pt_page_relation_def unat_def opt_cap_def transform_def slots_of_def opt_object_def)
  apply (frule page_table_at_rev)
  apply (frule(1) page_table_not_idle)
  apply (clarsimp simp:transform_objects_def not_idle_thread_def page_directory_not_idle
    restrict_map_def object_slots_def)
  apply (clarsimp simp:transform_page_table_contents_def unat_map_def split:ARM_Structs_A.pte.split_asm | rule conjI )+
    apply (clarsimp simp:transform_page_table_contents_def unat_map_def transform_pte_def)
    apply (simp add:word_of_int_nat[OF uint_ge_0,simplified] ucast_def mask_pt_bits_less)+
    apply (clarsimp simp:transform_page_table_contents_def unat_map_def transform_pte_def)
done

lemma opt_cap_section:
  "\<lbrakk>valid_idle s;pd_section_relation a pg x s \<or> pd_super_section_relation a pg x s;
    ucast (x && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk>\<Longrightarrow>
  \<exists>f sz. (opt_cap (a, unat (x && mask pd_bits >> 2) ) (transform s))
    = Some (cdl_cap.FrameCap pg f sz Fake None)"
  unfolding unat_def
  apply (erule disjE)
    apply (clarsimp simp: pd_section_relation_def opt_cap_def transform_def slots_of_def opt_object_def)
    apply (frule page_directory_at_rev)
    apply (frule(1) page_directory_not_idle)
    apply (clarsimp simp:transform_objects_def not_idle_thread_def page_directory_not_idle
    restrict_map_def object_slots_def)
    apply (clarsimp simp:transform_page_directory_contents_def unat_map_def split:ARM_Structs_A.pte.split_asm | rule conjI)+
      apply (clarsimp simp:transform_page_directory_contents_def unat_map_def transform_pde_def unat_def[symmetric] below_kernel_base)
      apply (simp add:word_of_int_nat[OF uint_ge_0,simplified] ucast_def unat_def mask_pt_bits_less)+
    apply (simp add:mask_pd_bits_less)
  apply (clarsimp simp:pd_super_section_relation_def opt_cap_def transform_def slots_of_def opt_object_def)
  apply (frule page_directory_at_rev)
  apply (frule(1) page_directory_not_idle)
  apply (clarsimp simp:transform_objects_def not_idle_thread_def page_directory_not_idle
    restrict_map_def object_slots_def)
  apply (clarsimp simp:transform_page_directory_contents_def unat_map_def split:ARM_Structs_A.pte.split_asm | rule conjI)+
  apply (clarsimp simp:transform_page_directory_contents_def unat_map_def transform_pde_def unat_def[symmetric] below_kernel_base)
  apply (simp add:word_of_int_nat[OF uint_ge_0,simplified] ucast_def unat_def mask_pt_bits_less)+
  apply (simp add:mask_pd_bits_less)
done

lemma opt_object_page_table:"\<lbrakk>valid_idle s;kheap s a = Some (ArchObj (arch_kernel_obj.PageTable fun))\<rbrakk>
\<Longrightarrow>opt_object a (transform s) =
  Some (cdl_object.PageTable \<lparr>cdl_page_table_caps = transform_page_table_contents fun\<rparr>)"
  apply (frule page_table_at_rev)
  apply (frule(1) page_table_not_idle)
  apply (clarsimp simp:transform_objects_def opt_object_def transform_def
    not_idle_thread_def restrict_map_def)
done

lemma opt_object_page_directory:"\<lbrakk>valid_idle s;kheap s a = Some (ArchObj (arch_kernel_obj.PageDirectory fun))\<rbrakk>
\<Longrightarrow>opt_object a (transform s) =
  Some (cdl_object.PageDirectory \<lparr>cdl_page_directory_caps = transform_page_directory_contents fun\<rparr>)"
  apply (frule page_directory_at_rev)
  apply (frule(1) page_directory_not_idle)
  apply (clarsimp simp:transform_objects_def opt_object_def transform_def
    not_idle_thread_def restrict_map_def)
done

lemma remove_cdt_pt_slot_exec:
  "\<lbrakk>dcorres dc \<top> Q (g ()) f;
   \<And>s. Q s\<longrightarrow> ( (\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s)) and valid_idle and pt_page_relation a pg_id ptr UNIV) s\<rbrakk>
    \<Longrightarrow> dcorres dc P Q
    (remove_parent (a ,aptr) >>= g) f"
  apply (rule corres_dummy_return_pr)
  apply (rule corres_guard_imp)
  apply (rule corres_split[OF _ dummy_remove_cdt_pt_slot])
    apply (rule_tac F="rv = ()" in corres_gen_asm)
    unfolding K_bind_def
    apply clarsimp
  apply (assumption)
  apply (simp|wp)+
  apply (drule_tac x = s in meta_spec)
  apply (clarsimp simp:pt_page_relation_def dest!:page_table_at_rev)
done

lemma remove_cdt_pd_slot_exec:
  "\<lbrakk>dcorres dc \<top> Q (g ()) f;
   \<And>s. Q s\<longrightarrow> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s)) and valid_idle and page_directory_at a) s\<rbrakk>
    \<Longrightarrow> dcorres dc P Q
    (remove_parent (a ,aptr) >>= g) f"
  apply (rule corres_dummy_return_pr)
  apply (rule corres_guard_imp)
  apply (rule corres_split[OF _ dummy_remove_cdt_pd_slot])
    unfolding K_bind_def
  apply (simp|wp)+
done

lemma remove_cdt_asid_pool_slot_exec:
  "\<lbrakk>dcorres dc \<top> Q (g ()) f;
   \<And>s. Q s\<longrightarrow> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s)) and valid_idle and asid_pool_at a) s\<rbrakk>
    \<Longrightarrow> dcorres dc P Q
    (remove_parent (a ,aptr) >>= g) f"
  apply (rule corres_dummy_return_pr)
  apply (rule corres_guard_imp)
  apply (rule corres_split[OF _ dummy_remove_cdt_asid_pool_slot])
    unfolding K_bind_def
  apply (simp|wp)+
done

lemma dcorres_set_pte_cap:
  "\<lbrakk> (x::word32) = (ptr && mask pt_bits >> 2);pte_cap = transform_pte a_pte\<rbrakk>\<Longrightarrow>
    dcorres dc \<top> (valid_idle and ko_at (ArchObj (arch_kernel_obj.PageTable fun)) a )
    (KHeap_D.set_cap (a, unat (ptr && mask pt_bits >> 2)) pte_cap)
    (KHeap_A.set_object a
      (ArchObj (arch_kernel_obj.PageTable (fun(ucast (ptr && mask pt_bits >> 2) := a_pte)))))"
  apply (simp add:KHeap_D.set_cap_def KHeap_A.set_object_def gets_the_def gets_def bind_assoc unat_def)
  apply (rule dcorres_absorb_get_r)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp:obj_at_def opt_object_page_table assert_opt_def has_slots_def object_slots_def)
  apply (clarsimp simp:KHeap_D.set_object_def simpler_modify_def put_def bind_def
                       corres_underlying_def update_slots_def return_def object_slots_def)
  apply (rule sym)
  apply (clarsimp simp:transform_def transform_current_thread_def)
  apply (rule ext)
  apply (clarsimp | rule conjI)+
    apply (frule page_table_at_rev)
    apply (frule(1) page_table_not_idle)
    apply (clarsimp simp:transform_objects_def not_idle_thread_def)
    apply (rule ext)
      apply (clarsimp simp:transform_page_table_contents_def transform_pte_def unat_map_def ucast_def)
      apply (clarsimp simp:word_of_nat mask_pt_bits_less ucast_def)
        apply (subst (asm) word_of_int_inj)
        apply (clarsimp simp:mask_pt_bits_less')+
    apply (clarsimp simp:uint_nat)
  apply clarify
  apply (clarsimp simp: transform_objects_def restrict_map_def map_add_def)
done

lemma dcorres_delete_cap_simple_set_pt:
  "dcorres dc \<top> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s))
       and pt_page_relation (ptr && ~~ mask pt_bits) pg_id ptr UNIV
       and valid_idle and ko_at (ArchObj (arch_kernel_obj.PageTable fun)) (ptr && ~~ mask pt_bits))
    (delete_cap_simple (ptr && ~~ mask pt_bits, unat (ptr && mask pt_bits >> 2)))
    (set_pt (ptr && ~~ mask pt_bits) (fun(ucast (ptr && mask pt_bits >> 2) := ARM_Structs_A.pte.InvalidPTE)))"
  apply (simp add:delete_cap_simple_def set_pt_def gets_the_def gets_def bind_assoc get_object_def)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:assert_def corres_free_fail
    split:Structures_A.kernel_object.split_asm arch_kernel_obj.splits)
  apply (frule opt_cap_page)
    apply (simp add:)+
  apply (clarsimp simp:gets_def assert_opt_def PageTableUnmap_D.is_final_cap_def PageTableUnmap_D.is_final_cap'_def)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp: always_empty_slot_def gets_the_def gets_def bind_assoc)
  apply (rule remove_cdt_pt_slot_exec[where pg_id = pg_id])
   apply (rule corres_guard_imp)
     apply (rule dcorres_set_pte_cap)
      apply (simp add:transform_pte_def)+
  apply clarsimp
  apply simp
  done

lemma dcorres_unmap_page_table_empty:
  " dcorres dc \<top> \<top>
              (PageTableUnmap_D.unmap_page_table word) (return a)"
  apply (simp add:PageTableUnmap_D.unmap_page_table_def)
  apply (rule corres_symb_exec_l)
    apply (rule_tac P =\<top> in  select_pick_corres[where x="[]"])
      apply (clarsimp simp:mapM_x_def revoke_cap_simple_def sequence_x_def)
    apply (simp add:validE_def exs_valid_def gets_def in_monad bind_def get_def return_def)
    apply wp
    apply clarsimp+
  done

lemma transform_page_table_contents_upd:
  "transform_page_table_contents fun(unat (y && mask pt_bits >> 2) \<mapsto> transform_pte pte) =
            transform_page_table_contents
             (fun(ucast ((y::word32) && mask pt_bits >> 2) := pte))"
  apply (rule ext)
  apply (clarsimp simp:transform_page_table_contents_def unat_map_def )
  apply (clarsimp simp:ucast_nat_def[symmetric])
  apply (subgoal_tac "unat (y && mask pt_bits >> 2) < 256")
  apply (rule conjI|clarsimp)+
    apply (drule word_unat.Abs_eqD)
     apply (simp add: unats_def)+
  apply (rule unat_less_helper)
  apply (subst shiftr_div_2n_w)
  apply (clarsimp simp:word_size)+
  apply (rule word_div_mult,simp)
  apply (clarsimp simp:pt_bits_def pageBits_def)
  apply (rule and_mask_less_size[where n = 10,simplified],simp add:word_size)
done

lemma transform_page_directory_contents_upd:
  "ucast ((ptr::word32) && mask pd_bits >> 2) \<notin> kernel_mapping_slots
  \<Longrightarrow> transform_page_directory_contents f(unat (ptr && mask pd_bits >> 2) \<mapsto> transform_pde a_pde)
   =  transform_page_directory_contents (f(ucast (ptr && mask pd_bits >> 2) := a_pde))"
  apply (rule ext)
    apply (simp (no_asm) add:transform_page_directory_contents_def unat_map_def)
    apply (simp add:below_kernel_base)
      apply (clarsimp simp: unat_def mask_pd_bits_less|rule conjI)+
      apply (clarsimp simp:kernel_pde_mask_def kernel_mapping_slots_def)
      apply (clarsimp simp:ucast_nat_def[symmetric])
      apply (drule sym)
      apply (clarsimp simp:unat_def)
      apply (drule word_unat.Abs_eqD)
        apply (simp add:unats_def unat_def[symmetric])+
      apply (rule unat_less_helper)
      apply (subst shiftr_div_2n_w,(simp add:word_size)+)
      apply (rule word_div_mult,simp)
      apply (clarsimp simp:pt_bits_def pd_bits_def pageBits_def)
      apply (rule and_mask_less_size[where n = 14,simplified],simp add:word_size)
    apply simp
    apply (clarsimp simp:ucast_def word_of_int_nat[OF uint_ge_0,simplified])
done

lemma dcorres_set_pde_cap:
  "\<lbrakk> (x::word32) = (ptr && mask pd_bits >> 2);pde_cap = transform_pde a_pde; ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk>\<Longrightarrow>
    dcorres dc \<top> (valid_idle and ko_at (ArchObj (arch_kernel_obj.PageDirectory fun)) a )
      (KHeap_D.set_cap (a, unat x) pde_cap)
      (KHeap_A.set_object a (ArchObj
                 (arch_kernel_obj.PageDirectory (fun(ucast x := a_pde)))))"
  apply (simp add:KHeap_D.set_cap_def KHeap_A.set_object_def gets_the_def gets_def bind_assoc)
  apply (rule dcorres_absorb_get_r)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp:obj_at_def opt_object_page_directory assert_opt_def has_slots_def object_slots_def)
  apply (clarsimp simp:KHeap_D.set_object_def simpler_modify_def put_def bind_def corres_underlying_def update_slots_def object_slots_def return_def)
  apply (clarsimp simp:transform_def transform_current_thread_def)
    apply (rule ext)
    apply (clarsimp | rule conjI)+
      apply (frule page_directory_at_rev)
      apply (frule(1) page_directory_not_idle)
      apply (clarsimp simp:transform_objects_def not_idle_thread_def)
      apply (rule sym)
      apply (erule transform_page_directory_contents_upd)
   apply (clarsimp simp: transform_objects_def restrict_map_def map_add_def)
done


lemma dcorres_delete_cap_simple_set_pde:
  " ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots
    \<Longrightarrow>dcorres dc \<top> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s))
    and (pd_pt_relation (ptr && ~~ mask pd_bits) oid ptr
         or pd_section_relation (ptr && ~~ mask pd_bits) oid ptr
         or pd_super_section_relation (ptr && ~~ mask pd_bits) oid ptr)
    and valid_idle and ko_at (ArchObj (arch_kernel_obj.PageDirectory fun)) (ptr && ~~ mask pd_bits))
             (delete_cap_simple (ptr && ~~ mask pd_bits, unat (ptr && mask pd_bits >> 2)))
             (set_pd (ptr && ~~ mask pd_bits) (fun(ucast (ptr && mask pd_bits >> 2) := ARM_Structs_A.pde.InvalidPDE)))"
  apply (simp add:delete_cap_simple_def set_pd_def gets_the_def gets_def bind_assoc get_object_def)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:assert_def corres_free_fail
    split:Structures_A.kernel_object.split_asm arch_kernel_obj.splits)
  apply (erule disjE)
    apply (frule opt_cap_page_table,simp+)
    apply (clarsimp simp:gets_def assert_opt_def PageTableUnmap_D.is_final_cap_def PageTableUnmap_D.is_final_cap'_def)
    apply (rule dcorres_absorb_get_l)
    apply (clarsimp simp:always_empty_slot_def gets_the_def gets_def bind_assoc)
    apply (rule remove_cdt_pd_slot_exec)
      apply (rule corres_guard_imp)
      apply (rule dcorres_set_pde_cap)
    apply (simp add:transform_pte_def)+
    apply (clarsimp simp:pd_pt_relation_def transform_pde_def)+
    apply (rule page_directory_at_rev)
    apply simp
  apply (frule opt_cap_section,simp+)
    apply (clarsimp simp:gets_def assert_opt_def PageTableUnmap_D.is_final_cap_def PageTableUnmap_D.is_final_cap'_def)
    apply (rule dcorres_absorb_get_l)
    apply (clarsimp simp:always_empty_slot_def gets_the_def gets_def bind_assoc)
    apply (rule remove_cdt_pd_slot_exec)
      apply (rule corres_guard_imp)
      apply (rule dcorres_set_pde_cap)
    apply simp+
    apply (clarsimp simp:pd_pt_relation_def transform_pde_def)+
    apply (rule page_directory_at_rev)
    apply simp
done

lemma large_frame_range_helper:
  "t \<in> set [0 , 4 .e. 0x3C] \<Longrightarrow> t < 0x40"
  apply (clarsimp simp: upto_enum_step_def)
  apply (subgoal_tac "x < 0x10")
    apply (subst mult_commute)
    apply (subst shiftl_t2n[where n =2,simplified,symmetric])
    apply (rule shiftl_less_t2n[where m = 6 and n =2,simplified])
       apply simp+
    apply (rule le_less_trans)
    apply simp+
done

lemma dcorres_unmap_page_single:
  "dcorres dc \<top> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s))
      and valid_idle and pspace_aligned and pt_page_relation (ptr && ~~ mask pt_bits) pg_id ptr UNIV)
        (PageTableUnmap_D.unmap_page pg_id)
     (store_pte ptr ARM_Structs_A.pte.InvalidPTE)"
  apply (simp add:store_pte_def PageTableUnmap_D.unmap_page_def)
  apply (simp add:gets_def get_pt_def get_object_def bind_assoc)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:assert_def corres_free_fail
    split:Structures_A.kernel_object.split_asm arch_kernel_obj.splits)
   apply (frule_tac slot_with_pt_frame_relation)
     apply simp
   apply (clarsimp simp:pt_page_relation_def assert_def)
   apply (clarsimp split: ARM_Structs_A.pte.split_asm)
     apply (rule corres_guard_imp)
     apply (rule_tac x =  "[(ptr && ~~ mask pt_bits, nat(uint (ptr && mask pt_bits >> 2)))  ]" in select_pick_corres [where P=\<top> ])
     apply (clarsimp simp:mapM_x_def sequence_x_def unat_def[symmetric])
     apply (rule_tac pg_id = "Platform.ptrFromPAddr word" in dcorres_delete_cap_simple_set_pt)
     apply (clarsimp simp:pt_page_relation_def obj_at_def obj_at_def)+
   apply (rule corres_guard_imp)
   apply (rule_tac x =  "[(ptr && ~~ mask pt_bits, nat(uint (ptr && mask pt_bits >> 2)))  ]" in select_pick_corres [where P=\<top> ])
   apply (clarsimp simp:mapM_x_def sequence_x_def unat_def[symmetric])
   apply (rule_tac pg_id = "Platform.ptrFromPAddr word" in dcorres_delete_cap_simple_set_pt)
   apply (clarsimp simp:pt_page_relation_def obj_at_def obj_at_def)+
done

lemma dcorres_unmap_section_single:
  " ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots
  \<Longrightarrow> dcorres dc \<top> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s))
      and valid_idle and pspace_aligned and
      (pd_section_relation (ptr && ~~ mask pd_bits) pg_id ptr
       or pd_super_section_relation (ptr && ~~ mask pd_bits) pg_id ptr))
    (PageTableUnmap_D.unmap_page pg_id)
    (store_pde ptr ARM_Structs_A.pde.InvalidPDE)"
  apply (simp add:store_pde_def PageTableUnmap_D.unmap_page_def)
  apply (simp add:gets_def get_pd_def get_object_def bind_assoc)
  apply (rule dcorres_absorb_get_l)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:assert_def corres_free_fail
    split:Structures_A.kernel_object.split_asm arch_kernel_obj.splits)
  apply (frule_tac slot_with_pd_section_relation)
    apply fastforce
    apply simp+
  apply (erule disjE)
    apply (clarsimp simp:pd_section_relation_def assert_def)
    apply (rule corres_guard_imp)
     apply (rule_tac x =  "[(ptr && ~~ mask pd_bits, nat(uint (ptr && mask pd_bits >> 2)))  ]"
       in select_pick_corres [where P=\<top> ])
     apply (clarsimp simp:mapM_x_def sequence_x_def unat_def[symmetric])
     apply (rule_tac oid = "Platform.ptrFromPAddr ref1" in dcorres_delete_cap_simple_set_pde)
     apply (clarsimp simp:pd_section_relation_def obj_at_def obj_at_def unat_def)+
  apply (clarsimp simp:pd_super_section_relation_def assert_def)
  apply (rule corres_guard_imp)
  apply (rule_tac x =  "[(ptr && ~~ mask pd_bits, nat(uint (ptr && mask pd_bits >> 2)))  ]"
    in select_pick_corres [where P=\<top> ])
  apply (clarsimp simp:mapM_x_def sequence_x_def unat_def[symmetric])
  apply (rule_tac oid = "Platform.ptrFromPAddr ref1" in dcorres_delete_cap_simple_set_pde)
  apply (clarsimp simp:pd_super_section_relation_def obj_at_def obj_at_def unat_def)+
done

lemma zip_map_eqv:
  "(y, x) \<in> set (zip (map g xs) (map f xs)) = (\<exists>t. (y = g t \<and> x = f t \<and> t \<in> set xs))"
  apply (clarsimp simp:zip_map1 zip_map2)
  apply (rule iffI)
    apply fastforce
  apply (clarsimp simp:set_zip_same)
  using imageI[where f ="(\<lambda>(a, b). (a, f b)) \<circ> (\<lambda>(x, y). (g x, y))",simplified]
  apply clarify
  apply (drule_tac x = t in meta_spec)
  apply (drule_tac x = t in meta_spec)
  apply (drule_tac x = "Id \<inter> (set xs) \<times> (set xs) " in meta_spec)
  apply clarsimp
done

lemma page_directory_address_eq:
  "\<lbrakk>is_aligned ptr 6; t \<in> set [0 , 4 .e. 0x3C]\<rbrakk> \<Longrightarrow> ptr && ~~ mask pd_bits = ptr + t && ~~ mask pd_bits"
  apply (drule large_frame_range_helper)
  using mask_lower_twice[where m = 14 and n = 6 and x= ptr,symmetric]
  apply (clarsimp simp:pd_bits_def pageBits_def pageBits_def)
  using mask_lower_twice[where m = 14 and n = 6 and x= "ptr+t",symmetric]
  apply (clarsimp simp:pd_bits_def pageBits_def pageBits_def)
  apply (subgoal_tac "(ptr && ~~ mask 6)  = (ptr + t && ~~ mask 6)")
    apply simp
  apply (frule is_aligned_neg_mask_eq)
    apply simp
  apply (drule_tac q = t in mask_out_add_aligned)
  apply (subst(asm) less_mask_eq [THEN mask_eq_x_eq_0[THEN iffD1]], erule order_less_le_trans)
  apply clarsimp+
done

lemma page_table_address_eq:
  "\<lbrakk>is_aligned ptr 6; t \<in> set [0 , 4 .e. 0x3C]\<rbrakk> \<Longrightarrow> ptr && ~~ mask pt_bits = ptr + t && ~~ mask pt_bits"
  apply (drule large_frame_range_helper)
  using mask_lower_twice[where m = 10 and n = 6 and x= ptr,symmetric]
  apply (clarsimp simp:pt_bits_def pageBits_def pageBits_def)
  using mask_lower_twice[where m = 10 and n = 6 and x= "ptr+t",symmetric]
  apply (clarsimp simp:pt_bits_def pageBits_def pageBits_def)
  apply (subgoal_tac "(ptr && ~~ mask 6)  = (ptr + t && ~~ mask 6)")
    apply simp
  apply (frule is_aligned_neg_mask_eq)
    apply simp
  apply (drule_tac q = t in mask_out_add_aligned)
  apply (subst(asm) less_mask_eq [THEN mask_eq_x_eq_0[THEN iffD1]], erule order_less_le_trans)
  apply clarsimp+
done

lemma shiftl_inj_if:
  "\<lbrakk>(shiftl a n) = (shiftl b n); shiftr (shiftl a n) n = a; shiftr (shiftl b n) n = b\<rbrakk> \<Longrightarrow> a = b"
 apply (drule arg_cong[where f = "\<lambda>x. shiftr x n"])
 apply (rule box_equals)
 defer
 apply (assumption)+
done

lemma ucast_inj_mask:
  "((ucast (x::'a::len word)) :: ('b::len word)) = ((ucast (y::'a::len word)) :: ('b::len word))
    \<Longrightarrow> (x && mask (len_of TYPE('b))) = (y && mask (len_of TYPE('b)))"
  apply (simp add:ucast_def)
  apply (simp add:word_ubin.inverse_norm)
  apply (simp add:word_ubin.eq_norm)
  apply (simp add:and_mask_bintr)
done

lemma split_word_noteq_on_mask:
  "(x \<noteq> y)  =  (x && mask k \<noteq> y && mask k \<or> x && ~~ mask k \<noteq> y && ~~ mask k)"
  apply (rule iffI)
  using split_word_eq_on_mask[symmetric]
  apply auto
done

lemma test_bits_mask:
  "\<lbrakk>x && mask l = y && mask l;na < size x; size x = size y\<rbrakk>
  \<Longrightarrow> na<l \<longrightarrow> x !! na = y !! na"
  apply (drule word_eqD)
  apply (auto simp:word_size)
done

lemma test_bits_neg_mask:
  "\<lbrakk>x && ~~ mask l = y && ~~ mask l;na < size x; size x = size y\<rbrakk>
  \<Longrightarrow> l\<le> na \<longrightarrow> x !! na = y !! na"
  apply (drule word_eqD)
  apply (auto simp:word_size neg_mask_bang)
done

lemma mask_compare_imply:
  "\<lbrakk> (x && mask k >> l) && mask n = (y && mask k >> l) && mask n;size x= size y; k\<le> size x; l+n \<le> k; x\<noteq>y\<rbrakk>
    \<Longrightarrow> (x && mask l \<noteq>y && mask l) \<or> (x && ~~ mask (l+n)) \<noteq> (y && ~~ mask (l+n))"
  apply (rule ccontr)
  apply (subgoal_tac "x = y")
    apply simp
  apply (rule word_eqI)
  apply clarsimp
  apply (case_tac "na<l")
    apply (drule_tac na = na in test_bits_mask[where l = l and y = y])
    apply clarsimp+
  apply (case_tac "l+n\<le> na")
    apply (drule_tac na = na in test_bits_neg_mask)
    apply clarsimp+
  apply (drule_tac na = "na-l" in test_bits_mask)
  apply (clarsimp simp: linorder_not_le)
  apply (subst (asm) add_commute[where a = l])+
  apply (drule nat_diff_less)
    apply (clarsimp simp:word_size)+
  apply (clarsimp simp:nth_shiftr)
  apply (auto simp:word_size)
done

lemma aligned_in_step_up_to:
  "\<lbrakk>x\<in> set (map (\<lambda>x. x + ptr) [0 , (2^t) .e. up]);t< WordSetup.word_bits; is_aligned ptr t\<rbrakk>
  \<Longrightarrow> is_aligned x t"
  apply (clarsimp simp:upto_enum_step_def image_def)
  apply (rule aligned_add_aligned[where n = t])
  apply (rule is_aligned_mult_triv2)
  apply (simp add:WordSetup.word_bits_def)+
done

lemma remain_pt_pd_relation:
  "\<lbrakk>is_aligned ptr 2; \<forall>a\<in>ys. is_aligned a 2; ptr\<notin> ys\<rbrakk> \<Longrightarrow> \<lbrace>\<lambda>s. \<forall>y\<in>ys. pt_page_relation (y && ~~ mask pt_bits) pg_id y S s\<rbrace>
    store_pte ptr sp
   \<lbrace>\<lambda>r s. \<forall>y\<in>ys. pt_page_relation (y && ~~ mask pt_bits) pg_id y S s\<rbrace>"
  apply (rule hoare_vcg_const_Ball_lift)
  apply (subgoal_tac "ptr\<noteq> y")
    apply (simp add:store_pte_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageTable x)) (ptr && ~~ mask pt_bits)
      and  pt_page_relation (y && ~~ mask pt_bits) pg_id y S" in hoare_vcg_precond_imp)
    apply (clarsimp simp:set_pt_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageTable x)) (ptr && ~~ mask pt_bits)
      and  pt_page_relation (y && ~~ mask pt_bits) pg_id y S" in hoare_vcg_precond_imp)
    apply (clarsimp simp:valid_def set_object_def in_monad)
    apply (drule_tac x= y in bspec,simp)
    apply (clarsimp simp:pt_page_relation_def dest!: ucast_inj_mask| rule conjI)+
      apply (drule mask_compare_imply)
        apply ((simp add:word_size pt_bits_def pageBits_def is_aligned_mask)+)

    apply (clarsimp simp:pt_page_relation_def obj_at_def)
    apply (assumption)
    apply wp
    apply (simp add:get_object_def)
    apply wp
    apply (clarsimp simp:obj_at_def)+
    apply (assumption)
    apply wp
    apply (clarsimp simp:obj_at_def pt_page_relation_def)+
done

lemma remain_pd_section_relation:
  "\<lbrakk>is_aligned ptr 2; is_aligned y 2; ptr \<noteq> y\<rbrakk>
   \<Longrightarrow> \<lbrace>\<lambda>s. pd_section_relation ( y && ~~ mask pd_bits) sid y s\<rbrace> store_pde ptr sp
       \<lbrace>\<lambda>r s. pd_section_relation (y && ~~ mask pd_bits) sid y s\<rbrace>"
    apply (simp add:store_pde_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageDirectory x)) (ptr && ~~ mask pd_bits)
      and pd_section_relation (y && ~~ mask pd_bits) sid y " in hoare_vcg_precond_imp)
    apply (clarsimp simp:set_pd_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageDirectory x)) (ptr && ~~ mask pd_bits)
      and pd_section_relation (y && ~~ mask pd_bits) sid y " in hoare_vcg_precond_imp)
    apply (clarsimp simp:valid_def set_object_def in_monad)
    apply (clarsimp simp:pd_section_relation_def dest!:ucast_inj_mask | rule conjI)+
      apply (drule mask_compare_imply)
        apply (simp add:word_size pd_bits_def pt_bits_def pageBits_def is_aligned_mask)+
    apply (clarsimp simp:pt_page_relation_def obj_at_def)
    apply (assumption)
    apply wp
    apply (simp add:get_object_def)
    apply wp
    apply (clarsimp simp:obj_at_def)+
    apply (assumption)
    apply wp
    apply (clarsimp simp:obj_at_def pt_page_relation_def)+
done

lemma remain_pd_super_section_relation:
  "\<lbrakk>is_aligned ptr 2; is_aligned y 2; ptr \<noteq> y\<rbrakk>
   \<Longrightarrow> \<lbrace>\<lambda>s. pd_super_section_relation ( y && ~~ mask pd_bits) sid y s\<rbrace> store_pde ptr sp
       \<lbrace>\<lambda>r s. pd_super_section_relation (y && ~~ mask pd_bits) sid y s\<rbrace>"
    apply (simp add:store_pde_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageDirectory x)) (ptr && ~~ mask pd_bits)
      and pd_super_section_relation (y && ~~ mask pd_bits) sid y " in hoare_vcg_precond_imp)
    apply (clarsimp simp:set_pd_def)
    apply wp
    apply (rule_tac Q = "ko_at (ArchObj (arch_kernel_obj.PageDirectory x)) (ptr && ~~ mask pd_bits)
      and pd_super_section_relation (y && ~~ mask pd_bits) sid y " in hoare_vcg_precond_imp)
    apply (clarsimp simp:valid_def set_object_def in_monad)
    apply (clarsimp simp:pd_super_section_relation_def dest!:ucast_inj_mask | rule conjI)+
      apply (drule mask_compare_imply)
        apply (simp add:word_size pd_bits_def pt_bits_def pageBits_def is_aligned_mask)+
    apply (clarsimp simp:pt_page_relation_def obj_at_def)
    apply (assumption)
    apply wp
    apply (simp add:get_object_def)
    apply wp
    apply (clarsimp simp:obj_at_def)+
    apply (assumption)
    apply wp
    apply (clarsimp simp:obj_at_def pt_page_relation_def)+
done

lemma remain_pd_either_section_relation:
  "\<lbrakk>\<forall>y \<in> set ys. is_aligned y 2;ptr\<notin> set ys;is_aligned ptr 2\<rbrakk>
   \<Longrightarrow> \<lbrace>\<lambda>s. \<forall>y\<in> set ys. (pd_super_section_relation (y && ~~ mask pd_bits) pg_id y s \<or>
    pd_section_relation (y && ~~ mask pd_bits) pg_id y s) \<rbrace>
    store_pde ptr ARM_Structs_A.pde.InvalidPDE
   \<lbrace>\<lambda>r s. \<forall>y\<in>set ys.
     (pd_super_section_relation (y && ~~ mask pd_bits) pg_id y s \<or>
     pd_section_relation (y && ~~ mask pd_bits) pg_id y s)\<rbrace>"
  apply (rule hoare_vcg_const_Ball_lift)
  apply (wp hoare_vcg_disj_lift)
    apply (rule hoare_strengthen_post[OF remain_pd_super_section_relation])
    apply fastforce+
  apply (rule hoare_strengthen_post[OF remain_pd_section_relation])
  apply fastforce+
done

lemma is_aligned_less_kernel_base_helper:
  "\<lbrakk>is_aligned (ptr :: word32) 6;
  ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots;
              x < 0x40 \<rbrakk>
   \<Longrightarrow> ucast (x + ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots"
  apply (simp add: kernel_mapping_slots_def)
  apply (simp add: word_le_nat_alt shiftr_20_unat_ucast
                   unat_ucast_pd_bits_shift)
  apply (fold word_le_nat_alt, unfold linorder_not_le)
  apply (drule minus_one_helper3[where x=x])
  apply (subst add_commute, subst is_aligned_add_or, assumption)
   apply (erule order_le_less_trans, simp)
  apply (simp add: word_ao_dist shiftr_over_or_dist)
  apply (subst less_mask_eq, erule order_le_less_trans)
   apply (simp add: pd_bits_def pageBits_def)
  apply (subst is_aligned_add_or[symmetric])
    apply (rule_tac n=4 in is_aligned_shiftr)
    apply (simp add: is_aligned_andI1)
   apply (rule shiftr_less_t2n)
   apply (erule order_le_less_trans, simp)
  apply (rule aligned_add_offset_less)
     apply (rule_tac n=4 in is_aligned_shiftr)
     apply (simp add: is_aligned_andI1)
    apply (simp add: kernel_base_def is_aligned_def)
   apply assumption
  apply (rule shiftr_less_t2n)
  apply (erule order_le_less_trans)
  apply simp
  done

lemma neg_aligned_less_kernel_base_helper:
  "\<lbrakk> is_aligned (ptr :: word32) 6;
  ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots;
              y - ptr < 0x40 \<rbrakk>
   \<Longrightarrow> ucast (y && mask pd_bits >> 2) \<notin> kernel_mapping_slots"
  by (drule(2) is_aligned_less_kernel_base_helper, simp)

lemma mapM_Cons_split:
  "xs \<noteq> [] \<Longrightarrow> (mapM f xs) = (do y \<leftarrow> f (hd xs); ys \<leftarrow> mapM f (tl xs); return (y # ys) od)"
  by (clarsimp simp:neq_Nil_conv mapM_Cons)

lemma dcorres_store_invalid_pde_super_section:
  "dcorres dc \<top> (pd_super_section_relation (ptr && ~~ mask pd_bits) pg_id ptr
   and invs
   and K (ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots))
  (delete_cap_simple (ptr && ~~ mask pd_bits, unat (ptr && mask pd_bits >> 2)))
  (store_pde ptr ARM_Structs_A.pde.InvalidPDE)"
  apply (simp add:K_def)
  apply (rule corres_gen_asm2)
  apply (rule corres_guard_imp)
    apply (simp add:store_pde_def)
    apply (rule corres_symb_exec_r)
      apply (rule dcorres_delete_cap_simple_set_pde[where oid = pg_id])
      apply simp
     apply (wp|simp)+
  apply (clarsimp simp: invs_def valid_mdb_def
    valid_state_def valid_pspace_def)
  done

lemma dcorres_store_invalid_pte:
  "dcorres dc \<top> (pt_page_relation (ptr && ~~ mask pt_bits) pg_id ptr UNIV
   and invs )
  (delete_cap_simple (ptr && ~~ mask pt_bits, unat (ptr && mask pt_bits >> 2)))
  (store_pte ptr ARM_Structs_A.pte.InvalidPTE)"
  apply (rule corres_guard_imp)
    apply (simp add:store_pte_def)
    apply (rule corres_symb_exec_r)
      apply (rule dcorres_delete_cap_simple_set_pt[where pg_id = pg_id])
     apply (wp|simp)+
  apply (clarsimp simp: invs_def valid_mdb_def
    valid_state_def valid_pspace_def)
  done

lemma dcorres_store_pde_non_sense:
  "dcorres dc \<top> (valid_idle and
     (\<lambda>s. \<exists>f. ko_at (ArchObj (arch_kernel_obj.PageDirectory f)) (slot && ~~ mask pd_bits) s
     \<and> (f (ucast (slot && mask pd_bits >> 2)) = pde)))
  (return a) (store_pde slot pde)"
  apply (simp add:store_pde_def)
  apply (simp add:get_pd_def bind_assoc
    get_object_def set_pd_def gets_def)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp add:assert_def corres_free_fail
    split:Structures_A.kernel_object.splits arch_kernel_obj.splits)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:corres_free_fail
    split:Structures_A.kernel_object.splits arch_kernel_obj.splits)
  apply (simp add:set_object_def put_def)
  apply (rule dcorres_absorb_get_r)
  apply (simp add:corres_underlying_def
    return_def transform_def transform_current_thread_def)
  apply (frule page_directory_at_rev)
  apply (drule(1) page_directory_not_idle[rotated])
  apply (rule ext)+
  apply (simp add:transform_objects_def
    not_idle_thread_def obj_at_def)
  done

lemma dcorres_store_pte_non_sense:
  "dcorres dc \<top> (valid_idle and
     (\<lambda>s. \<exists>f. ko_at (ArchObj (arch_kernel_obj.PageTable f)) (slot && ~~ mask pt_bits) s
      \<and> (f (ucast (slot && mask pt_bits >> 2)) = pte)))
  (return a) (store_pte slot pte)"
  apply (simp add:store_pte_def)
  apply (simp add:get_pt_def bind_assoc
    get_object_def set_pt_def gets_def)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp add:assert_def corres_free_fail
    split:Structures_A.kernel_object.splits arch_kernel_obj.splits)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:corres_free_fail
    split:Structures_A.kernel_object.splits arch_kernel_obj.splits)
  apply (simp add:set_object_def put_def)
  apply (rule dcorres_absorb_get_r)
  apply (simp add:corres_underlying_def
    return_def transform_def transform_current_thread_def)
  apply (frule page_table_at_rev)
  apply (drule(1) page_table_not_idle[rotated])
  apply (rule ext)+
  apply (simp add:transform_objects_def
    not_idle_thread_def obj_at_def)
  done

lemma store_pde_non_sense_wp:
  "\<lbrace>\<lambda>s. (\<exists>f. ko_at (ArchObj (arch_kernel_obj.PageDirectory f)) (slot && ~~ mask pd_bits) s
    \<and> (\<forall>slot\<in>set xs. f (ucast (slot && mask pd_bits >> 2)) = ARM_Structs_A.pde.InvalidPDE)) \<rbrace>
  store_pde x ARM_Structs_A.pde.InvalidPDE
   \<lbrace>\<lambda>r s. (\<exists>f. ko_at (ArchObj (arch_kernel_obj.PageDirectory f)) (slot && ~~ mask pd_bits) s
    \<and> (\<forall>slot\<in>set xs. f (ucast (slot && mask pd_bits >> 2)) = ARM_Structs_A.pde.InvalidPDE))\<rbrace>"
  apply (simp add:store_pde_def get_object_def
    get_pde_def set_pd_def set_object_def)
  apply wp
  apply (clarsimp simp:obj_at_def
    split:Structures_A.kernel_object.splits arch_kernel_object.splits)
  done

lemma dcorres_store_invalid_pde_tail_super_section:
  "dcorres dc \<top> (valid_idle and
    (\<lambda>s. \<exists>f. ko_at (ArchObj (arch_kernel_obj.PageDirectory f)) (slot && ~~ mask pd_bits) s
    \<and> (\<forall>slot\<in> set slots. f (ucast (slot && mask pd_bits >> 2)) = ARM_Structs_A.pde.InvalidPDE))
    and K (\<forall>sl\<in> set slots. sl && ~~ mask pd_bits = slot && ~~ mask pd_bits))
  (return a)
  (mapM (swp store_pde ARM_Structs_A.pde.InvalidPDE) slots)"
  proof (induct slots arbitrary:a)
    case Nil
    show ?case
      by (simp add:mapM_Nil)
  next
  case (Cons x xs)
  show ?case
   apply (rule corres_guard_imp)
     apply (simp add:mapM_Cons dc_def[symmetric])
     apply (rule corres_dummy_return_l)
     apply (rule corres_split[OF _ dcorres_store_pde_non_sense])
       apply (rule corres_dummy_return_l)
       apply (rule corres_split[OF _  Cons.hyps[unfolded swp_def]])
         apply (rule corres_free_return[where P=\<top> and P'=\<top>])
        apply wp
     apply simp
     apply (wp store_pde_non_sense_wp)
    apply simp
   apply (clarsimp simp:obj_at_def)
  done
qed

lemma store_pte_non_sense_wp:
  "\<lbrace>\<lambda>s. (\<exists>f. ko_at (ArchObj (arch_kernel_obj.PageTable f)) (slot && ~~ mask pt_bits) s
    \<and> (\<forall>slot\<in>set xs. f (ucast (slot && mask pt_bits >> 2)) = ARM_Structs_A.pte.InvalidPTE)) \<rbrace>
  store_pte x ARM_Structs_A.pte.InvalidPTE
   \<lbrace>\<lambda>r s. (\<exists>f. ko_at (ArchObj (arch_kernel_obj.PageTable f)) (slot && ~~ mask pt_bits) s
    \<and> (\<forall>slot\<in>set xs. f (ucast (slot && mask pt_bits >> 2)) = ARM_Structs_A.pte.InvalidPTE))\<rbrace>"
  apply (simp add:store_pte_def get_object_def
    get_pte_def set_pt_def set_object_def)
  apply wp
  apply (clarsimp simp:obj_at_def
    split:Structures_A.kernel_object.splits arch_kernel_object.splits)
  done

lemma dcorres_store_invalid_pte_tail_large_page:
  "dcorres dc \<top> (valid_idle and
    (\<lambda>s. \<exists>f. ko_at (ArchObj (arch_kernel_obj.PageTable f)) (slot && ~~ mask pt_bits) s
    \<and> (\<forall>slot\<in> set slots. f (ucast (slot && mask pt_bits >> 2)) = ARM_Structs_A.pte.InvalidPTE))
    and K (\<forall>sl\<in> set slots. sl && ~~ mask pt_bits = slot && ~~ mask pt_bits))
  (return a)
  (mapM (swp store_pte ARM_Structs_A.pte.InvalidPTE) slots)"
  proof (induct slots arbitrary:a)
    case Nil
    show ?case
      by (simp add:mapM_Nil)
  next
  case (Cons x xs)
  show ?case
   apply (rule corres_guard_imp)
     apply (simp add:mapM_Cons dc_def[symmetric])
     apply (rule corres_dummy_return_l)
     apply (rule corres_split[OF _ dcorres_store_pte_non_sense])
       apply (rule corres_dummy_return_l)
       apply (rule corres_split[OF _  Cons.hyps[unfolded swp_def]])
         apply (rule corres_free_return[where P=\<top> and P'=\<top>])
        apply wp
     apply simp
     apply (wp store_pte_non_sense_wp)
    apply simp
   apply (clarsimp simp:obj_at_def)
  done
qed

lemma dcorres_unmap_sections:
  "\<lbrakk>is_aligned ptr 6;ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots\<rbrakk>
    \<Longrightarrow> dcorres dc \<top> (invs and valid_pdpt_objs
           and (pd_super_section_relation (ptr && ~~ mask pd_bits) pg_id ptr))
     (PageTableUnmap_D.unmap_page pg_id)
     (mapM (swp store_pde ARM_Structs_A.pde.InvalidPDE) (map (\<lambda>x. x + ptr) [0 , 4 .e. 0x3C]))"
  apply (subst mapM_Cons_split)
   apply (simp add:upto_enum_step_def upto_enum_def)
  apply (simp add:store_pte_def PageTableUnmap_D.unmap_page_def)
  apply (simp add:gets_def get_pt_def get_object_def bind_assoc)
  apply (rule dcorres_absorb_get_l)
  apply (simp_all add:exs_valid_def get_def)
  apply (clarsimp simp:pd_super_section_relation_def)
  apply (rule corres_guard_imp)
    apply (rule_tac x = "[?n]" in select_pick_corres[where P = "\<top>"])
    apply (simp add:mapM_x_singleton)
    apply (rule corres_dummy_return_l)
    apply (rule corres_guard_imp)
     apply (rule corres_split[OF _ dcorres_store_invalid_pde_super_section])
       apply(rule corres_dummy_return_l)
       apply (rule_tac r'=dc
         in corres_split[OF corres_free_return[where P=\<top> and P'=\<top>]])
          apply (rule dcorres_store_invalid_pde_tail_super_section[where slot = ptr])
         apply wp
      apply (wp store_pde_non_sense_wp)
     apply simp
    apply simp+
     apply (simp add: hd_map_simp upto_enum_step_def upto_enum_def)
    apply clarsimp
    apply (rule slot_with_pd_section_relation)
      apply (simp add:invs_valid_idle)
     apply (clarsimp simp:pd_super_section_relation_def)
    apply simp
   apply (simp add:obj_at_def hd_map_simp upto_enum_step_def upto_enum_def
     pd_super_section_relation_def drop_map)
   apply (rule conjI,simp)
   apply (rule conjI,fastforce)
   apply (subst conj_ac)
   apply (rule context_conjI)
    apply (clarsimp simp:tl_map field_simps)
    apply (subst mask_lower_twice[symmetric,where n = 6])
     apply (simp add:pd_bits_def pageBits_def)
    apply (subst is_aligned_add_helper)
     apply simp
    apply (simp add:upto_0_to_n)
    apply (rule word_less_power_trans_ofnat[where k = 2 and m = 6,simplified])
     apply simp
    apply simp
   apply simp
  apply (rule ballI)
  apply (drule(1) bspec)
  apply (clarsimp simp:tl_map field_simps upto_0_to_n)
  apply (drule(1) valid_pdpt_objs_pdD)
  apply clarsimp
  apply (rename_tac pd rights attr ref s slot)
  apply (drule_tac x = "(ucast (ptr + of_nat slot * 4 && mask pd_bits >> 2))"
    and y = "ucast (ptr && mask pd_bits >> 2)"
    in valid_entriesD[rotated])
   apply (thin_tac "ptr + ?x  && ~~ mask pd_bits = ?y")
   apply (rule ccontr)
   apply simp
   apply (drule arg_cong[where f = "ucast::(12 word\<Rightarrow>word32)"])
   apply (drule arg_cong[where f = "\<lambda>x. shiftl x 2"])
   apply (subst (asm) ucast_ucast_len)
    apply (rule shiftr_less_t2n)
    apply (rule less_le_trans[OF and_mask_less'])
     apply (simp add:pd_bits_def pageBits_def)
    apply (simp add:pd_bits_def pageBits_def)
   apply (subst (asm) ucast_ucast_len)
    apply (rule shiftr_less_t2n)
    apply (rule less_le_trans[OF and_mask_less'])
     apply (simp add:pd_bits_def pageBits_def)
    apply (simp add:pd_bits_def pageBits_def)
   apply (simp add:shiftr_shiftl1)
   apply (subst (asm) is_aligned_neg_mask_eq[where n = 2])
    apply (erule aligned_after_mask[OF aligned_add_aligned])
     apply (simp add:shiftl_t2n[symmetric,where n =2,
       simplified field_simps,simplified] is_aligned_shiftl_self)
    apply simp
   apply (subst (asm) is_aligned_neg_mask_eq[where n = 2])
    apply (erule aligned_after_mask[OF is_aligned_weaken])
    apply simp
   apply (subst (asm) and_mask_plus)
       apply simp
      apply (simp add:pd_bits_def pageBits_def)+
    apply (simp add:shiftl_t2n[symmetric,where n =2,simplified field_simps,simplified])
    apply (rule shiftl_less_t2n[where m = 6,simplified])
     apply (simp add:word_of_nat_less)
    apply simp
   apply simp
   apply (subgoal_tac "0 < (of_nat (slot * 4)::word32)")
    apply simp
   apply (rule le_less_trans[OF _ of_nat_mono_maybe[where Y = 0]])
     apply fastforce
    apply simp
   apply fastforce
  apply (clarsimp split:if_splits)
  apply (rule ccontr)
  apply (erule_tac x = "ucast (ptr + of_nat slot * 4 && mask pd_bits >> 2)"
    in in_empty_interE)
   apply (rule non_invalid_in_pde_range)
   apply simp
  apply (simp add: ucast_neg_mask)
  apply (rule arg_cong[where f = ucast])
  apply (rule shiftr_eq_neg_mask_eq)
  apply (simp add:shiftr_shiftr shiftr_over_and_dist)
  apply (subst aligned_shift')
     apply (simp add:shiftl_t2n[symmetric,where n =2,simplified field_simps,simplified])
     apply (rule shiftl_less_t2n[where m = 6,simplified])
      apply (simp add:word_of_nat_less)
     apply simp+
  done

lemma pt_page_relation_weaken:
  "\<lbrakk> pt_page_relation a b c S s; S \<subseteq> T \<rbrakk> \<Longrightarrow> pt_page_relation a b c T s"
  apply (clarsimp simp: pt_page_relation_def)
  apply (auto split: ARM_Structs_A.pte.split)
  done

lemma dcorres_unmap_pages:
  "is_aligned ptr 6
    \<Longrightarrow> dcorres dc \<top> (invs and valid_pdpt_objs
          and pt_page_relation (ptr && ~~ mask pt_bits) pg_id ptr {ARMLargePage})
     (PageTableUnmap_D.unmap_page pg_id)
     (mapM (swp store_pte ARM_Structs_A.pte.InvalidPTE) (map (\<lambda>x. x + ptr) [0 , 4 .e. 0x3C]))"
  apply (subst mapM_Cons_split)
   apply (simp add:upto_enum_step_def upto_enum_def)
  apply (simp add: PageTableUnmap_D.unmap_page_def)
  apply (simp add:gets_def get_pt_def get_object_def bind_assoc)
  apply (rule dcorres_absorb_get_l)
  apply (clarsimp simp:pt_page_relation_def)
  apply (simp split:ARM_Structs_A.pte.split_asm)
  apply (rule corres_guard_imp)
    apply (rule_tac x = "[?n]" in select_pick_corres[where P = "\<top>"])
    apply (simp add:mapM_x_singleton)
    apply (rule corres_dummy_return_l)
    apply (rule corres_guard_imp)
      apply (rule corres_split[OF _ dcorres_store_invalid_pte])
        apply(rule corres_dummy_return_l)
        apply (rule_tac r'=dc
          in corres_split[OF corres_free_return[where P=\<top> and P'=\<top>]])
          apply (rule dcorres_store_invalid_pte_tail_large_page[where slot = ptr])
         apply wp
      apply (wp store_pte_non_sense_wp)
     apply simp
    apply simp+
   apply (simp add: hd_map_simp upto_enum_step_def upto_enum_def)
   apply (clarsimp simp:unat_def)
   apply (rule slot_with_pt_frame_relation)
    apply (simp add:invs_valid_idle)
   apply (fastforce simp:pt_page_relation_def)
  apply simp
  apply (simp add:obj_at_def hd_map_simp upto_enum_step_def upto_enum_def
    pt_page_relation_def)
  apply (rule conjI,simp)
  apply (rule conjI,fastforce)
  apply (subst conj_ac)
  apply (rule context_conjI)
   apply (clarsimp simp:tl_map drop_map)
   apply (simp add:field_simps)
   apply (subst mask_lower_twice[symmetric,where n = 6])
    apply (simp add:pt_bits_def pageBits_def)
   apply (subst is_aligned_add_helper)
     apply simp
    apply (simp add:upto_0_to_n)
    apply (rule word_less_power_trans_ofnat[where k = 2 and m = 6,simplified])
     apply simp
    apply simp
   apply simp
  apply clarsimp
  apply (drule(1) bspec)
  apply (clarsimp simp:tl_map drop_map upto_0_to_n)
  apply (simp add: field_simps)
  apply (drule(1) valid_pdpt_objs_ptD,clarify)
  apply (drule_tac x = "(ucast (ptr + of_nat x * 4 && mask pt_bits >> 2))"
    and y = "ucast (ptr && mask pt_bits >> 2)"
    in valid_entriesD[rotated])
   apply (thin_tac "ptr + ?x  && ~~ mask pt_bits = ?y")
   apply (rule ccontr)
   apply simp
   apply (drule arg_cong[where f = "ucast::(word8\<Rightarrow>word32)"])
   apply (drule arg_cong[where f = "\<lambda>x. shiftl x 2"])
   apply (subst (asm) ucast_ucast_len)
    apply (rule shiftr_less_t2n)
    apply (rule less_le_trans[OF and_mask_less'])
     apply (simp add:pt_bits_def pageBits_def)
    apply (simp add:pt_bits_def pageBits_def)
   apply (subst (asm) ucast_ucast_len)
    apply (rule shiftr_less_t2n)
    apply (rule less_le_trans[OF and_mask_less'])
     apply (simp add:pt_bits_def pageBits_def)
    apply (simp add:pt_bits_def pageBits_def)
   apply (simp add:shiftr_shiftl1)
   apply (subst (asm) is_aligned_neg_mask_eq[where n = 2])
    apply (erule aligned_after_mask[OF aligned_add_aligned])
     apply (simp add:shiftl_t2n[symmetric,where n =2,
       simplified field_simps,simplified] is_aligned_shiftl_self)
    apply simp
   apply (subst (asm) is_aligned_neg_mask_eq[where n = 2])
    apply (erule aligned_after_mask[OF is_aligned_weaken])
    apply simp
   apply (subst (asm) and_mask_plus)
       apply simp
      apply (simp add:pt_bits_def pageBits_def)+
    apply (simp add:shiftl_t2n[symmetric,where n =2,simplified field_simps,simplified])
    apply (rule shiftl_less_t2n[where m = 6,simplified])
     apply (simp add:word_of_nat_less)
    apply simp
   apply simp
   apply (subgoal_tac "0 < (of_nat (x * 4)::word32)")
    apply simp
   apply (rule le_less_trans[OF _ of_nat_mono_maybe[where Y = 0]])
     apply fastforce
    apply simp
   apply fastforce
  apply (clarsimp split:if_splits)
  apply (rule ccontr)
  apply (erule_tac x = "ucast (ptr + of_nat x * 4 && mask pt_bits >> 2)"
    in in_empty_interE)
   apply (rule non_invalid_in_pte_range)
   apply simp
  apply (simp add: ucast_neg_mask)
  apply (rule arg_cong[where f = ucast])
  apply (rule shiftr_eq_neg_mask_eq)
  apply (simp add:shiftr_shiftr shiftr_over_and_dist)
  apply (subst aligned_shift')
     apply (simp add:shiftl_t2n[symmetric,where n =2,simplified field_simps,simplified])
     apply (rule shiftl_less_t2n[where m = 6,simplified])
      apply (simp add:word_of_nat_less)
     apply simp+
done

lemma dcorres_unmap_page_table_store_pde:
  "ucast (ptr && mask pd_bits >> 2) \<notin> kernel_mapping_slots
   \<Longrightarrow> dcorres dc \<top> ((\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s))
    and valid_idle and pd_pt_relation (ptr && ~~ mask pd_bits) pt_id ptr )
           (PageTableUnmap_D.unmap_page_table pt_id)
           (store_pde ptr ARM_Structs_A.pde.InvalidPDE)"
   apply (clarsimp simp:PageTableUnmap_D.unmap_page_table_def store_pde_def bind_assoc)
   apply (simp add:gets_def)
   apply (rule dcorres_absorb_get_l)
   apply (simp add:get_pd_def)
   apply (clarsimp simp:get_object_def gets_def bind_assoc)
   apply (rule dcorres_absorb_get_r)
   apply (frule_tac slot_with_pd_pt_relation)
     apply simp+
   apply (clarsimp simp:pd_pt_relation_def assert_def)
   apply (rule corres_guard_imp)
   apply (rule_tac x = "[(ptr && ~~ mask pd_bits, nat(uint (ptr && mask pd_bits >> 2)))  ]"
     in select_pick_corres[where P=\<top> ])
     apply (clarsimp simp:mapM_x_def sequence_x_def unat_def[symmetric])
     apply (rule_tac  oid = "Platform.ptrFromPAddr ref" in dcorres_delete_cap_simple_set_pde)
       apply clarsimp
   apply(clarsimp simp:pd_pt_relation_def unat_def obj_at_def)+
done

lemma (in pspace_update_eq) pd_pt_relation_update[iff]:
  "pd_pt_relation a b c (f s) = pd_pt_relation a b c s"
  by (simp add: pd_pt_relation_def pspace)

crunch cdt[wp] :flush_page "\<lambda>s. P (cdt s)"
  (wp: crunch_wps simp:crunch_simps)

crunch valid_idle[wp]: flush_page "valid_idle"
  (wp: crunch_wps simp:crunch_simps)

lemma mdb_cte_at_flush_page[wp]:
  "\<lbrace>\<lambda>s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s)\<rbrace> flush_page a b c d
   \<lbrace>\<lambda>_ s. mdb_cte_at (swp (cte_wp_at (op \<noteq> cap.NullCap)) s) (cdt s)\<rbrace>"
  apply (simp add:mdb_cte_at_def)
  apply (simp only: imp_conv_disj)
  apply (wp hoare_vcg_all_lift hoare_vcg_disj_lift)
done

crunch pd_pt_relation[wp]: flush_table "pd_pt_relation a b c"
  (wp: crunch_wps simp: crunch_simps)

crunch valid_idle[wp]: flush_table "valid_idle"
  (wp: crunch_wps simp:crunch_simps)

crunch valid_idle[wp]: page_table_mapped "valid_idle"
  (wp: crunch_wps simp:crunch_simps)

crunch valid_idle[wp]: invalidate_asid_entry "valid_idle"
  (wp: crunch_wps simp:crunch_simps)

crunch valid_idle[wp]: flush_space "valid_idle"
  (wp: crunch_wps simp:crunch_simps)

lemma page_table_mapped_stable[wp]:
  "\<lbrace>op = s\<rbrace> page_table_mapped a b w \<lbrace>\<lambda>r. op = s\<rbrace>"
  apply (simp add:page_table_mapped_def)
  apply (wp|wpc)+
  apply (simp add:get_pde_def)
  apply wp
  apply (simp add:find_pd_for_asid_def)
  apply (wp|wpc)+
  apply clarsimp
done

lemma eqv_imply_stable:
assumes "\<And>cs. \<lbrace>op = cs\<rbrace> f \<lbrace>\<lambda>r. op = cs\<rbrace>"
shows "\<lbrace>P\<rbrace> f \<lbrace>\<lambda>r. P\<rbrace>"
  using assms
  apply (fastforce simp:valid_def)
done

lemma check_mapping_pptr_pt_relation:
  "\<lbrace>\<lambda>s. vmpage_size \<in> S\<rbrace> check_mapping_pptr w vmpage_size (Inl b)
            \<lbrace>\<lambda>r s. r \<longrightarrow> pt_page_relation (b && ~~ mask pt_bits) w b S s\<rbrace>"
  apply (simp add:check_mapping_pptr_def get_pte_def)
  apply (rule hoare_pre, wp get_pte_wp)
  apply (clarsimp simp: obj_at_def)
  apply (clarsimp simp: a_type_def pt_page_relation_def
                 split: Structures_A.kernel_object.split_asm split_if_asm
                        arch_kernel_obj.split_asm)
  apply (simp split: ARM_Structs_A.pte.split_asm)
  done

lemma check_mapping_pptr_section_relation:
  "\<lbrace>\<top>\<rbrace> check_mapping_pptr w ARMSection (Inr (lookup_pd_slot rv' b))
   \<lbrace>\<lambda>rv s. rv \<longrightarrow>
    pd_section_relation (lookup_pd_slot rv' b && ~~ mask pd_bits) w (lookup_pd_slot rv' b) s\<rbrace>"
  apply (rule hoare_vcg_precond_imp)
   apply (simp add:check_mapping_pptr_def)
   apply (wp get_pde_wp)
  apply (clarsimp simp: obj_at_def)
  apply (clarsimp simp: a_type_def pd_section_relation_def pd_super_section_relation_def
                 split: Structures_A.kernel_object.split_asm split_if_asm
                        arch_kernel_obj.split_asm
                        ARM_Structs_A.pde.split_asm)
done

lemma check_mapping_pptr_super_section_relation:
  "\<lbrace>\<top>\<rbrace> check_mapping_pptr w ARMSuperSection (Inr (lookup_pd_slot rv' b))
   \<lbrace>\<lambda>rv s. rv \<longrightarrow> pd_super_section_relation (lookup_pd_slot rv' b && ~~ mask pd_bits) w (lookup_pd_slot rv' b) s\<rbrace>"
  apply (rule hoare_vcg_precond_imp)
   apply (simp add:check_mapping_pptr_def)
   apply (wp get_pde_wp)
  apply (clarsimp simp: obj_at_def)
  apply (clarsimp simp: a_type_def pd_section_relation_def pd_super_section_relation_def
                 split: Structures_A.kernel_object.split_asm split_if_asm
                        arch_kernel_obj.split_asm
                        ARM_Structs_A.pde.split_asm)
done

lemma lookup_pt_slot_aligned:
  "\<lbrace>invs and \<exists>\<rhd> pd and K (is_aligned pd pd_bits \<and> is_aligned vptr 16 \<and> vptr < kernel_base)\<rbrace>
        lookup_pt_slot pd vptr \<lbrace>\<lambda>rb s. is_aligned rb 6\<rbrace>, -"
  apply (rule hoare_gen_asmE)+
  apply (rule hoare_pre, rule hoare_post_imp_R, rule lookup_pt_slot_cap_to)
   apply auto
  done

lemma get_pde_pd_relation:
  "\<lbrace>P\<rbrace> get_pde x
           \<lbrace>\<lambda>r s. \<exists>f. ko_at (ArchObj (arch_kernel_obj.PageDirectory f)) (x && ~~ mask pd_bits) s
           \<and> r = f (ucast (x && mask pd_bits >> 2))\<rbrace>"
  apply (simp add:get_pde_def)
  apply wp
  apply (clarsimp simp:obj_at_def)
done

lemma pd_pt_relation_page_table_mapped_wp:
  "\<lbrace>page_table_at w\<rbrace> page_table_mapped a b w
      \<lbrace>\<lambda>r s. (case r of Some pd \<Rightarrow> pd_pt_relation
    (lookup_pd_slot pd b && ~~ mask pd_bits) w (lookup_pd_slot pd b) s | _ \<Rightarrow> True)\<rbrace>"
  apply (simp add:page_table_mapped_def)
  apply wp
  apply wpc
    apply (clarsimp simp:validE_def valid_def return_def returnOk_def)
    apply wp
    apply simp
    apply (simp add:get_pde_def)
    apply wp
    apply (simp add:validE_def)
    apply (rule hoare_strengthen_post[where Q="\<lambda>rv. page_table_at w"])
      apply wp
  apply (clarsimp,rule conjI)
    apply fastforce
  apply (clarsimp simp:pd_pt_relation_def obj_at_def)
done

lemma hoare_post_Some_conj:
  "\<lbrakk> \<lbrace>P\<rbrace>f\<lbrace>\<lambda>r s. case r of Some a \<Rightarrow> Q a s | _ \<Rightarrow> S \<rbrace>;
    \<lbrace>P\<rbrace>f\<lbrace>\<lambda>r s. case r of Some a \<Rightarrow> R a s | _ \<Rightarrow> S \<rbrace>
   \<rbrakk> \<Longrightarrow>\<lbrace>P\<rbrace>f\<lbrace>\<lambda>r s. case r of Some a \<Rightarrow> Q a s \<and> R a s | _ \<Rightarrow> S\<rbrace>"
  apply (clarsimp simp:valid_def)
  apply (drule_tac x = s in spec)+
  apply clarsimp
  apply (drule_tac x= "(a,b)" in bspec,simp)+
  apply (clarsimp split:option.splits)
done

lemma cleanByVA_PoU_underlying_memory[wp]: " \<lbrace>\<lambda>m'. underlying_memory m' = m\<rbrace> cleanByVA_PoU w q \<lbrace>\<lambda>_ m'. underlying_memory m' = m\<rbrace>"
    apply(clarsimp simp: cleanByVA_PoU_def, wp)
done




lemma dcorres_unmap_page_table:
  "\<lbrakk>a \<le> mask asid_bits ; b < kernel_base ; vmsz_aligned b ARMSection\<rbrakk>
   \<Longrightarrow> dcorres dc \<top> (invs and valid_cap (cap.ArchObjectCap (arch_cap.PageTableCap w (Some (a, b)))))
     (PageTableUnmap_D.unmap_page_table w)
     (ArchVSpace_A.unmap_page_table a b w)"
   apply (simp add: unmap_page_table_def)
   apply (rule dcorres_expand_pfx)
   apply (rule_tac Q'="\<lambda>r.  op = s' and (\<lambda>s.
       (case r of Some pd \<Rightarrow> is_aligned pd pd_bits
           \<and> pd_pt_relation (lookup_pd_slot pd b && ~~ mask pd_bits) w (lookup_pd_slot pd b) s
                   | _ \<Rightarrow> True))"
       in corres_symb_exec_r)
     apply (clarsimp split:option.splits | rule conjI)+
     apply (rule corres_guard_imp[OF dcorres_unmap_page_table_empty])
     apply clarsimp+
     apply (rule dcorres_expand_pfx)
     apply (rule corres_guard_imp)
       apply (rule corres_dummy_return_l)
       apply (rule corres_split[where r'=dc])
           apply clarify
              apply (rule corres_dummy_return_l)
                  apply (rule corres_split[where r'=dc])
                   apply (rule dcorres_flush_table)
            apply (clarsimp)
           apply (rule dcorres_machine_op_noop)
           apply wp
         apply (simp add:dc_def[symmetric])
         apply (rule dcorres_unmap_page_table_store_pde)
         apply (simp add:less_kernel_base_mapping_slots)
     apply (wp|simp)+
       apply (clarsimp simp:valid_cap_def invs_def valid_state_def valid_pspace_def swp_def valid_mdb_def)
     apply (wp pd_pt_relation_page_table_mapped_wp | clarsimp)+
     apply (simp add:asid_bits_def valid_cap_def invs_def valid_state_def)
     apply (wp pd_pt_relation_page_table_mapped_wp | clarsimp)+
     apply (rule hoare_post_Some_conj)
     apply (wp page_table_mapped_wp)
       apply (clarsimp simp:invs_def valid_state_def valid_pspace_def)
       apply (wp pd_pt_relation_page_table_mapped_wp)
     apply (wp | clarsimp simp:valid_cap_def)+
  done

lemma imp_strength:
  "(A \<and> (B\<longrightarrow>C)) \<longrightarrow> (B \<longrightarrow> (A\<and>C))"
  by clarsimp



lemma cleanCacheRange_PoU_underlying_memory[wp]:
             "\<lbrace>\<lambda>ms. underlying_memory ms = m\<rbrace>
              cleanCacheRange_PoU a b c
              \<lbrace>\<lambda>rv ms. underlying_memory ms = m\<rbrace>"
   apply (clarsimp simp: cleanCacheRange_PoU_def, wp)
done

lemma dcorres_unmap_page:
  notes swp_apply[simp del]
  shows "dcorres dc \<top> (invs and valid_pdpt_objs and
                  valid_cap (cap.ArchObjectCap (arch_cap.PageCap word fun vmpage_size (Some (a, b)))))
              (PageTableUnmap_D.unmap_page word)
              (ArchVSpace_A.unmap_page vmpage_size a b word)"
  apply (rule dcorres_expand_pfx)
  apply (clarsimp simp:valid_cap_def)
  apply (simp add:ArchVSpace_A.unmap_page_def)
  apply (case_tac vmpage_size)
     apply simp_all
     apply (rule corres_guard_imp)
       apply (clarsimp simp: bindE_assoc)
       apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
         apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
           apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
             apply (clarsimp simp: catch_def bindE_def liftE_def bind_assoc lift_def throwError_def split: sum.splits)
             apply (rule corres_guard_imp)
               apply (rule corres_dummy_return_l)
               apply (rule corres_split[OF _ dcorres_unmap_page_single])
                 apply (rule dcorres_symb_exec_r)
                   apply (rule dcorres_flush_page)
                  apply (wp do_machine_op_wp | clarsimp)+
             apply (assumption)
            apply wp
            apply (simp add: imp_conjR)
            apply ((wp check_mapping_pptr_pt_relation | wp_once hoare_drop_imps)+)[1]
           apply (simp del: swp_apply | wp lookup_pt_slot_inv)+
     apply (simp del: swp_apply | wp lookup_pt_slot_inv | safe)+
    (*LargePage*)
    apply (rule corres_guard_imp)
      apply (clarsimp simp: bindE_assoc)
      apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
        apply (rule dcorres_symb_exec_r_catch'[OF dcorres_unmap_page_empty])
          apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
            apply (rule_tac F="is_aligned rv'a 6 " in corres_gen_asm2)
            apply (clarsimp simp: catch_def bindE_def liftE_def bind_assoc lift_def throwError_def split: sum.splits)
            apply (clarsimp simp:liftE_def catch_def is_aligned_mask[symmetric])
            apply (rule corres_guard_imp)
              apply (rule corres_dummy_return_l)
              apply (rule corres_split[OF _ dcorres_unmap_pages])
                 apply (rule dcorres_symb_exec_r)
                   apply (rule dcorres_flush_page)
                  apply (wp do_machine_op_wp | clarsimp)+
            apply (assumption)
           apply wp
           apply (simp add: imp_conjR)
           apply ((wp check_mapping_pptr_pt_relation | wp_once hoare_drop_imps)+)[1]
          apply (clarsimp |wp)+
         apply (wp flush_page_invs lookup_pt_slot_inv lookup_pt_slot_aligned)
       apply (wp | simp)+
    apply (clarsimp)+
    apply (clarsimp simp:invs_def valid_state_def valid_mdb_def
   cap_aligned_def vmsz_aligned_def valid_pspace_def)
   (* Section *)
   apply (rule corres_guard_imp)
     apply (clarsimp simp: bindE_assoc)
     apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
       apply (rule dcorres_symb_exec_r_catch[OF dcorres_unmap_page_empty])
         apply (rule_tac F = "is_aligned rv' pd_bits" in corres_gen_asm2)
         apply (rule corres_guard_imp)
           apply (clarsimp simp: catch_def bindE_def liftE_def bind_assoc lift_def throwError_def split: sum.splits)
           apply (rule corres_dummy_return_l)
           apply (rule corres_split)
              apply (rule dcorres_symb_exec_r)
                apply (rule dcorres_flush_page)
               apply (wp do_machine_op_wp | clarsimp )+
             apply (rule dcorres_unmap_section_single)
             apply (simp add:less_kernel_base_mapping_slots)
            apply (simp add:cap_aligned_def)
           apply wp
          apply simp
         apply (assumption)
        apply (wp|clarsimp)+
        apply (simp add: imp_conjR imp_disj1[symmetric] del: imp_disj1)
        apply ((wp check_mapping_pptr_section_relation hoare_vcg_disj_lift
       | wp_once hoare_drop_imps)+)[1]
       apply (wp|clarsimp)+
   apply fastforce
  (*Super Section*)
  apply (rule corres_guard_imp)
    apply (rule dcorres_symb_exec_r_catch)
       apply (rule dcorres_unmap_page_empty)
      apply (clarsimp simp: bindE_assoc)
      apply (rule dcorres_symb_exec_r_catch'[OF dcorres_unmap_page_empty])
        apply (rule_tac F="is_aligned rv' 6 \<and> is_aligned rv' pd_bits" in corres_gen_asm2)
        apply (clarsimp simp: catch_def bindE_def liftE_def bind_assoc lift_def throwError_def split: sum.splits)

        apply (clarsimp simp:liftE_def catch_def assert_def corres_free_fail)
        apply (rule corres_guard_imp)
          apply (rule corres_dummy_return_l)
          apply (rule corres_split[OF _ dcorres_unmap_sections[where pg_id = word]])
              apply (rule dcorres_symb_exec_r)
                apply (rule dcorres_flush_page)
               apply (wp do_machine_op_wp | clarsimp)+
             apply (simp add:lookup_pd_slot_def)
             apply (rule aligned_add_aligned)
               apply simp
              apply (simp add:vmsz_aligned_def)
              apply (drule is_aligned_shiftr[where w = b and m = 20 and n = 4,simplified])
              apply (rule is_aligned_shiftl[where m = 2 and n = 6 and w = "b>>20"])
              apply ((clarsimp simp:WordSetup.word_bits_def)+)[3]
            apply (simp add:less_kernel_base_mapping_slots)
           apply (clarsimp simp:cap_aligned_def)
          apply (wp|clarsimp)+
        apply (assumption)
       apply wp
       apply (simp add: imp_conjR)
       apply ((wp check_mapping_pptr_super_section_relation
      | wp_once hoare_drop_imps)+)[1]
      apply (wp flush_page_invs|clarsimp)+
     apply (rule validE_validE_R)
     apply (rule hoare_post_impErr[where E = "\<lambda>r. \<top>"])
       apply (rule validE_R_validE[OF find_pd_for_asid_aligned_pd])
      apply (rule conjI,erule is_aligned_weaken,simp+)
      apply (simp add:pd_bits_def pageBits_def)
     apply wp
  apply (clarsimp simp:cap_aligned_def invs_def valid_state_def valid_pspace_def)
done



lemma dcorres_delete_asid_none:
  "dcorres dc \<top> \<top> (CSpace_D.delete_asid x word) (return ())"
  apply (clarsimp simp:CSpace_D.delete_asid_def)
  apply (rule corres_alternate2)
  apply clarsimp
  done

lemma asid_table_transform:
  "cdl_asid_table (transform s) slot =
   unat_map (Some \<circ> transform_asid_table_entry \<circ> arm_asid_table (arch_state s)) slot"
  apply (simp add:transform_def transform_asid_table_def transform_asid_table_entry_def)
  done

lemma dcorres_delete_asid:
  "dcorres dc \<top> (valid_idle)
    (CSpace_D.delete_asid (transform_asid asid) word)
    (ArchVSpace_A.delete_asid asid word)"
  apply (clarsimp simp:CSpace_D.delete_asid_def ArchVSpace_A.delete_asid_def)
  apply (clarsimp simp:gets_def)
  apply (rule dcorres_absorb_get_r)
  apply (clarsimp simp:when_def split:option.splits)
  apply (rule conjI)
   apply clarsimp
   apply (rule corres_alternate2)
   apply clarsimp
  apply clarsimp
  apply (rule dcorres_symb_exec_r_strong)
    apply clarsimp
    apply (rule conjI)
     apply clarsimp
     apply (rule corres_alternate1)
     apply (rule dcorres_absorb_get_l)
     apply (drule_tac s="transform s'" in sym)
     apply (clarsimp simp:when_def asid_table_transform transform_asid_def
                          transform_asid_table_entry_def
                     split:option.splits if_splits)
     apply (rule dcorres_symb_exec_r_strong)
       apply (rule dcorres_symb_exec_r_strong)
         apply (rule corres_guard_imp)
           apply (rule corres_dummy_return_l)
           apply (rule corres_split[OF corres_trivial,where r'=dc])
              apply (rule dcorres_symb_exec_r[OF dcorres_set_vm_root])
               apply wp
             apply (rule dcorres_set_asid_pool)
               apply simp
              apply (clarsimp simp:transform_asid_def)
             apply (clarsimp simp:transform_asid_pool_entry_def)
            apply (wp | clarsimp)+
         apply simp
        apply (wp | clarsimp)+
       apply (subgoal_tac "valid_idle s \<and> ko_at (ArchObj (arch_kernel_obj.ASIDPool rv)) a s")
        apply simp+
     apply (wp | clarsimp)+
    apply (rule corres_alternate2)
    apply simp
   apply (wp | clarsimp)+
done

lemma thread_in_thread_cap_not_idle:
 "\<lbrakk>valid_global_refs s;cte_wp_at (op = (cap.ThreadCap ptr)) slot s\<rbrakk>
  \<Longrightarrow> not_idle_thread ptr s"
  apply (rule ccontr)
  apply (clarsimp simp:valid_cap_def valid_global_refs_def valid_refs_def)
  apply (case_tac slot)
  apply (drule_tac x = a in spec)
    apply (drule_tac x = b in spec)
  apply (clarsimp simp:cte_wp_at_def not_idle_thread_def)
  apply (simp add:cap_range_def global_refs_def)
done

lemma set_cap_set_thread_state_inactive:
  "dcorres dc \<top> (not_idle_thread thread and valid_etcbs)
   (KHeap_D.set_cap (thread, tcb_pending_op_slot) cdl_cap.NullCap)
   (set_thread_state thread Structures_A.thread_state.Inactive)"
  apply (clarsimp simp:set_thread_state_def)
  apply (rule dcorres_absorb_gets_the)
  apply (rule corres_guard_imp)
    apply (rule dcorres_rhs_noop_below_True[OF set_thread_state_ext_dcorres])
    apply (rule set_pending_cap_corres)
   apply simp
  apply (clarsimp dest!:get_tcb_SomeD
    simp:obj_at_def infer_tcb_pending_op_def)
  done

lemma dcorres_finalise_cap:
  "cdlcap = transform_cap cap \<Longrightarrow>
      dcorres (\<lambda>r r'. fst r = transform_cap (fst r'))
             \<top> (invs and valid_cap cap and valid_pdpt_objs and cte_wp_at (op=cap) slot and valid_etcbs)
          (CSpace_D.finalise_cap cdlcap final)
          (CSpace_A.finalise_cap cap final)"
  apply (case_tac cap)
            apply (simp_all add:transform_cap_simps when_def)
       apply clarsimp
       apply (rule corres_rel_imp)
        apply (rule corres_guard_imp[OF dcorres_ep_cancel_all])
         apply (clarsimp simp:invs_def valid_state_def)+
      apply (rule corres_rel_imp)
       apply (rule corres_guard_imp[OF dcorres_aep_cancel_all])
        apply ((clarsimp simp:invs_def valid_state_def)+)[3]
     apply (simp add:IpcCancel_A.suspend_def bind_assoc)
     apply clarsimp
     apply (rule corres_guard_imp)
       apply (rule corres_split[OF _ finalise_ipc_cancel])
         apply (rule corres_split)
            unfolding K_bind_def
            apply (rule dcorres_rhs_noop_above_True[OF tcb_sched_action_dcorres[where P=\<top> and P'=\<top>]])
            apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
            apply (clarsimp simp:transform_cap_def)
           apply (rule set_cap_set_thread_state_inactive)
          apply wp
       apply (simp add:not_idle_thread_def)
       apply wp
      apply (simp+)
     apply clarsimp
     apply (drule(1) thread_in_thread_cap_not_idle[OF invs_valid_global_refs])
     apply (simp add:not_idle_thread_def)
    apply clarsimp
    apply (rule corres_guard_imp)
      apply (rule corres_split[OF _ dcorres_deleting_irq_handler])
        apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
        apply (clarsimp simp:transform_cap_def)
      apply (wp|clarsimp)+
    apply (clarsimp simp:assert_def corres_free_fail)
    apply (case_tac arch_cap)
      apply (simp_all add: transform_cap_simps arch_finalise_cap_def split:arch_cap.split_asm)
        apply clarsimp
-- arch_cap.ASIDPoolCap
      apply (rule corres_guard_imp)
        apply (rule corres_split[OF _ dcorres_delete_asid_pool])
          apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
          apply (clarsimp simp:transform_cap_def)
        apply (wp|clarsimp)+
      apply (clarsimp split:option.splits | rule conjI)+
-- arch_cap.PageCap
        apply (rule corres_dummy_return_pr)
          apply (rule corres_guard_imp)
            apply (rule corres_split[OF _ dcorres_unmap_page_empty])
            unfolding K_bind_def
            apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
            apply (clarsimp simp:transform_cap_def)
        apply (wp|clarsimp split:)+
          apply (rule corres_guard_imp)
            apply (rule_tac fun1 = "set" in  corres_split[OF _ dcorres_unmap_page])
              apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
              apply (clarsimp simp:transform_cap_def)
            apply (wp | clarsimp )+
    apply (clarsimp split:option.splits | rule conjI)+
      apply (rule corres_dummy_return_pr)
        apply (rule corres_guard_imp)
          apply (rule corres_split[OF _ dcorres_unmap_page_table_empty])
            unfolding K_bind_def
            apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
            apply (clarsimp simp:transform_cap_def)
        apply (wp|clarsimp)+
--arch_cap.PageTableCap
      apply (rule dcorres_expand_pfx)
      apply (rule corres_guard_imp)
        apply (rule corres_split[OF _ dcorres_unmap_page_table])
          apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
          apply (clarsimp simp:transform_cap_def)
        apply ((wp|clarsimp )+)[4]
          apply (rule iffD1[OF le_mask_iff_lt_2n,THEN iffD2],simp add:word_size asid_bits_def)
          apply (clarsimp simp:valid_cap_def cap_aligned_def  )+
          apply (simp add:vmsz_aligned_def)
        apply (wp|clarsimp)+
      apply (rule conjI | clarsimp split:option.splits)+
      apply (rule corres_guard_imp)
        apply (rule corres_split[OF _ dcorres_delete_asid])
          apply (rule iffD2[OF corres_return[where P=\<top> and P'=\<top>]])
          apply (clarsimp simp:transform_cap_def)
         apply (wp|clarsimp split:option.splits)+
done

lemma dcorres_splits:
  "\<lbrakk> T a \<Longrightarrow> dcorres r P (Q a) f (g a);
    \<not> T a \<Longrightarrow> dcorres r P (Q' a) f (g a)\<rbrakk>\<Longrightarrow>
    dcorres r P ( (\<lambda>s. (T a) \<longrightarrow> (Q a s)) and (\<lambda>s. (\<not> (T a)) \<longrightarrow> (Q' a s)) ) f (g a)"
  apply (case_tac "T a")
    apply clarsimp+
done

lemma get_cap_weak_wp:
  "\<lbrace>cte_wp_at Q slot\<rbrace> CSpaceAcc_A.get_cap slot \<lbrace>\<lambda>rv s. Q rv\<rbrace>"
  by (clarsimp simp:valid_def cte_wp_at_def)

definition remainder_cap :: "bool \<Rightarrow> cap \<Rightarrow> cap"
where "remainder_cap final c\<equiv> case c of
  cap.CNodeCap r bits g \<Rightarrow> if final then cap.Zombie r (Some bits) (2 ^ bits) else cap.NullCap
| cap.ThreadCap r \<Rightarrow> if final then cap.Zombie r None 5 else cap.NullCap
| cap.Zombie r b n \<Rightarrow> cap.Zombie r b n
| cap.ArchObjectCap a \<Rightarrow> cap.NullCap
| _ \<Rightarrow> cap.NullCap"

lemma finalise_cap_remainder:
  "\<lbrace>\<top>\<rbrace>CSpace_A.finalise_cap cap final \<lbrace>\<lambda>r s. fst (r) = (remainder_cap final cap) \<rbrace>"
  apply (case_tac cap)
    apply (simp_all add:CSpace_A.finalise_cap.simps remainder_cap_def)
    apply (wp|clarsimp)+
     apply (fastforce simp:valid_def)
     apply (simp|clarify)+
   apply (wp|clarsimp)+
     apply (fastforce simp:valid_def)
     apply (simp|clarify)+
   apply (wp|clarsimp|rule conjI)+
   apply (simp add:arch_finalise_cap_def)
     apply (cases final)
       apply (case_tac arch_cap)
         apply (simp_all)
         apply (wp|clarsimp)+
         apply (simp_all split:option.splits)
         apply (wp | clarsimp | rule conjI)+
       apply (case_tac arch_cap)
         apply simp_all
       apply (wp|clarsimp split:option.splits | rule conjI)+
done

lemma obj_ref_not_idle:
  "\<lbrakk>valid_objs s;valid_global_refs s;cte_at slot s\<rbrakk> \<Longrightarrow> cte_wp_at (\<lambda>cap. \<forall>x\<in>obj_refs cap. not_idle_thread x s) slot s"
  apply (simp add:valid_global_refs_def valid_refs_def)
  apply (case_tac slot)
  apply clarsimp
  apply (drule_tac x = a in spec)
  apply (drule_tac x = b in spec)
  apply (clarsimp simp:cte_wp_at_def not_idle_thread_def cap_range_def global_refs_def)
done


lemma singleton_set_eq:
  "\<lbrakk>x = {a}; b\<in> x\<rbrakk>\<Longrightarrow> b = a"
  by clarsimp

lemma zombies_final_ccontr:
  "\<lbrakk>caps_of_state s p = Some cap; r \<in> obj_refs cap; is_zombie cap; zombies_final s;
     caps_of_state s p' = Some cap'\<rbrakk>
    \<Longrightarrow> r\<in> obj_refs cap' \<longrightarrow> is_zombie cap' \<and> p = p'"
  apply (rule ccontr)
  apply (case_tac p)
  apply (clarsimp simp:zombies_final_def)
  apply (drule_tac x = a in spec,drule_tac x = b in spec)
  apply (frule caps_of_state_cteD)
    apply (simp add:cte_wp_at_def)
  apply (clarsimp simp:IpcCancel_A.is_final_cap'_def)
  apply (frule_tac a = "(aa,ba)" and b = p' in singleton_set_eq)
    apply (clarsimp)
    apply (drule_tac a = "(aa,ba)" and b = p' in singleton_set_eq)
      apply (clarsimp dest!:caps_of_state_cteD simp:cte_wp_at_def)
      apply (drule IntI)
        apply simp+
  apply (drule_tac a = "(aa,ba)" and b = "(a,b)" in singleton_set_eq)
    apply clarsimp
  apply clarsimp
done

lemma zombie_cap_has_all:
  "\<lbrakk>valid_objs s;if_unsafe_then_cap s; zombies_final s;valid_global_refs s;
    caps_of_state s slot = Some (cap.Zombie w option n);
    (w,x) \<notin> cte_refs (cap.Zombie w option n) f  \<rbrakk>
    \<Longrightarrow>  caps_of_state s (w,x) = None \<or> caps_of_state s (w,x) = Some cap.NullCap"
  apply (clarsimp simp:if_unsafe_then_cap_def valid_cap_def split:option.splits)
    apply (drule_tac x = w in spec,drule_tac x = x in spec)
    apply (rule ccontr)
    apply clarsimp
    apply (clarsimp simp:ex_cte_cap_wp_to_def appropriate_cte_cap_def)
    apply (drule iffD1[OF cte_wp_at_caps_of_state])
    apply clarsimp
    apply (frule_tac p = slot and p'="(a,b)" in zombies_final_ccontr)
      apply simp+
      apply (simp add:is_zombie_def)
      apply simp+
    apply (case_tac cap)
      apply simp_all
      apply (case_tac y)
      apply simp_all
      apply (frule_tac p = "(a,b)" in caps_of_state_valid_cap)
        apply simp
      apply (frule_tac p = slot in caps_of_state_valid_cap)
        apply simp
      apply (clarsimp simp:valid_cap_def tcb_at_def dest!:get_tcb_SomeD)
      apply (drule_tac p = "(interrupt_irq_node s word,[])" in caps_of_state_cteD)
      apply (clarsimp simp:cte_wp_at_cases)
      apply (clarsimp simp:obj_at_def is_tcb_def tcb_cap_cases_def tcb_cnode_index_def to_bl_1
        split:if_splits)
   apply (drule valid_globals_irq_node[OF _ caps_of_state_cteD])
   apply simp
   apply (fastforce simp:cap_range_def)
done

lemma monadic_trancl_steps:
  "monadic_rewrite False False \<top>
     (monadic_trancl f x)
     (do y \<leftarrow> monadic_trancl f x;
           monadic_trancl f y od)"
  apply (simp add: monadic_rewrite_def monadic_trancl_def
                   bind_def split_def monadic_option_dest_def)
  apply (safe, simp_all)
  done

lemma monadic_trancl_f:
  "monadic_rewrite False False \<top>
     (monadic_trancl f x) (f x)"
  apply (simp add: monadic_rewrite_def monadic_trancl_def
                   bind_def split_def monadic_option_dest_def)
  apply (safe, simp_all)
   apply (simp add: r_into_rtrancl monadic_option_relation_form_def)+
  done

lemma monadic_trancl_step:
  "monadic_rewrite False False \<top>
       (monadic_trancl f x) (do y \<leftarrow> f x; monadic_trancl f y od)"
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_trancl_steps)
   apply (rule monadic_rewrite_bind_head)
   apply (rule monadic_trancl_f)
  apply simp
  done

lemma monadic_trancl_return:
  "monadic_rewrite False False \<top>
          (monadic_trancl f x) (return x)"
  by (simp add: monadic_rewrite_def monadic_trancl_def
                monadic_option_dest_def return_def)

lemma monadic_rewrite_if_lhs:
  "\<lbrakk> P \<Longrightarrow> monadic_rewrite F E Q b a;
     \<not> P \<Longrightarrow> monadic_rewrite F E R c a\<rbrakk>
     \<Longrightarrow> monadic_rewrite F E (\<lambda>s. (P \<longrightarrow> Q s) \<and> (\<not> P \<longrightarrow> R s))
        (if P then b else c) a"
  by (cases P, simp_all)

lemma monadic_rewrite_option_case:
  "\<lbrakk> \<And>y. x = Some y \<Longrightarrow> monadic_rewrite E F (P x) f (g y);
           x = None \<Longrightarrow> monadic_rewrite E F Q f h \<rbrakk>
     \<Longrightarrow> monadic_rewrite E F (\<lambda>s. (\<forall>y. x = Some y \<longrightarrow> P x s) \<and> (x = None \<longrightarrow> Q s))
              f (case x of Some y \<Rightarrow> g y | None \<Rightarrow> h)"
  by (cases x, simp_all)

lemma rtrancl_idem:
  assumes S: "S `` T = T"
       shows "S\<^sup>* `` T = T"
proof -
  note P = eqset_imp_iff[OF S, THEN iffD1, OF ImageI]
  have Q: "\<And>x y. (x, y) \<in> S\<^sup>* \<Longrightarrow> x \<in> T \<longrightarrow> y \<in> T"
    by (erule rtrancl.induct, auto dest: P)

  thus ?thesis
    by auto
qed

lemma monadic_trancl_lift_Inl:
  "monadic_trancl (lift f) (Inl err) = throwError err"
  apply (rule ext)
  apply (simp add: throwError_def return_def monadic_trancl_def)
  apply (subst rtrancl_idem)
   apply (auto simp: monadic_option_relation_form_def lift_def
                     throwError_def return_def monadic_option_dest_def)
  done

lemma monadic_trancl_preemptible_steps:
  "monadic_rewrite False False \<top>
      (monadic_trancl_preemptible f x)
      (doE y \<leftarrow> monadic_trancl_preemptible f x;
              monadic_trancl_preemptible f y odE)"
  apply (simp add: monadic_trancl_preemptible_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_trancl_steps)
   apply (simp add: bindE_def)
   apply (rule_tac Q="\<top>\<top>" in monadic_rewrite_bind_tail)
    apply (case_tac x)
     apply (simp add: lift_def monadic_trancl_lift_Inl)
     apply (rule monadic_rewrite_refl)
    apply (simp add: lift_def)
    apply (rule monadic_rewrite_refl)
   apply (wp | simp)+
  done

lemma monadic_trancl_preemptible_f:
  "monadic_rewrite False False (\<lambda>_. True)
     (monadic_trancl_preemptible f x) (f x)"
  apply (simp add: monadic_trancl_preemptible_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_trancl_f)
   apply (simp add: lift_def)
   apply (rule monadic_rewrite_refl)
  apply simp
  done

lemmas monadic_rewrite_bindE_head
    = monadic_rewrite_bindE[OF _ monadic_rewrite_refl hoare_vcg_propE_R]

lemma monadic_trancl_preemptible_step:
  "monadic_rewrite False False \<top>
      (monadic_trancl_preemptible f x)
      (doE y \<leftarrow> f x;
            monadic_trancl_preemptible f y odE)"
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_trancl_preemptible_steps)
   apply (rule monadic_rewrite_bindE_head)
   apply (rule monadic_trancl_preemptible_f)
  apply simp
  done

lemma monadic_trancl_preemptible_return:
  "monadic_rewrite False False (\<lambda>_. True)
     (monadic_trancl_preemptible f x) (returnOk x)"
  apply (simp add: monadic_trancl_preemptible_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_trans)
    apply (rule monadic_trancl_return)
   apply (simp add: returnOk_def)
   apply (rule monadic_rewrite_refl)
  apply simp
  done

lemma monadic_rewrite_corres2:
  "\<lbrakk> monadic_rewrite False E Q a a';
        corres_underlying R F r P P' a' c \<rbrakk>
     \<Longrightarrow> corres_underlying R F r (P and Q) P' a c"
  apply (simp add: corres_underlying_def monadic_rewrite_def)
  apply (erule ballEI, clarsimp)
  apply (drule(1) bspec, clarsimp)
  apply (drule spec, drule(1) mp)
  apply fastforce
  done

lemma dcorres_get_cap_symb_exec:
  "\<lbrakk> \<And>cap. dcorres r (P cap) (P' cap) f (g cap) \<rbrakk>
        \<Longrightarrow> dcorres r
          (\<lambda>s. \<forall>cap. opt_cap (transform_cslot_ptr slot) s = Some (transform_cap cap) \<longrightarrow> P cap s)
          (\<lambda>s. fst slot \<noteq> idle_thread s \<and> (\<forall>cap. caps_of_state s slot = Some cap \<longrightarrow> P' cap s) \<and> valid_etcbs s)
          f (do cap \<leftarrow> get_cap slot; g cap od)"
  apply (rule corres_symb_exec_r[OF _ get_cap_sp])
    apply (rule stronger_corres_guard_imp, assumption)
     apply (clarsimp simp: cte_wp_at_caps_of_state caps_of_state_transform_opt_cap)
    apply (clarsimp simp: cte_wp_at_caps_of_state)
   apply (wp | simp)+
  done

lemma set_cdt_modify:
  "set_cdt c = modify (\<lambda>s. s \<lparr> cdt := c \<rparr>)"
  by (simp add: set_cdt_def modify_def)

lemma no_cdt_loop_mloop:
  "no_mloop m \<Longrightarrow> m x \<noteq> Some x"
  apply (rule notI)
  apply (simp add: no_mloop_def cdt_parent_rel_def del: split_paired_All)
  apply (drule_tac x=x in spec)
  apply (erule notE, rule r_into_trancl)
  apply (simp add: is_cdt_parent_def)
  done

lemma set_cdt_list_modify:
  "set_cdt_list c = modify (\<lambda>s. s \<lparr> cdt_list := c \<rparr>)"
  by (simp add: set_cdt_list_def modify_def)

lemma swap_cap_corres:
  "dcorres dc \<top> (valid_idle and valid_mdb and cte_at slot_a and cte_at slot_b
                 and valid_etcbs and K (slot_a \<noteq> slot_b)
                 and not_idle_thread (fst slot_a)
                 and not_idle_thread (fst slot_b))
     (swap_cap (transform_cap cap_a) (transform_cslot_ptr slot_a)
               (transform_cap cap_b) (transform_cslot_ptr slot_b))
     (cap_swap cap_a slot_a cap_b slot_b)"
proof -
  note inj_on_insert[iff del]
  show ?thesis
  apply (simp add: swap_cap_def cap_swap_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split_nor [OF _ set_cap_corres[OF refl refl]])
      apply (rule corres_split_nor [OF _ set_cap_corres[OF refl refl]])
        apply (simp add: swap_parents_def set_original_def
                         set_cdt_modify gets_fold_into_modify bind_assoc
                         cap_swap_ext_def update_cdt_list_def set_cdt_list_modify)
        apply (simp add: gets_fold_into_modify modify_modify Fun.swap_def o_def)
        apply (rule_tac P'="K (slot_a \<noteq> slot_b) and cte_at slot_a and cte_at slot_b
                              and (\<lambda>s. mdb_cte_at (swp cte_at s) (cdt s))
                              and no_mloop o cdt"
                   and P=\<top> in corres_modify)

        apply (clarsimp simp:transform_def transform_current_thread_def
                             transform_asid_table_def transform_objects_def
                             transform_cdt_def split del: split_if)
        apply (rule sym)
        apply (subgoal_tac "inj_on transform_cslot_ptr
                   ({slot_a, slot_b} \<union> dom (cdt s') \<union> ran (cdt s'))
                     \<and> cdt s' slot_a \<noteq> Some slot_a \<and> cdt s' slot_b \<noteq> Some slot_b")
         apply (elim conjE)
         apply (subst map_lift_over_upd, erule subset_inj_on)
          apply (safe elim!: ranE, simp_all split: split_if_asm,
                 simp_all add: ranI)[1]
         apply (subst map_lift_over_upd, erule subset_inj_on)
          apply (safe elim!: ranE, simp_all split: split_if_asm,
                 simp_all add: ranI)[1]
         apply (subst map_lift_over_if_eq_twice)
          apply (erule subset_inj_on, fastforce)
         apply (rule ext)
         apply (cases slot_a, cases slot_b)
         apply (simp split del: split_if)
         apply (intro if_cong[OF refl],
                simp_all add: map_lift_over_eq_Some inj_on_iff[where f=transform_cslot_ptr]
                              ranI domI)[1]
          apply (subst subset_inj_on, assumption, fastforce)+
          prefer 2
          apply (subst subset_inj_on, assumption, fastforce)+
          apply (auto simp: map_lift_over_eq_Some inj_on_iff[where f=transform_cslot_ptr]
                            ranI domI
                     intro: map_lift_over_f_eq[THEN iffD2, OF _ refl]
                      elim: subset_inj_on)[2]
        apply (clarsimp simp: no_cdt_loop_mloop)
        apply (rule_tac s=s' in transform_cdt_slot_inj_on_cte_at[where P=\<top>])
        apply (auto simp: swp_def dest: mdb_cte_atD
                    elim!: ranE)[1]
       apply (wp set_cap_caps_of_state2 set_cap_idle
                  | simp add: swp_def cte_wp_at_caps_of_state)+
  apply clarsimp
  apply (clarsimp simp: cte_wp_at_caps_of_state valid_mdb_def)
  apply (safe intro!: mdb_cte_atI)
     apply (auto simp: swp_def cte_wp_at_caps_of_state not_idle_thread_def
                 dest: mdb_cte_atD elim!: ranE)
    done
qed

lemma swap_for_delete_corres:
  "dcorres dc \<top> (valid_mdb and valid_idle and not_idle_thread (fst p)
                     and not_idle_thread (fst p') and valid_etcbs and (\<lambda>_. p \<noteq> p'))
      (swap_for_delete (transform_cslot_ptr p) (transform_cslot_ptr p'))
      (cap_swap_for_delete p p')"
  apply (rule corres_gen_asm2)
  apply (simp add: swap_for_delete_def cap_swap_for_delete_def
                   when_def)
  apply (rule corres_guard_imp)
    apply (rule corres_split[OF _ get_cap_corres[OF refl]])+
        apply simp
        apply (rule swap_cap_corres)
       apply (wp get_cap_wp)
   apply simp
  apply (clarsimp simp: cte_wp_at_caps_of_state)
  done

definition
  "arch_page_vmpage_size cap \<equiv>
   case cap of cap.ArchObjectCap (arch_cap.PageCap _ _ sz _) \<Rightarrow> sz
         | _ \<Rightarrow> undefined"

lemma set_cap_noop_dcorres3:
  "dcorres dc \<top> (cte_wp_at (\<lambda>cap'. transform_cap cap = transform_cap cap'
                                 \<and> arch_page_vmpage_size cap = arch_page_vmpage_size cap') ptr)
    (return ()) (set_cap cap ptr)"
  apply (rule corres_noop, simp_all)
  apply (simp add: set_cap_def split_def set_object_def)
  apply (wp get_object_wp | wpc)+
  apply (clarsimp simp: obj_at_def)
  apply (erule cte_wp_atE)
   apply (clarsimp simp: transform_def transform_current_thread_def
                         transform_objects_def)
   apply (rule ext)
   apply (simp add: fun_upd_def[symmetric]
               del: dom_fun_upd)
   apply (simp add: restrict_map_def transform_cnode_contents_def
                    fun_eq_iff option_map_join_def map_add_def
             split: option.split nat.split)
  apply (clarsimp simp: transform_def transform_current_thread_def
                        transform_objects_def fun_eq_iff
                        arch_page_vmpage_size_def)
  apply (simp add: restrict_map_def transform_cnode_contents_def map_add_def
                   transform_tcb_def fun_eq_iff infer_tcb_pending_op_def
            split: option.split cong: Structures_A.thread_state.case_cong)
  apply (subgoal_tac "snd ptr = tcb_cnode_index 4 \<longrightarrow>
                       (\<forall>ms ns. get_ipc_buffer_words ms (tcb\<lparr>tcb_ipcframe := cap\<rparr>) ns
                          = get_ipc_buffer_words ms tcb ns)")
   apply (simp cong: transform_full_intent_cong)
   apply (simp add: transform_full_intent_def Let_def get_tcb_message_info_def
                    get_tcb_mrs_def)
   apply fastforce
  apply clarsimp
  apply (simp add: transform_cap_def split: cap.split_asm arch_cap.split_asm split_if_asm,
         simp_all add: get_ipc_buffer_words_def)
  done

lemma finalise_zombie:
  "is_zombie cap \<Longrightarrow> finalise_cap cap final
        = do assert final; return (cap, None) od"
  by (clarsimp simp add: is_cap_simps)

lemma corres_assert_rhs:
  "(F \<Longrightarrow> corres_underlying sr False r P P' f (g ()))
    \<Longrightarrow> corres_underlying sr False r P (\<lambda>s. F \<longrightarrow> P' s) f (assert F >>= g)"
  by (cases F, simp_all add: corres_fail)

lemma monadic_rewrite_select_x:
  "monadic_rewrite F False
      (\<lambda>s. x \<in> S) (select S) (return x)"
  by (simp add: monadic_rewrite_def return_def select_def)

lemmas monadic_rewrite_select_pick_x
    = monadic_rewrite_bind_head
         [OF monadic_rewrite_select_x[where x=x], simplified,
          THEN monadic_rewrite_trans, standard]

lemma finalise_cap_zombie':
  "(case cap of ZombieCap _ \<Rightarrow> True | _ \<Rightarrow> False)
     \<Longrightarrow> CSpace_D.finalise_cap cap fin =
              do assert fin; return (cap, None) od"
  by (simp split: cdl_cap.split_asm)

lemma corres_use_cutMon:
  "\<lbrakk> \<And>s. corres_underlying sr fl r P P' f (cutMon (op = s) g) \<rbrakk>
       \<Longrightarrow> corres_underlying sr fl r P P' f g"
  apply atomize
  apply (simp add: corres_underlying_def cutMon_def fail_def
            split: split_if_asm)
  apply (clarsimp simp: split_def)
  done

lemma corres_drop_cutMon:
  "corres_underlying sr False r P P' f g
     \<Longrightarrow> corres_underlying sr False r P P' f (cutMon Q g)"
  apply (simp add: corres_underlying_def cutMon_def fail_def
            split: split_if)
  apply (clarsimp simp: split_def)
  done

lemma corres_drop_cutMon_bind:
  "corres_underlying sr False r P P' f (g >>= h)
     \<Longrightarrow> corres_underlying sr False r P P' f (cutMon Q g >>= h)"
  apply (simp add: corres_underlying_def cutMon_def fail_def bind_def
            split: split_if)
  apply (clarsimp simp: split_def)
  done

lemma corres_drop_cutMon_bindE:
  "corres_underlying sr False r P P' f (g >>=E h)
     \<Longrightarrow> corres_underlying sr False r P P' f (cutMon Q g >>=E h)"
  apply (simp add: bindE_def)
  apply (erule corres_drop_cutMon_bind)
  done

lemma corres_cutMon:
  "\<lbrakk> \<And>s. Q s \<Longrightarrow> corres_underlying sr False r P P' f (cutMon (op = s) g) \<rbrakk>
         \<Longrightarrow> corres_underlying sr False r P P' f (cutMon Q g)"
  apply atomize
  apply (simp add: corres_underlying_def cutMon_def fail_def
            split: split_if_asm)
  apply (clarsimp simp: split_def)
  done

lemma underlying_memory_irq_state_independent[intro!, simp]:
  "underlying_memory (s\<lparr>irq_state := f (irq_state s)\<rparr>)
   = underlying_memory s"
  by simp


lemma get_ipc_buffer_words_irq_state_independent[intro!, simp]:
  "get_ipc_buffer_words (s\<lparr>irq_state := f (irq_state s)\<rparr>)
   = get_ipc_buffer_words s"
  apply (rule ext, rule ext)
  apply (simp add: get_ipc_buffer_words_def)
  apply (case_tac "tcb_ipcframe x", simp_all)
  apply (clarsimp split: ARM_Structs_A.arch_cap.splits)
  apply (rule arg_cong[where f=the])
  apply (rule evalMonad_mapM_cong)
    apply (simp add: evalMonad_def)
    apply safe
      apply ((clarsimp simp: loadWord_def bind_def gets_def get_def return_def in_monad)+)[3]
   apply (rule loadWord_inv)
  apply (rule df_loadWord)
  done

lemma get_tcb_mrs_irq_state_independent[intro!, simp]:
  "get_tcb_mrs (s\<lparr>irq_state := f (irq_state s)\<rparr>)
   = get_tcb_mrs s"
  by (auto simp: get_tcb_mrs_def)

lemma transform_full_intent_irq_state_independent[intro!, simp]:
  "transform_full_intent (s\<lparr>irq_state := f (irq_state s)\<rparr>)
   = transform_full_intent s"
  by (rule ext, rule ext, simp add: transform_full_intent_def)

lemma transform_tcb_irq_state_independent[intro!, simp]:
  "transform_tcb (s\<lparr>irq_state := f (irq_state s)\<rparr>)
   = transform_tcb s"
  by (rule ext, rule ext, rule ext, simp add: transform_tcb_def)

lemma transform_object_irq_state_independent[intro!, simp]:
  "transform_object (s \<lparr> irq_state := f (irq_state s) \<rparr>)
   = transform_object s"
  by (rule ext, rule ext, rule ext,
      simp add: transform_object_def
         split: Structures_A.kernel_object.splits)

lemma transform_objects_irq_state_independent[intro!, simp]:
  "transform_objects (s \<lparr> machine_state := machine_state s \<lparr> irq_state := f (irq_state (machine_state s)) \<rparr> \<rparr>)
   = transform_objects s"
  by (simp add: transform_objects_def)

lemma transform_irq_state_independent[intro!, simp]:
  "transform (s \<lparr> machine_state := machine_state s \<lparr> irq_state := f (irq_state (machine_state s)) \<rparr> \<rparr>)
   = transform s"
  by (simp add: transform_def transform_current_thread_def)

lemma transform_work_units_independent[intro!, simp]:
  "transform (s \<lparr> work_units_completed := f (work_units_completed s) \<rparr>)
   = transform s"
  apply (simp add: transform_def transform_current_thread_def transform_objects_def transform_cdt_def transform_asid_table_def)
  done

lemma transform_work_units_then_irq_state_independent[intro!, simp]:
  "transform (s \<lparr> work_units_completed := g (work_units_completed s) \<rparr>
                \<lparr> machine_state := machine_state s \<lparr> irq_state := f (irq_state (machine_state s)) \<rparr>\<rparr>) =
   transform s"
  apply (simp add: transform_def transform_current_thread_def transform_objects_def transform_cdt_def transform_asid_table_def)
  done

lemma throw_or_return_preemption_corres:
  "dcorres (dc \<oplus> dc) P P'
       (Monads_D.throw \<sqinter> returnOk ())
       preemption_point"
  apply (simp add: preemption_point_def)
  apply (auto simp: preemption_point_def o_def gets_def liftE_def whenE_def getActiveIRQ_def
                    corres_underlying_def select_def bind_def get_def bindE_def select_f_def modify_def
                    alternative_def throwError_def returnOk_def return_def lift_def
                    put_def do_machine_op_def
                    update_work_units_def wrap_ext_bool_det_ext_ext_def work_units_limit_def
                    work_units_limit_reached_def OR_choiceE_def reset_work_units_def mk_ef_def
           split: option.splits kernel_object.splits)
  done

lemma cutMon_fail:
  "cutMon P fail = fail"
  by (simp add: cutMon_def)

declare rec_del.simps[simp del]

lemma select_pick_corres_asm:
  "\<lbrakk> x \<in> S; corres_underlying sr nf r P Q (f x) g \<rbrakk>
    \<Longrightarrow> corres_underlying sr nf r P Q (select S >>= f) g"
  by (drule select_pick_corres[where x=x and S=S], simp)

lemma invs_weak_valid_mdb:
  "invs s \<longrightarrow> weak_valid_mdb s"
  by (simp add: weak_valid_mdb_def invs_def valid_mdb_def valid_state_def)

lemma invs_valid_idle_strg:
  "invs s \<longrightarrow> valid_idle s"
  by auto

lemma cutMon_validE_R_drop:
  "\<lbrace>P\<rbrace> f \<lbrace>Q\<rbrace>,- \<Longrightarrow> \<lbrace>P\<rbrace> cutMon R f \<lbrace>Q\<rbrace>,-"
  by (simp add: validE_R_def validE_def cutMon_valid_drop)

crunch idle_thread [wp]: cap_swap_for_delete "\<lambda>s. P (idle_thread s)"
(wp: dxo_wp_weak)

crunch idle_thread [wp]: finalise_cap "\<lambda>s. P (idle_thread s)"
 (wp: crunch_wps simp: crunch_simps)

lemma preemption_point_idle_thread[wp]: "\<lbrace> \<lambda>s. P (idle_thread s) \<rbrace> preemption_point \<lbrace> \<lambda>_ s. P (idle_thread (s :: det_state)) \<rbrace>"
  apply (clarsimp simp: preemption_point_def)
  apply (auto simp: valid_def o_def gets_def liftE_def whenE_def getActiveIRQ_def
                    corres_underlying_def select_def bind_def get_def bindE_def select_f_def modify_def
                    alternative_def throwError_def returnOk_def return_def lift_def
                    put_def do_machine_op_def
                    update_work_units_def wrap_ext_bool_det_ext_ext_def work_units_limit_def
                    work_units_limit_reached_def OR_choiceE_def reset_work_units_def mk_ef_def
           split: option.splits kernel_object.splits)
  done

lemma rec_del_idle_thread[wp]:
  "\<lbrace>\<lambda>s. P (idle_thread s)\<rbrace> rec_del args \<lbrace>\<lambda>rv s. P (idle_thread (s :: det_state))\<rbrace>"
  by (wp rec_del_preservation | simp)+

lemma gets_constant:
  "gets (\<lambda>_. x) = return x"
  by (simp add: return_def simpler_gets_def)

lemma monadic_rewrite_gets_the_gets:
  "monadic_rewrite F E (\<lambda>s. f s \<noteq> None) (gets_the f) (gets (the o f))"
  apply (simp add: monadic_rewrite_def gets_the_def assert_opt_def exec_gets
            split: option.split)
  apply (auto simp: simpler_gets_def return_def)
  done

lemmas corres_gets_the_bind
    = monadic_rewrite_corres2[OF monadic_rewrite_bind_head [OF monadic_rewrite_gets_the_gets]]

lemma finalise_slot_inner1_add_if_Null:
  "monadic_rewrite F False \<top>
     (finalise_slot_inner1 victim)
     (do cap \<leftarrow> KHeap_D.get_cap victim;
        if cap = cdl_cap.NullCap then return (cdl_cap.NullCap, True)
        else do
          final \<leftarrow> PageTableUnmap_D.is_final_cap cap;
          (cap', irqopt) \<leftarrow> CSpace_D.finalise_cap cap final;
          removeable \<leftarrow> gets $ CSpace_D.cap_removeable cap' victim;
          when (\<not> removeable) (KHeap_D.set_cap victim cap')
               \<sqinter> KHeap_D.set_cap victim cap';
          return (cap', removeable)
       od
     od)"
  apply (simp add: finalise_slot_inner1_def)
  apply (rule monadic_rewrite_imp)
   apply (rule monadic_rewrite_bind_tail)
    apply (rule monadic_rewrite_if_rhs)
     apply (simp add: PageTableUnmap_D.is_final_cap_def)
     apply (rule monadic_rewrite_trans)
      apply (rule monadic_rewrite_bind_tail[where j="\<lambda>_. j", standard, OF _ gets_wp])+
      apply (rename_tac remove, rule_tac P=remove in monadic_rewrite_gen_asm)
      apply simp
      apply (rule monadic_rewrite_refl)
     apply (simp add: gets_bind_ign when_def)
     apply (rule monadic_rewrite_trans)
      apply (rule monadic_rewrite_bind_head)
      apply (rule monadic_rewrite_pick_alternative_1)
     apply simp
     apply (rule monadic_rewrite_refl)
    apply (rule monadic_rewrite_refl)
   apply wp
  apply (clarsimp simp: CSpace_D.cap_removeable_def)
  done

lemma corres_if_rhs_only:
  "\<lbrakk> G \<Longrightarrow> corres_underlying sr nf rvr P Q a b;
      \<not> G \<Longrightarrow> corres_underlying sr nf rvr P' Q' a c\<rbrakk>
       \<Longrightarrow> corres_underlying sr nf rvr
             (P and P') (\<lambda>s. (G \<longrightarrow> Q s) \<and> (\<not> G \<longrightarrow> Q' s))
             a (if G then b else c)"
  by (rule corres_guard_imp, rule corres_if_rhs, simp+)

lemma OR_choiceE_det:
  "\<lbrakk>det c; \<And>P. \<lbrace>P\<rbrace> c \<lbrace>\<lambda>rv. P\<rbrace>\<rbrakk> \<Longrightarrow> (OR_choiceE c (f :: ('a + 'b) det_ext_monad) g)
     = (doE rv \<leftarrow> liftE c; if rv then f else g odE)"
  apply (rule ext)
  apply (clarsimp simp: OR_choiceE_def select_f_def bind_def det_def valid_def
               wrap_ext_bool_det_ext_ext_def get_def bindE_def ethread_get_def split_def
               gets_the_def assert_opt_def return_def gets_def fail_def mk_ef_def liftE_def no_fail_def
               split: option.splits prod.splits)
  apply atomize
  apply (erule_tac x="op = x" in allE)
  apply (erule_tac x=x in allE)+
  apply clarsimp
  done

lemma transform_work_units_completed_update[simp]: "transform (s\<lparr> work_units_completed := a \<rparr>) = transform s"
  by (auto simp: transform_def transform_cdt_def transform_current_thread_def transform_asid_table_def transform_objects_def)

lemma finalise_preemption_corres:
  "dcorres (dc \<oplus> (\<lambda>rv rv'. fst S \<subseteq> fst rv)) \<top> \<top>
      (monadic_trancl_preemptible finalise_slot_inner2 S) (preemption_point)"
  apply (simp add: finalise_slot_inner2_def preemption_point_def split_def)
  apply (subst OR_choiceE_det)
    apply (simp add: work_units_limit_reached_def)
   apply ((simp add: work_units_limit_reached_def | wp)+)[1]
  apply (rule corres_guard_imp)


    apply (rule dcorres_symb_exec_rE)
      apply (rule dcorres_symb_exec_rE)
        apply simp
        apply (rule conjI, clarsimp)
         apply (rule dcorres_symb_exec_rE)
           apply (rule dcorres_symb_exec_rE)
             apply (simp split: option.splits)
             apply (rule conjI, clarsimp)
              apply (rule monadic_rewrite_corres2)
               apply (rule monadic_trancl_preemptible_return)
              apply (rule dcorres_returnOk, simp)
             apply clarsimp
             apply (rule corres_guard_imp)
               apply (rule monadic_rewrite_corres2)
                apply (rule monadic_trancl_preemptible_f)
               apply (rule corres_alternate2[OF dcorres_throw], simp_all)[4]
           apply ((wp | simp)+)[1]
          apply (rule hoare_TrueI)
         apply ((simp add: reset_work_units_def | wp)+)[1]
        apply clarsimp
        apply (rule corres_guard_imp)
          apply (rule monadic_rewrite_corres2)
           apply (rule monadic_trancl_preemptible_return)
          apply (rule dcorres_returnOk, simp_all)[3]
       apply (rule hoare_TrueI)
      apply ((simp add: work_units_limit_reached_def | wp)+)[1]
     apply (rule hoare_TrueI)
    apply (simp add: update_work_units_def | wp)+
  done

lemma zombie_is_cap_toE_pre2:
  "\<lbrakk> s \<turnstile> cap.Zombie ptr zbits n; m < n \<rbrakk>
     \<Longrightarrow> (ptr, nat_to_cref (zombie_cte_bits zbits) m) \<in> cte_refs (cap.Zombie ptr zbits n) irqn"
  apply (clarsimp simp add: valid_cap_def cap_aligned_def)
  apply (clarsimp split: option.split_asm)
   apply (simp add: unat_of_bl_nat_to_cref)
   apply (simp add: nat_to_cref_def word_bits_conv)
  apply (simp add: unat_of_bl_nat_to_cref)
  apply (simp add: nat_to_cref_def word_bits_conv)
  done

lemma corres_note_assumption:
  "\<lbrakk> F; corres_underlying sr fl r P P' f g \<rbrakk>
        \<Longrightarrow> corres_underlying sr fl r (\<lambda>s. F \<longrightarrow> P s) P' f g"
  by simp

lemma corres_req2:
  "\<lbrakk>\<And>s s'. \<lbrakk>(s, s') \<in> sr; P s; P' s'\<rbrakk> \<Longrightarrow> F; F \<Longrightarrow> corres_underlying sr nf r Q Q' f g\<rbrakk>
         \<Longrightarrow> corres_underlying sr nf r (P and Q) (P' and Q') f g"
  apply (rule_tac F=F in corres_req, simp_all)
  apply (erule corres_guard_imp, simp_all)
  done

lemma nat_split_conv_to_if:
  "(case n of 0 \<Rightarrow> a | Suc nat' \<Rightarrow> f nat') = (if n = 0 then a else f (n - 1))"
  by (auto split: nat.splits)

lemma opt_cap_cnode:
  "\<lbrakk> kheap s y = Some (CNode sz cn); y \<noteq> idle_thread s; well_formed_cnode_n sz cn \<rbrakk>
    \<Longrightarrow> (opt_cap (y, node) (transform s) = Some cap)
           = (\<exists>v cap'. transform_cslot_ptr (y, v) = (y, node)
                   \<and> cn v = Some cap' \<and> cap = transform_cap cap')"
  apply clarsimp
  apply (simp add: opt_cap_def slots_of_def opt_object_def
                   transform_def transform_objects_def restrict_map_def
                   transform_cnode_contents_def option_map_join_def
                   transform_cslot_ptr_def object_slots_def
                   nat_split_conv_to_if
            split: option.split)
  apply (case_tac "sz = 0")
   apply (clarsimp, rule conjI)
    apply (metis nat_to_bl_id2 option.distinct(1) wf_cs_nD)
   apply (metis (full_types) nat_to_bl_bl_to_bin nat_to_bl_id2
                             option.inject wf_cs_nD)
  (* "sz \<noteq> 0" *)
  apply (clarsimp, rule conjI)
   apply (metis nat_to_bl_id2 option.distinct(1) wf_cs_nD)
  apply (metis (full_types) nat_to_bl_bl_to_bin nat_to_bl_id2
                            option.inject wf_cs_nD)
  done

lemma preemption_point_valid_etcbs[wp]: "\<lbrace> valid_etcbs \<rbrace> preemption_point \<lbrace> \<lambda>_. valid_etcbs \<rbrace>"
  apply (clarsimp simp: preemption_point_def)
  apply (auto simp: valid_def o_def gets_def liftE_def whenE_def getActiveIRQ_def
                    corres_underlying_def select_def bind_def get_def bindE_def select_f_def modify_def
                    alternative_def throwError_def returnOk_def return_def lift_def
                    put_def do_machine_op_def
                    update_work_units_def wrap_ext_bool_det_ext_ext_def work_units_limit_def
                    work_units_limit_reached_def OR_choiceE_def reset_work_units_def mk_ef_def
           split: option.splits kernel_object.splits)
  done

crunch valid_etcbs[wp]: cap_swap_ext, cap_swap_for_delete "valid_etcbs"

lemma rec_del_valid_etcbs[wp]:
  "\<lbrace> valid_etcbs \<rbrace> rec_del args \<lbrace>\<lambda>_. valid_etcbs \<rbrace>"
  by (wp rec_del_preservation | simp)+

lemma dcorres_rec_del:
  "\<lbrakk> (case args of CTEDeleteCall slot exp \<Rightarrow> \<not> exp | _ \<Rightarrow> True);
           (transform_cslot_ptr (slot_rdcall args), \<not> exposed_rdcall args) \<in> fst S;
           (case args of ReduceZombieCall (cap.Zombie p zbits (Suc n)) _ _ \<Rightarrow>
               (transform_cslot_ptr (p, replicate (zombie_cte_bits zbits) False), True) \<in> fst S
              \<and> (transform_cslot_ptr (p, nat_to_cref (zombie_cte_bits zbits) n), True) \<in> fst S
               | _ \<Rightarrow> True) \<rbrakk>
   \<Longrightarrow> dcorres (dc \<oplus> (\<lambda>rv rv'. (case args of FinaliseSlotCall _ _ \<Rightarrow>
                          fst rv' \<longrightarrow> (\<exists>v. (transform_cslot_ptr (slot_rdcall args), v) \<in> snd rv
                                 \<and> (\<not> exposed_rdcall args \<longrightarrow> v)) | _ \<Rightarrow> True)
                               \<and> fst S \<subseteq> fst rv))
      \<top>
      (invs and valid_rec_del_call args and cte_at (slot_rdcall args)
            and valid_etcbs
            and valid_pdpt_objs
            and emptyable (slot_rdcall args) and not_idle_thread (fst (slot_rdcall args))
            and (\<lambda>s. \<not> exposed_rdcall args \<longrightarrow>
                   ex_cte_cap_wp_to (\<lambda>cp. cap_irqs cp = {}) (slot_rdcall args) s)
            and (\<lambda>s. case args of
                ReduceZombieCall cap sl ex \<Rightarrow> \<forall>t\<in>obj_refs cap. halted_if_tcb t s
                   | _ \<Rightarrow> True))
      (doE S' \<leftarrow> monadic_trancl_preemptible
           finalise_slot_inner2 S;
         whenE ((case args of ReduceZombieCall _ _ _ \<Rightarrow> False | _ \<Rightarrow> True)
              \<and> exposed_rdcall args
              \<and> \<not> (transform_cslot_ptr (slot_rdcall args)) \<in> fst ` snd S') Monads_D.throw;
         returnOk S'
       odE)
      (cutMon (op = s) (rec_del args))"
proof (induct arbitrary: S rule: rec_del.induct,
       simp_all(no_asm) only: rec_del_fails fail_bindE corres_free_fail cutMon_fail)
  case (1 slot exposed s S)
  note ps = "1.prems"[simplified]
  hence nexp[simp]: "\<not> exposed" by simp
  show ?case
    using ps
    apply (simp add: dc_def[symmetric])
    apply (subst rec_del_simps_ext[unfolded split_def])
    apply simp
    apply (rule corres_guard_imp)
      apply (rule monadic_rewrite_corres2)
       apply (rule monadic_trancl_preemptible_steps)
      apply (simp add: cutMon_walk_bindE)
      apply (rule corres_splitEE)
         prefer 2
         apply (rule "1.hyps"[simplified, folded dc_def], assumption+)
        apply (rule corres_drop_cutMon)
        apply (simp add: liftME_def[symmetric])
        apply (rule_tac R="fst rv" in corres_cases)
         apply (simp add: when_def)
         apply (rule monadic_rewrite_corres2)
          apply (rule monadic_trancl_preemptible_f)
         apply (simp add: finalise_slot_inner2_def[unfolded split_def])
         apply (rule corres_alternate1, rule corres_alternate2)
         apply simp
         apply (rule select_pick_corres_asm)
          apply clarsimp
          apply assumption
         apply (simp add: liftM_def[symmetric] o_def dc_def[symmetric])
         apply (rule empty_slot_corres)
        apply (simp add: when_def)
        apply (rule monadic_rewrite_corres2)
         apply (rule monadic_trancl_preemptible_return)
        apply (rule corres_trivial, simp add: returnOk_liftE)
        apply wp
       apply (wp_trace cutMon_validE_R_drop rec_del_invs
                  | simp add: not_idle_thread_def
                  | strengthen invs_weak_valid_mdb invs_valid_idle_strg
                  | rule hoare_vcg_E_elim[rotated])+

    done
next
  case (2 slot exposed s S)
  note split_if[split del]
  have removeables:
    "\<And>s cap fin. \<lbrakk> cte_wp_at (op = cap) slot s; s \<turnstile> remainder_cap fin cap; invs s; valid_etcbs s;
            CSpace_A.cap_removeable (remainder_cap fin cap) slot  \<rbrakk>
      \<Longrightarrow> CSpace_D.cap_removeable (transform_cap (remainder_cap fin cap))
                 (transform_cslot_ptr slot) (transform s)"
    apply (case_tac "remainder_cap fin cap = cap.NullCap")
     apply (simp add: CSpace_D.cap_removeable_def)
    apply (clarsimp simp: remainder_cap_def valid_cap_simps
                          cte_wp_at_caps_of_state
                   split: cap.split_asm split_if_asm)
    apply (frule valid_global_refsD2, clarsimp)
    apply (clarsimp simp: CSpace_D.cap_removeable_def)
    apply (subgoal_tac "\<exists>x cap. (word, b) = transform_cslot_ptr (word, x)
                              \<and> caps_of_state s (word, x) = Some cap \<and> cap \<noteq> cap.NullCap")
     apply clarsimp
     apply (case_tac "(word, x) \<in> cte_refs (the (caps_of_state s slot)) (interrupt_irq_node s)")
      apply (clarsimp simp: unat_eq_0)
      apply (drule of_bl_eq_0)
       apply (simp add: cap_aligned_def word_bits_conv split: option.split_asm)
      apply clarsimp
     apply (frule zombie_cap_has_all[rotated -2], simp, clarsimp+)
    apply (clarsimp simp: tcb_at_def cap_range_def global_refs_def
                          opt_cap_tcb
                   split: option.split_asm split_if_asm | drule(1) valid_etcbs_get_tcb_get_etcb)+
      apply (rule_tac x="tcb_cnode_index b" in exI)
      apply (clarsimp simp: transform_cslot_ptr_def dest!: get_tcb_SomeD)
      apply (rule conjI, rule sym, rule bl_to_bin_tcb_cnode_index)
       apply (auto simp: tcb_slot_defs)[1]
      apply (rule iffD1[OF cte_wp_at_caps_of_state cte_wp_at_tcbI], (simp | rule conjI)+)
     apply (frule final_zombie_not_live[rotated 1, OF caps_of_state_cteD], clarsimp)
      apply (rule ccontr, erule zombies_finalE)
        apply (simp add: is_cap_simps)
       apply clarsimp
      apply (erule caps_of_state_cteD)
     apply (clarsimp simp: obj_at_def dest!: get_tcb_SomeD)
     apply (auto simp: infer_tcb_pending_op_def)[1]
    apply (clarsimp simp: obj_at_def is_cap_table_def)
    apply (clarsimp simp: opt_cap_cnode
                   split: Structures_A.kernel_object.split_asm)
    apply (subst (asm) opt_cap_cnode, assumption, simp, simp)
    apply clarsimp
    apply (rule exI, rule conjI, erule sym)
    apply (rule iffD1[OF cte_wp_at_caps_of_state cte_wp_at_cteI],
             (simp | rule conjI)+)
    done
  show ?case
    using "2.prems"
    apply (simp add: dc_def[symmetric])
    apply (subst rec_del_simps_ext[unfolded split_def])
    apply (simp add: bindE_assoc, simp add: liftE_bindE)
    apply (rule stronger_corres_guard_imp)
      apply (simp add: cutMon_walk_bind)
      apply (rule corres_drop_cutMon_bind)
      apply (rule monadic_rewrite_corres2)
       apply (rule monadic_rewrite_bindE_head)
       apply (rule monadic_trancl_preemptible_step)
      apply (simp add: finalise_slot_inner2_def
                          [THEN fun_cong, unfolded split_def])
      apply (simp add: alternative_bindE_distrib)
      apply (rule corres_alternate1)+
      apply (simp add: liftE_bindE bind_bindE_assoc bind_assoc)
      apply (rule select_pick_corres_asm, assumption)
      apply (rule monadic_rewrite_corres2)
       apply (rule monadic_rewrite_bind_head)
       apply (rule finalise_slot_inner1_add_if_Null[unfolded split_def])
      apply (simp add: bind_assoc if_to_top_of_bind)
      apply (rule corres_split[OF _ get_cap_corres[OF refl]])
        apply (rename_tac cap)
        apply (rule corres_cutMon)
        apply (simp add: if_to_top_of_bindE cutMon_walk_if
                    del: transform_cap_Null)
        apply (rule Corres_UL.corres_if2[unfolded if_apply_def2])
          apply simp
         apply (rule corres_drop_cutMon)
         apply (rule corres_underlying_gets_pre_lhs)+
         apply (rule monadic_rewrite_corres2)
          apply (rule monadic_rewrite_bindE_head)
          apply (rule monadic_trancl_preemptible_return)
         apply simp
         apply (rule corres_trivial, simp add: returnOk_liftE)
        apply (rule_tac F="cap \<noteq> cap.NullCap" in corres_gen_asm2)
        apply (rule corres_cutMon)
        apply (simp add: cutMon_walk_bind del: fst_conv)
        apply (rule corres_drop_cutMon_bind)
        apply (rule corres_split [OF _ is_final_cap_corres[OF refl]])
           apply (rule corres_cutMon)
           apply (simp add: cutMon_walk_bind del: fst_conv)
           apply (rule corres_drop_cutMon_bind)
           apply (rule corres_split[OF _ dcorres_finalise_cap[where slot=slot]])
              apply (rename_tac fin fin')
              apply (rule corres_cutMon)
              apply (simp(no_asm) add: cutMon_walk_if)
              apply (rule corres_underlying_gets_pre_lhs)
              apply (rename_tac remove)
              apply (rule_tac P="\<lambda>s. remove = CSpace_D.cap_removeable (fst fin) (transform_cslot_ptr slot) s"
                         and P'="cte_wp_at (op = cap) slot and invs and valid_etcbs and valid_cap (fst fin')"
                         and F="CSpace_A.cap_removeable (fst fin') slot \<longrightarrow> remove"
                              in corres_req2)
               apply (drule use_valid[OF _ finalise_cap_remainder, OF _ TrueI])
               apply (clarsimp simp: removeables)
              apply (rule corres_if_rhs_only)
               apply (rule_tac F=remove in corres_note_assumption, simp)
               apply (simp add: when_def)
               apply (rule monadic_rewrite_corres2)
                apply (rule monadic_rewrite_bind)
                  apply (rule monadic_rewrite_pick_alternative_1)
                 apply (rule monadic_rewrite_bind_tail)
                  apply (rule monadic_rewrite_bindE_head)
                  apply (rule monadic_trancl_preemptible_return)
                 apply wp
               apply simp
               apply (rule corres_underlying_gets_pre_lhs)
               apply (rule corres_drop_cutMon)
               apply (rule corres_trivial, simp add: returnOk_liftE)
              apply (rule corres_if_rhs_only)
               apply simp
               apply (rule corres_drop_cutMon)
               apply (rule monadic_rewrite_corres2)
                apply (rule monadic_rewrite_bind)
                  apply (rule monadic_rewrite_pick_alternative_2)
                 apply (rule monadic_rewrite_bind_tail)
                  apply (rule monadic_trancl_preemptible_return)
                 apply wp
               apply (rule corres_split[OF _ set_cap_corres])
                   apply (rule corres_underlying_gets_pre_lhs)
                   apply (rule corres_trivial, simp add: returnOk_liftE)
                  apply (wp | simp)+
              apply (rule monadic_rewrite_corres2)
               apply (rule monadic_rewrite_bind_head)
               apply (rule monadic_rewrite_pick_alternative_2)
              apply (simp add: cutMon_walk_bind)
              apply (rule corres_drop_cutMon_bind)
              apply (rule corres_split[OF _ set_cap_corres])
                  apply (rule_tac P="dcorres ?r ?P ?P' ?f" in subst)
                   apply (rule_tac f="\<lambda>_. ()" in gets_bind_ign)
                  apply (rule_tac r'="\<lambda>rv rv'. transform_cslot_ptr `
                                            (case fst fin' of cap.Zombie p zb (Suc n) \<Rightarrow>
                                                {(p, replicate (zombie_cte_bits zb) False),
                                                 (p, nat_to_cref (zombie_cte_bits zb) n)} | _ \<Rightarrow> {}) \<subseteq> rv"
                              and P=\<top> and P'="valid_cap (fst fin') and invs and valid_etcbs
                                                 and (\<lambda>s. idle_thread s \<notin> obj_refs (fst fin'))" in corres_split)
                     apply (rule monadic_rewrite_corres2)
                      apply (rule monadic_rewrite_bindE_head)
                      apply (rule monadic_rewrite_trans)
                       apply (rule monadic_trancl_preemptible_steps)
                      apply (rule monadic_rewrite_bindE[OF monadic_rewrite_refl])
                       apply (rule monadic_trancl_preemptible_steps)
                      apply wp
                     apply (rule corres_cutMon)
                     apply (simp add: cutMon_walk_bindE bindE_assoc)
                     apply (rule corres_splitEE)
                        prefer 2
                        apply (rule "2.hyps"[simplified, folded dc_def],
                                   (assumption | simp | rule conjI refl)+)
                        apply (clarsimp simp del: transform_cap_simps
                                           split: cap.split nat.split)
                       apply (rule corres_cutMon)
                       apply (simp add: cutMon_walk_bindE dc_def[symmetric])
                       apply (rule corres_drop_cutMon_bindE)
                       apply (rule corres_splitEE[OF _ finalise_preemption_corres])
                         apply (rule corres_cutMon)
                         apply (rule corres_rel_imp, rule "2.hyps"[simplified, folded dc_def],
                                  (assumption | simp | rule conjI refl)+)
                          apply clarsimp
                          apply blast
                         apply (rename_tac excr excr', case_tac excr, simp_all)[1]
                         apply clarsimp
                         apply blast
                        apply (wp cutMon_validE_R_drop rec_del_invs rec_del_cte_at
                                  rec_del_ReduceZombie_emptyable reduce_zombie_cap_to preemption_point_valid_etcbs preemption_point_inv
                                          | simp add: not_idle_thread_def del: gets_to_return)+
                    apply (clarsimp simp: get_zombie_range_def dom_def
                                   split: cap.split nat.split)

                    apply (frule cte_at_nat_to_cref_zbits[OF _ lessI])
                    apply (frule cte_at_replicate_zbits)
                    apply (clarsimp simp: cte_wp_at_caps_of_state caps_of_state_transform_opt_cap)
                    apply (clarsimp simp: transform_cslot_ptr_def)
                   apply (wp | simp)+
              apply (simp add: conj_ac)
              apply (wp replace_cap_invs final_cap_same_objrefs set_cap_cte_wp_at
                        hoare_vcg_const_Ball_lift set_cap_cte_cap_wp_to static_imp_wp
                          | erule finalise_cap_not_reply_master[simplified in_monad, simplified]
                          | simp only: not_idle_thread_def pred_conj_def simp_thms)+
           apply (rule hoare_strengthen_post)
            apply (rule_tac Q="\<lambda>fin s. invs s \<and> replaceable s slot (fst fin) cap
                                      \<and> valid_pdpt_objs s
                                      \<and> valid_etcbs s
                                      \<and> cte_wp_at (op = cap) slot s \<and> s \<turnstile> fst fin
                                      \<and> emptyable slot s \<and> fst slot \<noteq> idle_thread s
                                      \<and> (\<forall>t\<in>obj_refs (fst fin). halted_if_tcb t s)"
                       in hoare_vcg_conj_lift)
             apply (wp finalise_cap_invs[where slot=slot]
                       finalise_cap_replaceable
                       finalise_cap_makes_halted[where slot=slot]
                       hoare_vcg_disj_lift hoare_vcg_ex_lift)[1]
            apply (rule finalise_cap_cases[where slot=slot])
           apply clarsimp
           apply (frule if_unsafe_then_capD, clarsimp+)
           apply (clarsimp simp: cte_wp_at_caps_of_state)
           apply (frule valid_global_refsD2, clarsimp+)
           apply (erule disjE[where P="c = cap.NullCap \<and> P", standard])
            apply clarsimp
           apply (clarsimp simp: conj_ac invs_valid_idle global_refs_def cap_range_def
                          dest!: is_cap_simps' [THEN iffD1])
           apply (frule trans [OF _ appropriate_Zombie, OF sym])
           apply (case_tac cap,
                  simp_all add: fst_cte_ptrs_def is_cap_simps is_final_cap'_def)[1]
          apply assumption
         apply (wp get_cap_wp | simp add: is_final_cap_def)+
    apply (auto simp: not_idle_thread_def cte_wp_at_caps_of_state
                elim: caps_of_state_valid_cap)
    done
next
  case (3 ptr bits n slot s S)
  show ?case
    using "3.prems"
    apply (subst rec_del.simps)
    apply (clarsimp simp: assertE_assert liftE_bindE assert_def
                          corres_free_fail cutMon_fail)
    apply (case_tac "ptr = idle_thread s \<or> fst slot = idle_thread s")
     apply (clarsimp simp: cutMon_def corres_underlying_def fail_def)
     apply (clarsimp simp: cte_wp_at_caps_of_state
                    dest!: zombie_cap_two_nonidles)
    apply (rule corres_drop_cutMon)
    apply (simp add: liftME_def[symmetric] liftE_bindE[symmetric])
    apply (rule stronger_corres_guard_imp)
      apply (rule monadic_rewrite_corres2)
       apply (rule monadic_trancl_preemptible_f)
      apply (simp add: finalise_slot_inner2_def[unfolded split_def])
      apply (rule corres_alternate1, rule corres_alternate1, rule corres_alternate2)
      apply simp
      apply (rule_tac x="(?p, ?p')" in select_pick_corres)
      apply (simp add: liftM_def[symmetric] o_def dc_def[symmetric])
      apply (rule swap_for_delete_corres)
     apply (clarsimp simp: cte_wp_at_caps_of_state)
     apply (frule(1) caps_of_state_valid, drule cte_at_replicate_zbits)
     apply (clarsimp simp: cte_wp_at_caps_of_state transform_cslot_ptr_inj)
    apply (clarsimp simp: cte_wp_at_caps_of_state)
    apply (auto simp: not_idle_thread_def dest: zombie_cap_two_nonidles)
    done
next
  case (4 ptr bits n slot s S)
  show ?case
    using "4.prems"
    apply (subst rec_del.simps)
    apply simp
    apply (rule stronger_corres_guard_imp)
      apply (simp add: cutMon_walk_bindE)
      apply (rule monadic_rewrite_corres2)
       apply (rule monadic_trancl_preemptible_steps)
      apply (rule corres_splitEE[OF _ "4.hyps"[simplified, folded dc_def]])
          apply (rule corres_drop_cutMon)
          apply (simp add: liftE_bindE)
          apply (rule corres_symb_exec_r)
             apply (simp add: liftME_def[symmetric] split del: split_if)
             apply (rule monadic_rewrite_corres2)
              apply (rule monadic_trancl_preemptible_return)
             apply (rule corres_if_rhs_only)
              apply (simp add: returnOk_liftE)
              apply (rule corres_add_noop_lhs,
                     simp only: liftM_def[symmetric] corres_liftM_simp)
              apply (simp add: o_def dc_def[symmetric])
              apply (rule set_cap_noop_dcorres3)
             apply (simp add: assertE_assert liftE_def)
             apply (rule corres_assert_rhs)
             apply (rule corres_trivial, simp add: returnOk_def)
            apply (rule hoare_strengthen_post, rule get_cap_cte_wp_at)
            apply (clarsimp simp: cte_wp_at_caps_of_state arch_page_vmpage_size_def)
           apply (wp | simp)+
         apply (simp add: in_monad)
        apply simp
       apply (wp cutMon_validE_R_drop)
     apply clarsimp
    apply (clarsimp simp: cte_wp_at_caps_of_state halted_emptyable)
    apply (frule valid_global_refsD2, clarsimp+)
    apply (frule(1) caps_of_state_valid,
           drule_tac m=n in cte_at_nat_to_cref_zbits)
     apply simp
    apply (auto simp: cte_wp_at_caps_of_state not_idle_thread_def
                      global_refs_def cap_range_def
                elim: zombie_is_cap_toE[OF caps_of_state_cteD])
    done
qed

lemma dcorres_finalise_slot:
  "dcorres (dc \<oplus> dc) \<top> (invs and cte_at slot and valid_etcbs and valid_pdpt_objs and emptyable slot
                            and not_idle_thread (fst slot))
    (CSpace_D.finalise_slot (transform_cslot_ptr slot))
    (rec_del (FinaliseSlotCall slot True))"
  apply (rule corres_use_cutMon)
  apply (cut_tac b="\<lambda>_. returnOk ()" and d="\<lambda>_. returnOk ()" and r=dc
                and args3="FinaliseSlotCall slot True"
                and S3="({(transform_cslot_ptr slot, False)}, {})" and s3=s
            in corres_splitEE[rotated, OF dcorres_rec_del wp_post_tautE wp_post_tautE])
      apply (simp_all add: bindE_assoc CSpace_D.finalise_slot_def split_def)
   apply (simp_all add: liftME_def[symmetric])
  apply (simp add: returnOk_def)
  done

end

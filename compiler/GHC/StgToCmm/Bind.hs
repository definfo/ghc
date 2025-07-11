-----------------------------------------------------------------------------
--
-- Stg to C-- code generation: bindings
--
-- (c) The University of Glasgow 2004-2006
--
-----------------------------------------------------------------------------

module GHC.StgToCmm.Bind (
        cgTopRhsClosure,
        cgBind,
        emitBlackHoleCode,
        pushUpdateFrame, emitUpdateFrame
  ) where

import GHC.Prelude hiding ((<*>))

import GHC.Core          ( AltCon(..) )
import GHC.Core.Opt.Arity( isOneShotBndr )
import GHC.Runtime.Heap.Layout
import GHC.Unit.Module

import GHC.Stg.Syntax

import GHC.Platform
import GHC.Platform.Profile

import GHC.Builtin.Names (unpackCStringName, unpackCStringUtf8Name)

import GHC.StgToCmm.Config
import GHC.StgToCmm.Expr
import GHC.StgToCmm.Monad
import GHC.StgToCmm.Env
import GHC.StgToCmm.DataCon
import GHC.StgToCmm.Heap
import GHC.StgToCmm.Prof (ldvEnterClosure, enterCostCentreFun, enterCostCentreThunk,
                   initUpdFrameProf)
import GHC.StgToCmm.TagCheck
import GHC.StgToCmm.Ticky
import GHC.StgToCmm.Layout
import GHC.StgToCmm.Utils
import GHC.StgToCmm.Closure
import GHC.StgToCmm.Foreign    (emitPrimCall)

import GHC.Cmm.Graph
import GHC.Cmm.BlockId
import GHC.Cmm
import GHC.Cmm.Info
import GHC.Cmm.Utils
import GHC.Cmm.CLabel

import GHC.Stg.Utils
import GHC.Types.CostCentre
import GHC.Types.Id
import GHC.Types.Id.Info
import GHC.Types.Name
import GHC.Types.Var.Set
import GHC.Types.Basic
import GHC.Types.Tickish ( tickishIsCode )

import GHC.Utils.Misc
import GHC.Utils.Outputable
import GHC.Utils.Panic

import GHC.Data.FastString
import GHC.Data.List.SetOps

import Control.Monad

------------------------------------------------------------------------
--              Top-level bindings
------------------------------------------------------------------------

-- For closures bound at top level, allocate in static space.
-- They should have no free variables.

cgTopRhsClosure :: Platform
                -> RecFlag              -- member of a recursive group?
                -> Id
                -> CostCentreStack      -- Optional cost centre annotation
                -> UpdateFlag
                -> [Id]                 -- Args
                -> CgStgExpr
                -> (CgIdInfo, FCode ())

cgTopRhsClosure platform rec id ccs upd_flag args body =
  let closure_label = mkClosureLabel (idName id) (idCafInfo id)
      cg_id_info    = litIdInfo platform id lf_info (CmmLabel closure_label)
      lf_info       = mkClosureLFInfo platform id TopLevel [] upd_flag args
  in (cg_id_info, gen_code lf_info closure_label)
  where

  gen_code :: LambdaFormInfo -> CLabel -> FCode ()

  -- special case for a indirection (f = g).  We create an IND_STATIC
  -- closure pointing directly to the indirectee.  This is exactly
  -- what the CAF will eventually evaluate to anyway, we're just
  -- shortcutting the whole process, and generating a lot less code
  -- (#7308). Eventually the IND_STATIC closure will be eliminated
  -- by assembly '.equiv' directives, where possible (#15155).
  -- See Note [emit-time elimination of static indirections] in "GHC.Cmm.CLabel".
  --
  -- Note: we omit the optimisation when this binding is part of a
  -- recursive group, because the optimisation would inhibit the black
  -- hole detection from working in that case.  Test
  -- concurrent/should_run/4030 fails, for instance.
  --
  gen_code _ closure_label
    | StgApp f [] <- body
    , null args
    , isNonRec rec
    = do
         cg_info <- getCgIdInfo f
         emitDataCon closure_label indStaticInfoTable ccs [unLit (idInfoToAmode cg_info)]

  -- Emit standard stg_unpack_cstring closures for top-level unpackCString# thunks.
  --
  -- Note that we do not do this for thunks enclosured in code ticks (e.g. hpc
  -- ticks) since we want to ensure that these ticks are not lost (e.g.
  -- resulting in Strings being reported by hpc as uncovered). However, we
  -- don't worry about standard profiling ticks since unpackCString tends not
  -- be terribly interesting in profiles. See Note [unpack_cstring closures] in
  -- StgStdThunks.cmm.
  gen_code _ closure_label
    | null args
    , StgApp f [arg] <- stripStgTicksTopE (not . tickishIsCode) body
    , Just unpack <- is_string_unpack_op f
    = do arg' <- getArgAmode (NonVoid arg)
         case arg' of
           CmmLit lit -> do
             let info = CmmInfoTable
                   { cit_lbl = unpack
                   , cit_rep = HeapRep True 0 1 Thunk
                   , cit_prof = NoProfilingInfo
                   , cit_srt = Nothing
                   , cit_clo = Nothing
                   }
             emitDecl $ CmmData (Section Data closure_label) $
                 CmmStatics closure_label info ccs [] [lit]
           _ -> panic "cgTopRhsClosure.gen_code"
    where
      is_string_unpack_op f
        | idName f == unpackCStringName     = Just mkRtsUnpackCStringLabel
        | idName f == unpackCStringUtf8Name = Just mkRtsUnpackCStringUtf8Label
        | otherwise                         = Nothing

  gen_code lf_info _closure_label
   = do { profile <- getProfile
        ; let name = idName id
        ; mod_name <- getModuleName
        ; let descr         = closureDescription mod_name name
              closure_info  = mkClosureInfo profile True id lf_info 0 0 descr

        -- We don't generate the static closure here, because we might
        -- want to add references to static closures to it later.  The
        -- static closure is generated by GHC.Cmm.Info.Build.updInfoSRTs,
        -- See Note [SRTs], specifically the [FUN] optimisation.

        ; let fv_details :: [(NonVoid Id, ByteOff)]
              header = if isLFThunk lf_info then ThunkHeader else StdHeader
              (_, _, fv_details) = mkVirtHeapOffsets profile header []
        -- Don't drop the non-void args until the closure info has been made
        ; forkClosureBody (closureCodeBody True id closure_info ccs
                                args body fv_details)

        ; return () }

  unLit (CmmLit l) = l
  unLit _ = panic "unLit"

------------------------------------------------------------------------
--              Non-top-level bindings
------------------------------------------------------------------------

cgBind :: CgStgBinding -> FCode ()
cgBind (StgNonRec name rhs)
  = do  { (info, fcode) <- cgRhs name rhs
        ; addBindC info
        ; init <- fcode
        ; emit init }
        -- init cannot be used in body, so slightly better to sink it eagerly

cgBind (StgRec pairs)
  = do  {  r <- sequence $ unzipWith cgRhs pairs
        ;  let (id_infos, fcodes) = unzip r
        ;  addBindsC id_infos
        ;  (inits, body) <- getCodeR $ sequence fcodes
        ;  emit (catAGraphs inits <*> body) }

{- Note [cgBind rec]
   ~~~~~~~~~~~~~~~~~
   Recursive let-bindings are tricky.
   Consider the following pseudocode:

     let x = \_ ->  ... y ...
         y = \_ ->  ... z ...
         z = \_ ->  ... x ...
     in ...

   For each binding, we need to allocate a closure, and each closure must
   capture the address of the other closures.
   We want to generate the following C-- code:
     // Initialization Code
     x = hp - 24; // heap address of x's closure
     y = hp - 40; // heap address of x's closure
     z = hp - 64; // heap address of x's closure
     // allocate and initialize x
     m[hp-8]   = ...
     m[hp-16]  = y       // the closure for x captures y
     m[hp-24] = x_info;
     // allocate and initialize y
     m[hp-32] = z;       // the closure for y captures z
     m[hp-40] = y_info;
     // allocate and initialize z
     ...

   For each closure, we must generate not only the code to allocate and
   initialize the closure itself, but also some initialization Code that
   sets a variable holding the closure pointer.

   We could generate a pair of the (init code, body code), but since
   the bindings are recursive we also have to initialise the
   environment with the CgIdInfo for all the bindings before compiling
   anything.  So we do this in 3 stages:

     1. collect all the CgIdInfos and initialise the environment
     2. compile each binding into (init, body) code
     3. emit all the inits, and then all the bodies

   We'd rather not have separate functions to do steps 1 and 2 for
   each binding, since in practice they share a lot of code.  So we
   have just one function, cgRhs, that returns a pair of the CgIdInfo
   for step 1, and a monadic computation to generate the code in step
   2.

   The alternative to separating things in this way is to use a
   fixpoint.  That's what we used to do, but it introduces a
   maintenance nightmare because there is a subtle dependency on not
   being too strict everywhere.  Doing things this way means that the
   FCode monad can be strict, for example.
 -}

cgRhs :: Id
      -> CgStgRhs
      -> FCode (
                 CgIdInfo         -- The info for this binding
               , FCode CmmAGraph  -- A computation which will generate the
                                  -- code for the binding, and return an
                                  -- assignment of the form "x = Hp - n"
                                  -- (see above)
               )

cgRhs id (StgRhsCon cc con mn _ts args _typ)
  = withNewTickyCounterCon id con mn $
    buildDynCon id mn True cc con (assertNonVoidStgArgs args)
      -- con args are always non-void,
      -- see Note [Post-unarisation invariants] in GHC.Stg.Unarise

{- See Note [GC recovery] in "GHC.StgToCmm.Closure" -}
cgRhs id (StgRhsClosure fvs cc upd_flag args body _typ)
  = do
    profile <- getProfile
    check_tags <- stgToCmmDoTagCheck <$> getStgToCmmConfig
    use_std_ap_thunk <- stgToCmmTickyAP <$> getStgToCmmConfig
    mkRhsClosure profile use_std_ap_thunk check_tags id cc (nonVoidIds (dVarSetElems fvs)) upd_flag args body

------------------------------------------------------------------------
--              Non-constructor right hand sides
------------------------------------------------------------------------

mkRhsClosure :: Profile
             -> Bool                            -- Omit AP Thunks to improve profiling
             -> Bool                            -- Lint tag inference checks
             -> Id -> CostCentreStack
             -> [NonVoid Id]                    -- Free vars
             -> UpdateFlag
             -> [Id]                            -- Args
             -> CgStgExpr
             -> FCode (CgIdInfo, FCode CmmAGraph)

{- mkRhsClosure looks for two special forms of the right-hand side:
        a) selector thunks
        b) AP thunks

If neither happens, it just calls mkClosureLFInfo.  You might think
that mkClosureLFInfo should do all this, but it seems wrong for the
latter to look at the structure of an expression

Note [Selectors]
~~~~~~~~~~~~~~~~
We look at the body of the closure to see if it's a selector---turgid,
but nothing deep.  We are looking for a closure of {\em exactly} the
form:

...  = [the_fv] \ u [] ->
         case the_fv of
           con a_1 ... a_n -> a_i

Note [Ap thunks]
~~~~~~~~~~~~~~~~
A more generic AP thunk of the form

        x = [ x_1...x_n ] \.. [] -> x_1 ... x_n

A set of these is compiled statically into the RTS, so we just use
those.  We could extend the idea to thunks where some of the x_i are
global ids (and hence not free variables), but this would entail
generating a larger thunk.  It might be an option for non-optimising
compilation, though.

We only generate an Ap thunk if all the free variables are pointers,
for semi-obvious reasons.

-}

---------- See Note [Selectors] ------------------
mkRhsClosure    profile _ _check_tags bndr _cc
                [NonVoid the_fv]                -- Just one free var
                upd_flag                -- Updatable thunk
                []                      -- A thunk
                expr
  | let strip = stripStgTicksTopE (not . tickishIsCode)
  , StgCase (StgApp scrutinee [{-no args-}])
         _   -- ignore bndr
         (AlgAlt _)
         [GenStgAlt{ alt_con   = DataAlt _
                   , alt_bndrs = params
                   , alt_rhs   = sel_expr}] <- strip expr
  , StgApp selectee [{-no args-}] <- strip sel_expr
  , the_fv == scrutinee                -- Scrutinee is the only free variable

  , let (_, _, params_w_offsets) = mkVirtConstrOffsets profile (addIdReps (assertNonVoidIds params))
                                   -- pattern binders are always non-void,
                                   -- see Note [Post-unarisation invariants] in GHC.Stg.Unarise
  , Just the_offset <- assocMaybe params_w_offsets (NonVoid selectee)

  , let offset_into_int = bytesToWordsRoundUp (profilePlatform profile) the_offset
                          - fixedHdrSizeW profile
  , offset_into_int <= pc_MAX_SPEC_SELECTEE_SIZE (profileConstants profile) -- Offset is small enough
  = -- NOT TRUE: assert (is_single_constructor)
    -- The simplifier may have statically determined that the single alternative
    -- is the only possible case and eliminated the others, even if there are
    -- other constructors in the datatype.  It's still ok to make a selector
    -- thunk in this case, because we *know* which constructor the scrutinee
    -- will evaluate to.
    --
    -- srt is discarded; it must be empty
    let lf_info = mkSelectorLFInfo bndr offset_into_int (isUpdatable upd_flag)
    in cgRhsStdThunk bndr lf_info [StgVarArg the_fv]

---------- See Note [Ap thunks] ------------------
mkRhsClosure    profile use_std_ap check_tags bndr _cc
                fvs
                upd_flag
                []                      -- No args; a thunk
                (StgApp fun_id args)

  -- We are looking for an "ApThunk"; see data con ApThunk in GHC.StgToCmm.Closure
  -- of form (x1 x2 .... xn), where all the xi are locals (not top-level)
  -- So the xi will all be free variables
  | use_std_ap
  , args `lengthIs` (n_fvs-1)  -- This happens only if the fun_id and
                               -- args are all distinct local variables
                               -- The "-1" is for fun_id
    -- Missed opportunity:   (f x x) is not detected
  , all (isGcPtrRep . idPrimRep . fromNonVoid) fvs
  , isUpdatable upd_flag
  , n_fvs <= pc_MAX_SPEC_AP_SIZE (profileConstants profile)
  , not (profileIsProfiling profile)
                         -- not when profiling: we don't want to
                         -- lose information about this particular
                         -- thunk (e.g. its type) (#949)
  , idArity fun_id == unknownArity -- don't spoil a known call
          -- Ha! an Ap thunk
  , not check_tags -- See Note [Tag inference debugging]
  = cgRhsStdThunk bndr lf_info payload

  where
    n_fvs   = length fvs
    lf_info = mkApLFInfo bndr upd_flag n_fvs
    -- the payload has to be in the correct order, hence we can't
    -- just use the fvs.
    payload = StgVarArg fun_id : args

---------- Default case ------------------
mkRhsClosure profile _use_ap _check_tags bndr cc fvs upd_flag args body
  = do  { let lf_info = mkClosureLFInfo (profilePlatform profile) bndr NotTopLevel fvs upd_flag args
        ; (id_info, reg) <- rhsIdInfo bndr lf_info
        ; return (id_info, gen_code lf_info reg) }
 where
 gen_code lf_info reg
  = do  {       -- LAY OUT THE OBJECT
        -- If the binder is itself a free variable, then don't store
        -- it in the closure.  Instead, just bind it to Node on entry.
        -- NB we can be sure that Node will point to it, because we
        -- haven't told mkClosureLFInfo about this; so if the binder
        -- _was_ a free var of its RHS, mkClosureLFInfo thinks it *is*
        -- stored in the closure itself, so it will make sure that
        -- Node points to it...
        ; let   reduced_fvs = filter (NonVoid bndr /=) fvs

        ; profile <- getProfile
        ; let platform = profilePlatform profile

        -- MAKE CLOSURE INFO FOR THIS CLOSURE
        ; mod_name <- getModuleName
        ; let   name  = idName bndr
                descr = closureDescription mod_name name
                fv_details :: [(NonVoid Id, ByteOff)]
                header = if isLFThunk lf_info then ThunkHeader else StdHeader
                (tot_wds, ptr_wds, fv_details)
                   = mkVirtHeapOffsets profile header (addIdReps reduced_fvs)
                closure_info = mkClosureInfo profile False       -- Not static
                                             bndr lf_info tot_wds ptr_wds
                                             descr

        -- BUILD ITS INFO TABLE AND CODE
        ; forkClosureBody $
                -- forkClosureBody: (a) ensure that bindings in here are not seen elsewhere
                --                  (b) ignore Sequel from context; use empty Sequel
                -- And compile the body
                closureCodeBody False bndr closure_info cc args
                                body fv_details

        -- BUILD THE OBJECT
--      ; (use_cc, blame_cc) <- chooseDynCostCentres cc args body
        ; let use_cc = cccsExpr platform; blame_cc = cccsExpr platform
        ; emit (mkComment $ mkFastString "calling allocDynClosure")
        ; let toVarArg (NonVoid a, off) = (NonVoid (StgVarArg a), off)
        ; let info_tbl = mkCmmInfo closure_info bndr currentCCS
        ; hp_plus_n <- allocDynClosure (Just bndr) info_tbl lf_info use_cc blame_cc
                                         (map toVarArg fv_details)

        -- RETURN
        ; return (mkRhsInit platform reg lf_info hp_plus_n) }

-------------------------
cgRhsStdThunk
        :: Id
        -> LambdaFormInfo
        -> [StgArg]             -- payload
        -> FCode (CgIdInfo, FCode CmmAGraph)

cgRhsStdThunk bndr lf_info payload
 = do  { (id_info, reg) <- rhsIdInfo bndr lf_info
       ; return (id_info, gen_code reg)
       }
 where
 gen_code reg  -- AHA!  A STANDARD-FORM THUNK
  = withNewTickyCounterStdThunk (lfUpdatable lf_info) (bndr) payload $
    do
  {     -- LAY OUT THE OBJECT
    mod_name <- getModuleName
  ; profile  <- getProfile
  ; platform <- getPlatform
  ; let
        header = if isLFThunk lf_info then ThunkHeader else StdHeader
        (tot_wds, ptr_wds, payload_w_offsets)
            = mkVirtHeapOffsets profile header
                (addArgReps (nonVoidStgArgs payload))

        descr = closureDescription mod_name (idName bndr)
        closure_info = mkClosureInfo profile False       -- Not static
                                     bndr lf_info tot_wds ptr_wds
                                     descr

--  ; (use_cc, blame_cc) <- chooseDynCostCentres cc [{- no args-}] body
  ; let use_cc = cccsExpr platform; blame_cc = cccsExpr platform


        -- BUILD THE OBJECT
  ; let info_tbl = mkCmmInfo closure_info bndr currentCCS
  ; hp_plus_n <- allocDynClosure (Just bndr) info_tbl lf_info
                                   use_cc blame_cc payload_w_offsets

        -- RETURN
  ; return (mkRhsInit platform reg lf_info hp_plus_n) }


mkClosureLFInfo :: Platform
                -> Id           -- The binder
                -> TopLevelFlag -- True of top level
                -> [NonVoid Id] -- Free vars
                -> UpdateFlag   -- Update flag
                -> [Id]         -- Args
                -> LambdaFormInfo
mkClosureLFInfo platform bndr top fvs upd_flag args
  | null args =
        mkLFThunk (idType bndr) top (map fromNonVoid fvs) upd_flag
  | otherwise =
        mkLFReEntrant top (map fromNonVoid fvs) args (mkArgDescr platform args)


------------------------------------------------------------------------
--              The code for closures
------------------------------------------------------------------------

closureCodeBody :: Bool            -- whether this is a top-level binding
                -> Id              -- the closure's name
                -> ClosureInfo     -- Lots of information about this closure
                -> CostCentreStack -- Optional cost centre attached to closure
                -> [Id]            -- incoming args to the closure
                -> CgStgExpr
                -> [(NonVoid Id, ByteOff)] -- the closure's free vars
                -> FCode ()

{- There are two main cases for the code for closures.

* If there are *no arguments*, then the closure is a thunk, and not in
  normal form. So it should set up an update frame (if it is
  shared). NB: Thunks cannot have a primitive type!

* If there is *at least one* argument, then this closure is in
  normal form, so there is no need to set up an update frame.
-}

-- No args i.e. thunk
closureCodeBody top_lvl bndr cl_info cc [] body fv_details
  = withNewTickyCounterThunk
        (isStaticClosure cl_info)
        (closureUpdReqd cl_info)
        (closureName cl_info)
        (map fst fv_details) $
    emitClosureProcAndInfoTable top_lvl bndr lf_info info_tbl [] $
      \(_, node, _) -> thunkCode cl_info fv_details cc node body
   where
     lf_info  = closureLFInfo cl_info
     info_tbl = mkCmmInfo cl_info bndr cc

-- Functions
closureCodeBody top_lvl bndr cl_info cc args@(arg0:_) body fv_details
  = let nv_args = nonVoidIds args
        arity = length args
    in
    -- See Note [OneShotInfo overview] in GHC.Types.Basic.
    withNewTickyCounterFun (isOneShotBndr arg0) (closureName cl_info) (map fst fv_details)
        nv_args $ do {

        ; let
             lf_info  = closureLFInfo cl_info
             info_tbl = mkCmmInfo cl_info bndr cc

        -- Emit the main entry code
        ; emitClosureProcAndInfoTable top_lvl bndr lf_info info_tbl nv_args $
            \(_offset, node, arg_regs) -> do
                -- Emit slow-entry code (for entering a closure through a PAP)
                { mkSlowEntryCode bndr cl_info arg_regs
                ; profile <- getProfile
                ; platform <- getPlatform
                ; let node_points = nodeMustPointToIt profile lf_info
                      node' = if node_points then Just node else Nothing
                ; loop_header_id <- newBlockId
                -- Extend reader monad with information that
                -- self-recursive tail calls can be optimized into local
                -- jumps. See Note [Self-recursive tail calls] in GHC.StgToCmm.Expr.
                ; let !self_loop_info = MkSelfLoopInfo
                        { sli_id = bndr
                        , sli_arity = arity
                        , sli_header_block = loop_header_id
                        , sli_registers = arg_regs
                        }
                ; withSelfLoop self_loop_info $ do
                {
                -- Main payload
                ; entryHeapCheck cl_info node' arity arg_regs $ do
                { -- emit LDV code when profiling
                  when node_points (ldvEnterClosure cl_info (CmmLocal node))
                -- ticky after heap check to avoid double counting
                ; tickyEnterFun cl_info
                ; enterCostCentreFun cc
                    (CmmMachOp (mo_wordSub platform)
                         [ CmmReg (CmmLocal node) -- See [NodeReg clobbered with loopification]
                         , mkIntExpr platform (funTag platform cl_info) ])
                ; fv_bindings <- mapM bind_fv fv_details
                -- Load free vars out of closure *after*
                -- heap check, to reduce live vars over check
                ; when node_points $ load_fvs node lf_info fv_bindings
                ; checkFunctionArgTags (text "TagCheck failed - Argument to local function:" <> ppr bndr) bndr args
                ; void $ cgExpr body
                }}}

  }

-- Note [NodeReg clobbered with loopification]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Previously we used to pass nodeReg (aka R1) here. With profiling, upon
-- entering a closure, enterFunCCS was called with R1 passed to it. But since R1
-- may get clobbered inside the body of a closure, and since a self-recursive
-- tail call does not restore R1, a subsequent call to enterFunCCS received a
-- possibly bogus value from R1. The solution is to not pass nodeReg (aka R1) to
-- enterFunCCS. Instead, we pass node, the callee-saved temporary that stores
-- the original value of R1. This way R1 may get modified but loopification will
-- not care.

-- A function closure pointer may be tagged, so we
-- must take it into account when accessing the free variables.
bind_fv :: (NonVoid Id, ByteOff) -> FCode (LocalReg, ByteOff)
bind_fv (id, off) = do { reg <- rebindToReg id; return (reg, off) }

load_fvs :: LocalReg -> LambdaFormInfo -> [(LocalReg, ByteOff)] -> FCode ()
load_fvs node lf_info = mapM_ (\ (reg, off) ->
   do platform <- getPlatform
      let tag = lfDynTag platform lf_info
      emit $ mkTaggedObjectLoad platform reg node off tag)

-----------------------------------------
-- The "slow entry" code for a function.  This entry point takes its
-- arguments on the stack.  It loads the arguments into registers
-- according to the calling convention, and jumps to the function's
-- normal entry point.  The function's closure is assumed to be in
-- R1/node.
--
-- The slow entry point is used for unknown calls: eg. stg_PAP_entry

mkSlowEntryCode :: Id -> ClosureInfo -> [LocalReg] -> FCode ()
-- If this function doesn't have a specialised ArgDescr, we need
-- to generate the function's arg bitmap and slow-entry code.
-- Here, we emit the slow-entry code.
mkSlowEntryCode bndr cl_info arg_regs -- function closure is already in `Node'
  | Just (_, ArgGen _) <- closureFunInfo cl_info
  = do cfg       <- getStgToCmmConfig
       upd_frame <- getUpdFrameOff
       let node = idToReg platform (NonVoid bndr)
           profile  = stgToCmmProfile  cfg
           platform = stgToCmmPlatform cfg
           slow_lbl = closureSlowEntryLabel  platform cl_info
           fast_lbl = closureLocalEntryLabel platform cl_info
           -- mkDirectJump does not clobber `Node' containing function closure
           jump = mkJump profile NativeNodeCall
                                (mkLblExpr fast_lbl)
                                (map (CmmReg . CmmLocal) (node : arg_regs))
                                upd_frame
       tscope <- getTickScope
       emitProcWithConvention Slow Nothing slow_lbl
         (node : arg_regs) (jump, tscope)
  | otherwise = return ()

-----------------------------------------
thunkCode :: ClosureInfo -> [(NonVoid Id, ByteOff)] -> CostCentreStack
          -> LocalReg -> CgStgExpr -> FCode ()
thunkCode cl_info fv_details _cc node body
  = do { profile <- getProfile
       ; platform <- getPlatform
       ; let node_points = nodeMustPointToIt profile (closureLFInfo cl_info)
             node'       = if node_points then Just node else Nothing
        ; ldvEnterClosure cl_info (CmmLocal node) -- NB: Node always points when profiling

        -- Heap overflow check
        ; entryHeapCheck cl_info node' 0 [] $ do
        { -- Overwrite with black hole if necessary
          -- but *after* the heap-overflow check
        ; tickyEnterThunk cl_info
        ; when (blackHoleOnEntry cl_info && node_points)
                (blackHoleIt node)

          -- Push update frame
        ; setupUpdate cl_info node $
            -- We only enter cc after setting up update so
            -- that cc of enclosing scope will be recorded
            -- in update frame CAF/DICT functions will be
            -- subsumed by this enclosing cc
            do { enterCostCentreThunk (CmmReg $ nodeReg platform)
               ; let lf_info = closureLFInfo cl_info
               ; fv_bindings <- mapM bind_fv fv_details
               ; load_fvs node lf_info fv_bindings
               ; void $ cgExpr body }}}


------------------------------------------------------------------------
--              Update and black-hole wrappers
------------------------------------------------------------------------

blackHoleIt :: LocalReg -> FCode ()
-- Only called for closures with no args
-- Node points to the closure
blackHoleIt node_reg
  = emitBlackHoleCode (CmmReg (CmmLocal node_reg))

emitBlackHoleCode :: CmmExpr -> FCode ()
emitBlackHoleCode node = do
  cfg <- getStgToCmmConfig
  let profile     = stgToCmmProfile  cfg
      platform    = stgToCmmPlatform cfg
      is_eager_bh = stgToCmmEagerBlackHole cfg

  -- Eager blackholing is normally disabled, but can be turned on with
  -- -feager-blackholing.  When it is on, we replace the info pointer
  -- of the thunk with stg_EAGER_BLACKHOLE_info on entry.

  -- If we wanted to do eager blackholing with slop filling, we'd need
  -- to do it at the *end* of a basic block, otherwise we overwrite
  -- the free variables in the thunk that we still need.  We have a
  -- patch for this from Andy Cheadle, but not incorporated yet. --SDM
  -- [6/2004]
  --
  -- Previously, eager blackholing was enabled when ticky-ticky was
  -- on. But it didn't work, and it wasn't strictly necessary to bring
  -- back minimal ticky-ticky, so now EAGER_BLACKHOLING is
  -- unconditionally disabled. -- krc 1/2007

  -- Note the eager-blackholing check is here rather than in blackHoleOnEntry,
  -- because emitBlackHoleCode is called from GHC.Cmm.Parser.

  let  eager_blackholing =  not (profileIsProfiling profile) && is_eager_bh
             -- Profiling needs slop filling (to support LDV
             -- profiling), so currently eager blackholing doesn't
             -- work with profiling.

  when eager_blackholing $ do
    whenUpdRemSetEnabled $ emitUpdRemSetPushThunk node
    emitAtomicStore platform MemOrderRelease
        (cmmOffsetW platform node (fixedHdrSizeW profile))
        (currentTSOExpr platform)
    -- See Note [Heap memory barriers] in SMP.h.
    emitAtomicStore platform MemOrderRelease
        node
        (CmmReg (CmmGlobal $ GlobalRegUse EagerBlackholeInfo $ bWord platform))

emitAtomicStore :: Platform -> MemoryOrdering -> CmmExpr -> CmmExpr -> FCode ()
emitAtomicStore platform mord addr val =
    emitPrimCall [] (MO_AtomicWrite w mord) [addr, val]
  where
    w = typeWidth $ cmmExprType platform val

setupUpdate :: ClosureInfo -> LocalReg -> FCode () -> FCode ()
        -- Nota Bene: this function does not change Node (even if it's a CAF),
        -- so that the cost centre in the original closure can still be
        -- extracted by a subsequent enterCostCentre
setupUpdate closure_info node body
  | not (lfUpdatable (closureLFInfo closure_info))
  = body

  | not (isStaticClosure closure_info)
  = if not (closureUpdReqd closure_info)
      then do tickyUpdateFrameOmitted; body
      else do
          tickyPushUpdateFrame
          cfg <- getStgToCmmConfig
          let
              bh = blackHoleOnEntry closure_info
                && not (stgToCmmSCCProfiling cfg)
                && stgToCmmEagerBlackHole cfg

              lbl | bh        = mkBHUpdInfoLabel
                  | otherwise = mkUpdInfoLabel

          pushUpdateFrame lbl (CmmReg (CmmLocal node)) body

  | otherwise   -- A static closure
  = do  { tickyUpdateBhCaf closure_info

        ; if closureUpdReqd closure_info
          then do       -- Blackhole the (updatable) CAF:
                { upd_closure <- link_caf node
                ; pushUpdateFrame mkBHUpdInfoLabel upd_closure body }
          else do {tickyUpdateFrameOmitted; body}
    }

-----------------------------------------------------------------------------
-- Setting up update frames

-- Push the update frame on the stack in the Entry area,
-- leaving room for the return address that is already
-- at the old end of the area.
--
pushUpdateFrame :: CLabel -> CmmExpr -> FCode () -> FCode ()
pushUpdateFrame lbl updatee body
  = do
       updfr  <- getUpdFrameOff
       profile <- getProfile
       let
           hdr         = fixedHdrSize profile
           frame       = updfr + hdr + pc_SIZEOF_StgUpdateFrame_NoHdr (profileConstants profile)
       --
       emitUpdateFrame (CmmStackSlot Old frame) lbl updatee
       withUpdFrameOff frame body

emitUpdateFrame :: CmmExpr -> CLabel -> CmmExpr -> FCode ()
emitUpdateFrame frame lbl updatee = do
  profile <- getProfile
  let
           hdr         = fixedHdrSize profile
           off_updatee = hdr + pc_OFFSET_StgUpdateFrame_updatee (platformConstants platform)
           platform    = profilePlatform profile
  --
  emitStore frame (mkLblExpr lbl)
  emitStore (cmmOffset platform frame off_updatee) updatee
  initUpdFrameProf frame

-----------------------------------------------------------------------------
-- Entering a CAF
--
-- See Note [CAF management] in rts/sm/Storage.c

link_caf :: LocalReg           -- pointer to the closure
         -> FCode CmmExpr      -- Returns amode for closure to be updated
-- This function returns the address of the black hole, so it can be
-- updated with the new value when available.
link_caf node = do
  { cfg <- getStgToCmmConfig
        -- Call the RTS function newCAF, returning the newly-allocated
        -- blackhole indirection closure
  ; let newCAF_lbl = mkForeignLabel (fsLit "newCAF") Nothing
                                    ForeignLabelInExternalPackage IsFunction
  ; let profile  = stgToCmmProfile cfg
  ; let platform = profilePlatform profile
  ; bh <- newTemp (bWord platform)
  ; emitRtsCallGen [(bh,AddrHint)] newCAF_lbl
      [ (baseExpr platform,  AddrHint),
        (CmmReg (CmmLocal node), AddrHint) ]
      False

  -- see Note [atomic CAF entry] in rts/sm/Storage.c
  ; updfr  <- getUpdFrameOff
  ; let align_check = stgToCmmAlignCheck cfg
  ; let target      = entryCode platform
                        (closureInfoPtr platform align_check (CmmReg (CmmLocal node)))
  ; emit =<< mkCmmIfThen
      (cmmEqWord platform (CmmReg (CmmLocal bh)) (zeroExpr platform))
        -- re-enter the CAF
       (mkJump profile NativeNodeCall target [] updfr)

  ; return (CmmReg (CmmLocal bh)) }

------------------------------------------------------------------------
--              Profiling
------------------------------------------------------------------------

-- For "global" data constructors the description is simply occurrence
-- name of the data constructor itself.  Otherwise it is determined by
-- @closureDescription@ from the let binding information.

closureDescription
   :: Module            -- Module
   -> Name              -- Id of closure binding
   -> String
        -- Not called for StgRhsCon which have global info tables built in
        -- CgConTbls.hs with a description generated from the data constructor
closureDescription mod_name name
  = showSDocOneLine defaultSDocContext
    (char '<' <> pprFullName mod_name name <> char '>')

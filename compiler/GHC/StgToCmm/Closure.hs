
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FlexibleInstances #-}

-----------------------------------------------------------------------------
--
-- Stg to C-- code generation:
--
-- The types   LambdaFormInfo
--             ClosureInfo
--
-- Nothing monadic in here!
--
-----------------------------------------------------------------------------

module GHC.StgToCmm.Closure (
        DynTag,  tagForCon, isSmallFamily,

        idPrimRep, isVoidRep, isGcPtrRep, addIdReps, addArgReps,
        argPrimRep,

        NonVoid(..), fromNonVoid, nonVoidIds, nonVoidStgArgs,
        assertNonVoidIds, assertNonVoidStgArgs,

        -- * LambdaFormInfo
        LambdaFormInfo,         -- Abstract
        StandardFormInfo,        -- ...ditto...
        mkLFThunk, mkLFReEntrant, mkConLFInfo, mkSelectorLFInfo,
        mkApLFInfo, importedIdLFInfo, mkLFArgument, mkLFLetNoEscape,
        mkLFStringLit,
        lfDynTag,
        isLFThunk, isLFReEntrant, lfUpdatable,

        -- * Used by other modules
        CgLoc(..), CallMethod(..),
        nodeMustPointToIt, isKnownFun, funTag, tagForArity,
        getCallMethod,

        -- * ClosureInfo
        ClosureInfo,
        mkClosureInfo,
        mkCmmInfo,

        -- ** Inspection
        closureLFInfo, closureName,

        -- ** Labels
        -- These just need the info table label
        closureInfoLabel, staticClosureLabel,
        closureSlowEntryLabel, closureLocalEntryLabel,

        -- ** Predicates
        -- These are really just functions on LambdaFormInfo
        closureUpdReqd,
        closureReEntrant, closureFunInfo,
        isToplevClosure,

        blackHoleOnEntry,  -- Needs LambdaFormInfo and SMRep
        isStaticClosure,   -- Needs SMPre

        -- * InfoTables
        mkDataConInfoTable,
        cafBlackHoleInfoTable,
        indStaticInfoTable,
        staticClosureNeedsLink,
        mkClosureInfoTableLabel
    ) where

import GHC.Prelude
import GHC.Platform
import GHC.Platform.Profile

import GHC.Stg.Syntax
import GHC.Runtime.Heap.Layout
import GHC.Cmm
import GHC.Cmm.Utils
import GHC.StgToCmm.Types
import GHC.StgToCmm.Sequel

import GHC.Types.CostCentre
import GHC.Cmm.BlockId
import GHC.Cmm.CLabel
import GHC.Types.Id
import GHC.Types.Id.Info
import GHC.Core.DataCon
import GHC.Types.Name
import GHC.Core.Type
import GHC.Core.TyCo.Rep
import GHC.Tc.Utils.TcType
import GHC.Core.TyCon
import GHC.Types.RepType
import GHC.Types.Basic
import GHC.Utils.Outputable
import GHC.Utils.Panic
import GHC.Utils.Panic.Plain
import GHC.Data.Maybe (isNothing)

import Data.Coerce (coerce)
import qualified Data.ByteString.Char8 as BS8
import GHC.StgToCmm.Config
import GHC.Stg.InferTags.TagSig (isTaggedSig)

-----------------------------------------------------------------------------
--                Data types and synonyms
-----------------------------------------------------------------------------

-- These data types are mostly used by other modules, especially
-- GHC.StgToCmm.Monad, but we define them here because some functions in this
-- module need to have access to them as well

data CgLoc
  = CmmLoc CmmExpr      -- A stable CmmExpr; that is, one not mentioning
                        -- Hp, so that it remains valid across calls

  | LneLoc BlockId [LocalReg]             -- A join point
        -- A join point (= let-no-escape) should only
        -- be tail-called, and in a saturated way.
        -- To tail-call it, assign to these locals,
        -- and branch to the block id

instance OutputableP Platform CgLoc where
   pdoc = pprCgLoc

pprCgLoc :: Platform -> CgLoc -> SDoc
pprCgLoc platform = \case
   CmmLoc e    -> text "cmm" <+> pdoc platform e
   LneLoc b rs -> text "lne" <+> ppr b <+> ppr rs

-- used by ticky profiling
isKnownFun :: LambdaFormInfo -> Bool
isKnownFun LFReEntrant{} = True
isKnownFun LFLetNoEscape = True
isKnownFun _             = False


-------------------------------------
--        Non-void types
-------------------------------------
-- We frequently need the invariant that an Id or a an argument
-- is of a non-void type. This type is a witness to the invariant.

newtype NonVoid a = NonVoid a
  deriving (Eq, Show)

fromNonVoid :: NonVoid a -> a
fromNonVoid (NonVoid a) = a

instance (Outputable a) => Outputable (NonVoid a) where
  ppr (NonVoid a) = ppr a

nonVoidIds :: [Id] -> [NonVoid Id]
nonVoidIds ids = [NonVoid id | id <- ids, not (isZeroBitTy (idType id))]

-- | Used in places where some invariant ensures that all these Ids are
-- non-void; e.g. constructor field binders in case expressions.
-- See Note [Post-unarisation invariants] in "GHC.Stg.Unarise".
assertNonVoidIds :: [Id] -> [NonVoid Id]
assertNonVoidIds ids = assert (not (any (isZeroBitTy . idType) ids)) $
                       coerce ids

nonVoidStgArgs :: [StgArg] -> [NonVoid StgArg]
nonVoidStgArgs args = [NonVoid arg | arg <- args, not (isZeroBitTy (stgArgType arg))]

-- | Used in places where some invariant ensures that all these arguments are
-- non-void; e.g. constructor arguments.
-- See Note [Post-unarisation invariants] in "GHC.Stg.Unarise".
assertNonVoidStgArgs :: [StgArg] -> [NonVoid StgArg]
assertNonVoidStgArgs args = assert (not (any (isZeroBitTy . stgArgType) args)) $
                            coerce args


-----------------------------------------------------------------------------
--                Representations
-----------------------------------------------------------------------------

-- Why are these here?

-- | Assumes that there is precisely one 'PrimRep' of the type. This assumption
-- holds after unarise.
-- See Note [Post-unarisation invariants]
idPrimRep :: Id -> PrimRep
idPrimRep id = typePrimRep1 (idType id)
    -- See also Note [VoidRep] in GHC.Types.RepType

-- | Assumes that Ids have one PrimRep, which holds after unarisation.
-- See Note [Post-unarisation invariants]
addIdReps :: [NonVoid Id] -> [NonVoid (PrimRep, Id)]
addIdReps = map (\id -> let id' = fromNonVoid id
                         in NonVoid (idPrimRep id', id'))

-- | Assumes that arguments have one PrimRep, which holds after unarisation.
-- See Note [Post-unarisation invariants]
addArgReps :: [NonVoid StgArg] -> [NonVoid (PrimRep, StgArg)]
addArgReps = map (\arg -> let arg' = fromNonVoid arg
                           in NonVoid (argPrimRep arg', arg'))

-- | Assumes that the argument has one PrimRep, which holds after unarisation.
-- See Note [Post-unarisation invariants]
argPrimRep :: StgArg -> PrimRep
argPrimRep arg = typePrimRep1 (stgArgType arg)

------------------------------------------------------
--                Building LambdaFormInfo
------------------------------------------------------

mkLFArgument :: Id -> LambdaFormInfo
mkLFArgument id
  | isUnliftedType ty      = LFUnlifted
  | mightBeFunTy ty = LFUnknown True
  | otherwise              = LFUnknown False
  where
    ty = idType id

-------------
mkLFLetNoEscape :: LambdaFormInfo
mkLFLetNoEscape = LFLetNoEscape

-------------
mkLFReEntrant :: TopLevelFlag    -- True of top level
              -> [Id]            -- Free vars
              -> [Id]            -- Args
              -> ArgDescr        -- Argument descriptor
              -> LambdaFormInfo

mkLFReEntrant _ _ [] _
  = pprPanic "mkLFReEntrant" empty
mkLFReEntrant top fvs args arg_descr
  = LFReEntrant top (length args) (null fvs) arg_descr

-------------
mkLFThunk :: Type -> TopLevelFlag -> [Id] -> UpdateFlag -> LambdaFormInfo
mkLFThunk thunk_ty top fvs upd_flag
  = assert (not (isUpdatable upd_flag) || not (isUnliftedType thunk_ty)) $
    LFThunk top (null fvs)
            (isUpdatable upd_flag)
            NonStandardThunk
            (mightBeFunTy thunk_ty)

-------------
mkConLFInfo :: DataCon -> LambdaFormInfo
mkConLFInfo con = LFCon con

-------------
mkSelectorLFInfo :: Id -> Int -> Bool -> LambdaFormInfo
mkSelectorLFInfo id offset updatable
  = LFThunk NotTopLevel False updatable (SelectorThunk offset)
        (mightBeFunTy (idType id))

-------------
mkApLFInfo :: Id -> UpdateFlag -> Arity -> LambdaFormInfo
mkApLFInfo id upd_flag arity
  = LFThunk NotTopLevel (arity == 0) (isUpdatable upd_flag) (ApThunk arity)
        (mightBeFunTy (idType id))

-------------
-- | The 'LambdaFormInfo' of an imported Id.
--   See Note [The LFInfo of Imported Ids]
importedIdLFInfo :: Id -> LambdaFormInfo
importedIdLFInfo id =
    -- See Note [Conveying CAF-info and LFInfo between modules] in
    -- GHC.StgToCmm.Types
    case idLFInfo_maybe id of
      Just lf_info ->
        -- Use the existing LambdaFormInfo
        lf_info
      Nothing
        -- Doesn't have a LambdaFormInfo, but we know it must be 'LFReEntrant' from its arity
        | arity > 0
        -> LFReEntrant TopLevel arity True ArgUnknown

        -- We can't be sure of the LambdaFormInfo of this imported Id,
        -- so make a conservative one from the type.
        | otherwise
        -> assert (isNothing (isDataConId_maybe id)) $ -- See Note [LFInfo of DataCon workers and wrappers] in GHC.Types.Id.Make
           mkLFArgument id -- Not sure of exact arity
  where
    arity = idFunRepArity id

{-
Note [The LFInfo of Imported Ids]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
As explained in Note [Conveying CAF-info and LFInfo between modules]
the LambdaFormInfo records the details of a closure representation and is
often, when optimisations are enabled, serialized to the interface of a module.

In particular, the `lfInfo` field of the `IdInfo` field of an `Id`:
* For DataCon workers and wrappers is populated as described in
Note [LFInfo of DataCon workers and wrappers] in GHC.Types.Id.Make
* For other Ids defined in the module being compiled: is `Nothing`
* For other imported Ids:
  * is (Just lf_info) if the LFInfo was serialised into the interface file
    (typically, when the exporting module was compiled with -O)
  * is Nothing if it wasn't serialised

The LambdaFormInfo we give an Id is used in determining how to tag its pointer
(see `litIdInfo` and `lfDynTag`). Therefore, it's crucial we attribute a correct
LambdaFormInfo to imported Ids, or otherwise risk having pointers incorrectly
tagged which can lead to performance issues and even segmentation faults (see
#23231 and Note [Imported unlifted nullary datacon wrappers must have correct LFInfo]).

In particular, saturated data constructor applications *must* be unambiguously
given `LFCon`, and if the LFInfo says LFCon, then it really is a static data
constructor, and similar for LFReEntrant.

In `importedIdLFInfo`, we construct a LambdaFormInfo for imported Ids as follows:

(1) If the `lfInfo` field contains an LFInfo, we use that LFInfo which is
correct by construction (the invariant being that if it exists, it is correct):
  (1.1) Either it was serialised to the interface we're importing the Id from,
  (1.2) Or it's a DataCon worker or wrapper and its LFInfo was constructed
        according to Note [LFInfo of DataCon workers and wrappers]
(2) When the `lfInfo` field is `Nothing`
  (2.1) If the `idFunRepArity` of the Id is known and is greater than 0, then
  the Id is unambiguously a function and is given `LFReEntrant`, and pointers
  to this Id will be tagged (by `litIdInfo`) with the corresponding arity.
  (2.2) Otherwise, we can make a conservative estimate from the type.

-}

-------------
mkLFStringLit :: LambdaFormInfo
mkLFStringLit = LFUnlifted

-----------------------------------------------------
--                Dynamic pointer tagging
-----------------------------------------------------

type DynTag = Int       -- The tag on a *pointer*
                        -- (from the dynamic-tagging paper)

-- Note [Data constructor dynamic tags]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--
-- The family size of a data type (the number of constructors
-- or the arity of a function) can be either:
--    * small, if the family size < 2**tag_bits
--    * big, otherwise.
--
-- Small families can have the constructor tag in the tag bits.
-- Big families always use the tag values 1..mAX_PTR_TAG to represent
-- evaluatedness, the last one lumping together all overflowing ones.
-- We don't have very many tag bits: for example, we have 2 bits on
-- x86-32 and 3 bits on x86-64.
--
-- Also see Note [Tagging big families] in GHC.StgToCmm.Expr
--
-- The interpreter also needs to be updated if we change the
-- tagging strategy; see tagConstr in rts/Interpreter.c.

isSmallFamily :: Platform -> Int -> Bool
isSmallFamily platform fam_size = fam_size <= mAX_PTR_TAG platform

tagForCon :: Platform -> DataCon -> DynTag
tagForCon platform con = min (dataConTag con) (mAX_PTR_TAG platform)
-- NB: 1-indexed

tagForArity :: Platform -> RepArity -> DynTag
tagForArity platform arity
 | isSmallFamily platform arity = arity
 | otherwise                    = 0

-- | Return the tag in the low order bits of a variable bound
-- to this LambdaForm
lfDynTag :: Platform -> LambdaFormInfo -> DynTag
lfDynTag platform lf = case lf of
   LFCon con               -> tagForCon   platform con
   LFReEntrant _ arity _ _ -> tagForArity platform arity
   _other                  -> 0


-----------------------------------------------------------------------------
--                Observing LambdaFormInfo
-----------------------------------------------------------------------------

------------
isLFThunk :: LambdaFormInfo -> Bool
isLFThunk (LFThunk {})  = True
isLFThunk _ = False

isLFReEntrant :: LambdaFormInfo -> Bool
isLFReEntrant (LFReEntrant {}) = True
isLFReEntrant _                = False

-----------------------------------------------------------------------------
--                Choosing SM reps
-----------------------------------------------------------------------------

lfClosureType :: LambdaFormInfo -> ClosureTypeInfo
lfClosureType (LFReEntrant _ arity _ argd) = Fun arity argd
lfClosureType (LFCon con)                  = Constr (dataConTagZ con)
                                                    (dataConIdentity con)
lfClosureType (LFThunk _ _ _ is_sel _)     = thunkClosureType is_sel
lfClosureType _                            = panic "lfClosureType"

thunkClosureType :: StandardFormInfo -> ClosureTypeInfo
thunkClosureType (SelectorThunk off) = ThunkSelector off
thunkClosureType _                   = Thunk

-- We *do* get non-updatable top-level thunks sometimes.  eg. f = g
-- gets compiled to a jump to g (if g has non-zero arity), instead of
-- messing around with update frames and PAPs.  We set the closure type
-- to FUN_STATIC in this case.

-----------------------------------------------------------------------------
--                nodeMustPointToIt
-----------------------------------------------------------------------------

nodeMustPointToIt :: Profile -> LambdaFormInfo -> Bool
-- If nodeMustPointToIt is true, then the entry convention for
-- this closure has R1 (the "Node" register) pointing to the
-- closure itself --- the "self" argument

nodeMustPointToIt _ (LFReEntrant top _ no_fvs _)
  =  not no_fvs          -- Certainly if it has fvs we need to point to it
  || isNotTopLevel top   -- See Note [GC recovery]
        -- For lex_profiling we also access the cost centre for a
        -- non-inherited (i.e. non-top-level) function.
        -- The isNotTopLevel test above ensures this is ok.

nodeMustPointToIt profile (LFThunk top no_fvs updatable NonStandardThunk _)
  =  not no_fvs            -- Self parameter
  || isNotTopLevel top     -- Note [GC recovery]
  || updatable             -- Need to push update frame
  || profileIsProfiling profile
          -- For the non-updatable (single-entry case):
          --
          -- True if has fvs (in which case we need access to them, and we
          --                    should black-hole it)
          -- or profiling (in which case we need to recover the cost centre
          --                 from inside it)  ToDo: do we need this even for
          --                                    top-level thunks? If not,
          --                                    isNotTopLevel subsumes this

nodeMustPointToIt _ (LFThunk {})        -- Node must point to a standard-form thunk
  = True

nodeMustPointToIt _ (LFCon _) = True

        -- Strictly speaking, the above two don't need Node to point
        -- to it if the arity = 0.  But this is a *really* unlikely
        -- situation.  If we know it's nil (say) and we are entering
        -- it. Eg: let x = [] in x then we will certainly have inlined
        -- x, since nil is a simple atom.  So we gain little by not
        -- having Node point to known zero-arity things.  On the other
        -- hand, we do lose something; Patrick's code for figuring out
        -- when something has been updated but not entered relies on
        -- having Node point to the result of an update.  SLPJ
        -- 27/11/92.

nodeMustPointToIt _ (LFUnknown _)   = True
nodeMustPointToIt _ LFUnlifted      = False
nodeMustPointToIt _ LFLetNoEscape   = False

{- Note [GC recovery]
~~~~~~~~~~~~~~~~~~~~~
If we a have a local let-binding (function or thunk)
   let f = <body> in ...
AND <body> allocates, then the heap-overflow check needs to know how
to re-start the evaluation.  It uses the "self" pointer to do this.
So even if there are no free variables in <body>, we still make
nodeMustPointToIt be True for non-top-level bindings.

Why do any such bindings exist?  After all, let-floating should have
floated them out.  Well, a clever optimiser might leave one there to
avoid a space leak, deliberately recomputing a thunk.  Also (and this
really does happen occasionally) let-floating may make a function f smaller
so it can be inlined, so now (f True) may generate a local no-fv closure.
This actually happened during bootstrapping GHC itself, with f=mkRdrFunBind
in GHC.Tc.Deriv.Generate.) -}

-----------------------------------------------------------------------------
--                getCallMethod
-----------------------------------------------------------------------------

{- The entry conventions depend on the type of closure being entered,
whether or not it has free variables, and whether we're running
sequentially or in parallel.

Closure                           Node   Argument   Enter
Characteristics              Par   Req'd  Passing    Via
---------------------------------------------------------------------------
Unknown                     & no  & yes & stack     & node
Known fun (>1 arg), no fvs  & no  & no  & registers & fast entry (enough args)
                                                    & slow entry (otherwise)
Known fun (>1 arg), fvs     & no  & yes & registers & fast entry (enough args)
0 arg, no fvs \r,\s         & no  & no  & n/a       & direct entry
0 arg, no fvs \u            & no  & yes & n/a       & node
0 arg, fvs \r,\s,selector   & no  & yes & n/a       & node
0 arg, fvs \r,\s            & no  & yes & n/a       & direct entry
0 arg, fvs \u               & no  & yes & n/a       & node
Unknown                     & yes & yes & stack     & node
Known fun (>1 arg), no fvs  & yes & no  & registers & fast entry (enough args)
                                                    & slow entry (otherwise)
Known fun (>1 arg), fvs     & yes & yes & registers & node
0 arg, fvs \r,\s,selector   & yes & yes & n/a       & node
0 arg, no fvs \r,\s         & yes & no  & n/a       & direct entry
0 arg, no fvs \u            & yes & yes & n/a       & node
0 arg, fvs \r,\s            & yes & yes & n/a       & node
0 arg, fvs \u               & yes & yes & n/a       & node

When black-holing, single-entry closures could also be entered via node
(rather than directly) to catch double-entry. -}

data CallMethod
  = EnterIt             -- ^ No args, not a function

  | JumpToIt BlockId [LocalReg] -- A join point or a header of a local loop

  | ReturnIt            -- It's a value (function, unboxed value,
                        -- or constructor), so just return it.

  | InferedReturnIt     -- A properly tagged value, as determined by tag inference.
                        -- See Note [Tag Inference] and Note [Tag inference passes] in
                        -- GHC.Stg.InferTags.
                        -- It behaves /precisely/ like `ReturnIt`, except that when debugging is
                        -- enabled we emit an extra assertion to check that the returned value is
                        -- properly tagged.  We can use this as a check that tag inference is working
                        -- correctly.
                        -- TODO: SPJ suggested we could combine this with EnterIt, but for now I decided
                        -- not to do so.

  | SlowCall            -- Unknown fun, or known fun with
                        -- too few args.

  | DirectEntry         -- Jump directly, with args in regs
        CLabel          --   The code label
        RepArity        --   Its arity

instance Outputable CallMethod where
  ppr (EnterIt) = text "Enter"
  ppr (JumpToIt {}) = text "JumpToIt"
  ppr (ReturnIt ) = text "ReturnIt"
  ppr (InferedReturnIt) = text "InferedReturnIt"
  ppr (SlowCall ) = text "SlowCall"
  ppr (DirectEntry {}) = text "DirectEntry"

getCallMethod :: StgToCmmConfig
              -> Name           -- Function being applied
              -> Id             -- Function Id used to check if it can refer to
                                -- CAF's and whether the function is tail-calling
                                -- itself
              -> LambdaFormInfo -- Its info
              -> RepArity       -- Number of available arguments
                                -- (including void args)
              -> CgLoc          -- Passed in from cgIdApp so that we can
                                -- handle let-no-escape bindings and self-recursive
                                -- tail calls using the same data constructor,
                                -- JumpToIt. This saves us one case branch in
                                -- cgIdApp
              -> Maybe SelfLoopInfo -- can we perform a self-recursive tail-call
              -> CallMethod

getCallMethod cfg _ id _  n_args _cg_loc (Just self_loop)
  | stgToCmmLoopification cfg
  , MkSelfLoopInfo
    { sli_id = loop_id, sli_arity = arity
    , sli_header_block = blk_id, sli_registers = arg_regs
    } <- self_loop
  , id == loop_id
  , n_args == arity
  -- If these patterns match then we know that:
  --   * loopification optimisation is turned on
  --   * function is performing a self-recursive call in a tail position
  --   * number of parameters matches the function's arity.
  -- See Note [Self-recursive tail calls] in GHC.StgToCmm.Expr for more details
  = JumpToIt blk_id arg_regs

getCallMethod cfg name id (LFReEntrant _ arity _ _) n_args _cg_loc _self_loop_info
  | n_args == 0 -- No args at all
  && not (profileIsProfiling (stgToCmmProfile cfg))
     -- See Note [Evaluating functions with profiling] in rts/Apply.cmm
  = assert (arity /= 0) ReturnIt
  | n_args < arity = SlowCall        -- Not enough args
  | otherwise      = DirectEntry (enterIdLabel (stgToCmmPlatform cfg) name (idCafInfo id)) arity

getCallMethod _ _name _ LFUnlifted n_args _cg_loc _self_loop_info
  = assert (n_args == 0) ReturnIt

getCallMethod _ _name _ (LFCon _) n_args _cg_loc _self_loop_info
  = assert (n_args == 0) ReturnIt
    -- n_args=0 because it'd be ill-typed to apply a saturated
    --          constructor application to anything

getCallMethod cfg name id (LFThunk _ _ updatable std_form_info is_fun)
              n_args _cg_loc _self_loop_info

  | Just sig <- idTagSig_maybe id
  , isTaggedSig sig -- Infered to be already evaluated by Tag Inference
  , n_args == 0     -- See Note [Tag Inference]
  = InferedReturnIt

  | is_fun      -- it *might* be a function, so we must "call" it (which is always safe)
  = SlowCall    -- We cannot just enter it [in eval/apply, the entry code
                -- is the fast-entry code]

  -- Since is_fun is False, we are *definitely* looking at a data value
  | updatable || stgToCmmDoTicky cfg -- to catch double entry
      {- OLD: || opt_SMP
         I decided to remove this, because in SMP mode it doesn't matter
         if we enter the same thunk multiple times, so the optimisation
         of jumping directly to the entry code is still valid.  --SDM
        -}
  = EnterIt

  -- even a non-updatable selector thunk can be updated by the garbage
  -- collector, so we must enter it. (#8817)
  | SelectorThunk{} <- std_form_info
  = EnterIt

    -- We used to have assert (n_args == 0 ), but actually it is
    -- possible for the optimiser to generate
    --   let bot :: Int = error Int "urk"
    --   in (bot `cast` unsafeCoerce Int (Int -> Int)) 3
    -- This happens as a result of the case-of-error transformation
    -- So the right thing to do is just to enter the thing

  | otherwise        -- Jump direct to code for single-entry thunks
  = assert (n_args == 0) $
    DirectEntry (thunkEntryLabel (stgToCmmPlatform cfg) name (idCafInfo id) std_form_info
                updatable) 0

-- Imported(Unknown) Ids
getCallMethod cfg name id (LFUnknown might_be_a_function) n_args _cg_locs _self_loop_info
  | n_args == 0
  , Just sig <- idTagSig_maybe id
  , isTaggedSig sig -- Infered to be already evaluated by Tag Inference
  -- When profiling we must enter all potential functions to make sure we update the SCC
  -- even if the function itself is already evaluated.
  -- See Note [Evaluating functions with profiling] in rts/Apply.cmm
  , not (profileIsProfiling (stgToCmmProfile cfg) && might_be_a_function)
  = InferedReturnIt -- See Note [Tag Inference]

  | might_be_a_function = SlowCall

  | otherwise =
      assertPpr ( n_args == 0) ( ppr name <+> ppr n_args )
      EnterIt   -- Not a function

-- TODO: Redundant with above match?
-- getCallMethod _ name _ (LFUnknown False) n_args _cg_loc _self_loop_info
--   = assertPpr (n_args == 0) (ppr name <+> ppr n_args)
--     EnterIt -- Not a function

getCallMethod _ _name _ LFLetNoEscape _n_args (LneLoc blk_id lne_regs) _self_loop_info
  = JumpToIt blk_id lne_regs

getCallMethod _ _ _ _ _ _ _ = panic "Unknown call method"

-----------------------------------------------------------------------------
--              Data types for closure information
-----------------------------------------------------------------------------


{- ClosureInfo: information about a binding

   We make a ClosureInfo for each let binding (both top level and not),
   but not bindings for data constructors: for those we build a CmmInfoTable
   directly (see mkDataConInfoTable).

   To a first approximation:
       ClosureInfo = (LambdaFormInfo, CmmInfoTable)

   A ClosureInfo has enough information
     a) to construct the info table itself, and build other things
        related to the binding (e.g. slow entry points for a function)
     b) to allocate a closure containing that info pointer (i.e.
           it knows the info table label)
-}

data ClosureInfo
  = ClosureInfo {
        closureName :: !Id,           -- The thing bound to this closure
           -- we don't really need this field: it's only used in generating
           -- code for ticky and profiling, and we could pass the information
           -- around separately, but it doesn't do much harm to keep it here.

        closureLFInfo :: !LambdaFormInfo, -- NOTE: not an LFCon
          -- this tells us about what the closure contains: it's right-hand-side.

          -- the rest is just an unpacked CmmInfoTable.
        closureInfoLabel :: !CLabel,
        closureSMRep     :: !SMRep,          -- representation used by storage mgr
        closureProf      :: !ProfilingInfo
    }

-- | Convert from 'ClosureInfo' to 'CmmInfoTable'.
mkCmmInfo :: ClosureInfo -> Id -> CostCentreStack -> CmmInfoTable
mkCmmInfo ClosureInfo {..} id ccs
  = CmmInfoTable { cit_lbl  = closureInfoLabel
                 , cit_rep  = closureSMRep
                 , cit_prof = closureProf
                 , cit_srt  = Nothing
                 , cit_clo  = if isStaticRep closureSMRep
                                then Just (id,ccs)
                                else Nothing }

--------------------------------------
--        Building ClosureInfos
--------------------------------------

mkClosureInfo :: Profile
              -> Bool                -- Is static
              -> Id
              -> LambdaFormInfo
              -> Int -> Int        -- Total and pointer words
              -> String         -- String descriptor
              -> ClosureInfo
mkClosureInfo profile is_static id lf_info tot_wds ptr_wds val_descr
  = ClosureInfo { closureName      = id
                , closureLFInfo    = lf_info
                , closureInfoLabel = info_lbl   -- These three fields are
                , closureSMRep     = sm_rep     -- (almost) an info table
                , closureProf      = prof }     -- (we don't have an SRT yet)
  where
    sm_rep     = mkHeapRep profile is_static ptr_wds nonptr_wds (lfClosureType lf_info)
    prof       = mkProfilingInfo profile id val_descr
    nonptr_wds = tot_wds - ptr_wds

    info_lbl = mkClosureInfoTableLabel (profilePlatform profile) id lf_info

--------------------------------------
--   Other functions over ClosureInfo
--------------------------------------

-- Eager blackholing is normally disabled, but can be turned on with
-- -feager-blackholing.  When it is on, we replace the info pointer of
-- the thunk with stg_EAGER_BLACKHOLE_info on entry.

-- If we wanted to do eager blackholing with slop filling,
-- we'd need to do it at the *end* of a basic block, otherwise
-- we overwrite the free variables in the thunk that we still
-- need.  We have a patch for this from Andy Cheadle, but not
-- incorporated yet. --SDM [6/2004]
--
-- Previously, eager blackholing was enabled when ticky-ticky
-- was on. But it didn't work, and it wasn't strictly necessary
-- to bring back minimal ticky-ticky, so now EAGER_BLACKHOLING
-- is unconditionally disabled. -- krc 1/2007
--
-- Static closures are never themselves black-holed.

blackHoleOnEntry :: ClosureInfo -> Bool
blackHoleOnEntry cl_info
  | isStaticRep (closureSMRep cl_info)
  = False        -- Never black-hole a static closure

  | otherwise
  = case closureLFInfo cl_info of
      LFReEntrant {}            -> False
      LFLetNoEscape             -> False
      LFThunk _ _no_fvs upd _ _ -> upd   -- See Note [Black-holing non-updatable thunks]
      _other -> panic "blackHoleOnEntry"

{- Note [Black-holing non-updatable thunks]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
We must not black-hole non-updatable (single-entry) thunks otherwise
we run into issues like #10414. Specifically:

  * There is no reason to black-hole a non-updatable thunk: it should
    not be competed for by multiple threads

  * It could, conceivably, cause a space leak if we don't black-hole
    it, if there was a live but never-followed pointer pointing to it.
    Let's hope that doesn't happen.

  * It is dangerous to black-hole a non-updatable thunk because
     - is not updated (of course)
     - hence, if it is black-holed and another thread tries to evaluate
       it, that thread will block forever
    This actually happened in #10414.  So we do not black-hole
    non-updatable thunks.

  * How could two threads evaluate the same non-updatable (single-entry)
    thunk?  See Reid Barton's example below.

  * Only eager blackholing could possibly black-hole a non-updatable
    thunk, because lazy black-holing only affects thunks with an
    update frame on the stack.

Here is and example due to Reid Barton (#10414):
    x = \u []  concat [[1], []]
with the following definitions,

    concat x = case x of
        []       -> []
        (:) x xs -> (++) x (concat xs)

    (++) xs ys = case xs of
        []         -> ys
        (:) x rest -> (:) x ((++) rest ys)

Where we use the syntax @\u []@ to denote an updatable thunk and @\s []@ to
denote a single-entry (i.e. non-updatable) thunk. After a thread evaluates @x@
to WHNF and calls @(++)@ the heap will contain the following thunks,

    x = 1 : y
    y = \u []  (++) [] z
    z = \s []  concat []

Now that the stage is set, consider the follow evaluations by two racing threads
A and B,

  1. Both threads enter @y@ before either is able to replace it with an
     indirection

  2. Thread A does the case analysis in @(++)@ and consequently enters @z@,
     replacing it with a black-hole

  3. At some later point thread B does the same case analysis and also attempts
     to enter @z@. However, it finds that it has been replaced with a black-hole
     so it blocks.

  4. Thread A eventually finishes evaluating @z@ (to @[]@) and updates @y@
     accordingly. It does *not* update @z@, however, as it is single-entry. This
     leaves Thread B blocked forever on a black-hole which will never be
     updated.

To avoid this sort of condition we never black-hole non-updatable thunks.
-}

isStaticClosure :: ClosureInfo -> Bool
isStaticClosure cl_info = isStaticRep (closureSMRep cl_info)

closureUpdReqd :: ClosureInfo -> Bool
closureUpdReqd ClosureInfo{ closureLFInfo = lf_info } = lfUpdatable lf_info

lfUpdatable :: LambdaFormInfo -> Bool
lfUpdatable (LFThunk _ _ upd _ _)  = upd
lfUpdatable _ = False

closureReEntrant :: ClosureInfo -> Bool
closureReEntrant (ClosureInfo { closureLFInfo = LFReEntrant {} }) = True
closureReEntrant _ = False

closureFunInfo :: ClosureInfo -> Maybe (RepArity, ArgDescr)
closureFunInfo (ClosureInfo { closureLFInfo = lf_info }) = lfFunInfo lf_info

lfFunInfo :: LambdaFormInfo ->  Maybe (RepArity, ArgDescr)
lfFunInfo (LFReEntrant _ arity _ arg_desc)  = Just (arity, arg_desc)
lfFunInfo _                                 = Nothing

funTag :: Platform -> ClosureInfo -> DynTag
funTag platform (ClosureInfo { closureLFInfo = lf_info })
    = lfDynTag platform lf_info

isToplevClosure :: ClosureInfo -> Bool
isToplevClosure (ClosureInfo { closureLFInfo = lf_info })
  = case lf_info of
      LFReEntrant TopLevel _ _ _ -> True
      LFThunk TopLevel _ _ _ _   -> True
      _other                     -> False

--------------------------------------
--   Label generation
--------------------------------------

staticClosureLabel :: Platform -> ClosureInfo -> CLabel
staticClosureLabel platform = toClosureLbl platform .  closureInfoLabel

closureSlowEntryLabel :: Platform -> ClosureInfo -> CLabel
closureSlowEntryLabel platform = toSlowEntryLbl platform . closureInfoLabel

closureLocalEntryLabel :: Platform -> ClosureInfo -> CLabel
closureLocalEntryLabel platform
  | platformTablesNextToCode platform = toInfoLbl  platform . closureInfoLabel
  | otherwise                         = toEntryLbl platform . closureInfoLabel

-- | Get the info table label for a *thunk*.
mkClosureInfoTableLabel :: Platform -> Id -> LambdaFormInfo -> CLabel
mkClosureInfoTableLabel platform id lf_info
  = case lf_info of
        LFThunk _ _ upd_flag (SelectorThunk offset) _
                      -> mkSelectorInfoLabel platform upd_flag offset

        LFThunk _ _ upd_flag (ApThunk arity) _
                      -> mkApInfoTableLabel platform upd_flag arity

        LFThunk{}     -> mkInfoTableLabel name cafs
        LFReEntrant{} -> mkInfoTableLabel name cafs
        _other        -> panic "closureInfoTableLabel"

  where
    name = idName id

    cafs     = idCafInfo id

-- | thunkEntryLabel is a local help function, not exported.  It's used from
-- getCallMethod.
thunkEntryLabel :: Platform -> Name -> CafInfo -> StandardFormInfo -> Bool -> CLabel
thunkEntryLabel platform thunk_id caf_info sfi upd_flag = case sfi of
   ApThunk arity        -> enterApLabel       platform upd_flag arity
   SelectorThunk offset -> enterSelectorLabel platform upd_flag offset
   _                    -> enterIdLabel       platform thunk_id caf_info

enterApLabel :: Platform -> Bool -> Arity -> CLabel
enterApLabel platform is_updatable arity
  | platformTablesNextToCode platform = mkApInfoTableLabel platform is_updatable arity
  | otherwise                         = mkApEntryLabel     platform is_updatable arity

enterSelectorLabel :: Platform -> Bool -> WordOff -> CLabel
enterSelectorLabel platform upd_flag offset
  | platformTablesNextToCode platform = mkSelectorInfoLabel  platform upd_flag offset
  | otherwise                         = mkSelectorEntryLabel platform upd_flag offset

enterIdLabel :: Platform -> Name -> CafInfo -> CLabel
enterIdLabel platform id c
  | platformTablesNextToCode platform = mkInfoTableLabel id c
  | otherwise                         = mkEntryLabel id c


--------------------------------------
--   Profiling
--------------------------------------

-- Profiling requires two pieces of information to be determined for
-- each closure's info table --- description and type.

-- The description is stored directly in the @CClosureInfoTable@ when the
-- info table is built.

-- The type is determined from the type information stored with the @Id@
-- in the closure info using @closureTypeDescr@.

mkProfilingInfo :: Profile -> Id -> String -> ProfilingInfo
mkProfilingInfo profile id val_descr
  | not (profileIsProfiling profile) = NoProfilingInfo
  | otherwise                        = ProfilingInfo ty_descr_w8 (BS8.pack val_descr)
  where
    ty_descr_w8  = BS8.pack (getTyDescription (idType id))

getTyDescription :: Type -> String
getTyDescription ty
  = case (tcSplitSigmaTy ty) of { (_, _, tau_ty) ->
    case tau_ty of
      TyVarTy _              -> "*"
      AppTy fun _            -> getTyDescription fun
      TyConApp tycon _       -> getOccString tycon
      FunTy {}              -> '-' : fun_result tau_ty
      ForAllTy _  ty         -> getTyDescription ty
      LitTy n                -> getTyLitDescription n
      CastTy ty _            -> getTyDescription ty
      CoercionTy co          -> pprPanic "getTyDescription" (ppr co)
    }
  where
    fun_result (FunTy { ft_res = res }) = '>' : fun_result res
    fun_result other                    = getTyDescription other

getTyLitDescription :: TyLit -> String
getTyLitDescription l =
  case l of
    NumTyLit n -> show n
    StrTyLit n -> show n
    CharTyLit n -> show n

--------------------------------------
--   CmmInfoTable-related things
--------------------------------------

mkDataConInfoTable :: Profile -> DataCon -> ConInfoTableLocation -> Bool -> Int -> Int -> CmmInfoTable
mkDataConInfoTable profile data_con mn is_static ptr_wds nonptr_wds
 = CmmInfoTable { cit_lbl  = info_lbl
                , cit_rep  = sm_rep
                , cit_prof = prof
                , cit_srt  = Nothing
                , cit_clo  = Nothing }
 where
   name = dataConName data_con
   info_lbl = mkConInfoTableLabel name mn -- NoCAFRefs
   sm_rep = mkHeapRep profile is_static ptr_wds nonptr_wds cl_type
   cl_type = Constr (dataConTagZ data_con) (dataConIdentity data_con)
                  -- We keep the *zero-indexed* tag in the srt_len field
                  -- of the info table of a data constructor.

   prof | not (profileIsProfiling profile) = NoProfilingInfo
        | otherwise                        = ProfilingInfo ty_descr val_descr

   ty_descr  = BS8.pack $ occNameString $ getOccName $ dataConTyCon data_con
   val_descr = BS8.pack $ occNameString $ getOccName data_con

-- We need a black-hole closure info to pass to @allocDynClosure@ when we
-- want to allocate the black hole on entry to a CAF.

cafBlackHoleInfoTable :: CmmInfoTable
cafBlackHoleInfoTable
  = CmmInfoTable { cit_lbl  = mkCAFBlackHoleInfoTableLabel
                 , cit_rep  = blackHoleRep
                 , cit_prof = NoProfilingInfo
                 , cit_srt  = Nothing
                 , cit_clo  = Nothing }

indStaticInfoTable :: CmmInfoTable
indStaticInfoTable
  = CmmInfoTable { cit_lbl  = mkIndStaticInfoLabel
                 , cit_rep  = indStaticRep
                 , cit_prof = NoProfilingInfo
                 , cit_srt  = Nothing
                 , cit_clo  = Nothing }

staticClosureNeedsLink :: Bool -> CmmInfoTable -> Bool
-- A static closure needs a link field to aid the GC when traversing
-- the static closure graph.  But it only needs such a field if either
--        a) it has an SRT
--        b) it's a constructor with one or more pointer fields
-- In case (b), the constructor's fields themselves play the role
-- of the SRT.
staticClosureNeedsLink has_srt CmmInfoTable{ cit_rep = smrep }
  | isConRep smrep         = not (isStaticNoCafCon smrep)
  | otherwise              = has_srt

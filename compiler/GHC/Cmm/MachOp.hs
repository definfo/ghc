{-# LANGUAGE LambdaCase #-}

{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}

module GHC.Cmm.MachOp
    ( MachOp(..)
    , pprMachOp, isCommutableMachOp, isAssociativeMachOp
    , isComparisonMachOp, maybeIntComparison, machOpResultType
    , machOpArgReps, maybeInvertComparison, isFloatComparison

    -- MachOp builders
    , mo_wordAdd, mo_wordSub, mo_wordEq, mo_wordNe,mo_wordMul, mo_wordSQuot
    , mo_wordSRem, mo_wordSNeg, mo_wordUQuot, mo_wordURem
    , mo_wordSGe, mo_wordSLe, mo_wordSGt, mo_wordSLt, mo_wordUGe
    , mo_wordULe, mo_wordUGt, mo_wordULt
    , mo_wordAnd, mo_wordOr, mo_wordXor, mo_wordNot
    , mo_wordShl, mo_wordSShr, mo_wordUShr
    , mo_u_8To32, mo_s_8To32, mo_u_16To32, mo_s_16To32
    , mo_u_8ToWord, mo_s_8ToWord, mo_u_16ToWord, mo_s_16ToWord
    , mo_u_32ToWord, mo_s_32ToWord
    , mo_32To8, mo_32To16, mo_WordTo8, mo_WordTo16, mo_WordTo32, mo_WordTo64

    -- CallishMachOp
    , CallishMachOp(..), callishMachOpHints
    , pprCallishMachOp
    , machOpMemcpyishAlign

    -- Atomic read-modify-write
    , MemoryOrdering(..)
    , AtomicMachOp(..)

    -- Fused multiply-add
    , FMASign(..), pprFMASign
   )
where

import GHC.Prelude

import GHC.Platform
import GHC.Cmm.Type
import GHC.Utils.Outputable

-----------------------------------------------------------------------------
--              MachOp
-----------------------------------------------------------------------------

{- |
Machine-level primops; ones which we can reasonably delegate to the
native code generators to handle.

Most operations are parameterised by the 'Width' that they operate on.
Some operations have separate signed and unsigned versions, and float
and integer versions.

Note that there are variety of places in the native code generator where we
assume that the code produced for a MachOp does not introduce new blocks.
-}

-- Note [MO_S_MulMayOflo significant width]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
--
-- There are two interpretations in the code about what a multiplication
-- overflow exactly means:
--
-- 1. The result does not fit into the specified width (of type Width.)
-- 2. The result does not fit into a register.
--
-- (2) has some flaws: A following MO_Mul has a width, too. So MO_S_MulMayOflo
-- may signal no overflow, while MO_Mul truncates the result. There are
-- architectures with several register widths and it might be hard to decide
-- what's an overflow and what not. Both attributes can easily lead to subtle
-- bugs.
--
-- (1) has the benefit that its interpretation is completely independent of the
-- architecture. So, the mid-term plan is to migrate to this
-- interpretation/sematics.

data MachOp
  -- Integer operations (insensitive to signed/unsigned)
  = MO_Add Width
  | MO_Sub Width
  | MO_Eq  Width
  | MO_Ne  Width
  | MO_Mul Width                -- low word of multiply

  -- Signed multiply/divide
  | MO_S_MulMayOflo Width       -- nonzero if signed multiply overflows. See
                                -- Note [MO_S_MulMayOflo significant width]
  | MO_S_Quot Width             -- signed / (same semantics as IntQuotOp)
  | MO_S_Rem  Width             -- signed % (same semantics as IntRemOp)
  | MO_S_Neg  Width             -- unary -

  -- Unsigned multiply/divide
  | MO_U_Quot Width             -- unsigned / (same semantics as WordQuotOp)
  | MO_U_Rem  Width             -- unsigned % (same semantics as WordRemOp)

  -- Signed comparisons
  | MO_S_Ge Width
  | MO_S_Le Width
  | MO_S_Gt Width
  | MO_S_Lt Width

  -- Unsigned comparisons
  | MO_U_Ge Width
  | MO_U_Le Width
  | MO_U_Gt Width
  | MO_U_Lt Width

  -- Floating point arithmetic
  | MO_F_Add  Width
  | MO_F_Sub  Width
  | MO_F_Neg  Width             -- unary -
  | MO_F_Mul  Width
  | MO_F_Quot Width

  -- Floating-point fused multiply-add operations
  -- | Fused multiply-add, see 'FMASign'.
  | MO_FMA FMASign Width

  -- Floating point comparison
  | MO_F_Eq Width
  | MO_F_Ne Width
  | MO_F_Ge Width
  | MO_F_Le Width
  | MO_F_Gt Width
  | MO_F_Lt Width

  -- Bitwise operations.  Not all of these may be supported
  -- at all sizes, and only integral Widths are valid.
  | MO_And   Width
  | MO_Or    Width
  | MO_Xor   Width
  | MO_Not   Width

  -- Shifts. The shift amount must be in [0,widthInBits).
  | MO_Shl   Width
  | MO_U_Shr Width      -- unsigned shift right
  | MO_S_Shr Width      -- signed shift right

  -- Conversions.  Some of these will be NOPs.
  -- Floating-point conversions use the signed variant.
  | MO_SF_Conv Width Width      -- Signed int -> Float
  | MO_FS_Conv Width Width      -- Float -> Signed int
  | MO_SS_Conv Width Width      -- Signed int -> Signed int
  | MO_UU_Conv Width Width      -- unsigned int -> unsigned int
  | MO_XX_Conv Width Width      -- int -> int; puts no requirements on the
                                -- contents of upper bits when extending;
                                -- narrowing is simply truncation; the only
                                -- expectation is that we can recover the
                                -- original value by applying the opposite
                                -- MO_XX_Conv, e.g.,
                                --   MO_XX_CONV W64 W8 (MO_XX_CONV W8 W64 x)
                                -- is equivalent to just x.
  | MO_FF_Conv Width Width      -- Float -> Float

  -- Vector element insertion and extraction operations
  | MO_V_Insert  Length Width   -- Insert scalar into vector
  | MO_V_Extract Length Width   -- Extract scalar from vector

  -- Integer vector operations
  | MO_V_Add Length Width
  | MO_V_Sub Length Width
  | MO_V_Mul Length Width

  -- Signed vector multiply/divide
  | MO_VS_Quot Length Width
  | MO_VS_Rem  Length Width
  | MO_VS_Neg  Length Width

  -- Unsigned vector multiply/divide
  | MO_VU_Quot Length Width
  | MO_VU_Rem  Length Width

  -- Floating point vector element insertion and extraction operations
  | MO_VF_Insert  Length Width   -- Insert scalar into vector
  | MO_VF_Extract Length Width   -- Extract scalar from vector

  -- Floating point vector operations
  | MO_VF_Add  Length Width
  | MO_VF_Sub  Length Width
  | MO_VF_Neg  Length Width      -- unary negation
  | MO_VF_Mul  Length Width
  | MO_VF_Quot Length Width

  -- Alignment check (for -falignment-sanitisation)
  | MO_AlignmentCheck Int Width
  deriving (Eq, Show)

pprMachOp :: MachOp -> SDoc
pprMachOp mo = text (show mo)

-- | Where are the signs in a fused multiply-add instruction?
--
-- @x*y + z@ vs @x*y - z@ vs @-x*y+z@ vs @-x*y-z@.
--
-- Warning: the signs aren't consistent across architectures (X86, PowerPC, AArch64).
-- The user-facing implementation uses the X86 convention, while the relevant
-- backends use their corresponding conventions.
data FMASign
  -- | Fused multiply-add @x*y + z@.
  = FMAdd
  -- | Fused multiply-subtract. On X86: @x*y - z@.
  | FMSub
  -- | Fused multiply-add. On X86: @-x*y + z@.
  | FNMAdd
  -- | Fused multiply-subtract. On X86: @-x*y - z@.
  | FNMSub
  deriving (Eq, Show)

pprFMASign :: IsLine doc => FMASign -> doc
pprFMASign = \case
  FMAdd  -> text "fmadd"
  FMSub  -> text "fmsub"
  FNMAdd -> text "fnmadd"
  FNMSub -> text "fnmsub"

-- -----------------------------------------------------------------------------
-- Some common MachReps

-- A 'wordRep' is a machine word on the target architecture
-- Specifically, it is the size of an Int#, Word#, Addr#
-- and the unit of allocation on the stack and the heap
-- Any pointer is also guaranteed to be a wordRep.

mo_wordAdd, mo_wordSub, mo_wordEq, mo_wordNe,mo_wordMul, mo_wordSQuot
    , mo_wordSRem, mo_wordSNeg, mo_wordUQuot, mo_wordURem
    , mo_wordSGe, mo_wordSLe, mo_wordSGt, mo_wordSLt, mo_wordUGe
    , mo_wordULe, mo_wordUGt, mo_wordULt
    , mo_wordAnd, mo_wordOr, mo_wordXor, mo_wordNot, mo_wordShl, mo_wordSShr, mo_wordUShr
    , mo_u_8ToWord, mo_s_8ToWord, mo_u_16ToWord, mo_s_16ToWord, mo_u_32ToWord, mo_s_32ToWord
    , mo_WordTo8, mo_WordTo16, mo_WordTo32, mo_WordTo64
    :: Platform -> MachOp

mo_u_8To32, mo_s_8To32, mo_u_16To32, mo_s_16To32
    , mo_32To8, mo_32To16
    :: MachOp

mo_wordAdd      platform = MO_Add (wordWidth platform)
mo_wordSub      platform = MO_Sub (wordWidth platform)
mo_wordEq       platform = MO_Eq  (wordWidth platform)
mo_wordNe       platform = MO_Ne  (wordWidth platform)
mo_wordMul      platform = MO_Mul (wordWidth platform)
mo_wordSQuot    platform = MO_S_Quot (wordWidth platform)
mo_wordSRem     platform = MO_S_Rem (wordWidth platform)
mo_wordSNeg     platform = MO_S_Neg (wordWidth platform)
mo_wordUQuot    platform = MO_U_Quot (wordWidth platform)
mo_wordURem     platform = MO_U_Rem (wordWidth platform)

mo_wordSGe      platform = MO_S_Ge  (wordWidth platform)
mo_wordSLe      platform = MO_S_Le  (wordWidth platform)
mo_wordSGt      platform = MO_S_Gt  (wordWidth platform)
mo_wordSLt      platform = MO_S_Lt  (wordWidth platform)

mo_wordUGe      platform = MO_U_Ge  (wordWidth platform)
mo_wordULe      platform = MO_U_Le  (wordWidth platform)
mo_wordUGt      platform = MO_U_Gt  (wordWidth platform)
mo_wordULt      platform = MO_U_Lt  (wordWidth platform)

mo_wordAnd      platform = MO_And (wordWidth platform)
mo_wordOr       platform = MO_Or  (wordWidth platform)
mo_wordXor      platform = MO_Xor (wordWidth platform)
mo_wordNot      platform = MO_Not (wordWidth platform)
mo_wordShl      platform = MO_Shl (wordWidth platform)
mo_wordSShr     platform = MO_S_Shr (wordWidth platform)
mo_wordUShr     platform = MO_U_Shr (wordWidth platform)

mo_u_8To32               = MO_UU_Conv W8 W32
mo_s_8To32               = MO_SS_Conv W8 W32
mo_u_16To32              = MO_UU_Conv W16 W32
mo_s_16To32              = MO_SS_Conv W16 W32

mo_u_8ToWord    platform = MO_UU_Conv W8  (wordWidth platform)
mo_s_8ToWord    platform = MO_SS_Conv W8  (wordWidth platform)
mo_u_16ToWord   platform = MO_UU_Conv W16 (wordWidth platform)
mo_s_16ToWord   platform = MO_SS_Conv W16 (wordWidth platform)
mo_s_32ToWord   platform = MO_SS_Conv W32 (wordWidth platform)
mo_u_32ToWord   platform = MO_UU_Conv W32 (wordWidth platform)

mo_WordTo8      platform = MO_UU_Conv (wordWidth platform) W8
mo_WordTo16     platform = MO_UU_Conv (wordWidth platform) W16
mo_WordTo32     platform = MO_UU_Conv (wordWidth platform) W32
mo_WordTo64     platform = MO_UU_Conv (wordWidth platform) W64

mo_32To8                 = MO_UU_Conv W32 W8
mo_32To16                = MO_UU_Conv W32 W16


-- ----------------------------------------------------------------------------
-- isCommutableMachOp

{- |
Returns 'True' if the MachOp has commutable arguments.  This is used
in the platform-independent Cmm optimisations.

If in doubt, return 'False'.  This generates worse code on the
native routes, but is otherwise harmless.
-}
isCommutableMachOp :: MachOp -> Bool
isCommutableMachOp mop =
  case mop of
        MO_Add _                -> True
        MO_Eq _                 -> True
        MO_Ne _                 -> True
        MO_Mul _                -> True
        MO_S_MulMayOflo _       -> True
        MO_And _                -> True
        MO_Or _                 -> True
        MO_Xor _                -> True
        MO_F_Add _              -> True
        MO_F_Mul _              -> True
        _other                  -> False

-- ----------------------------------------------------------------------------
-- isAssociativeMachOp

{- |
Returns 'True' if the MachOp is associative (i.e. @(x+y)+z == x+(y+z)@)
This is used in the platform-independent Cmm optimisations.

If in doubt, return 'False'.  This generates worse code on the
native routes, but is otherwise harmless.
-}
isAssociativeMachOp :: MachOp -> Bool
isAssociativeMachOp mop =
  case mop of
        MO_Add {} -> True       -- NB: does not include
        MO_Mul {} -> True --     floatint point!
        MO_And {} -> True
        MO_Or  {} -> True
        MO_Xor {} -> True
        _other    -> False


-- ----------------------------------------------------------------------------
-- isComparisonMachOp

{- |
Returns 'True' if the MachOp is a comparison.

If in doubt, return False.  This generates worse code on the
native routes, but is otherwise harmless.
-}
isComparisonMachOp :: MachOp -> Bool
isComparisonMachOp mop =
  case mop of
    MO_Eq   _  -> True
    MO_Ne   _  -> True
    MO_S_Ge _  -> True
    MO_S_Le _  -> True
    MO_S_Gt _  -> True
    MO_S_Lt _  -> True
    MO_U_Ge _  -> True
    MO_U_Le _  -> True
    MO_U_Gt _  -> True
    MO_U_Lt _  -> True
    MO_F_Eq {} -> True
    MO_F_Ne {} -> True
    MO_F_Ge {} -> True
    MO_F_Le {} -> True
    MO_F_Gt {} -> True
    MO_F_Lt {} -> True
    _other     -> False

{- |
Returns @Just w@ if the operation is an integer comparison with width
@w@, or @Nothing@ otherwise.
-}
maybeIntComparison :: MachOp -> Maybe Width
maybeIntComparison mop =
  case mop of
    MO_Eq   w  -> Just w
    MO_Ne   w  -> Just w
    MO_S_Ge w  -> Just w
    MO_S_Le w  -> Just w
    MO_S_Gt w  -> Just w
    MO_S_Lt w  -> Just w
    MO_U_Ge w  -> Just w
    MO_U_Le w  -> Just w
    MO_U_Gt w  -> Just w
    MO_U_Lt w  -> Just w
    _ -> Nothing

isFloatComparison :: MachOp -> Bool
isFloatComparison mop =
  case mop of
    MO_F_Eq {} -> True
    MO_F_Ne {} -> True
    MO_F_Ge {} -> True
    MO_F_Le {} -> True
    MO_F_Gt {} -> True
    MO_F_Lt {} -> True
    _other     -> False

-- Note [Inverting conditions]
-- ~~~~~~~~~~~~~~~~~~~~~~~~~~~
-- Sometimes it's useful to be able to invert the sense of a
-- condition.  Not all conditional tests are invertible: in
-- particular, floating point conditionals cannot be inverted, because
-- there exist floating-point values which return False for both senses
-- of a condition (eg. !(NaN > NaN) && !(NaN /<= NaN)).

maybeInvertComparison :: MachOp -> Maybe MachOp
maybeInvertComparison op
  = case op of  -- None of these Just cases include floating point
        MO_Eq r   -> Just (MO_Ne r)
        MO_Ne r   -> Just (MO_Eq r)
        MO_U_Lt r -> Just (MO_U_Ge r)
        MO_U_Gt r -> Just (MO_U_Le r)
        MO_U_Le r -> Just (MO_U_Gt r)
        MO_U_Ge r -> Just (MO_U_Lt r)
        MO_S_Lt r -> Just (MO_S_Ge r)
        MO_S_Gt r -> Just (MO_S_Le r)
        MO_S_Le r -> Just (MO_S_Gt r)
        MO_S_Ge r -> Just (MO_S_Lt r)
        _other    -> Nothing

-- ----------------------------------------------------------------------------
-- machOpResultType

{- |
Returns the MachRep of the result of a MachOp.
-}
machOpResultType :: Platform -> MachOp -> [CmmType] -> CmmType
machOpResultType platform mop tys =
  case mop of
    MO_Add {}           -> ty1  -- Preserve GC-ptr-hood
    MO_Sub {}           -> ty1  -- of first arg
    MO_Mul    r         -> cmmBits r
    MO_S_MulMayOflo r   -> cmmBits r
    MO_S_Quot r         -> cmmBits r
    MO_S_Rem  r         -> cmmBits r
    MO_S_Neg  r         -> cmmBits r
    MO_U_Quot r         -> cmmBits r
    MO_U_Rem  r         -> cmmBits r

    MO_Eq {}            -> comparisonResultRep platform
    MO_Ne {}            -> comparisonResultRep platform
    MO_S_Ge {}          -> comparisonResultRep platform
    MO_S_Le {}          -> comparisonResultRep platform
    MO_S_Gt {}          -> comparisonResultRep platform
    MO_S_Lt {}          -> comparisonResultRep platform

    MO_U_Ge {}          -> comparisonResultRep platform
    MO_U_Le {}          -> comparisonResultRep platform
    MO_U_Gt {}          -> comparisonResultRep platform
    MO_U_Lt {}          -> comparisonResultRep platform

    MO_F_Add r          -> cmmFloat r
    MO_F_Sub r          -> cmmFloat r
    MO_F_Mul r          -> cmmFloat r
    MO_F_Quot r         -> cmmFloat r
    MO_F_Neg r          -> cmmFloat r

    MO_FMA _ r          -> cmmFloat r

    MO_F_Eq  {}         -> comparisonResultRep platform
    MO_F_Ne  {}         -> comparisonResultRep platform
    MO_F_Ge  {}         -> comparisonResultRep platform
    MO_F_Le  {}         -> comparisonResultRep platform
    MO_F_Gt  {}         -> comparisonResultRep platform
    MO_F_Lt  {}         -> comparisonResultRep platform

    MO_And {}           -> ty1  -- Used for pointer masking
    MO_Or {}            -> ty1
    MO_Xor {}           -> ty1
    MO_Not   r          -> cmmBits r
    MO_Shl   r          -> cmmBits r
    MO_U_Shr r          -> cmmBits r
    MO_S_Shr r          -> cmmBits r

    MO_SS_Conv _ to     -> cmmBits to
    MO_UU_Conv _ to     -> cmmBits to
    MO_XX_Conv _ to     -> cmmBits to
    MO_FS_Conv _ to     -> cmmBits to
    MO_SF_Conv _ to     -> cmmFloat to
    MO_FF_Conv _ to     -> cmmFloat to

    MO_V_Insert  l w    -> cmmVec l (cmmBits w)
    MO_V_Extract _ w    -> cmmBits w

    MO_V_Add l w        -> cmmVec l (cmmBits w)
    MO_V_Sub l w        -> cmmVec l (cmmBits w)
    MO_V_Mul l w        -> cmmVec l (cmmBits w)

    MO_VS_Quot l w      -> cmmVec l (cmmBits w)
    MO_VS_Rem  l w      -> cmmVec l (cmmBits w)
    MO_VS_Neg  l w      -> cmmVec l (cmmBits w)

    MO_VU_Quot l w      -> cmmVec l (cmmBits w)
    MO_VU_Rem  l w      -> cmmVec l (cmmBits w)

    MO_VF_Insert  l w   -> cmmVec l (cmmFloat w)
    MO_VF_Extract _ w   -> cmmFloat w

    MO_VF_Add  l w      -> cmmVec l (cmmFloat w)
    MO_VF_Sub  l w      -> cmmVec l (cmmFloat w)
    MO_VF_Mul  l w      -> cmmVec l (cmmFloat w)
    MO_VF_Quot l w      -> cmmVec l (cmmFloat w)
    MO_VF_Neg  l w      -> cmmVec l (cmmFloat w)

    MO_AlignmentCheck _ _ -> ty1
  where
    (ty1:_) = tys

comparisonResultRep :: Platform -> CmmType
comparisonResultRep = bWord  -- is it?


-- -----------------------------------------------------------------------------
-- machOpArgReps

-- | This function is used for debugging only: we can check whether an
-- application of a MachOp is "type-correct" by checking that the MachReps of
-- its arguments are the same as the MachOp expects.  This is used when
-- linting a CmmExpr.

machOpArgReps :: Platform -> MachOp -> [Width]
machOpArgReps platform op =
  case op of
    MO_Add    r         -> [r,r]
    MO_Sub    r         -> [r,r]
    MO_Eq     r         -> [r,r]
    MO_Ne     r         -> [r,r]
    MO_Mul    r         -> [r,r]
    MO_S_MulMayOflo r   -> [r,r]
    MO_S_Quot r         -> [r,r]
    MO_S_Rem  r         -> [r,r]
    MO_S_Neg  r         -> [r]
    MO_U_Quot r         -> [r,r]
    MO_U_Rem  r         -> [r,r]

    MO_S_Ge r           -> [r,r]
    MO_S_Le r           -> [r,r]
    MO_S_Gt r           -> [r,r]
    MO_S_Lt r           -> [r,r]

    MO_U_Ge r           -> [r,r]
    MO_U_Le r           -> [r,r]
    MO_U_Gt r           -> [r,r]
    MO_U_Lt r           -> [r,r]

    MO_F_Add r          -> [r,r]
    MO_F_Sub r          -> [r,r]
    MO_F_Mul r          -> [r,r]
    MO_F_Quot r         -> [r,r]
    MO_F_Neg r          -> [r]

    MO_FMA _ r          -> [r,r,r]

    MO_F_Eq  r          -> [r,r]
    MO_F_Ne  r          -> [r,r]
    MO_F_Ge  r          -> [r,r]
    MO_F_Le  r          -> [r,r]
    MO_F_Gt  r          -> [r,r]
    MO_F_Lt  r          -> [r,r]

    MO_And   r          -> [r,r]
    MO_Or    r          -> [r,r]
    MO_Xor   r          -> [r,r]
    MO_Not   r          -> [r]
    MO_Shl   r          -> [r, wordWidth platform]
    MO_U_Shr r          -> [r, wordWidth platform]
    MO_S_Shr r          -> [r, wordWidth platform]

    MO_SS_Conv from _   -> [from]
    MO_UU_Conv from _   -> [from]
    MO_XX_Conv from _   -> [from]
    MO_SF_Conv from _   -> [from]
    MO_FS_Conv from _   -> [from]
    MO_FF_Conv from _   -> [from]

    MO_V_Insert   l r   -> [typeWidth (vec l (cmmBits r)),r, W32]
    MO_V_Extract  l r   -> [typeWidth (vec l (cmmBits r)), W32]
    MO_VF_Insert  l r   -> [typeWidth (vec l (cmmFloat r)),r,W32]
    MO_VF_Extract l r   -> [typeWidth (vec l (cmmFloat r)),W32]
      -- SIMD vector indices are always 32 bit

    MO_V_Add _ r        -> [r,r]
    MO_V_Sub _ r        -> [r,r]
    MO_V_Mul _ r        -> [r,r]

    MO_VS_Quot _ r      -> [r,r]
    MO_VS_Rem  _ r      -> [r,r]
    MO_VS_Neg  _ r      -> [r]

    MO_VU_Quot _ r      -> [r,r]
    MO_VU_Rem  _ r      -> [r,r]

    MO_VF_Add  _ r      -> [r,r]
    MO_VF_Sub  _ r      -> [r,r]
    MO_VF_Mul  _ r      -> [r,r]
    MO_VF_Quot _ r      -> [r,r]
    MO_VF_Neg  _ r      -> [r]

    MO_AlignmentCheck _ r -> [r]

-----------------------------------------------------------------------------
-- CallishMachOp
-----------------------------------------------------------------------------

-- CallishMachOps tend to be implemented by foreign calls in some backends,
-- so we separate them out.  In Cmm, these can only occur in a
-- statement position, in contrast to an ordinary MachOp which can occur
-- anywhere in an expression.
data CallishMachOp
  = MO_F64_Pwr
  | MO_F64_Sin
  | MO_F64_Cos
  | MO_F64_Tan
  | MO_F64_Sinh
  | MO_F64_Cosh
  | MO_F64_Tanh
  | MO_F64_Asin
  | MO_F64_Acos
  | MO_F64_Atan
  | MO_F64_Asinh
  | MO_F64_Acosh
  | MO_F64_Atanh
  | MO_F64_Log
  | MO_F64_Log1P
  | MO_F64_Exp
  | MO_F64_ExpM1
  | MO_F64_Fabs
  | MO_F64_Sqrt
  | MO_F32_Pwr
  | MO_F32_Sin
  | MO_F32_Cos
  | MO_F32_Tan
  | MO_F32_Sinh
  | MO_F32_Cosh
  | MO_F32_Tanh
  | MO_F32_Asin
  | MO_F32_Acos
  | MO_F32_Atan
  | MO_F32_Asinh
  | MO_F32_Acosh
  | MO_F32_Atanh
  | MO_F32_Log
  | MO_F32_Log1P
  | MO_F32_Exp
  | MO_F32_ExpM1
  | MO_F32_Fabs
  | MO_F32_Sqrt

  -- 64-bit int/word ops for when they exceed the native word size
  -- (i.e. on 32-bit architectures)
  | MO_I64_ToI
  | MO_I64_FromI
  | MO_W64_ToW
  | MO_W64_FromW

  | MO_x64_Neg
  | MO_x64_Add
  | MO_x64_Sub
  | MO_x64_Mul
  | MO_I64_Quot
  | MO_I64_Rem
  | MO_W64_Quot
  | MO_W64_Rem

  | MO_x64_And
  | MO_x64_Or
  | MO_x64_Xor
  | MO_x64_Not
  | MO_x64_Shl
  | MO_I64_Shr
  | MO_W64_Shr

  | MO_x64_Eq
  | MO_x64_Ne
  | MO_I64_Ge
  | MO_I64_Gt
  | MO_I64_Le
  | MO_I64_Lt
  | MO_W64_Ge
  | MO_W64_Gt
  | MO_W64_Le
  | MO_W64_Lt

  | MO_UF_Conv Width

  | MO_S_Mul2    Width
  | MO_S_QuotRem Width
  | MO_U_QuotRem Width
  | MO_U_QuotRem2 Width
  | MO_Add2      Width
  | MO_AddWordC  Width
  | MO_SubWordC  Width
  | MO_AddIntC   Width
  | MO_SubIntC   Width
  | MO_U_Mul2    Width

  | MO_ReadBarrier
  | MO_WriteBarrier
  | MO_Touch         -- Keep variables live (when using interior pointers)

  -- Prefetch
  | MO_Prefetch_Data Int -- Prefetch hint. May change program performance but not
                     -- program behavior.
                     -- the Int can be 0-3. Needs to be known at compile time
                     -- to interact with code generation correctly.
                     --  TODO: add support for prefetch WRITES,
                     --  currently only exposes prefetch reads, which
                     -- would the majority of use cases in ghc anyways


  -- These three MachOps are parameterised by the known alignment
  -- of the destination and source (for memcpy/memmove) pointers.
  -- This information may be used for optimisation in backends.
  | MO_Memcpy Int
  | MO_Memset Int
  | MO_Memmove Int
  | MO_Memcmp Int

  | MO_PopCnt Width
  | MO_Pdep Width
  | MO_Pext Width
  | MO_Clz Width
  | MO_Ctz Width

  | MO_BSwap Width
  | MO_BRev Width

  -- | Atomic read-modify-write. Arguments are @[dest, n]@.
  | MO_AtomicRMW Width AtomicMachOp
  -- | Atomic read. Arguments are @[addr]@.
  | MO_AtomicRead Width MemoryOrdering
  -- | Atomic write. Arguments are @[addr, value]@.
  | MO_AtomicWrite Width MemoryOrdering
  -- | Atomic compare-and-swap. Arguments are @[dest, expected, new]@.
  -- Sequentially consistent.
  -- Possible future refactoring: should this be an'MO_AtomicRMW' variant?
  | MO_Cmpxchg Width
  -- | Atomic swap. Arguments are @[dest, new]@
  | MO_Xchg Width

  -- These rts provided functions are special: suspendThread releases the
  -- capability, hence we mustn't sink any use of data stored in the capability
  -- after this instruction.
  | MO_SuspendThread
  | MO_ResumeThread
  deriving (Eq, Show)

-- | C11 memory ordering semantics.
data MemoryOrdering
  = MemOrderRelaxed  -- ^ relaxed ordering
  | MemOrderAcquire  -- ^ acquire ordering
  | MemOrderRelease  -- ^ release ordering
  | MemOrderSeqCst   -- ^ sequentially consistent
  deriving (Eq, Ord, Show)

-- | The operation to perform atomically.
data AtomicMachOp =
      AMO_Add
    | AMO_Sub
    | AMO_And
    | AMO_Nand
    | AMO_Or
    | AMO_Xor
      deriving (Eq, Show)

pprCallishMachOp :: CallishMachOp -> SDoc
pprCallishMachOp mo = text (show mo)

-- | Return (results_hints,args_hints)
callishMachOpHints :: CallishMachOp -> ([ForeignHint], [ForeignHint])
callishMachOpHints op = case op of
  MO_Memcpy _      -> ([], [AddrHint,AddrHint,NoHint])
  MO_Memset _      -> ([], [AddrHint,NoHint,NoHint])
  MO_Memmove _     -> ([], [AddrHint,AddrHint,NoHint])
  MO_Memcmp _      -> ([], [AddrHint, AddrHint, NoHint])
  MO_SuspendThread -> ([AddrHint], [AddrHint,NoHint])
  MO_ResumeThread  -> ([AddrHint], [AddrHint])
  _                -> ([],[])
  -- empty lists indicate NoHint

-- | The alignment of a 'memcpy'-ish operation.
machOpMemcpyishAlign :: CallishMachOp -> Maybe Int
machOpMemcpyishAlign op = case op of
  MO_Memcpy  align -> Just align
  MO_Memset  align -> Just align
  MO_Memmove align -> Just align
  MO_Memcmp  align -> Just align
  _                -> Nothing

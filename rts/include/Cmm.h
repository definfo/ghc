/* -----------------------------------------------------------------------------
 *
 * (c) The University of Glasgow 2004-2013
 *
 * This file is included at the top of all .cmm source files (and
 * *only* .cmm files).  It defines a collection of useful macros for
 * making .cmm code a bit less error-prone to write, and a bit easier
 * on the eye for the reader.
 *
 * For the syntax of .cmm files, see the parser in ghc/compiler/GHC/Cmm/Parser.y.
 *
 * Accessing fields of structures defined in the RTS header files is
 * done via automatically-generated macros in DerivedConstants.h.  For
 * example, where previously we used
 *
 *          CurrentTSO->what_next = x
 *
 * in C-- we now use
 *
 *          StgTSO_what_next(CurrentTSO) = x
 *
 * where the StgTSO_what_next() macro is automatically generated by
 * utils/deriveConstants.  If you need to access a field that doesn't
 * already have a macro, edit that program (it's pretty self-explanatory).
 *
 * -------------------------------------------------------------------------- */

#pragma once

/*
 * In files that are included into both C and C-- (and perhaps
 * Haskell) sources, we sometimes need to conditionally compile bits
 * depending on the language.  CMINUSMINUS==1 in .cmm sources:
 */
#define CMINUSMINUS 1

#include "ghcconfig.h"
#include "rts/TSANUtils.h"

/* -----------------------------------------------------------------------------
   Types

   The following synonyms for C-- types are declared here:

     I8, I16, I32, I64    MachRep-style names for convenience

     W_                   is shorthand for the word type (== StgWord)
     F_                   shorthand for float  (F_ == StgFloat == C's float)
     D_                   shorthand for double (D_ == StgDouble == C's double)

     CInt                 has the same size as an int in C on this platform
     CLong                has the same size as a long in C on this platform
     CBool                has the same size as a bool in C on this platform

  --------------------------------------------------------------------------- */

#define I8  bits8
#define I16 bits16
#define I32 bits32
#define I64 bits64
#define P_  gcptr

#if SIZEOF_VOID_P == 4
#define W_ bits32
/* Maybe it's better to include MachDeps.h */
#define TAG_BITS                2
#elif SIZEOF_VOID_P == 8
#define W_ bits64
/* Maybe it's better to include MachDeps.h */
#define TAG_BITS                3
#else
#error Unknown word size
#endif

/*
 * The RTS must sometimes UNTAG a pointer before dereferencing it.
 * See the wiki page commentary/rts/haskell-execution/pointer-tagging
 */
#define TAG_MASK ((1 << TAG_BITS) - 1)
#define UNTAG(p) (p & ~TAG_MASK)
#define GETTAG(p) (p & TAG_MASK)

#if SIZEOF_INT == 4
#define CInt bits32
#elif SIZEOF_INT == 8
#define CInt bits64
#else
#error Unknown int size
#endif

#if SIZEOF_LONG == 4
#define CLong bits32
#elif SIZEOF_LONG == 8
#define CLong bits64
#else
#error Unknown long size
#endif

#define CBool bits8

#define F_   float32
#define D_   float64
#define L_   bits64
#define V16_ bits128
#define V32_ bits256
#define V64_ bits512

#define SIZEOF_StgDouble 8
#define SIZEOF_StgWord64 8

/* -----------------------------------------------------------------------------
   Misc useful stuff
   -------------------------------------------------------------------------- */

#define ccall foreign "C"

#define NULL (0::W_)

#define STRING(name,str)                        \
  section "rodata" {                            \
        name : bits8[] str;                     \
  }                                             \

#if defined(TABLES_NEXT_TO_CODE)
#define RET_LBL(f) f##_info
#else
#define RET_LBL(f) f##_ret
#endif

#if defined(TABLES_NEXT_TO_CODE)
#define ENTRY_LBL(f) f##_info
#else
#define ENTRY_LBL(f) f##_entry
#endif

/* -----------------------------------------------------------------------------
   Byte/word macros

   Everything in C-- is in byte offsets (well, most things).  We use
   some macros to allow us to express offsets in words and to try to
   avoid byte/word confusion.
   -------------------------------------------------------------------------- */

#define SIZEOF_W  SIZEOF_VOID_P
#define W_MASK    (SIZEOF_W-1)

#if SIZEOF_W == 4
#define W_SHIFT 2
#elif SIZEOF_W == 8
#define W_SHIFT 3
#endif

/* Converting quantities of words to bytes */
#define WDS(n) ((n)*SIZEOF_W)

/*
 * Converting quantities of bytes to words
 * NB. these work on *unsigned* values only
 */
#define BYTES_TO_WDS(n) ((n) / SIZEOF_W)
#define ROUNDUP_BYTES_TO_WDS(n) (((n) + SIZEOF_W - 1) / SIZEOF_W)

/*
 * TO_W_(n) and TO_ZXW_(n) convert n to W_ type from a smaller type,
 * with and without sign extension respectively
 */
#if SIZEOF_W == 4
#define TO_I64(x) %sx64(x)
#define TO_W_(x) %sx32(x)
#define TO_ZXW_(x) %zx32(x)
#define HALF_W_(x) %lobits16(x)
#elif SIZEOF_W == 8
#define TO_I64(x) (x)
#define TO_W_(x) %sx64(x)
#define TO_ZXW_(x) %zx64(x)
#define HALF_W_(x) %lobits32(x)
#endif

#if SIZEOF_INT == 4 && SIZEOF_W == 8
#define W_TO_INT(x) %lobits32(x)
#elif SIZEOF_INT == SIZEOF_W
#define W_TO_INT(x) (x)
#endif

#if SIZEOF_LONG == 4 && SIZEOF_W == 8
#define W_TO_LONG(x) %lobits32(x)
#elif SIZEOF_LONG == SIZEOF_W
#define W_TO_LONG(x) (x)
#endif

/* -----------------------------------------------------------------------------
   Atomic memory operations.
   -------------------------------------------------------------------------- */

#if SIZEOF_W == 4
#define cmpxchgW cmpxchg32
#define xchgW xchg32
#elif SIZEOF_W == 8
#define cmpxchgW cmpxchg64
#define xchgW xchg64
#endif

/* -----------------------------------------------------------------------------
   Heap/stack access, and adjusting the heap/stack pointers.
   -------------------------------------------------------------------------- */

#define Sp(n)  W_[Sp + WDS(n)]
#define Hp(n)  W_[Hp + WDS(n)]

#define Sp_adj(n) Sp = Sp + WDS(n)  /* pronounced "spadge" */
#define Hp_adj(n) Hp = Hp + WDS(n)

/* -----------------------------------------------------------------------------
   Assertions and Debuggery
   -------------------------------------------------------------------------- */

#if defined(DEBUG) || defined(USE_ASSERTS_ALL_WAYS)
#define ASSERTS_ENABLED 1
#else
#undef ASSERTS_ENABLED
#endif

#if defined(ASSERTS_ENABLED)
#define ASSERT(predicate)                       \
        if (predicate) {                        \
            /*null*/;                           \
        } else {                                \
            foreign "C" _assertFail(__FILE__, __LINE__) never returns; \
        }
#else
#define ASSERT(p) /* nothing */
#endif

#if defined(DEBUG)
#define DEBUG_ONLY(s) s
#else
#define DEBUG_ONLY(s) /* nothing */
#endif

/*
 * The IF_DEBUG macro is useful for debug messages that depend on one
 * of the RTS debug options.  For example:
 *
 *   IF_DEBUG(RtsFlags_DebugFlags_apply,
 *      foreign "C" fprintf(stderr, stg_ap_0_ret_str));
 *
 * Note the syntax is slightly different to the C version of this macro.
 */
#if defined(DEBUG)
#define IF_DEBUG(c,s)  if (RtsFlags_DebugFlags_##c(RtsFlags) != 0::CBool) { s; }
#else
#define IF_DEBUG(c,s)  /* nothing */
#endif

#define GHC_STATIC_ASSERT(x) static_assert(x)

/* -----------------------------------------------------------------------------
   Entering

   It isn't safe to "enter" every closure.  Functions in particular
   have no entry code as such; their entry point contains the code to
   apply the function.

   ToDo: range should end in N_CLOSURE_TYPES-1, not N_CLOSURE_TYPES,
   but switch doesn't allow us to use exprs there yet.

   If R1 points to a tagged object it points either to
   * A constructor.
   * A function with arity <= TAG_MASK.
   In both cases the right thing to do is to return.
   Note: it is rather lucky that we can use the tag bits to do this
         for both objects. Maybe it points to a brittle design?

   Indirections can contain tagged pointers, so their tag is checked.
   -------------------------------------------------------------------------- */

#if defined(PROFILING)

// When profiling, we cannot shortcut ENTER() by checking the tag,
// because LDV profiling relies on entering closures to mark them as
// "used".

#define LOAD_INFO_ACQUIRE(ret,x)                \
    info = %acquire StgHeader_info(UNTAG(x));

#define UNTAG_IF_PROF(x) UNTAG(x)

#else

#define LOAD_INFO_ACQUIRE(ret,x)                \
  if (GETTAG(x) != 0) {                         \
      ret(x);                                   \
  }                                             \
  info = %acquire StgHeader_info(x);

#define UNTAG_IF_PROF(x) (x) /* already untagged */

#endif

// We need two versions of ENTER():
//  - ENTER(x) takes the closure as an argument and uses return(),
//    for use in civilized code where the stack is handled by GHC
//
//  - ENTER_NOSTACK() where the closure is in R1, and returns are
//    explicit jumps, for use when we are doing the stack management
//    ourselves.

#if defined(PROFILING)
// See Note [Evaluating functions with profiling] in rts/Apply.cmm
#define ENTER(x) jump stg_ap_0_fast(x);
#else
#define ENTER(x) ENTER_(return,x)
#endif

#define ENTER_R1() P_ _r1; _r1 = R1; ENTER_(RET_R1, _r1)

#define RET_R1(x) jump %ENTRY_CODE(Sp(0)) [R1]

#define ENTER_(ret,x)                                   \
 again:                                                 \
  W_ info;                                              \
  /* See Note [Heap memory barriers] in SMP.h */        \
  LOAD_INFO_ACQUIRE(ret,x);                             \
  switch [INVALID_OBJECT .. N_CLOSURE_TYPES]            \
         (TO_W_( %INFO_TYPE(%STD_INFO(info)) )) {       \
  case                                                  \
    IND,                                                \
    IND_STATIC:                                         \
   {                                                    \
      x = %acquire StgInd_indirectee(x);                \
      goto again;                                       \
   }                                                    \
  case                                                  \
    FUN,                                                \
    FUN_1_0,                                            \
    FUN_0_1,                                            \
    FUN_2_0,                                            \
    FUN_1_1,                                            \
    FUN_0_2,                                            \
    FUN_STATIC,                                         \
    BCO,                                                \
    PAP,                                                \
    CONTINUATION:                                       \
   {                                                    \
       ret(x);                                          \
   }                                                    \
  default:                                              \
   {                                                    \
       x = UNTAG_IF_PROF(x);                            \
       jump %ENTRY_CODE(info) (x);                      \
   }                                                    \
  }

// The FUN cases almost never happen: a pointer to a non-static FUN
// should always be tagged.  This unfortunately isn't true for the
// interpreter right now, which leaves untagged FUNs on the stack.

/* -----------------------------------------------------------------------------
   Constants.
   -------------------------------------------------------------------------- */

#include "rts/Config.h"
#include "rts/Constants.h"
#include "DerivedConstants.h"
#include "rts/storage/ClosureTypes.h"
#include "rts/storage/FunTypes.h"
#include "rts/OSThreads.h"

/*
 * Need MachRegs, because some of the RTS code is conditionally
 * compiled based on REG_R1, REG_R2, etc.
 */
#include "stg/MachRegsForHost.h"

#include "rts/prof/LDV.h"

#undef BLOCK_SIZE
#undef MBLOCK_SIZE
#include "rts/storage/Block.h"  /* For Bdescr() */


#define MyCapability()  (BaseReg - OFFSET_Capability_r)

/* -------------------------------------------------------------------------
   Info tables
   ------------------------------------------------------------------------- */

#if defined(PROFILING)
#define PROF_HDR_FIELDS(w_,hdr1,hdr2)          \
  w_ hdr1,                                     \
  w_ hdr2,
#else
#define PROF_HDR_FIELDS(w_,hdr1,hdr2) /* nothing */
#endif

/* -------------------------------------------------------------------------
   Allocation and garbage collection
   ------------------------------------------------------------------------- */

/*
 * ALLOC_PRIM is for allocating memory on the heap for a primitive
 * object.  It is used all over PrimOps.cmm.
 *
 * We make the simplifying assumption that the "admin" part of a
 * primitive closure is just the header when calculating sizes for
 * ticky-ticky.  It's not clear whether eg. the size field of an array
 * should be counted as "admin", or the various fields of a BCO.
 */
#define ALLOC_PRIM(bytes)                                       \
   HP_CHK_GEN_TICKY(bytes);                                     \
   TICK_ALLOC_PRIM(SIZEOF_StgHeader,bytes-SIZEOF_StgHeader,0);  \
   CCCS_ALLOC(bytes);

#define HEAP_CHECK(bytes,failure)                       \
    TICK_BUMP(HEAP_CHK_ctr);                            \
    Hp = Hp + (bytes);                                  \
    if (Hp > HpLim) { HpAlloc = (bytes); failure; }     \
    TICK_ALLOC_RTS(bytes);

#define ALLOC_PRIM_WITH_CUSTOM_FAILURE(bytes,failure)           \
    HEAP_CHECK(bytes,failure)                                   \
    TICK_ALLOC_PRIM(SIZEOF_StgHeader,bytes-SIZEOF_StgHeader,0); \
    CCCS_ALLOC(bytes);

#define ALLOC_PRIM_(bytes,fun)                                  \
    ALLOC_PRIM_WITH_CUSTOM_FAILURE(bytes,GC_PRIM(fun));

#define ALLOC_PRIM_P(bytes,fun,arg)                             \
    ALLOC_PRIM_WITH_CUSTOM_FAILURE(bytes,GC_PRIM_P(fun,arg));

#define ALLOC_PRIM_N(bytes,fun,arg)                             \
    ALLOC_PRIM_WITH_CUSTOM_FAILURE(bytes,GC_PRIM_N(fun,arg));

/* CCS_ALLOC wants the size in words, because ccs->mem_alloc is in words */
#define CCCS_ALLOC(__alloc) CCS_ALLOC(BYTES_TO_WDS(__alloc), CCCS)

#define HP_CHK_GEN_TICKY(bytes)                 \
   HP_CHK_GEN(bytes);                           \
   TICK_ALLOC_RTS(bytes);

#define HP_CHK_P(bytes, fun, arg)               \
   HEAP_CHECK(bytes, GC_PRIM_P(fun,arg))

// TODO I'm not seeing where ALLOC_P_TICKY is used; can it be removed?
//         -NSF March 2013
#define ALLOC_P_TICKY(bytes, fun, arg)          \
   HP_CHK_P(bytes);                             \
   TICK_ALLOC_RTS(bytes);

// Load a field out of structure with relaxed ordering.
#define RELAXED_LOAD_FIELD(fld, ptr) \
    REP_##fld[(ptr) + OFFSET_##fld]

// Load a field out of an StgClosure with relaxed ordering.
#define RELAXED_LOAD_CLOSURE_FIELD(fld, ptr) \
    REP_##fld[(ptr) + SIZEOF_StgHeader + OFFSET_##fld]

#define CHECK_GC()                                                      \
  (bdescr_link(CurrentNursery) == NULL ||                               \
   RELAXED_LOAD_FIELD(generation_n_new_large_words, W_[g0]) >= TO_W_(CLong[large_alloc_lim]))

// allocate() allocates from the nursery, so we check to see
// whether the nursery is nearly empty in any function that uses
// allocate() - this includes many of the primops.
//
// HACK alert: the __L__ stuff is here to coax the common-block
// eliminator into commoning up the call stg_gc_noregs() with the same
// code that gets generated by a STK_CHK_GEN() in the same proc.  We
// also need an if (0) { goto __L__; } so that the __L__ label isn't
// optimised away by the control-flow optimiser prior to common-block
// elimination (it will be optimised away later).
//
// This saves some code in gmp-wrappers.cmm where we have lots of
// MAYBE_GC() in the same proc as STK_CHK_GEN().
//
#define MAYBE_GC(retry)                         \
    if (CHECK_GC()) {                           \
        HpAlloc = 0;                            \
        goto __L__;                             \
  __L__:                                        \
        call stg_gc_noregs();                   \
        goto retry;                             \
   }                                            \
   if (0) { goto __L__; }

#define GC_PRIM(fun)                            \
        jump stg_gc_prim(fun);

// Version of GC_PRIM for use in low-level Cmm.  We can call
// stg_gc_prim, because it takes one argument and therefore has a
// platform-independent calling convention (Note [Syntax of .cmm
// files] in GHC.Cmm.Parser).
#define GC_PRIM_LL(fun)                         \
        R1 = fun;                               \
        jump stg_gc_prim [R1];

// We pass the fun as the second argument, because the arg is
// usually already in the first argument position (R1), so this
// avoids moving it to a different register / stack slot.
#define GC_PRIM_N(fun,arg)                      \
        jump stg_gc_prim_n(arg,fun);

#define GC_PRIM_P(fun,arg)                      \
        jump stg_gc_prim_p(arg,fun);

#define GC_PRIM_P_LL(fun,arg)                   \
        R1 = arg;                               \
        R2 = fun;                               \
        jump stg_gc_prim_p_ll [R1,R2];

#define GC_PRIM_PP(fun,arg1,arg2)               \
        jump stg_gc_prim_pp(arg1,arg2,fun);

#define GC_PRIM_PP_LL(fun,arg1,arg2)            \
        R1 = arg1;                              \
        R2 = arg2;                              \
        R3 = fun;                               \
        jump stg_gc_prim_pp_ll [R1,R2,R3];

#define MAYBE_GC_(fun)                          \
    if (CHECK_GC()) {                           \
        HpAlloc = 0;                            \
        GC_PRIM(fun)                            \
   }

#define MAYBE_GC_N(fun,arg)                     \
    if (CHECK_GC()) {                           \
        HpAlloc = 0;                            \
        GC_PRIM_N(fun,arg)                      \
   }

#define MAYBE_GC_P(fun,arg)                     \
    if (CHECK_GC()) {                           \
        HpAlloc = 0;                            \
        GC_PRIM_P(fun,arg)                      \
   }

#define MAYBE_GC_PP(fun,arg1,arg2)              \
    if (CHECK_GC()) {                           \
        HpAlloc = 0;                            \
        GC_PRIM_PP(fun,arg1,arg2)               \
   }

#define STK_CHK_LL(n, fun)                      \
    TICK_BUMP(STK_CHK_ctr);                     \
    if (Sp - (n) < SpLim) {                     \
        GC_PRIM_LL(fun)                         \
    }

#define STK_CHK_P_LL(n, fun, arg)               \
    TICK_BUMP(STK_CHK_ctr);                     \
    if (Sp - (n) < SpLim) {                     \
        GC_PRIM_P_LL(fun,arg)                   \
    }

#define STK_CHK_PP(n, fun, arg1, arg2)          \
    TICK_BUMP(STK_CHK_ctr);                     \
    if (Sp - (n) < SpLim) {                     \
        GC_PRIM_PP(fun,arg1,arg2)               \
    }

#define STK_CHK_PP_LL(n, fun, arg1, arg2)       \
    TICK_BUMP(STK_CHK_ctr);                     \
    if (Sp - (n) < SpLim) {                     \
        GC_PRIM_PP_LL(fun,arg1,arg2)            \
    }

#define STK_CHK_ENTER(n, closure)               \
    TICK_BUMP(STK_CHK_ctr);                     \
    if (Sp - (n) < SpLim) {                     \
        jump __stg_gc_enter_1(closure);         \
    }

// A funky heap check used by AutoApply.cmm

#define HP_CHK_NP_ASSIGN_SP0(size,f)                    \
    HEAP_CHECK(size, Sp(0) = f; jump __stg_gc_enter_1 [R1];)

/* -----------------------------------------------------------------------------
   Closure headers
   -------------------------------------------------------------------------- */

/*
 * This is really ugly, since we don't do the rest of StgHeader this
 * way.  The problem is that values from DerivedConstants.h cannot be
 * dependent on the way (SMP, PROF etc.).  For SIZEOF_StgHeader we get
 * the value from GHC, but it seems like too much trouble to do that
 * for StgThunkHeader.
 */
#define SIZEOF_StgThunkHeader SIZEOF_StgHeader+SIZEOF_StgSMPThunkHeader

#define StgThunk_payload(__ptr__,__ix__) \
    W_[__ptr__+SIZEOF_StgThunkHeader+ WDS(__ix__)]

/* -----------------------------------------------------------------------------
   Closures
   -------------------------------------------------------------------------- */

/* The offset of the payload of an array */
#define BYTE_ARR_CTS(arr)  ((arr) + SIZEOF_StgArrBytes)

/* The number of words allocated in an array payload */
#define BYTE_ARR_WDS(arr) ROUNDUP_BYTES_TO_WDS(StgArrBytes_bytes(arr))

/* Getting/setting the info pointer of a closure */
#define SET_INFO(p,info) StgHeader_info(p) = info
#define SET_INFO_RELEASE(p,info) %release StgHeader_info(p) = info
#define GET_INFO(p) StgHeader_info(p)
#define GET_INFO_ACQUIRE(p) %acquire GET_INFO(p)

/* Determine the size of an ordinary closure from its info table */
#define sizeW_fromITBL(itbl) \
  SIZEOF_StgHeader + WDS(%INFO_PTRS(itbl)) + WDS(%INFO_NPTRS(itbl))

/* NB. duplicated from InfoTables.h! */
#define BITMAP_SIZE(bitmap) ((bitmap) & BITMAP_SIZE_MASK)
#define BITMAP_BITS(bitmap) ((bitmap) >> BITMAP_BITS_SHIFT)

#define LOOKS_LIKE_PTR(p) ((p) != NULL && (p) != INVALID_GHC_POINTER)

/* Debugging macros */
#define LOOKS_LIKE_INFO_PTR(p)                                  \
   (LOOKS_LIKE_PTR(p) &&                                        \
    LOOKS_LIKE_INFO_PTR_NOT_NULL(p))

#define LOOKS_LIKE_INFO_PTR_NOT_NULL(p)                         \
   ( (TO_W_(%INFO_TYPE(%STD_INFO(p))) != INVALID_OBJECT) &&     \
     (TO_W_(%INFO_TYPE(%STD_INFO(p))) <  N_CLOSURE_TYPES))

#define LOOKS_LIKE_CLOSURE_PTR(p)                               \
   ( LOOKS_LIKE_PTR(p) &&                                       \
     LOOKS_LIKE_INFO_PTR(GET_INFO(UNTAG(p))))

/*
 * The layout of the StgFunInfoExtra part of an info table changes
 * depending on TABLES_NEXT_TO_CODE.  So we define field access
 * macros which use the appropriate version here:
 */
#if defined(TABLES_NEXT_TO_CODE)
/*
 * when TABLES_NEXT_TO_CODE, slow_apply is stored as an offset
 * instead of the normal pointer.
 */

#define StgFunInfoExtra_slow_apply(fun_info)    \
        (TO_W_(StgFunInfoExtraRev_slow_apply_offset(fun_info))    \
               + (fun_info) + SIZEOF_StgFunInfoExtraRev + SIZEOF_StgInfoTable)

#define StgFunInfoExtra_fun_type(i)   StgFunInfoExtraRev_fun_type(i)
#define StgFunInfoExtra_arity(i)      StgFunInfoExtraRev_arity(i)
#define StgFunInfoExtra_bitmap(i)     StgFunInfoExtraRev_bitmap(i)
#else
#define StgFunInfoExtra_slow_apply(i) StgFunInfoExtraFwd_slow_apply(i)
#define StgFunInfoExtra_fun_type(i)   StgFunInfoExtraFwd_fun_type(i)
#define StgFunInfoExtra_arity(i)      StgFunInfoExtraFwd_arity(i)
#define StgFunInfoExtra_bitmap(i)     StgFunInfoExtraFwd_bitmap(i)
#endif

#define mutArrCardMask ((1 << MUT_ARR_PTRS_CARD_BITS) - 1)
#define mutArrPtrCardDown(i) ((i) >> MUT_ARR_PTRS_CARD_BITS)
#define mutArrPtrCardUp(i)   (((i) + mutArrCardMask) >> MUT_ARR_PTRS_CARD_BITS)
#define mutArrPtrsCardWords(n) ROUNDUP_BYTES_TO_WDS(mutArrPtrCardUp(n))

#if defined(PROFILING) || defined(DEBUG)
#define OVERWRITING_CLOSURE_SIZE(c, size) foreign "C" stg_overwritingClosureSize(c "ptr", size)
#define OVERWRITING_CLOSURE(c) foreign "C" stg_overwritingClosure(c "ptr")
#define OVERWRITING_CLOSURE_MUTABLE(c, off) foreign "C" stg_overwritingMutableClosureOfs(c "ptr", off)
#else
#define OVERWRITING_CLOSURE_SIZE(c, size) /* nothing */
#define OVERWRITING_CLOSURE(c) /* nothing */
/* This is used to zero slop after shrunk arrays. It is important that we do
 * this whenever profiling is enabled as described in Note [slop on the heap]
 * in Storage.c. */
#define OVERWRITING_CLOSURE_MUTABLE(c, off) \
    if (TO_W_(RtsFlags_ProfFlags_doHeapProfile(RtsFlags)) != 0) { foreign "C" stg_overwritingMutableClosureOfs(c "ptr", off); }
#endif

#define IS_STACK_CLEAN(stack) \
    ((TO_W_(StgStack_dirty(stack)) & STACK_DIRTY) == 0)

/* Note [ThreadSanitizer and fences]
 * ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
 * Sadly ThreadSanitizer currently doesn't support analysis of fences.
 * Consequently, to avoid false-positive data-race reports cases which rely
 * on fences for ordering should (when TSAN_ENABLED is defined) also provide
 * explicit ordered accesses to make ordering apparent to TSAN.
 */

// Memory barriers.
// For discussion of how these are used to fence heap object
// accesses see Note [Heap memory barriers] in SMP.h.
#if defined(THREADED_RTS)
#define prim_read_barrier prim %read_barrier()
#define prim_write_barrier prim %write_barrier()

// See Note [ThreadSanitizer and fences]
#define RELEASE_FENCE prim %write_barrier()
#define ACQUIRE_FENCE prim %read_barrier()

#else

#define prim_read_barrier /* nothing */
#define prim_write_barrier /* nothing */
#define RELEASE_FENCE /* nothing */
#define ACQUIRE_FENCE /* nothing */
#endif /* THREADED_RTS */

/* -----------------------------------------------------------------------------
   Ticky macros
   -------------------------------------------------------------------------- */

#if defined(TICKY_TICKY)
#define TICK_BUMP_BY(ctr,n) W_[ctr] = W_[ctr] + n
#else
#define TICK_BUMP_BY(ctr,n) /* nothing */
#endif

#define TICK_BUMP(ctr)      TICK_BUMP_BY(ctr,1)

#define TICK_ENT_DYN_IND()              TICK_BUMP(ENT_DYN_IND_ctr)
// ENT_DYN_THK_ctr doesn't exist anymore. Could be ENT_DYN_THK_SINGLE_ctr or
// ENT_DYN_THK_MANY_ctr
// #define TICK_ENT_DYN_THK()              TICK_BUMP(ENT_DYN_THK_ctr)
#define TICK_ENT_DYN_THK()

#define TICK_ENT_VIA_NODE()             TICK_BUMP(ENT_VIA_NODE_ctr)
#define TICK_ENT_STATIC_IND()           TICK_BUMP(ENT_STATIC_IND_ctr)
#define TICK_ENT_PERM_IND()             TICK_BUMP(ENT_PERM_IND_ctr)
#define TICK_ENT_PAP()                  TICK_BUMP(ENT_PAP_ctr)
#define TICK_ENT_AP()                   TICK_BUMP(ENT_AP_ctr)
#define TICK_ENT_AP_STACK()             TICK_BUMP(ENT_AP_STACK_ctr)
#define TICK_ENT_CONTINUATION()         TICK_BUMP(ENT_CONTINUATION_ctr)
#define TICK_ENT_BH()                   TICK_BUMP(ENT_BH_ctr)
#define TICK_ENT_LNE()                  TICK_BUMP(ENT_LNE_ctr)
#define TICK_UNKNOWN_CALL()             TICK_BUMP(UNKNOWN_CALL_ctr)
#define TICK_UPDF_PUSHED()              TICK_BUMP(UPDF_PUSHED_ctr)
#define TICK_CATCHF_PUSHED()            TICK_BUMP(CATCHF_PUSHED_ctr)
#define TICK_UPDF_OMITTED()             TICK_BUMP(UPDF_OMITTED_ctr)
#define TICK_UPD_NEW_IND()              TICK_BUMP(UPD_NEW_IND_ctr)
#define TICK_UPD_NEW_PERM_IND()         TICK_BUMP(UPD_NEW_PERM_IND_ctr)
#define TICK_UPD_OLD_IND()              TICK_BUMP(UPD_OLD_IND_ctr)
#define TICK_UPD_OLD_PERM_IND()         TICK_BUMP(UPD_OLD_PERM_IND_ctr)

#define TICK_SLOW_CALL_FUN_TOO_FEW()    TICK_BUMP(SLOW_CALL_FUN_TOO_FEW_ctr)
#define TICK_SLOW_CALL_FUN_CORRECT()    TICK_BUMP(SLOW_CALL_FUN_CORRECT_ctr)
#define TICK_SLOW_CALL_FUN_TOO_MANY()   TICK_BUMP(SLOW_CALL_FUN_TOO_MANY_ctr)
#define TICK_SLOW_CALL_PAP_TOO_FEW()    TICK_BUMP(SLOW_CALL_PAP_TOO_FEW_ctr)
#define TICK_SLOW_CALL_PAP_CORRECT()    TICK_BUMP(SLOW_CALL_PAP_CORRECT_ctr)
#define TICK_SLOW_CALL_PAP_TOO_MANY()   TICK_BUMP(SLOW_CALL_PAP_TOO_MANY_ctr)

#define TICK_SLOW_CALL_fast_v16()       TICK_BUMP(SLOW_CALL_fast_v16_ctr)
#define TICK_SLOW_CALL_fast_v()         TICK_BUMP(SLOW_CALL_fast_v_ctr)
#define TICK_SLOW_CALL_fast_p()         TICK_BUMP(SLOW_CALL_fast_p_ctr)
#define TICK_SLOW_CALL_fast_pv()        TICK_BUMP(SLOW_CALL_fast_pv_ctr)
#define TICK_SLOW_CALL_fast_pp()        TICK_BUMP(SLOW_CALL_fast_pp_ctr)
#define TICK_SLOW_CALL_fast_ppv()       TICK_BUMP(SLOW_CALL_fast_ppv_ctr)
#define TICK_SLOW_CALL_fast_ppp()       TICK_BUMP(SLOW_CALL_fast_ppp_ctr)
#define TICK_SLOW_CALL_fast_pppv()      TICK_BUMP(SLOW_CALL_fast_pppv_ctr)
#define TICK_SLOW_CALL_fast_pppp()      TICK_BUMP(SLOW_CALL_fast_pppp_ctr)
#define TICK_SLOW_CALL_fast_ppppp()     TICK_BUMP(SLOW_CALL_fast_ppppp_ctr)
#define TICK_SLOW_CALL_fast_pppppp()    TICK_BUMP(SLOW_CALL_fast_pppppp_ctr)
#define TICK_VERY_SLOW_CALL()           TICK_BUMP(VERY_SLOW_CALL_ctr)

/* NOTE: TICK_HISTO_BY and TICK_HISTO
   currently have no effect.
   The old code for it didn't typecheck and I
   just commented it out to get ticky to work.
   - krc 1/2007 */

#define TICK_HISTO_BY(histo,n,i) /* nothing */

#define TICK_HISTO(histo,n) TICK_HISTO_BY(histo,n,1)

/* An unboxed tuple with n components. */
#define TICK_RET_UNBOXED_TUP(n)                 \
  TICK_BUMP(RET_UNBOXED_TUP_ctr++);             \
  TICK_HISTO(RET_UNBOXED_TUP,n)

/*
 * A slow call with n arguments.  In the unevald case, this call has
 * already been counted once, so don't count it again.
 */
#define TICK_SLOW_CALL(n)                       \
  TICK_BUMP(SLOW_CALL_ctr);                     \
  TICK_HISTO(SLOW_CALL,n)

/*
 * This slow call was found to be to an unevaluated function; undo the
 * ticks we did in TICK_SLOW_CALL.
 */
#define TICK_SLOW_CALL_UNEVALD(n)               \
  TICK_BUMP(SLOW_CALL_UNEVALD_ctr);             \
  TICK_BUMP_BY(SLOW_CALL_ctr,-1);               \
  TICK_HISTO_BY(SLOW_CALL,n,-1);

/* Updating a closure with a new CON */
#define TICK_UPD_CON_IN_NEW(n)                  \
  TICK_BUMP(UPD_CON_IN_NEW_ctr);                \
  TICK_HISTO(UPD_CON_IN_NEW,n)

#define TICK_ALLOC_RTS(bytes)            \
    TICK_BUMP(ALLOC_RTS_ctr);                   \
    TICK_BUMP_BY(ALLOC_RTS_tot,bytes)

/* -----------------------------------------------------------------------------
   Misc junk
   -------------------------------------------------------------------------- */

#define NO_TREC                   stg_NO_TREC_closure
#define END_TSO_QUEUE             stg_END_TSO_QUEUE_closure
#define STM_AWOKEN                stg_STM_AWOKEN_closure

#define recordMutableCap(p, gen)                                        \
  W_ __bd;                                                              \
  W_ mut_list;                                                          \
  mut_list = Capability_mut_lists(MyCapability()) + WDS(gen);           \
 __bd = W_[mut_list];                                                   \
  if (bdescr_free(__bd) >= bdescr_start(__bd) + BLOCK_SIZE) {           \
      W_ __new_bd;                                                      \
      ("ptr" __new_bd) = foreign "C" allocBlock_lock();                 \
      bdescr_link(__new_bd) = __bd;                                     \
      __bd = __new_bd;                                                  \
      W_[mut_list] = __bd;                                              \
  }                                                                     \
  W_ free;                                                              \
  free = bdescr_free(__bd);                                             \
  W_[free] = p;                                                         \
  bdescr_free(__bd) = free + WDS(1);

#define recordMutable(p)                                        \
      P_ __p;                                                   \
      W_ __bd;                                                  \
      W_ __gen;                                                 \
      __p = p;                                                  \
      __bd = Bdescr(__p);                                       \
      __gen = TO_W_(bdescr_gen_no(__bd));                       \
      if (__gen > 0) { recordMutableCap(__p, __gen); }


/* -----------------------------------------------------------------------------
   Arrays
   -------------------------------------------------------------------------- */

/* Complete function body for the clone family of (mutable) array ops.
   Defined as a macro to avoid function call overhead or code
   duplication. */
#define cloneArray(info, src, offset, n)                       \
    W_ words, size;                                            \
    gcptr dst, dst_p, src_p;                                   \
                                                               \
    again: MAYBE_GC(again);                                    \
                                                               \
    size = n + mutArrPtrsCardWords(n);                         \
    words = BYTES_TO_WDS(SIZEOF_StgMutArrPtrs) + size;         \
    ("ptr" dst) = ccall allocate(MyCapability() "ptr", words); \
    TICK_ALLOC_PRIM(SIZEOF_StgMutArrPtrs, WDS(size), 0);       \
                                                               \
    SET_HDR(dst, info, CCCS);                                  \
    StgMutArrPtrs_ptrs(dst) = n;                               \
    StgMutArrPtrs_size(dst) = size;                            \
                                                               \
    dst_p = dst + SIZEOF_StgMutArrPtrs;                        \
    src_p = src + SIZEOF_StgMutArrPtrs + WDS(offset);          \
    prim %memcpy(dst_p, src_p, n * SIZEOF_W, SIZEOF_W);        \
                                                               \
    return (dst);

#define copyArray(src, src_off, dst, dst_off, n)                  \
  W_ dst_elems_p, dst_p, src_p, bytes;                            \
                                                                  \
    if ((n) != 0) {                                               \
        SET_HDR(dst, stg_MUT_ARR_PTRS_DIRTY_info, CCCS);          \
                                                                  \
        dst_elems_p = (dst) + SIZEOF_StgMutArrPtrs;               \
        dst_p = dst_elems_p + WDS(dst_off);                       \
        src_p = (src) + SIZEOF_StgMutArrPtrs + WDS(src_off);      \
        bytes = WDS(n);                                           \
                                                                  \
        prim %memcpy(dst_p, src_p, bytes, SIZEOF_W);              \
                                                                  \
        setCards(dst, dst_off, n);                                \
    }                                                             \
                                                                  \
    return ();

#define copyMutableArray(src, src_off, dst, dst_off, n)           \
  W_ dst_elems_p, dst_p, src_p, bytes;                            \
                                                                  \
    if ((n) != 0) {                                               \
        SET_HDR(dst, stg_MUT_ARR_PTRS_DIRTY_info, CCCS);          \
                                                                  \
        dst_elems_p = (dst) + SIZEOF_StgMutArrPtrs;               \
        dst_p = dst_elems_p + WDS(dst_off);                       \
        src_p = (src) + SIZEOF_StgMutArrPtrs + WDS(src_off);      \
        bytes = WDS(n);                                           \
                                                                  \
        if ((src) == (dst)) {                                     \
            prim %memmove(dst_p, src_p, bytes, SIZEOF_W);         \
        } else {                                                  \
            prim %memcpy(dst_p, src_p, bytes, SIZEOF_W);          \
        }                                                         \
                                                                  \
        setCards(dst, dst_off, n);                                \
    }                                                             \
                                                                  \
    return ();

/*
 * Set the cards in the array pointed to by arr for an
 * update to n elements, starting at element dst_off.
 */
#define setCards(arr, dst_off, n)                                \
  setCardsValue(arr, dst_off, n, 1)

/*
 * Set the cards in the array pointed to by arr for an
 * update to n elements, starting at element dst_off to value (0 to indicate
 * clean, 1 to indicate dirty). n must be non-zero.
 */
#define setCardsValue(arr, dst_off, n, value)                                    \
    W_ __start_card, __end_card, __cards, __dst_cards_p;                         \
    ASSERT(n != 0); \
    __dst_cards_p = (arr) + SIZEOF_StgMutArrPtrs + WDS(StgMutArrPtrs_ptrs(arr)); \
    __start_card = mutArrPtrCardDown(dst_off);                                   \
    __end_card = mutArrPtrCardDown((dst_off) + (n) - 1);                         \
    __cards = __end_card - __start_card + 1;                                     \
    prim %memset(__dst_cards_p + __start_card, (value), __cards, 1)

/* Complete function body for the clone family of small (mutable)
   array ops. Defined as a macro to avoid function call overhead or
   code duplication. */
#define cloneSmallArray(info, src, offset, n)                  \
    W_ words, size;                                            \
    gcptr dst, dst_p, src_p;                                   \
                                                               \
    again: MAYBE_GC(again);                                    \
                                                               \
    words = BYTES_TO_WDS(SIZEOF_StgSmallMutArrPtrs) + n;       \
    ("ptr" dst) = ccall allocate(MyCapability() "ptr", words); \
    TICK_ALLOC_PRIM(SIZEOF_StgSmallMutArrPtrs, WDS(n), 0);     \
                                                               \
    SET_HDR(dst, info, CCCS);                                  \
    StgSmallMutArrPtrs_ptrs(dst) = n;                          \
                                                               \
    dst_p = dst + SIZEOF_StgSmallMutArrPtrs;                   \
    src_p = src + SIZEOF_StgSmallMutArrPtrs + WDS(offset);     \
    prim %memcpy(dst_p, src_p, n * SIZEOF_W, SIZEOF_W);        \
                                                               \
    return (dst);


//
// Nonmoving write barrier helpers
//
// See Note [Update remembered set] in NonMovingMark.c.

#if defined(THREADED_RTS)
#define IF_NONMOVING_WRITE_BARRIER_ENABLED                     \
    if (W_[nonmoving_write_barrier_enabled] != 0) (likely: False)
#else
// A similar measure is also taken in rts/NonMoving.h, but that isn't visible from C--
#define IF_NONMOVING_WRITE_BARRIER_ENABLED                     \
    if (0)
#define nonmoving_write_barrier_enabled 0
#endif

// A useful helper for pushing a pointer to the update remembered set.
#define updateRemembSetPushPtr(p)                                    \
    IF_NONMOVING_WRITE_BARRIER_ENABLED {                             \
      ccall updateRemembSetPushClosure_(BaseReg "ptr", p "ptr");     \
    }

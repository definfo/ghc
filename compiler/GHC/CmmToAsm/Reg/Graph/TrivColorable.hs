module GHC.CmmToAsm.Reg.Graph.TrivColorable (
        trivColorable,
)

where

import GHC.Prelude

import GHC.Platform.Reg.Class
import GHC.Platform.Reg

import GHC.Data.Graph.Base

import GHC.Types.Unique.Set
import GHC.Platform
import GHC.Utils.Panic

-- trivColorable ---------------------------------------------------------------

-- trivColorable function for the graph coloring allocator
--
--      This gets hammered by scanGraph during register allocation,
--      so needs to be fairly efficient.
--
--      NOTE:   This only works for architectures with just RcInteger and RcDouble
--              (which are disjoint) ie. x86, x86_64 and ppc
--
--      The number of allocatable regs is hard coded in here so we can do
--              a fast comparison in trivColorable.
--
--      It's ok if these numbers are _less_ than the actual number of free
--              regs, but they can't be more or the register conflict
--              graph won't color.
--
--      If the graph doesn't color then the allocator will panic, but it won't
--              generate bad object code or anything nasty like that.
--
--      There is an allocatableRegsInClass :: RegClass -> Int, but doing
--      the unboxing is too slow for us here.
--      TODO: Is that still true? Could we use allocatableRegsInClass
--      without losing performance now?
--
--      Look at rts/include/stg/MachRegs.h to get the numbers.
--


-- Disjoint registers ----------------------------------------------------------
--
--      The definition has been unfolded into individual cases for speed.
--      Each architecture has a different register setup, so we use a
--      different regSqueeze function for each.
--
accSqueeze
        :: Int
        -> Int
        -> (reg -> Int)
        -> UniqSet reg
        -> Int

accSqueeze count maxCount squeeze us = acc count (nonDetEltsUniqSet us)
  -- See Note [Unique Determinism and code generation]
  where acc count [] = count
        acc count _ | count >= maxCount = count
        acc count (r:rs) = acc (count + squeeze r) rs

{- Note [accSqueeze]
~~~~~~~~~~~~~~~~~~~~
BL 2007/09
Doing a nice fold over the UniqSet makes trivColorable use
32% of total compile time and 42% of total alloc when compiling SHA1.hs from darcs.
Therefore the UniqFM is made non-abstract and we use custom fold.

MS 2010/04
When converting UniqFM to use Data.IntMap, the fold cannot use UniqFM internal
representation any more. But it is imperative that the accSqueeze stops
the folding if the count gets greater or equal to maxCount. We thus convert
UniqFM to a (lazy) list, do the fold and stops if necessary, which was
the most efficient variant tried. Benchmark compiling 10-times SHA1.hs follows.
(original = previous implementation, folding = fold of the whole UFM,
 lazyFold = the current implementation,
 hackFold = using internal representation of Data.IntMap)

                                 original  folding   hackFold  lazyFold
 -O -fasm (used everywhere)      31.509s   30.387s   30.791s   30.603s
                                 100.00%   96.44%    97.72%    97.12%
 -fregs-graph                    67.938s   74.875s   62.673s   64.679s
                                 100.00%   110.21%   92.25%    95.20%
 -fregs-iterative                89.761s   143.913s  81.075s   86.912s
                                 100.00%   160.33%   90.32%    96.83%
 -fnew-codegen                   38.225s   37.142s   37.551s   37.119s
                                 100.00%   97.17%    98.24%    97.11%
 -fnew-codegen -fregs-graph      91.786s   91.51s    87.368s   86.88s
                                 100.00%   99.70%    95.19%    94.65%
 -fnew-codegen -fregs-iterative  206.72s   343.632s  194.694s  208.677s
                                 100.00%   166.23%   94.18%    100.95%
-}

trivColorable
        :: Platform
        -> (RegClass -> VirtualReg -> Int)
        -> (RegClass -> RealReg    -> Int)
        -> Triv VirtualReg RegClass RealReg

trivColorable platform virtualRegSqueeze realRegSqueeze RcInteger conflicts exclusions
        | let cALLOCATABLE_REGS_INTEGER
                  =        (case platformArch platform of
                            ArchX86       -> 3
                            ArchX86_64    -> 5
                            ArchPPC       -> 16
                            ArchPPC_64 _  -> 15
                            ArchARM _ _ _ -> panic "trivColorable ArchARM"
                            -- N.B. x18 is reserved by the platform on AArch64/Darwin
                            ArchAArch64   -> 17
                            ArchAlpha     -> panic "trivColorable ArchAlpha"
                            ArchMipseb    -> panic "trivColorable ArchMipseb"
                            ArchMipsel    -> panic "trivColorable ArchMipsel"
                            ArchS390X     -> panic "trivColorable ArchS390X"
                            ArchRISCV64   -> 14
                            ArchLoongArch64->panic "trivColorable ArchLoongArch64"
                            ArchJavaScript-> panic "trivColorable ArchJavaScript"
                            ArchWasm32    -> panic "trivColorable ArchWasm32"
                            ArchUnknown   -> panic "trivColorable ArchUnknown")
        , count2        <- accSqueeze 0 cALLOCATABLE_REGS_INTEGER
                                (virtualRegSqueeze RcInteger)
                                conflicts

        , count3        <- accSqueeze  count2    cALLOCATABLE_REGS_INTEGER
                                (realRegSqueeze   RcInteger)
                                exclusions

        = count3 < cALLOCATABLE_REGS_INTEGER

trivColorable platform virtualRegSqueeze realRegSqueeze RcFloat conflicts exclusions
        | let cALLOCATABLE_REGS_FLOAT
                  =        (case platformArch platform of
                    -- On x86_64 and x86, Float and RcDouble
                    -- use the same registers,
                    -- so we only use RcDouble to represent the
                    -- register allocation problem on those types.
                            ArchX86       -> 0
                            ArchX86_64    -> 0
                            ArchPPC       -> 0
                            ArchPPC_64 _  -> 0
                            ArchARM _ _ _ -> panic "trivColorable ArchARM"
                            -- we can in principle address all the float regs as
                            -- segments. So we could have 64 Float regs. Or
                            -- 128 Half regs, or even 256 Byte regs.
                            ArchAArch64   -> 0
                            ArchAlpha     -> panic "trivColorable ArchAlpha"
                            ArchMipseb    -> panic "trivColorable ArchMipseb"
                            ArchMipsel    -> panic "trivColorable ArchMipsel"
                            ArchS390X     -> panic "trivColorable ArchS390X"
                            ArchRISCV64   -> 0
                            ArchLoongArch64->panic "trivColorable ArchLoongArch64"
                            ArchJavaScript-> panic "trivColorable ArchJavaScript"
                            ArchWasm32    -> panic "trivColorable ArchWasm32"
                            ArchUnknown   -> panic "trivColorable ArchUnknown")
        , count2        <- accSqueeze 0 cALLOCATABLE_REGS_FLOAT
                                (virtualRegSqueeze RcFloat)
                                conflicts

        , count3        <- accSqueeze  count2    cALLOCATABLE_REGS_FLOAT
                                (realRegSqueeze   RcFloat)
                                exclusions

        = count3 < cALLOCATABLE_REGS_FLOAT

trivColorable platform virtualRegSqueeze realRegSqueeze RcDouble conflicts exclusions
        | let cALLOCATABLE_REGS_DOUBLE
                  =        (case platformArch platform of
                            ArchX86       -> 8
                            -- in x86 32bit mode sse2 there are only
                            -- 8 XMM registers xmm0 ... xmm7
                            ArchX86_64    -> 10
                            -- in x86_64 there are 16 XMM registers
                            -- xmm0 .. xmm15, here 10 is a
                            -- "dont need to solve conflicts" count that
                            -- was chosen at some point in the past.
                            ArchPPC       -> 26
                            ArchPPC_64 _  -> 20
                            ArchARM _ _ _ -> panic "trivColorable ArchARM"
                            ArchAArch64   -> 24 -- 32 - F1 .. F4, D1..D4 - it's odd but see Note [AArch64 Register assignments] for our reg use.
                                                -- Seems we reserve different registers for D1..D4 and F1 .. F4 somehow, we should fix this.
                            ArchAlpha     -> panic "trivColorable ArchAlpha"
                            ArchMipseb    -> panic "trivColorable ArchMipseb"
                            ArchMipsel    -> panic "trivColorable ArchMipsel"
                            ArchS390X     -> panic "trivColorable ArchS390X"
                            ArchRISCV64   -> 20
                            ArchLoongArch64->panic "trivColorable ArchLoongArch64"
                            ArchJavaScript-> panic "trivColorable ArchJavaScript"
                            ArchWasm32    -> panic "trivColorable ArchWasm32"
                            ArchUnknown   -> panic "trivColorable ArchUnknown")
        , count2        <- accSqueeze 0 cALLOCATABLE_REGS_DOUBLE
                                (virtualRegSqueeze RcDouble)
                                conflicts

        , count3        <- accSqueeze  count2    cALLOCATABLE_REGS_DOUBLE
                                (realRegSqueeze   RcDouble)
                                exclusions

        = count3 < cALLOCATABLE_REGS_DOUBLE




-- Specification Code ----------------------------------------------------------
--
--      The trivColorable function for each particular architecture should
--      implement the following function, but faster.
--

{-
trivColorable :: RegClass -> UniqSet Reg -> UniqSet Reg -> Bool
trivColorable classN conflicts exclusions
 = let

        acc :: Reg -> (Int, Int) -> (Int, Int)
        acc r (cd, cf)
         = case regClass r of
                RcInteger       -> (cd+1, cf)
                RcFloat         -> (cd,   cf+1)
                _               -> panic "Regs.trivColorable: reg class not handled"

        tmp                     = nonDetFoldUFM acc (0, 0) conflicts
        (countInt,  countFloat) = nonDetFoldUFM acc tmp    exclusions

        squeese         = worst countInt   classN RcInteger
                        + worst countFloat classN RcFloat

   in   squeese < allocatableRegsInClass classN

-- | Worst case displacement
--      node N of classN has n neighbors of class C.
--
--      We currently only have RcInteger and RcDouble, which don't conflict at all.
--      This is a bit boring compared to what's in RegArchX86.
--
worst :: Int -> RegClass -> RegClass -> Int
worst n classN classC
 = case classN of
        RcInteger
         -> case classC of
                RcInteger       -> min n (allocatableRegsInClass RcInteger)
                RcFloat         -> 0

        RcDouble
         -> case classC of
                RcFloat         -> min n (allocatableRegsInClass RcFloat)
                RcInteger       -> 0

-- allocatableRegs is allMachRegNos with the fixed-use regs removed.
-- i.e., these are the regs for which we are prepared to allow the
-- register allocator to attempt to map VRegs to.
allocatableRegs :: [RegNo]
allocatableRegs
   = let isFree i = freeReg i
     in  filter isFree allMachRegNos


-- | The number of regs in each class.
--      We go via top level CAFs to ensure that we're not recomputing
--      the length of these lists each time the fn is called.
allocatableRegsInClass :: RegClass -> Int
allocatableRegsInClass cls
 = case cls of
        RcInteger       -> allocatableRegsInteger
        RcFloat         -> allocatableRegsDouble

allocatableRegsInteger :: Int
allocatableRegsInteger
        = length $ filter (\r -> regClass r == RcInteger)
                 $ map RealReg allocatableRegs

allocatableRegsFloat :: Int
allocatableRegsFloat
        = length $ filter (\r -> regClass r == RcFloat
                 $ map RealReg allocatableRegs
-}

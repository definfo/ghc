module GHC.HsToCore.Breakpoints
  ( mkModBreaks
  ) where

import GHC.Prelude

import qualified GHC.Runtime.Interpreter as GHCi
import GHC.Runtime.Interpreter.Types
import GHCi.RemoteTypes
import GHC.ByteCode.Types
import GHC.Stack.CCS
import GHC.Unit

import GHC.HsToCore.Ticks (Tick (..))

import GHC.Data.SizedSeq
import GHC.Utils.Outputable as Outputable

import Data.List (intersperse)
import Data.Array

mkModBreaks :: Interp -> Module -> SizedSeq Tick -> IO ModBreaks
mkModBreaks interp mod extendedMixEntries
  = do
    let count = fromIntegral $ sizeSS extendedMixEntries
        entries = ssElts extendedMixEntries

    breakArray <- GHCi.newBreakArray interp count
    ccs <- mkCCSArray interp mod count entries
    mod_ptr <- GHCi.newModuleName interp (moduleName mod)
    let
           locsTicks  = listArray (0,count-1) [ tick_loc  t | t <- entries ]
           varsTicks  = listArray (0,count-1) [ tick_ids  t | t <- entries ]
           declsTicks = listArray (0,count-1) [ tick_path t | t <- entries ]
    return $ emptyModBreaks
                       { modBreaks_flags  = breakArray
                       , modBreaks_locs   = locsTicks
                       , modBreaks_vars   = varsTicks
                       , modBreaks_decls  = declsTicks
                       , modBreaks_ccs    = ccs
                       , modBreaks_module = mod_ptr
                       }

mkCCSArray
  :: Interp -> Module -> Int -> [Tick]
  -> IO (Array BreakIndex (RemotePtr GHC.Stack.CCS.CostCentre))
mkCCSArray interp modul count entries
  | GHCi.interpreterProfiled interp = do
      let module_str = moduleNameString (moduleName modul)
      costcentres <- GHCi.mkCostCentres interp module_str (map mk_one entries)
      return (listArray (0,count-1) costcentres)
  | otherwise = return (listArray (0,-1) [])
 where
    mk_one t = (name, src)
      where name = concat $ intersperse "." $ tick_path t
            src = renderWithContext defaultSDocContext $ ppr $ tick_loc t


{-# LANGUAGE NondecreasingIndentation #-}

{-
(c) The University of Glasgow 2006-2008
(c) The GRASP/AQUA Project, Glasgow University, 1993-1998
-}

-- | Module for constructing @ModIface@ values (interface files),
-- writing them to disk and comparing two versions to see if
-- recompilation is required.
module GHC.Iface.Make
   ( mkPartialIface
   , mkFullIface
   , mkIfaceTc
   , mkIfaceExports
   )
where

import GHC.Prelude

import GHC.Hs

import GHC.Stg.InferTags.TagSig (StgCgInfos)
import GHC.StgToCmm.Types (CmmCgInfos (..))

import GHC.Tc.Utils.TcType
import GHC.Tc.Utils.Monad

import GHC.Iface.Decl
import GHC.Iface.Syntax
import GHC.Iface.Recomp
import GHC.Iface.Load
import GHC.Iface.Ext.Fields

import GHC.CoreToIface

import qualified GHC.LanguageExtensions as LangExt
import GHC.Core
import GHC.Core.Class
import GHC.Core.Coercion.Axiom
import GHC.Core.ConLike
import GHC.Core.InstEnv
import GHC.Core.FamInstEnv
import GHC.Core.Ppr
import GHC.Core.RoughMap( RoughMatchTc(..) )

import GHC.Driver.Config.HsToCore.Usage
import GHC.Driver.Env
import GHC.Driver.Backend
import GHC.Driver.DynFlags
import GHC.Driver.Plugins

import GHC.Types.Id
import GHC.Types.Fixity.Env
import GHC.Types.SafeHaskell
import GHC.Types.Annotations
import GHC.Types.Name
import GHC.Types.Avail
import GHC.Types.Name.Reader
import GHC.Types.Name.Env
import GHC.Types.Name.Set
import GHC.Types.Unique.DSet
import GHC.Types.TypeEnv
import GHC.Types.SourceFile
import GHC.Types.TyThing
import GHC.Types.HpcInfo
import GHC.Types.CompleteMatch
import GHC.Types.SourceText
import GHC.Types.SrcLoc ( unLoc )

import GHC.Utils.Outputable
import GHC.Utils.Panic
import GHC.Utils.Panic.Plain
import GHC.Utils.Logger

import GHC.Data.FastString
import GHC.Data.Maybe

import GHC.HsToCore.Docs
import GHC.HsToCore.Usage

import GHC.Unit
import GHC.Unit.Module.Warnings
import GHC.Unit.Module.ModIface
import GHC.Unit.Module.ModDetails
import GHC.Unit.Module.ModGuts
import GHC.Unit.Module.ModSummary
import GHC.Unit.Module.Deps

import Data.Function
import Data.List ( sortBy )
import Data.Ord
import Data.IORef


{-
************************************************************************
*                                                                      *
\subsection{Completing an interface}
*                                                                      *
************************************************************************
-}

mkPartialIface :: HscEnv
               -> CoreProgram
               -> ModDetails
               -> ModSummary
               -> ModGuts
               -> PartialModIface
mkPartialIface hsc_env core_prog mod_details mod_summary
  ModGuts{ mg_module       = this_mod
         , mg_hsc_src      = hsc_src
         , mg_usages       = usages
         , mg_used_th      = used_th
         , mg_deps         = deps
         , mg_rdr_env      = rdr_env
         , mg_fix_env      = fix_env
         , mg_warns        = warns
         , mg_hpc_info     = hpc_info
         , mg_safe_haskell = safe_mode
         , mg_trust_pkg    = self_trust
         , mg_docs         = docs
         }
  = mkIface_ hsc_env this_mod core_prog hsc_src used_th deps rdr_env fix_env warns hpc_info self_trust
             safe_mode usages docs mod_summary mod_details

-- | Fully instantiate an interface. Adds fingerprints and potentially code
-- generator produced information.
--
-- CmmCgInfos is not available when not generating code (-fno-code), or when not
-- generating interface pragmas (-fomit-interface-pragmas). See also
-- Note [Conveying CAF-info and LFInfo between modules] in GHC.StgToCmm.Types.
mkFullIface :: HscEnv -> PartialModIface -> Maybe StgCgInfos -> Maybe CmmCgInfos -> IO ModIface
mkFullIface hsc_env partial_iface mb_stg_infos mb_cmm_infos = do
    let decls
          | gopt Opt_OmitInterfacePragmas (hsc_dflags hsc_env)
          = mi_decls partial_iface
          | otherwise
          = updateDecl (mi_decls partial_iface) mb_stg_infos mb_cmm_infos

    full_iface <-
      {-# SCC "addFingerprints" #-}
      addFingerprints hsc_env partial_iface{ mi_decls = decls }

    -- Debug printing
    let unit_state = hsc_units hsc_env
    putDumpFileMaybe (hsc_logger hsc_env) Opt_D_dump_hi "FINAL INTERFACE" FormatText
      (pprModIface unit_state full_iface)

    return full_iface

updateDecl :: [IfaceDecl] -> Maybe StgCgInfos -> Maybe CmmCgInfos -> [IfaceDecl]
updateDecl decls Nothing Nothing = decls
updateDecl decls m_stg_infos m_cmm_infos
  = map update_decl decls
  where
    (non_cafs,lf_infos) = maybe (mempty, mempty)
                                (\cmm_info -> (ncs_nameSet (cgNonCafs cmm_info), cgLFInfos cmm_info))
                                m_cmm_infos
    tag_sigs = fromMaybe mempty m_stg_infos

    update_decl (IfaceId nm ty details infos)
      | let not_caffy = elemNameSet nm non_cafs
      , let mb_lf_info = lookupNameEnv lf_infos nm
      , let sig = lookupNameEnv tag_sigs nm
      , warnPprTrace (isNothing mb_lf_info) "updateDecl" (text "Name without LFInfo:" <+> ppr nm) True
        -- Only allocate a new IfaceId if we're going to update the infos
      , isJust mb_lf_info || not_caffy || isJust sig
      = IfaceId nm ty details $
          (if not_caffy then (HsNoCafRefs :) else id) $
          (if isJust sig then (HsTagSig (fromJust sig):) else id) $
          (case mb_lf_info of
             Nothing -> infos -- LFInfos not available when building .cmm files
             Just lf_info -> HsLFInfo (toIfaceLFInfo nm lf_info) : infos)

    update_decl decl
      = decl




-- | Make an interface from the results of typechecking only.  Useful
-- for non-optimising compilation, or where we aren't generating any
-- object code at all ('NoBackend').
mkIfaceTc :: HscEnv
          -> SafeHaskellMode    -- The safe haskell mode
          -> ModDetails         -- gotten from mkBootModDetails, probably
          -> ModSummary
          -> Maybe CoreProgram
          -> TcGblEnv           -- Usages, deprecations, etc
          -> IO ModIface
mkIfaceTc hsc_env safe_mode mod_details mod_summary mb_program
  tc_result@TcGblEnv{ tcg_mod = this_mod,
                      tcg_src = hsc_src,
                      tcg_imports = imports,
                      tcg_rdr_env = rdr_env,
                      tcg_fix_env = fix_env,
                      tcg_merged = merged,
                      tcg_warns = warns,
                      tcg_hpc = other_hpc_info,
                      tcg_th_splice_used = tc_splice_used,
                      tcg_dependent_files = dependent_files
                    }
  = do
          let used_names = mkUsedNames tc_result
          let pluginModules = map lpModule (loadedPlugins (hsc_plugins hsc_env))
          let home_unit = hsc_home_unit hsc_env
          let deps = mkDependencies home_unit
                                    (tcg_mod tc_result)
                                    (tcg_imports tc_result)
                                    (map mi_module pluginModules)
          let hpc_info = emptyHpcInfo other_hpc_info
          used_th <- readIORef tc_splice_used
          dep_files <- (readIORef dependent_files)
          (needed_links, needed_pkgs) <- readIORef (tcg_th_needed_deps tc_result)
          let uc = initUsageConfig hsc_env
              plugins = hsc_plugins hsc_env
              fc = hsc_FC hsc_env
              unit_env = hsc_unit_env hsc_env
          -- Do NOT use semantic module here; this_mod in mkUsageInfo
          -- is used solely to decide if we should record a dependency
          -- or not.  When we instantiate a signature, the semantic
          -- module is something we want to record dependencies for,
          -- but if you pass that in here, we'll decide it's the local
          -- module and does not need to be recorded as a dependency.
          -- See Note [Identity versus semantic module]
          usages <- initIfaceLoad hsc_env $ mkUsageInfo uc plugins fc unit_env this_mod (imp_mods imports) used_names
                      dep_files merged needed_links needed_pkgs

          docs <- extractDocs (ms_hspp_opts mod_summary) tc_result

          let partial_iface = mkIface_ hsc_env
                   this_mod (fromMaybe [] mb_program) hsc_src
                   used_th deps rdr_env
                   fix_env warns hpc_info
                   (imp_trust_own_pkg imports) safe_mode usages
                   docs mod_summary
                   mod_details

          mkFullIface hsc_env partial_iface Nothing Nothing

mkIface_ :: HscEnv -> Module -> CoreProgram -> HscSource
         -> Bool -> Dependencies -> GlobalRdrEnv
         -> NameEnv FixItem -> Warnings GhcRn -> HpcInfo
         -> Bool
         -> SafeHaskellMode
         -> [Usage]
         -> Maybe Docs
         -> ModSummary
         -> ModDetails
         -> PartialModIface
mkIface_ hsc_env
         this_mod core_prog hsc_src used_th deps rdr_env fix_env src_warns
         hpc_info pkg_trust_req safe_mode usages
         docs mod_summary
         ModDetails{  md_insts     = insts,
                      md_fam_insts = fam_insts,
                      md_rules     = rules,
                      md_anns      = anns,
                      md_types     = type_env,
                      md_exports   = exports,
                      md_complete_matches = complete_matches }
-- NB:  notice that mkIface does not look at the bindings
--      only at the TypeEnv.  The previous Tidy phase has
--      put exactly the info into the TypeEnv that we want
--      to expose in the interface

  = do
    let home_unit    = hsc_home_unit hsc_env
        semantic_mod = homeModuleNameInstantiation home_unit (moduleName this_mod)
        entities = typeEnvElts type_env
        show_linear_types = xopt LangExt.LinearTypes (hsc_dflags hsc_env)

        extra_decls = if gopt Opt_WriteIfSimplifiedCore dflags then Just [ toIfaceTopBind b | b <- core_prog ]
                                                               else Nothing
        decls  = [ tyThingToIfaceDecl show_linear_types entity
                 | entity <- entities,
                   let name = getName entity,
                   not (isImplicitTyThing entity),
                      -- No implicit Ids and class tycons in the interface file
                   not (isWiredInName name),
                      -- Nor wired-in things; the compiler knows about them anyhow
                   nameIsLocalOrFrom semantic_mod name  ]
                      -- Sigh: see Note [Root-main Id] in GHC.Tc.Module
                      -- NB: ABSOLUTELY need to check against semantic_mod,
                      -- because all of the names in an hsig p[H=<H>]:H
                      -- are going to be for <H>, not the former id!
                      -- See Note [Identity versus semantic module]

        fixities    = sortBy (comparing fst)
          [(occ,fix) | FixItem occ fix <- nonDetNameEnvElts fix_env]
          -- The order of fixities returned from nonDetNameEnvElts is not
          -- deterministic, so we sort by OccName to canonicalize it.
          -- See Note [Deterministic UniqFM] in GHC.Types.Unique.DFM for more details.
        warns       = toIfaceWarnings src_warns
        iface_rules = map coreRuleToIfaceRule rules
        iface_insts = map instanceToIfaceInst $ fixSafeInstances safe_mode (instEnvElts insts)
        iface_fam_insts = map famInstToIfaceFamInst fam_insts
        trust_info  = setSafeMode safe_mode
        annotations = map mkIfaceAnnotation anns
        icomplete_matches = map mkIfaceCompleteMatch complete_matches
        !rdrs = maybeGlobalRdrEnv rdr_env

    ModIface {
          mi_module      = this_mod,
          -- Need to record this because it depends on the -instantiated-with flag
          -- which could change
          mi_sig_of      = if semantic_mod == this_mod
                            then Nothing
                            else Just semantic_mod,
          mi_hsc_src     = hsc_src,
          mi_deps        = deps,
          mi_usages      = usages,
          mi_exports     = mkIfaceExports exports,

          -- Sort these lexicographically, so that
          -- the result is stable across compilations
          mi_insts       = sortBy cmp_inst     iface_insts,
          mi_fam_insts   = sortBy cmp_fam_inst iface_fam_insts,
          mi_rules       = sortBy cmp_rule     iface_rules,

          mi_fixities    = fixities,
          mi_warns       = warns,
          mi_anns        = annotations,
          mi_globals     = rdrs,
          mi_used_th     = used_th,
          mi_decls       = decls,
          mi_extra_decls = extra_decls,
          mi_hpc         = isHpcUsed hpc_info,
          mi_trust       = trust_info,
          mi_trust_pkg   = pkg_trust_req,
          mi_complete_matches = icomplete_matches,
          mi_docs        = docs,
          mi_final_exts  = (),
          mi_ext_fields  = emptyExtensibleFields,
          mi_src_hash = ms_hs_hash mod_summary
          }
  where
     cmp_rule     = lexicalCompareFS `on` ifRuleName
     -- Compare these lexicographically by OccName, *not* by unique,
     -- because the latter is not stable across compilations:
     cmp_inst     = comparing (nameOccName . ifDFun)
     cmp_fam_inst = comparing (nameOccName . ifFamInstTcName)

     dflags = hsc_dflags hsc_env

     -- We only fill in mi_globals if the module was compiled to byte
     -- code.  Otherwise, the compiler may not have retained all the
     -- top-level bindings and they won't be in the TypeEnv (see
     -- Desugar.addExportFlagsAndRules).  The mi_globals field is used
     -- by GHCi to decide whether the module has its full top-level
     -- scope available. (#5534)
     maybeGlobalRdrEnv :: GlobalRdrEnv -> Maybe IfGlobalRdrEnv
     maybeGlobalRdrEnv rdr_env
        | backendWantsGlobalBindings (backend dflags)
        = Just $! forceGlobalRdrEnv rdr_env
          -- See Note [Forcing GREInfo] in GHC.Types.GREInfo.
        | otherwise
        = Nothing

     ifFamInstTcName = ifFamInstFam


--------------------------
instanceToIfaceInst :: ClsInst -> IfaceClsInst
instanceToIfaceInst (ClsInst { is_dfun = dfun_id, is_flag = oflag
                             , is_cls_nm = cls_name, is_cls = cls
                             , is_tcs = rough_tcs
                             , is_orphan = orph })
  = assert (cls_name == className cls) $
    IfaceClsInst { ifDFun     = idName dfun_id
                 , ifOFlag    = oflag
                 , ifInstCls  = cls_name
                 , ifInstTys  = ifaceRoughMatchTcs $ tail rough_tcs
                   -- N.B. Drop the class name from the rough match template
                   --      It is put back by GHC.Core.InstEnv.mkImportedClsInst
                 , ifInstOrph = orph }

--------------------------
famInstToIfaceFamInst :: FamInst -> IfaceFamInst
famInstToIfaceFamInst (FamInst { fi_axiom    = axiom
                               , fi_fam      = fam
                               , fi_tcs      = rough_tcs
                               , fi_orphan   = orphan })
  = IfaceFamInst { ifFamInstAxiom    = coAxiomName axiom
                 , ifFamInstFam      = fam
                 , ifFamInstTys      = ifaceRoughMatchTcs rough_tcs
                 , ifFamInstOrph     = orphan }

ifaceRoughMatchTcs :: [RoughMatchTc] -> [Maybe IfaceTyCon]
ifaceRoughMatchTcs tcs = map do_rough tcs
  where
    do_rough RM_WildCard     = Nothing
    do_rough (RM_KnownTc n) = Just (toIfaceTyCon_name n)

--------------------------
toIfaceWarnings :: Warnings GhcRn -> IfaceWarnings
toIfaceWarnings (WarnAll txt) = IfWarnAll (toIfaceWarningTxt txt)
toIfaceWarnings (WarnSome vs ds) = IfWarnSome vs' ds'
  where
    vs' = [(occ, toIfaceWarningTxt txt) | (occ, txt) <- vs]
    ds' = [(occ, toIfaceWarningTxt txt) | (occ, txt) <- ds]

toIfaceWarningTxt :: WarningTxt GhcRn -> IfaceWarningTxt
toIfaceWarningTxt (WarningTxt mb_cat src strs) = IfWarningTxt (unLoc . iwc_wc . unLoc <$> mb_cat) (unLoc src) (map (toIfaceStringLiteralWithNames . unLoc) strs)
toIfaceWarningTxt (DeprecatedTxt src strs) = IfDeprecatedTxt (unLoc src) (map (toIfaceStringLiteralWithNames . unLoc) strs)

toIfaceStringLiteralWithNames :: WithHsDocIdentifiers StringLiteral GhcRn -> (IfaceStringLiteral, [IfExtName])
toIfaceStringLiteralWithNames (WithHsDocIdentifiers src names) = (toIfaceStringLiteral src, map unLoc names)

toIfaceStringLiteral :: StringLiteral -> IfaceStringLiteral
toIfaceStringLiteral (StringLiteral sl fs _) = IfStringLiteral sl fs

coreRuleToIfaceRule :: CoreRule -> IfaceRule
-- A plugin that installs a BuiltinRule in a CoreDoPluginPass should
-- ensure that there's another CoreDoPluginPass that removes the rule.
-- Otherwise a module using the plugin and compiled with -fno-omit-interface-pragmas
-- would cause panic when the rule is attempted to be written to the interface file.
coreRuleToIfaceRule rule@(BuiltinRule {})
  = pprPanic "toHsRule:" (pprRule rule)

coreRuleToIfaceRule (Rule { ru_name = name, ru_fn = fn,
                            ru_act = act, ru_bndrs = bndrs,
                            ru_args = args, ru_rhs = rhs,
                            ru_orphan = orph, ru_auto = auto })
  = IfaceRule { ifRuleName  = name, ifActivation = act,
                ifRuleBndrs = map toIfaceBndr bndrs,
                ifRuleHead  = fn,
                ifRuleArgs  = map do_arg args,
                ifRuleRhs   = toIfaceExpr rhs,
                ifRuleAuto  = auto,
                ifRuleOrph  = orph }
  where
        -- For type args we must remove synonyms from the outermost
        -- level.  Reason: so that when we read it back in we'll
        -- construct the same ru_rough field as we have right now;
        -- see tcIfaceRule
    do_arg (Type ty)     = IfaceType (toIfaceType (deNoteType ty))
    do_arg (Coercion co) = IfaceCo   (toIfaceCoercion co)
    do_arg arg           = toIfaceExpr arg


{-
************************************************************************
*                                                                      *
       COMPLETE Pragmas
*                                                                      *
************************************************************************
-}

mkIfaceCompleteMatch :: CompleteMatch -> IfaceCompleteMatch
mkIfaceCompleteMatch (CompleteMatch cls mtc) =
  IfaceCompleteMatch (map conLikeName (uniqDSetToList cls)) (toIfaceTyCon <$> mtc)


{-
************************************************************************
*                                                                      *
       Keeping track of what we've slurped, and fingerprints
*                                                                      *
************************************************************************
-}


mkIfaceAnnotation :: Annotation -> IfaceAnnotation
mkIfaceAnnotation (Annotation { ann_target = target, ann_value = payload })
  = IfaceAnnotation {
        ifAnnotatedTarget = fmap nameOccName target,
        ifAnnotatedValue = payload
    }

mkIfaceExports :: [AvailInfo] -> [IfaceExport]  -- Sort to make canonical
mkIfaceExports exports
  = sortBy stableAvailCmp (map sort_subs exports)
  where
    sort_subs :: AvailInfo -> AvailInfo
    sort_subs (Avail n) = Avail n
    sort_subs (AvailTC n []) = AvailTC n []
    sort_subs (AvailTC n (m:ms))
       | n == m
       = AvailTC n (m:sortBy stableNameCmp ms)
       | otherwise
       = AvailTC n (sortBy stableNameCmp (m:ms))
       -- Maintain the AvailTC Invariant

{-
Note [Original module]
~~~~~~~~~~~~~~~~~~~~~
Consider this:
        module X where { data family T }
        module Y( T(..) ) where { import X; data instance T Int = MkT Int }
The exported Avail from Y will look like
        X.T{X.T, Y.MkT}
That is, in Y,
  - only MkT is brought into scope by the data instance;
  - but the parent (used for grouping and naming in T(..) exports) is X.T
  - and in this case we export X.T too

In the result of mkIfaceExports, the names are grouped by defining module,
so we may need to split up a single Avail into multiple ones.
-}

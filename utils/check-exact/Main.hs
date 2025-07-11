{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE BangPatterns #-}
{-# OPTIONS_GHC -Wno-incomplete-uni-patterns #-}
{-# OPTIONS_GHC -Wno-incomplete-patterns #-}
{-# OPTIONS_GHC -Wno-orphans #-}

import Data.Data
import Data.List (intercalate)
import GHC hiding (moduleName)
import GHC.Data.Bag
import GHC.Driver.Errors.Types
import GHC.Driver.Ppr
import GHC.Hs.Dump
import GHC.Types.Error
import GHC.Types.Name.Occurrence
import GHC.Types.Name.Reader
import GHC.Utils.Error
import GHC.Utils.Outputable
import System.Environment( getArgs )
import System.Exit
import System.FilePath
import System.IO

import Types
import Utils
import ExactPrint
import Transform
import Parsers

import GHC.Parser.Lexer
import GHC.Data.FastString

-- ---------------------------------------------------------------------

_tt :: IO ()
-- _tt = testOneFile changers "/home/alanz/mysrc/git.haskell.org/worktree/master/_build/stage1/lib/"
-- _tt = testOneFile changers "/home/alanz/mysrc/git.haskell.org/ghc/_build/stage1/lib/"
-- _tt = testOneFile changers "/home/alanz/mysrc/git.haskell.org/worktree/exactprint/_build/stage1/lib"
_tt = testOneFile changers "/home/alanz/mysrc/git.haskell.org/worktree/epw/_build/stage1/lib"

 -- "../../testsuite/tests/ghc-api/exactprint/RenameCase1.hs" (Just changeRenameCase1)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutLet2.hs" (Just changeLayoutLet2)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutLet3.hs" (Just changeLayoutLet3)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutLet4.hs" (Just changeLayoutLet3)
 -- "../../testsuite/tests/ghc-api/exactprint/Rename1.hs" (Just changeRename1)
 -- "../../testsuite/tests/ghc-api/exactprint/Rename2.hs" (Just changeRename2)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn1.hs" (Just changeLayoutIn1)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn3.hs" (Just changeLayoutIn3)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn3a.hs" (Just changeLayoutIn3)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn3b.hs" (Just changeLayoutIn3)
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn4.hs" (Just changeLayoutIn4)
 -- "../../testsuite/tests/ghc-api/exactprint/LocToName.hs" (Just changeLocToName)
 -- "../../testsuite/tests/ghc-api/exactprint/LetIn1.hs" (Just changeLetIn1)
 -- "../../testsuite/tests/ghc-api/exactprint/WhereIn4.hs" (Just changeWhereIn4)
 -- "../../testsuite/tests/ghc-api/exactprint/AddDecl1.hs" (Just changeAddDecl1)
 -- "../../testsuite/tests/ghc-api/exactprint/AddDecl2.hs" (Just changeAddDecl2)
 -- "../../testsuite/tests/ghc-api/exactprint/AddDecl3.hs" (Just changeAddDecl3)
 -- "../../testsuite/tests/ghc-api/exactprint/LocalDecls.hs" (Just changeLocalDecls)
 -- "../../testsuite/tests/ghc-api/exactprint/LocalDecls2.hs" (Just changeLocalDecls2)
 -- "../../testsuite/tests/ghc-api/exactprint/WhereIn3a.hs" (Just changeWhereIn3a)
 -- "../../testsuite/tests/ghc-api/exactprint/WhereIn3b.hs" (Just changeWhereIn3b)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl1.hs" (Just addLocaLDecl1)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl2.hs" (Just addLocaLDecl2)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl3.hs" (Just addLocaLDecl3)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl4.hs" (Just addLocaLDecl4)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl5.hs" (Just addLocaLDecl5)
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl6.hs" (Just addLocaLDecl6)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl1.hs" (Just rmDecl1)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl2.hs" (Just rmDecl2)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl3.hs" (Just rmDecl3)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl4.hs" (Just rmDecl4)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl5.hs" (Just rmDecl5)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl6.hs" (Just rmDecl6)
 -- "../../testsuite/tests/ghc-api/exactprint/RmDecl7.hs" (Just rmDecl7)
 -- "../../testsuite/tests/ghc-api/exactprint/RmTypeSig1.hs" (Just rmTypeSig1)
 -- "../../testsuite/tests/ghc-api/exactprint/RmTypeSig2.hs" (Just rmTypeSig2)
 -- "../../testsuite/tests/ghc-api/exactprint/AddHiding1.hs" (Just addHiding1)
 -- "../../testsuite/tests/ghc-api/exactprint/AddHiding2.hs" (Just addHiding2)
 -- "../../testsuite/tests/printer/Ppr001.hs" Nothing
 -- "../../testsuite/tests/ghc-api/annotations/CommentsTest.hs" Nothing
 -- "../../testsuite/tests/hiefile/should_compile/Constructors.hs" Nothing
 -- "../../testsuite/tests/hiefile/should_compile/Scopes.hs" Nothing
 -- "../../testsuite/tests/hiefile/should_compile/hie008.hs" Nothing
 -- "../../testsuite/tests/hiefile/should_run/PatTypes.hs" Nothing
 -- "../../testsuite/tests/parser/should_compile/T14189.hs" Nothing

 -- "../../testsuite/tests/printer/AnnotationLet.hs" Nothing
 -- "../../testsuite/tests/printer/AnnotationTuple.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr001.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr002.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr002a.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr003.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr004.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr005.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr006.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr007.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr008.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr009.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr011.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr012.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr013.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr014.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr015.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr016.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr017.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr018.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr019.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr020.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr021.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr022.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr023.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr024.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr025.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr026.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr027.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr028.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr029.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr030.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr031.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr032.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr033.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr034.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr035.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr036.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr037.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr038.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr039.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr040.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr041.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr042.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr043.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr044.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr045.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr046.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr048.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr049.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr050.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr051.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr052.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr053.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr054.hs" Nothing
 -- "../../testsuite/tests/printer/Ppr055.hs" Nothing
 -- "../../testsuite/tests/printer/PprRecordDotSyntax1.hs" Nothing
 -- "../../testsuite/tests/printer/PprRecordDotSyntax2.hs" Nothing
 -- "../../testsuite/tests/printer/PprRecordDotSyntax3.hs" Nothing
 -- "../../testsuite/tests/printer/PprRecordDotSyntax4.hs" Nothing
 -- "../../testsuite/tests/printer/PprRecordDotSyntaxA.hs" Nothing
 -- "../../testsuite/tests/printer/StarBinderAnns.hs" Nothing
 -- "../../testsuite/tests/printer/T13050p.hs" Nothing
 -- "../../testsuite/tests/printer/T13199.hs" Nothing
 -- "../../testsuite/tests/printer/T13550.hs" Nothing
 -- "../../testsuite/tests/printer/T13942.hs" Nothing
 -- "../../testsuite/tests/printer/T14289.hs" Nothing
 -- "../../testsuite/tests/printer/T14289b.hs" Nothing
 -- "../../testsuite/tests/printer/T14289c.hs" Nothing
 -- "../../testsuite/tests/printer/T14306.hs" Nothing
 -- "../../testsuite/tests/printer/T14343.hs" Nothing
 -- "../../testsuite/tests/printer/T14343b.hs" Nothing
 -- "../../testsuite/tests/printer/T15761.hs" Nothing
 -- "../../testsuite/tests/printer/T18052a.hs" Nothing
 -- "../../testsuite/tests/printer/T18247a.hs" Nothing
 -- "../../testsuite/tests/printer/Test10268.hs" Nothing
 -- "../../testsuite/tests/printer/Test10276.hs" Nothing
 -- "../../testsuite/tests/printer/Test10278.hs" Nothing
 -- "../../testsuite/tests/printer/Test10312.hs" Nothing
 -- "../../testsuite/tests/printer/Test10354.hs" Nothing
 -- "../../testsuite/tests/printer/Test10357.hs" Nothing
 -- "../../testsuite/tests/printer/Test10399.hs" Nothing
 -- "../../testsuite/tests/printer/Test11018.hs" Nothing
 -- "../../testsuite/tests/printer/Test11332.hs" Nothing
 -- "../../testsuite/tests/printer/Test12417.hs" Nothing
 -- "../../testsuite/tests/printer/Test16212.hs" Nothing
 -- "../../testsuite/tests/printer/Test16230.hs" Nothing
 -- "../../testsuite/tests/printer/Test16236.hs" Nothing
 -- "../../testsuite/tests/printer/Test17519.hs" Nothing
 -- "../../testsuite/tests/printer/InTreeAnnotations1.hs" Nothing
 -- "../../testsuite/tests/printer/Test19798.hs" Nothing

 -- "../../testsuite/tests/qualifieddo/should_compile/qdocompile001.hs" Nothing
 -- "../../testsuite/tests/typecheck/should_fail/StrictBinds.hs" Nothing
 -- "../../testsuite/tests/typecheck/should_fail/T17566c.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/AddLocalDecl1.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/EmptyWheres.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/LayoutIn1.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/LocalDecls2.expected.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/WhereIn3a.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/Windows.hs" Nothing
 -- "../../testsuite/tests/printer/Test19784.hs" Nothing
 -- "../../testsuite/tests/printer/Test19813.hs" Nothing
 -- "../../testsuite/tests/printer/Test19814.hs" Nothing
 -- "../../testsuite/tests/printer/Test19821.hs" Nothing
 -- "../../testsuite/tests/printer/Test19834.hs" Nothing
 -- "../../testsuite/tests/printer/Test19840.hs" Nothing
 -- "../../testsuite/tests/printer/Test19850.hs" Nothing
 -- "../../testsuite/tests/printer/Test20258.hs" Nothing
 -- "../../testsuite/tests/printer/PprLinearArrow.hs" Nothing
 -- "../../testsuite/tests/printer/PprSemis.hs" Nothing
 -- "../../testsuite/tests/printer/PprEmptyMostly.hs" Nothing
 -- "../../testsuite/tests/parser/should_compile/DumpSemis.hs" Nothing
 -- "../../testsuite/tests/ghc-api/exactprint/Test20239.hs" Nothing
 -- "../../testsuite/tests/printer/PprArrowLambdaCase.hs" Nothing
 -- "../../testsuite/tests/printer/Test16279.hs" Nothing
 -- "../../testsuite/tests/printer/HsDocTy.hs" Nothing
--  "../../testsuite/tests/printer/Test22765.hs" Nothing
 -- "../../testsuite/tests/printer/Test22771.hs" Nothing
 "../../testsuite/tests/printer/Test23465.hs" Nothing

-- cloneT does not need a test, function can be retired


-- exact = ppr

changers :: [(String, Changer)]
changers =
  [("noChange",          noChange)
  ,("changeRenameCase1", changeRenameCase1)
  ,("changeLayoutLet2",  changeLayoutLet2)
  ,("changeLayoutLet3",  changeLayoutLet3)
  ,("changeLayoutIn1",   changeLayoutIn1)
  ,("changeLayoutIn3",   changeLayoutIn3)
  ,("changeLayoutIn4",   changeLayoutIn4)
  ,("changeLocToName",   changeLocToName)
  ,("changeRename1",     changeRename1)
  ,("changeRename2",     changeRename2)
  ,("changeWhereIn4",    changeWhereIn4)
  ,("changeLetIn1",      changeLetIn1)
  ,("changeAddDecl1",    changeAddDecl1)
  ,("changeAddDecl2",    changeAddDecl2)
  ,("changeAddDecl3",    changeAddDecl3)
  ,("changeLocalDecls",  changeLocalDecls)
  ,("changeLocalDecls2", changeLocalDecls2)
  ,("changeWhereIn3a",   changeWhereIn3a)
  ,("changeWhereIn3b",   changeWhereIn3b)
  ,("ADDLOCALDECL1",     addLocaLDecl1)
  ,("ADDLOCALDECL2",     addLocaLDecl2)
  ,("ADDLOCALDECL3",     addLocaLDecl3)
  ,("ADDLOCALDECL4",     addLocaLDecl4)
  ,("ADDLOCALDECL5",     addLocaLDecl5)
  ,("ADDLOCALDECL6",     addLocaLDecl6)
  ,("ADDLOCALDECL6",     addLocaLDecl6)
  ,("rmDecl1",           rmDecl1)
  ,("rmDecl2",           rmDecl2)
  ,("rmDecl3",           rmDecl3)
  ,("rmDecl4",           rmDecl4)
  ,("rmDecl5",           rmDecl5)
  ,("rmDecl6",           rmDecl6)
  ,("rmDecl7",           rmDecl7)
  ,("rmTypeSig1",        rmTypeSig1)
  ,("rmTypeSig2",        rmTypeSig2)
  ,("addHiding1",        addHiding1)
  ,("addHiding2",        addHiding2)
   ]

-- ---------------------------------------------------------------------

usage :: String
usage = unlines
    [ "usage: check-exact (libdir) (file)"
    , "       check-exact (libdir) (file) (changer)"
    , ""
    , "where libdir is the GHC library directory (e.g. the output of"
    , "ghc --print-libdir), file is the file to parse"
    , "and changer is an optional name of a 'changer' to modify the"
    , " AST before printing."
    ]

main :: IO()
main = do
  args <- getArgs
  case args of
   [] -> _tt
   [libdir,fileName] -> testOneFile changers libdir fileName Nothing
   [libdir,fileName,changerStr] -> do
     case lookup changerStr changers of
       Just doChange -> testOneFile changers libdir fileName (Just doChange)
       Nothing -> do
         putStrLn $ "exactprint: could not find changer for [" ++ changerStr ++ "]"
         putStrLn $ "valid changers are:\n" ++ unlines (map fst changers)
         putStrLn $ "(see utils/check-exact/Main.hs)"
         exitFailure
   _ -> putStrLn usage

deriving instance Data Token

writeBinFile :: FilePath -> String -> IO()
writeBinFile fpath x = withBinaryFile fpath WriteMode (\h -> hSetEncoding h utf8 >> hPutStr h x)

testOneFile :: [(String, Changer)] -> FilePath -> String -> Maybe Changer -> IO ()
testOneFile _ libdir fileName mchanger = do
       (p,_toks) <- parseOneFile libdir fileName
       -- putStrLn $ "\n\ngot p" ++ showAst (take 4 $ reverse _toks)
       let
         origAst = ppAst p
         pped    = exactPrint p

         newFile         = dropExtension fileName <.> "ppr"      <.> takeExtension fileName
         newFileChanged  = dropExtension fileName <.> "changed"  <.> takeExtension fileName
         newFileExpected = dropExtension fileName <.> "expected" <.> takeExtension fileName
         astFile        = fileName <.> "ast"
         newAstFile     = fileName <.> "ast.new"
         changedAstFile = fileName <.> "ast.changed"

       writeBinFile astFile origAst
       writeBinFile newFile pped

       (changedSourceOk, expectedSource, changedSource) <- case mchanger of
         Just changer -> do
           (pped', ast') <- exactprintWithChange libdir changer p
           writeBinFile changedAstFile (ppAst ast')
           writeBinFile newFileChanged pped'

           expectedSource <- readFile newFileExpected
           changedSource  <- readFile newFileChanged
           return (expectedSource == changedSource, expectedSource, changedSource)
         Nothing -> return (True, "", "")


       (p',_) <- parseOneFile libdir newFile
       let newAstStr :: String
           newAstStr = ppAst p'
       writeBinFile newAstFile newAstStr

       let origAstOk = origAst == newAstStr

       if origAstOk && changedSourceOk
         then do
           exitSuccess
         else if not origAstOk
           then do
             putStrLn "exactPrint: AST Match Failed"
             putStrLn "\n===================================\nOrig\n\n"
             putStrLn origAst
             putStrLn "\n===================================\nNew\n\n"
             putStrLn newAstStr
             exitFailure
           else do
             putStrLn "exactPrint: Changed AST Source Mismatch"
             putStrLn "\n===================================\nExpected\n\n"
             putStrLn expectedSource
             putStrLn "\n===================================\nChanged\n\n"
             putStrLn changedSource
             putStrLn "\n===================================\n"
             putStrLn $ show changedSourceOk
             exitFailure

ppAst :: Data a => a -> String
ppAst ast = showSDocUnsafe $ showAstData BlankSrcSpanFile NoBlankEpAnnotations ast


parseOneFile :: FilePath -> FilePath -> IO (ParsedSource, [Located Token])
parseOneFile libdir fileName = do
  res <- parseModuleEpAnnsWithCpp libdir defaultCppOptions fileName
  case res of
    Left m -> error (showErrorMessages m)
    Right (injectedComments, _dflags, pmod) -> do
      let !pmodWithComments = insertCppComments pmod injectedComments
      return (pmodWithComments, [])

showErrorMessages :: Messages GhcMessage -> String
showErrorMessages msgs =
  renderWithContext defaultSDocContext
    $ vcat
    $ pprMsgEnvelopeBagWithLocDefault
    $ getMessages
    $ msgs

-- ---------------------------------------------------------------------

exactprintWithChange :: FilePath -> Changer -> ParsedSource -> IO (String, ParsedSource)
exactprintWithChange libdir f p = do
  p' <- f libdir p
  return (exactPrint p', p')

-- First param is libdir
type Changer = FilePath -> (ParsedSource -> IO ParsedSource)

noChange :: Changer
noChange _libdir parsed = return parsed

-- changeDeltaAst :: Changer
-- changeDeltaAst _libdir parsed = return (makeDeltaAst parsed)

changeRenameCase1 :: Changer
changeRenameCase1 _libdir parsed = return (rename "bazLonger" [((3,15),(3,18))] parsed)

changeLayoutLet2 :: Changer
changeLayoutLet2 _libdir parsed = return (rename "xxxlonger" [((7,5),(7,8)),((8,24),(8,27))] parsed)

changeLayoutLet3 :: Changer
changeLayoutLet3 _libdir parsed = return (rename "xxxlonger" [((7,5),(7,8)),((9,14),(9,17))] parsed)

changeLayoutIn1 :: Changer
changeLayoutIn1 _libdir parsed = return (rename "square" [((7,17),(7,19)),((7,24),(7,26))] parsed)

changeLayoutIn3 :: Changer
changeLayoutIn3 _libdir parsed = return (rename "anotherX" [((7,13),(7,14)),((7,37),(7,38)),((8,37),(8,38))] parsed)

changeLayoutIn4 :: Changer
changeLayoutIn4 _libdir parsed = return (rename "io" [((7,8),(7,13)),((7,28),(7,33))] parsed)

changeLocToName :: Changer
changeLocToName _libdir parsed = return (rename "LocToName.newPoint" [((20,1),(20,11)),((20,28),(20,38)),((24,1),(24,11))] parsed)


changeRename1 :: Changer
changeRename1 _libdir parsed = return (rename "bar2" [((3,1),(3,4))] parsed)

changeRename2 :: Changer
changeRename2 _libdir parsed = return (rename "joe" [((2,1),(2,5))] parsed)

rename :: (Data a, ExactPrint a) => String -> [(Pos, Pos)] -> a -> a
rename newNameStr spans' a
  = everywhere (mkT replaceRdr) (makeDeltaAst a)
  where
    newName = mkRdrUnqual (mkVarOcc newNameStr)

    cond :: SrcSpan -> Bool
    cond ln = ss2range ln `elem` spans'

    replaceRdr :: LocatedN RdrName -> LocatedN RdrName
    replaceRdr (L ln _)
        | cond (locA ln) = L ln newName
    replaceRdr x = x

-- ---------------------------------------------------------------------

changeWhereIn4 :: Changer
changeWhereIn4 _libdir parsed
  = return (everywhere (mkT replace) (makeDeltaAst parsed))
  where
    replace :: LocatedN RdrName -> LocatedN RdrName
    replace (L ln _n)
      | ss2range (locA ln) == ((12,16),(12,17)) = L ln (mkRdrUnqual (mkVarOcc "p_2"))
    replace x = x

-- ---------------------------------------------------------------------

changeLetIn1 :: Changer
changeLetIn1 _libdir parsed
  = return (everywhere (mkT replace) parsed)
  where
    replace :: HsExpr GhcPs -> HsExpr GhcPs
    replace (HsLet an tkLet localDecls _ expr)
      =
         let (HsValBinds x (ValBinds xv bagDecls sigs)) = localDecls
             [l2,_l1] = map wrapDecl $ bagToList bagDecls
             bagDecls' = listToBag $ concatMap decl2Bind [l2]
             (L (SrcSpanAnn _ le) e) = expr
             a = (SrcSpanAnn (EpAnn (Anchor (realSrcSpan le) (MovedAnchor (SameLine 1))) mempty emptyComments) le)
             expr' = L a e
             tkIn' = L (TokenLoc (EpaDelta (DifferentLine 1 0) [])) HsTok
         in (HsLet an tkLet
                (HsValBinds x (ValBinds xv bagDecls' sigs)) tkIn' expr')

    replace x = x

-- ---------------------------------------------------------------------

-- | Add a declaration to AddDecl
changeAddDecl1 :: Changer
changeAddDecl1 libdir top = do
  Right decl <- withDynFlags libdir (\df -> parseDecl df "<interactive>" "nn = n2")
  let decl' = setEntryDP decl (DifferentLine 2 0)

  let (p',_,_) = runTransform doAddDecl
      doAddDecl = everywhereM (mkM replaceTopLevelDecls) top
      replaceTopLevelDecls :: ParsedSource -> Transform ParsedSource
      replaceTopLevelDecls m = insertAtStart m decl'
  return p'

-- ---------------------------------------------------------------------

changeAddDecl2 :: Changer
changeAddDecl2 libdir top = do
  Right decl <- withDynFlags libdir (\df -> parseDecl df "<interactive>" "nn = n2")
  let decl' = setEntryDP (makeDeltaAst decl) (DifferentLine 2 0)

  let (p',_,_) = runTransform doAddDecl
      doAddDecl = everywhereM (mkM replaceTopLevelDecls) (makeDeltaAst top)
      replaceTopLevelDecls :: ParsedSource -> Transform ParsedSource
      replaceTopLevelDecls m = insertAtEnd m decl'
  return p'

-- ---------------------------------------------------------------------

changeAddDecl3 :: Changer
changeAddDecl3 libdir top = do
  Right decl <- withDynFlags libdir (\df -> parseDecl df "<interactive>" "nn = n2")
  let decl' = setEntryDP decl (DifferentLine 2 0)

  let (p',_,_) = runTransform doAddDecl
      doAddDecl = everywhereM (mkM replaceTopLevelDecls) top
      f d (l1:l2:ls) = (l1:d:l2':ls)
        where
          l2' = setEntryDP l2 (DifferentLine 2 0)

      replaceTopLevelDecls :: ParsedSource -> Transform ParsedSource
      replaceTopLevelDecls m = insertAt f m decl'
  return p'

-- ---------------------------------------------------------------------

-- | Add a local declaration with signature to LocalDecl
changeLocalDecls :: Changer
changeLocalDecls libdir (L l p) = do
  Right s@(L ls (SigD _ sig))  <- withDynFlags libdir (\df -> parseDecl df "sig"  "nn :: Int")
  Right d@(L ld (ValD _ decl)) <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  let decl' = setEntryDP (L ld decl) (DifferentLine 1 0)
  let  sig' = setEntryDP (L ls sig)  (SameLine 0)
  let (p',_,_w) = runTransform doAddLocal
      doAddLocal = everywhereM (mkM replaceLocalBinds) p
      replaceLocalBinds :: LMatch GhcPs (LHsExpr GhcPs)
                        -> Transform (LMatch GhcPs (LHsExpr GhcPs))
      replaceLocalBinds (L lm (Match an mln pats (GRHSs _ rhs (HsValBinds van (ValBinds _ binds sigs))))) = do
        let oldDecls = sortLocatedA $ map wrapDecl (bagToList binds) ++ map wrapSig sigs
        let decls = s:d:oldDecls
        let oldDecls' = captureLineSpacing oldDecls
        let oldBinds     = concatMap decl2Bind oldDecls'
            (os:oldSigs) = concatMap decl2Sig  oldDecls'
            os' = setEntryDP os (DifferentLine 2 0)
        let sortKey = captureOrder decls
        let (EpAnn anc (AnnList (Just (Anchor anc2 _)) a b c dd) cs) = van
        let van' = (EpAnn anc (AnnList (Just (Anchor anc2 (MovedAnchor (DifferentLine 1 4)))) a b c dd) cs)
        let binds' = (HsValBinds van'
                          (ValBinds sortKey (listToBag $ decl':oldBinds)
                                          (sig':os':oldSigs)))
        return (L lm (Match an mln pats (GRHSs emptyComments rhs binds')))
      replaceLocalBinds x = return x
  return (L l p')

-- ---------------------------------------------------------------------

-- | Add a local declaration with signature to LocalDecl, where there was no
-- prior local decl. So it adds a "where" annotation.
changeLocalDecls2 :: Changer
changeLocalDecls2 libdir (L l p) = do
  Right d@(L ld (ValD _ decl)) <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  Right s@(L ls (SigD _ sig))  <- withDynFlags libdir (\df -> parseDecl df "sig"  "nn :: Int")
  let decl' = setEntryDP (L ld decl) (DifferentLine 1 0)
  let  sig' = setEntryDP (L ls  sig) (SameLine 2)
  let (p',_,_w) = runTransform doAddLocal
      doAddLocal = everywhereM (mkM replaceLocalBinds) p
      replaceLocalBinds :: LMatch GhcPs (LHsExpr GhcPs)
                        -> Transform (LMatch GhcPs (LHsExpr GhcPs))
      replaceLocalBinds (L lm (Match ma mln pats (GRHSs _ rhs EmptyLocalBinds{}))) = do
        newSpan <- uniqueSrcSpanT
        let anc = (Anchor (rs newSpan) (MovedAnchor (DifferentLine 1 2)))
        let anc2 = (Anchor (rs newSpan) (MovedAnchor (DifferentLine 1 4)))
        let an = EpAnn anc
                        (AnnList (Just anc2) Nothing Nothing
                                 [AddEpAnn AnnWhere (EpaDelta (SameLine 0) [])] [])
                        emptyComments
        let decls = [s,d]
        let sortKey = captureOrder decls
        let binds = (HsValBinds an (ValBinds sortKey (listToBag $ [decl'])
                                    [sig']))
        return (L lm (Match ma mln pats (GRHSs emptyComments rhs binds)))
      replaceLocalBinds x = return x
  return (L l p')

-- ---------------------------------------------------------------------

-- | Check that balanceCommentsList is idempotent
changeWhereIn3a :: Changer
changeWhereIn3a _libdir (L l p) = do
  let decls0 = hsmodDecls p
      (decls,_,w) = runTransform (balanceCommentsList decls0)
  debugM $ unlines w
  let p2 = p { hsmodDecls = decls}
  return (L l p2)

-- ---------------------------------------------------------------------

changeWhereIn3b :: Changer
changeWhereIn3b _libdir (L l p) = do
  let decls0 = hsmodDecls p
      (decls,_,w) = runTransform (balanceCommentsList decls0)
      (de0:tdecls@(_:de1:d2:_)) = decls
      de0' = setEntryDP de0 (DifferentLine 2 0)
      de1' = setEntryDP de1 (DifferentLine 2 0)
      d2' = setEntryDP d2 (DifferentLine 2 0)
      decls' = d2':de1':de0':tdecls
  debugM $ unlines w
  debugM $ "changeWhereIn3b:de1':" ++ showAst de1'
  let p2 = p { hsmodDecls = decls'}
  return (L l p2)

-- ---------------------------------------------------------------------

addLocaLDecl1 :: Changer
addLocaLDecl1 libdir top = do
  Right (L ld (ValD _ decl)) <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  let decl' = setEntryDP (L ld decl) (DifferentLine 1 5)
      doAddLocal = do
        let lp = makeDeltaAst top
        (de1:d2:d3:_) <- hsDecls lp
        (de1'',d2') <- balanceComments de1 d2
        (de1',_) <- modifyValD (getLocA de1'') de1'' $ \_m d -> do
          return ((wrapDecl decl' : d),Nothing)
        replaceDecls lp [de1', d2', d3]

  (lp',_,w) <- runTransformT doAddLocal
  debugM $ "addLocaLDecl1:" ++ intercalate "\n" w
  return lp'

-- ---------------------------------------------------------------------

addLocaLDecl2 :: Changer
addLocaLDecl2 libdir lp = do
  Right newDecl <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  let
      doAddLocal = do
         (de1:d2:_) <- hsDecls lp
         (de1'',d2') <- balanceComments de1 d2

         (parent',_) <- modifyValD (getLocA de1) de1'' $ \_m (d:ds) -> do
           newDecl' <- transferEntryDP' d newDecl
           let d' = setEntryDP d (DifferentLine 1 0)
           return ((newDecl':d':ds),Nothing)

         replaceDecls lp [parent',d2']

  (lp',_,_w) <- runTransformT doAddLocal
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

addLocaLDecl3 :: Changer
addLocaLDecl3 libdir top = do
  Right newDecl <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  let
      doAddLocal = do
         let lp = makeDeltaAst top
         (de1:d2:_) <- hsDecls lp
         (de1'',d2') <- balanceComments de1 d2

         (parent',_) <- modifyValD (getLocA de1) de1'' $ \_m (d:ds) -> do
           let newDecl' = setEntryDP newDecl (DifferentLine 1 0)
           return (((d:ds) ++ [newDecl']),Nothing)

         replaceDecls (anchorEof lp) [parent',d2']

  (lp',_,_w) <- runTransformT doAddLocal
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

addLocaLDecl4 :: Changer
addLocaLDecl4 libdir lp = do
  Right newDecl <- withDynFlags libdir (\df -> parseDecl df "decl" "nn = 2")
  Right newSig  <- withDynFlags libdir (\df -> parseDecl df "sig"  "nn :: Int")
  let
      doAddLocal = do
         (parent:ds) <- hsDecls lp

         let newDecl' = setEntryDP newDecl (DifferentLine 1 0)
         let newSig'  = setEntryDP newSig  (DifferentLine 1 4)

         (parent',_) <- modifyValD (getLocA parent) parent $ \_m decls -> do
           return ((decls++[newSig',newDecl']),Nothing)

         replaceDecls (anchorEof lp) (parent':ds)

  (lp',_,_w) <- runTransformT doAddLocal
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'


-- ---------------------------------------------------------------------

addLocaLDecl5 :: Changer
addLocaLDecl5 _libdir lp = do
  let
      doAddLocal = do
         decls <- hsDecls lp
         [s1,de1,d2,d3] <- balanceCommentsList decls

         let d3' = setEntryDP d3 (DifferentLine 2 0)

         (de1',_) <- modifyValD (getLocA de1) de1 $ \_m _decls -> do
           let d2' = setEntryDP d2 (DifferentLine 1 0)
           return ([d2'],Nothing)
         replaceDecls lp [s1,de1',d3']

  (lp',_,_w) <- runTransformT doAddLocal
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

addLocaLDecl6 :: Changer
addLocaLDecl6 libdir lp = do
  Right newDecl <- withDynFlags libdir (\df -> parseDecl df "decl" "x = 3")
  let
      newDecl' = setEntryDP newDecl (DifferentLine 1 4)
      doAddLocal = do
        decls0 <- hsDecls lp
        [de1'',d2] <- balanceCommentsList decls0

        let de1 = captureMatchLineSpacing de1''
        let L _ (ValD _ (FunBind _ _ (MG _ (L _ ms)))) = de1
        let [ma1,_ma2] = ms

        (de1',_) <- modifyValD (getLocA ma1) de1 $ \_m decls -> do
           return ((newDecl' : decls),Nothing)
        replaceDecls lp [de1', d2]

  (lp',_,_w) <- runTransformT doAddLocal
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl1 :: Changer
rmDecl1 _libdir top = do
  let doRmDecl = do
         let lp = makeDeltaAst top
         tlDecs0 <- hsDecls lp
         tlDecs <- balanceCommentsList $ captureLineSpacing tlDecs0
         let (de1:_s1:_d2:d3:ds) = tlDecs
         let d3' = setEntryDP d3 (DifferentLine 2 0)

         replaceDecls lp (de1:d3':ds)

  (lp',_,_w) <- runTransformT doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl2 :: Changer
rmDecl2 _libdir lp = do
  let
      doRmDecl = do
        let
          go :: GHC.LHsExpr GhcPs -> Transform (GHC.LHsExpr GhcPs)
          go e@(GHC.L _ (GHC.HsLet{})) = do
            decs0 <- hsDecls e
            decs <- balanceCommentsList $ captureLineSpacing decs0
            e' <- replaceDecls e (init decs)
            return e'
          go x = return x

        everywhereM (mkM go) lp

  let (lp',_,_w) = runTransform doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl3 :: Changer
rmDecl3 _libdir lp = do
  let
      doRmDecl = do
         [de1,d2] <- hsDecls lp

         (de1',Just sd1) <- modifyValD (getLocA de1) de1 $ \_m [sd1] -> do
           let sd1' = setEntryDP sd1 (DifferentLine 2 0)
           return ([],Just sd1')

         replaceDecls lp [de1',sd1,d2]

  (lp',_,_w) <- runTransformT doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl4 :: Changer
rmDecl4 _libdir lp = do
  let
      doRmDecl = do
         [de1] <- hsDecls lp

         (de1',Just sd1) <- modifyValD (getLocA de1) de1 $ \_m [sd1,sd2] -> do
           sd2' <- transferEntryDP' sd1 sd2

           let sd1' = setEntryDP sd1 (DifferentLine 2 0)
           return ([sd2'],Just sd1')

         replaceDecls (anchorEof lp) [de1',sd1]

  (lp',_,_w) <- runTransformT doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl5 :: Changer
rmDecl5 _libdir lp = do
  let
      doRmDecl = do
        let
          go :: HsExpr GhcPs -> Transform (HsExpr GhcPs)
          go (HsLet a tkLet lb tkIn expr) = do
            decs <- hsDeclsValBinds lb
            let hdecs : _ = decs
            let dec = last decs
            _ <- transferEntryDP hdecs dec
            lb' <- replaceDeclsValbinds WithoutWhere lb [dec]
            return (HsLet a tkLet lb' tkIn expr)
          go x = return x

        everywhereM (mkM go) lp

  let (lp',_,_w) = runTransform doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl6 :: Changer
rmDecl6 _libdir lp = do
  let
      doRmDecl = do
         [de1] <- hsDecls lp

         (de1',_) <- modifyValD (getLocA de1) de1 $ \_m subDecs -> do
           let (ss1:_sd1:sd2:sds) = subDecs
           sd2' <- transferEntryDP' ss1 sd2

           return (sd2':sds,Nothing)

         replaceDecls lp [de1']

  (lp',_,_w) <- runTransformT doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmDecl7 :: Changer
rmDecl7 _libdir top = do
  let
      doRmDecl = do
         let lp = makeDeltaAst top
         tlDecs <- hsDecls lp
         [s1,de1,d2,d3] <- balanceCommentsList tlDecs

         d3' <- transferEntryDP' d2 d3

         replaceDecls lp [s1,de1,d3']

  (lp',_,_w) <- runTransformT doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmTypeSig1 :: Changer
rmTypeSig1 _libdir lp = do
  let doRmDecl = do
         tlDecs <- hsDecls lp
         let (s0:de1:d2) = tlDecs
             s1 = captureTypeSigSpacing s0
             (L l (SigD x1 (TypeSig x2 [n1,n2] typ))) = s1
         n2' <- transferEntryDP n1 n2
         let s1' = (L l (SigD x1 (TypeSig x2 [n2'] typ)))
         replaceDecls lp (s1':de1:d2)

  let (lp',_,_w) = runTransform doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

rmTypeSig2 :: Changer
rmTypeSig2 _libdir lp = do
  let doRmDecl = do
         tlDecs <- hsDecls lp
         let [de1] = tlDecs

         (de1',_) <- modifyValD (getLocA de1) de1 $ \_m [s,d] -> do
           d' <- transferEntryDP s d
           return ([d'],Nothing)
         replaceDecls lp [de1']

  let (lp',_,_w) = runTransform doRmDecl
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

addHiding1 :: Changer
addHiding1 _libdir (L l p) = do
  let doTransform = do
        l0 <- uniqueSrcSpanT
        l1 <- uniqueSrcSpanT
        l2 <- uniqueSrcSpanT
        let
          [L li imp1,imp2] = hsmodImports p
          n1 = L (noAnnSrcSpanDP0 l1) (mkVarUnqual (mkFastString "n1"))
          n2 = L (noAnnSrcSpanDP0 l2) (mkVarUnqual (mkFastString "n2"))
          v1 = L (addComma $ noAnnSrcSpanDP0 l1) (IEVar Nothing (L (noAnnSrcSpanDP0 l1) (IEName noExtField n1)))
          v2 = L (           noAnnSrcSpanDP0 l2) (IEVar Nothing (L (noAnnSrcSpanDP0 l2) (IEName noExtField n2)))
          impHiding = L (SrcSpanAnn (EpAnn (Anchor (realSrcSpan l0) m0)
                                     (AnnList Nothing
                                              (Just (AddEpAnn AnnOpenP  d1))
                                              (Just (AddEpAnn AnnCloseP d0))
                                              [(AddEpAnn AnnHiding d1)]
                                              [])
                                       emptyComments) l0) [v1,v2]
          imp1' = imp1 { ideclImportList = Just (EverythingBut,impHiding)}
          p' = p { hsmodImports = [L li imp1',imp2]}
        return (L l p')

  let (lp',_,_w) = runTransform doTransform
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'

-- ---------------------------------------------------------------------

addHiding2 :: Changer
addHiding2 _libdir top = do
  let doTransform = do
        let (L l p) = makeDeltaAst top
        l1 <- uniqueSrcSpanT
        l2 <- uniqueSrcSpanT
        let
          [L li imp1] = hsmodImports p
          Just (_,L lh ns) = ideclImportList imp1
          lh' = (SrcSpanAnn (EpAnn (Anchor (realSrcSpan (locA lh)) m0)
                                     (AnnList Nothing
                                              (Just (AddEpAnn AnnOpenP  d1))
                                              (Just (AddEpAnn AnnCloseP d0))
                                              [(AddEpAnn AnnHiding d1)]
                                              [])
                                       emptyComments) (locA lh))
          n1 = L (noAnnSrcSpanDP0 l1) (mkVarUnqual (mkFastString "n1"))
          n2 = L (noAnnSrcSpanDP0 l2) (mkVarUnqual (mkFastString "n2"))
          v1 = L (addComma $ noAnnSrcSpanDP0 l1) (IEVar Nothing (L (noAnnSrcSpanDP0 l1) (IEName noExtField n1)))
          v2 = L (           noAnnSrcSpanDP0 l2) (IEVar Nothing (L (noAnnSrcSpanDP0 l2) (IEName noExtField n2)))
          L ln n = last ns
          n' = L (addComma ln) n
          imp1' = imp1 { ideclImportList = Just (EverythingBut, L lh' (init ns ++ [n',v1,v2]))}
          p' = p { hsmodImports = [L li imp1']}
        return (L l p')

  let (lp',_,_w) = runTransform doTransform
  debugM $ "log:[\n" ++ intercalate "\n" _w ++ "]log end\n"
  return lp'


-- ---------------------------------------------------------------------
-- From SYB

-- | Apply transformation on each level of a tree.
--
-- Just like 'everything', this is stolen from SYB package.
everywhere :: (forall a. Data a => a -> a) -> (forall a. Data a => a -> a)
everywhere f = f . gmapT (everywhere f)

-- | Create generic transformation.
--
-- Another function stolen from SYB package.
mkT :: (Typeable a, Typeable b) => (b -> b) -> (a -> a)
mkT f = case cast f of
    Just f' -> f'
    Nothing -> id

-- ---------------------------------------------------------------------

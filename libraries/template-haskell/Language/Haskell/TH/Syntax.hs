{-# LANGUAGE CPP, DeriveDataTypeable,
             DeriveGeneric, FlexibleInstances, DefaultSignatures,
             RankNTypes, RoleAnnotations, ScopedTypeVariables,
             MagicHash, KindSignatures, PolyKinds, TypeApplications, DataKinds,
             GADTs, UnboxedTuples, UnboxedSums, TypeOperators,
             Trustworthy, DeriveFunctor, DeriveTraversable,
             BangPatterns, RecordWildCards, ImplicitParams #-}

{-# OPTIONS_GHC -fno-warn-inline-rule-shadowing #-}
{-# LANGUAGE TemplateHaskellQuotes #-}
{-# LANGUAGE StandaloneKindSignatures #-}

-----------------------------------------------------------------------------
-- |
-- Module      :  Language.Haskell.Syntax
-- Copyright   :  (c) The University of Glasgow 2003
-- License     :  BSD-style (see the file libraries/base/LICENSE)
--
-- Maintainer  :  libraries@haskell.org
-- Stability   :  experimental
-- Portability :  portable
--
-- Abstract syntax definitions for Template Haskell.
--
-----------------------------------------------------------------------------

module Language.Haskell.TH.Syntax
    ( module Language.Haskell.TH.Syntax
      -- * Language extensions
    , module Language.Haskell.TH.LanguageExtensions
    , ForeignSrcLang(..)
    -- * Notes
    -- ** Unresolved Infix
    -- $infix
    ) where

import qualified Data.Fixed as Fixed
import Data.Data hiding (Fixity(..))
import Data.IORef
import System.IO.Unsafe ( unsafePerformIO )
import System.FilePath
import GHC.IO.Unsafe    ( unsafeDupableInterleaveIO )
import Control.Monad (liftM)
import Control.Monad.IO.Class (MonadIO (..))
import Control.Monad.Fix (MonadFix (..))
import Control.Applicative (Applicative(..))
import Control.Exception (BlockedIndefinitelyOnMVar (..), catch, throwIO)
import Control.Exception.Base (FixIOException (..))
import Control.Concurrent.MVar (newEmptyMVar, readMVar, putMVar)
import System.IO        ( hPutStrLn, stderr )
import Data.Char        ( isAlpha, isAlphaNum, isUpper, ord )
import Data.Int
import Data.List.NonEmpty ( NonEmpty(..) )
import Data.Void        ( Void, absurd )
import Data.Word
import Data.Ratio
import GHC.CString      ( unpackCString# )
import GHC.Generics     ( Generic )
import GHC.Types        ( Int(..), Word(..), Char(..), Double(..), Float(..),
                          TYPE, RuntimeRep(..), Multiplicity (..) )
import qualified Data.Kind as Kind (Type)
import GHC.Prim         ( Int#, Word#, Char#, Double#, Float#, Addr# )
import GHC.Ptr          ( Ptr, plusPtr )
import GHC.Lexeme       ( startsVarSym, startsVarId )
import GHC.ForeignSrcLang.Type
import Language.Haskell.TH.LanguageExtensions
import Numeric.Natural
import Prelude hiding (Applicative(..))
import Foreign.ForeignPtr
import Foreign.C.String
import Foreign.C.Types

#if __GLASGOW_HASKELL__ >= 901
import GHC.Types ( Levity(..) )
#endif

#if __GLASGOW_HASKELL__ >= 903
import Data.Array.Byte (ByteArray(..))
import GHC.Exts
  ( ByteArray#, unsafeFreezeByteArray#, copyAddrToByteArray#, newByteArray#
  , isByteArrayPinned#, isTrue#, sizeofByteArray#, unsafeCoerce#, byteArrayContents#
  , copyByteArray#, newPinnedByteArray#)
import GHC.ForeignPtr (ForeignPtr(..), ForeignPtrContents(..))
import GHC.ST (ST(..), runST)
#endif

-----------------------------------------------------
--
--              The Quasi class
--
-----------------------------------------------------

class (MonadIO m, MonadFail m) => Quasi m where
  qNewName :: String -> m Name
        -- ^ Fresh names

        -- Error reporting and recovery
  qReport  :: Bool -> String -> m ()    -- ^ Report an error (True) or warning (False)
                                        -- ...but carry on; use 'fail' to stop
  qRecover :: m a -- ^ the error handler
           -> m a -- ^ action which may fail
           -> m a               -- ^ Recover from the monadic 'fail'

        -- Inspect the type-checker's environment
  qLookupName :: Bool -> String -> m (Maybe Name)
       -- True <=> type namespace, False <=> value namespace
  qReify          :: Name -> m Info
  qReifyFixity    :: Name -> m (Maybe Fixity)
  qReifyType      :: Name -> m Type
  qReifyInstances :: Name -> [Type] -> m [Dec]
       -- Is (n tys) an instance?
       -- Returns list of matching instance Decs
       --    (with empty sub-Decs)
       -- Works for classes and type functions
  qReifyRoles         :: Name -> m [Role]
  qReifyAnnotations   :: Data a => AnnLookup -> m [a]
  qReifyModule        :: Module -> m ModuleInfo
  qReifyConStrictness :: Name -> m [DecidedStrictness]

  qLocation :: m Loc

  qRunIO :: IO a -> m a
  qRunIO = liftIO
  -- ^ Input/output (dangerous)
  qGetPackageRoot :: m FilePath

  qAddDependentFile :: FilePath -> m ()

  qAddTempFile :: String -> m FilePath

  qAddTopDecls :: [Dec] -> m ()

  qAddForeignFilePath :: ForeignSrcLang -> String -> m ()

  qAddModFinalizer :: Q () -> m ()

  qAddCorePlugin :: String -> m ()

  qGetQ :: Typeable a => m (Maybe a)

  qPutQ :: Typeable a => a -> m ()

  qIsExtEnabled :: Extension -> m Bool
  qExtsEnabled :: m [Extension]

  qPutDoc :: DocLoc -> String -> m ()
  qGetDoc :: DocLoc -> m (Maybe String)

-----------------------------------------------------
--      The IO instance of Quasi
--
--  This instance is used only when running a Q
--  computation in the IO monad, usually just to
--  print the result.  There is no interesting
--  type environment, so reification isn't going to
--  work.
--
-----------------------------------------------------

instance Quasi IO where
  qNewName = newNameIO

  qReport True  msg = hPutStrLn stderr ("Template Haskell error: " ++ msg)
  qReport False msg = hPutStrLn stderr ("Template Haskell error: " ++ msg)

  qLookupName _ _       = badIO "lookupName"
  qReify _              = badIO "reify"
  qReifyFixity _        = badIO "reifyFixity"
  qReifyType _          = badIO "reifyFixity"
  qReifyInstances _ _   = badIO "reifyInstances"
  qReifyRoles _         = badIO "reifyRoles"
  qReifyAnnotations _   = badIO "reifyAnnotations"
  qReifyModule _        = badIO "reifyModule"
  qReifyConStrictness _ = badIO "reifyConStrictness"
  qLocation             = badIO "currentLocation"
  qRecover _ _          = badIO "recover" -- Maybe we could fix this?
  qGetPackageRoot       = badIO "getProjectRoot"
  qAddDependentFile _   = badIO "addDependentFile"
  qAddTempFile _        = badIO "addTempFile"
  qAddTopDecls _        = badIO "addTopDecls"
  qAddForeignFilePath _ _ = badIO "addForeignFilePath"
  qAddModFinalizer _    = badIO "addModFinalizer"
  qAddCorePlugin _      = badIO "addCorePlugin"
  qGetQ                 = badIO "getQ"
  qPutQ _               = badIO "putQ"
  qIsExtEnabled _       = badIO "isExtEnabled"
  qExtsEnabled          = badIO "extsEnabled"
  qPutDoc _ _           = badIO "putDoc"
  qGetDoc _             = badIO "getDoc"

instance Quote IO where
  newName = newNameIO

newNameIO :: String -> IO Name
newNameIO s = do { n <- atomicModifyIORef' counter (\x -> (x + 1, x))
                 ; pure (mkNameU s n) }

badIO :: String -> IO a
badIO op = do   { qReport True ("Can't do `" ++ op ++ "' in the IO monad")
                ; fail "Template Haskell failure" }

-- Global variable to generate unique symbols
counter :: IORef Uniq
{-# NOINLINE counter #-}
counter = unsafePerformIO (newIORef 0)


-----------------------------------------------------
--
--              The Q monad
--
-----------------------------------------------------

newtype Q a = Q { unQ :: forall m. Quasi m => m a }

-- \"Runs\" the 'Q' monad. Normal users of Template Haskell
-- should not need this function, as the splice brackets @$( ... )@
-- are the usual way of running a 'Q' computation.
--
-- This function is primarily used in GHC internals, and for debugging
-- splices by running them in 'IO'.
--
-- Note that many functions in 'Q', such as 'reify' and other compiler
-- queries, are not supported when running 'Q' in 'IO'; these operations
-- simply fail at runtime. Indeed, the only operations guaranteed to succeed
-- are 'newName', 'runIO', 'reportError' and 'reportWarning'.
runQ :: Quasi m => Q a -> m a
runQ (Q m) = m

instance Monad Q where
  Q m >>= k  = Q (m >>= \x -> unQ (k x))
  (>>) = (*>)

instance MonadFail Q where
  fail s     = report True s >> Q (fail "Q monad failure")

instance Functor Q where
  fmap f (Q x) = Q (fmap f x)

instance Applicative Q where
  pure x = Q (pure x)
  Q f <*> Q x = Q (f <*> x)
  Q m *> Q n = Q (m *> n)

-- | @since 2.17.0.0
instance Semigroup a => Semigroup (Q a) where
  (<>) = liftA2 (<>)

-- | @since 2.17.0.0
instance Monoid a => Monoid (Q a) where
  mempty = pure mempty

-- | If the function passed to 'mfix' inspects its argument,
-- the resulting action will throw a 'FixIOException'.
--
-- @since 2.17.0.0
instance MonadFix Q where
  -- We use the same blackholing approach as in fixIO.
  -- See Note [Blackholing in fixIO] in System.IO in base.
  mfix k = do
    m <- runIO newEmptyMVar
    ans <- runIO (unsafeDupableInterleaveIO
             (readMVar m `catch` \BlockedIndefinitelyOnMVar ->
                                    throwIO FixIOException))
    result <- k ans
    runIO (putMVar m result)
    return result


-----------------------------------------------------
--
--              The Quote class
--
-----------------------------------------------------



-- | The 'Quote' class implements the minimal interface which is necessary for
-- desugaring quotations.
--
-- * The @Monad m@ superclass is needed to stitch together the different
-- AST fragments.
-- * 'newName' is used when desugaring binding structures such as lambdas
-- to generate fresh names.
--
-- Therefore the type of an untyped quotation in GHC is `Quote m => m Exp`
--
-- For many years the type of a quotation was fixed to be `Q Exp` but by
-- more precisely specifying the minimal interface it enables the `Exp` to
-- be extracted purely from the quotation without interacting with `Q`.
class Monad m => Quote m where
  {- |
  Generate a fresh name, which cannot be captured.

  For example, this:

  @f = $(do
    nm1 <- newName \"x\"
    let nm2 = 'mkName' \"x\"
    return ('LamE' ['VarP' nm1] (LamE [VarP nm2] ('VarE' nm1)))
   )@

  will produce the splice

  >f = \x0 -> \x -> x0

  In particular, the occurrence @VarE nm1@ refers to the binding @VarP nm1@,
  and is not captured by the binding @VarP nm2@.

  Although names generated by @newName@ cannot /be captured/, they can
  /capture/ other names. For example, this:

  >g = $(do
  >  nm1 <- newName "x"
  >  let nm2 = mkName "x"
  >  return (LamE [VarP nm2] (LamE [VarP nm1] (VarE nm2)))
  > )

  will produce the splice

  >g = \x -> \x0 -> x0

  since the occurrence @VarE nm2@ is captured by the innermost binding
  of @x@, namely @VarP nm1@.
  -}
  newName :: String -> m Name

instance Quote Q where
  newName s = Q (qNewName s)

-----------------------------------------------------
--
--              The TExp type
--
-----------------------------------------------------

type TExp :: TYPE r -> Kind.Type
type role TExp nominal   -- See Note [Role of TExp]
newtype TExp a = TExp
  { unType :: Exp -- ^ Underlying untyped Template Haskell expression
  }
-- ^ Typed wrapper around an 'Exp'.
--
-- This is the typed representation of terms produced by typed quotes.
--
-- Representation-polymorphic since /template-haskell-2.16.0.0/.

-- | Discard the type annotation and produce a plain Template Haskell
-- expression
--
-- Representation-polymorphic since /template-haskell-2.16.0.0/.
unTypeQ :: forall (r :: RuntimeRep) (a :: TYPE r) m . Quote m => m (TExp a) -> m Exp
unTypeQ m = do { TExp e <- m
               ; return e }

-- | Annotate the Template Haskell expression with a type
--
-- This is unsafe because GHC cannot check for you that the expression
-- really does have the type you claim it has.
--
-- Representation-polymorphic since /template-haskell-2.16.0.0/.
unsafeTExpCoerce :: forall (r :: RuntimeRep) (a :: TYPE r) m .
                      Quote m => m Exp -> m (TExp a)
unsafeTExpCoerce m = do { e <- m
                        ; return (TExp e) }

{- Note [Role of TExp]
~~~~~~~~~~~~~~~~~~~~~~
TExp's argument must have a nominal role, not phantom as would
be inferred (#8459).  Consider

  e :: Code Q Age
  e = [|| MkAge 3 ||]

  foo = $(coerce e) + 4::Int

The splice will evaluate to (MkAge 3) and you can't add that to
4::Int. So you can't coerce a (Code Q Age) to a (Code Q Int). -}

-- Code constructor

type Code :: (Kind.Type -> Kind.Type) -> TYPE r -> Kind.Type
type role Code representational nominal   -- See Note [Role of TExp]
newtype Code m a = Code
  { examineCode :: m (TExp a) -- ^ Underlying monadic value
  }
-- ^ Represents an expression which has type @a@, built in monadic context @m@. Built on top of 'TExp', typed
-- expressions allow for type-safe splicing via:
--
--   - typed quotes, written as @[|| ... ||]@ where @...@ is an expression; if
--     that expression has type @a@, then the quotation has type
--     @Quote m => Code m a@
--
--   - typed splices inside of typed quotes, written as @$$(...)@ where @...@
--     is an arbitrary expression of type @Quote m => Code m a@
--
-- Traditional expression quotes and splices let us construct ill-typed
-- expressions:
--
-- >>> fmap ppr $ runQ (unTypeCode [| True == $( [| "foo" |] ) |])
-- GHC.Types.True GHC.Classes.== "foo"
-- >>> GHC.Types.True GHC.Classes.== "foo"
-- <interactive> error:
--     • Couldn't match expected type ‘Bool’ with actual type ‘[Char]’
--     • In the second argument of ‘(==)’, namely ‘"foo"’
--       In the expression: True == "foo"
--       In an equation for ‘it’: it = True == "foo"
--
-- With typed expressions, the type error occurs when /constructing/ the
-- Template Haskell expression:
--
-- >>> fmap ppr $ runQ (unTypeCode [|| True == $$( [|| "foo" ||] ) ||])
-- <interactive> error:
--     • Couldn't match type ‘[Char]’ with ‘Bool’
--       Expected type: Code Q Bool
--         Actual type: Code Q [Char]
--     • In the Template Haskell quotation [|| "foo" ||]
--       In the expression: [|| "foo" ||]
--       In the Template Haskell splice $$([|| "foo" ||])


-- | Unsafely convert an untyped code representation into a typed code
-- representation.
unsafeCodeCoerce :: forall (r :: RuntimeRep) (a :: TYPE r) m .
                      Quote m => m Exp -> Code m a
unsafeCodeCoerce m = Code (unsafeTExpCoerce m)

-- | Lift a monadic action producing code into the typed 'Code'
-- representation
liftCode :: forall (r :: RuntimeRep) (a :: TYPE r) m . m (TExp a) -> Code m a
liftCode = Code

-- | Extract the untyped representation from the typed representation
unTypeCode :: forall (r :: RuntimeRep) (a :: TYPE r) m . Quote m
           => Code m a -> m Exp
unTypeCode = unTypeQ . examineCode

-- | Modify the ambient monad used during code generation. For example, you
-- can use `hoistCode` to handle a state effect:
-- @
--  handleState :: Code (StateT Int Q) a -> Code Q a
--  handleState = hoistCode (flip runState 0)
-- @
hoistCode :: forall m n (r :: RuntimeRep) (a :: TYPE r) . Monad m
          => (forall x . m x -> n x) -> Code m a -> Code n a
hoistCode f (Code a) = Code (f a)


-- | Variant of (>>=) which allows effectful computations to be injected
-- into code generation.
bindCode :: forall m a (r :: RuntimeRep) (b :: TYPE r) . Monad m
         => m a -> (a -> Code m b) -> Code m b
bindCode q k = liftCode (q >>= examineCode . k)

-- | Variant of (>>) which allows effectful computations to be injected
-- into code generation.
bindCode_ :: forall m a (r :: RuntimeRep) (b :: TYPE r) . Monad m
          => m a -> Code m b -> Code m b
bindCode_ q c = liftCode ( q >> examineCode c)

-- | A useful combinator for embedding monadic actions into 'Code'
-- @
-- myCode :: ... => Code m a
-- myCode = joinCode $ do
--   x <- someSideEffect
--   return (makeCodeWith x)
-- @
joinCode :: forall m (r :: RuntimeRep) (a :: TYPE r) . Monad m
         => m (Code m a) -> Code m a
joinCode = flip bindCode id

----------------------------------------------------
-- Packaged versions for the programmer, hiding the Quasi-ness


-- | Report an error (True) or warning (False),
-- but carry on; use 'fail' to stop.
report  :: Bool -> String -> Q ()
report b s = Q (qReport b s)
{-# DEPRECATED report "Use reportError or reportWarning instead" #-} -- deprecated in 7.6

-- | Report an error to the user, but allow the current splice's computation to carry on. To abort the computation, use 'fail'.
reportError :: String -> Q ()
reportError = report True

-- | Report a warning to the user, and carry on.
reportWarning :: String -> Q ()
reportWarning = report False

-- | Recover from errors raised by 'reportError' or 'fail'.
recover :: Q a -- ^ handler to invoke on failure
        -> Q a -- ^ computation to run
        -> Q a
recover (Q r) (Q m) = Q (qRecover r m)

-- We don't export lookupName; the Bool isn't a great API
-- Instead we export lookupTypeName, lookupValueName
lookupName :: Bool -> String -> Q (Maybe Name)
lookupName ns s = Q (qLookupName ns s)

-- | Look up the given name in the (type namespace of the) current splice's scope. See "Language.Haskell.TH.Syntax#namelookup" for more details.
lookupTypeName :: String -> Q (Maybe Name)
lookupTypeName  s = Q (qLookupName True s)

-- | Look up the given name in the (value namespace of the) current splice's scope. See "Language.Haskell.TH.Syntax#namelookup" for more details.
lookupValueName :: String -> Q (Maybe Name)
lookupValueName s = Q (qLookupName False s)

{-
Note [Name lookup]
~~~~~~~~~~~~~~~~~~
-}
{- $namelookup #namelookup#
The functions 'lookupTypeName' and 'lookupValueName' provide
a way to query the current splice's context for what names
are in scope. The function 'lookupTypeName' queries the type
namespace, whereas 'lookupValueName' queries the value namespace,
but the functions are otherwise identical.

A call @lookupValueName s@ will check if there is a value
with name @s@ in scope at the current splice's location. If
there is, the @Name@ of this value is returned;
if not, then @Nothing@ is returned.

The returned name cannot be \"captured\".
For example:

> f = "global"
> g = $( do
>          Just nm <- lookupValueName "f"
>          [| let f = "local" in $( varE nm ) |]

In this case, @g = \"global\"@; the call to @lookupValueName@
returned the global @f@, and this name was /not/ captured by
the local definition of @f@.

The lookup is performed in the context of the /top-level/ splice
being run. For example:

> f = "global"
> g = $( [| let f = "local" in
>            $(do
>                Just nm <- lookupValueName "f"
>                varE nm
>             ) |] )

Again in this example, @g = \"global\"@, because the call to
@lookupValueName@ queries the context of the outer-most @$(...)@.

Operators should be queried without any surrounding parentheses, like so:

> lookupValueName "+"

Qualified names are also supported, like so:

> lookupValueName "Prelude.+"
> lookupValueName "Prelude.map"

-}


{- | 'reify' looks up information about the 'Name'. It will fail with
a compile error if the 'Name' is not visible. A 'Name' is visible if it is
imported or defined in a prior top-level declaration group. See the
documentation for 'newDeclarationGroup' for more details.

It is sometimes useful to construct the argument name using 'lookupTypeName' or 'lookupValueName'
to ensure that we are reifying from the right namespace. For instance, in this context:

> data D = D

which @D@ does @reify (mkName \"D\")@ return information about? (Answer: @D@-the-type, but don't rely on it.)
To ensure we get information about @D@-the-value, use 'lookupValueName':

> do
>   Just nm <- lookupValueName "D"
>   reify nm

and to get information about @D@-the-type, use 'lookupTypeName'.
-}
reify :: Name -> Q Info
reify v = Q (qReify v)

{- | @reifyFixity nm@ attempts to find a fixity declaration for @nm@. For
example, if the function @foo@ has the fixity declaration @infixr 7 foo@, then
@reifyFixity 'foo@ would return @'Just' ('Fixity' 7 'InfixR')@. If the function
@bar@ does not have a fixity declaration, then @reifyFixity 'bar@ returns
'Nothing', so you may assume @bar@ has 'defaultFixity'.
-}
reifyFixity :: Name -> Q (Maybe Fixity)
reifyFixity nm = Q (qReifyFixity nm)

{- | @reifyType nm@ attempts to find the type or kind of @nm@. For example,
@reifyType 'not@   returns @Bool -> Bool@, and
@reifyType ''Bool@ returns @Type@.
This works even if there's no explicit signature and the type or kind is inferred.
-}
reifyType :: Name -> Q Type
reifyType nm = Q (qReifyType nm)

{- | Template Haskell is capable of reifying information about types and
terms defined in previous declaration groups. Top-level declaration splices break up
declaration groups.

For an example, consider this  code block. We define a datatype @X@ and
then try to call 'reify' on the datatype.

@
module Check where

data X = X
    deriving Eq

$(do
    info <- reify ''X
    runIO $ print info
 )
@

This code fails to compile, noting that @X@ is not available for reification at the site of 'reify'. We can fix this by creating a new declaration group using an empty top-level splice:

@
data X = X
    deriving Eq

$(pure [])

$(do
    info <- reify ''X
    runIO $ print info
 )
@

We provide 'newDeclarationGroup' as a means of documenting this behavior
and providing a name for the pattern.

Since top level splices infer the presence of the @$( ... )@ brackets, we can also write:

@
data X = X
    deriving Eq

newDeclarationGroup

$(do
    info <- reify ''X
    runIO $ print info
 )
@

-}
newDeclarationGroup :: Q [Dec]
newDeclarationGroup = pure []

{- | @reifyInstances nm tys@ returns a list of all visible instances (see below for "visible")
of @nm tys@. That is,
if @nm@ is the name of a type class, then all instances of this class at the types @tys@
are returned. Alternatively, if @nm@ is the name of a data family or type family,
all instances of this family at the types @tys@ are returned.

Note that this is a \"shallow\" test; the declarations returned merely have
instance heads which unify with @nm tys@, they need not actually be satisfiable.

  - @reifyInstances ''Eq [ 'TupleT' 2 \``AppT`\` 'ConT' ''A \``AppT`\` 'ConT' ''B ]@ contains
    the @instance (Eq a, Eq b) => Eq (a, b)@ regardless of whether @A@ and
    @B@ themselves implement 'Eq'

  - @reifyInstances ''Show [ 'VarT' ('mkName' "a") ]@ produces every available
    instance of 'Eq'

There is one edge case: @reifyInstances ''Typeable tys@ currently always
produces an empty list (no matter what @tys@ are given).

In principle, the *visible* instances are
* all instances defined in a prior top-level declaration group
  (see docs on @newDeclarationGroup@), or
* all instances defined in any module transitively imported by the
  module being compiled

However, actually searching all modules transitively below the one being
compiled is unreasonably expensive, so @reifyInstances@ will report only the
instance for modules that GHC has had some cause to visit during this
compilation.  This is a shortcoming: @reifyInstances@ might fail to report
instances for a type that is otherwise unusued, or instances defined in a
different component.  You can work around this shortcoming by explicitly importing the modules
whose instances you want to be visible. GHC issue <https://gitlab.haskell.org/ghc/ghc/-/issues/20529#note_388980 #20529>
has some discussion around this.

-}
reifyInstances :: Name -> [Type] -> Q [InstanceDec]
reifyInstances cls tys = Q (qReifyInstances cls tys)

{- | @reifyRoles nm@ returns the list of roles associated with the parameters
(both visible and invisible) of
the tycon @nm@. Fails if @nm@ cannot be found or is not a tycon.
The returned list should never contain 'InferR'.

An invisible parameter to a tycon is often a kind parameter. For example, if
we have

@
type Proxy :: forall k. k -> Type
data Proxy a = MkProxy
@

and @reifyRoles Proxy@, we will get @['NominalR', 'PhantomR']@. The 'NominalR' is
the role of the invisible @k@ parameter. Kind parameters are always nominal.
-}
reifyRoles :: Name -> Q [Role]
reifyRoles nm = Q (qReifyRoles nm)

-- | @reifyAnnotations target@ returns the list of annotations
-- associated with @target@.  Only the annotations that are
-- appropriately typed is returned.  So if you have @Int@ and @String@
-- annotations for the same target, you have to call this function twice.
reifyAnnotations :: Data a => AnnLookup -> Q [a]
reifyAnnotations an = Q (qReifyAnnotations an)

-- | @reifyModule mod@ looks up information about module @mod@.  To
-- look up the current module, call this function with the return
-- value of 'Language.Haskell.TH.Lib.thisModule'.
reifyModule :: Module -> Q ModuleInfo
reifyModule m = Q (qReifyModule m)

-- | @reifyConStrictness nm@ looks up the strictness information for the fields
-- of the constructor with the name @nm@. Note that the strictness information
-- that 'reifyConStrictness' returns may not correspond to what is written in
-- the source code. For example, in the following data declaration:
--
-- @
-- data Pair a = Pair a a
-- @
--
-- 'reifyConStrictness' would return @['DecidedLazy', DecidedLazy]@ under most
-- circumstances, but it would return @['DecidedStrict', DecidedStrict]@ if the
-- @-XStrictData@ language extension was enabled.
reifyConStrictness :: Name -> Q [DecidedStrictness]
reifyConStrictness n = Q (qReifyConStrictness n)

-- | Is the list of instances returned by 'reifyInstances' nonempty?
--
-- If you're confused by an instance not being visible despite being
-- defined in the same module and above the splice in question, see the
-- docs for 'newDeclarationGroup' for a possible explanation.
isInstance :: Name -> [Type] -> Q Bool
isInstance nm tys = do { decs <- reifyInstances nm tys
                       ; return (not (null decs)) }

-- | The location at which this computation is spliced.
location :: Q Loc
location = Q qLocation

-- |The 'runIO' function lets you run an I\/O computation in the 'Q' monad.
-- Take care: you are guaranteed the ordering of calls to 'runIO' within
-- a single 'Q' computation, but not about the order in which splices are run.
--
-- Note: for various murky reasons, stdout and stderr handles are not
-- necessarily flushed when the compiler finishes running, so you should
-- flush them yourself.
runIO :: IO a -> Q a
runIO m = Q (qRunIO m)

-- | Get the package root for the current package which is being compiled.
-- This can be set explicitly with the -package-root flag but is normally
-- just the current working directory.
--
-- The motivation for this flag is to provide a principled means to remove the
-- assumption from splices that they will be executed in the directory where the
-- cabal file resides. Projects such as haskell-language-server can't and don't
-- change directory when compiling files but instead set the -package-root flag
-- appropiately.
getPackageRoot :: Q FilePath
getPackageRoot = Q qGetPackageRoot

-- | The input is a filepath, which if relative is offset by the package root.
makeRelativeToProject :: FilePath -> Q FilePath
makeRelativeToProject fp | isRelative fp = do
  root <- getPackageRoot
  return (root </> fp)
makeRelativeToProject fp = return fp



-- | Record external files that runIO is using (dependent upon).
-- The compiler can then recognize that it should re-compile the Haskell file
-- when an external file changes.
--
-- Expects an absolute file path.
--
-- Notes:
--
--   * ghc -M does not know about these dependencies - it does not execute TH.
--
--   * The dependency is based on file content, not a modification time
addDependentFile :: FilePath -> Q ()
addDependentFile fp = Q (qAddDependentFile fp)

-- | Obtain a temporary file path with the given suffix. The compiler will
-- delete this file after compilation.
addTempFile :: String -> Q FilePath
addTempFile suffix = Q (qAddTempFile suffix)

-- | Add additional top-level declarations. The added declarations will be type
-- checked along with the current declaration group.
addTopDecls :: [Dec] -> Q ()
addTopDecls ds = Q (qAddTopDecls ds)

-- |
addForeignFile :: ForeignSrcLang -> String -> Q ()
addForeignFile = addForeignSource
{-# DEPRECATED addForeignFile
               "Use 'Language.Haskell.TH.Syntax.addForeignSource' instead"
  #-} -- deprecated in 8.6

-- | Emit a foreign file which will be compiled and linked to the object for
-- the current module. Currently only languages that can be compiled with
-- the C compiler are supported, and the flags passed as part of -optc will
-- be also applied to the C compiler invocation that will compile them.
--
-- Note that for non-C languages (for example C++) @extern "C"@ directives
-- must be used to get symbols that we can access from Haskell.
--
-- To get better errors, it is recommended to use #line pragmas when
-- emitting C files, e.g.
--
-- > {-# LANGUAGE CPP #-}
-- > ...
-- > addForeignSource LangC $ unlines
-- >   [ "#line " ++ show (__LINE__ + 1) ++ " " ++ show __FILE__
-- >   , ...
-- >   ]
addForeignSource :: ForeignSrcLang -> String -> Q ()
addForeignSource lang src = do
  let suffix = case lang of
                 LangC      -> "c"
                 LangCxx    -> "cpp"
                 LangObjc   -> "m"
                 LangObjcxx -> "mm"
                 LangAsm    -> "s"
                 LangJs     -> "js"
                 RawObject  -> "a"
  path <- addTempFile suffix
  runIO $ writeFile path src
  addForeignFilePath lang path

-- | Same as 'addForeignSource', but expects to receive a path pointing to the
-- foreign file instead of a 'String' of its contents. Consider using this in
-- conjunction with 'addTempFile'.
--
-- This is a good alternative to 'addForeignSource' when you are trying to
-- directly link in an object file.
addForeignFilePath :: ForeignSrcLang -> FilePath -> Q ()
addForeignFilePath lang fp = Q (qAddForeignFilePath lang fp)

-- | Add a finalizer that will run in the Q monad after the current module has
-- been type checked. This only makes sense when run within a top-level splice.
--
-- The finalizer is given the local type environment at the splice point. Thus
-- 'reify' is able to find the local definitions when executed inside the
-- finalizer.
addModFinalizer :: Q () -> Q ()
addModFinalizer act = Q (qAddModFinalizer (unQ act))

-- | Adds a core plugin to the compilation pipeline.
--
-- @addCorePlugin m@ has almost the same effect as passing @-fplugin=m@ to ghc
-- in the command line. The major difference is that the plugin module @m@
-- must not belong to the current package. When TH executes, it is too late
-- to tell the compiler that we needed to compile first a plugin module in the
-- current package.
addCorePlugin :: String -> Q ()
addCorePlugin plugin = Q (qAddCorePlugin plugin)

-- | Get state from the 'Q' monad. Note that the state is local to the
-- Haskell module in which the Template Haskell expression is executed.
getQ :: Typeable a => Q (Maybe a)
getQ = Q qGetQ

-- | Replace the state in the 'Q' monad. Note that the state is local to the
-- Haskell module in which the Template Haskell expression is executed.
putQ :: Typeable a => a -> Q ()
putQ x = Q (qPutQ x)

-- | Determine whether the given language extension is enabled in the 'Q' monad.
isExtEnabled :: Extension -> Q Bool
isExtEnabled ext = Q (qIsExtEnabled ext)

-- | List all enabled language extensions.
extsEnabled :: Q [Extension]
extsEnabled = Q qExtsEnabled

-- | Add Haddock documentation to the specified location. This will overwrite
-- any documentation at the location if it already exists. This will reify the
-- specified name, so it must be in scope when you call it. If you want to add
-- documentation to something that you are currently splicing, you can use
-- 'addModFinalizer' e.g.
--
-- > do
-- >   let nm = mkName "x"
-- >   addModFinalizer $ putDoc (DeclDoc nm) "Hello"
-- >   [d| $(varP nm) = 42 |]
--
-- The helper functions 'withDecDoc' and 'withDecsDoc' will do this for you, as
-- will the 'funD_doc' and other @_doc@ combinators.
-- You most likely want to have the @-haddock@ flag turned on when using this.
-- Adding documentation to anything outside of the current module will cause an
-- error.
putDoc :: DocLoc -> String -> Q ()
putDoc t s = Q (qPutDoc t s)

-- | Retreives the Haddock documentation at the specified location, if one
-- exists.
-- It can be used to read documentation on things defined outside of the current
-- module, provided that those modules were compiled with the @-haddock@ flag.
getDoc :: DocLoc -> Q (Maybe String)
getDoc n = Q (qGetDoc n)

instance MonadIO Q where
  liftIO = runIO

instance Quasi Q where
  qNewName            = newName
  qReport             = report
  qRecover            = recover
  qReify              = reify
  qReifyFixity        = reifyFixity
  qReifyType          = reifyType
  qReifyInstances     = reifyInstances
  qReifyRoles         = reifyRoles
  qReifyAnnotations   = reifyAnnotations
  qReifyModule        = reifyModule
  qReifyConStrictness = reifyConStrictness
  qLookupName         = lookupName
  qLocation           = location
  qGetPackageRoot     = getPackageRoot
  qAddDependentFile   = addDependentFile
  qAddTempFile        = addTempFile
  qAddTopDecls        = addTopDecls
  qAddForeignFilePath = addForeignFilePath
  qAddModFinalizer    = addModFinalizer
  qAddCorePlugin      = addCorePlugin
  qGetQ               = getQ
  qPutQ               = putQ
  qIsExtEnabled       = isExtEnabled
  qExtsEnabled        = extsEnabled
  qPutDoc             = putDoc
  qGetDoc             = getDoc


----------------------------------------------------
-- The following operations are used solely in GHC.HsToCore.Quote when
-- desugaring brackets. They are not necessary for the user, who can use
-- ordinary return and (>>=) etc

sequenceQ :: forall m . Monad m => forall a . [m a] -> m [a]
sequenceQ = sequence


-----------------------------------------------------
--
--              The Lift class
--
-----------------------------------------------------

-- | A 'Lift' instance can have any of its values turned into a Template
-- Haskell expression. This is needed when a value used within a Template
-- Haskell quotation is bound outside the Oxford brackets (@[| ... |]@ or
-- @[|| ... ||]@) but not at the top level. As an example:
--
-- > add1 :: Int -> Code Q Int
-- > add1 x = [|| x + 1 ||]
--
-- Template Haskell has no way of knowing what value @x@ will take on at
-- splice-time, so it requires the type of @x@ to be an instance of 'Lift'.
--
-- A 'Lift' instance must satisfy @$(lift x) ≡ x@ and @$$(liftTyped x) ≡ x@
-- for all @x@, where @$(...)@ and @$$(...)@ are Template Haskell splices.
-- It is additionally expected that @'lift' x ≡ 'unTypeCode' ('liftTyped' x)@.
--
-- 'Lift' instances can be derived automatically by use of the @-XDeriveLift@
-- GHC language extension:
--
-- > {-# LANGUAGE DeriveLift #-}
-- > module Foo where
-- >
-- > import Language.Haskell.TH.Syntax
-- >
-- > data Bar a = Bar1 a (Bar a) | Bar2 String
-- >   deriving Lift
--
-- Representation-polymorphic since /template-haskell-2.16.0.0/.
class Lift (t :: TYPE r) where
  -- | Turn a value into a Template Haskell expression, suitable for use in
  -- a splice.
  lift :: Quote m => t -> m Exp
#if __GLASGOW_HASKELL__ >= 901
  default lift :: (r ~ ('BoxedRep 'Lifted), Quote m) => t -> m Exp
#else
  default lift :: (r ~ 'LiftedRep, Quote m) => t -> m Exp
#endif
  lift = unTypeCode . liftTyped

  -- | Turn a value into a Template Haskell typed expression, suitable for use
  -- in a typed splice.
  --
  -- @since 2.16.0.0
  liftTyped :: Quote m => t -> Code m t


-- If you add any instances here, consider updating test th/TH_Lift
instance Lift Integer where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL x))

instance Lift Int where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

-- | @since 2.16.0.0
instance Lift Int# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntPrimL (fromIntegral (I# x))))

instance Lift Int8 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Int16 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Int32 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Int64 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

-- | @since 2.16.0.0
instance Lift Word# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (WordPrimL (fromIntegral (W# x))))

instance Lift Word where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Word8 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Word16 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Word32 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Word64 where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift Natural where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (IntegerL (fromIntegral x)))

instance Lift (Fixed.Fixed a) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (Fixed.MkFixed x) = do
    ex <- lift x
    return (ConE mkFixedName `AppE` ex)
    where
      mkFixedName = 'Fixed.MkFixed

instance Integral a => Lift (Ratio a) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (RationalL (toRational x)))

instance Lift Float where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (RationalL (toRational x)))

-- | @since 2.16.0.0
instance Lift Float# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (FloatPrimL (toRational (F# x))))

instance Lift Double where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (RationalL (toRational x)))

-- | @since 2.16.0.0
instance Lift Double# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (DoublePrimL (toRational (D# x))))

instance Lift Char where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (CharL x))

-- | @since 2.16.0.0
instance Lift Char# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x = return (LitE (CharPrimL (C# x)))

instance Lift Bool where
  liftTyped x = unsafeCodeCoerce (lift x)

  lift True  = return (ConE trueName)
  lift False = return (ConE falseName)

-- | Produces an 'Addr#' literal from the NUL-terminated C-string starting at
-- the given memory address.
--
-- @since 2.16.0.0
instance Lift Addr# where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = return (LitE (StringPrimL (map (fromIntegral . ord) (unpackCString# x))))

#if __GLASGOW_HASKELL__ >= 903

-- |
-- @since 2.19.0.0
instance Lift ByteArray where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (ByteArray b) = return
    (AppE (AppE (VarE addrToByteArrayName) (LitE (IntegerL (fromIntegral len))))
      (LitE (BytesPrimL (Bytes ptr 0 (fromIntegral len)))))
    where
      len# = sizeofByteArray# b
      len = I# len#
      pb :: ByteArray#
      !(ByteArray pb)
        | isTrue# (isByteArrayPinned# b) = ByteArray b
        | otherwise = runST $ ST $
          \s -> case newPinnedByteArray# len# s of
            (# s', mb #) -> case copyByteArray# b 0# mb 0# len# s' of
              s'' -> case unsafeFreezeByteArray# mb s'' of
                (# s''', ret #) -> (# s''', ByteArray ret #)
      ptr :: ForeignPtr Word8
      ptr = ForeignPtr (byteArrayContents# pb) (PlainPtr (unsafeCoerce# pb))

addrToByteArrayName :: Name
addrToByteArrayName = 'addrToByteArray

addrToByteArray :: Int -> Addr# -> ByteArray
addrToByteArray (I# len) addr = runST $ ST $
  \s -> case newByteArray# len s of
    (# s', mb #) -> case copyAddrToByteArray# addr mb 0# len s' of
      s'' -> case unsafeFreezeByteArray# mb s'' of
        (# s''', ret #) -> (# s''', ByteArray ret #)

#endif

instance Lift a => Lift (Maybe a) where
  liftTyped x = unsafeCodeCoerce (lift x)

  lift Nothing  = return (ConE nothingName)
  lift (Just x) = liftM (ConE justName `AppE`) (lift x)

instance (Lift a, Lift b) => Lift (Either a b) where
  liftTyped x = unsafeCodeCoerce (lift x)

  lift (Left x)  = liftM (ConE leftName  `AppE`) (lift x)
  lift (Right y) = liftM (ConE rightName `AppE`) (lift y)

instance Lift a => Lift [a] where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift xs = do { xs' <- mapM lift xs; return (ListE xs') }

liftString :: Quote m => String -> m Exp
-- Used in GHC.Tc.Gen.Expr to short-circuit the lifting for strings
liftString s = return (LitE (StringL s))

-- | @since 2.15.0.0
instance Lift a => Lift (NonEmpty a) where
  liftTyped x = unsafeCodeCoerce (lift x)

  lift (x :| xs) = do
    x' <- lift x
    xs' <- lift xs
    return (InfixE (Just x') (ConE nonemptyName) (Just xs'))

-- | @since 2.15.0.0
instance Lift Void where
  liftTyped = liftCode . absurd
  lift = pure . absurd

instance Lift () where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift () = return (ConE (tupleDataName 0))

instance (Lift a, Lift b) => Lift (a, b) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b)
    = liftM TupE $ sequence $ map (fmap Just) [lift a, lift b]

instance (Lift a, Lift b, Lift c) => Lift (a, b, c) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b, c)
    = liftM TupE $ sequence $ map (fmap Just) [lift a, lift b, lift c]

instance (Lift a, Lift b, Lift c, Lift d) => Lift (a, b, c, d) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b, c, d)
    = liftM TupE $ sequence $ map (fmap Just) [lift a, lift b, lift c, lift d]

instance (Lift a, Lift b, Lift c, Lift d, Lift e)
      => Lift (a, b, c, d, e) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b, c, d, e)
    = liftM TupE $ sequence $ map (fmap Just) [ lift a, lift b
                                              , lift c, lift d, lift e ]

instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f)
      => Lift (a, b, c, d, e, f) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b, c, d, e, f)
    = liftM TupE $ sequence $ map (fmap Just) [ lift a, lift b, lift c
                                              , lift d, lift e, lift f ]

instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f, Lift g)
      => Lift (a, b, c, d, e, f, g) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (a, b, c, d, e, f, g)
    = liftM TupE $ sequence $ map (fmap Just) [ lift a, lift b, lift c
                                              , lift d, lift e, lift f, lift g ]

-- | @since 2.16.0.0
instance Lift (# #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# #) = return (ConE (unboxedTupleTypeName 0))

-- | @since 2.16.0.0
instance (Lift a) => Lift (# a #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [lift a]

-- | @since 2.16.0.0
instance (Lift a, Lift b) => Lift (# a, b #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [lift a, lift b]

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c)
      => Lift (# a, b, c #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b, c #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [lift a, lift b, lift c]

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d)
      => Lift (# a, b, c, d #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b, c, d #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [ lift a, lift b
                                                     , lift c, lift d ]

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e)
      => Lift (# a, b, c, d, e #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b, c, d, e #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [ lift a, lift b
                                                     , lift c, lift d, lift e ]

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f)
      => Lift (# a, b, c, d, e, f #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b, c, d, e, f #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [ lift a, lift b, lift c
                                                     , lift d, lift e, lift f ]

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f, Lift g)
      => Lift (# a, b, c, d, e, f, g #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift (# a, b, c, d, e, f, g #)
    = liftM UnboxedTupE $ sequence $ map (fmap Just) [ lift a, lift b, lift c
                                                     , lift d, lift e, lift f
                                                     , lift g ]

-- | @since 2.16.0.0
instance (Lift a, Lift b) => Lift (# a | b #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 2
        (# | y #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 2

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c)
      => Lift (# a | b | c #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 3
        (# | y | #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 3
        (# | | y #) -> UnboxedSumE <$> lift y <*> pure 3 <*> pure 3

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d)
      => Lift (# a | b | c | d #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | | | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 4
        (# | y | | #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 4
        (# | | y | #) -> UnboxedSumE <$> lift y <*> pure 3 <*> pure 4
        (# | | | y #) -> UnboxedSumE <$> lift y <*> pure 4 <*> pure 4

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e)
      => Lift (# a | b | c | d | e #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | | | | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 5
        (# | y | | | #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 5
        (# | | y | | #) -> UnboxedSumE <$> lift y <*> pure 3 <*> pure 5
        (# | | | y | #) -> UnboxedSumE <$> lift y <*> pure 4 <*> pure 5
        (# | | | | y #) -> UnboxedSumE <$> lift y <*> pure 5 <*> pure 5

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f)
      => Lift (# a | b | c | d | e | f #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | | | | | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 6
        (# | y | | | | #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 6
        (# | | y | | | #) -> UnboxedSumE <$> lift y <*> pure 3 <*> pure 6
        (# | | | y | | #) -> UnboxedSumE <$> lift y <*> pure 4 <*> pure 6
        (# | | | | y | #) -> UnboxedSumE <$> lift y <*> pure 5 <*> pure 6
        (# | | | | | y #) -> UnboxedSumE <$> lift y <*> pure 6 <*> pure 6

-- | @since 2.16.0.0
instance (Lift a, Lift b, Lift c, Lift d, Lift e, Lift f, Lift g)
      => Lift (# a | b | c | d | e | f | g #) where
  liftTyped x = unsafeCodeCoerce (lift x)
  lift x
    = case x of
        (# y | | | | | | #) -> UnboxedSumE <$> lift y <*> pure 1 <*> pure 7
        (# | y | | | | | #) -> UnboxedSumE <$> lift y <*> pure 2 <*> pure 7
        (# | | y | | | | #) -> UnboxedSumE <$> lift y <*> pure 3 <*> pure 7
        (# | | | y | | | #) -> UnboxedSumE <$> lift y <*> pure 4 <*> pure 7
        (# | | | | y | | #) -> UnboxedSumE <$> lift y <*> pure 5 <*> pure 7
        (# | | | | | y | #) -> UnboxedSumE <$> lift y <*> pure 6 <*> pure 7
        (# | | | | | | y #) -> UnboxedSumE <$> lift y <*> pure 7 <*> pure 7

-- TH has a special form for literal strings,
-- which we should take advantage of.
-- NB: the lhs of the rule has no args, so that
--     the rule will apply to a 'lift' all on its own
--     which happens to be the way the type checker
--     creates it.
{-# RULES "TH:liftString" lift = \s -> return (LitE (StringL s)) #-}


trueName, falseName :: Name
trueName  = 'True
falseName = 'False

nothingName, justName :: Name
nothingName = 'Nothing
justName    = 'Just

leftName, rightName :: Name
leftName  = 'Left
rightName = 'Right

nonemptyName :: Name
nonemptyName = '(:|)

oneName, manyName :: Name
oneName  = 'One
manyName = 'Many

-----------------------------------------------------
--
--              Generic Lift implementations
--
-----------------------------------------------------

-- | 'dataToQa' is an internal utility function for constructing generic
-- conversion functions from types with 'Data' instances to various
-- quasi-quoting representations.  See the source of 'dataToExpQ' and
-- 'dataToPatQ' for two example usages: @mkCon@, @mkLit@
-- and @appQ@ are overloadable to account for different syntax for
-- expressions and patterns; @antiQ@ allows you to override type-specific
-- cases, a common usage is just @const Nothing@, which results in
-- no overloading.
dataToQa  ::  forall m a k q. (Quote m, Data a)
          =>  (Name -> k)
          ->  (Lit -> m q)
          ->  (k -> [m q] -> m q)
          ->  (forall b . Data b => b -> Maybe (m q))
          ->  a
          ->  m q
dataToQa mkCon mkLit appCon antiQ t =
    case antiQ t of
      Nothing ->
          case constrRep constr of
            AlgConstr _ ->
                appCon (mkCon funOrConName) conArgs
              where
                funOrConName :: Name
                funOrConName =
                    case showConstr constr of
                      "(:)"       -> Name (mkOccName ":")
                                          (NameG DataName
                                                (mkPkgName "ghc-prim")
                                                (mkModName "GHC.Types"))
                      con@"[]"    -> Name (mkOccName con)
                                          (NameG DataName
                                                (mkPkgName "ghc-prim")
                                                (mkModName "GHC.Types"))
                      con@('(':_) -> Name (mkOccName con)
                                          (NameG DataName
                                                (mkPkgName "ghc-prim")
                                                (mkModName "GHC.Tuple.Prim"))

                      -- Tricky case: see Note [Data for non-algebraic types]
                      fun@(x:_)   | startsVarSym x || startsVarId x
                                  -> mkNameG_v tyconPkg tyconMod fun
                      con         -> mkNameG_d tyconPkg tyconMod con

                  where
                    tycon :: TyCon
                    tycon = (typeRepTyCon . typeOf) t

                    tyconPkg, tyconMod :: String
                    tyconPkg = tyConPackage tycon
                    tyconMod = tyConModule  tycon

                conArgs :: [m q]
                conArgs = gmapQ (dataToQa mkCon mkLit appCon antiQ) t
            IntConstr n ->
                mkLit $ IntegerL n
            FloatConstr n ->
                mkLit $ RationalL n
            CharConstr c ->
                mkLit $ CharL c
        where
          constr :: Constr
          constr = toConstr t

      Just y -> y


{- Note [Data for non-algebraic types]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Class Data was originally intended for algebraic data types.  But
it is possible to use it for abstract types too.  For example, in
package `text` we find

  instance Data Text where
    ...
    toConstr _ = packConstr

  packConstr :: Constr
  packConstr = mkConstr textDataType "pack" [] Prefix

Here `packConstr` isn't a real data constructor, it's an ordinary
function.  Two complications

* In such a case, we must take care to build the Name using
  mkNameG_v (for values), not mkNameG_d (for data constructors).
  See #10796.

* The pseudo-constructor is named only by its string, here "pack".
  But 'dataToQa' needs the TyCon of its defining module, and has
  to assume it's defined in the same module as the TyCon itself.
  But nothing enforces that; #12596 shows what goes wrong if
  "pack" is defined in a different module than the data type "Text".
  -}

-- | 'dataToExpQ' converts a value to a 'Exp' representation of the
-- same value, in the SYB style. It is generalized to take a function
-- override type-specific cases; see 'liftData' for a more commonly
-- used variant.
dataToExpQ  ::  (Quote m, Data a)
            =>  (forall b . Data b => b -> Maybe (m Exp))
            ->  a
            ->  m Exp
dataToExpQ = dataToQa varOrConE litE (foldl appE)
    where
          -- Make sure that VarE is used if the Constr value relies on a
          -- function underneath the surface (instead of a constructor).
          -- See #10796.
          varOrConE s =
            case nameSpace s of
                 Just VarName      -> return (VarE s)
                 Just (FldName {}) -> return (VarE s)
                 Just DataName     -> return (ConE s)
                 _ -> error $ "Can't construct an expression from name "
                           ++ showName s
          appE x y = do { a <- x; b <- y; return (AppE a b)}
          litE c = return (LitE c)

-- | 'liftData' is a variant of 'lift' in the 'Lift' type class which
-- works for any type with a 'Data' instance.
liftData :: (Quote m, Data a) => a -> m Exp
liftData = dataToExpQ (const Nothing)

-- | 'dataToPatQ' converts a value to a 'Pat' representation of the same
-- value, in the SYB style. It takes a function to handle type-specific cases,
-- alternatively, pass @const Nothing@ to get default behavior.
dataToPatQ  ::  (Quote m, Data a)
            =>  (forall b . Data b => b -> Maybe (m Pat))
            ->  a
            ->  m Pat
dataToPatQ = dataToQa id litP conP
    where litP l = return (LitP l)
          conP n ps =
            case nameSpace n of
                Just DataName -> do
                    ps' <- sequence ps
                    return (ConP n [] ps')
                _ -> error $ "Can't construct a pattern from name "
                          ++ showName n

-----------------------------------------------------
--              Names and uniques
-----------------------------------------------------

newtype ModName = ModName String        -- Module name
 deriving (Show,Eq,Ord,Data,Generic)

newtype PkgName = PkgName String        -- package name
 deriving (Show,Eq,Ord,Data,Generic)

-- | Obtained from 'reifyModule' and 'Language.Haskell.TH.Lib.thisModule'.
data Module = Module PkgName ModName -- package qualified module name
 deriving (Show,Eq,Ord,Data,Generic)

newtype OccName = OccName String
 deriving (Show,Eq,Ord,Data,Generic)

mkModName :: String -> ModName
mkModName s = ModName s

modString :: ModName -> String
modString (ModName m) = m


mkPkgName :: String -> PkgName
mkPkgName s = PkgName s

pkgString :: PkgName -> String
pkgString (PkgName m) = m


-----------------------------------------------------
--              OccName
-----------------------------------------------------

mkOccName :: String -> OccName
mkOccName s = OccName s

occString :: OccName -> String
occString (OccName occ) = occ


-----------------------------------------------------
--               Names
-----------------------------------------------------
--
-- For "global" names ('NameG') we need a totally unique name,
-- so we must include the name-space of the thing
--
-- For unique-numbered things ('NameU'), we've got a unique reference
-- anyway, so no need for name space
--
-- For dynamically bound thing ('NameS') we probably want them to
-- in a context-dependent way, so again we don't want the name
-- space.  For example:
--
-- > let v = mkName "T" in [| data $v = $v |]
--
-- Here we use the same Name for both type constructor and data constructor
--
--
-- NameL and NameG are bound *outside* the TH syntax tree
-- either globally (NameG) or locally (NameL). Ex:
--
-- > f x = $(h [| (map, x) |])
--
-- The 'map' will be a NameG, and 'x' wil be a NameL
--
-- These Names should never appear in a binding position in a TH syntax tree

{- $namecapture #namecapture#
Much of 'Name' API is concerned with the problem of /name capture/, which
can be seen in the following example.

> f expr = [| let x = 0 in $expr |]
> ...
> g x = $( f [| x |] )
> h y = $( f [| y |] )

A naive desugaring of this would yield:

> g x = let x = 0 in x
> h y = let x = 0 in y

All of a sudden, @g@ and @h@ have different meanings! In this case,
we say that the @x@ in the RHS of @g@ has been /captured/
by the binding of @x@ in @f@.

What we actually want is for the @x@ in @f@ to be distinct from the
@x@ in @g@, so we get the following desugaring:

> g x = let x' = 0 in x
> h y = let x' = 0 in y

which avoids name capture as desired.

In the general case, we say that a @Name@ can be captured if
the thing it refers to can be changed by adding new declarations.
-}

{- |
An abstract type representing names in the syntax tree.

'Name's can be constructed in several ways, which come with different
name-capture guarantees (see "Language.Haskell.TH.Syntax#namecapture" for
an explanation of name capture):

  * the built-in syntax @'f@ and @''T@ can be used to construct names,
    The expression @'f@ gives a @Name@ which refers to the value @f@
    currently in scope, and @''T@ gives a @Name@ which refers to the
    type @T@ currently in scope. These names can never be captured.

  * 'lookupValueName' and 'lookupTypeName' are similar to @'f@ and
     @''T@ respectively, but the @Name@s are looked up at the point
     where the current splice is being run. These names can never be
     captured.

  * 'newName' monadically generates a new name, which can never
     be captured.

  * 'mkName' generates a capturable name.

Names constructed using @newName@ and @mkName@ may be used in bindings
(such as @let x = ...@ or @\x -> ...@), but names constructed using
@lookupValueName@, @lookupTypeName@, @'f@, @''T@ may not.
-}
data Name = Name OccName NameFlavour deriving (Data, Eq, Generic)

instance Ord Name where
    -- check if unique is different before looking at strings
  (Name o1 f1) `compare` (Name o2 f2) = (f1 `compare` f2)   `thenCmp`
                                        (o1 `compare` o2)

data NameFlavour
  = NameS           -- ^ An unqualified name; dynamically bound
  | NameQ ModName   -- ^ A qualified name; dynamically bound
  | NameU !Uniq     -- ^ A unique local name
  | NameL !Uniq     -- ^ Local name bound outside of the TH AST
  | NameG NameSpace PkgName ModName -- ^ Global name bound outside of the TH AST:
                -- An original name (occurrences only, not binders)
                -- Need the namespace too to be sure which
                -- thing we are naming
  deriving ( Data, Eq, Ord, Show, Generic )

data NameSpace = VarName        -- ^ Variables
               | DataName       -- ^ Data constructors
               | TcClsName      -- ^ Type constructors and classes; Haskell has them
                                -- in the same name space for now.
               | FldName
                 { fldParent :: !String
                   -- ^ The textual name of the parent of the field.
                   --
                   --   - For a field of a datatype, this is the name of the first constructor
                   --     of the datatype (regardless of whether this constructor has this field).
                   --   - For a field of a pattern synonym, this is the name of the pattern synonym.
                 }
               deriving( Eq, Ord, Show, Data, Generic )

-- | @Uniq@ is used by GHC to distinguish names from each other.
type Uniq = Integer

-- | The name without its module prefix.
--
-- ==== __Examples__
--
-- >>> nameBase ''Data.Either.Either
-- "Either"
-- >>> nameBase (mkName "foo")
-- "foo"
-- >>> nameBase (mkName "Module.foo")
-- "foo"
nameBase :: Name -> String
nameBase (Name occ _) = occString occ

-- | Module prefix of a name, if it exists.
--
-- ==== __Examples__
--
-- >>> nameModule ''Data.Either.Either
-- Just "Data.Either"
-- >>> nameModule (mkName "foo")
-- Nothing
-- >>> nameModule (mkName "Module.foo")
-- Just "Module"
nameModule :: Name -> Maybe String
nameModule (Name _ (NameQ m))     = Just (modString m)
nameModule (Name _ (NameG _ _ m)) = Just (modString m)
nameModule _                      = Nothing

-- | A name's package, if it exists.
--
-- ==== __Examples__
--
-- >>> namePackage ''Data.Either.Either
-- Just "base"
-- >>> namePackage (mkName "foo")
-- Nothing
-- >>> namePackage (mkName "Module.foo")
-- Nothing
namePackage :: Name -> Maybe String
namePackage (Name _ (NameG _ p _)) = Just (pkgString p)
namePackage _                      = Nothing

-- | Returns whether a name represents an occurrence of a top-level variable
-- ('VarName'), data constructor ('DataName'), type constructor, or type class
-- ('TcClsName'). If we can't be sure, it returns 'Nothing'.
--
-- ==== __Examples__
--
-- >>> nameSpace 'Prelude.id
-- Just VarName
-- >>> nameSpace (mkName "id")
-- Nothing -- only works for top-level variable names
-- >>> nameSpace 'Data.Maybe.Just
-- Just DataName
-- >>> nameSpace ''Data.Maybe.Maybe
-- Just TcClsName
-- >>> nameSpace ''Data.Ord.Ord
-- Just TcClsName
nameSpace :: Name -> Maybe NameSpace
nameSpace (Name _ (NameG ns _ _)) = Just ns
nameSpace _                       = Nothing

{- |
Generate a capturable name. Occurrences of such names will be
resolved according to the Haskell scoping rules at the occurrence
site.

For example:

> f = [| pi + $(varE (mkName "pi")) |]
> ...
> g = let pi = 3 in $f

In this case, @g@ is desugared to

> g = Prelude.pi + 3

Note that @mkName@ may be used with qualified names:

> mkName "Prelude.pi"

See also 'Language.Haskell.TH.Lib.dyn' for a useful combinator. The above example could
be rewritten using 'Language.Haskell.TH.Lib.dyn' as

> f = [| pi + $(dyn "pi") |]
-}
mkName :: String -> Name
-- The string can have a '.', thus "Foo.baz",
-- giving a dynamically-bound qualified name,
-- in which case we want to generate a NameQ
--
-- Parse the string to see if it has a "." in it
-- so we know whether to generate a qualified or unqualified name
-- It's a bit tricky because we need to parse
--
-- > Foo.Baz.x   as    Qual Foo.Baz x
--
-- So we parse it from back to front
mkName str
  = split [] (reverse str)
  where
    split occ []        = Name (mkOccName occ) NameS
    split occ ('.':rev) | not (null occ)
                        , is_rev_mod_name rev
                        = Name (mkOccName occ) (NameQ (mkModName (reverse rev)))
        -- The 'not (null occ)' guard ensures that
        --      mkName "&." = Name "&." NameS
        -- The 'is_rev_mod' guards ensure that
        --      mkName ".&" = Name ".&" NameS
        --      mkName "^.." = Name "^.." NameS      -- #8633
        --      mkName "Data.Bits..&" = Name ".&" (NameQ "Data.Bits")
        -- This rather bizarre case actually happened; (.&.) is in Data.Bits
    split occ (c:rev)   = split (c:occ) rev

    -- Recognises a reversed module name xA.yB.C,
    -- with at least one component,
    -- and each component looks like a module name
    --   (i.e. non-empty, starts with capital, all alpha)
    is_rev_mod_name rev_mod_str
      | (compt, rest) <- break (== '.') rev_mod_str
      , not (null compt), isUpper (last compt), all is_mod_char compt
      = case rest of
          []             -> True
          (_dot : rest') -> is_rev_mod_name rest'
      | otherwise
      = False

    is_mod_char c = isAlphaNum c || c == '_' || c == '\''

-- | Only used internally
mkNameU :: String -> Uniq -> Name
mkNameU s u = Name (mkOccName s) (NameU u)

-- | Only used internally
mkNameL :: String -> Uniq -> Name
mkNameL s u = Name (mkOccName s) (NameL u)

-- | Only used internally
mkNameQ :: String -> String -> Name
mkNameQ mn occ = Name (mkOccName occ) (NameQ (mkModName mn))

-- | Used for 'x etc, but not available to the programmer
mkNameG :: NameSpace -> String -> String -> String -> Name
mkNameG ns pkg modu occ
  = Name (mkOccName occ) (NameG ns (mkPkgName pkg) (mkModName modu))

mkNameS :: String -> Name
mkNameS n = Name (mkOccName n) NameS

mkNameG_v, mkNameG_tc, mkNameG_d :: String -> String -> String -> Name
mkNameG_v  = mkNameG VarName
mkNameG_tc = mkNameG TcClsName
mkNameG_d  = mkNameG DataName

mkNameG_fld :: String -- ^ package
            -> String -- ^ module
            -> String -- ^ parent (first constructor of parent type)
            -> String -- ^ field name
            -> Name
mkNameG_fld pkg modu con occ = mkNameG (FldName con) pkg modu occ

data NameIs = Alone | Applied | Infix

showName :: Name -> String
showName = showName' Alone

showName' :: NameIs -> Name -> String
showName' ni nm
 = case ni of
       Alone        -> nms
       Applied
        | pnam      -> nms
        | otherwise -> "(" ++ nms ++ ")"
       Infix
        | pnam      -> "`" ++ nms ++ "`"
        | otherwise -> nms
    where
        -- For now, we make the NameQ and NameG print the same, even though
        -- NameQ is a qualified name (so what it means depends on what the
        -- current scope is), and NameG is an original name (so its meaning
        -- should be independent of what's in scope.
        -- We may well want to distinguish them in the end.
        -- Ditto NameU and NameL
        nms = case nm of
          Name occ NameS          -> occString occ
          Name occ (NameQ m)      -> modString m ++ "." ++ occString occ
          Name occ (NameG _ _ m) -> modString m ++ "." ++ occString occ
          Name occ (NameU u)      -> occString occ ++ "_" ++ show u
          Name occ (NameL u)      -> occString occ ++ "_" ++ show u

        pnam = classify nms

        -- True if we are function style, e.g. f, [], (,)
        -- False if we are operator style, e.g. +, :+
        classify "" = False -- shouldn't happen; . operator is handled below
        classify (x:xs) | isAlpha x || (x `elem` "_[]()") =
                            case dropWhile (/='.') xs of
                                  (_:xs') -> classify xs'
                                  []      -> True
                        | otherwise = False

instance Show Name where
  show = showName

-- Tuple data and type constructors
-- | Tuple data constructor
tupleDataName :: Int -> Name
-- | Tuple type constructor
tupleTypeName :: Int -> Name

tupleDataName n = mk_tup_name n DataName  True
tupleTypeName n = mk_tup_name n TcClsName True

-- Unboxed tuple data and type constructors
-- | Unboxed tuple data constructor
unboxedTupleDataName :: Int -> Name
-- | Unboxed tuple type constructor
unboxedTupleTypeName :: Int -> Name

unboxedTupleDataName n = mk_tup_name n DataName  False
unboxedTupleTypeName n = mk_tup_name n TcClsName False

mk_tup_name :: Int -> NameSpace -> Bool -> Name
mk_tup_name n space boxed
  = Name (mkOccName tup_occ) (NameG space (mkPkgName "ghc-prim") tup_mod)
  where
    withParens thing
      | boxed     = "("  ++ thing ++ ")"
      | otherwise = "(#" ++ thing ++ "#)"
    tup_occ | n == 1    = if boxed then solo else "Solo#"
            | otherwise = withParens (replicate n_commas ',')
    n_commas = n - 1
    tup_mod  = mkModName "GHC.Tuple.Prim"
    solo
      | space == DataName = "MkSolo"
      | otherwise = "Solo"

-- Unboxed sum data and type constructors
-- | Unboxed sum data constructor
unboxedSumDataName :: SumAlt -> SumArity -> Name
-- | Unboxed sum type constructor
unboxedSumTypeName :: SumArity -> Name

unboxedSumDataName alt arity
  | alt > arity
  = error $ prefix ++ "Index out of bounds." ++ debug_info

  | alt <= 0
  = error $ prefix ++ "Alt must be > 0." ++ debug_info

  | arity < 2
  = error $ prefix ++ "Arity must be >= 2." ++ debug_info

  | otherwise
  = Name (mkOccName sum_occ)
         (NameG DataName (mkPkgName "ghc-prim") (mkModName "GHC.Prim"))

  where
    prefix     = "unboxedSumDataName: "
    debug_info = " (alt: " ++ show alt ++ ", arity: " ++ show arity ++ ")"

    -- Synced with the definition of mkSumDataConOcc in GHC.Builtin.Types
    sum_occ = '(' : '#' : bars nbars_before ++ '_' : bars nbars_after ++ "#)"
    bars i = replicate i '|'
    nbars_before = alt - 1
    nbars_after  = arity - alt

unboxedSumTypeName arity
  | arity < 2
  = error $ "unboxedSumTypeName: Arity must be >= 2."
         ++ " (arity: " ++ show arity ++ ")"

  | otherwise
  = Name (mkOccName sum_occ)
         (NameG TcClsName (mkPkgName "ghc-prim") (mkModName "GHC.Prim"))

  where
    -- Synced with the definition of mkSumTyConOcc in GHC.Builtin.Types
    sum_occ = '(' : '#' : replicate (arity - 1) '|' ++ "#)"

-----------------------------------------------------
--              Locations
-----------------------------------------------------

data Loc
  = Loc { loc_filename :: String
        , loc_package  :: String
        , loc_module   :: String
        , loc_start    :: CharPos
        , loc_end      :: CharPos }
   deriving( Show, Eq, Ord, Data, Generic )

type CharPos = (Int, Int)       -- ^ Line and character position


-----------------------------------------------------
--
--      The Info returned by reification
--
-----------------------------------------------------

-- | Obtained from 'reify' in the 'Q' Monad.
data Info
  =
  -- | A class, with a list of its visible instances
  ClassI
      Dec
      [InstanceDec]

  -- | A class method
  | ClassOpI
       Name
       Type
       ParentName

  -- | A \"plain\" type constructor. \"Fancier\" type constructors are returned
  -- using 'PrimTyConI' or 'FamilyI' as appropriate. At present, this reified
  -- declaration will never have derived instances attached to it (if you wish
  -- to check for an instance, see 'reifyInstances').
  | TyConI
        Dec

  -- | A type or data family, with a list of its visible instances. A closed
  -- type family is returned with 0 instances.
  | FamilyI
        Dec
        [InstanceDec]

  -- | A \"primitive\" type constructor, which can't be expressed with a 'Dec'.
  -- Examples: @(->)@, @Int#@.
  | PrimTyConI
       Name
       Arity
       Unlifted

  -- | A data constructor
  | DataConI
       Name
       Type
       ParentName

  -- | A pattern synonym
  | PatSynI
       Name
       PatSynType

  {- |
  A \"value\" variable (as opposed to a type variable, see 'TyVarI').

  The @Maybe Dec@ field contains @Just@ the declaration which
  defined the variable - including the RHS of the declaration -
  or else @Nothing@, in the case where the RHS is unavailable to
  the compiler. At present, this value is /always/ @Nothing@:
  returning the RHS has not yet been implemented because of
  lack of interest.
  -}
  | VarI
       Name
       Type
       (Maybe Dec)

  {- |
  A type variable.

  The @Type@ field contains the type which underlies the variable.
  At present, this is always @'VarT' theName@, but future changes
  may permit refinement of this.
  -}
  | TyVarI      -- Scoped type variable
        Name
        Type    -- What it is bound to
  deriving( Show, Eq, Ord, Data, Generic )

-- | Obtained from 'reifyModule' in the 'Q' Monad.
data ModuleInfo =
  -- | Contains the import list of the module.
  ModuleInfo [Module]
  deriving( Show, Eq, Ord, Data, Generic )

{- |
In 'ClassOpI' and 'DataConI', name of the parent class or type
-}
type ParentName = Name

-- | In 'UnboxedSumE' and 'UnboxedSumP', the number associated with a
-- particular data constructor. 'SumAlt's are one-indexed and should never
-- exceed the value of its corresponding 'SumArity'. For example:
--
-- * @(\#_|\#)@ has 'SumAlt' 1 (out of a total 'SumArity' of 2)
--
-- * @(\#|_\#)@ has 'SumAlt' 2 (out of a total 'SumArity' of 2)
type SumAlt = Int

-- | In 'UnboxedSumE', 'UnboxedSumT', and 'UnboxedSumP', the total number of
-- 'SumAlt's. For example, @(\#|\#)@ has a 'SumArity' of 2.
type SumArity = Int

-- | In 'PrimTyConI', arity of the type constructor
type Arity = Int

-- | In 'PrimTyConI', is the type constructor unlifted?
type Unlifted = Bool

-- | 'InstanceDec' describes a single instance of a class or type function.
-- It is just a 'Dec', but guaranteed to be one of the following:
--
--   * 'InstanceD' (with empty @['Dec']@)
--
--   * 'DataInstD' or 'NewtypeInstD' (with empty derived @['Name']@)
--
--   * 'TySynInstD'
type InstanceDec = Dec

data Fixity          = Fixity Int FixityDirection
    deriving( Eq, Ord, Show, Data, Generic )
data FixityDirection = InfixL | InfixR | InfixN
    deriving( Eq, Ord, Show, Data, Generic )

-- | Highest allowed operator precedence for 'Fixity' constructor (answer: 9)
maxPrecedence :: Int
maxPrecedence = (9::Int)

-- | Default fixity: @infixl 9@
defaultFixity :: Fixity
defaultFixity = Fixity maxPrecedence InfixL


{-
Note [Unresolved infix]
~~~~~~~~~~~~~~~~~~~~~~~
-}
{- $infix #infix#

When implementing antiquotation for quasiquoters, one often wants
to parse strings into expressions:

> parse :: String -> Maybe Exp

But how should we parse @a + b * c@? If we don't know the fixities of
@+@ and @*@, we don't know whether to parse it as @a + (b * c)@ or @(a
+ b) * c@.

In cases like this, use 'UInfixE', 'UInfixP', 'UInfixT', or 'PromotedUInfixT',
which stand for \"unresolved infix expression/pattern/type/promoted
constructor\", respectively. When the compiler is given a splice containing a
tree of @UInfixE@ applications such as

> UInfixE
>   (UInfixE e1 op1 e2)
>   op2
>   (UInfixE e3 op3 e4)

it will look up and the fixities of the relevant operators and
reassociate the tree as necessary.

  * trees will not be reassociated across 'ParensE', 'ParensP', or 'ParensT',
    which are of use for parsing expressions like

    > (a + b * c) + d * e

  * 'InfixE', 'InfixP', 'InfixT', and 'PromotedInfixT' expressions are never
    reassociated.

  * The 'UInfixE' constructor doesn't support sections. Sections
    such as @(a *)@ have no ambiguity, so 'InfixE' suffices. For longer
    sections such as @(a + b * c -)@, use an 'InfixE' constructor for the
    outer-most section, and use 'UInfixE' constructors for all
    other operators:

    > InfixE
    >   Just (UInfixE ...a + b * c...)
    >   op
    >   Nothing

    Sections such as @(a + b +)@ and @((a + b) +)@ should be rendered
    into 'Exp's differently:

    > (+ a + b)   ---> InfixE Nothing + (Just $ UInfixE a + b)
    >                    -- will result in a fixity error if (+) is left-infix
    > (+ (a + b)) ---> InfixE Nothing + (Just $ ParensE $ UInfixE a + b)
    >                    -- no fixity errors

  * Quoted expressions such as

    > [| a * b + c |] :: Q Exp
    > [p| a : b : c |] :: Q Pat
    > [t| T + T |] :: Q Type

    will never contain 'UInfixE', 'UInfixP', 'UInfixT', 'PromotedUInfixT',
    'InfixT', 'PromotedInfixT, 'ParensE', 'ParensP', or 'ParensT' constructors.

-}

-----------------------------------------------------
--
--      The main syntax data types
--
-----------------------------------------------------

data Lit = CharL Char
         | StringL String
         | IntegerL Integer     -- ^ Used for overloaded and non-overloaded
                                -- literals. We don't have a good way to
                                -- represent non-overloaded literals at
                                -- the moment. Maybe that doesn't matter?
         | RationalL Rational   -- Ditto
         | IntPrimL Integer
         | WordPrimL Integer
         | FloatPrimL Rational
         | DoublePrimL Rational
         | StringPrimL [Word8]  -- ^ A primitive C-style string, type 'Addr#'
         | BytesPrimL Bytes     -- ^ Some raw bytes, type 'Addr#':
         | CharPrimL Char
    deriving( Show, Eq, Ord, Data, Generic )

    -- We could add Int, Float, Double etc, as we do in HsLit,
    -- but that could complicate the
    -- supposedly-simple TH.Syntax literal type

-- | Raw bytes embedded into the binary.
--
-- Avoid using Bytes constructor directly as it is likely to change in the
-- future. Use helpers such as `mkBytes` in Language.Haskell.TH.Lib instead.
data Bytes = Bytes
   { bytesPtr    :: ForeignPtr Word8 -- ^ Pointer to the data
   , bytesOffset :: Word             -- ^ Offset from the pointer
   , bytesSize   :: Word             -- ^ Number of bytes

   -- Maybe someday:
   -- , bytesAlignement  :: Word -- ^ Alignement constraint
   -- , bytesReadOnly    :: Bool -- ^ Shall we embed into a read-only
   --                            --   section or not
   -- , bytesInitialized :: Bool -- ^ False: only use `bytesSize` to allocate
   --                            --   an uninitialized region
   }
   deriving (Data,Generic)

-- We can't derive Show instance for Bytes because we don't want to show the
-- pointer value but the actual bytes (similarly to what ByteString does). See
-- #16457.
instance Show Bytes where
   show b = unsafePerformIO $ withForeignPtr (bytesPtr b) $ \ptr ->
               peekCStringLen ( ptr `plusPtr` fromIntegral (bytesOffset b)
                              , fromIntegral (bytesSize b)
                              )

-- We can't derive Eq and Ord instances for Bytes because we don't want to
-- compare pointer values but the actual bytes (similarly to what ByteString
-- does).  See #16457
instance Eq Bytes where
   (==) = eqBytes

instance Ord Bytes where
   compare = compareBytes

eqBytes :: Bytes -> Bytes -> Bool
eqBytes a@(Bytes fp off len) b@(Bytes fp' off' len')
  | len /= len'              = False    -- short cut on length
  | fp == fp' && off == off' = True     -- short cut for the same bytes
  | otherwise                = compareBytes a b == EQ

compareBytes :: Bytes -> Bytes -> Ordering
compareBytes (Bytes _   _    0)    (Bytes _   _    0)    = EQ  -- short cut for empty Bytes
compareBytes (Bytes fp1 off1 len1) (Bytes fp2 off2 len2) =
    unsafePerformIO $
      withForeignPtr fp1 $ \p1 ->
      withForeignPtr fp2 $ \p2 -> do
        i <- memcmp (p1 `plusPtr` fromIntegral off1)
                    (p2 `plusPtr` fromIntegral off2)
                    (fromIntegral (min len1 len2))
        return $! (i `compare` 0) <> (len1 `compare` len2)

foreign import ccall unsafe "memcmp"
  memcmp :: Ptr a -> Ptr b -> CSize -> IO CInt


-- | Pattern in Haskell given in @{}@
data Pat
  = LitP Lit                        -- ^ @{ 5 or \'c\' }@
  | VarP Name                       -- ^ @{ x }@
  | TupP [Pat]                      -- ^ @{ (p1,p2) }@
  | UnboxedTupP [Pat]               -- ^ @{ (\# p1,p2 \#) }@
  | UnboxedSumP Pat SumAlt SumArity -- ^ @{ (\#|p|\#) }@
  | ConP Name [Type] [Pat]          -- ^ @data T1 = C1 t1 t2; {C1 \@ty1 p1 p2} = e@
  | InfixP Pat Name Pat             -- ^ @foo ({x :+ y}) = e@
  | UInfixP Pat Name Pat            -- ^ @foo ({x :+ y}) = e@
                                    --
                                    -- See "Language.Haskell.TH.Syntax#infix"
  | ParensP Pat                     -- ^ @{(p)}@
                                    --
                                    -- See "Language.Haskell.TH.Syntax#infix"
  | TildeP Pat                      -- ^ @{ ~p }@
  | BangP Pat                       -- ^ @{ !p }@
  | AsP Name Pat                    -- ^ @{ x \@ p }@
  | WildP                           -- ^ @{ _ }@
  | RecP Name [FieldPat]            -- ^ @f (Pt { pointx = x }) = g x@
  | ListP [ Pat ]                   -- ^ @{ [1,2,3] }@
  | SigP Pat Type                   -- ^ @{ p :: t }@
  | ViewP Exp Pat                   -- ^ @{ e -> p }@
  deriving( Show, Eq, Ord, Data, Generic )

type FieldPat = (Name,Pat)

data Match = Match Pat Body [Dec] -- ^ @case e of { pat -> body where decs }@
    deriving( Show, Eq, Ord, Data, Generic )

data Clause = Clause [Pat] Body [Dec]
                                  -- ^ @f { p1 p2 = body where decs }@
    deriving( Show, Eq, Ord, Data, Generic )

data Exp
  = VarE Name                          -- ^ @{ x }@
  | ConE Name                          -- ^ @data T1 = C1 t1 t2; p = {C1} e1 e2  @
  | LitE Lit                           -- ^ @{ 5 or \'c\'}@
  | AppE Exp Exp                       -- ^ @{ f x }@
  | AppTypeE Exp Type                  -- ^ @{ f \@Int }@

  | InfixE (Maybe Exp) Exp (Maybe Exp) -- ^ @{x + y} or {(x+)} or {(+ x)} or {(+)}@

    -- It's a bit gruesome to use an Exp as the operator when a Name
    -- would suffice. Historically, Exp was used to make it easier to
    -- distinguish between infix constructors and non-constructors.
    -- This is a bit overkill, since one could just as well call
    -- `startsConId` or `startsConSym` (from `GHC.Lexeme`) on a Name.
    -- Unfortunately, changing this design now would involve lots of
    -- code churn for consumers of the TH API, so we continue to use
    -- an Exp as the operator and perform an extra check during conversion
    -- to ensure that the Exp is a constructor or a variable (#16895).

  | UInfixE Exp Exp Exp                -- ^ @{x + y}@
                                       --
                                       -- See "Language.Haskell.TH.Syntax#infix"
  | ParensE Exp                        -- ^ @{ (e) }@
                                       --
                                       -- See "Language.Haskell.TH.Syntax#infix"
  | LamE [Pat] Exp                     -- ^ @{ \\ p1 p2 -> e }@
  | LamCaseE [Match]                   -- ^ @{ \\case m1; m2 }@
  | LamCasesE [Clause]                 -- ^ @{ \\cases m1; m2 }@
  | TupE [Maybe Exp]                   -- ^ @{ (e1,e2) }  @
                                       --
                                       -- The 'Maybe' is necessary for handling
                                       -- tuple sections.
                                       --
                                       -- > (1,)
                                       --
                                       -- translates to
                                       --
                                       -- > TupE [Just (LitE (IntegerL 1)),Nothing]

  | UnboxedTupE [Maybe Exp]            -- ^ @{ (\# e1,e2 \#) }  @
                                       --
                                       -- The 'Maybe' is necessary for handling
                                       -- tuple sections.
                                       --
                                       -- > (# 'c', #)
                                       --
                                       -- translates to
                                       --
                                       -- > UnboxedTupE [Just (LitE (CharL 'c')),Nothing]

  | UnboxedSumE Exp SumAlt SumArity    -- ^ @{ (\#|e|\#) }@
  | CondE Exp Exp Exp                  -- ^ @{ if e1 then e2 else e3 }@
  | MultiIfE [(Guard, Exp)]            -- ^ @{ if | g1 -> e1 | g2 -> e2 }@
  | LetE [Dec] Exp                     -- ^ @{ let { x=e1; y=e2 } in e3 }@
  | CaseE Exp [Match]                  -- ^ @{ case e of m1; m2 }@
  | DoE (Maybe ModName) [Stmt]         -- ^ @{ do { p <- e1; e2 }  }@ or a qualified do if
                                       -- the module name is present
  | MDoE (Maybe ModName) [Stmt]        -- ^ @{ mdo { x <- e1 y; y <- e2 x; } }@ or a qualified
                                       -- mdo if the module name is present
  | CompE [Stmt]                       -- ^ @{ [ (x,y) | x <- xs, y <- ys ] }@
      --
      -- The result expression of the comprehension is
      -- the /last/ of the @'Stmt'@s, and should be a 'NoBindS'.
      --
      -- E.g. translation:
      --
      -- > [ f x | x <- xs ]
      --
      -- > CompE [BindS (VarP x) (VarE xs), NoBindS (AppE (VarE f) (VarE x))]

  | ArithSeqE Range                    -- ^ @{ [ 1 ,2 .. 10 ] }@
  | ListE [ Exp ]                      -- ^ @{ [1,2,3] }@
  | SigE Exp Type                      -- ^ @{ e :: t }@
  | RecConE Name [FieldExp]            -- ^ @{ T { x = y, z = w } }@
  | RecUpdE Exp [FieldExp]             -- ^ @{ (f x) { z = w } }@
  | StaticE Exp                        -- ^ @{ static e }@
  | UnboundVarE Name                   -- ^ @{ _x }@
                                       --
                                       -- This is used for holes or unresolved
                                       -- identifiers in AST quotes. Note that
                                       -- it could either have a variable name
                                       -- or constructor name.
  | LabelE String                      -- ^ @{ #x }@ ( Overloaded label )
  | ImplicitParamVarE String           -- ^ @{ ?x }@ ( Implicit parameter )
  | GetFieldE Exp String               -- ^ @{ exp.field }@ ( Overloaded Record Dot )
  | ProjectionE (NonEmpty String)      -- ^ @(.x)@ or @(.x.y)@ (Record projections)
  | TypedBracketE Exp                  -- ^ @[|| e ||]@
  | TypedSpliceE Exp                   -- ^ @$$e@
  deriving( Show, Eq, Ord, Data, Generic )

type FieldExp = (Name,Exp)

-- Omitted: implicit parameters

data Body
  = GuardedB [(Guard,Exp)]   -- ^ @f p { | e1 = e2
                                 --      | e3 = e4 }
                                 -- where ds@
  | NormalB Exp              -- ^ @f p { = e } where ds@
  deriving( Show, Eq, Ord, Data, Generic )

data Guard
  = NormalG Exp -- ^ @f x { | odd x } = x@
  | PatG [Stmt] -- ^ @f x { | Just y <- x, Just z <- y } = z@
  deriving( Show, Eq, Ord, Data, Generic )

data Stmt
  = BindS Pat Exp -- ^ @p <- e@
  | LetS [ Dec ]  -- ^ @{ let { x=e1; y=e2 } }@
  | NoBindS Exp   -- ^ @e@
  | ParS [[Stmt]] -- ^ @x <- e1 | s2, s3 | s4@ (in 'CompE')
  | RecS [Stmt]   -- ^ @rec { s1; s2 }@
  deriving( Show, Eq, Ord, Data, Generic )

data Range = FromR Exp | FromThenR Exp Exp
           | FromToR Exp Exp | FromThenToR Exp Exp Exp
          deriving( Show, Eq, Ord, Data, Generic )

data Dec
  = FunD Name [Clause]            -- ^ @{ f p1 p2 = b where decs }@
  | ValD Pat Body [Dec]           -- ^ @{ p = b where decs }@
  | DataD Cxt Name [TyVarBndr BndrVis]
          (Maybe Kind)            -- Kind signature (allowed only for GADTs)
          [Con] [DerivClause]
                                  -- ^ @{ data Cxt x => T x = A x | B (T x)
                                  --       deriving (Z,W)
                                  --       deriving stock Eq }@
  | NewtypeD Cxt Name [TyVarBndr BndrVis]
             (Maybe Kind)         -- Kind signature
             Con [DerivClause]    -- ^ @{ newtype Cxt x => T x = A (B x)
                                  --       deriving (Z,W Q)
                                  --       deriving stock Eq }@
  | TypeDataD Name [TyVarBndr BndrVis]
          (Maybe Kind)            -- Kind signature (allowed only for GADTs)
          [Con]                   -- ^ @{ type data T x = A x | B (T x) }@
  | TySynD Name [TyVarBndr BndrVis] Type -- ^ @{ type T x = (x,x) }@
  | ClassD Cxt Name [TyVarBndr BndrVis]
         [FunDep] [Dec]           -- ^ @{ class Eq a => Ord a where ds }@
  | InstanceD (Maybe Overlap) Cxt Type [Dec]
                                  -- ^ @{ instance {\-\# OVERLAPS \#-\}
                                  --        Show w => Show [w] where ds }@
  | SigD Name Type                -- ^ @{ length :: [a] -> Int }@
  | KiSigD Name Kind              -- ^ @{ type TypeRep :: k -> Type }@
  | ForeignD Foreign              -- ^ @{ foreign import ... }
                                  --{ foreign export ... }@

  | InfixD Fixity Name            -- ^ @{ infix 3 foo }@
  | DefaultD [Type]               -- ^ @{ default (Integer, Double) }@

  -- | pragmas
  | PragmaD Pragma                -- ^ @{ {\-\# INLINE [1] foo \#-\} }@

  -- | data families (may also appear in [Dec] of 'ClassD' and 'InstanceD')
  | DataFamilyD Name [TyVarBndr BndrVis]
               (Maybe Kind)
         -- ^ @{ data family T a b c :: * }@

  | DataInstD Cxt (Maybe [TyVarBndr ()]) Type
             (Maybe Kind)         -- Kind signature
             [Con] [DerivClause]  -- ^ @{ data instance Cxt x => T [x]
                                  --       = A x | B (T x)
                                  --       deriving (Z,W)
                                  --       deriving stock Eq }@

  | NewtypeInstD Cxt (Maybe [TyVarBndr ()]) Type -- Quantified type vars
                 (Maybe Kind)      -- Kind signature
                 Con [DerivClause] -- ^ @{ newtype instance Cxt x => T [x]
                                   --        = A (B x)
                                   --        deriving (Z,W)
                                   --        deriving stock Eq }@
  | TySynInstD TySynEqn            -- ^ @{ type instance ... }@

  -- | open type families (may also appear in [Dec] of 'ClassD' and 'InstanceD')
  | OpenTypeFamilyD TypeFamilyHead
         -- ^ @{ type family T a b c = (r :: *) | r -> a b }@

  | ClosedTypeFamilyD TypeFamilyHead [TySynEqn]
       -- ^ @{ type family F a b = (r :: *) | r -> a where ... }@

  | RoleAnnotD Name [Role]     -- ^ @{ type role T nominal representational }@
  | StandaloneDerivD (Maybe DerivStrategy) Cxt Type
       -- ^ @{ deriving stock instance Ord a => Ord (Foo a) }@
  | DefaultSigD Name Type      -- ^ @{ default size :: Data a => a -> Int }@

  -- | Pattern Synonyms
  | PatSynD Name PatSynArgs PatSynDir Pat
      -- ^ @{ pattern P v1 v2 .. vn <- p }@  unidirectional           or
      --   @{ pattern P v1 v2 .. vn = p  }@  implicit bidirectional   or
      --   @{ pattern P v1 v2 .. vn <- p
      --        where P v1 v2 .. vn = e  }@  explicit bidirectional
      --
      -- also, besides prefix pattern synonyms, both infix and record
      -- pattern synonyms are supported. See 'PatSynArgs' for details

  | PatSynSigD Name PatSynType  -- ^ A pattern synonym's type signature.

  | ImplicitParamBindD String Exp
      -- ^ @{ ?x = expr }@
      --
      -- Implicit parameter binding declaration. Can only be used in let
      -- and where clauses which consist entirely of implicit bindings.
  deriving( Show, Eq, Ord, Data, Generic )

-- | Varieties of allowed instance overlap.
data Overlap = Overlappable   -- ^ May be overlapped by more specific instances
             | Overlapping    -- ^ May overlap a more general instance
             | Overlaps       -- ^ Both 'Overlapping' and 'Overlappable'
             | Incoherent     -- ^ Both 'Overlapping' and 'Overlappable', and
                              -- pick an arbitrary one if multiple choices are
                              -- available.
  deriving( Show, Eq, Ord, Data, Generic )

-- | A single @deriving@ clause at the end of a datatype.
data DerivClause = DerivClause (Maybe DerivStrategy) Cxt
    -- ^ @{ deriving stock (Eq, Ord) }@
  deriving( Show, Eq, Ord, Data, Generic )

-- | What the user explicitly requests when deriving an instance.
data DerivStrategy = StockStrategy    -- ^ A \"standard\" derived instance
                   | AnyclassStrategy -- ^ @-XDeriveAnyClass@
                   | NewtypeStrategy  -- ^ @-XGeneralizedNewtypeDeriving@
                   | ViaStrategy Type -- ^ @-XDerivingVia@
  deriving( Show, Eq, Ord, Data, Generic )

-- | A pattern synonym's type. Note that a pattern synonym's /fully/
-- specified type has a peculiar shape coming with two forall
-- quantifiers and two constraint contexts. For example, consider the
-- pattern synonym
--
-- > pattern P x1 x2 ... xn = <some-pattern>
--
-- P's complete type is of the following form
--
-- > pattern P :: forall universals.   required constraints
-- >           => forall existentials. provided constraints
-- >           => t1 -> t2 -> ... -> tn -> t
--
-- consisting of four parts:
--
--   1. the (possibly empty lists of) universally quantified type
--      variables and required constraints on them.
--   2. the (possibly empty lists of) existentially quantified
--      type variables and the provided constraints on them.
--   3. the types @t1@, @t2@, .., @tn@ of @x1@, @x2@, .., @xn@, respectively
--   4. the type @t@ of @\<some-pattern\>@, mentioning only universals.
--
-- Pattern synonym types interact with TH when (a) reifying a pattern
-- synonym, (b) pretty printing, or (c) specifying a pattern synonym's
-- type signature explicitly:
--
--   * Reification always returns a pattern synonym's /fully/ specified
--     type in abstract syntax.
--
--   * Pretty printing via 'Language.Haskell.TH.Ppr.pprPatSynType' abbreviates
--     a pattern synonym's type unambiguously in concrete syntax: The rule of
--     thumb is to print initial empty universals and the required
--     context as @() =>@, if existentials and a provided context
--     follow. If only universals and their required context, but no
--     existentials are specified, only the universals and their
--     required context are printed. If both or none are specified, so
--     both (or none) are printed.
--
--   * When specifying a pattern synonym's type explicitly with
--     'PatSynSigD' either one of the universals, the existentials, or
--     their contexts may be left empty.
--
-- See the GHC user's guide for more information on pattern synonyms
-- and their types:
-- <https://downloads.haskell.org/~ghc/latest/docs/html/users_guide/glasgow_exts.html#pattern-synonyms>.
type PatSynType = Type

-- | Common elements of 'OpenTypeFamilyD' and 'ClosedTypeFamilyD'. By
-- analogy with "head" for type classes and type class instances as
-- defined in /Type classes: an exploration of the design space/, the
-- @TypeFamilyHead@ is defined to be the elements of the declaration
-- between @type family@ and @where@.
data TypeFamilyHead =
  TypeFamilyHead Name [TyVarBndr BndrVis] FamilyResultSig (Maybe InjectivityAnn)
  deriving( Show, Eq, Ord, Data, Generic )

-- | One equation of a type family instance or closed type family. The
-- arguments are the left-hand-side type and the right-hand-side result.
--
-- For instance, if you had the following type family:
--
-- @
-- type family Foo (a :: k) :: k where
--   forall k (a :: k). Foo \@k a = a
-- @
--
-- The @Foo \@k a = a@ equation would be represented as follows:
--
-- @
-- 'TySynEqn' ('Just' ['PlainTV' k, 'KindedTV' a ('VarT' k)])
--            ('AppT' ('AppKindT' ('ConT' ''Foo) ('VarT' k)) ('VarT' a))
--            ('VarT' a)
-- @
data TySynEqn = TySynEqn (Maybe [TyVarBndr ()]) Type Type
  deriving( Show, Eq, Ord, Data, Generic )

data FunDep = FunDep [Name] [Name]
  deriving( Show, Eq, Ord, Data, Generic )

data Foreign = ImportF Callconv Safety String Name Type
             | ExportF Callconv        String Name Type
         deriving( Show, Eq, Ord, Data, Generic )

-- keep Callconv in sync with module ForeignCall in ghc/compiler/GHC/Types/ForeignCall.hs
data Callconv = CCall | StdCall | CApi | Prim | JavaScript
          deriving( Show, Eq, Ord, Data, Generic )

data Safety = Unsafe | Safe | Interruptible
        deriving( Show, Eq, Ord, Data, Generic )

data Pragma = InlineP         Name Inline RuleMatch Phases
            | OpaqueP         Name
            | SpecialiseP     Name Type (Maybe Inline) Phases
            | SpecialiseInstP Type
            | RuleP           String (Maybe [TyVarBndr ()]) [RuleBndr] Exp Exp Phases
            | AnnP            AnnTarget Exp
            | LineP           Int String
            | CompleteP       [Name] (Maybe Name)
                -- ^ @{ {\-\# COMPLETE C_1, ..., C_i [ :: T ] \#-} }@
        deriving( Show, Eq, Ord, Data, Generic )

data Inline = NoInline
            | Inline
            | Inlinable
            deriving (Show, Eq, Ord, Data, Generic)

data RuleMatch = ConLike
               | FunLike
               deriving (Show, Eq, Ord, Data, Generic)

data Phases = AllPhases
            | FromPhase Int
            | BeforePhase Int
            deriving (Show, Eq, Ord, Data, Generic)

data RuleBndr = RuleVar Name
              | TypedRuleVar Name Type
              deriving (Show, Eq, Ord, Data, Generic)

data AnnTarget = ModuleAnnotation
               | TypeAnnotation Name
               | ValueAnnotation Name
              deriving (Show, Eq, Ord, Data, Generic)

type Cxt = [Pred]                 -- ^ @(Eq a, Ord b)@

-- | Since the advent of @ConstraintKinds@, constraints are really just types.
-- Equality constraints use the 'EqualityT' constructor. Constraints may also
-- be tuples of other constraints.
type Pred = Type

-- | 'SourceUnpackedness' corresponds to unpack annotations found in the source code.
--
-- This may not agree with the annotations returned by 'reifyConStrictness'.
-- See 'reifyConStrictness' for more information.
data SourceUnpackedness
  = NoSourceUnpackedness -- ^ @C a@
  | SourceNoUnpack       -- ^ @C { {\-\# NOUNPACK \#-\} } a@
  | SourceUnpack         -- ^ @C { {\-\# UNPACK \#-\} } a@
        deriving (Show, Eq, Ord, Data, Generic)

-- | 'SourceStrictness' corresponds to strictness annotations found in the source code.
--
-- This may not agree with the annotations returned by 'reifyConStrictness'.
-- See 'reifyConStrictness' for more information.
data SourceStrictness = NoSourceStrictness    -- ^ @C a@
                      | SourceLazy            -- ^ @C {~}a@
                      | SourceStrict          -- ^ @C {!}a@
        deriving (Show, Eq, Ord, Data, Generic)

-- | Unlike 'SourceStrictness' and 'SourceUnpackedness', 'DecidedStrictness'
-- refers to the strictness annotations that the compiler chooses for a data constructor
-- field, which may be different from what is written in source code.
--
-- Note that non-unpacked strict fields are assigned 'DecidedLazy' when a bang would be inappropriate,
-- such as the field of a newtype constructor and fields that have an unlifted type.
--
-- See 'reifyConStrictness' for more information.
data DecidedStrictness = DecidedLazy -- ^ Field inferred to not have a bang.
                       | DecidedStrict -- ^ Field inferred to have a bang.
                       | DecidedUnpack -- ^ Field inferred to be unpacked.
        deriving (Show, Eq, Ord, Data, Generic)

-- | A data constructor.
--
-- The constructors for 'Con' can roughly be divided up into two categories:
-- those for constructors with \"vanilla\" syntax ('NormalC', 'RecC', and
-- 'InfixC'), and those for constructors with GADT syntax ('GadtC' and
-- 'RecGadtC'). The 'ForallC' constructor, which quantifies additional type
-- variables and class contexts, can surround either variety of constructor.
-- However, the type variables that it quantifies are different depending
-- on what constructor syntax is used:
--
-- * If a 'ForallC' surrounds a constructor with vanilla syntax, then the
--   'ForallC' will only quantify /existential/ type variables. For example:
--
--   @
--   data Foo a = forall b. MkFoo a b
--   @
--
--   In @MkFoo@, 'ForallC' will quantify @b@, but not @a@.
--
-- * If a 'ForallC' surrounds a constructor with GADT syntax, then the
--   'ForallC' will quantify /all/ type variables used in the constructor.
--   For example:
--
--   @
--   data Bar a b where
--     MkBar :: (a ~ b) => c -> MkBar a b
--   @
--
--   In @MkBar@, 'ForallC' will quantify @a@, @b@, and @c@.
--
-- Multiplicity annotations for data types are currently not supported
-- in Template Haskell (i.e. all fields represented by Template Haskell
-- will be linear).
data Con =
  -- | @C Int a@
    NormalC Name [BangType]

  -- | @C { v :: Int, w :: a }@
  | RecC Name [VarBangType]

  -- | @Int :+ a@
  | InfixC BangType Name BangType

  -- | @forall a. Eq a => C [a]@
  | ForallC [TyVarBndr Specificity] Cxt Con

  -- @C :: a -> b -> T b Int@
  | GadtC [Name]
            -- ^ The list of constructors, corresponding to the GADT constructor
            -- syntax @C1, C2 :: a -> T b@.
            --
            -- Invariant: the list must be non-empty.
          [BangType] -- ^ The constructor arguments
          Type -- ^ See Note [GADT return type]

  -- | @C :: { v :: Int } -> T b Int@
  | RecGadtC [Name]
             -- ^ The list of constructors, corresponding to the GADT record
             -- constructor syntax @C1, C2 :: { fld :: a } -> T b@.
             --
             -- Invariant: the list must be non-empty.
             [VarBangType] -- ^ The constructor arguments
             Type -- ^ See Note [GADT return type]
        deriving (Show, Eq, Ord, Data, Generic)

-- Note [GADT return type]
-- ~~~~~~~~~~~~~~~~~~~~~~~
-- The return type of a GADT constructor does not necessarily match the name of
-- the data type:
--
-- type S = T
--
-- data T a where
--     MkT :: S Int
--
--
-- type S a = T
--
-- data T a where
--     MkT :: S Char Int
--
--
-- type Id a = a
-- type S a = T
--
-- data T a where
--     MkT :: Id (S Char Int)
--
--
-- That is why we allow the return type stored by a constructor to be an
-- arbitrary type. See also #11341

data Bang = Bang SourceUnpackedness SourceStrictness
         -- ^ @C { {\-\# UNPACK \#-\} !}a@
        deriving (Show, Eq, Ord, Data, Generic)

type BangType    = (Bang, Type)
type VarBangType = (Name, Bang, Type)

-- | As of @template-haskell-2.11.0.0@, 'Strict' has been replaced by 'Bang'.
type Strict      = Bang

-- | As of @template-haskell-2.11.0.0@, 'StrictType' has been replaced by
-- 'BangType'.
type StrictType    = BangType

-- | As of @template-haskell-2.11.0.0@, 'VarStrictType' has been replaced by
-- 'VarBangType'.
type VarStrictType = VarBangType

-- | A pattern synonym's directionality.
data PatSynDir
  = Unidir             -- ^ @pattern P x {<-} p@
  | ImplBidir          -- ^ @pattern P x {=} p@
  | ExplBidir [Clause] -- ^ @pattern P x {<-} p where P x = e@
  deriving( Show, Eq, Ord, Data, Generic )

-- | A pattern synonym's argument type.
data PatSynArgs
  = PrefixPatSyn [Name]        -- ^ @pattern P {x y z} = p@
  | InfixPatSyn Name Name      -- ^ @pattern {x P y} = p@
  | RecordPatSyn [Name]        -- ^ @pattern P { {x,y,z} } = p@
  deriving( Show, Eq, Ord, Data, Generic )

data Type = ForallT [TyVarBndr Specificity] Cxt Type -- ^ @forall \<vars\>. \<ctxt\> => \<type\>@
          | ForallVisT [TyVarBndr ()] Type -- ^ @forall \<vars\> -> \<type\>@
          | AppT Type Type                 -- ^ @T a b@
          | AppKindT Type Kind             -- ^ @T \@k t@
          | SigT Type Kind                 -- ^ @t :: k@
          | VarT Name                      -- ^ @a@
          | ConT Name                      -- ^ @T@
          | PromotedT Name                 -- ^ @'T@
          | InfixT Type Name Type          -- ^ @T + T@
          | UInfixT Type Name Type         -- ^ @T + T@
                                           --
                                           -- See "Language.Haskell.TH.Syntax#infix"
          | PromotedInfixT Type Name Type  -- ^ @T :+: T@
          | PromotedUInfixT Type Name Type -- ^ @T :+: T@
                                           --
                                           -- See "Language.Haskell.TH.Syntax#infix"
          | ParensT Type                   -- ^ @(T)@

          -- See Note [Representing concrete syntax in types]
          | TupleT Int                     -- ^ @(,)@, @(,,)@, etc.
          | UnboxedTupleT Int              -- ^ @(\#,\#)@, @(\#,,\#)@, etc.
          | UnboxedSumT SumArity           -- ^ @(\#|\#)@, @(\#||\#)@, etc.
          | ArrowT                         -- ^ @->@
          | MulArrowT                      -- ^ @%n ->@
                                           --
                                           -- Generalised arrow type with multiplicity argument
          | EqualityT                      -- ^ @~@
          | ListT                          -- ^ @[]@
          | PromotedTupleT Int             -- ^ @'()@, @'(,)@, @'(,,)@, etc.
          | PromotedNilT                   -- ^ @'[]@
          | PromotedConsT                  -- ^ @'(:)@
          | StarT                          -- ^ @*@
          | ConstraintT                    -- ^ @Constraint@
          | LitT TyLit                     -- ^ @0@, @1@, @2@, etc.
          | WildCardT                      -- ^ @_@
          | ImplicitParamT String Type     -- ^ @?x :: t@
      deriving( Show, Eq, Ord, Data, Generic )

data Specificity = SpecifiedSpec          -- ^ @a@
                 | InferredSpec           -- ^ @{a}@
      deriving( Show, Eq, Ord, Data, Generic )

-- | The @flag@ type parameter is instantiated to one of the following types:
--
--   * 'Specificity' (examples: 'ForallC', 'ForallT')
--   * 'BndrVis' (examples: 'DataD', 'ClassD', etc.)
--   * '()', a catch-all type for other forms of binders, including 'ForallVisT', 'DataInstD', 'RuleP', and 'TyVarSig'
--
data TyVarBndr flag = PlainTV  Name flag      -- ^ @a@
                    | KindedTV Name flag Kind -- ^ @(a :: k)@
      deriving( Show, Eq, Ord, Data, Generic, Functor, Foldable, Traversable )

data BndrVis = BndrReq                    -- ^ @a@
             | BndrInvis                  -- ^ @\@a@
      deriving( Show, Eq, Ord, Data, Generic )

-- | Type family result signature
data FamilyResultSig = NoSig              -- ^ no signature
                     | KindSig  Kind      -- ^ @k@
                     | TyVarSig (TyVarBndr ()) -- ^ @= r, = (r :: k)@
      deriving( Show, Eq, Ord, Data, Generic )

-- | Injectivity annotation
data InjectivityAnn = InjectivityAnn Name [Name]
  deriving ( Show, Eq, Ord, Data, Generic )

data TyLit = NumTyLit Integer             -- ^ @2@
           | StrTyLit String              -- ^ @\"Hello\"@
           | CharTyLit Char               -- ^ @\'C\'@, @since 4.16.0.0
  deriving ( Show, Eq, Ord, Data, Generic )

-- | Role annotations
data Role = NominalR            -- ^ @nominal@
          | RepresentationalR   -- ^ @representational@
          | PhantomR            -- ^ @phantom@
          | InferR              -- ^ @_@
  deriving( Show, Eq, Ord, Data, Generic )

-- | Annotation target for reifyAnnotations
data AnnLookup = AnnLookupModule Module
               | AnnLookupName Name
               deriving( Show, Eq, Ord, Data, Generic )

-- | To avoid duplication between kinds and types, they
-- are defined to be the same. Naturally, you would never
-- have a type be 'StarT' and you would never have a kind
-- be 'SigT', but many of the other constructors are shared.
-- Note that the kind @Bool@ is denoted with 'ConT', not
-- 'PromotedT'. Similarly, tuple kinds are made with 'TupleT',
-- not 'PromotedTupleT'.

type Kind = Type

{- Note [Representing concrete syntax in types]
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
Haskell has a rich concrete syntax for types, including
  t1 -> t2, (t1,t2), [t], and so on
In TH we represent all of this using AppT, with a distinguished
type constructor at the head.  So,
  Type              TH representation
  -----------------------------------------------
  t1 -> t2          ArrowT `AppT` t2 `AppT` t2
  [t]               ListT `AppT` t
  (t1,t2)           TupleT 2 `AppT` t1 `AppT` t2
  '(t1,t2)          PromotedTupleT 2 `AppT` t1 `AppT` t2

But if the original HsSyn used prefix application, we won't use
these special TH constructors.  For example
  [] t              ConT "[]" `AppT` t
  (->) t            ConT "->" `AppT` t
In this way we can faithfully represent in TH whether the original
HsType used concrete syntax or not.

The one case that doesn't fit this pattern is that of promoted lists
  '[ Maybe, IO ]    PromotedListT 2 `AppT` t1 `AppT` t2
but it's very smelly because there really is no type constructor
corresponding to PromotedListT. So we encode HsExplicitListTy with
PromotedConsT and PromotedNilT (which *do* have underlying type
constructors):
  '[ Maybe, IO ]    PromotedConsT `AppT` Maybe `AppT`
                    (PromotedConsT  `AppT` IO `AppT` PromotedNilT)
-}

-- | A location at which to attach Haddock documentation.
-- Note that adding documentation to a 'Name' defined oustide of the current
-- module will cause an error.
data DocLoc
  = ModuleDoc         -- ^ At the current module's header.
  | DeclDoc Name      -- ^ At a declaration, not necessarily top level.
  | ArgDoc Name Int   -- ^ At a specific argument of a function, indexed by its
                      -- position.
  | InstDoc Type      -- ^ At a class or family instance.
  deriving ( Show, Eq, Ord, Data, Generic )

-----------------------------------------------------
--              Internal helper functions
-----------------------------------------------------

cmpEq :: Ordering -> Bool
cmpEq EQ = True
cmpEq _  = False

thenCmp :: Ordering -> Ordering -> Ordering
thenCmp EQ o2 = o2
thenCmp o1 _  = o1

get_cons_names :: Con -> [Name]
get_cons_names (NormalC n _)     = [n]
get_cons_names (RecC n _)        = [n]
get_cons_names (InfixC _ n _)    = [n]
get_cons_names (ForallC _ _ con) = get_cons_names con
-- GadtC can have multiple names, e.g
-- > data Bar a where
-- >   MkBar1, MkBar2 :: a -> Bar a
-- Will have one GadtC with [MkBar1, MkBar2] as names
get_cons_names (GadtC ns _ _)    = ns
get_cons_names (RecGadtC ns _ _) = ns

{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE FunctionalDependencies     #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE TemplateHaskell            #-}
{-# OPTIONS_GHC -Wall #-}

-- TODO: More precise error and logging origins

module Camfort.Specification.Hoare.CheckBackend
  ( AnnotatedProgramUnit(..)
  , apuPreconditions
  , apuPostconditions
  , apuPU
  , apuAuxDecls
  , BackendAnalysis
  , HoareCheckResult(..)
  , HoareBackendError(..)
  , checkPU
  ) where

import           Data.Data (Data)
import           Control.Exception                      (Exception (..))
import           Control.Lens
import           Control.Monad.Except
import           Control.Monad.Reader
import           Control.Monad.RWS.Strict
import           Control.Monad.State.Strict
import           Data.Foldable                          (foldlM)
import           Data.Generics.Uniplate.Operations
import           Data.Map                               (Map)
import           Data.Maybe                             (isJust)
import           Data.Void                              (Void)

import           Data.SBV                               (SBool, defaultSMTCfg)

import qualified Language.Fortran.Analysis              as F
import qualified Language.Fortran.AST                   as F
import qualified Language.Fortran.LValue                as F
import qualified Language.Fortran.Util.Position         as F

import           Camfort.Analysis
import           Camfort.Analysis.Logger                (Builder, Text)
import           Camfort.Helpers.TypeLevel
import           Camfort.Specification.Hoare.Annotation
import           Camfort.Specification.Hoare.Syntax
import           Camfort.Specification.Hoare.Translate
import           Language.Fortran.Model
import           Language.Fortran.Model.Repr
import           Language.Fortran.Model.Repr.Prim
import           Language.Fortran.Model.Translate
import           Language.Fortran.Model.Vars

import           Language.Expression
import           Language.Expression.Pretty
import           Language.Expression.Prop
import           Language.Verification
import           Language.Verification.Conditions

--------------------------------------------------------------------------------
--  Data types
--------------------------------------------------------------------------------

data AnnotatedProgramUnit =
  AnnotatedProgramUnit
  { _apuPreconditions  :: [PrimFormula InnerHA]
  , _apuPostconditions :: [PrimFormula InnerHA]
  , _apuAuxDecls       :: [AuxDecl InnerHA]
  , _apuPU             :: F.ProgramUnit HA
  }

data HoareBackendError
  = VerifierError (VerifierError FortranVar)
  | TranslateErrorAnn TranslateError
  -- ^ Unit errors come from translating annotation formulae
  | TranslateErrorSrc TranslateError
  -- ^ HA errors come from translating actual source Fortran
  | InvalidSourceName SourceName
  -- ^ A program source name had no unique name
  | UnsupportedBlock (F.Block HA)
  -- ^ Found a block that we don't know how to deal with
  | UnexpectedBlock (F.Block HA)
  -- ^ Found a block in an illegal place
  | ArgWithoutDecl NamePair
  -- ^ Found an argument that didn't come with a variable declaration
  | AnnotationError (F.Block HA)
  -- ^ The program was insufficiently annotated (TODO: more detail)
  | AssignVarNotInScope NamePair
  -- ^ The variable was referenced in an assignment but not in scope
  | MissingWhileInvariant (F.Block HA)
  -- ^ The while block had no associated invariant
  | WrongAssignmentType Text SomeType
  -- ^ Expected array type but got the given type instead
  | NonLValueAssignment
  -- ^ Assigning to an expression that isn't an lvalue
  | UnsupportedAssignment Text
  -- ^ Tried to assign to something that's valid Fortran but unsupported

instance Describe HoareBackendError where
  describeBuilder = \case
    VerifierError e -> "verifier error: " <> describeBuilder (displayException e)
    TranslateErrorAnn te -> "translation error in logic annotation: " <> describeBuilder te
    TranslateErrorSrc te -> "translation error in source code: " <> describeBuilder te
    InvalidSourceName nm -> "a program source name had no associated unique name: " <> describeBuilder (pretty nm)
    UnsupportedBlock _ -> "encountered unsupported block"
    UnexpectedBlock _ -> "a block was found in an illegal location"
    ArgWithoutDecl nm ->
      "argument " <> describeBuilder (show nm) <>
      " doesn't have an associated type declaration"
    AnnotationError _ ->
      "the program was insufficiently annotated; " <>
      "`seq` annotations must appear before each command which is not an assignment"
    AssignVarNotInScope nm -> "variable " <> describeBuilder (pretty nm) <>
      " is being assigned to but is not in scope"
    MissingWhileInvariant _ ->
      "found a `do while` block with no invariant; " <>
      "invariant annotations must appear at the start of every `do while` loop"
    WrongAssignmentType message gotType ->
      "unexpected variable type; expected " <> describeBuilder message <>
      "; got " <> describeBuilder (pretty gotType)
    NonLValueAssignment ->
      "assignment an expression which is not a valid lvalue"
    UnsupportedAssignment message ->
      "unsupported assignment; " <> describeBuilder message

type BackendAnalysis = AnalysisT HoareBackendError Void IO

data HoareCheckResult = HoareCheckResult (F.ProgramUnit HA) Bool
  deriving (Show)

describePuName :: F.ProgramUnitName -> Builder
describePuName (F.Named n)         = describeBuilder n
describePuName F.NamelessBlockData = "<nameless block data>"
describePuName F.NamelessComment   = "<nameless comment>"
describePuName F.NamelessMain      = "<nameless main>"

instance Describe HoareCheckResult where
  describeBuilder (HoareCheckResult pu result) =
    "Program unit '" <> describePuName (F.puSrcName pu) <> "': " <>
    (if result then "verified!" else "unverifiable!")

data CheckHoareState =
  CheckHoareState

type ScopeVars = Map UniqueName SomeVar

data CheckHoareEnv =
  CheckHoareEnv
  { _heImplicitVars   :: Bool
  , _heVarsInScope    :: ScopeVars
    -- ^ The variables in scope. Associates unique names with name pairs and types.
  , _heSourceToUnique :: Map SourceName [UniqueName]
    -- ^ The corresponding unique names for all the source names we have seen.
  , _heReprHandler    :: forall p k a. Prim p k a -> PrimReprHandler a
  , _hePU             :: F.ProgramUnit HA
  }

initialState :: CheckHoareState
initialState = CheckHoareState

emptyEnv :: F.ProgramUnit HA -> PrimReprSpec -> CheckHoareEnv
emptyEnv pu spec = CheckHoareEnv True mempty mempty (makeSymRepr spec) pu

makeLenses ''AnnotatedProgramUnit
makeLenses ''CheckHoareState
makeLenses ''CheckHoareEnv

instance HasPrimReprHandlers CheckHoareEnv where
  primReprHandler = view heReprHandler

--------------------------------------------------------------------------------
--  Main function
--------------------------------------------------------------------------------

checkPU :: AnnotatedProgramUnit -> PrimReprSpec -> BackendAnalysis HoareCheckResult
checkPU apu symSpec = do

  let pu = apu ^. apuPU

  (bodyTriple, env) <- flip runStateT (emptyEnv pu symSpec) $ do
    logInfo' pu $ " - Setting up"

    body <- initialSetup

    let translatePUFormulae =
            readerOfState
          . traverse (tryTranslateFormula pu)

    preconds <- translatePUFormulae (apu ^. apuPreconditions)
    postconds <- translatePUFormulae (apu ^. apuPostconditions)

    logInfo' pu $ " - Interpreting pre- and postconditions"

    let precond = propAnd preconds
        postcond = propAnd postconds

    logInfo' pu $ " - Found preconditions: "  <> describe (pretty precond)
    logInfo' pu $ " - Found postconditions: " <> describe (pretty postcond)

    return (precond, postcond, body)

  logInfo' pu $ " - Computing verification conditions"

  (_, vcs) <- runGenM env (genBody bodyTriple)

  logInfo' pu $ " - Verifying conditions:"

  let checkVcs _ [] = return True
      checkVcs i (vc : rest) = do
        logInfo' pu $ "   " <> describeShow i <> ". " <> describe (pretty vc)
        result <- verifyVc (failAnalysis' pu) vc
        if result
          then checkVcs (1 + i) rest
          else do
          logInfo' pu "    - Failed!"
          zipWithM_ printUnchecked [(1 + i)..] vcs
          return False

      printUnchecked i vc = do
        logInfo' pu $ "   " <> describeShow i <> ". " <> describe (pretty vc)
        logInfo' pu   "    - Unchecked"

  HoareCheckResult pu <$> runReaderT (checkVcs (1 :: Int) vcs) env

--------------------------------------------------------------------------------
--  Check Monad
--------------------------------------------------------------------------------

type CheckHoare = BackendAnalysis

-- TODO: Maybe report a warning when two variables have the same source name.


varOfType :: NamePair -> SomeType -> SomeVar
varOfType names (Some d) = Some (FortranVar d names)

expNamePair :: F.Expression (F.Analysis a) -> NamePair
expNamePair = NamePair <$> UniqueName . F.varName <*> SourceName . F.srcName

functionNamePair :: F.ProgramUnit (F.Analysis a) -> NamePair
functionNamePair =
  NamePair <$> UniqueName . fromPuName . F.puName
           <*> SourceName . fromPuName . F.puSrcName
  where
    fromPuName (F.Named n) = n
    fromPuName _           = error "impossible: function has no name"

-- | Create a variable in scope with the given name and type.
newVar :: NamePair -> SomeType -> CheckHoareEnv -> CheckHoareEnv
newVar np@(NamePair uniq src) ty
  = (heVarsInScope . at uniq .~ Just (varOfType np ty))
  . (heSourceToUnique . at src %~ \case
        Nothing -> Just [uniq]
        Just xs -> Just (uniq : xs))


-- | In specifications attached to program units (pre- and post-conditions), the
-- @fortran-src@ renamer doesn't have access to a renaming environment so it
-- doesn't assign the right unique names. Once we have access to unique names
-- from inside the program unit, this function assigns those names to variables
-- in the PU specifications.
setFormulaUniqueNames :: (Data ann) => Map SourceName [UniqueName] -> PrimFormula (F.Analysis ann) -> PrimFormula (F.Analysis ann)
setFormulaUniqueNames nameMap = transformBi setExpUN
  where
    setExpUN :: F.Expression InnerHA -> F.Expression InnerHA
    setExpUN = do
      np <- realNamePair <$> expNamePair
      F.modifyAnnotation (setAnnUniq (np ^. npUnique . _Wrapped))

    realNamePair np@(NamePair _ src) =
      -- TODO: How sound is it to take the first available? Should I throw
      -- warnings?
      case nameMap ^? ix src . _Cons . _1 of
        Just uniq -> NamePair uniq src
        Nothing   -> np

    setAnnUniq uniq a = a { F.uniqueName = Just uniq }


-- | Sets up the environment for checking the program unit, including reading
-- past variable declarations. Returns the blocks after the variable declarations.
initialSetup :: StateT CheckHoareEnv CheckHoare [F.Block HA]
initialSetup = do
  pu <- use hePU
  let body = childrenBi pu :: [F.Block HA]

  -- If the program unit is a function, we might need to treat its name as a
  -- variable with its return type.

  -- If the program is a function or subroutine, it might have arguments that we
  -- need to treat as variables.
  rawArgNames <- case pu of
    F.PUFunction _ _ (Just rettype) _ _ funargs retvalue _ _ -> do
      rettype' <- readerOfState $ tryTranslateTypeInfo (typeInfo rettype)

      let retNames = case retvalue  of
            Just rv -> expNamePair rv
            Nothing -> functionNamePair pu

      modify $ newVar retNames rettype'

      return (maybe [] F.aStrip funargs)

    F.PUSubroutine _ _ _ _ subargs _ _ -> return (maybe [] F.aStrip subargs)
    _ -> return []

  let argNames = map expNamePair rawArgNames

  restBody <- readInitialBlocks body

  -- Verify that all argument names have types associated with them.
  forM_ argNames $ \argName -> do
    hasType <- isJust <$> use (heVarsInScope . at (argName ^. npUnique))
    unless hasType $ failAnalysis' pu (ArgWithoutDecl argName)

  return restBody


-- | As part of the initial setup, reads setup blocks like declarations and
-- implicit statements. Updates the environment accordingly. Returns the rest of
-- the blocks, after the setup blocks.
readInitialBlocks :: [F.Block HA] -> StateT CheckHoareEnv CheckHoare [F.Block HA]
readInitialBlocks = dropWhileM readInitialBlock
  where
    -- This function should return 'True' if the block may be part of the setup,
    -- and 'False' otherwise.
    readInitialBlock :: F.Block HA -> StateT CheckHoareEnv CheckHoare Bool
    readInitialBlock bl = case bl of
      F.BlStatement _ _ _ st ->
        case st of
          F.StDeclaration _ _ astTypeSpec attrs decls -> do
            -- This is the part of the type info that applies to every variable
            -- in the declaration list.
            let topTypeInfo =
                  typeInfo astTypeSpec &
                  tiAttributes .~ attrs

            -- Each variable may have extra information that modifies its type info
            declVarsTis <- forM (F.aStrip decls) $ \case
              -- TODO: Deal with declarations that include assignments
              F.DeclVariable _ _ nameExp declLength Nothing ->
                return (nameExp,
                        topTypeInfo
                        & tiDeclaratorLength .~ declLength)

              F.DeclArray _ _ nameExp declDims declLength Nothing ->
                return (nameExp,
                        topTypeInfo
                        & tiDeclaratorLength .~ declLength
                        & tiDimensionDeclarators .~ Just declDims)

              _ -> failAnalysis' bl (UnsupportedBlock bl)

            forM_ declVarsTis $ \(varNameExp, varTypeInfo) -> do
              varType <- readerOfState $ tryTranslateTypeInfo varTypeInfo
              let varNames = expNamePair varNameExp
              modify $ newVar varNames varType

            return True

          F.StImplicit _ _ Nothing -> do
            -- TODO: Deal with implicits properly
            return True
          F.StImplicit _ _ (Just _) -> failAnalysis' bl (UnsupportedBlock bl)
          _ -> return False

      F.BlComment{} -> return True
      _ -> return False

verifyVc :: (HoareBackendError -> CheckHoare Bool) -> MetaFormula Bool -> ReaderT CheckHoareEnv CheckHoare Bool
verifyVc handle prop = do
  let getSrProp :: HighRepr Bool -> SBool
      getSrProp (HRHigh x) = x
      getSrProp (HRCore _) = error "absurd"

  let debug = False
      cfg | debug = defaultSMTCfg { verbose = True, transcript = Just "transcript.smt2" }
          | otherwise = defaultSMTCfg

  env <- asks primReprHandlers

  let res = query (getSrProp <$> runReaderT (evalProp lift HRCore prop) env) env
  res' <- liftIO . runVerifierWith cfg $ res

  case res' of
    Right b -> return b
    Left e  -> lift $ handle (VerifierError e)

--------------------------------------------------------------------------------
--  Generation Monad
--------------------------------------------------------------------------------

newtype GenM a = GenM (RWST CheckHoareEnv [MetaFormula Bool] CheckHoareState CheckHoare a)
  deriving
    ( Functor
    , Applicative
    , Monad
    , MonadState CheckHoareState
    , MonadReader CheckHoareEnv
    , MonadWriter [MetaFormula Bool]
    , MonadIO
    , MonadLogger HoareBackendError Void
    , MonadAnalysis HoareBackendError Void
    )


runGenM :: CheckHoareEnv -> GenM a -> CheckHoare (a, [MetaFormula Bool])
runGenM env (GenM action) = evalRWST action env initialState


type FortranTriplet a = Triplet MetaExpr FortranVar a


genBody :: FortranTriplet [F.Block HA] -> GenM ()
genBody = traverseOf _3 bodyToSequence >=> void . sequenceVCs genBlock


genBlock :: FortranTriplet (F.Block HA) -> GenM ()
genBlock (precond, postcond, bl) = do
  case bl of
    F.BlIf _ _ _ _ conds bodies _ -> do
      condsExprs <- traverse (traverse tryTranslateBoolExpr) conds
      multiIfVCs genBody expr (precond, postcond, (zip condsExprs bodies))

    F.BlDoWhile _ _ _ _ cond body _ -> do
      primInvariant <-
        case body of
         b : _ | Just (SodSpec (Specification SpecInvariant f)) <- getAnnSod (F.getAnnotation b) -> return f
         _ -> failAnalysis' bl $ MissingWhileInvariant bl

      invariant <- tryTranslateFormula body primInvariant
      condExpr <- tryTranslateBoolExpr cond

      whileVCs genBody expr invariant (precond, postcond, (condExpr, body))

    F.BlComment _ _ _ -> return ()
    _ -> failAnalysis' bl $ UnsupportedBlock bl


bodyToSequence :: [F.Block HA] -> GenM (AnnSeq MetaExpr FortranVar (F.Block HA))
bodyToSequence blocks = do
  foldlM combineBlockSequence emptyAnnSeq blocks


combineBlockSequence
  :: AnnSeq MetaExpr FortranVar (F.Block HA)
  -> F.Block HA
  -> GenM (AnnSeq MetaExpr FortranVar (F.Block HA))
combineBlockSequence prevSeq bl = do
  blSeq <- blockToSequence bl

  case prevSeq `joinAnnSeq` blSeq of
    Just r  -> return r
    Nothing -> failAnalysis' bl $ AnnotationError bl


blockToSequence :: F.Block HA -> GenM (AnnSeq MetaExpr FortranVar (F.Block HA))
blockToSequence bl = do
  chooseFrom [assignment, sequenceSpec, other]
  where
    assignment =
      assignmentBlock bl >>= \case
        Just a -> return $ Just $ JustAssign [a]
        Nothing -> return $ Nothing

    sequenceSpec =
      case getAnnSod (F.getAnnotation bl) of
        Just (SodSpec (Specification SpecSeq m)) -> do
          m' <- tryTranslateFormula bl m
          return $ Just $ propAnnSeq m'
        _ -> return Nothing

    other = return $ case bl of
      F.BlComment{} -> Just emptyAnnSeq
      _             -> Just $ cmdAnnSeq bl

    -- Tries each action in the list, using the first that works and otherwise
    -- reporting an error.
    chooseFrom :: [GenM (Maybe a)] -> GenM a
    chooseFrom [] = failAnalysis' bl $ AnnotationError bl
    chooseFrom (action : rest) = do
      m <- action
      case m of
        Just x  -> return x
        Nothing -> chooseFrom rest

--------------------------------------------------------------------------------
-- Handling assignments

primAssignment
  :: (ReportAnn (F.Analysis ann))
  => NamePair
  -> F.Expression (F.Analysis ann)
  -> GenM (Assignment MetaExpr FortranVar)
primAssignment nm rvalAst = do
  Some varV@(FortranVar varD _) <- varFromScope rvalAst nm

  case varD of
    DPrim _ -> do
      rvalExpr <- tryTranslateExpr varD rvalAst
      return (Assignment varV (intoMetaExpr rvalExpr))
    _ -> failAnalysis' rvalAst $ WrongAssignmentType "primitive value" (Some varD)

arrayAssignment
  :: (ReportAnn (F.Analysis ann))
  => NamePair
  -> F.Expression (F.Analysis ann)
  -> F.Expression (F.Analysis ann)
  -> GenM (Assignment MetaExpr FortranVar)
arrayAssignment arrName ixAst rvalAst = do
  Some varV@(FortranVar varD _) <- varFromScope rvalAst arrName

  case varD of
    DArray ixIndex valAv -> do
      let ixD = dIndex ixIndex
          valD = dArrValue valAv

      ixExpr   <- intoMetaExpr <$> tryTranslateExpr ixD ixAst
      rvalExpr <- intoMetaExpr <$> tryTranslateExpr valD rvalAst

      -- Replace instances of the array variable with the same array, but with
      -- the new value written at the given index.
      let arrExpr = Expr' $ EVar varV
          arrExpr' = eop' $ MopWriteArr varD arrExpr ixExpr rvalExpr

      return (Assignment varV arrExpr')

    _ -> failAnalysis' rvalAst $ WrongAssignmentType "array type" (Some varD)


assignmentBlock :: F.Block HA -> GenM (Maybe (Assignment MetaExpr FortranVar))
assignmentBlock bl = do
  case bl of
    F.BlStatement _ _ _ stAst@(F.StExpressionAssign _ _ lexp rvalue) ->
      Just <$> do
        lvalue <- maybe (failAnalysis' lexp NonLValueAssignment)
                  return (F.toLValue lexp)

        case lvalue of
          F.LvSimpleVar {} -> primAssignment (expNamePair lexp) rvalue

          F.LvSubscript _ _ lvar@(F.LvSimpleVar {}) ixs ->
            case ixs of
              F.AList _ _ [F.IxSingle _ _ _ ixExpr] ->
                arrayAssignment (lvVarNames lvar) ixExpr rvalue

              _ -> failAnalysis' ixs $
                   UnsupportedAssignment "only simple indices are supported for now"
          _ -> failAnalysis' stAst $
               UnsupportedAssignment "complex assignment"

    _ -> return Nothing


--------------------------------------------------------------------------------

varFromScope :: (F.Spanned a) => a -> NamePair -> GenM SomeVar
varFromScope loc np = do
  let uniq = np ^. npUnique
  mscoped <- view (heVarsInScope . at uniq)
  case mscoped of
    Just v  -> return v
    Nothing -> failAnalysis' loc $ AssignVarNotInScope np

--------------------------------------------------------------------------------
--  Translation
--------------------------------------------------------------------------------

class Show a => ReportAnn a where
  fromTranslateError :: proxy a -> TranslateError -> HoareBackendError

instance ReportAnn HA      where fromTranslateError _ = TranslateErrorSrc
instance ReportAnn InnerHA where fromTranslateError _ = TranslateErrorAnn


doTranslate
  :: (MonadReader CheckHoareEnv m, ReportAnn ann)
  => (HoareBackendError -> m a) -> (f ann -> TranslateT m a) -> f ann -> m a
doTranslate handle trans ast = do
  env <- asks toTranslateEnv
  transResult <- runTranslateT (trans ast) env
  case transResult of
    Right x  -> return x
    Left err -> handle (fromTranslateError ast err)


toTranslateEnv :: CheckHoareEnv -> TranslateEnv
toTranslateEnv env =
  defaultTranslateEnv
    & teImplicitVars .~ env ^. heImplicitVars
    & teVarsInScope .~ env ^. heVarsInScope

--------------------------------------------------------------------------------
-- Shorthands for translating expressions and failing the analysis if the
-- translation fails

tryTranslateExpr
  :: ( ReportAnn (F.Analysis ann)
     , MonadReader CheckHoareEnv m
     , MonadAnalysis HoareBackendError w m
     )
  => D a -> F.Expression (F.Analysis ann) -> m (FortranExpr a)
tryTranslateExpr d e = doTranslate (failAnalysis' e) (translateExpression' d) e

tryTranslateTypeInfo
  :: ( ReportAnn (F.Analysis ann)
     , MonadReader CheckHoareEnv m
     , MonadAnalysis HoareBackendError w m
     )
  => TypeInfo (F.Analysis ann) -> m SomeType
tryTranslateTypeInfo ti = doTranslate (failAnalysis' ti) translateTypeInfo ti

tryTranslateBoolExpr
  :: ( ReportAnn (F.Analysis ann)
     , MonadReader CheckHoareEnv m
     , MonadAnalysis HoareBackendError w m
     )
  => F.Expression (F.Analysis ann) -> m (MetaExpr FortranVar Bool)
tryTranslateBoolExpr e = doTranslate (failAnalysis' e) translateBoolExpression e

tryTranslateFormula
  :: ( F.Spanned o
     , ReportAnn (F.Analysis ann)
     , Data ann
     , MonadReader CheckHoareEnv m
     , MonadAnalysis HoareBackendError w m
     )
  => o -> PrimFormula (F.Analysis ann) -> m (MetaFormula Bool)
tryTranslateFormula loc formula = do
  sourceToUnique <- view heSourceToUnique
  -- TODO: Instead of setting unique names before translation, can we get the
  -- renamer to work inside annotations? I've tried to make this work but ran
  -- into some problems:
  -- - We have to run the renamer before calling 'annotateComments' or it
  --   doesn't find any comments (why?).
  -- - When the renamer is run /after/ calling 'annotateComemnts' it doesn't do
  --   any renaming inside annotations (why?)
  let formulaUN = setFormulaUniqueNames sourceToUnique formula
  doTranslate (failAnalysis' loc) translateFormula formulaUN

--------------------------------------------------------------------------------
--  Utility functions
--------------------------------------------------------------------------------

dropWhileM :: (Monad m) => (a -> m Bool) -> [a] -> m [a]
dropWhileM _ [] = return []
dropWhileM f (x : xs) = do
  continue <- f x
  if continue
    then dropWhileM f xs
    else return (x : xs)


getAnnSod :: HA -> Maybe (SpecOrDecl InnerHA)
getAnnSod = view (to F.prevAnnotation . hoareSod)


lvVarNames :: F.LValue (F.Analysis x) -> NamePair
lvVarNames e =
  let uniqueName = UniqueName $ F.lvVarName e
      srcName = SourceName $ F.lvSrcName e
  in NamePair uniqueName srcName


readerOfState :: (MonadState s m) => ReaderT s m a -> m a
readerOfState action = do
  st <- get
  runReaderT action st

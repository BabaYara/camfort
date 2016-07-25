{-
   Copyright 2016, Dominic Orchard, Andrew Rice, Mistral Contrastin, Matthew Danish

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
-}

{-
  Units of measure extension to Fortran: frontend
-}

{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PatternGuards #-}

module Camfort.Specification.Units.InferenceFrontend
  ( initInference, runCriticalVariables, runInferVariables, runInconsistentConstraints, getConstraint )
where

import Data.Data (Data)
import Data.List (nub)
import qualified Data.Map as M
import qualified Data.Set as S
import Data.Maybe (isJust, fromMaybe)
import Data.Generics.Uniplate.Operations
import Control.Monad
import Control.Monad.State.Strict
import Control.Monad.Writer.Strict
import Control.Monad.Trans.Except
import Control.Monad.RWS.Strict

import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Analysis as FA

import Camfort.Analysis.CommentAnnotator (annotateComments)
import Camfort.Analysis.Annotations
import Camfort.Specification.Units.Environment
import Camfort.Specification.Units.Monad
import Camfort.Specification.Units.InferenceBackend
import qualified Camfort.Specification.Units.Parser as P

import qualified Debug.Trace as D
import qualified Numeric.LinearAlgebra as H -- for debugging

--------------------------------------------------

-- | Prepare to run an inference function.
initInference :: UnitSolver ()
initInference = do
  pf <- gets usProgramFile
  -- Parse unit annotations found in comments and link to their
  -- corresponding statements in the AST.
  let (linkedPF, parserReport) = runWriter $ annotateComments P.unitParser pf
  modifyProgramFile $ const linkedPF

  -- Send the output of the parser to the logger.
  mapM_ tell parserReport

  -- The following insert* functions examine the AST and insert
  -- mappings into the tables stored in the UnitState.

  -- First, find all given unit annotations and insert them into our
  -- mappings.  Also obtain all unit alias definitions.
  insertGivenUnits

  -- For function or subroutine parameters (or return variables) that
  -- are not given explicit units, give them a parametric polymorphic
  -- unit.
  insertParametricUnits

  -- Any other variables get assigned a unique undetermined unit named
  -- after the variable. This assumes that all variables have unique
  -- names, which the renaming module already has assured.
  insertUndeterminedUnits

  -- Now take the information that we have gathered and annotate the
  -- variable expressions within the AST with it.
  annotateAllVariables

  -- Annotate the literals within the program based upon the
  -- Literals-mode option.
  annotateLiterals

  -- With the variable expressions annotated, we now propagate the
  -- information throughout the AST, giving units to as many
  -- expressions as possible, and also constraints wherever
  -- appropriate.
  propagateUnits

  -- Gather up all of the constraints that we identified in the AST.
  -- These constraints will include parametric polymorphic units that
  -- have not yet been instantiated into their particular uses.
  abstractCons <- extractConstraints

  -- Eliminate all parametric polymorphic units by copying them for
  -- each specific use cases and substituting a unique call-site
  -- identifier that distinguishes each use-case from the others.
  cons <- applyTemplates abstractCons

  -- Remove any traces of CommentAnnotator, since the annotations can
  -- cause generic operations traversing the AST to get confused.
  modifyProgramFile cleanLinks

  modify $ \ s -> s { usConstraints = cons }

  debugLogging

cleanLinks :: F.ProgramFile UA -> F.ProgramFile UA
cleanLinks = transformBi (\ a -> a { unitBlock = Nothing, unitSpec = Nothing } :: UnitAnnotation A)

--------------------------------------------------
-- Inference functions

-- | Return a list of critical variables as UnitInfo list (most likely
-- to be of the UnitVar constructor).
runCriticalVariables :: UnitSolver [UnitInfo]
runCriticalVariables = do
  cons <- usConstraints `fmap` get
  return $ criticalVariables cons

-- | Return a list of variable names mapped to their corresponding
-- unit that was inferred.
runInferVariables :: UnitSolver [(String, UnitInfo)]
runInferVariables = do
  cons <- usConstraints `fmap` get
  return $ inferVariables cons

-- | Return a possible list of unsolvable constraints.
runInconsistentConstraints :: UnitSolver (Maybe Constraints)
runInconsistentConstraints = do
  cons <- usConstraints `fmap` get
  return $ inconsistentConstraints cons

--------------------------------------------------

-- | Seek out any parameters to functions or subroutines that do not
-- already have units, and insert parametric units for them into the
-- map of variables to UnitInfo.
insertParametricUnits :: UnitSolver ()
insertParametricUnits = gets usProgramFile >>= (mapM_ paramPU . universeBi)
  where
    paramPU pu = do
      forM_ indexedParams $ \ (i, param) -> do
        -- Insert a parametric unit if the variable does not already have a unit.
        modifyVarUnitMap $ M.insertWith (curry snd) param (UnitParamAbs (fname, i))
      where
        fname = puName pu
        indexedParams
          | F.PUFunction _ _ _ _ _ (Just paList) (Just r) _ _ <- pu = zip [0..] $ varName r : map varName (F.aStrip paList)
          | F.PUFunction _ _ _ _ _ (Just paList) _ _ _        <- pu = zip [0..] $ fname     : map varName (F.aStrip paList)
          | F.PUSubroutine _ _ _ _ (Just paList) _ _          <- pu = zip [1..] $ map varName (F.aStrip paList)
          | otherwise                                               = []

--------------------------------------------------

-- | Any remaining variables with unknown units are given unit UnitVar
-- with a unique name (in this case, taken from the unique name of the
-- variable as provided by the Renamer), or UnitParamVarAbs if the
-- variables are inside of a function or subroutine.
insertUndeterminedUnits :: UnitSolver ()
insertUndeterminedUnits = do
  pf <- gets usProgramFile
  forM_ (universeBi pf) $ \ pu -> case pu of
    F.PUFunction {}   -> modifyPUBlocksM (transformBiM (toParamVar (puName pu))) pu
    F.PUSubroutine {} -> modifyPUBlocksM (transformBiM (toParamVar (puName pu))) pu
    _                 -> modifyPUBlocksM (transformBiM toUnitVar) pu

  where
    toParamVar :: String -> F.Expression UA -> UnitSolver (F.Expression UA)
    toParamVar fname v@(F.ExpValue _ _ (F.ValVariable _)) = do
      let vname = varName v
      modifyVarUnitMap $ M.insertWith (curry snd) vname (UnitParamVarAbs (fname, vname))
      return v
    toParamVar _ e = return e

    toUnitVar :: F.Expression UA -> UnitSolver (F.Expression UA)
    toUnitVar v@(F.ExpValue _ _ (F.ValVariable _)) = do
      let vname = varName v
      modifyVarUnitMap $ M.insertWith (curry snd) vname (UnitVar vname)
      return v
    toUnitVar e = return e

--------------------------------------------------

-- | Any units provided by the programmer through comment annotations
-- will be incorporated into the VarUnitMap.
insertGivenUnits :: UnitSolver ()
insertGivenUnits = do
  pf <- gets usProgramFile
  mapM_ checkComment [ b | b@(F.BlComment {}) <- universeBi pf ]
  where
    -- Look through each comment that has some kind of unit annotation within it.
    checkComment :: F.Block UA -> UnitSolver ()
    checkComment (F.BlComment a _ _)
      -- Look at unit assignment between variable and spec.
      | Just (P.UnitAssignment (Just vars) unitsAST) <- mSpec
      , Just b                                       <- mBlock = insertUnitAssignments (toUnitInfo unitsAST) b vars
      -- Add a new unit alias.
      | Just (P.UnitAlias name unitsAST)             <- mSpec  = modifyUnitAliasMap (M.insert name (toUnitInfo unitsAST))
      | otherwise                                              = return ()
      where
        mSpec  = unitSpec (FA.prevAnnotation a)
        mBlock = unitBlock (FA.prevAnnotation a)

    -- Figure out the unique names of the referenced variables and
    -- then insert unit info under each of those names.
    insertUnitAssignments info (F.BlStatement _ _ _ (F.StDeclaration _ _ _ _ decls)) varRealNames = do
      -- figure out the 'unique name' of the varRealName that was found in the comment
      -- FIXME: account for module renaming
      -- FIXME: might be more efficient to allow access to variable renaming environ at this program point
      nameMap <- uoNameMap `fmap` ask
      let m = M.fromList [ (varUniqueName, info) | e@(F.ExpValue _ _ (F.ValVariable _)) <- universeBi decls
                                                 , varRealName <- varRealNames
                                                 , let varUniqueName = varName e
                                                 , maybe False (== varRealName) (varUniqueName `M.lookup` nameMap) ]
      modifyVarUnitMap $ M.unionWith const m
      modifyGivenVarSet . S.union . S.fromList . M.keys $ m

--------------------------------------------------

-- | Take the unit information from the VarUnitMap and use it to
-- annotate every variable expression in the AST.
annotateAllVariables :: UnitSolver ()
annotateAllVariables = modifyProgramFileM $ \ pf -> do
  varUnitMap <- usVarUnitMap `fmap` get
  let annotateExp e@(F.ExpValue _ _ (F.ValVariable _))
        | Just info <- M.lookup (varName e) varUnitMap = setUnitInfo info e
      annotateExp e = e
  return $ transformBi annotateExp pf

--------------------------------------------------

-- | Give units to literals based upon the rules of the Literals mode.
--
-- LitUnitless: All literals are unitless.
-- LitPoly:     All literals are polymorphic.
-- LitMixed:    The literal "0" or "0.0" is fully parametric polymorphic.
--              All other literals are monomorphic, possibly unitless.
annotateLiterals :: UnitSolver ()
annotateLiterals = modifyProgramFileM (transformBiM annotateLiteralsPU)

annotateLiteralsPU :: F.ProgramUnit UA -> UnitSolver (F.ProgramUnit UA)
annotateLiteralsPU pu = do
  mode <- asks uoLiterals
  case mode of
    LitUnitless -> modifyPUBlocksM (transformBiM expUnitless) pu
    LitPoly     -> modifyPUBlocksM (transformBiM (withLiterals genParamLit)) pu
    LitMixed    -> modifyPUBlocksM (transformBiM expMixed) pu
  where
    -- Follow the LitMixed rules.
    expMixed e = case e of
      F.ExpValue _ _ (F.ValInteger i) | read i == (0 :: Int) -> withLiterals genParamLit e
                                      | otherwise            -> withLiterals genUnitLiteral e
      F.ExpValue _ _ (F.ValReal i) | read i == (0 :: Double) -> withLiterals genParamLit e
                                   | otherwise               -> withLiterals genUnitLiteral e
      _                                                      -> return e

    -- Set all literals to unitless.
    expUnitless e
      | isLiteral e = return $ setUnitInfo UnitlessLit e
      | otherwise   = return e

    -- Set all literals to the result of given monadic computation.
    withLiterals m e
      | isLiteral e = flip setUnitInfo e `fmap` m
      | otherwise   = return e

--------------------------------------------------

-- | Convert all parametric templates into actual uses, via substitution.
applyTemplates :: Constraints -> UnitSolver Constraints
-- postcondition: returned constraints lack all Parametric constructors
applyTemplates cons = do
  let instances = nub [ (name, i) | UnitParamUse (name, _, i) <- universeBi cons ]
  temps <- foldM substInstance [] instances
  aliasMap <- usUnitAliasMap `fmap` get
  let aliases = [ ConEq (UnitAlias name) def | (name, def) <- M.toList aliasMap ]
  let transAlias (UnitName a) | a `M.member` aliasMap = UnitAlias a
      transAlias u                                    = u
  return . transformBi transAlias . filter (not . isParametric) $ cons ++ temps ++ aliases

-- | Look up Parametric template and apply it to everything.
substInstance :: Constraints -> (F.Name, Int) -> UnitSolver Constraints
substInstance output (name, callId) = do
  tmap <- usTemplateMap `fmap` get
  return . instantiate (name, callId) . (output ++) $ [] `fromMaybe` M.lookup name tmap

-- | Convert a parametric template into a particular use
instantiate (name, callId) = transformBi $ \ info -> case info of
  UnitParamAbs (name, position)  -> UnitParamUse (name, position, callId)
  UnitParamLitAbs litId          -> UnitParamLitUse (litId, callId)
  UnitParamVarAbs (fname, vname) -> UnitParamVarUse (fname, vname, callId)
  _                              -> info

-- | Gather all constraints from the AST, as well as from the varUnitMap
extractConstraints :: UnitSolver Constraints
extractConstraints = do
  pf         <- gets usProgramFile
  varUnitMap <- gets usVarUnitMap
  return $ [ con | con@(ConEq {}) <- universeBi pf ] ++
           [ ConEq (UnitVar v) u | (v, u) <- M.toList varUnitMap ]

-- | Does the constraint contain any Parametric elements?
isParametric :: Constraint -> Bool
isParametric info = not . null $ [ () | UnitParamAbs _ <- universeBi info ] ++
                                 [ () | UnitParamVarAbs _ <- universeBi info ] ++
                                 [ () | UnitParamLitAbs _ <- universeBi info ]

--------------------------------------------------

-- | Decorate the AST with unit info.
propagateUnits :: UnitSolver ()
-- precondition: all variables have already been annotated
propagateUnits = modifyProgramFileM $ transformBiM propagatePU        <=<
                                      transformBiM propagateStatement <=<
                                      transformBiM propagateExp

propagateExp :: F.Expression UA -> UnitSolver (F.Expression UA)
propagateExp e = fmap uoLiterals ask >>= \ lm -> case e of
  F.ExpValue _ _ (F.ValVariable _)       -> return e -- all variables should already be annotated
  F.ExpValue _ _ (F.ValInteger _)        -> return e -- all literal numbers should already be annotated
  F.ExpValue _ _ (F.ValReal _)           -> return e -- all literal numbers should already be annotated
  F.ExpBinary _ _ F.Multiplication e1 e2 -> setF2 UnitMul (getUnitInfoMul lm e1) (getUnitInfoMul lm e2)
  F.ExpBinary _ _ F.Division e1 e2       -> setF2 UnitMul (getUnitInfoMul lm e1) (flip UnitPow (-1) `fmap` (getUnitInfoMul lm e2))
  F.ExpBinary _ _ F.Exponentiation e1 e2 -> setF2 UnitPow (getUnitInfo e1) (constantExpression e2)
  F.ExpBinary _ _ o e1 e2 | isOp AddOp o -> setF2C ConEq  (getUnitInfo e1) (getUnitInfo e2)
                          | isOp RelOp o -> setF2C ConEq  (getUnitInfo e1) (getUnitInfo e2)
  F.ExpFunctionCall {}                   -> propagateFunctionCall e
  _                                      -> whenDebug (tell ("propagateExp: unhandled: " ++ show e)) >> return e
  where
    -- shorter names for convenience functions
    setF2 f u1 u2  = return $ maybeSetUnitInfoF2 f u1 u2 e
    -- remember, not only set a constraint, but also give a unit!
    setF2C f u1 u2 = return . maybeSetUnitInfo u1 $ maybeSetUnitConstraintF2 f u1 u2 e

propagateFunctionCall :: F.Expression UA -> UnitSolver (F.Expression UA)
propagateFunctionCall e@(F.ExpFunctionCall a s f Nothing)                     = do
  (info, _)     <- callHelper f []
  return . setUnitInfo info $ F.ExpFunctionCall a s f Nothing
propagateFunctionCall e@(F.ExpFunctionCall a s f (Just (F.AList a' s' args))) = do
  (info, args') <- callHelper f args
  return . setUnitInfo info $ F.ExpFunctionCall a s f (Just (F.AList a' s' args'))

propagateStatement :: F.Statement UA -> UnitSolver (F.Statement UA)
propagateStatement stmt = case stmt of
  F.StExpressionAssign _ _ e1 e2               -> do
    return $ maybeSetUnitConstraintF2 ConEq (getUnitInfo e1) (getUnitInfo e2) stmt
  F.StCall a s sub (Just (F.AList a' s' args)) -> do
    (_, args') <- callHelper sub args
    return $ F.StCall a s sub (Just (F.AList a' s' args'))
  F.StDeclaration {}                           -> transformBiM propagateDeclarator stmt
  _                                            -> return stmt

propagateDeclarator :: F.Declarator UA -> UnitSolver (F.Declarator UA)
propagateDeclarator decl = case decl of
  F.DeclVariable _ _ e1 _ (Just e2) -> do
    return $ maybeSetUnitConstraintF2 ConEq (getUnitInfo e1) (getUnitInfo e2) decl
  F.DeclArray _ _ e1 _ _ (Just e2)  -> do
    return $ maybeSetUnitConstraintF2 ConEq (getUnitInfo e1) (getUnitInfo e2) decl
  _                                 -> return decl

propagatePU :: F.ProgramUnit UA -> UnitSolver (F.ProgramUnit UA)
propagatePU pu = do
  let name = puName pu
  let cons = [ con | con@(ConEq {}) <- universeBi pu, containsParametric name con ]

  modifyTemplateMap (M.insert name cons)
  return (setConstraint (ConConj cons) pu)

--------------------------------------------------

-- | Check if x contains an abstract parametric reference under the given name.
containsParametric :: Data from => String -> from -> Bool
containsParametric name x = not (null [ () | UnitParamAbs (name', _) <- universeBi x, name == name' ])

-- | Coalesce various function and subroutine call common code.
callHelper :: F.Expression UA -> [F.Argument UA] -> UnitSolver (UnitInfo, [F.Argument UA])
callHelper nexp args = do
  let name = varName nexp
  callId <- genCallId -- every call-site gets its own unique identifier
  let eachArg i arg@(F.Argument _ _ _ e)
        -- add site-specific parametric constraints to each argument
        | Just u <- getUnitInfo e = setConstraint (ConEq u (UnitParamUse (name, i, callId))) arg
        | otherwise               = arg
  let args' = zipWith eachArg [1..] args
  -- build a site-specific parametric unit for use on a return variable, if any
  let info = UnitParamUse (name, 0, callId)
  return (info, args')

-- | Generate a unique identifier for a call-site.
genCallId :: UnitSolver Int
genCallId = do
  st <- get
  let callId = usLitNums st
  put $ st { usLitNums = callId + 1 }
  return callId

-- | Generate a unique identifier for a literal encountered in the code.
genUnitLiteral :: UnitSolver UnitInfo
genUnitLiteral = do
  s <- get
  let i = usLitNums s
  put $ s { usLitNums = i + 1 }
  return $ UnitLiteral i

-- | Generate a unique identifier for a polymorphic literal encountered in the code.
genParamLit :: UnitSolver UnitInfo
genParamLit = do
  s <- get
  let i = usLitNums s
  put $ s { usLitNums = i + 1 }
  return $ UnitParamLitAbs i

--------------------------------------------------

-- | Extract the unit info from a given annotated piece of AST.
getUnitInfo :: F.Annotated f => f UA -> Maybe UnitInfo
getUnitInfo = unitInfo . FA.prevAnnotation . F.getAnnotation

-- | Extract the constraint from a given annotated piece of AST.
getConstraint :: F.Annotated f => f UA -> Maybe Constraint
getConstraint = unitConstraint . FA.prevAnnotation . F.getAnnotation

-- | Extract the unit info from a given annotated piece of AST, within
-- the context of a multiplication expression, and given a particular
-- mode for handling literals.
--
-- The point is that the unit-assignment of a literal constant can
-- vary depending upon whether it is being multiplied by a variable
-- with units, and possibly by global options that assume one way or
-- the other.
getUnitInfoMul :: LiteralsOpt -> F.Expression UA -> Maybe UnitInfo
getUnitInfoMul LitPoly e          = getUnitInfo e
getUnitInfoMul _ e
  | isJust (constantExpression e) = Just UnitlessLit
  | otherwise                     = getUnitInfo e

-- | Set the UnitInfo field on a piece of AST.
setUnitInfo :: F.Annotated f => UnitInfo -> f UA -> f UA
setUnitInfo info = modifyAnnotation (onPrev (\ ua -> ua { unitInfo = Just info }))

-- | Set the Constraint field on a piece of AST.
setConstraint :: F.Annotated f => Constraint -> f UA -> f UA
setConstraint c = modifyAnnotation (onPrev (\ ua -> ua { unitConstraint = Just c }))

--------------------------------------------------

-- Various helper functions for setting the UnitInfo or Constraint of a piece of AST
maybeSetUnitInfo :: F.Annotated f => Maybe UnitInfo -> f UA -> f UA
maybeSetUnitInfo Nothing e  = e
maybeSetUnitInfo (Just u) e = setUnitInfo u e

maybeSetUnitInfoF2 :: F.Annotated f => (a -> b -> UnitInfo) -> Maybe a -> Maybe b -> f UA -> f UA
maybeSetUnitInfoF2 f (Just u1) (Just u2) e = setUnitInfo (f u1 u2) e
maybeSetUnitInfoF2 _ _ _ e                 = e

maybeSetUnitConstraintF2 :: F.Annotated f => (a -> b -> Constraint) -> Maybe a -> Maybe b -> f UA -> f UA
maybeSetUnitConstraintF2 f (Just u1) (Just u2) e = setConstraint (f u1 u2) e
maybeSetUnitConstraintF2 _ _ _ e                 = e

fmapUnitInfo :: F.Annotated f => (UnitInfo -> UnitInfo) -> f UA -> f UA
fmapUnitInfo f x
  | Just u <- getUnitInfo x = setUnitInfo (f u) x
  | otherwise               = x

-- Operate only on the blocks of a program unit, not the contained sub-programunits.
modifyPUBlocksM :: Monad m => ([F.Block a] -> m [F.Block a]) -> F.ProgramUnit a -> m (F.ProgramUnit a)
modifyPUBlocksM f pu = case pu of
  F.PUMain a s n b pus                    -> flip fmap (f b) $ \ b' -> F.PUMain a s n b' pus
  F.PUModule a s n b pus                  -> flip fmap (f b) $ \ b' -> F.PUModule a s n b' pus
  F.PUSubroutine a s r n p b subs         -> flip fmap (f b) $ \ b' -> F.PUSubroutine a s r n p b' subs
  F.PUFunction   a s r rec n p res b subs -> flip fmap (f b) $ \ b' -> F.PUFunction a s r rec n p res b' subs
  F.PUBlockData  a s n b                  -> flip fmap (f b) $ \ b' -> F.PUBlockData  a s n b'

-- Is it a literal, literally?
isLiteral (F.ExpValue _ _ (F.ValReal _)) = True
isLiteral (F.ExpValue _ _ (F.ValInteger _)) = True
isLiteral _ = False

--------------------------------------------------

-- | Statically computes if the expression is a constant value.
constantExpression :: F.Expression a -> Maybe Double
constantExpression (F.ExpValue _ _ (F.ValInteger i)) = Just $ read i
constantExpression (F.ExpValue _ _ (F.ValReal r))    = Just $ read r
-- FIXME: expand...
constantExpression _                                 = Nothing

-- | Asks the question: is the operator within the given category?
isOp :: BinOpKind -> F.BinaryOp -> Bool
isOp cat = (== cat) . binOpKind

data BinOpKind = AddOp | MulOp | DivOp | PowerOp | LogicOp | RelOp deriving Eq
binOpKind :: F.BinaryOp -> BinOpKind
binOpKind F.Addition         = AddOp
binOpKind F.Subtraction      = AddOp
binOpKind F.Multiplication   = MulOp
binOpKind F.Division         = DivOp
binOpKind F.Exponentiation   = PowerOp
binOpKind F.Concatenation    = AddOp
binOpKind F.GT               = RelOp
binOpKind F.GTE              = RelOp
binOpKind F.LT               = RelOp
binOpKind F.LTE              = RelOp
binOpKind F.EQ               = RelOp
binOpKind F.NE               = RelOp
binOpKind F.Or               = LogicOp
binOpKind F.And              = LogicOp
binOpKind F.Equivalent       = RelOp
binOpKind F.NotEquivalent    = RelOp
binOpKind (F.BinCustom _)    = RelOp

--------------------------------------------------

debugLogging :: UnitSolver ()
debugLogging = whenDebug $ do
    cons <- usConstraints `fmap` get
    vum <- usVarUnitMap `fmap` get
    tell . unlines $ [ "  " ++ show info ++ " :: " ++ n | (n, info) <- M.toList vum ]
    tell "\n\n"
    uam <- usUnitAliasMap `fmap` get
    tell . unlines $ [ "  " ++ n ++ " = " ++ show info | (n, info) <- M.toList uam ]
    tell . unlines $ map (\ (ConEq u1 u2) -> "  ***Constraint: " ++ show (flattenUnits u1) ++ " === " ++ show (flattenUnits u2) ++ "\n") cons
    tell $ show cons
    let (unsolvedM, inconsists, colA) = constraintsToMatrix cons
    let solvedM = rref unsolvedM
    tell "\n--------------------------------------------------\n"
    tell $ show colA
    tell "\n--------------------------------------------------\n"
    tell $ show unsolvedM
    tell "\n--------------------------------------------------\n"
    tell . show $ (H.takeRows (H.rank solvedM) solvedM)
    tell "\n--------------------------------------------------\n"
    tell $ "Rank: " ++ show (H.rank solvedM) ++ "\n"
    tell $ "Is inconsistent RREF? " ++ show (isInconsistentRREF solvedM) ++ "\n"
    tell $ "Inconsistent rows: " ++ show (inconsistentConstraints cons) ++ "\n"
    tell "--------------------------------------------------\n"
    tell $ "Critical Variables: " ++ show (criticalVariables cons) ++ "\n"
    tell $ "Infer Variables: " ++ show (inferVariables cons) ++ "\n"

--------------------------------------------------

-- convenience
puName :: F.ProgramUnit UA -> F.Name
puName pu
  | F.Named n <- FA.puName pu = n
  | otherwise               = "_nameless"

varName :: F.Expression UA -> F.Name
varName = FA.varName

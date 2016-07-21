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
  pf <- usProgramFile `fmap` get
  -- Parse unit annotations found in comments and link to their
  -- corresponding statements in the AST.
  let (linkedPF, parserReport) = runWriter $ annotateComments P.unitParser pf
  -- Send the output of the parser to the logger.
  mapM_ tell parserReport
  insertGivenUnits linkedPF -- also obtains all unit alias definitions
  insertParametricUnits linkedPF
  insertUnitVarUnits linkedPF
  annotPF <- annotateAllVariables linkedPF
  propPF               <- propagateUnits annotPF
  consWithoutTemplates <- extractConstraints propPF
  cons                 <- applyTemplates consWithoutTemplates

  modify $ \ s -> s { usConstraints = cons, usProgramFile = cleanLinks propPF }
  debugLogging

-- Remove traces of CommentAnnotator, since it confuses uniplate searches...
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
insertParametricUnits :: F.ProgramFile UA -> UnitSolver ()
insertParametricUnits = mapM_ paramPU . universeBi
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

-- | Any remaining variables with unknown units are given unit
-- UnitVar with a unique name (in this case, taken from the
-- unique name of the variable as provided by the Renamer).
insertUnitVarUnits :: F.ProgramFile UA -> UnitSolver ()
insertUnitVarUnits pf = forM_ (nub [ varName v | v@(F.ExpValue _ _ (F.ValVariable _)) <- universeBi pf ]) $ \ vname ->
  -- Insert an undetermined unit if the variable does not already have a unit.
  modifyVarUnitMap $ M.insertWith (curry snd) vname (UnitVar vname)

--------------------------------------------------

-- | Any units provided by the programmer through comment annotations
-- will be incorporated into the VarUnitMap.
insertGivenUnits :: F.ProgramFile UA -> UnitSolver ()
insertGivenUnits pf = mapM_ checkComment [ b | b@(F.BlComment {}) <- universeBi pf ]
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
annotateAllVariables :: F.ProgramFile UA -> UnitSolver (F.ProgramFile UA)
annotateAllVariables pf = do
  varUnitMap <- usVarUnitMap `fmap` get
  let annotateExp e@(F.ExpValue _ _ (F.ValVariable _))
        | Just info <- M.lookup (varName e) varUnitMap = setUnitInfo info e
      annotateExp e = e
  return $ transformBi annotateExp pf

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
  UnitParamAbs (name, position) -> UnitParamUse (name, position, callId)
  _                             -> info

-- | Gather all constraints from the AST, as well as from the varUnitMap
extractConstraints :: F.ProgramFile UA -> UnitSolver Constraints
extractConstraints pf = do
  varUnitMap <- usVarUnitMap `fmap` get
  return $ [ con | con@(ConEq {}) <- universeBi pf ] ++
           [ ConEq (UnitVar v) u | (v, u) <- M.toList varUnitMap ]

-- | Does the constraint contain any Parametric elements?
isParametric :: Constraint -> Bool
isParametric info = not (null [ () | UnitParamAbs _ <- universeBi info ])

--------------------------------------------------

-- | Decorate the AST with unit info.
propagateUnits :: F.ProgramFile UA -> UnitSolver (F.ProgramFile UA)
-- precondition: all variables have already been annotated
propagateUnits = transformBiM propagatePU <=< transformBiM propagateStatement <=< transformBiM propagateExp

propagateExp :: F.Expression UA -> UnitSolver (F.Expression UA)
propagateExp e = fmap uoLiterals ask >>= \ lm -> case e of
  F.ExpValue _ _ (F.ValVariable _)       -> return e -- all variables should already be annotated
  F.ExpValue _ _ (F.ValInteger _)        -> flip setUnitInfo e `fmap` genUnitLiteral
  F.ExpValue _ _ (F.ValReal _)           -> flip setUnitInfo e `fmap` genUnitLiteral
  F.ExpBinary _ _ F.Multiplication e1 e2 -> setF2 UnitMul (getUnitInfoMul lm e1) (getUnitInfoMul lm e2)
  F.ExpBinary _ _ F.Division e1 e2       -> setF2 UnitMul (getUnitInfoMul lm e1) (flip UnitPow (-1) `fmap` (getUnitInfoMul lm e2))
  F.ExpBinary _ _ F.Exponentiation e1 e2 -> setF2 UnitPow (getUnitInfo e1) (constantExpression e2)
  F.ExpBinary _ _ o e1 e2 | isOp AddOp o -> setF2C ConEq  (getUnitInfo e1) (getUnitInfo e2)
                          | isOp RelOp o -> setF2C ConEq  (getUnitInfo e1) (getUnitInfo e2)
  F.ExpFunctionCall {}                   -> propagateFunctionCall e
  _                                      -> whenDebug (tell ("propagateExp: unhandled: " ++ show e)) >> return e
  where
    setF2 f u1 u2  = return $ maybeSetUnitInfoF2 f u1 u2 e
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
  _                                            -> return stmt

propagatePU :: F.ProgramUnit UA -> UnitSolver (F.ProgramUnit UA)
propagatePU pu = modifyTemplateMap (M.insert name cons) >> return (setConstraint (ConConj cons) pu)
  where
    cons = [ con | con@(ConEq {}) <- universeBi pu, containsParametric name con ]
    name = puName pu

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

-- | Generate a unique identifier for each call-site.
genCallId :: UnitSolver Int
genCallId = do
  st <- get
  let callId = usLitNums st
  put $ st { usLitNums = callId + 1 }
  return callId

-- | Generate a unique identifier for each literal encountered in the code.
genUnitLiteral :: UnitSolver UnitInfo
genUnitLiteral = do
  s <- get
  let i = usLitNums s
  put $ s { usLitNums = i + 1 }
  return $ UnitLiteral i

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
maybeSetUnitInfo Nothing e = e
maybeSetUnitInfo (Just u) e = setUnitInfo u e

maybeSetUnitInfoF2 :: F.Annotated f => (a -> b -> UnitInfo) -> Maybe a -> Maybe b -> f UA -> f UA
maybeSetUnitInfoF2 f (Just u1) (Just u2) e = setUnitInfo (f u1 u2) e
maybeSetUnitInfoF2 _ _ _ e = e

maybeSetUnitConstraintF2 :: F.Annotated f => (a -> b -> Constraint) -> Maybe a -> Maybe b -> f UA -> f UA
maybeSetUnitConstraintF2 f (Just u1) (Just u2) e = setConstraint (f u1 u2) e
maybeSetUnitConstraintF2 _ _ _ e = e

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

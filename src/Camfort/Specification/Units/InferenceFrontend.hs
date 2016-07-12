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

  Units of measure extension to Fortran

TODO:
 * Deal with variable shadowing in "contained" functions.
 * Better errors with line number info

-}


{-# LANGUAGE ScopedTypeVariables, ImplicitParams, DoAndIfThenElse, ConstraintKinds,
             MultiParamTypeClasses #-}

module Camfort.Specification.Units.InferenceFrontend where

import Data.Data
import Data.Char
import Data.Function
import Data.List
import Data.Matrix
import Data.Maybe
import Data.Ratio
import Data.Generics.Uniplate.Operations
import Data.Label.Monadic hiding (modify)
import Control.Monad.State.Strict hiding (gets)
import Control.Monad
import Control.Monad.Writer.Strict
import GHC.Prim

import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Analysis as FA
import qualified Language.Fortran.Analysis.Types as FAT
import qualified Language.Fortran.Analysis.Renaming as FAR
import qualified Language.Fortran.Analysis.BBlocks as FAB
import qualified Language.Fortran.Analysis.DataFlow as FAD
import qualified Language.Fortran.Util.Position as FU
import qualified Language.Fortran.Util.SecondParameter as FUS

import Camfort.Analysis.CommentAnnotator
import Camfort.Analysis.Annotations hiding (Unitless)
import Camfort.Analysis.Types
import Camfort.Specification.Units.Debug
import Camfort.Specification.Units.Environment
import Camfort.Specification.Units.InferenceBackend
import Camfort.Specification.Units.Solve
import Camfort.Specification.Units.SyntaxConversion
import qualified Camfort.Specification.Units.Parser as Parser
import Camfort.Transformation.Syntax

import qualified Debug.Trace as D

type Params = (?criticals      :: Bool,
               ?solver         :: Solver,
               ?debug          :: Bool,
               ?assumeLiterals :: AssumeLiterals)

plumb f x = do { f x ; return x }

-- Helper for transforming the 'previous' annotation
onPrev :: (a -> a) -> FA.Analysis a -> FA.Analysis a
onPrev f ann = ann { FA.prevAnnotation = f (FA.prevAnnotation ann) }

-- Instances for embedding parsed specifications into the AST
instance ASTEmbeddable (FA.Analysis (UnitAnnotation A)) Parser.UnitStatement where
  annotateWithAST ann ast =
    "DOING ANNOTATE" `D.trace` onPrev (\ann -> ann { unitSpec = Just $ ast }) ann

-- Link annotaiton comments to declaration statements
instance Linkable (FA.Analysis (UnitAnnotation A)) where
  link ann (b@(F.BlStatement _ _ _ (F.StDeclaration {}))) =
      onPrev (\ann -> ann { unitBlock = Just b }) ann
  link ann b = ann

-- Core procedure for inferring units
doInferUnits ::
    Params => F.ProgramFile (FA.Analysis (UnitAnnotation A))
           -> State UnitEnv ()
doInferUnits pf = do
    (pf', parserReport) <- return $ runWriter (annotateComments Parser.unitParser pf)
    report <<++ (intercalate "\n" parserReport)
    descendBiM perProgramUnit pf'
    --
    ifDebug (report <<++ "Finished inferring prog units")
    ifDebug debugGaussian
    --
    inferInterproceduralUnits pf'
    return ()

-- Check units per program unit, with special handling of functions and subroutines
-- which need adding to the set of constraints
perProgramUnit ::
       (?criticals :: Bool, ?solver :: Solver, ?debug :: Bool,
        ?assumeLiterals :: AssumeLiterals)
    => F.ProgramUnit (FA.Analysis (UnitAnnotation A))
    -> State UnitEnv (F.ProgramUnit (FA.Analysis (UnitAnnotation A)))
perProgramUnit p@(F.PUMain _ _ _ body subprogs) = do
    resetTemps
    descendBiM perBlock body
    descendBiM perProgramUnit subprogs
    return p

perProgramUnit p@(F.PUModule _ _ _ body subprogs) = do
    resetTemps
    puname =: (Just $ FA.puName p)
    descendBiM perBlock p
    descendBiM perProgramUnit subprogs
    return p

perProgramUnit p@(F.PUSubroutine ann span rec name args body subprogs) = do
    resetTemps
    addProcedure rec name Nothing args body subprogs
    return p

perProgramUnit p@(F.PUFunction ann span retTy rec name args result
                                                     body subprogs) = do
    resetTemps
    addProcedure rec name (Just name) args body subprogs
    return p

perProgramUnit p = do
    resetTemps
    descendBiM perBlock p
    return p

addProcedure :: Params
    => Bool -- Recursive or not
    -> F.Name
    -> Maybe F.Name -- Maybe return name
    -> (Maybe (F.AList F.Expression (FA.Analysis (UnitAnnotation A)))) -- Arguments
    -> [F.Block (FA.Analysis (UnitAnnotation A))] -- Body
    -> (Maybe [F.ProgramUnit (FA.Analysis (UnitAnnotation A))])
    -> State UnitEnv ()
addProcedure rec name rname args body subprogs = do
    descendBiM perBlock body
    descendBiM perProgramUnit subprogs
    uenv <- gets varColEnv
    resultVar <- case rname of
                   Just rname ->
                     case (lookupWithoutSrcSpan rname uenv) of
                        Just (uvar, _) -> return $ Just uvar
                        Nothing        -> do m <- addCol Variable
                                             return $ (Just (VarCol m))
                   Nothing -> return Nothing

    let argVars = fromMaybe [] (fmap (map (lookupUnitByName uenv) . F.aStrip) args)
    procedureEnv << (name, (resultVar, argVars))
    if rec
      then do descendBiM perBlock body
              return ()
      else return ()
    -- Intermediate solve for procedures (subroutines & functions)
    ifDebug (report <<++ "Pre doing row reduce")
    consistent <- solveSystemM ""
    success =: consistent

    linearSystem =. reduceRows 1
    ifDebug (report <<++ "Post doing reduce")
    ifDebug (debugGaussian)
    return ()
  where
    lookupUnitByName uenv ve@(F.ExpValue _ _ (F.ValVariable _)) =
        maybe (VarCol 1) fst $ lookupWithoutSrcSpan v uenv
          where v = FA.varName ve

-- STUB!
updateUnitEnv :: FA.Analysis (UnitAnnotation A) -> State UnitEnv ()
updateUnitEnv _ = return ()

{- OLD RELEVANT CODE

inferDecl proc decl@(Decl a s d typ) =
      do let BaseType _ _ attrs _ _ = arrayElementType typ
         units <- sequence $ concatMap extractUnit attrs
         mapM_ (\(e1, e2, multiplier) -> processVar units proc (e1, e2) typ) d
         return $ decl

inferDecl proc x@(MeasureUnitDef a s d) =
   do mapM learnDerivedUnit d
      return x
     where
        learnDerivedUnit (name, spec) =
          do denv <- gets derivedUnitEnv
             when (isJust $ lookup name denv) $ error "Redeclared unit of measure"
             unit <- convertUnit spec
             denv <- gets derivedUnitEnv
             when (isJust $ lookup name denv) $ error "Recursive unit-of-measure definition"
             derivedUnitEnv << (name, unit)
-}

perBlock :: (?solver :: Solver, ?criticals :: Bool, ?debug :: Bool,
                  ?assumeLiterals :: AssumeLiterals)
    => F.Block (FA.Analysis (UnitAnnotation A)) -> State UnitEnv (F.Block (FA.Analysis (UnitAnnotation A)))
perBlock b@(F.BlComment ann span _) = do
    updateUnitEnv ann
    case (unitSpec (FA.prevAnnotation ann), unitBlock (FA.prevAnnotation ann)) of
      (Just (Parser.UnitAssignment var unitsAST), Just block) -> do
         let units = toUnitInfo unitsAST
         unitsConverted <- convertUnit units
         case block of
              bl@(F.BlStatement ann span _ (F.StDeclaration _ _ _ _ decls)) ->
                mapM_ (processVar var [unitsConverted]) (getNamesAndInits decls)
              _ -> return ()
      _ -> return ()
    return b

  where
    getNamesAndInits x =
        [(FA.varName e, i, s) | (F.DeclVariable _ _ e@(F.ExpValue _ s (F.ValVariable _)) _ i) <-
                    (universeBi (F.aStrip x) :: [F.Declarator (FA.Analysis (UnitAnnotation A))])]
     ++ [(FA.varName e, i, s) | (F.DeclArray _ _ e@(F.ExpValue _ s (F.ValVariable _)) _ _ i) <-
                    (universeBi (F.aStrip x) :: [F.Declarator (FA.Analysis (UnitAnnotation A))])]
     -- TODO: generate constraints for indices
    dimDeclarators x = concat
         [F.aStrip dims | (F.DeclArray _ _ _ dims _ _) <-
                    (universeBi (F.aStrip x) :: [F.Declarator (FA.Analysis (UnitAnnotation A))])]

    processVar (Just dvar) units (v, initExpr, span) | dvar == v = do
      system <- gets linearSystem
      let m = ncols (fst system) + 1
      unitVarCats <<++ Variable -- TODO: check how much we need this: (unitVarCat v proc)
      extendConstraints units
      varColEnv << (VarBinder (v, span), (VarCol m, []))
      uv <- gets varColEnv
      -- If the declaration has a null expression, do not create a unifying variable
      case initExpr of
          Nothing -> return ()
          Just e  -> do
            uv <- perExpr e
            mustEqual False (VarCol m) uv
            return ()
    processVar _ units (v, initExpr, span) | otherwise = return ()

{- TODO: investigate
    unitVarCat :: Variable -> Maybe ProcedureNames -> UnitVarCategory
    unitVarCat v proc | Just (n, r, args) <- proc, v `elem` args = Argument
                  | otherwise                                = Variable
-}

perBlock b@(F.BlStatement _ _ _ s) = do
    perStatement s
    return b

perBlock b = do
    mapM_ perDoSpecification (universeBi b)
    mapM_ perExpr (universeBi b)
    descendBiM (plumb perBlock) b
    return b

perDoSpecification ::
    Params => F.DoSpecification (FA.Analysis (UnitAnnotation A)) -> State UnitEnv ()
perDoSpecification (F.DoSpecification _ _
                      st@(F.StExpressionAssign _ _ ei e0) en step) = do
   uiv <- perExpr ei
   e0v <- perExpr e0
   env <- perExpr en
   mustEqual True uiv e0v
   mustEqual True e0v env
   case step of
     Nothing    -> return ()
     Just stepE -> do stepv <- perExpr stepE
                      mustEqual True env stepv
                      return ()

-- TODO: see if we need to insert anymore statement-specific constraints here
perStatement :: (?solver :: Solver, ?criticals :: Bool, ?debug :: Bool,
                  ?assumeLiterals :: AssumeLiterals)
    => F.Statement (FA.Analysis (UnitAnnotation A)) -> State UnitEnv ()
perStatement (F.StExpressionAssign _ _ e1 e2) = do
    uv1 <- perExpr e1
    uv2 <- perExpr e2
    mustEqual False uv1 uv2
    return ()

perStatement (F.StPointerAssign _ _ e1 e2) = do
    uv1 <- perExpr e1
    uv2 <- perExpr e2
    mustEqual False uv1 uv2
    return ()

perStatement (F.StCall _ _ e@(F.ExpValue _ _ (F.ValVariable _)) args) = do
    uvs <- fromMaybe (return []) (fmap (mapM perArgument . F.aStrip) args)
    calls << (FA.varName e, (Nothing, uvs))

perStatement s = do
    mapM_ perDoSpecification (universeBi s)
    descendBiM (plumb perExpr) s
    return ()


-- ***************************************
--
-- *  Unit inference (main, over all AST)
--
-- ***************************************

extendConstraints :: [UnitConstant] -> State UnitEnv ()
extendConstraints units =
        do (matrix, vector) <- gets linearSystem
           let n = nrows matrix + 1
               m = ncols matrix + 1
           linearSystem =: case units of
                             [] -> do (extendTo 0 0 m matrix, vector)
                             _ -> (setElem 1 (n, m) $ extendTo 0 n m matrix, vector ++ [last units])
           tmpColsAdded << m
           tmpRowsAdded << n
           return ()

inferInterproceduralUnits ::
    Params => F.ProgramFile (FA.Analysis (UnitAnnotation A)) -> State UnitEnv ()
inferInterproceduralUnits x =
  do --reorderColumns
     if ?criticals then reorderVarCols else return ()
     consistent <- solveSystemM "inconsistent"
     if consistent then
         do system <- gets linearSystem
            let dontAssumeLiterals = case ?assumeLiterals of
                                       Poly     -> True
                                       Unitless -> False
                                       Mixed    -> False
            inferInterproceduralUnits' x dontAssumeLiterals system -- edited
            return ()
     else
         return ()

inferInterproceduralUnits' ::
    Params => F.ProgramFile (FA.Analysis (UnitAnnotation A)) -> Bool -> LinearSystem
           -> State UnitEnv (F.ProgramFile (FA.Analysis (UnitAnnotation A)))
inferInterproceduralUnits' x haveAssumedLiterals system1 =
  do addInterproceduralConstraints x
     consistent <- solveSystemM "inconsistent"
     if not consistent then
          do  linearSystem =: system1
              return x
      else do
        system2 <- gets linearSystem
        if system1 == system2
          then if ?criticals then nextStep else checkUnderdeterminedM >> nextStep
          else inferInterproceduralUnits' x haveAssumedLiterals system2
  where nextStep | haveAssumedLiterals = return x
                 | otherwise           = do consistent <- assumeLiteralUnits
                                            if not consistent
                                             then return x
                                             else do system3 <- gets linearSystem
                                                     inferInterproceduralUnits' x True system3


class UpdateColInfo t where
    updateColInfo :: Col -> Col -> t -> t

instance UpdateColInfo VarCol where
    updateColInfo x n (VarCol y) | y == x = VarCol n
                                       | y == n = VarCol x
                                       | otherwise = VarCol y

instance UpdateColInfo VarColEnv where
    updateColInfo _ _ [] = []
    updateColInfo x n ((v, (uv, uvs)):ys) = (v, (updateColInfo x n uv, map (updateColInfo x n) uvs)) : (updateColInfo x n ys)

instance UpdateColInfo Procedure where
    updateColInfo x n (Nothing, ps) = (Nothing, map (updateColInfo x n) ps)
    updateColInfo x n (Just p, ps) = (Just $ updateColInfo x n p, map (updateColInfo x n) ps)

instance UpdateColInfo ProcedureEnv where
    updateColInfo x n = map (\(s, p) -> (s, updateColInfo x n p))

instance UpdateColInfo (Int, a) where
    updateColInfo x n (y, s) | y == x = (n, s)
                             | y == n = (x, s)
                             | otherwise = (y, s)

instance UpdateColInfo Int where
    updateColInfo x n y | y == x = x
                        | y == n = n
                        | otherwise = y

swapUnitVarCats x n xs = swapUnitVarCats' x n xs xs 1
swapUnitVarCats' x n [] ys c = []
swapUnitVarCats' x n (z:zs) ys c | c == x = (ys !! (n - 1)) : (swapUnitVarCats' x n zs ys (c + 1))
                                 | c == n = (ys !! (x - 1)) : (swapUnitVarCats' x n zs ys (c + 1))
                                 | otherwise = z : (swapUnitVarCats' x n zs ys (c + 1))

swapCols :: Int -> Int -> State UnitEnv ()
swapCols x n = do --report <<++ ("Pre swap - " ++ (show x) ++ " <-> " ++ (show n))
                  --debugGaussian
                  varColEnv   =. updateColInfo x n
                  procedureEnv =. updateColInfo x n
                  calls        =. updateColInfo x n
                  unitVarCats  =. swapUnitVarCats x n
                  linearSystem =. (\(m, v) -> (switchCols x n m, v))
                  debugInfo    =. map (updateColInfo x n)
                  tmpColsAdded =. map (updateColInfo x n)
                  --report <<++ "Post swap"
                  --debugGaussian
                  return ()


{-| reorderVarCols puts any variable columns to the end of the Gaussian matrix (along with the associated information) -}
reorderVarCols :: State UnitEnv ()
reorderVarCols = do ucats <- gets unitVarCats
                    (matrix, _) <- gets linearSystem
                    reorderVarCols' (ncols matrix) 1
                   where   correctEnd :: Int -> State UnitEnv Int
                           correctEnd 0   = return 0
                           correctEnd end = do ucats <- gets unitVarCats
                                               case (ucats !! (end - 1)) of
                                                  Variable -> correctEnd (end - 1)
                                                  _        -> return $ end

                           reorderVarCols' :: Int -> Int -> State UnitEnv ()
                           reorderVarCols' end c | c >= end = return ()
                           reorderVarCols' end c = do ucats <- gets unitVarCats
                                                      case (ucats !! (c - 1)) of
                                                        Variable -> do end' <- correctEnd end
                                                                       swapCols end' c
                                                                       reorderVarCols' (end' - 1) (c+1)
                                                        _        -> reorderVarCols' end (c+1)

assumeLiteralUnits :: (?solver :: Solver, ?debug :: Bool) => State UnitEnv Bool
assumeLiteralUnits =
  do system@(matrix, vector) <- gets linearSystem
     mapM_ assumeLiteralUnits' [1 .. ncols matrix]
     consistent <- solveSystemM "underdetermined"
     when (not consistent) $ linearSystem =: system
     return consistent

assumeLiteralUnits' m =
      do (matrix, vector) <- gets linearSystem
         ucats <- gets unitVarCats
         let n = find (\n -> matrix ! (n, m) /= 0) [1 .. nrows matrix]
             m' = n >>= (\n -> find (\m -> matrix ! (n, m) /= 0) [1 .. ncols matrix])
             nonLiteral n m = matrix ! (n, m) /= 0 && ucats !! (m - 1) /= (Literal True)
             m's = n >>= (\n -> find (nonLiteral n) [1 .. ncols matrix])
         when (ucats !! (m - 1) == (Literal True) && (m' /= Just m || isJust m's)) $ do
           n' <- addRow
           modify $ liftUnitEnv $ setElem 1 (n', m)

addInterproceduralConstraints ::
    (?debug :: Bool) => F.ProgramFile (FA.Analysis (UnitAnnotation A)) -> State UnitEnv ()
addInterproceduralConstraints x =
  do
    cs <- gets calls
    mapM_ addCall cs
  where
    addCall (name, (result, args)) =
      do penv <- gets procedureEnv
         case lookup name penv of
           Just (r, as) ->
                             let (r1, r2) = decodeResult result r
                             in handleArgs (args ++ r1) (as ++ r2)
           Nothing      -> return ()

    handleArgs actualVars dummyVars =
      do order <- gets reorderedCols
         let actual = map (\(VarCol uv) -> uv) actualVars
             dummy = map (\(VarCol uv) -> uv) dummyVars
         mapM_ (handleArg $ zip dummy actual) dummy

    -- experimentation but now deprecated.
{-
    handleArgNew dummyToActual dummy =
        do grid0 <- debugGaussian'
           mapM (\(l, r) -> do n <- addRow
                               modify $ liftUnitEnv $ setElem 1 (n, l)
                               modify $ liftUnitEnv $ setElem (-1) (n, r)
                ) dummyToActual
           grid1 <- debugGaussian'
           if (grid0 == grid1) then
               return ()
           else
             do report <<++ "HANDLED AND DIFFERENT!"
                report <<++ ("\n" ++ grid0)
                report <<++ ("\n" ++ grid1)
                return ()-}

    -- TODO: this can be optimised
    handleArg dummyToActual dummy =
      do (matrix, vector) <- gets linearSystem
         --grid0 <- debugGaussian'
         ifDebug (debugGaussian)

         ifDebug (report <<++ ("hArg - " ++ show dummyToActual ++ "-" ++ show dummy))

         let -- find the first row with a non-zero column for the variable
             n = maybe 1 id $ find (\n -> matrix ! (n, dummy) /= 0) [1 .. nrows matrix]

             -- find the first non-zero column on the row just selected
             Just m = find (\m -> matrix ! (n, m) /= 0) [1 .. ncols matrix]

         ifDebug (report <<++ ("n = " ++ show n ++ ", m = " ++ show m))

         if (m == dummy) then
           do  let -- Get list of columns with non-zero coefficients to the right of the focus
                   ms = filter (\m -> matrix ! (n, m) /= 0) [m .. ncols matrix]

                   -- Get the list of columns to which the non-zero coeffecients are paired by 'dummyToActual' relation.
                   m's = mapMaybe (flip lookup dummyToActual) ms
                   pairs = --if (length m's == 1) then -- i.e. there is not a direct relationship between variable and return
                           --    zip ms (repeat (head m's))
                           --else
                               (zip ms m's)

               ifDebug(report <<++ ("ms = " ++ show ms ++ ", m's' = " ++ show m's ++ ", their zip = " ++ show pairs ++ " dA = " ++ show dummyToActual))

               if (True) -- length m's == length ms)
                 then do { newRow <- addRow' $ vector !! (n - 1);
--                           mapM_ (handleArgPair matrix n newRow) pairs ; }
                           mapM_ (handleArgPair matrix n newRow) dummyToActual ; }
                 else return ()
         else
             return ()

    -- Copy the row
    handleArgPair matrix n newRow (m, m') = do modify $ liftUnitEnv $ setElem (matrix ! (n, m)) (newRow, m')

    decodeResult (Just r1) (Just r2) = ([r1], [r2])
    decodeResult Nothing Nothing = ([], [])
    decodeResult (Just _) Nothing = error "Subroutine used as a function!"
    decodeResult Nothing (Just _) = error "Function used as a subroutine!"

data BinOpKind = AddOp | MulOp | DivOp | PowerOp | LogicOp | RelOp
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

(<**>) :: Maybe a -> Maybe a -> Maybe a
Nothing <**> x = x
(Just x) <**> y = (Just x)


{- OLD
    uenv <- gets varColEnv
    case lookupWithoutSrcSpan v uenv of
    let (VarName _ v, args) = head names

    case lookupWithoutSrcSpan v uenv of
       -- array variable?
       Just (uv, uvs@(_:_)) -> inferArgUnits' uvs >> return uv
       -- function call?
       Nothing | not (null args) -> do case (lookup (map toUpper v) intrinsicsDict) of
                                          Just fun -> fun v
                                          Nothing  -> return () -- error $ "I don't know the intrinsic " ++ v -- return ()
                                       uv@(VarCol uvn) <- anyUnits Temporary
                                       debugInfo << (uvn, (srcSpan ve, pprint ve))
                                       uvs <- inferArgUnits
                                       let uvs' = justArgUnits args uvs
                                       calls << (v, (Just uv, uvs'))
                                       return uv
       -- scalar variable or external function call?
       Just (uv, []) -> inferArgUnits >> return uv
       -- default specifier
       _ | v == "*" -> inferLiteral ve
       -- just bad code
       x -> case lookupCaseInsensitive v penv of
              Just (Just uv, argUnits) ->
                   if (null args) then inferArgUnits' argUnits >> return uv
                   else  do uv <- anyUnits Temporary
                            uvs <- inferArgUnits
                            let uvs' = justArgUnits args uvs
                            calls << (v, (Just uv, uvs'))
                            return uv

              Nothing -> error $ "\n" ++ (showSrcFile . srcSpan $ ve) ++ ": undefined variable " ++ v ++ " at " ++ (showSrcSpan . srcSpan $ ve)
  where inferArgUnits = sequence [mapM perExpr exprs | (_, exprs) <- names]
        inferArgUnits' uvs = sequence [(perExpr expr) >>= (\uv' -> mustEqual True uv' uv) | ((_, exprs), uv) <- zip names uvs, expr <- exprs, not (nullF.Expression [expr])]

        justArgUnits [NullF.Expression _ _] _ = []  -- zero-argument function call
        justArgUnits _ uvs = head uvs
        -}

-- TODO, create unit vars for every index and make sure consistent
perIndex :: Params => F.Name -> F.Index (FA.Analysis (UnitAnnotation A)) -> State UnitEnv ()
perIndex v (F.IxSingle _ _ _ e) = return ()
 {-
  uenv <- gets varColEnv
  arrV <- case lookpuWithoutSrcSpan v env
           Nothing -> do
              uv@(ValCol uvn) <- anyUnits Temporary
              return uv
           Just (uv, uvs) ->
-}

perExpr :: Params => F.Expression (FA.Analysis (UnitAnnotation A)) -> State UnitEnv VarCol
perExpr e@(F.ExpValue _ _ (F.ValVariable n)) = do
    let v = FA.varName e
    uenv <- gets varColEnv
    case lookupWithoutSrcSpan v uenv of
      Nothing -> do
          uv@(VarCol uvn) <- anyUnits Temporary
          return uv
      -- TODO, check what it means when uvs is defined
      Just (uv, uvs) -> return uv

perExpr e@(F.ExpValue _ span v) = perLiteral v
  where
    perLiteral :: Params => F.Value (FA.Analysis (UnitAnnotation A)) -> State UnitEnv VarCol
    perLiteral val = do
      uv@(VarCol uvn) <- anyUnits (Literal (?assumeLiterals /= Mixed))
      debugInfo << (uvn, (span, show val))
      return uv

perExpr e@(F.ExpBinary _ _ op e1 e2) = do
    uv1 <- perExpr e1
    uv2 <- perExpr e2
    (VarCol n) <- case binOpKind op of
                    AddOp   -> mustEqual True uv1 uv2
                    MulOp   -> mustAddUp uv1 uv2 1 1
                    DivOp   -> mustAddUp uv1 uv2 1 (-1)
                    PowerOp -> powerUnits uv1 e2
                    LogicOp -> mustEqual True uv1 uv2
                    RelOp   -> do mustEqual True uv1 uv2
                                  return $ VarCol 1
    debugInfo << (n, (FU.getSpan e, pprint e))
    return (VarCol n)
  where
    pprint e = "" -- TODO pprint

perExpr (F.ExpUnary _ _ _ e) = perExpr e
perExpr (F.ExpSubscript _ _ e alist) = do
    descendBiM (plumb (perIndex (FA.varName e))) alist
    perExpr e

perExpr f@(F.ExpFunctionCall _ _ e@(F.ExpValue _ _ (F.ValVariable _)) args) = do
    uv <- anyUnits Temporary
    argsU <- fromMaybe (return []) (fmap (mapM perArgument . F.aStrip) args)
    calls << (FA.varName e, (Just uv, argsU))
    return uv

perExpr f@(F.ExpDataRef _ _ e1 e2) = do
    perExpr e2
    perExpr e1
perExpr f@(F.ExpImpliedDo _ _ exprs spec) = do
    perDoSpecification spec
    uv <- anyUnits Temporary
    exprsU <- mapM perExpr (F.aStrip exprs)
    mapM_ (mustEqual True uv) exprsU
    return uv
perExpr f@(F.ExpInitialisation _ _ exprs) = do
    uv <- anyUnits Temporary
    exprsU <- mapM perExpr (F.aStrip exprs)
    mapM_ (mustEqual True uv) exprsU
    return uv
perExpr f@(F.ExpReturnSpec _ _ e) = do
    perExpr e

perArgument :: Params =>
    F.Argument (FA.Analysis (UnitAnnotation A)) -> State UnitEnv VarCol
perArgument (F.Argument _ _ _ expr) = perExpr expr

handleExpression :: Params
    => F.Expression (FA.Analysis (UnitAnnotation A))
    -> State UnitEnv (F.Expression (FA.Analysis (UnitAnnotation A)))
handleExpression x = do
    perExpr x
    return x

-- TODO: error handling in powerUnits
powerUnits :: Params
           => VarCol -> F.Expression (FA.Analysis (UnitAnnotation A)) -> State UnitEnv VarCol

powerUnits (VarCol uv) (F.ExpValue _ _ (F.ValInteger powerString)) =
  case fmap (fromInteger . fst) $ listToMaybe $ reads powerString of
    Just power -> do
      m <- addCol Temporary
      n <- addRow
      modify $ liftUnitEnv $ incrElem (-1) (n, m) . incrElem power (n, uv)
      return $ VarCol m
    Nothing -> mustEqual False (VarCol uv) (VarCol 1)
powerUnits uv e =
  do mustEqual False uv (VarCol 1)
     uv <- perExpr e
     mustEqual False uv (VarCol 1)

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

{- This module collects together stubs that connect analysis/transformations
   with the input -> output procedures -}

{-# LANGUAGE DoAndIfThenElse #-}
{-# LANGUAGE DeriveDataTypeable #-}
{-# LANGUAGE TypeSynonymInstances #-}
{-# LANGUAGE FlexibleInstances #-}

module Camfort.Functionality where

import System.Console.GetOpt
import System.Directory
import System.Environment
import System.IO

import Data.Monoid
import Data.Generics.Uniplate.Operations

import Camfort.Analysis.Annotations
import Camfort.Analysis.Types
import Camfort.Analysis.Simple
import Camfort.Analysis.Syntax

import Camfort.Transformation.DeadCode
import Camfort.Transformation.CommonBlockElim
import Camfort.Transformation.CommonBlockElimToCalls
import Camfort.Transformation.EquivalenceElim
import Camfort.Transformation.DerivedTypeIntro

import qualified Camfort.Specification.Units as LU
import Camfort.Specification.Units.Environment
import Camfort.Specification.Units.Monad

import Camfort.Helpers
import Camfort.Output
import Camfort.Input

import Data.Data
import Data.List (foldl', nub, (\\), elemIndices, intersperse, intercalate)

import qualified Data.ByteString.Char8 as B
import Data.Text.Encoding (encodeUtf8, decodeUtf8With)
import Data.Text.Encoding.Error (replace)

-- FORPAR related imports
import qualified Language.Fortran.Parser.Any as FP
import qualified Language.Fortran.AST as F
import Language.Fortran.Analysis.Renaming
  (renameAndStrip, analyseRenames, unrename, NameMap)
import Language.Fortran.Analysis(initAnalysis)
import qualified Camfort.Specification.Stencils as Stencils

import qualified Debug.Trace as D

-- CamFort optional flags
data Flag = Version
         | Input String
         | Output String
         | Excludes String
         | Literals LiteralsOpt
         | StencilInferMode Stencils.InferMode
         | Debug deriving (Data, Show)

type Options = [Flag]

-- Extract excluces information from options
instance Default String where
    defaultValue = ""
getExcludes :: Options -> String
getExcludes xs = getOption xs

-- * Wrappers on all of the features
typeStructuring inSrc excludes outSrc _ = do
    putStrLn $ "Introducing derived data types in '" ++ inSrc ++ "'"
    report <- doRefactor typeStruct inSrc excludes outSrc
    putStrLn report

ast d excludes f _ = do
    xs <- readForparseSrcDir (d ++ "/" ++ f) excludes
    putStrLn $ show (map (\(_, _, p) -> p) xs)

countVarDecls inSrc excludes _ _ = do
    putStrLn $ "Counting variable declarations in '" ++ inSrc ++ "'"
    doAnalysisSummaryForpar countVariableDeclarations inSrc excludes Nothing

dead inSrc excludes outSrc _ = do
    putStrLn $ "Eliminating dead code in '" ++ inSrc ++ "'"
    report <- doRefactorForpar ((mapM (deadCode False))) inSrc excludes outSrc
    putStrLn report

commonToArgs inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring common blocks in '" ++ inSrc ++ "'"
    report <- doRefactor (commonElimToCalls inSrc) inSrc excludes outSrc
    putStrLn report

common inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring common blocks in '" ++ inSrc ++ "'"
    report <- doRefactor (commonElimToModules inSrc) inSrc excludes outSrc
    putStrLn report

equivalences inSrc excludes outSrc _ = do
    putStrLn $ "Refactoring equivalences blocks in '" ++ inSrc ++ "'"
    report <- doRefactor (mapM refactorEquivalences) inSrc excludes outSrc
    putStrLn report

{- Units feature -}
optsToUnitOpts :: [Flag] -> UnitOpts
optsToUnitOpts = foldl' (\ o f -> case f of Literals m -> o { uoLiterals = m }
                                            Debug -> o { uoDebug = True }
                                            _     -> o) unitOpts0

unitsCheck inSrc excludes outSrc opt = do
    putStrLn $ "Checking units for '" ++ inSrc ++ "'"
    doAnalysisReportForpar (concatMap (LU.checkUnits (optsToUnitOpts opt))) putStrLn inSrc excludes

unitsInfer inSrc excludes outSrc opt = do
    putStrLn $ "Inferring units for '" ++ inSrc ++ "'"
    doAnalysisReportForpar (concatMap (LU.inferUnits (optsToUnitOpts opt))) putStrLn inSrc excludes

unitsSynth inSrc excludes outSrc opt = do
    putStrLn $ "Synthesising units for '" ++ inSrc ++ "'"
    doRefactorForpar (mapM (LU.synthesiseUnits (optsToUnitOpts opt))) inSrc excludes outSrc

unitsCriticals inSrc excludes outSrc opt = do
    putStrLn $ "Suggesting variables to annotate with unit specifications in '"
             ++ inSrc ++ "'"
    doAnalysisReportForpar (mapM (LU.inferCriticalVariables (optsToUnitOpts opt))) (putStrLn . fst) inSrc excludes

{- Stencils feature -}
stencilsCheck inSrc excludes _ _ = do
   putStrLn $ "Checking stencil specs for '" ++ inSrc ++ "'"
   doAnalysisSummaryForpar (\f p -> (Stencils.check f p, p)) inSrc excludes Nothing

stencilsInfer inSrc excludes outSrc opt = do
   putStrLn $ "Infering stencil specs for '" ++ inSrc ++ "'"
   doAnalysisSummaryForpar (Stencils.infer (getOption opt)) inSrc excludes (Just outSrc)

stencilsSynth inSrc excludes outSrc opt = do
   putStrLn $ "Synthesising stencil specs for '" ++ inSrc ++ "'"
   doRefactorForpar (Stencils.synth (getOption opt)) inSrc excludes outSrc

stencilsVarFlowCycles inSrc excludes _ _ = do
   putStrLn $ "Inferring var flow cycles for '" ++ inSrc ++ "'"
   let flowAnalysis = intercalate ", " . map show . Stencils.findVarFlowCycles
   doAnalysisSummaryForpar (\_ p -> (flowAnalysis p , p)) inSrc excludes Nothing

--------------------------------------------------
-- Forpar wrappers

doRefactorForpar :: ([(Filename, F.ProgramFile A)]
                 -> (String, [(Filename, F.ProgramFile Annotation)]))
                 -> FileOrDir -> [Filename] -> FileOrDir -> IO ()
doRefactorForpar rFun inSrc excludes outSrc = do
    if excludes /= [] && excludes /= [""]
    then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
           ++ " from " ++ inSrc ++ "/"
    else return ()
    ps <- readForparseSrcDir inSrc excludes
    let (report, ps') = rFun (map (\(f, inp, ast) -> (f, ast)) ps)
    --let outFiles = filter (\f -> not ((take (length $ d ++ "out") f) == (d ++ "out"))) (map fst ps')
    --let outFiles = map fst ps'
    putStrLn report
    let outputs = mkOutputFileForpar ps ps'
    outputFiles inSrc outSrc outputs
  where snd3 (a, b, c) = b

mkOutputFileForpar :: [(Filename, SourceText, a)]
                   -> [(Filename, F.ProgramFile Annotation)]
                   -> [(Filename, SourceText, F.ProgramFile Annotation)]
mkOutputFileForpar ps ps' = zip3 (map fst ps') (map snd3 ps) (map snd ps')
  where
    snd3 (a, b, c) = b


{-| Performs an analysis which reports to the user,
     but does not output any files -}
doAnalysisReportForpar :: ([(Filename, F.ProgramFile A)] -> r)
                       -> (r -> IO out)
                       -> FileOrDir -> [Filename] -> IO out
doAnalysisReportForpar rFun sFun inSrc excludes = do
  if excludes /= [] && excludes /= [""]
      then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
                    ++ " from " ++ inSrc ++ "/"
      else return ()
  ps <- readForparseSrcDir inSrc excludes
----
  let report = rFun (map (\(f, inp, ast) -> (f, ast)) ps)
  sFun report
----

-- * Source directory and file handling
readForparseSrcDir :: FileOrDir -> [Filename]
                   -> IO [(Filename, SourceText, F.ProgramFile A)]
readForparseSrcDir inp excludes = do
    isdir <- isDirectory inp
    files <- if isdir
             then do files <- rGetDirContents inp
                     -- Compute alternate list of excludes with the
                     -- the directory appended
                     let excludes' = excludes ++ map (\x -> inp ++ "/" ++ x) excludes
                     return $ (map (\y -> inp ++ "/" ++ y) files) \\ excludes'
             else return [inp]
    mapM readForparseSrcFile files
----

{-| Read a specific file, and parse it -}
readForparseSrcFile :: Filename -> IO (Filename, SourceText, F.ProgramFile A)
readForparseSrcFile f = do
    inp <- flexReadFile f
    let ast = FP.fortranParser inp f
    return $ (f, inp, fmap (const unitAnnotation) ast)
----

doAnalysisSummaryForpar :: (Monoid s, Show' s) => (Filename -> F.ProgramFile A -> (s, F.ProgramFile A))
                        -> FileOrDir -> [Filename] -> Maybe FileOrDir -> IO ()
doAnalysisSummaryForpar aFun inSrc excludes outSrc = do
  if excludes /= [] && excludes /= [""]
    then putStrLn $ "Excluding " ++ (concat $ intersperse "," excludes)
                                 ++ " from " ++ inSrc ++ "/"
    else return ()
  ps <- readForparseSrcDir inSrc excludes
  let (out, ps') = callAndSummarise aFun ps
  putStrLn . show' $ out

callAndSummarise aFun ps = do
  foldl' (\(n, pss) (f, _, ps) -> let (n', ps') = aFun f ps
                                  in (n `mappend` n', ps' : pss)) (mempty, []) ps

----

-- | Read file using ByteString library and deal with any weird characters.
flexReadFile :: String -> IO B.ByteString
flexReadFile = fmap (encodeUtf8 . decodeUtf8With (replace ' ')) . B.readFile

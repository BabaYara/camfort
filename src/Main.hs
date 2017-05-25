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

{-# LANGUAGE DoAndIfThenElse #-}

module Main where

import System.Console.GetOpt
import System.Environment

import Camfort.Helpers
import Camfort.Functionality

import Data.Text (pack, unpack, split)

{-| The entry point to CamFort. Displays user information, and
    handlers which functionality is being requested -}
main = do
  args <- getArgs
  putStrLn ""
  if length args >= 2 then

    let (func : (inp : _)) = args
    in case lookup func functionality of
         Just (fun, _) -> do
           (opts, _) <- compilerOpts args

           (numReqArgs, outp) <-
               if RefactorInPlace `elem` opts
                -- Does not check to see if an output directory
                -- is also specified since flags come last and therefore
                -- override any specification of an output directory
                -- (which would come earlier).
               then return (2, inp)
               else
                 if func `elem` outputNotRequired
                 then if length args >= 3 && (head (args !! 2) == '-')
                      then return (2, "")
                      else -- case where an unnecessary output is specified
                           return (3, "")
                 else if length args >= 3
                      then return (3, args !! 2)
                      else fail $ usage ++ "This mode requires an output \
                                           \file/directory to be specified."

           let excluded_files = map unpack . split (==',') . pack . getExcludes
           fun inp (excluded_files opts) outp opts
         Nothing -> putStrLn fullUsageInfo

  else do
    putStrLn introMsg
    if length args == 1
     then putStrLn $ usage ++ "Please specify an input file/directory"
     else putStrLn fullUsageInfo

-- * Options for CamFort  and information on the different modes

fullUsageInfo = usageInfo (usage ++ menu ++ "\nOptions:") options

options :: [OptDescr Flag]
options =
     [ Option ['v','?'] ["version"] (NoArg Version)
         "show version number"
     , Option [] ["inplace"] (NoArg RefactorInPlace)
         "refactor in place (replaces input files)"
     , Option ['e']     ["exclude"] (ReqArg Excludes "FILES")
         "files to exclude (comma separated list, no spaces)"
     , Option ['l']     ["units-literals"] (ReqArg (Literals . read) "ID")
         "units-of-measure literals mode. ID = Unitless, Poly, or Mixed"
     , Option ['m']     ["stencil-inference-mode"]
                (ReqArg (StencilInferMode . read . (++ "Mode")) "ID")
                "stencil specification inference mode. ID = Do, Assign, or Both"
     , Option ['I']     ["include-dir"]
                (ReqArg IncludeDir "DIR")
                "directory to search for precompiled files"
     , Option []        ["debug"] (NoArg Debug)
         "enable debug mode"
     , Option []        ["doxygen"] (NoArg Doxygen)
         "synthesise annotations compatible with Doxygen"
     , Option []        ["ford"] (NoArg Ford)
         "synthesise annotations compatible with Ford"
     ]

compilerOpts :: [String] -> IO ([Flag], [String])
compilerOpts argv =
  case getOpt Permute options argv of
    (o,n,[]  ) -> return (o,n)
    (_,_,errs) -> ioError (userError (concat errs ++ usageInfo header options))
  where header = introMsg ++ usage ++ menu ++ "\nOptions:"

-- * Which modes do not require an output
outputNotRequired = ["count", "ast"
                  , "stencils-infer", "stencils-check"
                  , "units-infer", "units-check", "units-suggest"]

functionality = analyses ++ refactorings

{-| List of refactorings provided in CamFort -}
refactorings :: [(String
               , (FileOrDir -> [Filename] -> FileOrDir -> Options -> IO ()
               , String))]
refactorings =
    [("common", (common, "common block elimination")),
     ("equivalence", (equivalences, "equivalence elimination")),
     ("dead", (dead, "dead-code elimination")),
     ("datatype", (datatypes, "derived data type introduction"))]

{-| List of analses provided by CamFort -}
analyses :: [(String
           , (FileOrDir -> [Filename] -> FileOrDir -> Options -> IO ()
           , String))]
analyses =
    [
     ("count", (countVarDecls, "count variable declarations")),
     ("ast", (ast, "print the raw AST -- for development purposes")),
     ("stencils-check", (stencilsCheck, "stencil spec checking")),
     ("stencils-infer", (stencilsInfer, "stencil spec inference")),
     ("stencils-synth", (stencilsSynth, "stencil spec synthesis")),
     ("units-suggest", (unitsCriticals,
                                  "suggest variables to annotate with\
                                  \units-of-measure for maximum coverage")),
     ("units-check", (unitsCheck, "unit-of-measure checking")),
     ("units-infer", (unitsInfer, "unit-of-measure inference")),
     ("units-synth", (unitsSynth, "unit-of-measure synthesise specs.")),
     ("units-compile", (unitsCompile, "units-of-measure compile module information.")) ]

-- * Usage and about information
version = "0.902"
introMsg = "CamFort " ++ version ++ " - Cambridge Fortran Infrastructure."
usage = "Usage: camfort <MODE> <INPUT> [OUTPUT] [OPTIONS...]\n"
menu =
  "Refactor functions:\n"
  ++ concatMap (\(k, (_, info)) -> space ++ k ++ replicate (15 - length k) ' '
  ++ "   [" ++ info ++ "] \n") refactorings
  ++ "\nAnalysis functions:\n"
  ++ concatMap (\(k, (_, info)) -> space ++ k ++ replicate (15 - length k) ' '
  ++ "   [" ++ info ++ "] \n") analyses
  where space = replicate 5 ' '

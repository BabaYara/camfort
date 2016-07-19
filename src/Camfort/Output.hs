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

{-# LANGUAGE FlexibleInstances, UndecidableInstances, ImplicitParams, DoAndIfThenElse,
             MultiParamTypeClasses, FlexibleContexts, KindSignatures, ScopedTypeVariables,
             DeriveGeneric, DeriveDataTypeable #-}

{-

 Provides support for outputting source files and analysis information

-}

module Camfort.Output where

import Camfort.Helpers
import Camfort.Traverse

import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Util.Position as FU
import qualified Language.Fortran.Analysis as FA

import qualified Language.Fortran.Parser as Fortran
import Language.Fortran
import Language.Fortran.Pretty
import Language.Fortran.PreProcess

import Camfort.Analysis.Annotations
import Camfort.Analysis.Syntax
import Camfort.PrettyPrint
import Camfort.Reprint
import Camfort.Transformation.Syntax

import Camfort.Specification.Units.Environment

import System.FilePath
import System.Directory

-- FIXME: Did enough to get this module to compile, it's not optimised to use ByteString.
import qualified Data.ByteString.Char8 as B
import Data.Map.Lazy hiding (map, foldl)
import Data.Functor.Identity
import Data.Generics
import GHC.Generics
import Data.List hiding (zip)
import Data.Generics.Uniplate.Data
import Generics.Deriving.Copoint
import Data.Char
import Data.Generics.Zipper
import Data.Maybe
import Debug.Trace
import Text.Printf

import Control.Monad.Trans.Class
import Control.Monad.Trans.State.Lazy


-- Custom 'Show' which on strings is the identity
class Show' s where
      show' :: s -> String
instance {-# OVERLAPS #-} Show' String where
      show' = id
instance {-# OVERLAPS #-} (Show' a, Show' b) => Show' (a, b) where
      show' (a, b) = "(" ++ show' a ++ "," ++ show' b ++")"
instance {-# OVERLAPPABLE #-} (Show a) => Show' a where
      show' = show

class OutputFiles t where
  {-| Given a directory and list of triples of filenames, with their source
       text (if it exists) and their AST, write these to the directory -}
  mkOutputText :: FileOrDir -> t -> SourceText
  outputFile   :: t -> Filename

  outputFiles :: FileOrDir -> FileOrDir -> [t] -> IO ()
  outputFiles inp outp pdata = do
      outIsDir <- isDirectory outp
      inIsDir  <- isDirectory inp
      inIsFile <- doesFileExist inp
      if outIsDir then do
          createDirectoryIfMissing True outp
          putStrLn $ "Writing refactored files to directory: " ++ outp ++ "/"
          isdir <- isDirectory inp
          let inSrc = if isdir then inp else getDir inp
          mapM_ (\x -> let f' = changeDir outp inSrc (outputFile x)
                       in do checkDir f'
                             putStrLn $ "Writing " ++ f'
                             B.writeFile f' (mkOutputText outp x)) pdata
       else
         if inIsDir || length pdata > 1
         then  error $ "Error: attempting to output multiple files, but the \
                         \given output destination is a single file. \n\
                         \Please specify an output directory"
         else
           if inIsFile -- Input was just a file, then output just a file
           then do
             putStrLn $ "Writing refactored file to: " ++ outp
             putStrLn $ "Writing " ++ outp
             B.writeFile outp (mkOutputText outp (head pdata))

            else let outSrc = getDir outp
               in do createDirectoryIfMissing True outSrc
                     putStrLn $ "Writing refactored file to: " ++ outp
                     putStrLn $ "Writing " ++ outp
                     B.writeFile outp (mkOutputText outp (head pdata))

-- When the new source text is already provided
instance OutputFiles (Filename, SourceText) where
  mkOutputText _ (_, output) = output
  outputFile (f, _) = f

data PR a = PR (Program a) deriving Data

instance PrettyPrint (PR Annotation) where
   prettyPrint (PR x) = prettyPrint x

-- When there is a file to be reprinted (for refactoring)
instance OutputFiles (Filename, SourceText, Program Annotation) where
  mkOutputText f' (f, input, ast') = B.pack $ evalState (reprint refactoringLF input f' (PR ast')) 0
    where
  outputFile (f, _, _) = f

-- When there is a file to be reprinted (for refactoring)
instance OutputFiles (Filename, SourceText, F.ProgramFile Annotation) where
  mkOutputText f' (f, input, ast') = B.pack $ runIdentity $ reprint refactoringForPar input f' ast'
  outputFile (f, _, _) = f

srcSpanToSrcLocs :: FU.SrcSpan -> (SrcLoc, SrcLoc)
srcSpanToSrcLocs (FU.SrcSpan lpos upos) = (toSrcLoc lpos, toSrcLoc upos)
  where
    toSrcLoc pos = SrcLoc { srcFilename = ""
                          , srcLine     = FU.posLine pos
                          , srcColumn   = FU.posColumn pos }

instance (PrettyPrint (F.ProgramFile Annotation)) where
   -- STUB
   prettyPrint _ = ""

refactoringForPar :: (Typeable a) => [String] -> a -> StateT SrcLoc Identity (String, Bool)
refactoringForPar inp =
    (\_ -> return ("", False)) `extQ` (outputComments inp)
  where
    outputComments :: [String] -> F.Block Annotation -> StateT SrcLoc Identity (String, Bool)
    outputComments inp e@(F.BlComment ann span comment) = do
       cursor <- get
       if (pRefactored ann)
         then    let (lb, ub) = srcSpanToSrcLocs span
                     lb'      = leftOne lb
                     (p0, _)  = takeBounds (cursor, lb') inp
                     nl       = if comment == [] then "" else "\n"
                 in put ub >> return (p0 ++ comment ++ nl, True)
         else return ("", False)
      where leftOne (SrcLoc f l c) = SrcLoc f (l-1) (c-1)
    outputComments _ _ = return ("", False)


{-| changeDir is used to change the directory of a filename string.
    If the filename string has no directory then this is an identity  -}
changeDir newDir oldDir oldFilename = newDir ++ (listDiffL oldDir oldFilename)
                                      where listDiffL []     ys = ys
                                            listDiffL xs     [] = []
                                            listDiffL (x:xs) (y:ys) | x==y      = listDiffL xs ys
                                                                    | otherwise = ys

{-| output pre-analysis ASTs into the directory with the given file names (the list of ASTs should match the
    list of filenames) -}
outputAnalysisFiles :: FileOrDir -> [Program Annotation] -> [Filename] -> IO ()
outputAnalysisFiles src asts files = do
  isdir <- isDirectory src
  let src' = if isdir then src else dropFileName src
  putStrLn $ "Writing analysis files to directory: " ++ src'
  mapM (\(ast', f) -> writeFile (f ++ ".html") ((concatMap outputHTML) ast')) (zip asts files)
  return ()


{- Specifies how to do specific refactorings
  (uses generic query extension - remember extQ is non-symmetric)
-}

refactoringLF :: (Typeable a) => [String] -> a -> StateT SrcLoc (State Int) (String, Bool)
refactoringLF inp = ((((\_ -> return ("", False))
                              `extQ` (refactorUses inp))
                                 `extQ` (refactorDecl inp))
                                    `extQ` (refactorArgName inp))
                                       `extQ` (refactorFortran inp)


refactorFortran :: Monad m => [String] -> Fortran Annotation -> StateT SrcLoc m (String, Bool)
refactorFortran inp e = do
    cursor <- get
    if (pRefactored $ tag e) then
          let (lb, ub) = srcSpan e
              (p0, _) = takeBounds (cursor, lb) inp
              outE = pprint e
              lnl = case e of (NullStmt _ _) -> (if ((p0 /= []) && (Prelude.last p0 /= '\n')) then "\n" else "")
                              _              -> ""
              lnl2 = if ((p0 /= []) && (Prelude.last p0 /= '\n')) then "\n" else ""
              textOut = if p0 == "\n" then outE else (p0 ++ lnl2 ++ outE ++ lnl)
          in put ub >> return (textOut, True)
    else return ("", False)


refactorDecl :: [String] -> Decl Annotation -> StateT SrcLoc (State Int) (String, Bool)
refactorDecl inp d = do
    cursor <- get
    if (pRefactored $ tag d) then
       let (lb, ub) = srcSpan d
           (p0, _) = takeBounds (cursor, lb) inp
           textOut = p0 ++ (pprint d)
       in do textOut' <- -- The following compensates new lines with removed lines
                         case d of
                           (NullDecl _ _) ->
                              do added <- lift get
                                 let diff = linesCovered ub lb
                                 -- remove empty newlines here if extra lines have been added
                                 let (text, removed) = if added <= diff
                                                         then removeNewLines textOut added
                                                         else removeNewLines textOut diff
                                 lift $ put (added - removed)
                                 return text
                           otherwise -> return textOut
             put ub
             return (textOut', True)
    else return ("", False)

refactorArgName :: Monad m => [String] -> ArgName Annotation -> StateT SrcLoc m (String, Bool)
refactorArgName inp a = do
    cursor <- get
    case (refactored $ tag a) of
        Just lb -> do
            let (p0, _) = takeBounds (cursor, lb) inp
            put lb
            return (p0 ++ pprint a, True)
        Nothing -> return ("", False)

refactorUses :: [String] -> Uses Annotation -> StateT SrcLoc (State Int) (String, Bool)
refactorUses inp u = do
    cursor <- get
    let ?variant = HTMLPP in
        case (refactored $ tag u) of
           Just lb -> let (p0, _) = takeBounds (cursor, lb) inp
                          syntax  = printSlave u
                       in do added <- lift get
                             if (newNode $ tag u) then lift $ put (added + (countLines syntax))
                                                  else return ()
                             put $ toCol0 lb
                             return (p0 ++ syntax, True)
           Nothing -> return ("", False)

countLines []        = 0
countLines ('\n':xs) = 1 + countLines xs
countLines (x:xs)    = countLines xs

{- 'removeNewLines xs n' removes at most 'n' new lines characters from the input string
    xs, returning the new string and the number of new lines that were removed. Note
    that the number of new lines removed might actually be less than 'n'- but in principle
    this should not happen with the usaage in 'refactorDecl' -}

removeNewLines [] n = ([], 0)

removeNewLines xs 0 = (xs, 0)

-- Deal with CR LF in the same way as just LF
removeNewLines ('\r':('\n':('\r':('\n':xs)))) n = let (xs', n') = removeNewLines ('\r':'\n':xs) (n - 1)
                                                   in (xs', n' + 1)

removeNewLines ('\n':('\n':xs)) n = let (xs', n') = removeNewLines ('\n':xs) (n - 1)
                                     in (xs', n' + 1)
removeNewLines (x:xs) n = let (xs', n') = removeNewLines xs n
                          in (x:xs', n)

--removeNewLines ('\n':xs) 0 = let (xs', n') = removeNewLines xs 0
--                             in ('\n':xs', 0)

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
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}

module Camfort.Transformation.DeadCode
  ( deadCode
  ) where

import Camfort.Analysis (SimpleAnalysis, analysisInput, writeDebug)
import Camfort.Analysis.Annotations
import qualified Language.Fortran.Analysis.DataFlow as FAD
import qualified Language.Fortran.Analysis.Renaming as FAR
import qualified Language.Fortran.Analysis.BBlocks as FAB
import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Util.Position as FU
import qualified Language.Fortran.Analysis as FA
import Camfort.Helpers.Syntax

import qualified Data.IntMap as IM
import qualified Data.Set as S
import Data.Generics.Uniplate.Operations
import Data.Maybe


-- Eliminate dead code from a program, based on the fortran-src
-- live-variable analysis

-- Currently only strips out dead code through simple variable assignments
-- but not through array-subscript assignmernts
deadCode :: Bool -> SimpleAnalysis (F.ProgramFile A) (F.ProgramFile A)
deadCode flag = do
  pf <- analysisInput
  let
    (report, _) = deadCode' flag lva pf'
    -- initialise analysis
    pf'   = FAB.analyseBBlocks . FAR.analyseRenames . FA.initAnalysis $ pf
    -- get map of program unit ==> basic block graph
    bbm   = FAB.genBBlockMap pf'
    -- build the supergraph of global dependency
    sgr   = FAB.genSuperBBGr bbm
    -- extract the supergraph itself
    gr    = FAB.superBBGrGraph sgr
    -- live variables
    lva   = FAD.liveVariableAnalysis gr
  writeDebug report
  pure $ fmap FA.prevAnnotation pf'

deadCode' :: Bool -> FAD.InOutMap (S.Set F.Name)
                  -> F.ProgramFile (FA.Analysis A)
                  -> (Report, F.ProgramFile (FA.Analysis A))
deadCode' flag lva pf =
    if report == mempty
      then (report, pf')
      else (report, pf') >>= deadCode' flag lva
  where
    (report, pf') = transformBiM (perStmt flag lva) pf

-- Core of the transformation happens here on assignment statements
perStmt :: Bool
        -> FAD.InOutMap (S.Set F.Name)
        -> F.Statement (FA.Analysis A) -> (Report, F.Statement (FA.Analysis A))
perStmt flag lva x@(F.StExpressionAssign a sp@(FU.SrcSpan s1 _) e1 e2)
     | pRefactored (FA.prevAnnotation a) == flag =
  fromMaybe (mkReport "", x) $
    do label <- FA.insLabel a
       (_, out) <- IM.lookup label lva
       assignedName <- extractVariable e1
       if assignedName `S.member` out
         then Nothing
         else -- Dead assignment
           Just (mkReport report, F.StExpressionAssign a' (dropLine sp) e1 e2)
             where report =  "o" ++ show s1 ++ ": removed dead code\n"
                   -- Set annotation to mark statement for elimination in
                   -- the reprinter
                   a' = onPrev (\ap -> ap {refactored = Just s1}) a
perStmt _ _ x = return x

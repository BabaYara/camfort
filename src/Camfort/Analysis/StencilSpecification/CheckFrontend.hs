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

{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE ImplicitParams #-}

module Camfort.Analysis.StencilSpecification.CheckFrontend where

import Data.Data
import Data.Generics.Uniplate.Operations
import Control.Arrow
import Control.Monad.State.Lazy
import Control.Monad.Reader
import Control.Monad.Writer hiding (Product)

import Camfort.Analysis.StencilSpecification.CheckBackend
import qualified Camfort.Analysis.StencilSpecification.Grammar as Gram
import Camfort.Analysis.StencilSpecification.Model
import Camfort.Analysis.StencilSpecification.InferenceFrontend
import Camfort.Analysis.StencilSpecification.InferenceBackend
import Camfort.Analysis.StencilSpecification.Synthesis
import Camfort.Analysis.StencilSpecification.Syntax
import Camfort.Analysis.Loops (collect)
import Camfort.Analysis.Annotations
import Camfort.Analysis.CommentAnnotator
import Camfort.Helpers

import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Analysis as FA
import qualified Language.Fortran.Analysis.Types as FAT
import qualified Language.Fortran.Analysis.Renaming as FAR
import qualified Language.Fortran.Analysis.BBlocks as FAB
import qualified Language.Fortran.Analysis.DataFlow as FAD
import qualified Language.Fortran.Util.Position as FU

import Data.Graph.Inductive.Graph hiding (isEmpty)
import qualified Data.Map as M
import qualified Data.Set as S
import Data.Maybe
import Data.List


-- Entry point
stencilChecking :: F.ProgramFile (FA.Analysis A) -> [String]
stencilChecking pf = snd . runWriter $
  do -- Attempt to parse comments to specifications
     pf' <- annotateComments Gram.specParser pf
     let results = let ?flowsGraph = flTo in descendBiM perBlockCheck pf'
     -- Format output
     let a@(_, output) = evalState (runWriterT $ results) ([], [])
     tell $ pprint output
  where
    pprint = map (\(span, spec) -> show span ++ "\t" ++ spec)
    -- perform reaching definitions analysis
    rd    = FAD.reachingDefinitions dm gr
    -- create graph of definition "flows"
    flTo =  FAD.genFlowsToGraph bm dm gr rd
    -- VarFlowsToMap: A -> { B, C } indicates that A contributes to B, C
    flMap = FAD.genVarFlowsToMap dm flTo
    -- find 2-cycles: A -> B -> A
    cycs2 = [ (n, m) | (n, ns) <- M.toList flMap
                    , m       <- S.toList ns
                    , ms      <- maybeToList $ M.lookup m flMap
                    , n `S.member` ms && n /= m ]
    -- identify every loop by its back-edge
    beMap = FAD.genBackEdgeMap (FAD.dominators gr) gr

    -- get map of AST-Block-ID ==> corresponding AST-Block
    bm    = FAD.genBlockMap pf
    -- get map of program unit ==> basic block graph
    bbm   = FAB.genBBlockMap pf
    -- build the supergraph of global dependency
    sgr   = FAB.genSuperBBGr bbm
    -- extract the supergraph itself
    gr    = FAB.superBBGrGraph sgr
    -- get map of variable name ==> { defining AST-Block-IDs }
    dm    = FAD.genDefMap bm
    tenv  = FAT.inferTypes pf

-- Helper for transforming the 'previous' annotation
onPrev :: (a -> a) -> FA.Analysis a -> FA.Analysis a
onPrev f ann = ann { FA.prevAnnotation = f (FA.prevAnnotation ann) }

-- Instances for embedding parsed specifications into the AST
instance ASTEmbeddable (FA.Analysis Annotation) Gram.Specification where
  annotateWithAST ann ast =
    onPrev (\ann -> ann { stencilSpec = Just $ Left ast }) ann

instance Linkable (FA.Analysis Annotation) where
  link ann (b@(F.BlDo {})) =
      onPrev (\ann -> ann { stencilBlock = Just b }) ann
  link ann (b@(F.BlStatement _ _ _ (F.StExpressionAssign {}))) =
      onPrev (\ann -> ann { stencilBlock = Just b }) ann
  link ann b = ann


-- If the annotation contains an unconverted stencil specification syntax tree
-- then convert it and return an updated annotation containing the AST
parseCommentToAST :: FA.Analysis A -> FU.SrcSpan ->
  WriterT [(FU.SrcSpan, String)] (State (RegionEnv, [Variable])) (FA.Analysis A)
parseCommentToAST ann span =
  case stencilSpec (FA.prevAnnotation ann) of
    Just (Left stencilComment) -> do
         (regionEnv, _) <- get
         let ?renv = regionEnv
          in case synToAst stencilComment of
               Left err   -> error $ show span ++ ": " ++ err
               Right ast  -> return $ onPrev
                              (\ann -> ann {stencilSpec = Just (Right ast)}) ann
    _ -> return ann

-- If the annotation contains an encapsulated region environment, extract it
-- and add it to current region environment in scope
updateRegionEnv :: FA.Analysis A -> WriterT [(FU.SrcSpan, String)]
        (State (RegionEnv, [Variable])) ()
updateRegionEnv ann =
  case stencilSpec (FA.prevAnnotation ann) of
    Just (Right (Left regionEnv)) -> modify $ ((++) regionEnv) *** id
    _                             -> return ()

-- Given a mapping from variables to inferred specifications
-- an environment of specification delcarations, for each declared
-- specification check if there is a inferred specification that
-- agrees with it, *up-to the model*
compareInferredToDeclared :: [([F.Name], Specification)] -> SpecDecls -> Bool
compareInferredToDeclared inferreds declareds =
  all (\(names, dec) ->
    all (\name ->
      any (\inf -> eqByModel inf dec) (lookupAggregate inferreds name)
       ) names) declareds

perBlockCheck ::
      (?flowsGraph :: FAD.FlowsGraph A)
   => F.Block (FA.Analysis A)
   -> WriterT [(FU.SrcSpan, String)]
        (State (RegionEnv, [Variable])) (F.Block (FA.Analysis A))

perBlockCheck b@(F.BlComment ann span _) = do
  ann' <- parseCommentToAST ann span
  updateRegionEnv ann'
  let b' = F.setAnnotation ann' b
  case (stencilSpec $ FA.prevAnnotation ann', stencilBlock $ FA.prevAnnotation ann') of
    -- Comment contains a specification and an associated block
    (Just (Right (Right specDecls)), Just block) ->
     case block of
      s@(F.BlStatement ann span _ (F.StExpressionAssign _ _ _ rhs)) -> do
        -- Create list of relative indices
        (_, ivs) <- get
        -- Do inference
        let inferred = fst . runWriter $ genSpecifications ivs [s]
        -- Model and compare the current and specified stencil specs
        if compareInferredToDeclared inferred specDecls
          then tell [ (span, "Correct.") ]
          else tell [ (span, "Not well specified:\n\t\t  expecting: "
                           ++ pprintSpecDecls specDecls
                           ++ "\t\t  inferred:    " ++ pprintSpecDecls inferred) ]
        return $ b'
      _ -> return $ b'

      (F.BlDo ann span _ mDoSpec body) -> do
        -- Stub, collect stencils inside 'do' block
        return $ b'
      _ -> return $ b'
    _ -> return b'

perBlockCheck b@(F.BlDo ann span _ mDoSpec body) = do
   let localIvs = getInductionVar mDoSpec
   -- introduce any induction variables into the induction variable state
   modify $ id *** union localIvs
   -- descend into the body of the do-statement
   mapM_ (descendBiM perBlockCheck) body
   -- Remove any induction variable from the state
   modify $ id *** (\\ localIvs)
   return b

perBlockCheck b = do
  updateRegionEnv . F.getAnnotation $ b
  -- Go inside child blocks
  mapM_ (descendBiM perBlockCheck) $ children b
  return b

-- Local variables:
-- mode: haskell
-- haskell-program-name: "cabal repl"
-- End:
{-# LANGUAGE FlexibleContexts           #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE NamedFieldPuns             #-}
{-# LANGUAGE OverloadedStrings          #-}
{-# LANGUAGE RankNTypes                 #-}

{-# OPTIONS_GHC -Wall #-}

module Camfort.Specification.Hoare.CheckFrontend where

import           Control.Applicative                      (liftA2)
import           Control.Exception
import           Control.Lens
import           Control.Monad.Writer.Strict              hiding (Product)
import           Data.Generics.Uniplate.Operations
import           Data.Map                                 (Map)
import qualified Data.Map                                 as Map
import           Data.Maybe                               (catMaybes)
import           Data.Void                                (absurd)

import qualified Language.Fortran.Analysis                as F
import qualified Language.Fortran.AST                     as F
import qualified Language.Fortran.Util.Position           as F

import           Camfort.Analysis
import qualified Camfort.Analysis.Annotations as CA
import           Camfort.Analysis.CommentAnnotator
import           Camfort.Analysis.ModFile                 (withCombinedModuleMap)
import           Camfort.Specification.Parser             (SpecParseError)

import           Language.Fortran.Model.Repr.Prim

import           Camfort.Specification.Hoare.Annotation
import           Camfort.Specification.Hoare.CheckBackend
import           Camfort.Specification.Hoare.Parser
import           Camfort.Specification.Hoare.Parser.Types (HoareParseError)
import           Camfort.Specification.Hoare.Syntax

--------------------------------------------------------------------------------
--  Results and errors
--------------------------------------------------------------------------------

type HoareAnalysis = AnalysisT HoareFrontendError HoareFrontendWarning IO

data HoareFrontendError
  = ParseError (SpecParseError HoareParseError)
  | InvalidPUConditions F.ProgramUnitName [SpecOrDecl InnerHA]
  | BackendError HoareBackendError

data HoareFrontendWarning
  = OrphanDecls F.ProgramUnitName [AuxDecl InnerHA]

instance Describe HoareFrontendError where
  describeBuilder = \case
    ParseError spe -> "parse error: " <> describeBuilder (displayException spe)
    InvalidPUConditions nm conds ->
      "invalid specification types attached to PU with name " <> describeBuilder (show nm) <> ": " <>
      describeBuilder (show conds)
    BackendError e -> describeBuilder e

instance Describe HoareFrontendWarning where
  describeBuilder = \case
    OrphanDecls nm decls ->
      "auxiliary variable declared for a program unit with no annotations with name " <>
      describeBuilder (show nm) <> ": " <> describeBuilder (show decls)

parseError :: F.SrcSpan -> SpecParseError HoareParseError -> HoareAnalysis ()
parseError sp err = logError' sp (ParseError err)

-- | Finds all annotated program units in the given program file. Returns errors
-- for program units that are incorrectly annotated, along with a list of
-- program units which are correctly annotated at the top level.
findAnnotatedPUs :: F.ProgramFile HA -> HoareAnalysis [AnnotatedProgramUnit]
findAnnotatedPUs pf =
  let pusByName :: Map F.ProgramUnitName (F.ProgramUnit HA)
      pusByName = Map.fromList [(F.puName pu, pu) | pu <- universeBi pf]

      -- Each annotation may get linked with one program unit. However, for this
      -- analysis we want to collect all of the annotations that are associated
      -- with the same program unit. For this we need to do some extra work
      -- because the comment annotator can't directly deal with this situation.
      sodsByPU :: Map F.ProgramUnitName [SpecOrDecl InnerHA]
      sodsByPU = Map.fromListWith (++)
        [(nm, [sod])
        | ann <- universeBi pf :: [HA]
        , Just nm  <- [F.prevAnnotation ann ^. hoarePUName]
        , Just sod <- [F.prevAnnotation ann ^. hoareSod]]

      -- For a given program unit and list of associated specifications, either
      -- create an annotated program unit, or report an error if something is
      -- wrong.
      collectUnit
        :: F.ProgramUnit HA -> [SpecOrDecl InnerHA]
        -> HoareAnalysis (Maybe AnnotatedProgramUnit)
      collectUnit pu sods = do
        let pres  = sods ^.. traverse . _SodSpec . _SpecPre
            posts = sods ^.. traverse . _SodSpec . _SpecPost
            decls = sods ^.. traverse . _SodDecl


            errors = filter (isn't (_SodSpec . _SpecPre ) .&&
                             isn't (_SodSpec . _SpecPost) .&&
                             isn't _SodDecl)
                     sods
              where (.&&) = liftA2 (&&)

            result = AnnotatedProgramUnit pres posts decls pu

        unless (null errors) $ logError' pu (InvalidPUConditions (F.puName pu) errors)

        if null pres && null posts
          then do
            unless (null decls) $ logWarn' pu (OrphanDecls (F.puName pu) decls)
            return Nothing
          else return $ Just result

      apus :: [HoareAnalysis (Maybe AnnotatedProgramUnit)]
      apus = map snd . Map.toList $ Map.intersectionWith collectUnit pusByName sodsByPU

  in catMaybes <$> sequence apus


invariantChecking :: PrimReprSpec -> F.ProgramFile HA -> HoareAnalysis [HoareCheckResult]
invariantChecking primSpec pf = do
  let parserWithAnns = F.initAnalysis . fmap (const CA.unitAnnotation) <$> hoareParser

  pf' <- annotateComments parserWithAnns parseError pf
  mfs <- analysisModFiles

  -- TODO: This isn't the purpose of module maps! Run the renamer over annotated
  -- comments instead.
  let (pf'', _) = withCombinedModuleMap mfs pf'

  annotatedPUs <- findAnnotatedPUs pf''

  let checkAndReport apu = do
        let nm = F.puName (apu ^. apuPU)
            prettyName = describe $ case F.puSrcName (apu ^. apuPU) of
              F.Named x -> x
              _         -> show nm
        logInfo' (apu ^. apuPU) $ "Verifying program unit: " <> prettyName
        loggingAnalysisError . mapAnalysisT BackendError absurd $ checkPU apu primSpec

  catMaybes <$> traverse checkAndReport annotatedPUs

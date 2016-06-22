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

This files gives an executable implementation of the model for
abstract stencil specifications. This model is used to drive both
the specification checking and program synthesis features.

-}

{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE TupleSections #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE ImplicitParams #-}

module Camfort.Analysis.StencilSpecification.Model where

import Camfort.Analysis.StencilSpecification.Syntax
import Data.Set hiding (map,foldl')
import qualified Data.Set as Set
import Data.List hiding ((\\))
import qualified Data.List as DL
import qualified Data.Map as DM

import Debug.Trace

-- Relative multi-dimensional indices are represented by [Int]
-- e.g. [0, 1, -1] corresponds to a subscript expression a(i, j+1, k-1)
-- Specifications are mapped to (multi)sets of [Int] where
-- the multiset representation is a Map to Bool giving
-- False = multiplicity 1, True = multiplicity > 1

model :: Result Spatial -> Result (Multiset [Int])
model s = let ?dimensionality = dimensionality s
          in mkModel s

-- Is an inferred specification equal to a declared specification,
-- up to the mode? The first parameter must come from the inference and
-- the second from a user-given declaration
eqByModel :: Specification -> Specification -> Bool
eqByModel infered declared =
    let d1 = dimensionality infered
        d2 = dimensionality declared
    in let ?dimensionality = d1 `max` d2
       in let modelInf = mkModel infered
              modelDec = mkModel declared
          in case (modelInf, modelDec) of
               -- Test approximations first

               -- If only one bound is present in one model, but both are in the
               -- other, then compare only the bounds present in both
               (Bound (Just mdlLI) Nothing, Bound (Just mdlLD) _)
                        -> mdlLD <= mdlLI
               (Bound Nothing (Just mdlUI), Bound _ (Just mdlUD))
                        -> mdlUI <= mdlUD
               (Bound (Just mdlLI) (Just _), Bound (Just mdlLD) Nothing)
                        -> mdlLD <= mdlLI
               (Bound (Just _ ) (Just mdlUI), Bound Nothing (Just mdlUD))
                        -> mdlUI <= mdlUD
               (Exact s, Bound Nothing (Just mdlUD))
                        -> s <= mdlUD
               (Exact s, Bound (Just mdlLD) Nothing)
                        -> mdlLD <= s
               (Exact s, Bound (Just mdlLD) (Just mdlUD))
                        -> (mdlLD <= s) && (s <= mdlUD)
              -- Otherwise do the normal comparison
               (x, y) -> x == y


-- Recursive `Model` class implemented for all parts of the spec.
class Model spec where
   type Domain spec

   -- generate model for the specification, where the implicit
   -- parameter ?dimensionality is the global dimensionality
   -- for the spec (not just the local maximum dimensionality)
   mkModel :: (?dimensionality :: Int) => spec -> Domain spec

   -- Return the maximum dimension specified in the spec
   -- giving the dimensionality for that specification
   dimensionality :: spec -> Int
   dimensionality = maximum . dimensions
   -- Return all the dimensions specified for in this spec
   dimensions :: spec -> [Int]

-- Multiset representation where multiplicities are (-1) modulo 2
-- that is, False = multiplicity 1, True = multiplicity > 1
type Multiset a = DM.Map a Bool

-- Build a multiset representation from a list (of possibly repeated) elements
mkMultiset :: Ord a => [a] -> DM.Map a Bool
mkMultiset =
  Prelude.foldr (\a map -> DM.insertWithKey multi a True map) DM.empty
     where multi k x y = x || y

instance Model Specification where
   type Domain Specification = Result (Multiset [Int])

   mkModel (Specification (Left s)) = mkModel s
   mkModel _                        = error "Only spatial specs are modelled"

   dimensionality (Specification (Left s)) = dimensionality s
   dimensionality _                        = 0

   dimensions (Specification (Left s)) = dimensions s
   dimensions _                        = [0]

-- Model a 'Result' of 'Spatial'
instance Model (Result Spatial) where
  type Domain (Result Spatial) = Result (Multiset [Int])

  mkModel = fmap mkModel
  dimensionality (Exact s) = dimensionality s
  dimensionality (Bound l u) = (dimensionality l) `max` (dimensionality u)

  dimensions (Exact s) = dimensions s
  dimensions (Bound l u) = (dimensions l) ++ (dimensions u)

-- Lifting of model to Maybe type
instance Model a => Model (Maybe a) where
  type Domain (Maybe a) = Maybe (Domain a)

  mkModel Nothing = Nothing
  mkModel (Just x) = Just (mkModel x)

  dimensions Nothing = [0]
  dimensions (Just x) = dimensions x

-- Core part of the model
instance Model Spatial where
    type Domain Spatial = Multiset [Int]

    mkModel spec@(Spatial lin irrefls refls s) =
      case lin of
        Linear    -> DM.fromList . map (,False) . toList $ indices
        NonLinear -> DM.fromList . map (,True) . toList $ indices
       where
         indices = Set.difference (Set.union reflIxs model) irreflIxs

         reflIxs   = fromList [mkSingleEntry 0 d ?dimensionality | d <- refls]
         irreflIxs = fromList [mkSingleEntryNeg 0 d ?dimensionality | d <- irrefls]

         mdl = mkModel s
         model = case absoluteIxs of
                   [] -> mdl
                   _  -> fromList $ cprodV (toList mdl) absoluteIxs

         absoluteIxs = [mkSingleEntry absoluteRep d ?dimensionality | d <- unspecifiedDims ]
         unspecifiedDims = (DL.\\) [1 .. ?dimensionality] (sort $ dimensions spec)

    dimensionality (Spatial _ irrefls refls s) =
              maximum1 refls
        `max` dimensionality s

    dimensions (Spatial _ _ refls s) = refls ++ (dimensions s)


instance Model RegionSum where
   type Domain RegionSum = Set [Int]
   mkModel (Sum ss) = unions (map mkModel ss)
   dimensionality (Sum ss) =
     maximum1 (map dimensionality ss)

   dimensions (Sum ss) = concatMap dimensions ss


instance Model Region where
   type Domain Region = Set [Int]

   mkModel (Forward dep dim) =
     fromList [mkSingleEntry i dim ?dimensionality | i <- [0..dep]]

   mkModel (Backward dep dim) =
     fromList [mkSingleEntry i dim ?dimensionality | i <- [(-dep)..0]]

   mkModel (Centered dep dim) =
     fromList [mkSingleEntry i dim ?dimensionality | i <- [(-dep)..dep]]

   dimensionality (Forward  _ d) = d
   dimensionality (Backward _ d) = d
   dimensionality (Centered _ d) = d

   dimensions (Forward _ d)  = [d]
   dimensions (Backward _ d) = [d]
   dimensions (Centered _ d) = [d]

-- | mkSingleEntry offset dimension dimensionality -> relative index vector
-- | precondition: dimensionality >= dimension
mkSingleEntry :: Int -> Int -> Int -> [Int]
mkSingleEntry i 0 ds = error $ "Dimensions are 1-indexed"
mkSingleEntry i 1 ds = [i] ++ take (ds - 1) (repeat 0)
mkSingleEntry i d ds = 0 : mkSingleEntry i (d - 1) (ds - 1)

mkSingleEntryNeg :: Int -> Int -> Int -> [Int]
mkSingleEntryNeg i 0 ds = error $ "Dimensions are 1-indexed"
mkSingleEntryNeg i 1 ds = [i] ++ take (ds - 1) (repeat absoluteRep)
mkSingleEntryNeg i d ds = absoluteRep : mkSingleEntry i (d - 1) (ds - 1)


instance Model RegionProd where
   type Domain RegionProd = Set [Int]

   mkModel (Product []) = Set.empty
   mkModel (Product ss) =
      fromList $ cprodVs $ map (toList . mkModel) ss

   dimensionality (Product ss) =
      maximum1 (map dimensionality ss)
   dimensions (Product ss) =
      concatMap dimensions ss

-- Cartesian product on list of vectors4
cprodVs :: [[[Int]]] -> [[Int]]
cprodVs = foldr1 cprodV

cprodV :: [[Int]] -> [[Int]] -> [[Int]]
cprodV xss yss = xss >>= (\xs -> yss >>= (\ys -> pairwisePerm xs ys))

pairwisePerm :: [Int] -> [Int] -> [[Int]]
pairwisePerm x y = sequence . map prod . transpose $ [x, y]
  where prod xs = if any (\x -> x == absoluteRep) xs
                  then [absoluteRep]
                  else xs

maximum1 [] = 0
maximum1 xs = maximum xs

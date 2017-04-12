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

{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE LambdaCase #-}

module Camfort.Specification.Stencils.InferenceBackend where

import Prelude
import Data.Generics.Uniplate.Operations
import Data.List
import Data.Data
import Control.Arrow ((***))
import Data.Function
import Data.Maybe
import Algebra.Lattice (joins1)

import Camfort.Specification.Stencils.Model
import Camfort.Specification.Stencils.LatticeModel
import Camfort.Specification.Stencils.DenotationalSemantics
import Camfort.Helpers
import qualified Camfort.Helpers.Vec as V

import Debug.Trace
import Unsafe.Coerce

import Camfort.Specification.Stencils.Syntax

{- Spans are a pair of a lower and upper bound -}

type Span a = (a, a)

spansToApproxSpatial :: [ Span (V.Vec (V.S n) Int) ]
                       -> Either String (Approximation Spatial)
spansToApproxSpatial spans = sequence . fmap intervalsToRegions $ approxUnion
  where
    approxVecs =
      toApprox . map (fmap absRepToInf . transposeVecInterval) $ spans
    approxUnion = fmap (joins1 . map return) approxVecs

    toApprox :: [ V.Vec n (Interval Arbitrary) ]
             -> Approximation [ V.Vec n (Interval Standard) ]
    toApprox vs
      | parts <- (elongatedPartitions . map approxVec) vs =
          case parts of
            (orgs, []) -> Exact . map fromExact $ orgs
            ([], elongs) -> Bound Nothing (Just $ map upperBound elongs)
            (orgs, elongs) -> Bound (Just . map upperBound $ orgs)
                                    (Just . map upperBound $ orgs ++ elongs)

    elongatedPartitions =
      partition $ \case { Exact{} -> True; Bound{} -> False }

    -- TODO: DELETE AS SOON AS POSSIBLE
    absRepToInf :: Interval Arbitrary -> Interval Arbitrary
    absRepToInf interv@(IntervArbitrary a b)
      | fromIntegral a == absoluteRep = IntervInfiniteArbitrary
      | fromIntegral b == absoluteRep = IntervInfiniteArbitrary
      | otherwise = interv

    transposeVecInterval :: Span (V.Vec n Int) -> V.Vec n (Interval Arbitrary)
    transposeVecInterval (us, vs) = V.zipWith IntervArbitrary us vs

mkTrivialSpan :: V.Vec n Int -> Span (V.Vec n Int)
mkTrivialSpan V.Nil = (V.Nil, V.Nil)
mkTrivialSpan (V.Cons x xs) =
    if x == absoluteRep
    then (V.Cons (-absoluteRep) ys, V.Cons absoluteRep zs)
    else (V.Cons x ys, V.Cons x zs)
  where
    (ys, zs) = mkTrivialSpan xs

-- TODO: This seems completely redundant. Perhaps DELETE.
inferFromIndices :: VecList Int -> Specification
inferFromIndices (VL ixs) = Specification $
    case fromBool mult of
      Linear -> Once $ inferCore ixs'
      NonLinear -> Mult $ inferCore ixs'
    where
      (ixs', mult) = hasDuplicates ixs

-- Same as inferFromIndices but don't do any linearity checking
-- (defaults to NonLinear). This is used when the front-end does
-- the linearity check first as an optimimsation.
inferFromIndicesWithoutLinearity :: VecList Int -> Specification
inferFromIndicesWithoutLinearity (VL ixs) =
    Specification . Mult . inferCore $ ixs

inferCore :: [V.Vec n Int] -> Approximation Spatial
inferCore subs =
    case V.proveNonEmpty . head $ subs of
      Just (V.ExistsEqT V.ReflEq) ->
        case fmap simplify . spansToApproxSpatial . inferMinimalVectorRegions $ subs of
          Right a -> a
          Left msg -> error msg
      Nothing -> error "Input vectors are empty!"

simplify :: Approximation Spatial -> Approximation Spatial
simplify = fmap simplifySpatial

simplifySpatial :: Spatial -> Spatial
simplifySpatial (Spatial (Sum ps)) = Spatial (Sum ps')
   where ps' = order (reducor ps normaliseNoSort size)
         order = sort . map (Product . sort . unProd)
         size :: [RegionProd] -> Int
         size = Prelude.sum . map (length . unProd)

-- Given a list, a list->list transofmer, a size function
-- find the minimal transformed list by applying the transformer
-- to every permutation of the list and when a smaller list is found
-- iteratively apply to permutations on the smaller list
reducor :: [a] -> ([a] -> [a]) -> ([a] -> Int) -> [a]
reducor xs f size = reducor' (permutations xs)
    where
      reducor' [y] = f y
      reducor' (y:ys) =
          if size y' < size y
            then reducor' (permutations y')
            else reducor' ys
        where y' = f y

{-| |inferMinimalVectorRegions| a key part of the algorithm, from a list of
    n-dimensional relative indices it infers a list of (possibly overlapping)
    1-dimensional spans (vectors) within the n-dimensional space.
    Built from |minimalise| and |allRegionPermutations| -}
inferMinimalVectorRegions :: [V.Vec n Int] -> [Span (V.Vec n Int)]
inferMinimalVectorRegions = fixCoalesce . map mkTrivialSpan
  where fixCoalesce spans =
          let spans' = minimaliseRegions . coalesceContiguous $ spans
          in if spans' == spans then spans' else fixCoalesce spans'

-- An alternative that is simpler and possibly quicker
coalesceContiguous :: [Span (V.Vec n Int)] -> [Span (V.Vec n Int)]
coalesceContiguous []  = []
coalesceContiguous [x] = [x]
coalesceContiguous [x, y] =
    case coalesce x y of
       Nothing -> [x, y]
       Just c  -> [c]
coalesceContiguous (x:xs) =
    case sequenceMaybes (map (coalesce x) xs) of
       Nothing -> x : coalesceContiguous xs
       Just cs -> coalesceContiguous (cs ++ xs)

sequenceMaybes :: Eq a => [Maybe a] -> Maybe [a]
sequenceMaybes xs | all (== Nothing) xs = Nothing
                  | otherwise = Just (catMaybes xs)

coalesce :: Span (V.Vec n Int) -> Span (V.Vec n Int) -> Maybe (Span (V.Vec n Int))
coalesce (V.Nil, V.Nil) (V.Nil, V.Nil) = Just (V.Nil, V.Nil)
-- If two well-defined intervals are equal, then they cannot be coalesced
coalesce x y | x == y = Nothing
-- Otherwise
coalesce x@(V.Cons l1 ls1, V.Cons u1 us1) y@(V.Cons l2 ls2, V.Cons u2 us2)
  | l1 == l2 && u1 == u2
    = case coalesce (ls1, us1) (ls2, us2) of
        Just (l, u) -> Just (V.Cons l1 l, V.Cons u1 u)
        Nothing     -> Nothing
  | (u1 + 1 == l2) && (us1 == us2) && (ls1 == ls2)
    = Just (V.Cons l1 ls1, V.Cons u2 us2)
  | (u2 + 1 == l1) && (us1 == us2) && (ls1 == ls2)
    = Just (V.Cons l2 ls2, V.Cons u1 us1)
  | otherwise
    = Nothing

{-| Collapses the regions into a small set by looking for potential overlaps
    and eliminating those that overlap -}
minimaliseRegions :: [Span (V.Vec n Int)] -> [Span (V.Vec n Int)]
minimaliseRegions [] = []
minimaliseRegions xss = nub . minimalise $ xss
  where localMin x ys = filter' x (\y -> containedWithin x y && (x /= y)) xss ++ ys
        minimalise = foldr localMin []
        -- If nothing is caught by the filter, i.e. no overlaps then return
        -- the original regions r
        filter' r f xs = case filter f xs of
                           [] -> [r]
                           ys -> ys

{-| Binary predicate on whether the first region containedWithin the second -}
containedWithin :: Span (V.Vec n Int) -> Span (V.Vec n Int) -> Bool
containedWithin (V.Nil, V.Nil) (V.Nil, V.Nil)
  = True
containedWithin (V.Cons l1 ls1, V.Cons u1 us1) (V.Cons l2 ls2, V.Cons u2 us2)
  = (l2 <= l1 && u1 <= u2) && containedWithin (ls1, us1) (ls2, us2)


{- Vector list repreentation where the size 'n' is existential quantified -}
data VecList a where VL :: [V.Vec n a] -> VecList a

-- pre-condition: the input is a 'rectangular' list of lists (i.e. all internal
-- lists have the same size)
fromLists :: [[Int]] -> VecList Int
fromLists [] = VL ([] :: [V.Vec V.Z Int])
fromLists (xs:xss) = consList (V.fromList xs) (fromLists xss)
  where
    consList :: V.VecBox Int -> VecList Int -> VecList Int
    consList (V.VecBox vec) (VL [])     = VL [vec]
    consList (V.VecBox vec) (VL xs)
      = -- Force the pre-condition equality
        case preCondition vec xs of
            V.ReflEq -> VL (vec : xs)
            where -- At the moment the pre-condition is 'assumed', and therefore
              -- force used unsafeCoerce: TODO, rewrite
              preCondition :: V.Vec n a -> [V.Vec n1 a] -> V.EqT n n1
              preCondition xs x = unsafeCoerce V.ReflEq

-- Local variables:
-- mode: haskell
-- haskell-program-name: "cabal repl"
-- End:

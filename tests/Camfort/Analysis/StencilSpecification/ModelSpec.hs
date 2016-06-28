{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ImplicitParams #-}

module Camfort.Analysis.StencilSpecification.ModelSpec (spec) where

import Camfort.Helpers.Vec
import Camfort.Analysis.StencilSpecification
import Camfort.Analysis.StencilSpecification.Synthesis
import Camfort.Analysis.StencilSpecification.Model
import Camfort.Analysis.StencilSpecification.Syntax hiding (Spec)
import qualified Camfort.Analysis.StencilSpecification.Syntax as Syn

import Camfort.Analysis.Annotations
import qualified Language.Fortran.AST as F
import Language.Fortran.Util.Position

import Data.Bits
import Data.List
import Data.Map hiding (map)

import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck

spec :: Spec
spec = do
  describe "Stencils - Model" $ do
    describe "Test soundness of model 1" $ modelHasLeftInverse
    describe "Test soundness of model 2" $ modelHasApproxLeftInverse variations2
    describe "Test soundness of model 3" $ modelHasApproxLeftInverse variations3

  describe "Consistency of model with paper" $ do
    describe "Quickcheck" $ it "" $ property $ propPairwisePerm

    describe "Manual for absolute rep" $ do
      it "Check absolute rep (0)" $
                   (sort $ pp           [1,2,absoluteRep] [5,1,7])
        `shouldBe` (sort $ pairwisePerm [1,2,absoluteRep] [5,1,7])

      it "Check absolute rep (1)" $
                   (sort $ pp           [1,absoluteRep] [5,1])
        `shouldBe` (sort $ pairwisePerm [1,absoluteRep] [5,1])

      it "Check absolute rep (2)" $
                   (sort $ pp           [absoluteRep,2,absoluteRep] [absoluteRep,1,7])
        `shouldBe` (sort $ pairwisePerm [absoluteRep,2,absoluteRep] [absoluteRep,1,7])


propPairwisePerm :: [Int] -> [Int] -> Bool
propPairwisePerm x y = if (length x == length y && length x < 16)
                         then (sort . nub $ pp x y)
                           == (sort . nub $ pairwisePerm x y)
                         else True

pp :: [Int] -> [Int] -> [[Int]]
pp x y = nub $
 let n = length x
 in map (\i ->
     map (\j ->
          ((x !! j) `times` (not (testBit i j))
   `plus` ((y !! j) `times` testBit i j))
          ) [0..(n-1)]
       ) [0 :: Int .. ((2^n)-1)]
    where times x True = x
          times x False | x == absoluteRep = x
                        | otherwise = 0
          plus x y | x == absoluteRep || y == absoluteRep = absoluteRep
                   | otherwise = x + y


variations :: [([(Int, Int)], Syn.Result Spatial)]
variations =
  [ ([ (0,0) ],
    Exact $ Spatial NonLinear [] [ 1, 2 ] (Sum [Product []]))

  , ([ (1,0), (0,0) ],
    Exact $ Spatial NonLinear [] [2] (Sum [Product [Forward 1 1]]))

  , ([ (0,1), (0,0) ],
    Exact $ Spatial NonLinear [] [1] (Sum [Product [Forward 1 2]]))

  , ([ (1,1), (0,1), (1,0), (0,0) ],
    Exact $ Spatial NonLinear [] [] (Sum [Product [Forward 1 1, Forward 1 2]]))

  , ([ (-1, 1), (0, 1) ],
    Exact $ Spatial NonLinear [2] [] (Sum [Product [Backward 1 1, Forward 1 2]]))

  , ([ (-1,0), (0,0) ],
    Exact $ Spatial NonLinear [] [2] (Sum [Product [Backward 1 1]]))

  , ([ (0,-1), (0,0) ],
    Exact $ Spatial NonLinear [] [1] (Sum [Product [Backward 1 2]]))

  , ([ (-1,-1), (0,-1), (-1,0), (0,0) ],
    Exact $ Spatial NonLinear [] [] (Sum [Product [Backward 1 1, Backward 1 2]]))

  , ( [ (0,-1), (1,-1), (0,0), (1,0), (1,1), (0,1), (2,-1), (2,0), (2,1) ],
    Exact $ Spatial NonLinear [] []
              (Sum [Product [ Forward 2 1, Centered 1 2 ] ] ))

  , ( [ (-1,0), (-1,1), (0,0), (0,1), (1,1), (1,0), (-1,2), (0,2), (1,2) ],
    Exact $ Spatial NonLinear [] []
              (Sum [Product [ Forward 2 2, Centered 1 1 ] ] ))
 ]

variations2 :: [(Syn.Result [[Int]], Int, Syn.Result Spatial)]
variations2 =
  [
  -- Stencil which has some absolute component (not represented in the spec)
    (Exact [ [0, absoluteRep], [1, absoluteRep] ], 2,
    Exact $ Spatial NonLinear [] [] (Sum [Product [Forward 1 1]]))

 -- Spec on bounds
 ,  (Bound Nothing (Just $ [ [0, absoluteRep], [1, absoluteRep],
                             [2, absoluteRep] ]), 2,
     Bound Nothing
           (Just $ Spatial NonLinear [] [] (Sum [Product [Forward 2 1]])))
 ]

variations3 :: [(Syn.Result [[Int]], Int, Syn.Result Spatial)]
variations3 =
  [
 -- Spec on bounds
    (Bound Nothing (Just $ [ [0, absoluteRep, 0], [1, absoluteRep, 0],
                             [2, absoluteRep, 0],
                             [0, absoluteRep, 1], [1, absoluteRep, 1],
                             [2, absoluteRep, 1]]), 3,
     Bound Nothing
           (Just $ Spatial NonLinear [] [] (Sum [Product [Forward 1 3, Forward 2 1]])))
  ]

modelHasLeftInverse = mapM_ check (zip variations [0..])
  where check ((ixs, spec), n) = it ("("++show n++")") $ (sort mdl) `shouldBe` (sort ixs)
          where mdl = map (toPair . fst) . toList . fromExact . model $ spec
        toPair [x, y] = (x, y)
        toPair xs     = error $ "Got " ++ show xs

modelHasApproxLeftInverse vars = mapM_ check (zip vars [(0 :: Int)..])
  where check ((ixs, dims, spec), n) =
          it ("("++show n++")") $ mdl' `shouldBe` (fmap sort ixs)
            where mdl = let ?globalDimensionality = dims in mkModel spec
                  mdl' = fmap (sort . map fst . toList) mdl

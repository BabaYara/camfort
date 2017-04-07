{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE ImplicitParams #-}

module Camfort.Specification.Stencils.ModelSpec (spec) where

import qualified Camfort.Helpers.Vec as V
import Camfort.Specification.Stencils
import Camfort.Specification.Stencils.Synthesis
import Camfort.Specification.Stencils.Model
import Camfort.Specification.Stencils.Syntax hiding (Spec)
import qualified Camfort.Specification.Stencils.Syntax as Syn

import Camfort.Analysis.Annotations
import qualified Language.Fortran.AST as F
import Language.Fortran.Util.Position

import Data.Bits
import Data.List
import Data.Set (toList)

import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck

spec :: Spec
spec = do
  describe "Consistency of model vs access patterns" $ do
    let singleOneDimSpec = Single $ Exact $ Spatial $ Sum
          [ Product [ Forward 1 1 True ] ]
    it "1D readOnce - positive" $ do
      let acs = Single [[0], [1]]
      consistent acs singleOneDimSpec `shouldBe` True

    it "1D readOnce - negative" $ do
      let acs = Multiple [[0], [1]]
      consistent acs singleOneDimSpec `shouldBe` False

    let reflCentOneDimSpec = Single $ Exact $ Spatial $ Sum
          [ Product [ Centered 1 1 False ] ]
    it "1D centered nonpointed - positive" $ do
      let acs = Single [[-1], [1]]
      consistent acs reflCentOneDimSpec `shouldBe` True

    let centeredAcs = Single [[-1], [0], [1]]
    it "1D centered nonpointed - negative" $
      consistent centeredAcs reflCentOneDimSpec `shouldBe` False

    it "1D centered nonpointed lower bound - positive" $ do
      let spec = Single $ Bound
            (Just $ Spatial $ Sum [ Product [ Centered 1 1 False ] ])
            Nothing
      consistent centeredAcs spec `shouldBe` True

    it "1D backward nonpointed lower bound - positive" $ do
      let spec = Single $ Bound
            (Just $ Spatial $ Sum [ Product [ Backward 1 1 False ] ])
            Nothing
      consistent (Single [[-1]]) spec `shouldBe` True

    it "1D centered nonpointed upper bound - negative" $ do
      let spec = Single $ Bound
            Nothing
            (Just $ Spatial $ Sum [ Product [ Centered 1 1 False ] ])
      consistent centeredAcs spec `shouldBe` False

    it "1D double bounded" $ do
      let acs = Single [ [-3], [-2], [-1], [0], [1], [3] ]
      let spec = Single $ Bound
            (Just $ Spatial $ Sum [ Product [ Centered 1 1 True ] ])
            (Just $ Spatial $ Sum [ Product [ Centered 1 3 True ] ])
      consistent acs spec `shouldBe` True

    it "1D spec 3D access" $ do
      let acs = Single [ [0,1,-2], [absoluteRep, 2,3] ]
      let spec = Single $ Exact $
            Spatial $ Sum [ Product [ Forward 2 2 False ] ]
      consistent acs spec `shouldBe` True

    let twoDimSpec = Single $ Exact $
          Spatial $ Sum [ Product [ Centered 0 1 True, Forward 1 2 True ] ]

    it "2 dimensional spec example" $ do
      let acs = Single [ [0,0], [0,1] ]
      consistent acs twoDimSpec `shouldBe` True

    it "Constant access not allowed in otherwise fine access pattern" $ do
      let acs = Single [ [0,0], [0,1], [absoluteRep, absoluteRep] ]
      consistent acs twoDimSpec `shouldBe` False

  describe "Stencils - Model" $ do
    describe "Test soundness of model 1" modelHasLeftInverse
    describe "Test soundness of model 2" $ modelHasApproxLeftInverse variations2
    describe "Test soundness of model 3" $ modelHasApproxLeftInverse variations3

  describe "Consistency of model with paper" $ do
    describe "Quickcheck" $ it "" $ property propPairwisePerm

    describe "Manual for absolute rep" $ do
      it "Check absolute rep (0)" $
                   sort (pp           [1,2,absoluteRep] [5,1,7])
        `shouldBe` sort (pairwisePerm [1,2,absoluteRep] [5,1,7])

      it "Check absolute rep (1)" $
                   sort (pp           [1,absoluteRep] [5,1])
        `shouldBe` sort (pairwisePerm [1,absoluteRep] [5,1])

      it "Check absolute rep (2)" $
                   sort (pp           [absoluteRep,2,absoluteRep] [absoluteRep,1,7])
        `shouldBe` sort (pairwisePerm [absoluteRep,2,absoluteRep] [absoluteRep,1,7])


propPairwisePerm :: [Int] -> [Int] -> Bool
propPairwisePerm x y =
    if length x == length y && length x < 16
      then (sort . nub $ pp x y) == (sort . nub $ pairwisePerm x y)
      else True

pp :: [Int] -> [Int] -> [[Int]]
pp x y =
 let n = length x
 in map (\i ->
     map (\j -> ((x !! j) `times` not (testBit i j))
                  `plus`
                ((y !! j) `times` testBit i j)
          ) [0..(n-1)]
       ) [0 :: Int .. ((2^n)-1)]
    where times x True = x
          times x False = 0
          plus x y = x + y


variations :: [([[Int]], Syn.Multiplicity (Syn.Approximation Spatial))]
variations =
  [ ([ [1], [0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Forward 1 1 True]]))

  , ([ [absoluteRep,1], [absoluteRep,0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Forward 1 2 True]]))

  , ([ [1,1], [0,1], [1,0], [0,0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Forward 1 1 True, Forward 1 2 True]]))

  , ([ [-1, 1], [0, 1] ],
    Multiple $ Exact $ Spatial (Sum [Product [Backward 1 1 True, Forward 1 2 False]]))

  , ([ [-1], [0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Backward 1 1 True]]))

  , ([ [absoluteRep,-1], [absoluteRep,0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Backward 1 2 True]]))

  , ([ [-1,-1], [0,-1], [-1,0], [0,0] ],
    Multiple $ Exact $ Spatial (Sum [Product [Backward 1 1 True, Backward 1 2 True]]))

  , ( [ [0,-1], [1,-1], [0,0], [1,0], [1,1], [0,1], [2,-1], [2,0], [2,1] ],
    Multiple $ Exact $ Spatial
              (Sum [Product [ Forward 2 1 True, Centered 1 2 True ] ] ))

  , ( [ [-1,0], [-1,1], [0,0], [0,1], [1,1], [1,0], [-1,2], [0,2], [1,2] ],
    Multiple $ Exact $ Spatial
              (Sum [Product [ Forward 2 2 True, Centered 1 1 True ] ] ))
 ]

variations2 :: [( Syn.Multiplicity (Syn.Approximation [[Int]])
                , Int
                , Syn.Multiplicity (Syn.Approximation Spatial) )]
variations2 =
  [
  -- Stencil which has some absolute component (not represented in the spec)
    ( Multiple $ Exact [ [0, absoluteRep], [1, absoluteRep] ]
    , 2
    , Multiple $ Exact $ Spatial (Sum [Product [Forward 1 1 True]])
    )

 -- Spec on bounds
  , ( Multiple $ Bound Nothing (Just [ [0, absoluteRep], [1, absoluteRep]
                                     , [2, absoluteRep] ])
    , 2
    , Multiple $ Bound Nothing
        (Just $ Spatial (Sum [Product [Forward 2 1 True]]))
    )
  ]

variations3 :: [( Syn.Multiplicity (Syn.Approximation [[Int]])
                , Int
                , Syn.Multiplicity (Syn.Approximation Spatial) )]
variations3 =
  [
 -- Spec on bounds
    ( Multiple $
        Bound Nothing (Just  [ [0, absoluteRep, 0], [1, absoluteRep, 0]
                             , [2, absoluteRep, 0], [0, absoluteRep, 1]
                             , [1, absoluteRep, 1], [2, absoluteRep, 1]])
    , 3
    , Multiple $
        Bound Nothing (Just $ Spatial (Sum [Product [ Forward 1 3 True
                                                    , Forward 2 1 True ]]))
    )
  ]

modelHasLeftInverse = mapM_ check (zip variations [0..])
  where
    check ((ixs, spec), n) =
        it ("("++show n++")") $
          sort mdl `shouldBe` sort ixs
      where
        mdl = toList . fromExact . fromMult . model' $ spec
        model' = flip model $ length . head $ ixs

modelHasApproxLeftInverse vars = mapM_ check (zip vars [(0 :: Int)..])
  where
    check ((ixs, dims, spec), n) =
     it ("("++show n++")") $ mdl `shouldBe` fmap sort <$> ixs
     where
       mdl =
         let ?globalDimensionality = dims
         in fmap (sort . toList) <$> mkModel spec

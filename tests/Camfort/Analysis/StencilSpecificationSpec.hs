{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}

module Camfort.Analysis.StencilSpecificationSpec (spec) where

import Data.List

import Camfort.Helpers.Vec
import Camfort.Analysis.StencilSpecification
import Camfort.Analysis.StencilSpecification.Synthesis
import Camfort.Analysis.StencilSpecification.Model
import Camfort.Analysis.StencilSpecification.Inference
import Camfort.Analysis.StencilSpecification.Syntax hiding (Spec)
import Camfort.Analysis.Annotations
import qualified Language.Fortran.AST as F
import Language.Fortran.Util.Position

import Data.Map.Strict (toList)


import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck

spec :: Spec
spec =
  describe "Stencils" $ do
    describe "Idempotence of spanBounding" $ do
      it "(0)" $ property $ prop_spanBoundingIdem zeroN
      it "(1)" $ property $ prop_spanBoundingIdem oneN
      it "(2)" $ property $ prop_spanBoundingIdem twoN
      it "(3)" $ property $ prop_spanBoundingIdem threeN
      it "(4)" $ property $ prop_spanBoundingIdem fourN

    describe "Associativity of spanBounding" $ do
      it "(0)" $ property $ prop_spanBoundingAssoc zeroN
      it "(1)" $ property $ prop_spanBoundingAssoc oneN
      it "(2)" $ property $ prop_spanBoundingAssoc twoN
      it "(3)" $ property $ prop_spanBoundingAssoc threeN
      it "(4)" $ property $ prop_spanBoundingAssoc fourN

    describe "Un-permutable permutations on vectors" $ do
      it "(0)" $ property $ prop_perms_invertable zeroN
      it "(1)" $ property $ prop_perms_invertable oneN
      it "(2)" $ property $ prop_perms_invertable twoN
      it "(3)" $ property $ prop_perms_invertable threeN
      it "(4)" $ property $ prop_perms_invertable fourN

    it "sorting on indices" $
      shouldBe (sort [ Cons 1 (Cons 2 (Cons 1 Nil))
                      , Cons 2 (Cons 2 (Cons 3 Nil))
                      , Cons 1 (Cons 3 (Cons 3 Nil))
                      , Cons 0 (Cons 3 (Cons 1 Nil))
                      , Cons 1 (Cons 0 (Cons 2 Nil))
                      , Cons 1 (Cons 1 (Cons 1 Nil))
                      , Cons 2 (Cons 1 (Cons 1 Nil)) ])
                ([ Cons 1 (Cons 1 (Cons 1 Nil))
                , Cons 2 (Cons 1 (Cons 1 Nil))
                , Cons 1 (Cons 2 (Cons 1 Nil))
                , Cons 0 (Cons 3 (Cons 1 Nil))
                , Cons 1 (Cons 0 (Cons 2 Nil))
                , Cons 2 (Cons 2 (Cons 3 Nil))
                , Cons 1 (Cons 3 (Cons 3 Nil))
                ] :: [Vec (S (S (S Z))) Int])

    it "composeRegions (1,0)-(1,0) span and (2,0)-(2,0) span" $
      shouldBe (composeConsecutiveSpans
                  (Cons 1 (Cons 0 Nil), Cons 1 (Cons 0 Nil))
                  (Cons 2 (Cons 0 Nil), Cons 2 (Cons 0 Nil)))
               (Just (Cons 1 (Cons 0 Nil), Cons 2 (Cons 0 Nil)))

    it "composeRegions failing on (1,0)-(2,0) span and (4,0)-(5,0) span" $
      shouldBe (composeConsecutiveSpans
                  (Cons 1 (Cons 0 Nil), Cons 2 (Cons 0 Nil))
                  (Cons 4 (Cons 0 Nil), Cons 5 (Cons 0 Nil)))
               Nothing

    it "composeRegions failing on (1,0)-(2,0) span and (3,1)-(3,1) span" $
      shouldBe (composeConsecutiveSpans
                  (Cons 1 (Cons 0 Nil), Cons 2 (Cons 0 Nil))
                  (Cons 3 (Cons 1 Nil), Cons 3 (Cons 1 Nil)))
               Nothing

    it "five point stencil 2D" $
      -- Sort the expected value for the sake of easy equality
      shouldBe (inferMinimalVectorRegions fivepoint)
               (sort [ (Cons (-1) (Cons 0 Nil), Cons 1 (Cons 0 Nil))
                     , (Cons 0 (Cons (-1) Nil), Cons 0 (Cons 1 Nil)) ])

    it "seven point stencil 3D" $
      shouldBe
        (inferMinimalVectorRegions sevenpoint)
        (sort
           [ (Cons (-1) (Cons 0 (Cons 0 Nil)), Cons 1 (Cons 0 (Cons 0 Nil)))
           , (Cons 0 (Cons (-1) (Cons 0 Nil)), Cons 0 (Cons 1 (Cons 0 Nil)))
           , (Cons 0 (Cons 0 (Cons (-1) Nil)), Cons 0 (Cons 0 (Cons 1 Nil))) ])

    describe "Example stencil inferences" $ do
      it "five point stencil 2D" $
        (fromIndicesToSpec $ VL fivepoint)
        `shouldBe`
         (exactSp $ Spatial NonLinear [] [] (Sum [ Product [ Centered 1 1 ],
                                                 Product [ Centered 1 2 ]]))

      it "seven point stencil 2D" $
        (fromIndicesToSpec $ VL sevenpoint)
        `shouldBe`
          (exactSp $ Spatial NonLinear [] [] (Sum [ Product [ Centered 1 1 ],
                                                  Product [ Centered 1 2 ],
                                                  Product [ Centered 1 3 ]]))

      it "five point stencil 2D with blip" $
         (fromIndicesToSpec $ VL fivepointErr)
         `shouldBe`
          (exactSp $ Spatial NonLinear [] [] (Sum [ Product [ Forward 1 1 ,
                                                            Forward 1 2 ],
                                                  Product [ Centered 1 1 ],
                                                  Product [ Centered 1 2 ] ]))

      it "centered forward" $
         (fromIndicesToSpec $ VL centeredFwd)
         `shouldBe`
          (exactSp $ Spatial NonLinear [] [] (Sum [ Product [ Forward 1 1
                                                  , Centered 1 2 ] ]))
{-
    describe "Example bounding boxes" $ do
      it "five point stencil 2D" $
        (fromIndicesToSpec $ VL fivepoint)
        `shouldBe`
        (exactSp $ Spatial NonLinear [] [] (Sum [Product [Centered 1 1,
                                                        Centered 1 2]]))

      it "seven point stencil 2D" $
        (fromIndicesToSpec $ VL sevenpoint)
        `shouldBe`
        (exactSp $ Spatial NonLinear [] [] (Sum [Product [Centered 1 1,
                                                        Centered 1 2,
                                                        Centered 1 3]]))

      it "five point stencil 2D with blip" $
        (fromIndicesToSpec $ VL fivepointErr)
        `shouldBe`
        (exactSp $ Spatial NonLinear [] [] (Sum [Product [Centered 1 1,
                                                        Centered 1 2]]))

      it "centered forward" $
        (fromIndicesToSpec $ VL centeredFwd)
        `shouldBe`
        (exactSp $ Spatial NonLinear [] [] (Sum [ Product [ Forward 1 1
                                                        , Centered 1 2 ] ])) -}

    describe "2D stencil verification" $
      mapM_ test2DSpecVariation variations

    describe "3D stencil verification" $
      mapM_ test3DSpecVariation variations3D

    describe ("Synthesising indexing expressions from offsets is inverse to" ++
              "extracting offsets from indexing expressions; and vice versa") $
      it "isomorphism" $ property prop_extract_synth_inverse

exactSp = Exact . Specification . Left

{- Properties of `spanBoundingBox`: idempotent and associative -}
prop_spanBoundingIdem :: Natural n -> Span (Vec n Int) -> Bool
prop_spanBoundingIdem w x = spanBoundingBox x x == normaliseSpan x

prop_spanBoundingAssoc :: Natural n -> Span (Vec n Int)
                                    -> Span (Vec n Int)
                                    -> Span (Vec n Int) -> Bool
prop_spanBoundingAssoc w x y z =
  (==) (spanBoundingBox x (spanBoundingBox y z))
       (spanBoundingBox (spanBoundingBox x y) z)

{- Permutations that come with 'unpermute' functions are invertable -}
prop_perms_invertable :: (Permutable n) => Natural n -> Vec n Int -> Bool
prop_perms_invertable w xs =
  replicate (fact (lengthV xs)) xs == map (\(xs, f) -> f xs) (permutationsV xs)
  where
    fact 0 = 1
    fact n = n * fact (n - 1)

zeroN  = Zero
oneN   = Succ zeroN
twoN   = Succ oneN
threeN = Succ twoN
fourN  = Succ threeN

-- Indices for the 2D five point stencil (deliberately in an odd order)
fivepoint = [ Cons (-1) (Cons 0 Nil), Cons 0 (Cons (-1) Nil)
            , Cons 1 (Cons 0 Nil) , Cons 0 (Cons 1 Nil), Cons 0 (Cons 0 Nil)
            ]
-- Indices for the 3D seven point stencil
sevenpoint = [ Cons (-1) (Cons 0 (Cons 0 Nil)), Cons 0 (Cons (-1) (Cons 0 Nil))
             , Cons 0 (Cons 0 (Cons 1 Nil)), Cons 0 (Cons 1 (Cons 0 Nil))
             , Cons 1 (Cons 0 (Cons 0 Nil)), Cons 0 (Cons 0 (Cons (-1) Nil))
             , Cons 0 (Cons 0 (Cons 0 Nil))
             ]
centeredFwd = [ Cons 1 (Cons 0 Nil), Cons 0 (Cons 1 Nil), Cons 0 (Cons (-1) Nil)
              , Cons 1 (Cons 1 Nil), Cons 0 (Cons 0 Nil), Cons 1 (Cons (-1) Nil)
              ] :: [ Vec (S (S Z)) Int ]

-- Examples of unusal patterns
fivepointErr = [ Cons (-1) (Cons 0 Nil), Cons 0 (Cons (-1) Nil)
               , Cons 1 (Cons 0 Nil), Cons 0 (Cons 1 Nil), Cons 0 (Cons 0 Nil)
               , Cons 1 (Cons 1 Nil)
               ] :: [ Vec (S (S Z)) Int ]

{- Construct arbtirary vectors and test up to certain sizes -}
instance Arbitrary a => Arbitrary (Vec Z a) where
    arbitrary = return Nil

instance (Arbitrary (Vec n a), Arbitrary a) => Arbitrary (Vec (S n) a) where
    arbitrary = do x  <- arbitrary
                   xs <- arbitrary
                   return $ Cons x xs

test2DSpecVariation (input, expectation) =
    it ("format=" ++ show input) $ do

       -- Test inference
       (ixCollectionToSpec ["i", "j"] (map fromFormatToIx input))
          `shouldBe` Just [ expectedSpec ]
  where
    expectedSpec = fmap (Specification . Left) expectation
    fromFormatToIx [ri,rj] = [ offsetToIx "i" ri, offsetToIx "j" rj ]

variations =
  [ ( [ [0,0] ]
    , Exact $ Spatial NonLinear [] [ 1, 2 ] (Sum [Product []])
    )
  , ( [ [1,0], [0,0] ]
    , Exact $ Spatial NonLinear [] [2] (Sum [Product [Forward 1 1]])
    )
  , ( [ [0,1], [0,0] ]
    , Exact $ Spatial NonLinear [] [1] (Sum [Product [Forward 1 2]])
    )
  , ( [ [1,1], [0,1], [1,0], [0,0] ]
    , Exact $ Spatial NonLinear [] [] (Sum [Product [Forward 1 1, Forward 1 2]])
    )
  , ( [ [-1,0], [0,0] ]
    , Exact $ Spatial NonLinear [] [2] (Sum [Product [Backward 1 1]])
    )
  , ( [ [0,-1], [0,0] ]
    , Exact $ Spatial NonLinear [] [1] (Sum [Product [Backward 1 2]])
    )
  , ( [ [-1,-1], [0,-1], [-1,0], [0,0] ]
    , Exact $ Spatial NonLinear [] [] (Sum [Product [Backward 1 1, Backward 1 2]])
    )
  , ( [ [0,-1], [1,-1], [0,0], [1,0], [1,1], [0,1] ]
    , Exact $ Spatial NonLinear [] [] $ Sum [ Product [ Forward 1 1 , Centered 1 2 ] ]
    )
   -- Stencil which is non-contiguous in one direction
  , ( [ [0, 4], [1, 4] ]
    , Bound (Just (Spatial NonLinear [] [] (Sum [Product [Forward 1 1]])))
            (Just (Spatial NonLinear [] [] (Sum [Product [Forward 1 1, Forward 4 2]])))
    )
   -- Stencil which has non-relative indices in one dimension
  , ( [ [0, absoluteRep], [1, absoluteRep] ]
    , Exact $ Spatial NonLinear [] [] (Sum [Product [Forward 1 1]])
    )
  ]

test3DSpecVariation (input, expectation) =
    it ("format=" ++ show input) $ do

      -- Test inference
      (ixCollectionToSpec ["i", "j", "k"] (map fromFormatToIx input))
           `shouldBe` Just [ expectedSpec ]

  where
    expectedSpec = fmap (Specification . Left) expectation
    fromFormatToIx [ri,rj,rk] =
      [offsetToIx "i" ri, offsetToIx "j" rj, offsetToIx "k" rk]


variations3D =
  [ ( [ [-1,0,-1], [0,0,-1], [-1,0,0], [0,0,0] ]
    ,  Exact $ Spatial NonLinear [] [2] (Sum [Product [Backward 1 1, Backward 1 3]])
    )
  , ( [ [1,1,0], [0,1,0] ]
    ,  Exact $ Spatial NonLinear [2] [3] (Sum [Product [Forward 1 1, Forward 1 2]])
    )
  , ( [ [-1,absoluteRep,-1], [0,absoluteRep,-1], [-1,absoluteRep,0], [0,absoluteRep,0] ]
    ,  Exact $ Spatial NonLinear [] [] (Sum [Product [Backward 1 1, Backward 1 3]])
    )
  ]

prop_extract_synth_inverse :: F.Name -> Int -> Bool
prop_extract_synth_inverse v o =
     ixToOffset [v] (offsetToIx v o) == Just o
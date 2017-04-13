{-# LANGUAGE DataKinds #-}

module Camfort.Specification.Stencils.LatticeModelSpec (spec) where

import Algebra.Lattice
import qualified Data.Set as S
import Data.List.NonEmpty
import qualified Camfort.Helpers.Vec as V

import Camfort.Specification.Stencils.LatticeModel

import Test.Hspec

spec :: Spec
spec =
  describe "Model spec" $ do
    describe "ioCompare" $ do
      let reg1 =
            return (V.Cons (IntervHoled 0 2 False) (V.Cons (IntervHoled 0 2 False) V.Nil))
            \/
            return (V.Cons (IntervHoled 0 1 True) (V.Cons (IntervHoled 0 2 False) V.Nil))
      let reg2 = return $ V.Cons (IntervHoled 0 2 True) (V.Cons (IntervHoled 0 2 False) V.Nil)
      res <- runIO $ ioCompare reg1 reg2

      it "compares equal regions" $
        res `shouldBe` EQ

      let reg3 =
            reg2 \/ return (V.Cons (IntervHoled 0 3 False) (V.Cons (IntervHoled 0 0 True) V.Nil))
      res <- runIO $ ioCompare reg3 reg2
      it "compares greater regions" $
        res `shouldBe` GT

      let reg4 = reg1 \/ return (V.Cons IntervInfinite $ V.Cons IntervInfinite V.Nil)
      res <- runIO $ ioCompare reg3 reg4
      it "compares smaller regions" $
        res `shouldBe` LT

      let prod1 = return $ V.Cons (Offsets . S.fromList $ [2,3,5])
                                  (V.Cons (Offsets . S.fromList $ [10, 15]) V.Nil)
      let prod2 = return $ V.Cons (Offsets . S.fromList $ [2,3,4,5])
                                  (V.Cons (Offsets . S.fromList $ [10, 12, 15]) V.Nil)
      res <- runIO $ ioCompare prod1 prod2
      it "compare equal offset products" $
        res `shouldBe` LT

      let prod3 = prod1 \/
                  return (V.Cons (Offsets . S.fromList $ [ 4 ])
                                 (V.Cons (Offsets . S.fromList $ [ 10, 12, 15 ]) V.Nil))
                         \/
                  return (V.Cons (Offsets . S.fromList $ [ 2, 3, 4, 5 ])
                                 (V.Cons (Offsets . S.fromList $ [ 12 ]) V.Nil))
      res <- runIO $ ioCompare prod3 prod2
      it "compare equal offset products" $
        res `shouldBe` EQ

      let regBack = return $
            V.Cons (IntervHoled (-1) 0 True) (V.Cons IntervInfinite V.Nil)
      let off = return $
            V.Cons (Offsets . S.fromList $ [-1, 0]) (V.Cons SetOfIntegers V.Nil)
      res <- runIO $ ioCompare regBack off
      it "compare equal offset and interval" $
        res `shouldBe` EQ

      let regFivePoint =
            return (V.Cons (IntervHoled (-1) 1 True)
                           (V.Cons (IntervHoled 0 0 True) V.Nil))
            \/
            return (V.Cons (IntervHoled 0 0 True)
                           (V.Cons (IntervHoled (-1) 1 True) V.Nil))
      let offFivePoint =
            return (V.Cons (Offsets . S.fromList $ [-1])
                           (V.Cons (Offsets . S.fromList $ [0]) V.Nil))
            \/
            return (V.Cons (Offsets . S.fromList $ [0])
                           (V.Cons (Offsets . S.fromList $ [0]) V.Nil))
            \/
            return (V.Cons (Offsets . S.fromList $ [1])
                           (V.Cons (Offsets . S.fromList $ [0]) V.Nil))
            \/
            return (V.Cons (Offsets . S.fromList $ [0])
                           (V.Cons (Offsets . S.fromList $ [-1]) V.Nil))
            \/
            return (V.Cons (Offsets . S.fromList $ [0])
                           (V.Cons (Offsets . S.fromList $ [1]) V.Nil))
      res <- runIO $ ioCompare regFivePoint offFivePoint
      it "compare equal offset and interval" $
        res `shouldBe` EQ

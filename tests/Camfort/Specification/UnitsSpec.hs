{-# LANGUAGE ImplicitParams #-}
module Camfort.Specification.UnitsSpec (spec) where

import qualified Data.ByteString.Char8 as B

import Language.Fortran.Parser.Any
import qualified Language.Fortran.Analysis as FA
import qualified Language.Fortran.Analysis.Renaming as FAR
import Camfort.Input
import Camfort.Functionality
import Camfort.Output
import Camfort.Analysis.Annotations
import Camfort.Specification.Units
import Camfort.Specification.Units.Monad
import Camfort.Specification.Units.InferenceFrontend
import Camfort.Specification.Units.InferenceBackend
import Camfort.Specification.Units.Environment
import Data.List
import Data.Maybe
import Data.Either
import qualified Data.Array as A
import qualified Numeric.LinearAlgebra as H
import qualified Data.Map.Strict as M
import Numeric.LinearAlgebra (
    atIndex, (<>), (><), rank, (?), toLists, toList, fromLists, fromList, rows, cols,
    takeRows, takeColumns, dropRows, dropColumns, subMatrix, diag, build, fromBlocks,
    ident, flatten, lu, dispf, Matrix
  )

import Test.Hspec
import Test.QuickCheck
import Test.Hspec.QuickCheck

runFrontendInit litMode pf = usConstraints state
  where
    pf' = FA.initAnalysis . fmap mkUnitAnnotation . fmap (const unitAnnotation) $ pf
    uOpts = unitOpts0 { uoNameMap = M.empty, uoDebug = False, uoLiterals = litMode }
    (_, state, logs) = runUnitSolver uOpts pf' initInference

runUnits litMode pf m = (r, usConstraints state)
  where
    pf' = FA.initAnalysis . fmap mkUnitAnnotation . fmap (const unitAnnotation) $ pf
    uOpts = unitOpts0 { uoNameMap = M.empty, uoDebug = False, uoLiterals = litMode }
    (r, state, logs) = runUnitSolver uOpts pf' $ initInference >> m

runUnits' litMode pf m = (state, logs)
  where
    pf' = FA.initAnalysis . fmap mkUnitAnnotation . fmap (const unitAnnotation) $ pf
    uOpts = unitOpts0 { uoNameMap = M.empty, uoDebug = True, uoLiterals = litMode }
    (r, state, logs) = runUnitSolver uOpts pf' $ initInference >> m

runUnitsRenamed' litMode pf m = (state, logs)
  where
    pf' = FAR.analyseRenames . FA.initAnalysis . fmap mkUnitAnnotation . fmap (const unitAnnotation) $ pf
    uOpts = unitOpts0 { uoNameMap = FAR.extractNameMap pf', uoDebug = True, uoLiterals = litMode }
    (r, state, logs) = runUnitSolver uOpts pf' $ initInference >> m

spec :: Spec
spec = do
  describe "Unit Inference Frontend" $ do
    describe "Literal Mode" $ do
      it "litTest1 Mixed" $ do
        head (fromJust (head (rights [fst (runUnits LitMixed litTest1 runInconsistentConstraints)]))) `shouldSatisfy`
          conParamEq (ConEq (UnitName "a") (UnitMul (UnitName "a") (UnitVar ("j", "j"))))
      it "litTest1 Poly" $ do
        head (fromJust (head (rights [fst (runUnits LitPoly litTest1 runInconsistentConstraints)]))) `shouldSatisfy`
          conParamEq (ConEq (UnitName "a") (UnitMul (UnitName "a") (UnitVar ("j", "j"))))
      it "litTest1 Unitless" $ do
        head (fromJust (head (rights [fst (runUnits LitUnitless litTest1 runInconsistentConstraints)]))) `shouldSatisfy`
          conParamEq (ConEq (UnitName "a") (UnitVar ("k", "k")))
    describe "Polymorphic functions" $ do
      it "squarePoly1" $ do
        show (sort (head (rights [fst (runUnits LitMixed squarePoly1 runInferVariables)]))) `shouldBe`
          show (sort [(("a", "a"),UnitName "m"),(("b", "b"), UnitName "s"),(("x", "x"),UnitPow (UnitName "m") 2.0),(("y", "y"),UnitPow (UnitName "s") 2.0)])
    describe "Recursive functions" $ do
      it "Recursive Addition is OK" $ do
        show (sort (head (rights [fst (runUnits LitMixed recursive1 runInferVariables)]))) `shouldBe`
          show (sort [(("y", "y"),UnitName "m"),(("z", "z"), UnitName "m")])
    describe "Recursive functions" $ do
      it "Recursive Multiplication is not OK" $ do
        head (fromJust (head (rights [fst (runUnits LitMixed recursive2 runInconsistentConstraints)]))) `shouldSatisfy`
          conParamEq (ConEq (UnitParamPosAbs ("recur", 0)) (UnitParamPosAbs ("recur", 2)))

  describe "Unit Inference Backend" $ do
    describe "Flatten constraints" $ do
      it "testCons1" $ do
        flattenConstraints testCons1 `shouldBe` testCons1_flattened
    describe "Shift terms" $ do
      it "testCons1" $ do
        map shiftTerms (flattenConstraints testCons1) `shouldBe` testCons1_shifted
      it "testCons2" $ do
        map shiftTerms (flattenConstraints testCons2) `shouldBe` testCons2_shifted
      it "testCons3" $ do
        map shiftTerms (flattenConstraints testCons3) `shouldBe` testCons3_shifted
    describe "Consistency" $ do
      it "testCons1" $ do
        inconsistentConstraints testCons1 `shouldBe` Just [ConEq (UnitName "kg") (UnitName "m")]
      it "testCons2" $ do
        inconsistentConstraints testCons2 `shouldBe` Nothing
      it "testCons3" $ do
        inconsistentConstraints testCons3 `shouldBe` Nothing
    describe "Critical Variables" $ do
      it "testCons2" $ do
        criticalVariables testCons2 `shouldSatisfy` null
      it "testCons3" $ do
        criticalVariables testCons3 `shouldBe` [UnitVar ("c", "c"), UnitVar ("e", "e")]
      it "testCons4" $ do
        criticalVariables testCons4 `shouldBe` [UnitVar ("simple2_a22", "simple2_a22")]
      it "testCons5" $ do
        criticalVariables testCons5 `shouldSatisfy` null
    describe "Infer Variables" $ do
      it "testCons5" $ do
        inferVariables testCons5 `shouldBe` testCons5_infer

--------------------------------------------------

testCons1 = [ ConEq (UnitName "kg") (UnitName "m")
            , ConEq (UnitVar ("x", "x")) (UnitName "m")
            , ConEq (UnitVar ("y", "y")) (UnitName "kg")]

testCons1_flattened = [([UnitPow (UnitName "kg") 1.0],[UnitPow (UnitName "m") 1.0])
                      ,([UnitPow (UnitVar ("x", "x")) 1.0],[UnitPow (UnitName "m") 1.0])
                      ,([UnitPow (UnitVar ("y", "y")) 1.0],[UnitPow (UnitName "kg") 1.0])]

testCons1_shifted = [([],[UnitPow (UnitName "m") 1.0,UnitPow (UnitName "kg") (-1.0)])
                    ,([UnitPow (UnitVar ("x", "x")) 1.0],[UnitPow (UnitName "m") 1.0])
                    ,([UnitPow (UnitVar ("y", "y")) 1.0],[UnitPow (UnitName "kg") 1.0])]

--------------------------------------------------

testCons2 = [ConEq (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-1.0))) (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-1.0)))
            ,ConEq (UnitName "m") (UnitMul (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-1.0))) (UnitName "s"))
            ,ConEq (UnitAlias "accel") (UnitMul (UnitName "m") (UnitPow (UnitParamPosUse ("simple1_sqr6",0,0)) (-1.0)))
            ,ConEq (UnitName "s") (UnitParamPosUse ("simple1_sqr6",1,0))
            ,ConEq (UnitVar ("simple1_a5", "simple1_a5")) (UnitAlias "accel")
            ,ConEq (UnitVar ("simple1_t4", "simple1_t4")) (UnitName "s")
            ,ConEq (UnitVar ("simple1_v3", "simple1_v3")) (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-1.0)))
            ,ConEq (UnitVar ("simple1_x1", "simple1_x1")) (UnitName "m")
            ,ConEq (UnitVar ("simple1_y2", "simple1_y2")) (UnitName "m")
            ,ConEq (UnitParamPosUse ("simple1_sqr6",0,0)) (UnitParamPosUse ("simple1_mul7",0,1))
            ,ConEq (UnitParamPosUse ("simple1_sqr6",1,0)) (UnitParamPosUse ("simple1_mul7",1,1))
            ,ConEq (UnitParamPosUse ("simple1_sqr6",1,0)) (UnitParamPosUse ("simple1_mul7",2,1))
            ,ConEq (UnitParamPosUse ("simple1_mul7",0,1)) (UnitMul (UnitParamPosUse ("simple1_mul7",1,1)) (UnitParamPosUse ("simple1_mul7",2,1)))
            ,ConEq (UnitAlias "accel") (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-2.0)))]

testCons2_shifted = [([],[UnitPow (UnitName "m") 1.0,UnitPow (UnitName "s") (-1.0),UnitPow (UnitName "m") (-1.0),UnitPow (UnitName "s") 1.0])
                    ,([],[UnitPow (UnitName "m") 1.0,UnitPow (UnitName "m") (-1.0)])
                    ,([UnitPow (UnitAlias "accel") 1.0,UnitPow (UnitParamPosUse ("simple1_sqr6",0,0)) 1.0],[UnitPow (UnitName "m") 1.0])
                    ,([UnitPow (UnitParamPosUse ("simple1_sqr6",1,0)) (-1.0)],[UnitPow (UnitName "s") (-1.0)])
                    ,([UnitPow (UnitVar ("simple1_a5", "simple1_a5")) 1.0,UnitPow (UnitAlias "accel") (-1.0)],[])
                    ,([UnitPow (UnitVar ("simple1_t4", "simple1_t4")) 1.0],[UnitPow (UnitName "s") 1.0])
                    ,([UnitPow (UnitVar ("simple1_v3", "simple1_v3")) 1.0],[UnitPow (UnitName "m") 1.0,UnitPow (UnitName "s") (-1.0)])
                    ,([UnitPow (UnitVar ("simple1_x1", "simple1_x1")) 1.0],[UnitPow (UnitName "m") 1.0])
                    ,([UnitPow (UnitVar ("simple1_y2", "simple1_y2")) 1.0],[UnitPow (UnitName "m") 1.0])
                    ,([UnitPow (UnitParamPosUse ("simple1_sqr6",0,0)) 1.0,UnitPow (UnitParamPosUse ("simple1_mul7",0,1)) (-1.0)],[])
                    ,([UnitPow (UnitParamPosUse ("simple1_sqr6",1,0)) 1.0,UnitPow (UnitParamPosUse ("simple1_mul7",1,1)) (-1.0)],[])
                    ,([UnitPow (UnitParamPosUse ("simple1_sqr6",1,0)) 1.0,UnitPow (UnitParamPosUse ("simple1_mul7",2,1)) (-1.0)],[])
                    ,([UnitPow (UnitParamPosUse ("simple1_mul7",0,1)) 1.0,UnitPow (UnitParamPosUse ("simple1_mul7",1,1)) (-1.0),UnitPow (UnitParamPosUse ("simple1_mul7",2,1)) (-1.0)],[])
                    ,([UnitPow (UnitAlias "accel") 1.0],[UnitPow (UnitName "m") 1.0,UnitPow (UnitName "s") (-2.0)])]

testCons3 = [ ConEq (UnitVar ("a", "a")) (UnitVar ("e", "e"))
            , ConEq (UnitVar ("a", "a")) (UnitMul (UnitVar ("b", "b")) (UnitMul (UnitVar ("c", "c")) (UnitVar ("d", "d"))))
            , ConEq (UnitVar ("d", "d")) (UnitName "m") ]

testCons3_shifted = [([UnitPow (UnitVar ("a", "a")) 1.0,UnitPow (UnitVar ("e", "e")) (-1.0)],[])
                    ,([UnitPow (UnitVar ("a", "a")) 1.0,UnitPow (UnitVar ("b", "b")) (-1.0),UnitPow (UnitVar ("c", "c")) (-1.0),UnitPow (UnitVar ("d", "d")) (-1.0)],[])
                    ,([UnitPow (UnitVar ("d", "d")) 1.0],[UnitPow (UnitName "m") 1.0])]

testCons4 = [ConEq (UnitVar ("simple2_a11", "simple2_a11")) (UnitParamPosUse ("simple2_sqr3",0,0))
            ,ConEq (UnitVar ("simple2_a22", "simple2_a22")) (UnitParamPosUse ("simple2_sqr3",1,0))
            ,ConEq (UnitVar ("simple2_a11", "simple2_a11")) (UnitVar ("simple2_a11", "simple2_a11"))
            ,ConEq (UnitVar ("simple2_a22", "simple2_a22")) (UnitVar ("simple2_a22", "simple2_a22"))
            ,ConEq (UnitParamPosUse ("simple2_sqr3",0,0)) (UnitMul (UnitParamPosUse ("simple2_sqr3",1,0)) (UnitParamPosUse ("simple2_sqr3",1,0)))]

testCons5 = [ConEq (UnitVar ("simple2_a11", "simple2_a11")) (UnitParamPosUse ("simple2_sqr3",0,0))
            ,ConEq (UnitAlias "accel") (UnitParamPosUse ("simple2_sqr3",1,0))
            ,ConEq (UnitVar ("simple2_a11", "simple2_a11")) (UnitVar ("simple2_a11", "simple2_a11"))
            ,ConEq (UnitVar ("simple2_a22", "simple2_a22")) (UnitAlias "accel")
            ,ConEq (UnitParamPosUse ("simple2_sqr3",0,0)) (UnitMul (UnitParamPosUse ("simple2_sqr3",1,0)) (UnitParamPosUse ("simple2_sqr3",1,0)))
            ,ConEq (UnitAlias "accel") (UnitMul (UnitName "m") (UnitPow (UnitName "s") (-2.0)))]

testCons5_infer = [(("simple2_a11", "simple2_a11"),UnitMul (UnitPow (UnitName "m") 2.0) (UnitPow (UnitName "s") (-4.0)))
                  ,(("simple2_a22", "simple2_a22"),UnitMul (UnitPow (UnitName "m") 1.0) (UnitPow (UnitName "s") (-2.0)))]

--------------------------------------------------

litTest1 = flip fortranParser "litTest1.f90" . B.pack $ unlines
    [ "program main"
    , "  != unit(a) :: x"
    , "  real :: x, j, k"
    , ""
    , "  j = 1 + 1"
    , "  k = j * j"
    , "  x = x + k"
    , "  x = x * j ! inconsistent"
    , "end program main" ]

squarePoly1 = flip fortranParser "squarePoly1.f90" . B.pack $ unlines
    [ "! Demonstrates parametric polymorphism through functions-calling-functions."
    , "program squarePoly"
    , "  implicit none"
    , "  real :: x"
    , "  real :: y"
    , "  != unit(m) :: a"
    , "  real :: a"
    , "  != unit(s) :: b"
    , "  real :: b"
    , "  x = squareP(a)"
    , "  y = squareP(b)"
    , "  contains"
    , "  real function square(n)"
    , "    real :: n"
    , "    square = n * n"
    , "  end function"
    , "  real function squareP(m)"
    , "    real :: m"
    , "    squareP = square(m)"
    , "  end function"
    , "end program" ]

recursive1 = flip fortranParser "recursive1.f90" . B.pack $ unlines
    [ "program main"
    , "  != unit(m) :: y"
    , "  integer :: x = 5, y = 2, z"
    , "  z = recur(x,y)"
    , "  print *, y"
    , "contains"
    , "  real recursive function recur(n, b) result(r)"
    , "    integer :: n, b"
    , "    if (n .EQ. 0) then"
    , "       r = b"
    , "    else"
    , "       r = b + recur(n - 1, b)"
    , "    end if"
    , "  end function recur"
    , "end program main" ]

recursive2 = flip fortranParser "recursive2.f90" . B.pack $ unlines
    [ "program main"
    , "  != unit(m) :: y"
    , "  integer :: x = 5, y = 2, z"
    , "  z = recur(x,y)"
    , "  print *, y"
    , "contains"
    , "  real recursive function recur(n, b) result(r)"
    , "    integer :: n, b"
    , "    if (n .EQ. 0) then"
    , "       r = b"
    , "    else"
    , "       r = b * recur(n - 1, b) ! inconsistent"
    , "    end if"
    , "  end function recur"
    , "end program main" ]

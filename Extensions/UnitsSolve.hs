{-# LANGUAGE ImplicitParams, BangPatterns #-}

module Extensions.UnitsSolve where

import Data.List
import Data.Matrix
import qualified Data.Vector as V
import Control.Exception
import System.IO.Unsafe
import qualified Debug.Trace as D


import Language.Fortran
import Extensions.UnitsEnvironment

-- Top-level, select the solver
solveSystem :: (?solver :: Solver) => LinearSystem -> Consistency LinearSystem
solveSystem = case ?solver of
--                  LAPACK -> solveSystemL
                  Custom -> solveSystemC
                  
--------------------------------------------------
-- CUSTOM SOLVER
--------------------------------------------------

-- Top-level custom solver
solveSystemC :: LinearSystem -> Consistency LinearSystem
solveSystemC system = solveSystem' system 1 1

solveSystem' :: LinearSystem -> Col -> Row -> Consistency LinearSystem
solveSystem' (matrix, vector) m k
  | m > ncols matrix = efmap (cutSystem k) $ checkSystem (matrix, vector) k
  | otherwise = elimRow (matrix, vector) n m k
                where n = find (\n -> matrix ! (n, m) /= 0) [k .. nrows matrix]

cutSystem :: Int -> LinearSystem -> LinearSystem
cutSystem k (matrix, vector) = (matrix', vector')
  where matrix' = submatrix 1 (k - 1) 1 (ncols matrix) matrix
        vector' = take (k - 1) vector

checkSystem :: LinearSystem -> Row -> Consistency LinearSystem
checkSystem (matrix, vector) k
  | k > nrows matrix = Ok (matrix, vector)
  | vector !! (k - 1) /= Unitful [] = let vars = V.toList $ getRow k matrix 
                                          bad = Bad (matrix, vector) k (vector !! (k - 1), vars)
                                      in bad
  | otherwise = checkSystem (matrix, vector) (k + 1)

elimRow :: LinearSystem -> Maybe Row -> Col -> Row -> Consistency LinearSystem
elimRow system Nothing m k = solveSystem' system (m + 1) k
elimRow (matrix, vector) (Just n) m k = -- (show (m, k)) `D.trace`
 solveSystem' system' (m + 1) (k + 1)
  where matrix' = let s = matrix ! (n, m) in 
                    (if (k == n) then id else switchRows k n)
                       (if s == 1 then matrix else scaleRow (recip $ s) n matrix)
        vector' = switchScaleElems k n (fromRational $ recip $ matrix ! (n, m)) vector
        system' = elimRow' (matrix', vector') k m

msteeper matrix k m = msteep matrix 1 
                       where
                         r = nrows matrix
                         msteep matrix n | n > r = matrix
                                         | n == k = msteep matrix (n+1)
                                         | otherwise = let s = (- matrix ! (n, m)) 
                                                       in if s == 0 then msteep matrix (n+1)
                                                          else msteep (combineRows n s k matrix) (n+1)

elimRow' :: LinearSystem -> Row -> Col -> LinearSystem
elimRow' (matrix, vector) k m = (matrix', vector')
  where mstep matrix n = let s = (- matrix ! (n, m)) in if s == 0 then matrix else combineRows n s k matrix 
        matrix' = foldl mstep matrix $ [1 .. k - 1] ++ [k + 1 .. nrows matrix]
        --matrix' = msteeper matrix k m
        vector'' = [x - fromRational (matrix ! (n, m)) * vector !! (k - 1) | (n, x) <- zip [1..] vector]
        (a, _ : b) = splitAt (k - 1) vector''
        vector' = a ++ vector !! (k - 1) : b

switchScaleElems :: Num a => Int -> Int -> a -> [a] -> [a]
switchScaleElems i j factor list = a ++ factor * b : c
  where (lj, b:rj) = splitAt (j - 1) list
        (a, _:c) = splitAt (i - 1) (lj ++ list !! (i - 1) : rj)

--------------------------------------------------
-- Top-level custom solver based on HMatrix
solveSystemH :: LinearSystem -> Consistency LinearSystem
solveSystemH system@(m,v) = D.trace ("Input:\n" ++ show m' ++ "\nv=" ++ show v) $
                            Ok (f sys')
  where
    (m', units) = convertToHMatrix system
    m2 = rref m'
    m3 = takeRows (rank m2) m2
    sys' = convertFromHMatrix (m3, units)
    f sys@(m, v) = D.trace ("Ok:\n" ++ dispf 1 m3 ++ "\nv=" ++ show v) $ sys

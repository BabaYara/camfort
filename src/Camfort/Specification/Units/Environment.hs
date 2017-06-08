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
{-# LANGUAGE DeriveDataTypeable, DeriveGeneric, PatternGuards #-}


{- Provides various data types and type class instances for the Units extension -}

module Camfort.Specification.Units.Environment where

import Control.Monad.State.Strict hiding (gets)

import qualified Language.Fortran.AST as F
import qualified Language.Fortran.Analysis as FA
import qualified Language.Fortran.Util.Position as FU

import qualified Camfort.Specification.Units.Parser as P

import Data.Char
import Data.Data
import Data.List
import Data.Matrix
import Data.Ratio
import Data.Binary
import GHC.Generics (Generic)
import qualified Debug.Trace as D

import Camfort.Helpers (SourceText)
import qualified Data.ByteString.Char8 as B

import Text.Printf

-- | A (unique name, source name) variable
type VV = (F.Name, F.Name)

type UniqueId = Int

-- | Description of the unit of an expression.
data UnitInfo
  = UnitParamPosAbs (String, Int)         -- an abstract parameter identified by PU name and argument position
  | UnitParamPosUse (String, Int, Int)    -- identify particular instantiation of parameters
  | UnitParamVarAbs (String, VV)          -- an abstract parameter identified by PU name and variable name
  | UnitParamVarUse (String, VV, Int)     -- a particular instantiation of above
  | UnitParamLitAbs UniqueId              -- a literal with abstract, polymorphic units, uniquely identified
  | UnitParamLitUse (UniqueId, Int)       -- a particular instantiation of a polymorphic literal
  | UnitParamEAPAbs VV                    -- an abstract Explicitly Annotated Polymorphic unit variable
  | UnitParamEAPUse (VV, Int)             -- a particular instantiation of an Explicitly Annotated Polymorphic unit variable
  | UnitLiteral Int                       -- literal with undetermined but uniquely identified units
  | UnitlessLit                           -- a unitless literal
  | UnitlessVar                           -- a unitless variable
  | UnitName String                       -- a basic unit
  | UnitAlias String                      -- the name of a unit alias
  | UnitVar VV                            -- variable with undetermined units: (unique name, source name)
  | UnitMul UnitInfo UnitInfo             -- two units multiplied
  | UnitPow UnitInfo Double               -- a unit raised to a constant power
  | UnitRecord [(String, UnitInfo)]       -- 'record'-type of units
  deriving (Eq, Ord, Data, Typeable, Generic)

instance Binary UnitInfo

instance Show UnitInfo where
  show u = case u of
    UnitParamPosAbs (f, i)         -> printf "#<ParamPosAbs %s[%d]>" f i
    UnitParamPosUse (f, i, j)      -> printf "#<ParamPosUse %s[%d] callId=%d>" f i j
    UnitParamVarAbs (f, (v, _))    -> printf "#<ParamVarAbs %s.%s>" f v
    UnitParamVarUse (f, (v, _), j) -> printf "#<ParamVarUse %s.%s callId=%d>" f v j
    UnitParamLitAbs i              -> printf "#<ParamLitAbs litId=%d>" i
    UnitParamLitUse (i, j)         -> printf "#<ParamLitUse litId=%d callId=%d]>" i j
    UnitParamEAPAbs (v, _)         -> v
    UnitParamEAPUse ((v, _), i)    -> printf "#<ParamEAPUse %s callId=%d]>" v i
    UnitLiteral i                  -> printf "#<Literal id=%d>" i
    UnitlessLit                    -> "1"
    UnitlessVar                    -> "1"
    UnitName name                  -> name
    UnitAlias name                 -> name
    UnitVar (vName, _)             -> printf "#<Var %s>" vName
    UnitRecord recs                -> "record (" ++ intercalate ", " (map (\ (n, u) -> n ++ " :: " ++ show u) recs) ++ ")"
    UnitMul u1 (UnitPow u2 k)
      | k < 0                      -> maybeParen u1 ++ " / " ++ maybeParen (UnitPow u2 (-k))
    UnitMul u1 u2                  -> maybeParenS u1 ++ " " ++ maybeParenS u2
    UnitPow u 1                    -> show u
    UnitPow u 0                    -> "1"
    UnitPow u k                    -> -- printf "%s**%f" (maybeParen u) k
      case doubleToRationalSubset k of
          Just r
            | e <- showRational r
            , e /= "1"  -> printf "%s**%s" (maybeParen u) e
            | otherwise -> show u
          Nothing -> error $
                      printf "Irrational unit exponent: %s**%f" (maybeParen u) k
       where showRational r
               | r < 0     = printf "(%s)" (showRational' r)
               | otherwise = showRational' r
             showRational' r
               | denominator r == 1 = show (numerator r)
               | otherwise = printf "(%d / %d)" (numerator r) (denominator r)
    where
      maybeParen x | all isAlphaNum s = s
                   | otherwise        = "(" ++ s ++ ")"
        where s = show x
      maybeParenS x | all isUnitMulOk s = s
                    | otherwise         = "(" ++ s ++ ")"
        where s = show x
      isUnitMulOk c = isSpace c || isAlphaNum c || c `elem` "*."

-- Converts doubles to a rational that can be expressed
-- as a rational with denominator at most 10
-- otherwise Noting
doubleToRationalSubset :: Double -> Maybe Rational
doubleToRationalSubset x | x < 0 =
    doubleToRationalSubset (abs x) >>= (\x -> return (-x))
doubleToRationalSubset x =
    doubleToRational' 0 1 (ceiling x) 1
  where
    -- The maximum common denominator, controls granularity
    n = 16
    doubleToRational' a b c d
         | b <= n && d <= n =
           let mediant = (fromIntegral (a+c))/(fromIntegral (b+d))
           in if x == mediant
              then if b + d <= n
                   then Just $ (a + c) % (b + d)
                   else Nothing
              else if x > mediant
                   then doubleToRational' (a+c) (b+d) c d
                   else doubleToRational' a b (a+c) (b+d)
         | b > n     = Just $ c % d
         | otherwise = Just $ a % b

-- | A relation between UnitInfos
data Constraint
  = ConEq   UnitInfo UnitInfo        -- an equality constraint
  | ConConj [Constraint]             -- conjunction of constraints
  deriving (Eq, Ord, Data, Typeable, Generic)

instance Binary Constraint

type Constraints = [Constraint]

instance Show Constraint where
  show (ConEq u1 u2) = show u1 ++ " === " ++ show u2
  show (ConConj cs) = intercalate " && " (map show cs)

isVarUnit (UnitVar _)         = True
isVarUnit (UnitParamVarUse _) = True
isVarUnit _                   = False

isUnresolvedUnit (UnitVar _)         = True
isUnresolvedUnit (UnitParamVarUse _) = True
isUnresolvedUnit (UnitParamVarAbs _) = True
isUnresolvedUnit (UnitParamPosUse _) = True
isUnresolvedUnit (UnitParamPosAbs _) = True
isUnresolvedUnit (UnitParamLitUse _) = True
isUnresolvedUnit (UnitParamLitAbs _) = True
isUnresolvedUnit (UnitParamEAPAbs _) = True
isUnresolvedUnit (UnitParamEAPUse _) = True
isUnresolvedUnit (UnitPow u _)       = isUnresolvedUnit u
isUnresolvedUnit (UnitMul u1 u2)     = isUnresolvedUnit u1 || isUnresolvedUnit u2
isUnresolvedUnit _                   = False

isResolvedUnit = not . isUnresolvedUnit

isConcreteUnit :: UnitInfo -> Bool
isConcreteUnit (UnitPow u _) = isConcreteUnit u
isConcreteUnit (UnitMul u v) = isConcreteUnit u && isConcreteUnit v
isConcreteUnit (UnitAlias _) = True
isConcreteUnit UnitlessLit = True
isConcreteUnit (UnitName _) = True
isConcreteUnit _ = False

pprintConstr :: Maybe SourceText -> Constraint -> String
pprintConstr srcText (ConEq u1 u2)
  | isResolvedUnit u1 && isConcreteUnit u1 &&
    isResolvedUnit u2 && isConcreteUnit u2 =
      "Units '" ++ pprintUnitInfo srcText u1 ++ "' and '" ++ pprintUnitInfo srcText u2 ++
      "' are inconsistent"
  | isResolvedUnit u1 = "'" ++ pprintUnitInfo srcText u2 ++ "' should have unit '" ++ pprintUnitInfo srcText u1 ++ "'"
  | isResolvedUnit u2 = "'" ++ pprintUnitInfo srcText u1 ++ "' should have unit '" ++ pprintUnitInfo srcText u2 ++ "'"
pprintConstr srcText (ConEq u1 u2) = "'" ++ pprintUnitInfo srcText u1 ++ "' should have the same units as '" ++ pprintUnitInfo srcText u2 ++ "'"
pprintConstr srcText (ConConj cs)  = intercalate "\n\t and " (map (pprintConstr srcText) cs)

pprintUnitInfo :: Maybe SourceText -> UnitInfo -> String
pprintUnitInfo _ (UnitVar (_, sName)) = printf "%s" sName
pprintUnitInfo _ (UnitParamVarUse (_, (_, sName), _)) = printf "%s" sName
pprintUnitInfo _ (UnitParamPosUse (fname, 0, _)) = printf "result of %s" fname
pprintUnitInfo _ (UnitParamPosUse (fname, i, _)) = printf "parameter %d to %s" i fname
pprintUnitInfo _ (UnitParamEAPUse ((v, _), _)) = printf "explicitly annotated polymorphic unit %s" v
pprintUnitInfo (Just srcText) (UnitLiteral _) = B.unpack srcText
pprintUnitInfo Nothing (UnitLiteral _) = "literal number"
pprintUnitInfo _ ui = show ui

--------------------------------------------------

-- | Constraint 'parametric' equality (structural) treat all uses of a parametric
-- abstractions as equivalent to the abstraction. This structural version
-- compares equality of two constraints, but does not consider the constraints
-- to be composable (by transitivity).
conParamEqStructural :: Constraint -> Constraint -> Bool
conParamEqStructural (ConEq lhs1 rhs1) (ConEq lhs2 rhs2) =
   (unitParamEq lhs1 lhs2 && unitParamEq rhs1 rhs2) ||
   (unitParamEq rhs1 lhs2 && unitParamEq lhs1 rhs2)
conParamEqStructural (ConConj cs1) (ConConj cs2) = and $ zipWith conParamEqStructural cs1 cs2
conParamEqStructural _ _ = False

-- | Constraint 'parametric' equality: treat all uses of a parametric
-- abstractions as equivalent to the abstraction.
conParamEq :: Constraint -> Constraint -> Bool
conParamEq (ConEq lhs1 rhs1) (ConEq lhs2 rhs2) = (unitParamEq lhs1 lhs2 || unitParamEq rhs1 rhs2) ||
                                                 (unitParamEq rhs1 lhs2 || unitParamEq lhs1 rhs2)
conParamEq (ConConj cs1) (ConConj cs2) = and $ zipWith conParamEq cs1 cs2
conParamEq _ _ = False

-- | Unit 'parametric' equality: treat all uses of a parametric
-- abstractions as equivalent to the abstraction.
unitParamEq :: UnitInfo -> UnitInfo -> Bool
unitParamEq (UnitParamLitAbs i)           (UnitParamLitUse (i', _))     = i == i'
unitParamEq (UnitParamLitUse (i', _))     (UnitParamLitAbs i)           = i == i'
unitParamEq (UnitParamVarAbs (f, i))      (UnitParamVarUse (f', i', _)) = (f, i) == (f', i')
unitParamEq (UnitParamVarUse (f', i', _)) (UnitParamVarAbs (f, i))      = (f, i) == (f', i')
unitParamEq (UnitParamPosAbs (f, i))      (UnitParamPosUse (f', i', _)) = (f, i) == (f', i')
unitParamEq (UnitParamPosUse (f', i', _)) (UnitParamPosAbs (f, i))      = (f, i) == (f', i')
unitParamEq (UnitParamEAPAbs v)           (UnitParamEAPUse (v', _))     = v == v'
unitParamEq (UnitParamEAPUse (v', _))     (UnitParamEAPAbs v)           = v == v'
unitParamEq (UnitMul u1 u2)               (UnitMul u1' u2')             = unitParamEq u1 u1' && unitParamEq u2 u2' ||
                                                                          unitParamEq u1 u2' && unitParamEq u2 u1'
unitParamEq (UnitPow u p)                 (UnitPow u' p')               = unitParamEq u u' && p == p'
unitParamEq u1 u2 = u1 == u2

--------------------------------------------------

-- The annotation on the AST used for solving units.
data UnitAnnotation a = UnitAnnotation {
    prevAnnotation :: a,
    unitSpec       :: Maybe P.UnitStatement,
    unitConstraint :: Maybe Constraint,
    unitInfo       :: Maybe UnitInfo,
    unitBlock      :: Maybe (F.Block (FA.Analysis (UnitAnnotation a))), -- ^ linked variable declaration
    unitPU         :: Maybe (F.ProgramUnit (FA.Analysis (UnitAnnotation a))) -- ^ linked program unit
  } deriving (Data, Typeable, Show)

dbgUnitAnnotation (UnitAnnotation _ s c i b p) =
  "{ unitSpec = " ++ show s ++ ", unitConstraint = " ++ show c ++ ", unitInfo = " ++ show i ++ ", unitBlock = " ++
     (case b of
        Nothing -> "Nothing"
        Just (F.BlStatement _ span _ (F.StDeclaration {}))  -> "Just {decl}@" ++ show span
        Just (F.BlStatement _ span _ _) -> "Just {stmt}@" ++ show span
        Just _ -> "Just ...")
   ++ ", unitPU = " ++
     (case p of
        Nothing -> "Nothing"
        Just (F.PUFunction _ span _ _ _ _ _ _ _)  -> "Just {func}@" ++ show span
        Just (F.PUSubroutine _ span _ _ _ _ _) -> "Just {subr}@" ++ show span
        Just _ -> "Just ...")
   ++ "}"

mkUnitAnnotation :: a -> UnitAnnotation a
mkUnitAnnotation a = UnitAnnotation a Nothing Nothing Nothing Nothing Nothing

--------------------------------------------------

-- | Convert parser units to UnitInfo
toUnitInfo   :: P.UnitOfMeasure -> UnitInfo
toUnitInfo (P.UnitProduct u1 u2)       = UnitMul (toUnitInfo u1) (toUnitInfo u2)
toUnitInfo (P.UnitQuotient u1 u2)      = UnitMul (toUnitInfo u1) (UnitPow (toUnitInfo u2) (-1))
toUnitInfo (P.UnitExponentiation u1 p) = UnitPow (toUnitInfo u1) (toDouble p)
  where
    toDouble :: P.UnitPower   -> Double
    toDouble (P.UnitPowerInteger i)    = fromInteger i
    toDouble (P.UnitPowerRational x y) = fromRational (x % y)
toUnitInfo (P.UnitBasic str)           = UnitName str
toUnitInfo (P.Unitless)                = UnitlessLit
toUnitInfo (P.UnitRecord us)           = UnitRecord (map (fmap toUnitInfo) us)

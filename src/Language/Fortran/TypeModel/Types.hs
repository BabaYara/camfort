{-# LANGUAGE DataKinds                  #-}
{-# LANGUAGE DeriveDataTypeable         #-}
{-# LANGUAGE FlexibleInstances          #-}
{-# LANGUAGE GADTs                      #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE KindSignatures             #-}
{-# LANGUAGE LambdaCase                 #-}
{-# LANGUAGE MultiParamTypeClasses      #-}
{-# LANGUAGE PolyKinds                  #-}
{-# LANGUAGE RankNTypes                 #-}
{-# LANGUAGE ScopedTypeVariables        #-}

{-# OPTIONS_GHC -Wall #-}

-- TODO: Complex Numbers

module Language.Fortran.TypeModel.Types where

import           Data.Function                         (on)
import           Data.Int                              (Int16, Int32, Int64,
                                                        Int8)
import           Data.List                             (intersperse)
import           Data.Monoid                           (Endo (..))
import           Data.Typeable                         (Typeable)
import           Data.Word                             (Word8)

import           Data.Singletons.TypeLits

import           Data.SBV                              (Boolean (..), SBool)
import           Data.SBV.Dynamic                      hiding (KReal)

import           Data.Vinyl                            hiding (Field)
import           Data.Vinyl.Functor

import           Language.Expression
import           Language.Expression.Pretty
import           Language.Expression.Prop              (LogicOp (..))

import           Language.Fortran.TypeModel.Singletons

--------------------------------------------------------------------------------
--  Semantic Types
--------------------------------------------------------------------------------

newtype Bool8  = Bool8 { getBool8 :: Int8 } deriving (Show, Num, Eq, Typeable)
newtype Bool16 = Bool16 { getBool16 :: Int16 } deriving (Show, Num, Eq, Typeable)
newtype Bool32 = Bool32 { getBool32 :: Int32 } deriving (Show, Num, Eq, Typeable)
newtype Bool64 = Bool64 { getBool64 :: Int64 } deriving (Show, Num, Eq, Typeable)
newtype Char8  = Char8 { getChar8 :: Word8 } deriving (Show, Num, Eq, Typeable)

--------------------------------------------------------------------------------
--  Primitive Types
--------------------------------------------------------------------------------

newtype PrimS a = PrimS a
  deriving (Show, Eq, Typeable)

-- | Lists the allowed primitive Fortran types, with corresponding (phantom)
-- constraints on precision, kind and semantic Haskell type.
data Prim p k a where
  PInt8          :: Prim 'P8   'KInt     Int8
  PInt16         :: Prim 'P16  'KInt     Int16
  PInt32         :: Prim 'P32  'KInt     Int32
  PInt64         :: Prim 'P64  'KInt     Int64

  PBool8         :: Prim 'P8   'KLogical Bool8
  PBool16        :: Prim 'P16  'KLogical Bool16
  PBool32        :: Prim 'P32  'KLogical Bool32
  PBool64        :: Prim 'P64  'KLogical Bool64

  PFloat         :: Prim 'P32  'KReal    Float
  PDouble        :: Prim 'P64  'KReal    Double

  PChar          :: Prim 'P8   'KChar    Char8

--------------------------------------------------------------------------------
--  Arrays
--------------------------------------------------------------------------------

data Index a where
  Index :: Prim p 'KInt a -> Index (PrimS a)

data ArrValue a where
  ArrValue :: Prim p k a -> ArrValue (PrimS a)

newtype Array i a = Array [a]

--------------------------------------------------------------------------------
--  Records
--------------------------------------------------------------------------------

data Field f field where
  Field :: SSymbol name -> f a -> Field f '(name, a)

overField :: (f a -> f b) -> Field f '(name, a) -> Field f '(name, b)
overField f (Field n x) = Field n (f x)

data Record name fields where
  Record :: SSymbol name -> Rec (Field Identity) fields -> Record name fields

--------------------------------------------------------------------------------
--  Fortran Types
--------------------------------------------------------------------------------

-- TODO: Support arrays of non-primitive values

-- | A Fortran type, with a phantom type variable indicating the Haskell type
-- that it semantically corresponds to.
data D a where
  DPrim :: Prim p k a -> D (PrimS a)
  DArray :: Index i -> ArrValue a -> D (Array i a)
  DData :: SSymbol name -> Rec (Field D) fs -> D (Record name fs)

dIndex :: Index i -> D i
dIndex (Index p) = DPrim p

dArrValue :: ArrValue a -> D a
dArrValue (ArrValue p) = DPrim p

--------------------------------------------------------------------------------
--  SBV Representations
--------------------------------------------------------------------------------

data SymRepr a where
  SRPrim
    :: D (PrimS a)
    -> SVal
    -> SymRepr (PrimS a)

  SRArray
    :: D (Array i a)
    -> SArr
    -> SymRepr (Array i a)

  SRData
    :: D (Record name fs)
    -> Rec (Field SymRepr) fs
    -> SymRepr (Record name fs)

  SRProp
    :: SBool
    -> SymRepr Bool

getReprD :: SymRepr a -> Maybe (D a)
getReprD = \case
  SRPrim d _  -> Just d
  SRArray d _ -> Just d
  SRData d _  -> Just d
  SRProp _    -> Nothing

instance Applicative f => EvalOp f SymRepr LogicOp where
  evalOp f = \case
    LogLit x     -> pure $ SRProp (fromBool x)
    LogNot x     -> SRProp . bnot . getSrProp <$> f x
    LogAnd x y   -> appBinop (&&&) x y
    LogOr x y    -> appBinop (|||) x y
    LogImpl x y  -> appBinop (==>) x y
    LogEquiv x y -> appBinop (<=>) x y

    where
      appBinop g x y = fmap SRProp $ (g `on` getSrProp) <$> f x <*> f y
      getSrProp :: SymRepr Bool -> SBool
      getSrProp (SRProp x) = x

--------------------------------------------------------------------------------
--  Pretty Printing
--------------------------------------------------------------------------------

instance Pretty1 (Prim p k) where
  prettys1Prec p = \case
    PInt8   -> showString "integer8"
    PInt16  -> showString "integer16"
    PInt32  -> showString "integer32"
    PInt64  -> showString "integer64"
    PFloat  -> showString "real"
    PDouble -> showParen (p > 8) $ showString "double precision"
    PBool8  -> showString "logical8"
    PBool16 -> showString "logical16"
    PBool32 -> showString "logical32"
    PBool64 -> showString "logical64"
    PChar   -> showString "character"

instance Pretty1 ArrValue where
  prettys1Prec p = \case
    ArrValue prim -> prettys1Prec p prim

instance (Pretty1 f) => Pretty1 (Field f) where
  prettys1Prec _ = \case
    Field fname x ->
      prettys1Prec 0 x .
      showString " " .
      withKnownSymbol fname (showString (symbolVal fname))

-- | e.g. "type custom_type { character a, integer array b }"
instance Pretty1 D where
  prettys1Prec p = \case
    DPrim px -> prettys1Prec p px
    DArray _ pv -> prettys1Prec p pv . showString " array"
    DData rname fields ->
        showParen (p > 8)
      $ showString "type "
      . withKnownSymbol rname (showString (symbolVal rname))
      . showString "{ "
      . appEndo ( mconcat
              . intersperse (Endo $ showString ", ")
              . recordToList
              . rmap (Const . Endo . prettys1Prec 0)
              $ fields)
      . showString " }"

-- --------------------------------------------------------------------------------
-- --  Dynamic Types
-- --------------------------------------------------------------------------------

-- data DynType
--   = DTInt
--   | DTFloat
--   | DTBool
--   | DTRec String [(String, DynType)]
--   | DTArr DynType DynType

-- dynToD :: DynType -> Maybe (Some D)
-- dynToD = \case
--   DTInt -> Just $ Some $ DPrim PInt64
--   DTFloat -> Just $ Some $ DPrim PFloat
--   DTBool -> Just $ Some $ DPrim PBool8

--   DTRec recName fields -> do
--     SomeSymbol np <- return $ someSymbolVal recName
--     Some fs <- listToRecord dynToField fields

--     return $ Some $ DData (singByProxy np) fs

--   DTArr indexTy valTy -> do
--     Some i <- dynToIndex indexTy
--     Some v <- dynToD valTy
--     Just $ Some $ DArray i v

-- dynToIndex :: DynType -> Maybe (Some Index)
-- dynToIndex = \case
--   DTInt -> Just $ Some $ Index PInt64
--   _ -> Nothing

-- dynToField :: (String, DynType) -> Maybe (Some RField)
-- dynToField (fieldName, fieldTy) = do
--   SomeSymbol np <- return $ someSymbolVal fieldName
--   Some ty <- dynToD fieldTy
--   return $ Some $ (RField (singByProxy np) ty)


-- listToRecord :: Applicative t => (a -> t (Some f)) -> [a] -> t (Some (Rec f))
-- listToRecord f [] = pure (Some RNil)
-- listToRecord (f :: a -> t (Some f)) (x : xs) = cons <$> f x <*> listToRecord f xs
--   where
--     cons :: Some f -> Some (Rec f) -> Some (Rec f)
--     cons y ys = case (y, ys) of (Some z, Some zs) -> Some (z :& zs)
